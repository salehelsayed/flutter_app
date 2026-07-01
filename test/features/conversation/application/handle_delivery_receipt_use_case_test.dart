// 115 Phase 2.2 — receipt apply: 'inboxed' → 'delivered' flips ONLY here
// (G4 allowed minting site (a)). All forward transitions ride
// conditionalTransitionStatus (D-6) so a late receipt can never downgrade
// and a racing sweep can never resurrect.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../domain/repositories/fake_message_repository.dart';

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

ChatMessage buildReceipt({
  String from = 'peer-x',
  required List<String> messageIds,
}) {
  return ChatMessage(
    from: from,
    to: 'my-peer',
    content: jsonEncode({
      'type': 'delivery_receipt',
      'version': '1',
      'payload': {
        'messageIds': messageIds,
        'ts': '2026-06-13T12:00:00.000Z',
      },
    }),
    timestamp: '2026-06-13T12:00:00.000Z',
    isIncoming: true,
  );
}

ConversationMessage makeInboxedOutgoing({
  String id = 'msg-rcpt-001',
  String contactPeerId = 'peer-x',
  bool isIncoming = false,
  String status = 'inboxed',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer',
    text: 'pending custody',
    timestamp: '2026-06-13T11:00:00.000Z',
    status: status,
    isIncoming: isIncoming,
    createdAt: '2026-06-13T11:00:00.000Z',
    transport: 'inbox',
    wireEnvelope: '{"type":"chat_message","version":"2","encrypted":{}}',
  );
}

void main() {
  late FakeMessageRepository messageRepo;

  setUp(() {
    messageRepo = FakeMessageRepository();
  });

  group('handleDeliveryReceipt', () {
    test(
      "flips matching outgoing 'inboxed' rows to 'delivered' and clears wire_envelope",
      () async {
        messageRepo.seed([makeInboxedOutgoing()]);

        final events = await captureFlowEvents(() async {
          await handleDeliveryReceipt(
            message: buildReceipt(messageIds: ['msg-rcpt-001']),
            messageRepo: messageRepo,
          );
        });

        final row = await messageRepo.getMessage('msg-rcpt-001');
        expect(row!.status, 'delivered');
        expect(row.wireEnvelope, isNull);
        // D-6: the flip must ride the conditional transition, never a blind
        // INSERT OR REPLACE persist.
        expect(messageRepo.conditionalTransitionCallCount, greaterThan(0));
        expect(
          events.any((e) => e['event'] == 'DELIVERY_RECEIPT_APPLIED'),
          isTrue,
        );
      },
    );

    test('ignores receipts for foreign-peer, incoming, or unknown message ids', () async {
      messageRepo.seed([
        // Outgoing 'inboxed' row that belongs to peer Y, not the receipt
        // sender X.
        makeInboxedOutgoing(id: 'msg-foreign-001', contactPeerId: 'peer-y'),
        // Incoming row with a matching id.
        makeInboxedOutgoing(id: 'msg-incoming-001', isIncoming: true),
      ]);

      await handleDeliveryReceipt(
        message: buildReceipt(
          from: 'peer-x',
          messageIds: ['msg-foreign-001', 'msg-incoming-001', 'msg-unknown'],
        ),
        messageRepo: messageRepo,
      );

      expect(
        (await messageRepo.getMessage('msg-foreign-001'))!.status,
        'inboxed',
      );
      expect(
        (await messageRepo.getMessage('msg-foreign-001'))!.wireEnvelope,
        isNotNull,
      );
      expect(
        (await messageRepo.getMessage('msg-incoming-001'))!.status,
        'inboxed',
      );
    });

    test("re-applying a receipt to an already-delivered row is a no-op", () async {
      messageRepo.seed([makeInboxedOutgoing()]);

      await handleDeliveryReceipt(
        message: buildReceipt(messageIds: ['msg-rcpt-001']),
        messageRepo: messageRepo,
      );
      final savesAfterFirst = messageRepo.saveMessageCallCount;

      await handleDeliveryReceipt(
        message: buildReceipt(messageIds: ['msg-rcpt-001']),
        messageRepo: messageRepo,
      );

      final row = await messageRepo.getMessage('msg-rcpt-001');
      expect(row!.status, 'delivered');
      expect(
        messageRepo.saveMessageCallCount,
        savesAfterFirst,
        reason: 'idempotent re-apply must not persist again',
      );
    });

    test('unmatched or foreign receipt emits telemetry', () async {
      messageRepo.seed([
        makeInboxedOutgoing(id: 'msg-foreign-002', contactPeerId: 'peer-y'),
      ]);

      final events = await captureFlowEvents(() async {
        await handleDeliveryReceipt(
          message: buildReceipt(
            from: 'peer-x',
            messageIds: ['msg-never-seen', 'msg-foreign-002'],
          ),
          messageRepo: messageRepo,
        );
      });

      final unmatched = events.singleWhere(
        (e) => e['event'] == 'DELIVERY_RECEIPT_UNMATCHED',
      );
      expect(unmatched['details']['from'], isNotNull);
      expect(unmatched['details']['id'], isNotNull);
      expect(
        events.any((e) => e['event'] == 'DELIVERY_RECEIPT_FOREIGN_PEER'),
        isTrue,
      );
    });

    // -----------------------------------------------------------------------
    // 185 — defensive receipt arm: a row that reached terminal 'failed' during
    // a sender-offline send (whose envelope still reached the receiver) is
    // lifted to 'delivered' by the peer-authenticated receipt. Belt-and-
    // suspenders for the relayReady TTL-lag window where a just-went-offline
    // send is still stamped 'failed'.
    // -----------------------------------------------------------------------

    test(
      "TC-185-10 a valid peer-authenticated receipt lifts a 'failed' row to 'delivered'",
      () async {
        messageRepo.seed([makeInboxedOutgoing(status: 'failed')]);

        final events = await captureFlowEvents(() async {
          await handleDeliveryReceipt(
            message: buildReceipt(messageIds: ['msg-rcpt-001']),
            messageRepo: messageRepo,
          );
        });

        final row = await messageRepo.getMessage('msg-rcpt-001');
        expect(row!.status, 'delivered');
        expect(row.wireEnvelope, isNull);
        // Distinct-event discriminator: APPLIED fired and NO_TRANSITION did NOT
        // (the latter is HEAD's behaviour before the failed→delivered arm).
        expect(
          events.any((e) => e['event'] == 'DELIVERY_RECEIPT_APPLIED'),
          isTrue,
          reason: 'the failed row must be lifted, emitting APPLIED',
        );
        expect(
          events.any((e) => e['event'] == 'DELIVERY_RECEIPT_NO_TRANSITION'),
          isFalse,
          reason:
              'HEAD lacks a failed→delivered arm and emits NO_TRANSITION; the '
              'fix must transition instead',
        );
      },
    );

    test(
      "TC-185-11 a foreign-peer receipt does NOT lift a 'failed' row",
      () async {
        messageRepo.seed([
          makeInboxedOutgoing(
            id: 'msg-failed-foreign',
            contactPeerId: 'peer-y',
            status: 'failed',
          ),
        ]);

        final events = await captureFlowEvents(() async {
          await handleDeliveryReceipt(
            // Receipt is from peer-x, but the row belongs to peer-y.
            message: buildReceipt(from: 'peer-x', messageIds: ['msg-failed-foreign']),
            messageRepo: messageRepo,
          );
        });

        final row = await messageRepo.getMessage('msg-failed-foreign');
        expect(row!.status, 'failed', reason: 'receiver-auth guard (:55) holds');
        expect(row.wireEnvelope, isNotNull);
        expect(
          events.any((e) => e['event'] == 'DELIVERY_RECEIPT_FOREIGN_PEER'),
          isTrue,
        );
      },
    );

    test(
      "TC-185-12 a 'failed' row with NO matching receipt stays 'failed'",
      () async {
        messageRepo.seed([makeInboxedOutgoing(status: 'failed')]);

        await handleDeliveryReceipt(
          // Receipt is for a different id — the failed row is never confirmed.
          message: buildReceipt(messageIds: ['some-other-id']),
          messageRepo: messageRepo,
        );

        final row = await messageRepo.getMessage('msg-rcpt-001');
        expect(
          row!.status,
          'failed',
          reason: 'only a receiver confirmation for THIS id may lift a failed row',
        );
      },
    );

    test(
      'TC-185-31 an unconfirmed row is never auto-delivered without its own receipt',
      () async {
        messageRepo.seed([
          makeInboxedOutgoing(id: 'msg-sent-unconf', status: 'sent'),
          makeInboxedOutgoing(id: 'msg-failed-unconf', status: 'failed'),
        ]);

        await handleDeliveryReceipt(
          // A receipt for an entirely unrelated id must not touch either row.
          message: buildReceipt(messageIds: ['unrelated-id']),
          messageRepo: messageRepo,
        );

        expect((await messageRepo.getMessage('msg-sent-unconf'))!.status, 'sent');
        expect(
          (await messageRepo.getMessage('msg-failed-unconf'))!.status,
          'failed',
        );
      },
    );

    test(
      'TC-185-32 the failed→delivered flip rides conditionalTransitionStatus '
      'and a stale duplicate receipt cannot downgrade or double-apply',
      () async {
        messageRepo.seed([makeInboxedOutgoing(status: 'failed')]);

        await handleDeliveryReceipt(
          message: buildReceipt(messageIds: ['msg-rcpt-001']),
          messageRepo: messageRepo,
        );
        expect(
          messageRepo.conditionalTransitionCallCount,
          greaterThan(0),
          reason: 'D-6: the flip must be a CAS transition, not a blind save',
        );
        expect((await messageRepo.getMessage('msg-rcpt-001'))!.status, 'delivered');
        final savesAfterFirst = messageRepo.saveMessageCallCount;

        // A late/duplicate receipt for the already-delivered row is a no-op.
        await handleDeliveryReceipt(
          message: buildReceipt(messageIds: ['msg-rcpt-001']),
          messageRepo: messageRepo,
        );

        final row = await messageRepo.getMessage('msg-rcpt-001');
        expect(row!.status, 'delivered', reason: 'no downgrade on re-apply');
        expect(
          messageRepo.saveMessageCallCount,
          savesAfterFirst,
          reason: 'idempotent re-apply must not persist again',
        );
      },
    );

    // Doc placement note: 115 P2.5's second test ('sender tombstone flips
    // inboxed → delivered on deletion receipt and becomes hidden') lives here
    // because it exercises handleDeliveryReceipt + the tombstone visibility
    // normalizer end-to-end on the SENDER side.
    test(
      "sender tombstone flips 'inboxed' → 'delivered' on deletion receipt and becomes hidden",
      () async {
        final tombstone = makeInboxedOutgoing(id: 'msg-tomb-001').copyWith(
          text: '',
          deletedAt: '2026-06-13T11:30:00.000Z',
          deletedByPeerId: 'my-peer',
          wireEnvelope:
              '{"type":"message_deletion","version":"2","encrypted":{}}',
        );
        expect(tombstone.isHidden, isFalse);
        messageRepo.seed([tombstone]);

        await handleDeliveryReceipt(
          message: buildReceipt(messageIds: ['msg-tomb-001']),
          messageRepo: messageRepo,
        );

        final row = await messageRepo.getMessage('msg-tomb-001');
        expect(row!.status, 'delivered');
        expect(row.wireEnvelope, isNull);
        expect(
          row.isHidden,
          isTrue,
          reason:
              'the delivered tombstone hides via '
              'normalizeOutgoingDeleteTombstoneVisibility (D-3)',
        );
      },
    );
  });
}
