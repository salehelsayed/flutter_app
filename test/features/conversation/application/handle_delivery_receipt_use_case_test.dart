// 115 Phase 2.2 — receipt apply: 'inboxed' → 'delivered' flips ONLY here
// (G4 allowed minting site (a)). All forward transitions ride
// one typed receipt settlement so a late receipt can never downgrade and a
// racing sweep can never resurrect.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';

class _ReceiptMutationSpy extends FakeMessageRepository {
  int getMessageCallCount = 0;

  final List<
    ({
      String messageId,
      String expectedContactPeerId,
      String? expectedEnvelope,
      String status,
      String? transport,
      int? relayExpiresAt,
      OutgoingOrdinarySettlementMode mode,
    })
  >
  normalCalls = [];
  final List<
    ({
      String messageId,
      String expectedContactPeerId,
      String? expectedEnvelope,
      String status,
      String? transport,
      int? relayExpiresAt,
      OutgoingOrdinarySettlementMode mode,
    })
  >
  tombstoneCalls = [];

  @override
  Future<ConversationMessage?> getMessage(String id) {
    getMessageCallCount++;
    return super.getMessage(id);
  }

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryTransport({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) {
    normalCalls.add((
      messageId: messageId,
      expectedContactPeerId: expectedContactPeerId,
      expectedEnvelope: expectedEnvelope,
      status: status,
      transport: transport,
      relayExpiresAt: relayExpiresAt,
      mode: mode,
    ));
    return super.settleOutgoingOrdinaryTransport(
      messageId: messageId,
      expectedContactPeerId: expectedContactPeerId,
      expectedEnvelope: expectedEnvelope,
      status: status,
      transport: transport,
      relayExpiresAt: relayExpiresAt,
      mode: mode,
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryDeleteTombstone({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) {
    tombstoneCalls.add((
      messageId: messageId,
      expectedContactPeerId: expectedContactPeerId,
      expectedEnvelope: expectedEnvelope,
      status: status,
      transport: transport,
      relayExpiresAt: relayExpiresAt,
      mode: mode,
    ));
    return super.settleOutgoingOrdinaryDeleteTombstone(
      messageId: messageId,
      expectedContactPeerId: expectedContactPeerId,
      expectedEnvelope: expectedEnvelope,
      status: status,
      transport: transport,
      relayExpiresAt: relayExpiresAt,
      mode: mode,
    );
  }
}

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
  String? transport = 'direct',
}) {
  return ChatMessage(
    from: from,
    to: 'my-peer',
    content: jsonEncode({
      'type': 'delivery_receipt',
      'version': '1',
      'payload': {'messageIds': messageIds, 'ts': '2026-06-13T12:00:00.000Z'},
    }),
    timestamp: '2026-06-13T12:00:00.000Z',
    isIncoming: true,
    transport: transport,
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
      'R2 receipt provenance accepts direct relay inbox and rejects wifi null unknown',
      () async {
        for (final transport in const <String>['direct', 'relay', 'inbox']) {
          final repo = _ReceiptMutationSpy();
          final messageId = 'trusted-$transport';
          repo.seed(<ConversationMessage>[makeInboxedOutgoing(id: messageId)]);

          final liveReceipt = buildReceipt(
            messageIds: <String>[messageId],
            transport: transport,
          );
          final receipt = transport == 'inbox'
              ? InboxStagingEntry(
                  entryId: 'receipt-entry',
                  ownerPeerId: 'my-peer',
                  senderPeerId: 'peer-x',
                  messageType: 'delivery_receipt',
                  relayTimestamp: liveReceipt.timestamp,
                  envelope: liveReceipt.content,
                  stagedAt: '2026-06-13T12:00:01.000Z',
                ).toChatMessage()
              : liveReceipt;

          await handleDeliveryReceipt(message: receipt, messageRepo: repo);

          expect(repo.getMessageCallCount, 1, reason: transport);
          expect(repo.normalCalls, hasLength(1), reason: transport);
          expect(repo.normalCalls.single.messageId, messageId);
          expect(
            repo.normalCalls.single.mode,
            OutgoingOrdinarySettlementMode.receipt,
          );
          final settled = await repo.getMessage(messageId);
          expect(settled!.status, 'delivered', reason: transport);
          expect(settled.wireEnvelope, isNull, reason: transport);
        }

        for (final transport in <String?>['wifi', null, 'unknown']) {
          final repo = _ReceiptMutationSpy();
          final mediaRepo = FakeMediaAttachmentRepository();
          final ordinary = makeInboxedOutgoing(id: 'untrusted-ordinary');
          final protected = makeInboxedOutgoing(id: 'untrusted-protected')
              .copyWith(
                privateMediaPolicy: const PrivateMediaPolicy.protected(),
                privateMediaState: PrivateMediaLifecycleState.available,
              );
          final viewOnce = makeInboxedOutgoing(id: 'untrusted-view-once')
              .copyWith(
                privateMediaPolicy: const PrivateMediaPolicy.viewOnce(),
                privateMediaState: PrivateMediaLifecycleState.available,
              );
          final tombstone = makeInboxedOutgoing(id: 'untrusted-tombstone')
              .copyWith(
                text: '',
                deletedAt: '2026-06-13T11:30:00.000Z',
                deletedByPeerId: 'my-peer',
                wireEnvelope: 'delete-envelope',
              );
          final originalRows = <ConversationMessage>[
            ordinary,
            protected,
            viewOnce,
            tombstone,
          ];
          repo.seed(originalRows);

          await handleDeliveryReceipt(
            message: buildReceipt(
              messageIds: originalRows
                  .map((message) => message.id)
                  .toList(growable: false),
              transport: transport,
            ),
            messageRepo: repo,
            mediaAttachmentRepo: mediaRepo,
          );

          expect(repo.getMessageCallCount, 0, reason: 'transport=$transport');
          expect(repo.normalCalls, isEmpty, reason: 'transport=$transport');
          expect(repo.tombstoneCalls, isEmpty, reason: 'transport=$transport');
          expect(
            repo.ordinaryMutationCallCount,
            0,
            reason: 'transport=$transport',
          );
          expect(
            mediaRepo.getAttachmentsForMessageCallCount,
            0,
            reason: 'transport=$transport',
          );
          expect(repo.saveMessageCallCount, 0, reason: 'transport=$transport');
          for (final original in originalRows) {
            final preserved = await repo.getMessage(original.id);
            expect(preserved!.status, original.status, reason: original.id);
            expect(
              preserved.wireEnvelope,
              original.wireEnvelope,
              reason: original.id,
            );
            expect(preserved.hiddenAt, original.hiddenAt, reason: original.id);
          }
        }

        final malformedRepo = _ReceiptMutationSpy();
        final malformedEvents = await captureFlowEvents(() async {
          await handleDeliveryReceipt(
            message: const ChatMessage(
              from: 'peer-x',
              to: 'my-peer',
              content: 'not-json',
              timestamp: '2026-06-13T12:00:00.000Z',
              isIncoming: true,
              transport: 'wifi',
            ),
            messageRepo: malformedRepo,
          );
        });
        expect(malformedRepo.getMessageCallCount, 0);
        expect(
          malformedEvents.any(
            (event) => event['event'] == 'DELIVERY_RECEIPT_PARSE_ERROR',
          ),
          isFalse,
          reason: 'untrusted provenance must return before parsing content',
        );
      },
    );

    test(
      'peer-bound ordinary receipt uses one atomic settlement without widening authority',
      () async {
        final repo = _ReceiptMutationSpy();
        final tombstone = makeInboxedOutgoing(id: 'receipt-tombstone').copyWith(
          text: '',
          deletedAt: '2026-06-13T11:30:00.000Z',
          deletedByPeerId: 'my-peer',
          wireEnvelope: 'delete-envelope',
        );
        repo.seed(<ConversationMessage>[
          makeInboxedOutgoing(id: 'receipt-inboxed'),
          makeInboxedOutgoing(
            id: 'receipt-legacy-null-envelope',
            status: 'sent',
          ).copyWith(wireEnvelope: null),
          makeInboxedOutgoing(id: 'receipt-failed', status: 'failed'),
          makeInboxedOutgoing(id: 'receipt-sending', status: 'sending'),
          makeInboxedOutgoing(id: 'receipt-foreign', contactPeerId: 'peer-y'),
          tombstone,
        ]);

        await handleDeliveryReceipt(
          message: buildReceipt(
            messageIds: const <String>[
              'receipt-inboxed',
              'receipt-legacy-null-envelope',
              'receipt-failed',
              'receipt-sending',
              'receipt-foreign',
              'receipt-tombstone',
            ],
          ),
          messageRepo: repo,
        );

        expect(repo.normalCalls.map((call) => call.messageId), <String>[
          'receipt-inboxed',
          'receipt-legacy-null-envelope',
          'receipt-failed',
          'receipt-sending',
        ]);
        expect(repo.tombstoneCalls.map((call) => call.messageId), <String>[
          'receipt-tombstone',
        ]);
        expect(
          repo.normalCalls.every(
            (call) =>
                call.expectedContactPeerId == 'peer-x' &&
                call.status == 'delivered' &&
                call.mode == OutgoingOrdinarySettlementMode.receipt,
          ),
          isTrue,
        );
        expect(
          repo.normalCalls
              .singleWhere(
                (call) => call.messageId == 'receipt-legacy-null-envelope',
              )
              .expectedEnvelope,
          isNull,
        );
        expect(
          repo.tombstoneCalls.single.mode,
          OutgoingOrdinarySettlementMode.receipt,
        );
        expect(repo.saveMessageCallCount, 0);
        expect(repo.conditionalTransitionCallCount, 0);
        expect(repo.wireEnvelopeUpdates, isEmpty);

        for (final id in const <String>[
          'receipt-inboxed',
          'receipt-legacy-null-envelope',
          'receipt-failed',
        ]) {
          final settled = await repo.getMessage(id);
          expect(settled!.status, 'delivered', reason: id);
          expect(settled.wireEnvelope, isNull, reason: id);
        }
        expect((await repo.getMessage('receipt-sending'))!.status, 'sending');
        expect((await repo.getMessage('receipt-foreign'))!.status, 'inboxed');
        final settledTombstone = await repo.getMessage('receipt-tombstone');
        expect(settledTombstone!.status, 'delivered');
        expect(settledTombstone.wireEnvelope, isNull);
        expect(settledTombstone.hiddenAt, settledTombstone.deletedAt);

        final typedCallsAfterFirst =
            repo.normalCalls.length + repo.tombstoneCalls.length;
        await handleDeliveryReceipt(
          message: buildReceipt(
            messageIds: const <String>['receipt-inboxed', 'receipt-tombstone'],
          ),
          messageRepo: repo,
        );
        expect(
          repo.normalCalls.length + repo.tombstoneCalls.length,
          typedCallsAfterFirst,
          reason: 'duplicate delivered receipts are field-freezing no-ops',
        );
      },
    );

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
        expect(messageRepo.ordinaryMutationCallCount, 1);
        expect(messageRepo.conditionalTransitionCallCount, 0);
        expect(messageRepo.saveMessageCallCount, 0);
        expect(
          events.any((e) => e['event'] == 'DELIVERY_RECEIPT_APPLIED'),
          isTrue,
        );
      },
    );

    test(
      'ignores receipts for foreign-peer, incoming, or unknown message ids',
      () async {
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
      },
    );

    test(
      "re-applying a receipt to an already-delivered row is a no-op",
      () async {
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
      },
    );

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
    // lifted to 'delivered' by an authenticated-ingress, peer-bound receipt.
    // Belt-and-suspenders for the relayReady TTL-lag window where a just-went-
    // offline send is still stamped 'failed'.
    // -----------------------------------------------------------------------

    test(
      "TC-185-10 a valid peer-bound receipt lifts a 'failed' row to 'delivered'",
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
            message: buildReceipt(
              from: 'peer-x',
              messageIds: ['msg-failed-foreign'],
            ),
            messageRepo: messageRepo,
          );
        });

        final row = await messageRepo.getMessage('msg-failed-foreign');
        expect(
          row!.status,
          'failed',
          reason: 'authenticated-ingress and row-peer guards both hold',
        );
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
          reason:
              'only a receiver confirmation for THIS id may lift a failed row',
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

        expect(
          (await messageRepo.getMessage('msg-sent-unconf'))!.status,
          'sent',
        );
        expect(
          (await messageRepo.getMessage('msg-failed-unconf'))!.status,
          'failed',
        );
      },
    );

    test(
      'TC-185-32 the failed→delivered flip rides typed atomic settlement '
      'and a stale duplicate receipt cannot downgrade or double-apply',
      () async {
        messageRepo.seed([makeInboxedOutgoing(status: 'failed')]);

        await handleDeliveryReceipt(
          message: buildReceipt(messageIds: ['msg-rcpt-001']),
          messageRepo: messageRepo,
        );
        expect(messageRepo.ordinaryMutationCallCount, 1);
        expect(messageRepo.conditionalTransitionCallCount, 0);
        expect(messageRepo.saveMessageCallCount, 0);
        expect(
          (await messageRepo.getMessage('msg-rcpt-001'))!.status,
          'delivered',
        );
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
