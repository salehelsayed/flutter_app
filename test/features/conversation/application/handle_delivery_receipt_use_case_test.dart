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
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

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
  Map<String, String>? mutationEventIds,
  String? transport = 'direct',
}) {
  return ChatMessage(
    from: from,
    to: 'my-peer',
    content: jsonEncode({
      'type': 'delivery_receipt',
      'version': '1',
      'payload': {
        'messageIds': messageIds,
        'mutationEventIds': ?mutationEventIds,
        'ts': '2026-06-13T12:00:00.000Z',
      },
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
    test('TC-361-03a a linked origin receipt settles only the exact current '
        'generation of the logical contact row', () async {
      const messageId = 'msg-linked-receipt';
      const linkedTransport = 'peer-linked-transport';
      const logicalContact = 'peer-logical-contact';
      messageRepo.seed(<ConversationMessage>[
        makeInboxedOutgoing(
          id: messageId,
          contactPeerId: logicalContact,
        ).copyWith(directEventFanoutGenerationId: messageId),
      ]);
      final authority = _FakeTransportAuthority({
        linkedTransport: const DirectTransportAuthorityResolution.authorized(
          kind: DirectTransportAuthorityKind.linked,
          contactAccountPeerId: logicalContact,
          contactIsBlocked: false,
        ),
      });

      // A stale/future event receipt is zero-effect.
      await handleDeliveryReceipt(
        message: buildReceipt(
          from: linkedTransport,
          messageIds: const <String>[messageId],
          mutationEventIds: const <String, String>{
            messageId: 'a-later-generation',
          },
        ),
        messageRepo: messageRepo,
        transportAuthority: authority,
      );
      expect((await messageRepo.getMessage(messageId))!.status, 'inboxed');

      // The exact current generation settles once and clears the witness.
      await handleDeliveryReceipt(
        message: buildReceipt(
          from: linkedTransport,
          messageIds: const <String>[messageId],
        ),
        messageRepo: messageRepo,
        transportAuthority: authority,
      );
      final settled = await messageRepo.getMessage(messageId);
      expect(settled!.status, 'delivered');
      expect(messageRepo.fanoutReceiptSettlements.last.generation, messageId);
      expect(
        messageRepo.fanoutReceiptSettlements.last.transport,
        linkedTransport,
      );
    });

    test('TC-361-03a an unresolvable receipt origin transport stays a foreign '
        'peer with zero effect', () async {
      const messageId = 'msg-foreign-receipt';
      const logicalContact = 'peer-logical-contact';
      messageRepo.seed(<ConversationMessage>[
        makeInboxedOutgoing(id: messageId, contactPeerId: logicalContact),
      ]);
      final authority = _FakeTransportAuthority(
        const <String, DirectTransportAuthorityResolution>{},
      );

      await handleDeliveryReceipt(
        message: buildReceipt(
          from: 'peer-unknown-transport',
          messageIds: const <String>[messageId],
        ),
        messageRepo: messageRepo,
        transportAuthority: authority,
      );

      expect((await messageRepo.getMessage(messageId))!.status, 'inboxed');
      expect(messageRepo.fanoutReceiptSettlements, isEmpty);
    });

    test(
      'TC-349-06 delayed initial receipt cannot settle current edit',
      () async {
        const messageId = 'msg-current-edit';
        const editEventId = '34900000-0000-4000-8000-000000000006';
        final editEnvelope = jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': messageId,
          'eventId': editEventId,
          'senderPeerId': 'my-peer',
          'encrypted': const <String, Object?>{
            'kem': 'kem',
            'ciphertext': 'cipher',
            'nonce': 'nonce',
          },
        });
        messageRepo.seed(<ConversationMessage>[
          makeInboxedOutgoing(id: messageId).copyWith(
            editedAt: '2026-06-13T11:30:00.000Z',
            wireEnvelope: editEnvelope,
          ),
        ]);

        await handleDeliveryReceipt(
          message: buildReceipt(messageIds: const <String>[messageId]),
          messageRepo: messageRepo,
        );

        final row = await messageRepo.getMessage(messageId);
        expect(row!.status, 'inboxed');
        expect(row.wireEnvelope, editEnvelope);
      },
    );
    test(
      'TC-349-06 stale edit receipt cannot settle current deletion and exact event receipt can',
      () async {
        const messageId = 'msg-current-deletion';
        const deletionEventId = '34900000-0000-4000-8000-000000000007';
        final deletionEnvelope = jsonEncode(<String, Object?>{
          'type': 'message_deletion',
          'version': '2',
          'eventId': deletionEventId,
          'senderPeerId': 'my-peer',
          'encrypted': const <String, Object?>{
            'kem': 'kem',
            'ciphertext': 'cipher',
            'nonce': 'nonce',
          },
        });
        messageRepo.seed(<ConversationMessage>[
          makeInboxedOutgoing(id: messageId).copyWith(
            text: '',
            deletedAt: '2026-06-13T11:40:00.000Z',
            deletedByPeerId: 'my-peer',
            wireEnvelope: deletionEnvelope,
          ),
        ]);

        await handleDeliveryReceipt(
          message: buildReceipt(
            messageIds: const <String>[messageId],
            mutationEventIds: const <String, String>{
              messageId: 'stale-edit-event',
            },
          ),
          messageRepo: messageRepo,
        );
        expect((await messageRepo.getMessage(messageId))!.status, 'inboxed');

        await handleDeliveryReceipt(
          message: buildReceipt(
            messageIds: const <String>[messageId],
            mutationEventIds: const <String, String>{
              messageId: deletionEventId,
            },
          ),
          messageRepo: messageRepo,
        );
        final settled = (await messageRepo.getMessage(messageId))!;
        expect(settled.status, 'delivered');
        expect(settled.wireEnvelope, isNull);
      },
    );

    test('TC-356-04d exact private deletion receipt settles only the matching '
        'event', () async {
      // The private tombstone settles through its own durable owner, so this
      // uses the real repository rather than the ordinary-only fake.
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const messageId = 'msg-private-deletion';
      const deletionEventId = '35600000-0000-4000-8000-00000000040d';
      final deletionEnvelope = jsonEncode(<String, Object?>{
        'type': 'message_deletion',
        'version': '2',
        'eventId': deletionEventId,
        'senderPeerId': 'my-peer',
        'encrypted': const <String, Object?>{
          'kem': 'kem',
          'ciphertext': 'cipher',
          'nonce': 'nonce',
        },
      });
      await fixture.seedDirectParent(messageId, contactPeerId: 'peer-remote');
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'sender_peer_id': 'my-peer',
          'text': '',
          'status': 'inboxed',
          'transport': 'inbox',
          'is_incoming': 0,
          'wire_envelope': deletionEnvelope,
          'deleted_at': '2026-06-13T11:45:00.000Z',
          'deleted_by_peer_id': 'my-peer',
          'hidden_at': null,
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );

      ChatMessage receipt(Map<String, String>? mutationEventIds) =>
          buildReceipt(
            from: 'peer-remote',
            messageIds: const <String>[messageId],
            mutationEventIds: mutationEventIds,
          );

      // Target-only, blank and crossed event maps cannot settle the exact
      // private tombstone.
      for (final wrong in <Map<String, String>?>[
        null,
        const <String, String>{messageId: ''},
        const <String, String>{messageId: 'some-other-event'},
      ]) {
        await handleDeliveryReceipt(
          message: receipt(wrong),
          messageRepo: fixture.messageRepo,
        );
        final row = (await fixture.messageRepo.getMessage(messageId))!;
        expect(row.status, 'inboxed');
        expect(row.wireEnvelope, deletionEnvelope);
      }

      await handleDeliveryReceipt(
        message: receipt(const <String, String>{messageId: deletionEventId}),
        messageRepo: fixture.messageRepo,
      );
      final settled = (await fixture.messageRepo.getMessage(messageId))!;
      expect(settled.status, 'delivered');
      expect(settled.wireEnvelope, isNull);
      expect(
        settled.privateMediaMode,
        PrivateMediaMode.protected,
        reason: 'a receipt never rewrites private lifecycle policy',
      );
      expect(
        await fixture.db.query('direct_reaction_inbox_custody_outbox'),
        isEmpty,
        reason: 'a device receipt is not v109 acceptance; it retires nothing',
      );
    });

    test(
      'TC-349-06 mixed receipt batch settles legacy IDs but not blank wrong mutation entries',
      () async {
        const legacyId = 'legacy-message';
        const editId = 'current-edit-message';
        const editEventId = '34900000-0000-4000-8000-000000000008';
        final editEnvelope = jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': editId,
          'eventId': editEventId,
          'senderPeerId': 'my-peer',
          'encrypted': const <String, Object?>{
            'kem': 'kem',
            'ciphertext': 'cipher',
            'nonce': 'nonce',
          },
        });
        messageRepo.seed(<ConversationMessage>[
          makeInboxedOutgoing(id: legacyId),
          makeInboxedOutgoing(id: editId).copyWith(
            editedAt: '2026-06-13T11:30:00.000Z',
            wireEnvelope: editEnvelope,
          ),
        ]);
        final receipt =
            buildReceipt(messageIds: const <String>[legacyId, editId]).copyWith(
              content: jsonEncode(<String, Object?>{
                'type': 'delivery_receipt',
                'version': '1',
                'payload': <String, Object?>{
                  'messageIds': const <String>[legacyId, editId],
                  'mutationEventIds': const <String, Object?>{
                    legacyId: 7,
                    editId: ' ',
                    'outside': editEventId,
                  },
                },
              }),
            );

        await handleDeliveryReceipt(message: receipt, messageRepo: messageRepo);

        expect((await messageRepo.getMessage(legacyId))!.status, 'delivered');
        final currentEdit = (await messageRepo.getMessage(editId))!;
        expect(currentEdit.status, 'inboxed');
        expect(currentEdit.wireEnvelope, editEnvelope);
      },
    );
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

class _FakeTransportAuthority implements DirectTransportAuthorityResolver {
  _FakeTransportAuthority(this.byTransport);

  final Map<String, DirectTransportAuthorityResolution> byTransport;
  int resolveCalls = 0;

  @override
  Future<DirectTransportAuthorityResolution> resolveDirectTransportAuthority(
    String transportPeerId,
  ) async {
    resolveCalls++;
    return byTransport[transportPeerId] ??
        const DirectTransportAuthorityResolution.refused('unknown_transport');
  }
}
