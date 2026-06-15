// 115 Phase 3.3 — the sender custody-verification sweep: every unconfirmed
// 'inboxed' row is periodically re-stored (custody repaired) or truthfully
// downgraded to 'sent' (custody lost, visibly non-delivered) — a cap/TTL
// loss window is never shown as delivered. All forward transitions ride
// conditionalTransitionStatus (D-6); re-store happens at expiry minus the
// 12h clock-skew margin (D-7).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/verify_inbox_custody_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

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

/// Function-seam fake returning canned [InboxStoreOutcome]s (mirrors the
/// fake_upload_media_fn.dart seam pattern — no P2PService interface change).
class RecordingDetailedStoreFn {
  final List<InboxStoreOutcome> outcomes;
  int callIndex = 0;
  final calls = <({String peerId, String envelope})>[];

  RecordingDetailedStoreFn(this.outcomes);

  Future<InboxStoreOutcome> call(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    calls.add((peerId: toPeerId, envelope: message));
    final outcome =
        outcomes[callIndex < outcomes.length ? callIndex : outcomes.length - 1];
    callIndex++;
    return outcome;
  }
}

// Fixed sweep clock: 2026-06-13T12:00:00Z.
final fixedNow = DateTime.utc(2026, 6, 13, 12);

ConversationMessage makeInboxedRow({
  String id = 'msg-custody-001',
  String contactPeerId = 'peer-target',
  int? relayExpiresAt,
  String? custodyCheckedAt,
  String? timestamp,
  String wireEnvelope =
      '{"type":"chat_message","version":"2","encrypted":{"kem":"k","ciphertext":"{\\"id\\":\\"x\\"}","nonce":"n"}}',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer',
    text: 'pending custody',
    timestamp:
        timestamp ??
        fixedNow.subtract(const Duration(hours: 2)).toIso8601String(),
    status: 'inboxed',
    isIncoming: false,
    createdAt: fixedNow.subtract(const Duration(hours: 2)).toIso8601String(),
    transport: 'inbox',
    wireEnvelope: wireEnvelope,
    relayExpiresAt: relayExpiresAt,
    custodyCheckedAt: custodyCheckedAt,
  );
}

void main() {
  late FakeMessageRepository messageRepo;
  late List<({String id, int? expiresAtMs})> custodyMarks;

  Future<void> markCustodyChecked(
    String messageId, {
    int? relayExpiresAtMs,
  }) async {
    custodyMarks.add((id: messageId, expiresAtMs: relayExpiresAtMs));
  }

  setUp(() {
    messageRepo = FakeMessageRepository();
    custodyMarks = [];
  });

  Future<int> runSweep({
    required List<ConversationMessage> custodyRows,
    required RecordingDetailedStoreFn store,
  }) {
    return verifyInboxCustody(
      loadInboxCustody: ({required Duration recheckOlderThan}) async =>
          custodyRows,
      storeInInboxDetailed: store.call,
      markCustodyChecked: markCustodyChecked,
      messageRepo: messageRepo,
      nowFn: () => fixedNow,
    );
  }

  group('verifyInboxCustody', () {
    test(
      "sweep re-stores rows past relay_expires_at and a 'stored' outcome refreshes expiry (INBOX_CUSTODY_RESTORED)",
      () async {
        final newExpiry = fixedNow
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch;
        final row = makeInboxedRow(
          relayExpiresAt: fixedNow
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        );
        messageRepo.seed([row]);
        final store = RecordingDetailedStoreFn([
          InboxStoreOutcome(
            status: InboxStoreStatus.stored,
            expiresAtMs: newExpiry,
          ),
        ]);

        final events = await captureFlowEvents(() async {
          final restored = await runSweep(custodyRows: [row], store: store);
          expect(restored, 1);
        });

        expect(store.calls, hasLength(1));
        expect(store.calls.single.envelope, row.wireEnvelope);
        expect(custodyMarks.single.id, row.id);
        expect(custodyMarks.single.expiresAtMs, newExpiry);
        expect(
          events.any((e) => e['event'] == 'INBOX_CUSTODY_RESTORED'),
          isTrue,
        );
        // Status untouched: still 'inboxed' awaiting the receipt.
        expect((await messageRepo.getMessage(row.id))!.status, 'inboxed');
      },
    );

    test(
      "a 'duplicate' outcome marks the row custody-checked without status change",
      () async {
        final row = makeInboxedRow(
          relayExpiresAt: fixedNow
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        );
        messageRepo.seed([row]);
        final store = RecordingDetailedStoreFn([
          const InboxStoreOutcome(status: InboxStoreStatus.duplicate),
        ]);

        await runSweep(custodyRows: [row], store: store);

        expect(custodyMarks.single.id, row.id);
        final after = await messageRepo.getMessage(row.id);
        expect(after!.status, 'inboxed');
        expect(after.wireEnvelope, isNotNull);
      },
    );

    test(
      "'inbox_full' downgrades to 'sent' keeping the envelope (INBOX_CUSTODY_LOST)",
      () async {
        final row = makeInboxedRow(
          relayExpiresAt: fixedNow
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        );
        messageRepo.seed([row]);
        final store = RecordingDetailedStoreFn([
          const InboxStoreOutcome(
            status: InboxStoreStatus.rejectedFull,
            errorCode: 'INBOX_FULL',
          ),
        ]);

        final events = await captureFlowEvents(() async {
          await runSweep(custodyRows: [row], store: store);
        });

        final after = await messageRepo.getMessage(row.id);
        expect(after!.status, 'sent', reason: 'custody lost must be SURFACED');
        expect(
          after.wireEnvelope,
          isNotNull,
          reason: 'retryUnackedMessages owns the row now — envelope required',
        );
        expect(events.any((e) => e['event'] == 'INBOX_CUSTODY_LOST'), isTrue);
      },
    );

    test(
      'rows with null relay_expires_at (old-relay stores) are re-stored every sweep',
      () async {
        final row = makeInboxedRow(relayExpiresAt: null);
        messageRepo.seed([row]);
        final store = RecordingDetailedStoreFn([
          const InboxStoreOutcome(status: InboxStoreStatus.stored),
        ]);

        await runSweep(custodyRows: [row], store: store);

        expect(
          store.calls,
          hasLength(1),
          reason: 'an old relay gave no expiry — custody must be re-proven',
        );
      },
    );

    test(
      "rows older than 7 days without receipt surface non-delivered even on 'duplicate' (old-relay zombie-dedup defense)",
      () async {
        final row = makeInboxedRow(
          id: 'msg-zombie-001',
          timestamp: fixedNow
              .subtract(const Duration(days: 8))
              .toIso8601String(),
          relayExpiresAt: fixedNow
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        );
        messageRepo.seed([row]);
        // Old memory backend never rebuilds dedup ids on TTL prune: the entry
        // is GONE but the relay still answers 'duplicate' forever.
        final store = RecordingDetailedStoreFn([
          const InboxStoreOutcome(status: InboxStoreStatus.duplicate),
        ]);

        await runSweep(custodyRows: [row], store: store);

        final after = await messageRepo.getMessage(row.id);
        expect(
          after!.status,
          'sent',
          reason:
              "a >7d zombie-'duplicate' must NOT be trusted as live custody",
        );
        expect(after.wireEnvelope, isNotNull);
      },
    );

    test(
      'sweep re-stores at relay_expires_at minus the 12h skew margin, pinned with skewed expiresAtMs fixtures',
      () async {
        // Inside the margin window: expiry 6h ahead of device clock — a
        // relay-ahead skew could mean it is ALREADY expired there. Re-store.
        final insideMargin = makeInboxedRow(
          id: 'msg-skew-inside',
          relayExpiresAt: fixedNow
              .add(const Duration(hours: 6))
              .millisecondsSinceEpoch,
        );
        // Freshly stamped: expiry 7 days out — far outside the margin.
        final fresh = makeInboxedRow(
          id: 'msg-skew-fresh',
          relayExpiresAt: fixedNow
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
        );
        messageRepo.seed([insideMargin, fresh]);
        final store = RecordingDetailedStoreFn([
          const InboxStoreOutcome(status: InboxStoreStatus.stored),
        ]);

        await runSweep(custodyRows: [insideMargin, fresh], store: store);

        expect(store.calls, hasLength(1));
        expect(store.calls.single.envelope, insideMargin.wireEnvelope);
        // The 12h constant is the pinned decision (D-7).
        expect(
          kRelayCustodySkewMarginMs,
          const Duration(hours: 12).inMilliseconds,
        );
      },
    );

    test(
      'late sweep/retry persist does not downgrade a delivered row',
      () async {
        // The stored row already settled 'delivered' (a receipt landed); the
        // sweep still holds the STALE 'inboxed' snapshot from its load.
        final staleSnapshot = makeInboxedRow(
          id: 'msg-race-001',
          relayExpiresAt: fixedNow
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        );
        messageRepo.seed([staleSnapshot.copyWith(status: 'delivered')]);
        final store = RecordingDetailedStoreFn([
          const InboxStoreOutcome(
            status: InboxStoreStatus.rejectedFull,
            errorCode: 'INBOX_FULL',
          ),
        ]);

        await runSweep(custodyRows: [staleSnapshot], store: store);

        expect(
          (await messageRepo.getMessage('msg-race-001'))!.status,
          'delivered',
          reason:
              'D-6: the downgrade rides conditionalTransitionStatus(from: '
              "'inboxed'), matches 0 rows, and the receipt outcome survives",
        );
      },
    );

    test(
      'sweep re-stores a stale-unreceipted row before expiry (bounded false-pending latency)',
      () async {
        final row = makeInboxedRow(
          id: 'msg-stale-receipt',
          relayExpiresAt: fixedNow
              .add(const Duration(days: 5))
              .millisecondsSinceEpoch,
          custodyCheckedAt: fixedNow
              .subtract(kCustodyStaleReceiptRestoreAfter)
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        );
        messageRepo.seed([row]);
        final store = RecordingDetailedStoreFn([
          const InboxStoreOutcome(status: InboxStoreStatus.stored),
        ]);

        await runSweep(custodyRows: [row], store: store);

        expect(store.calls, hasLength(1));
        expect(store.calls.single.envelope, row.wireEnvelope);
      },
    );

    // 115 P3.6 PIN (green-on-arrival, floor = 116 P1-2): the sweep re-stores
    // the row's stored envelope BYTES — an edit row's re-store carries
    // action:edit. Fails loudly if anyone ever rebuilds envelopes inside the
    // sweep instead of re-storing the stored bytes.
    test(
      "a custody-sweep re-store of an edit row carries action:edit",
      () async {
        final editEnvelope = jsonEncode({
          'type': 'chat_message',
          'version': '2',
          'id': 'msg-edit-custody',
          'senderPeerId': 'my-peer',
          'encrypted': {
            'kem': 'k',
            'ciphertext': jsonEncode({
              'id': 'msg-edit-custody',
              'action': 'edit',
              'editedAt': '2026-06-13T10:00:00.000Z',
            }),
            'nonce': 'n',
          },
        });
        final row = makeInboxedRow(
          id: 'msg-edit-custody',
          relayExpiresAt: fixedNow
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          wireEnvelope: editEnvelope,
        );
        messageRepo.seed([row]);
        final store = RecordingDetailedStoreFn([
          const InboxStoreOutcome(status: InboxStoreStatus.stored),
        ]);

        await runSweep(custodyRows: [row], store: store);

        final sent =
            jsonDecode(store.calls.single.envelope) as Map<String, dynamic>;
        final inner =
            jsonDecode(
                  (sent['encrypted'] as Map<String, dynamic>)['ciphertext']
                      as String,
                )
                as Map<String, dynamic>;
        expect(inner['action'], 'edit');
      },
    );
  });
}
