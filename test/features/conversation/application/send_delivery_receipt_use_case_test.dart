// 115 Phase 2.3 — receipt send: plaintext v1 envelope (D-4, the one type old
// routers provably drop by name), live send first, inbox fallback second,
// per-drain messageId coalescing, and NO retry loop on failure (D-5 — the
// custody sweep + duplicate-receive path own the repair loop).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../../../core/services/fake_p2p_service.dart';

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

void main() {
  group('sendDeliveryReceipt', () {
    test(
      "builds plaintext v1 'delivery_receipt' envelope carrying messageIds and falls back to storeInInbox when live send is unacked",
      () async {
        // Acked live send: envelope goes out live, NO inbox store.
        final livePeer = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'receiver'),
          sendMessageWithReplyResult: const SendMessageResult(
            sent: true,
            acked: true,
            reply: 'ack',
          ),
        );

        final events = await captureFlowEvents(() async {
          final ok = await sendDeliveryReceipt(
            p2pService: livePeer,
            targetPeerId: 'peer-sender',
            messageIds: const ['msg-1', 'msg-2'],
          );
          expect(ok, isTrue);
        });

        expect(livePeer.storeInInboxCallCount, 0);
        final envelope =
            jsonDecode(livePeer.lastSendMessageContent!)
                as Map<String, dynamic>;
        expect(envelope['type'], 'delivery_receipt');
        expect(envelope['version'], '1');
        final payload = envelope['payload'] as Map<String, dynamic>;
        // D-5: messageIds coalesced — one envelope per peer per drain batch.
        expect(payload['messageIds'], ['msg-1', 'msg-2']);
        expect(payload['ts'], isNotNull);
        expect(
          events.any((e) => e['event'] == 'DELIVERY_RECEIPT_SENT'),
          isTrue,
        );

        // Unacked live send: the SAME envelope falls back to storeInInbox.
        final unackedPeer = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'receiver'),
          sendMessageWithReplyResult: const SendMessageResult(
            sent: false,
          ),
          storeInInboxResult: true,
        );

        final ok = await sendDeliveryReceipt(
          p2pService: unackedPeer,
          targetPeerId: 'peer-sender',
          messageIds: const ['msg-3'],
        );
        expect(ok, isTrue);
        expect(unackedPeer.storeInInboxCallCount, 1);
        final stored =
            jsonDecode(unackedPeer.lastStoreInInboxMessage!)
                as Map<String, dynamic>;
        expect(stored['type'], 'delivery_receipt');
        expect(
          (stored['payload'] as Map<String, dynamic>)['messageIds'],
          ['msg-3'],
        );
      },
    );

    test(
      'failed receipt store emits DELIVERY_RECEIPT_STORE_FAILED and does not throw or retry-loop',
      () async {
        final failingPeer = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'receiver'),
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
          storeInInboxResult: false,
        );

        final events = await captureFlowEvents(() async {
          final ok = await sendDeliveryReceipt(
            p2pService: failingPeer,
            targetPeerId: 'peer-sender',
            messageIds: const ['msg-4'],
          );
          expect(ok, isFalse);
        });

        // Graceful single attempt — repair is owned by the custody sweep and
        // the duplicate-receive → receipt re-send path (D-5).
        expect(failingPeer.storeInInboxCallCount, 1);
        expect(failingPeer.sendMessageWithReplyCallCount, 1);
        expect(
          events.any((e) => e['event'] == 'DELIVERY_RECEIPT_STORE_FAILED'),
          isTrue,
        );
      },
    );
  });

  group('deliveryReceiptMintDecision (132)', () {
    test('OFF mode (flag=false): mints only for relay-inbox, names skip reasons', () {
      // Relay-inbox arrivals mint regardless of the flag.
      expect(
        deliveryReceiptMintDecision(
          transport: 'inbox',
          confirmatoryDirectLanEnabled: false,
        ).shouldMint,
        isTrue,
      );
      expect(
        deliveryReceiptMintDecision(
          stagedEntryId: 'relay-1',
          transport: 'inbox',
          confirmatoryDirectLanEnabled: false,
        ).shouldMint,
        isTrue,
      );
      // Direct/LAN staged replays skip in OFF mode — with a named reason.
      final direct = deliveryReceiptMintDecision(
        stagedEntryId: 'direct:n1',
        transport: 'direct',
        confirmatoryDirectLanEnabled: false,
      );
      expect(direct.shouldMint, isFalse);
      expect(direct.skipReason, DeliveryReceiptMintSkipReason.direct);
      final lan = deliveryReceiptMintDecision(
        stagedEntryId: 'lan:n1',
        transport: 'wifi',
        confirmatoryDirectLanEnabled: false,
      );
      expect(lan.shouldMint, isFalse);
      expect(lan.skipReason, DeliveryReceiptMintSkipReason.lan);
      // No staged id + non-inbox transport skips as nonInbox.
      expect(
        deliveryReceiptMintDecision(
          transport: 'direct',
          confirmatoryDirectLanEnabled: false,
        ).skipReason,
        DeliveryReceiptMintSkipReason.nonInbox,
      );
      expect(
        deliveryReceiptMintDecision(
          confirmatoryDirectLanEnabled: false,
        ).skipReason,
        DeliveryReceiptMintSkipReason.nonInbox,
      );
    });

    test(
      'INV-132-0 parity: shouldMintDeliveryReceipt == decision.shouldMint (at the live default)',
      () {
        for (final staged in <String?>[null, 'direct:n', 'lan:n', 'relay-1']) {
          for (final t in <String?>[null, 'inbox', 'direct', 'wifi']) {
            expect(
              shouldMintDeliveryReceipt(stagedEntryId: staged, transport: t),
              deliveryReceiptMintDecision(
                stagedEntryId: staged,
                transport: t,
              ).shouldMint,
              reason: 'staged=$staged transport=$t',
            );
          }
        }
      },
    );

    test(
      'Phase 1 (flag on): broadens minting to direct/LAN/non-inbox arrivals',
      () {
        bool mint(String? staged, String? t) => deliveryReceiptMintDecision(
          stagedEntryId: staged,
          transport: t,
          confirmatoryDirectLanEnabled: true,
        ).shouldMint;
        expect(mint('direct:n1', 'direct'), isTrue);
        expect(mint('lan:n1', 'wifi'), isTrue);
        expect(mint(null, 'direct'), isTrue);
        expect(mint(null, null), isTrue);
        // Relay-inbox still mints (unchanged).
        expect(mint(null, 'inbox'), isTrue);
        expect(mint('relay-1', 'inbox'), isTrue);
      },
    );

    test('Phase 1 is LIVE by default (device-verified 2026-06-19)', () {
      expect(kConfirmatoryDirectLanReceiptEnabled, isTrue);
    });
  });
}
