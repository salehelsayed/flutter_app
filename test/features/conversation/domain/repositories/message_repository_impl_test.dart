import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/database/direct_reaction_inbox_custody_outbox_contract.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart'
    show OutgoingDirectPrivateFanoutInboxCustodyDbResult;
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // In-memory store for testing
  late Map<String, Map<String, Object?>> store;
  late int dbLoadMessageCallCount;
  late MessageRepositoryImpl repo;
  late DirectReactionNotificationProjection directReactionProjection;
  late OutgoingOrdinaryMutationOutcome nextStageOutcome;
  late OutgoingOrdinaryMutationOutcome nextSettlementOutcome;
  late OutgoingOrdinaryMutationOutcome nextTombstoneSettlementOutcome;
  late List<MediaAttachment> authoritativeOrdinaryMedia;
  late int ordinaryStageCallCount;
  late int ordinarySettlementCallCount;
  late int ordinaryTombstoneSettlementCallCount;
  late bool removeAfterAppliedSettlement;
  late int privateDeletionStageCallCount;
  late DbDirectPrivateDeletionCustodyStageResult nextPrivateDeletionStage;
  late int privateFanoutBarrierCallCount;
  late OutgoingDirectPrivateFanoutInboxCustodyDbResult
  nextPrivateFanoutBarrierResult;
  ({
    Map<String, Object?> completionRow,
    String expectedPendingLocalPath,
    bool hasOwnedPendingCompletion,
    String senderTransportPeerId,
    String contactAccountPeerId,
    DirectPrivateMediaFanoutStageAuthority authority,
    DirectContactFanoutSnapshot? expectedSnapshot,
    List<DirectPrivateMediaFanoutTargetBinding> targetBindings,
  })?
  lastPrivateFanoutBarrierArgs;
  ({
    Map<String, Object?> expectedRow,
    Map<String, Object?> tombstoneRow,
    String recipientPeerId,
    String eventId,
    String wireEnvelope,
  })?
  lastPrivateDeletionStageArgs;

  setUp(() async {
    store = {};
    dbLoadMessageCallCount = 0;
    nextStageOutcome = OutgoingOrdinaryMutationOutcome.refused;
    nextSettlementOutcome = OutgoingOrdinaryMutationOutcome.refused;
    nextTombstoneSettlementOutcome = OutgoingOrdinaryMutationOutcome.refused;
    authoritativeOrdinaryMedia = const <MediaAttachment>[];
    ordinaryStageCallCount = 0;
    ordinarySettlementCallCount = 0;
    ordinaryTombstoneSettlementCallCount = 0;
    removeAfterAppliedSettlement = false;
    privateDeletionStageCallCount = 0;
    lastPrivateDeletionStageArgs = null;
    nextPrivateDeletionStage =
        const DbDirectPrivateDeletionCustodyStageResult.refused();
    privateFanoutBarrierCallCount = 0;
    nextPrivateFanoutBarrierResult =
        const OutgoingDirectPrivateFanoutInboxCustodyDbResult.refused();
    lastPrivateFanoutBarrierArgs = null;
    directReactionProjection = DirectReactionNotificationProjection(
      store: _MemorySecureKeyStore(),
    );
    await directReactionProjection.replaceLocalIdentity(
      accountPeerId: 'peer-local',
    );

    repo = MessageRepositoryImpl(
      dbInsertMessage: (row) async {
        store[row['id'] as String] = Map.from(row);
      },
      dbLoadMessagesForContact: (contactPeerId) async {
        return store.values
            .where(
              (row) =>
                  row['contact_peer_id'] == contactPeerId &&
                  row['hidden_at'] == null,
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['timestamp'] as String).compareTo(b['timestamp'] as String),
          );
      },
      dbLoadLatestMessageForContact: (contactPeerId) async {
        final rows =
            store.values
                .where(
                  (row) =>
                      row['contact_peer_id'] == contactPeerId &&
                      row['hidden_at'] == null,
                )
                .toList()
              ..sort(
                (a, b) => (b['timestamp'] as String).compareTo(
                  a['timestamp'] as String,
                ),
              );
        return rows.isNotEmpty ? rows.first : null;
      },
      dbUpdateMessageStatus: (id, status) async {
        if (!store.containsKey(id)) {
          return 0;
        }
        store[id]!['status'] = status;
        return 1;
      },
      dbLoadMessage: (id) async {
        dbLoadMessageCallCount++;
        return store[id];
      },
      dbCountMessagesForContact: (contactPeerId) async {
        return store.values
            .where(
              (row) =>
                  row['contact_peer_id'] == contactPeerId &&
                  row['hidden_at'] == null,
            )
            .length;
      },
      dbMarkConversationAsRead: (contactPeerId) async {
        var count = 0;
        final now = DateTime.now().toUtc().toIso8601String();
        for (final row in store.values) {
          if (row['contact_peer_id'] == contactPeerId &&
              row['hidden_at'] == null &&
              row['is_incoming'] == 1 &&
              row['read_at'] == null) {
            row['read_at'] = now;
            count++;
          }
        }
        return count;
      },
      dbCountUnreadForContact: (contactPeerId) async {
        return store.values
            .where(
              (row) =>
                  row['contact_peer_id'] == contactPeerId &&
                  row['hidden_at'] == null &&
                  row['is_incoming'] == 1 &&
                  row['read_at'] == null,
            )
            .length;
      },
      dbCountTotalUnread: () async {
        return store.values
            .where(
              (row) =>
                  row['hidden_at'] == null &&
                  row['is_incoming'] == 1 &&
                  row['read_at'] == null,
            )
            .length;
      },
      dbCountTotalUnreadExcludingArchived: () async {
        return store.values
            .where(
              (row) =>
                  row['hidden_at'] == null &&
                  row['is_incoming'] == 1 &&
                  row['read_at'] == null,
            )
            .length;
      },
      dbDeleteMessagesForContact: (contactPeerId) async {
        final keysToRemove = store.entries
            .where((e) => e.value['contact_peer_id'] == contactPeerId)
            .map((e) => e.key)
            .toList();
        for (final key in keysToRemove) {
          store.remove(key);
        }
        return keysToRemove.length;
      },
      dbDeleteMessage: (id) async {
        return store.remove(id) == null ? 0 : 1;
      },
      dbExistsMessageByContent: (_, _, _, _) async => false,
      dbLoadMessagesPage: (contactPeerId, {limit = 50, beforeTimestamp}) async {
        var rows = store.values
            .where(
              (row) =>
                  row['contact_peer_id'] == contactPeerId &&
                  row['hidden_at'] == null,
            )
            .toList();
        if (beforeTimestamp != null) {
          rows = rows
              .where(
                (row) =>
                    (row['timestamp'] as String).compareTo(beforeTimestamp) < 0,
              )
              .toList();
        }
        rows.sort(
          (a, b) =>
              (b['timestamp'] as String).compareTo(a['timestamp'] as String),
        );
        final page = rows.take(limit).toList();
        return page.reversed.toList();
      },
      dbLoadFailedOutgoingMessages: () async {
        return store.values
            .where(
              (row) => row['status'] == 'failed' && row['is_incoming'] == 0,
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['timestamp'] as String).compareTo(b['timestamp'] as String),
          );
      },
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) async {
        return store.values
            .where(
              (row) =>
                  row['status'] == 'sent' &&
                  row['is_incoming'] == 0 &&
                  row['wire_envelope'] != null &&
                  (row['timestamp'] as String).compareTo(
                        olderThan.toUtc().toIso8601String(),
                      ) <
                      0,
            )
            .take(limit)
            .toList()
          ..sort(
            (a, b) =>
                (a['timestamp'] as String).compareTo(b['timestamp'] as String),
          );
      },
      dbLoadConversationThreadSummaries: (contactPeerIds) async {
        final summaries = <Map<String, Object?>>[];
        for (final contactPeerId in contactPeerIds) {
          final rows =
              store.values
                  .where(
                    (row) =>
                        row['contact_peer_id'] == contactPeerId &&
                        row['hidden_at'] == null,
                  )
                  .toList()
                ..sort((a, b) {
                  final timestampOrder = (b['timestamp'] as String).compareTo(
                    a['timestamp'] as String,
                  );
                  if (timestampOrder != 0) return timestampOrder;
                  final createdAtA = a['created_at'] as String? ?? '';
                  final createdAtB = b['created_at'] as String? ?? '';
                  return createdAtB.compareTo(createdAtA);
                });
          final latest = rows.isEmpty ? null : rows.first;
          summaries.add({
            'contact_peer_id': contactPeerId,
            'message_count': rows.length,
            'unread_count': rows
                .where(
                  (row) => row['is_incoming'] == 1 && row['read_at'] == null,
                )
                .length,
            'latest_id': latest?['id'],
            'latest_contact_peer_id': latest?['contact_peer_id'],
            'latest_sender_peer_id': latest?['sender_peer_id'],
            'latest_text': latest?['text'],
            'latest_timestamp': latest?['timestamp'],
            'latest_status': latest?['status'],
            'latest_is_incoming': latest?['is_incoming'],
            'latest_created_at': latest?['created_at'],
            'latest_edited_at': latest?['edited_at'],
            'latest_read_at': latest?['read_at'],
            'latest_quoted_message_id': latest?['quoted_message_id'],
            'latest_deleted_at': latest?['deleted_at'],
            'latest_deleted_by_peer_id': latest?['deleted_by_peer_id'],
            'latest_hidden_at': latest?['hidden_at'],
            'latest_transport': latest?['transport'],
            'latest_wire_envelope': latest?['wire_envelope'],
          });
        }
        return summaries;
      },
      dbRecoverStuckSendingMessages:
          ({required DateTime olderThan, int limit = 50}) async => 0,
      dbUpdateWireEnvelope: (id, wireEnvelope) async {},
      dbLoadDirectTextMutationInboxCustodyForEvent:
          ({required recipientPeerId, required eventId}) async => null,
      dbRecordDirectTextMutationInboxCustodyFailureIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
            required errorCode,
            required attemptedAt,
          }) async => false,
      dbCompleteAcceptedDirectTextMutationInboxCustodyIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
            required relayExpiresAt,
          }) async => DirectMutationInboxCustodyCompletionOutcome.stale,
      dbStageOutgoingDirectPrivateDeletionInboxCustody:
          ({
            required expectedRow,
            required tombstoneRow,
            required recipientPeerId,
            required eventId,
            required wireEnvelope,
          }) async {
            privateDeletionStageCallCount++;
            lastPrivateDeletionStageArgs = (
              expectedRow: expectedRow,
              tombstoneRow: tombstoneRow,
              recipientPeerId: recipientPeerId,
              eventId: eventId,
              wireEnvelope: wireEnvelope,
            );
            return nextPrivateDeletionStage;
          },
      dbCommitOutgoingDirectPrivateWireEnvelopeFanoutWithInboxCustody:
          (
            completionRow, {
            required expectedPendingLocalPath,
            required hasOwnedPendingCompletion,
            required senderTransportPeerId,
            required contactAccountPeerId,
            required authority,
            required expectedSnapshot,
            required targetBindings,
          }) async {
            privateFanoutBarrierCallCount++;
            lastPrivateFanoutBarrierArgs = (
              completionRow: completionRow,
              expectedPendingLocalPath: expectedPendingLocalPath,
              hasOwnedPendingCompletion: hasOwnedPendingCompletion,
              senderTransportPeerId: senderTransportPeerId,
              contactAccountPeerId: contactAccountPeerId,
              authority: authority,
              expectedSnapshot: expectedSnapshot,
              targetBindings: targetBindings,
            );
            return nextPrivateFanoutBarrierResult;
          },
      dbStageOutgoingOrdinaryAttempt:
          ({required expectedRow, required stagedRow, required kind}) async {
            ordinaryStageCallCount++;
            if (nextStageOutcome == OutgoingOrdinaryMutationOutcome.applied) {
              store[stagedRow['id'] as String] = <String, Object?>{
                ...stagedRow,
                'text': 'authoritative staged text',
              };
            }
            return nextStageOutcome;
          },
      dbSettleOutgoingOrdinaryTransport:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
            required status,
            required transport,
            required relayExpiresAt,
            required mode,
          }) async {
            ordinarySettlementCallCount++;
            if (nextSettlementOutcome ==
                OutgoingOrdinaryMutationOutcome.applied) {
              store[messageId] = <String, Object?>{
                ...store[messageId]!,
                'status': status,
                'transport': transport,
                'wire_envelope': status == 'delivered'
                    ? null
                    : expectedEnvelope,
                'relay_expires_at': relayExpiresAt,
                'custody_checked_at': null,
              };
              if (removeAfterAppliedSettlement) {
                store.remove(messageId);
              }
            }
            return nextSettlementOutcome;
          },
      dbSettleOutgoingOrdinaryDeleteTombstone:
          ({
            required messageId,
            required expectedContactPeerId,
            required expectedEnvelope,
            required status,
            required transport,
            required relayExpiresAt,
            required mode,
          }) async {
            ordinaryTombstoneSettlementCallCount++;
            if (nextTombstoneSettlementOutcome ==
                OutgoingOrdinaryMutationOutcome.applied) {
              final row = store[messageId]!;
              store[messageId] = <String, Object?>{
                ...row,
                'status': status,
                'transport': transport,
                'wire_envelope': status == 'delivered'
                    ? null
                    : expectedEnvelope,
                'relay_expires_at': relayExpiresAt,
                'custody_checked_at': null,
                'hidden_at': status == 'delivered' ? row['deleted_at'] : null,
              };
            }
            return nextTombstoneSettlementOutcome;
          },
      loadOutgoingOrdinaryMedia: (_) async => authoritativeOrdinaryMedia,
      dbLoadStuckSendingOutgoingMessages:
          ({required DateTime olderThan, int limit = 50}) async => [],
      dbLoadSendingOutgoingMessages: () async => [],
      dbConditionalTransitionStatus:
          (id, {required fromStatus, required toStatus}) async {
            final row = store[id];
            if (row == null || row['status'] != fromStatus) {
              return 0;
            }
            row['status'] = toStatus;
            return 1;
          },
      directReactionProjection: directReactionProjection,
      dbLoadLocallyAuthoredMessagesForProjection: () async => store.values
          .where((row) => row['is_incoming'] == 0)
          .toList(growable: false),
    );
  });

  ConversationMessage makeMessage({
    String id = 'msg-1',
    String contactPeerId = 'contact-peer',
    String senderPeerId = 'sender-peer',
    String text = 'Hello',
    String timestamp = '2026-02-09T10:00:00.000Z',
    String status = 'sent',
    bool isIncoming = false,
    String createdAt = '2026-02-09T10:00:01.000Z',
    String? editedAt,
    String? readAt,
    String? quotedMessageId,
    String? deletedAt,
    String? deletedByPeerId,
    String? hiddenAt,
    String? transport,
    String? wireEnvelope,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: contactPeerId,
      senderPeerId: senderPeerId,
      text: text,
      timestamp: timestamp,
      status: status,
      isIncoming: isIncoming,
      createdAt: createdAt,
      editedAt: editedAt,
      readAt: readAt,
      quotedMessageId: quotedMessageId,
      deletedAt: deletedAt,
      deletedByPeerId: deletedByPeerId,
      hiddenAt: hiddenAt,
      transport: transport,
      wireEnvelope: wireEnvelope,
    );
  }

  void expectMessageShape(
    ConversationMessage actual,
    ConversationMessage expected,
  ) {
    expect(actual.id, expected.id);
    expect(actual.contactPeerId, expected.contactPeerId);
    expect(actual.senderPeerId, expected.senderPeerId);
    expect(actual.text, expected.text);
    expect(actual.timestamp, expected.timestamp);
    expect(actual.status, expected.status);
    expect(actual.isIncoming, expected.isIncoming);
    expect(actual.createdAt, expected.createdAt);
    expect(actual.editedAt, expected.editedAt);
    expect(actual.readAt, expected.readAt);
    expect(actual.quotedMessageId, expected.quotedMessageId);
    expect(actual.deletedAt, expected.deletedAt);
    expect(actual.deletedByPeerId, expected.deletedByPeerId);
    expect(actual.hiddenAt, expected.hiddenAt);
    expect(actual.transport, expected.transport);
    expect(actual.wireEnvelope, expected.wireEnvelope);
  }

  group('MessageRepositoryImpl', () {
    test(
      'ordinary attempt and settlement publish only authoritative applied state',
      () async {
        const messageId = 'ordinary-authoritative-publication';
        final candidate = makeMessage(
          id: messageId,
          status: 'sending',
          wireEnvelope: 'envelope-attempt',
        );
        authoritativeOrdinaryMedia = const <MediaAttachment>[
          MediaAttachment(
            id: 'ordinary-direct-media',
            messageId: messageId,
            mime: 'image/png',
            size: 7,
            mediaType: 'image',
            downloadStatus: 'done',
            createdAt: '2026-02-09T10:00:02.000Z',
          ),
          MediaAttachment(
            id: 'wrong-owner-media',
            messageId: messageId,
            mime: 'image/png',
            size: 8,
            mediaType: 'image',
            downloadStatus: 'done',
            createdAt: '2026-02-09T10:00:03.000Z',
            ownerLane: MediaOwnerLane.group,
          ),
          MediaAttachment(
            id: 'wrong-parent-media',
            messageId: 'another-message',
            mime: 'image/png',
            size: 9,
            mediaType: 'image',
            downloadStatus: 'done',
            createdAt: '2026-02-09T10:00:04.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
        ];
        final emitted = <ConversationMessage>[];
        final subscription = repo.messageChanges.listen(emitted.add);
        addTearDown(subscription.cancel);

        nextStageOutcome = OutgoingOrdinaryMutationOutcome.applied;
        final staged = await repo.stageOutgoingOrdinaryAttempt(
          expected: null,
          staged: candidate,
          kind: OutgoingOrdinaryAttemptKind.fresh,
        );
        await Future<void>.delayed(Duration.zero);

        expect(ordinaryStageCallCount, 1);
        expect(staged.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(staged.message!.text, 'authoritative staged text');
        expect(staged.message!.media, hasLength(1));
        expect(staged.message!.media.single.id, 'ordinary-direct-media');
        expect(staged.message!.media.single.ownerLane, MediaOwnerLane.direct);
        expect(emitted, hasLength(1));
        expect(emitted.single.text, 'authoritative staged text');
        expect(
          (await directReactionProjection.readAuthoredTargets()).map(
            (target) => target['id'],
          ),
          <String?>[messageId],
        );

        await directReactionProjection.removeAuthoredTarget(messageId);
        store[messageId] = <String, Object?>{
          ...store[messageId]!,
          'text': 'concurrent durable text',
          'status': 'delivered',
          'wire_envelope': null,
        };
        for (final outcome in <OutgoingOrdinaryMutationOutcome>[
          OutgoingOrdinaryMutationOutcome.idempotent,
          OutgoingOrdinaryMutationOutcome.preserved,
          OutgoingOrdinaryMutationOutcome.refused,
        ]) {
          nextSettlementOutcome = outcome;
          final noOp = await repo.settleOutgoingOrdinaryTransport(
            messageId: messageId,
            expectedContactPeerId: 'contact-peer',
            expectedEnvelope: 'envelope-attempt',
            status: 'delivered',
            transport: 'direct',
            relayExpiresAt: null,
            mode: OutgoingOrdinarySettlementMode.live,
          );
          expect(noOp.outcome, outcome);
          expect(noOp.message!.text, 'concurrent durable text');
          expect(noOp.message!.status, 'delivered');
        }
        await Future<void>.delayed(Duration.zero);
        expect(ordinarySettlementCallCount, 3);
        expect(emitted, hasLength(1), reason: 'no-op outcomes stay silent');
        expect(await directReactionProjection.readAuthoredTargets(), isEmpty);

        const tombstoneId = 'ordinary-authoritative-tombstone';
        store[tombstoneId] = makeMessage(
          id: tombstoneId,
          text: '',
          status: 'inboxed',
          deletedAt: '2026-02-09T10:05:00.000Z',
          deletedByPeerId: 'sender-peer',
          wireEnvelope: 'delete-envelope',
        ).toMap();
        await directReactionProjection.upsertAuthoredTarget(
          makeMessage(id: tombstoneId),
        );
        nextTombstoneSettlementOutcome =
            OutgoingOrdinaryMutationOutcome.applied;
        final tombstone = await repo.settleOutgoingOrdinaryDeleteTombstone(
          messageId: tombstoneId,
          expectedContactPeerId: 'contact-peer',
          expectedEnvelope: 'delete-envelope',
          status: 'delivered',
          transport: 'inbox',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.receipt,
        );
        await Future<void>.delayed(Duration.zero);
        expect(ordinaryTombstoneSettlementCallCount, 1);
        expect(tombstone.message!.isHidden, isTrue);
        expect(emitted, hasLength(2));
        expect(emitted.last.id, tombstoneId);
        expect(await directReactionProjection.readAuthoredTargets(), isEmpty);

        store[messageId] = candidate.toMap();
        nextSettlementOutcome = OutgoingOrdinaryMutationOutcome.applied;
        removeAfterAppliedSettlement = true;
        final removedAfterCommit = await repo.settleOutgoingOrdinaryTransport(
          messageId: messageId,
          expectedContactPeerId: 'contact-peer',
          expectedEnvelope: 'envelope-attempt',
          status: 'sent',
          transport: 'direct',
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.live,
        );
        removeAfterAppliedSettlement = false;
        expect(
          removedAfterCommit.outcome,
          OutgoingOrdinaryMutationOutcome.removed,
        );
        expect(removedAfterCommit.message, isNull);
        expect(emitted, hasLength(2));

        store.remove(messageId);
        nextSettlementOutcome = OutgoingOrdinaryMutationOutcome.removed;
        final removed = await repo.settleOutgoingOrdinaryTransport(
          messageId: messageId,
          expectedContactPeerId: 'contact-peer',
          expectedEnvelope: null,
          status: 'delivered',
          transport: null,
          relayExpiresAt: null,
          mode: OutgoingOrdinarySettlementMode.receipt,
        );
        expect(removed.outcome, OutgoingOrdinaryMutationOutcome.removed);
        expect(removed.message, isNull);
        expect(emitted, hasLength(2));
      },
    );

    test('saveMessage persists to store', () async {
      final msg = makeMessage();
      await repo.saveMessage(msg);

      expect(store.containsKey('msg-1'), true);
      expect(store['msg-1']!['text'], 'Hello');
    });

    test('saveMessage persists editedAt metadata', () async {
      final msg = makeMessage(editedAt: '2026-02-09T10:05:00.000Z');
      await repo.saveMessage(msg);

      final loaded = await repo.getMessage(msg.id);
      expect(loaded, isNotNull);
      expect(loaded!.editedAt, '2026-02-09T10:05:00.000Z');
    });

    test(
      'saveMessage emits validated transient image/video once without caching it',
      () async {
        const messageId = 'forward-media-projection';
        const media = <MediaAttachment>[
          MediaAttachment(
            id: 'forward-image',
            messageId: messageId,
            mime: 'image/png',
            size: 3,
            mediaType: 'image',
            localPath: '/tmp/forward-image.png',
            downloadStatus: 'done',
            createdAt: '2026-02-09T10:00:01.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
          MediaAttachment(
            id: 'forward-video',
            messageId: messageId,
            mime: 'video/mp4',
            size: 4,
            mediaType: 'video',
            localPath: '/tmp/forward-video.mp4',
            downloadStatus: 'done',
            createdAt: '2026-02-09T10:00:02.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
        ];
        final outgoing = makeMessage(
          id: messageId,
          text: 'Forwarded media',
          status: 'sent',
        ).copyWith(media: media);
        final emitted = <ConversationMessage>[];
        final sub = repo.messageChanges.listen(emitted.add);
        addTearDown(sub.cancel);

        await repo.saveMessage(outgoing);
        await Future<void>.delayed(Duration.zero);

        expect(store[messageId], isNot(contains('media')));
        expect(emitted, hasLength(1));
        expectMessageShape(emitted.single, outgoing);
        expect(
          emitted.single.media.map((attachment) => attachment.id),
          <String>['forward-image', 'forward-video'],
        );
        expect(
          (await repo.getMessage(messageId))!.media,
          isEmpty,
          reason: 'row reads must never recover transient paths from cache',
        );

        await repo.updateMessageStatus(messageId, 'delivered');
        await Future<void>.delayed(Duration.zero);

        expect(emitted, hasLength(2));
        expect(emitted.last.status, 'delivered');
        expect(
          emitted.last.media,
          isEmpty,
          reason: 'status events are canonical row projections only',
        );
      },
    );

    test(
      'deleted or explicitly empty saves never resurrect transient media',
      () async {
        const messageId = 'deleted-media-projection';
        const media = <MediaAttachment>[
          MediaAttachment(
            id: 'deleted-image',
            messageId: messageId,
            mime: 'image/png',
            size: 3,
            mediaType: 'image',
            localPath: '/tmp/deleted-image.png',
            downloadStatus: 'done',
            createdAt: '2026-02-09T10:00:01.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
        ];
        final outgoing = makeMessage(id: messageId).copyWith(media: media);
        final emitted = <ConversationMessage>[];
        final sub = repo.messageChanges.listen(emitted.add);
        addTearDown(sub.cancel);

        await repo.saveMessage(outgoing);
        await Future<void>.delayed(Duration.zero);
        expect(emitted.single.media, media);

        final deleted = outgoing.copyWith(
          text: '',
          deletedAt: '2026-02-09T10:05:00.000Z',
          hiddenAt: '2026-02-09T10:05:00.000Z',
          media: media,
        );
        await repo.saveMessage(deleted);
        await Future<void>.delayed(Duration.zero);

        expect(emitted.last.isDeleted, isTrue);
        expect(emitted.last.media, isEmpty);
        expect((await repo.getMessage(messageId))!.media, isEmpty);

        await repo.saveMessage(deleted.copyWith(media: const []));
        await repo.updateMessageStatus(messageId, 'delivered');
        await Future<void>.delayed(Duration.zero);
        expect(emitted.last.media, isEmpty);
      },
    );

    test('getMessagesForContact returns empty list when no messages', () async {
      final result = await repo.getMessagesForContact('nonexistent');
      expect(result, isEmpty);
    });

    test(
      'getMessagesForContact returns messages ordered by timestamp',
      () async {
        await repo.saveMessage(
          makeMessage(id: 'msg-2', timestamp: '2026-02-09T11:00:00.000Z'),
        );
        await repo.saveMessage(
          makeMessage(id: 'msg-1', timestamp: '2026-02-09T10:00:00.000Z'),
        );
        await repo.saveMessage(
          makeMessage(id: 'msg-3', timestamp: '2026-02-09T12:00:00.000Z'),
        );

        final messages = await repo.getMessagesForContact('contact-peer');
        expect(messages.length, 3);
        expect(messages[0].id, 'msg-1');
        expect(messages[1].id, 'msg-2');
        expect(messages[2].id, 'msg-3');
      },
    );

    test('getMessagesForContact filters by contactPeerId', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1', contactPeerId: 'peer-A'));
      await repo.saveMessage(makeMessage(id: 'msg-2', contactPeerId: 'peer-B'));

      final messagesA = await repo.getMessagesForContact('peer-A');
      expect(messagesA.length, 1);
      expect(messagesA[0].id, 'msg-1');

      final messagesB = await repo.getMessagesForContact('peer-B');
      expect(messagesB.length, 1);
      expect(messagesB[0].id, 'msg-2');
    });

    test('getLatestMessageForContact returns most recent', () async {
      await repo.saveMessage(
        makeMessage(id: 'msg-1', timestamp: '2026-02-09T10:00:00.000Z'),
      );
      await repo.saveMessage(
        makeMessage(id: 'msg-2', timestamp: '2026-02-09T12:00:00.000Z'),
      );

      final latest = await repo.getLatestMessageForContact('contact-peer');
      expect(latest, isNotNull);
      expect(latest!.id, 'msg-2');
    });

    test('getLatestMessageForContact returns null when none exist', () async {
      final latest = await repo.getLatestMessageForContact('nonexistent');
      expect(latest, isNull);
    });

    test('getMessagesForContact excludes hidden tombstone rows', () async {
      await repo.saveMessage(
        makeMessage(id: 'msg-visible', timestamp: '2026-02-09T10:00:00.000Z'),
      );
      await repo.saveMessage(
        makeMessage(
          id: 'msg-hidden',
          timestamp: '2026-02-09T11:00:00.000Z',
          deletedAt: '2026-02-09T11:30:00.000Z',
          deletedByPeerId: 'sender-peer',
          hiddenAt: '2026-02-09T11:30:00.000Z',
        ),
      );

      final messages = await repo.getMessagesForContact('contact-peer');
      expect(messages.map((message) => message.id), ['msg-visible']);

      final hidden = await repo.getMessage('msg-hidden');
      expect(hidden, isNotNull);
      expect(hidden!.isHidden, isTrue);
      expect(hidden.isDeleted, isTrue);
    });

    test(
      'getConversationThreadSummaries returns counts and latest rows',
      () async {
        await repo.saveMessage(
          makeMessage(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            text: 'older',
            timestamp: '2026-02-09T10:00:00.000Z',
            isIncoming: true,
          ),
        );
        await repo.saveMessage(
          makeMessage(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            text: 'newer',
            timestamp: '2026-02-09T11:00:00.000Z',
            isIncoming: true,
          ),
        );

        final summaries = await repo.getConversationThreadSummaries([
          'peer-A',
          'peer-B',
        ]);

        expect(summaries['peer-A']!.messageCount, 2);
        expect(summaries['peer-A']!.unreadCount, 2);
        expect(summaries['peer-A']!.latestMessage!.id, 'msg-2');
        expect(summaries['peer-B']!.messageCount, 0);
        expect(summaries['peer-B']!.latestMessage, isNull);
      },
    );

    test(
      'getConversationThreadSummaries maps deleted metadata on latest row',
      () async {
        await repo.saveMessage(
          makeMessage(
            id: 'msg-deleted',
            contactPeerId: 'peer-A',
            text: '',
            timestamp: '2026-02-09T11:00:00.000Z',
            deletedAt: '2026-02-09T11:05:00.000Z',
            deletedByPeerId: 'peer-A',
          ),
        );

        final summaries = await repo.getConversationThreadSummaries(['peer-A']);
        final latest = summaries['peer-A']!.latestMessage;

        expect(latest, isNotNull);
        expect(latest!.isDeleted, isTrue);
        expect(latest.deletedAt, '2026-02-09T11:05:00.000Z');
        expect(latest.deletedByPeerId, 'peer-A');
      },
    );

    test('updateMessageStatus changes status', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1', status: 'sent'));
      await repo.updateMessageStatus('msg-1', 'delivered');

      expect(store['msg-1']!['status'], 'delivered');
    });

    test('deleteMessage removes only the targeted row', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1', contactPeerId: 'peer-a'));
      await repo.saveMessage(makeMessage(id: 'msg-2', contactPeerId: 'peer-a'));
      await repo.saveMessage(makeMessage(id: 'msg-3', contactPeerId: 'peer-b'));

      final count = await repo.deleteMessage('msg-2');

      expect(count, 1);
      expect(store.containsKey('msg-1'), isTrue);
      expect(store.containsKey('msg-2'), isFalse);
      expect(store.containsKey('msg-3'), isTrue);
    });

    test(
      'physical delete emits exact removal only after the durable row is gone',
      () async {
        await repo.saveMessage(
          makeMessage(id: 'pip-parent', contactPeerId: 'peer-pip'),
        );
        final removals = <DirectMessageRemoval>[];
        var rowWasAbsentAtEmission = false;
        final subscription = repo.messageRemovals.listen((removal) {
          removals.add(removal);
          rowWasAbsentAtEmission = !store.containsKey('pip-parent');
        });
        addTearDown(subscription.cancel);

        expect(await repo.deleteMessage('pip-parent'), 1);

        expect(rowWasAbsentAtEmission, isTrue);
        expect(removals, hasLength(1));
        expect(removals.single.contactPeerId, 'peer-pip');
        expect(removals.single.messageId, 'pip-parent');

        expect(await repo.deleteMessage('pip-parent'), 0);
        expect(removals, hasLength(1), reason: 'a no-op delete stays silent');
      },
    );

    test(
      'updateMessageStatus emits updated message exactly once without reloading cached row',
      () async {
        final original = makeMessage(
          id: 'msg-update-stream',
          text: 'Needs ACK',
          timestamp: '2026-02-09T10:02:00.000Z',
          status: 'sent',
          createdAt: '2026-02-09T10:02:01.000Z',
          quotedMessageId: 'quoted-123',
          transport: 'relay',
          wireEnvelope: '{"type":"chat_message"}',
        );
        await repo.saveMessage(original);
        dbLoadMessageCallCount = 0;

        final emitted = <ConversationMessage>[];
        final sub = repo.messageChanges.listen(emitted.add);
        addTearDown(sub.cancel);

        await repo.updateMessageStatus(original.id, 'delivered');
        await Future<void>.delayed(Duration.zero);

        expect(dbLoadMessageCallCount, 0);
        expect(emitted, hasLength(1));
        expectMessageShape(
          emitted.single,
          original.copyWith(status: 'delivered'),
        );
        expect(store[original.id]!['status'], 'delivered');
      },
    );

    test(
      'updateMessageStatus does not emit stale cached message when the row no longer exists',
      () async {
        final original = makeMessage(
          id: 'msg-update-missing-row',
          text: 'Missing row',
          status: 'sending',
        );
        await repo.saveMessage(original);
        store.remove(original.id);
        dbLoadMessageCallCount = 0;

        final emitted = <ConversationMessage>[];
        final sub = repo.messageChanges.listen(emitted.add);
        addTearDown(sub.cancel);

        await repo.updateMessageStatus(original.id, 'failed');
        await Future<void>.delayed(Duration.zero);

        expect(dbLoadMessageCallCount, 0);
        expect(emitted, isEmpty);
      },
    );

    test(
      'conditionalTransitionStatus emits updated message exactly once without reloading cached row',
      () async {
        final original = makeMessage(
          id: 'msg-conditional-stream',
          text: 'Pause me',
          timestamp: '2026-02-09T10:03:00.000Z',
          status: 'sending',
          createdAt: '2026-02-09T10:03:01.000Z',
          transport: 'direct',
        );
        await repo.saveMessage(original);
        dbLoadMessageCallCount = 0;

        final emitted = <ConversationMessage>[];
        final sub = repo.messageChanges.listen(emitted.add);
        addTearDown(sub.cancel);

        final updated = await repo.conditionalTransitionStatus(
          original.id,
          fromStatus: 'sending',
          toStatus: 'failed',
        );
        await Future<void>.delayed(Duration.zero);

        expect(updated, 1);
        expect(dbLoadMessageCallCount, 0);
        expect(emitted, hasLength(1));
        expectMessageShape(emitted.single, original.copyWith(status: 'failed'));
      },
    );

    // 194 (read-emission) — markConversationAsRead emits the peerId on
    // conversationReadStream ONLY when >=1 row flipped to read (INV-5). Surfaces
    // that project unread state (Orbit inner circle) subscribe to it.
    test(
      'markConversationAsRead emits peerId on conversationReadStream when rows>0, '
      'and nothing when 0',
      () async {
        await repo.saveMessage(
          makeMessage(id: 'in-1', contactPeerId: 'peer-x', isIncoming: true),
        );
        await repo.saveMessage(
          makeMessage(id: 'in-2', contactPeerId: 'peer-x', isIncoming: true),
        );

        final reads = <String>[];
        final sub = repo.conversationReadStream.listen(reads.add);
        addTearDown(sub.cancel);

        final marked = await repo.markConversationAsRead('peer-x');
        await Future<void>.delayed(Duration.zero);
        expect(marked, 2);
        expect(reads, ['peer-x'], reason: 'one conversation-level read event');

        reads.clear();
        // Already read -> 0 rows -> no emission (INV-5 guard).
        final markedAgain = await repo.markConversationAsRead('peer-x');
        await Future<void>.delayed(Duration.zero);
        expect(markedAgain, 0);
        expect(reads, isEmpty);
      },
    );

    test('messageExists returns true for existing message', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1'));
      expect(await repo.messageExists('msg-1'), true);
    });

    test(
      'outgoing create/delete and backfill maintain authored-target projection',
      () async {
        await repo.saveMessage(makeMessage(id: 'outgoing'));
        await repo.saveMessage(makeMessage(id: 'incoming', isIncoming: true));
        expect(
          (await directReactionProjection.readAuthoredTargets()).map(
            (row) => row['id'],
          ),
          <String?>['outgoing'],
        );

        await directReactionProjection.removeAuthoredTarget('outgoing');
        await repo.mirrorAllDirectReactionAuthoredTargets();
        expect(
          (await directReactionProjection.readAuthoredTargets()).map(
            (row) => row['id'],
          ),
          <String?>['outgoing'],
        );

        await repo.deleteMessage('outgoing');
        expect(await directReactionProjection.readAuthoredTargets(), isEmpty);
      },
    );

    test('messageExists returns false for non-existing message', () async {
      expect(await repo.messageExists('nonexistent'), false);
    });

    test('getMessagesPage returns most recent page', () async {
      for (var i = 1; i <= 5; i++) {
        await repo.saveMessage(
          makeMessage(
            id: 'msg-$i',
            timestamp: '2026-02-09T${10 + i}:00:00.000Z',
          ),
        );
      }

      final page = await repo.getMessagesPage('contact-peer', limit: 3);
      expect(page.length, 3);
      expect(page[0].id, 'msg-3');
      expect(page[1].id, 'msg-4');
      expect(page[2].id, 'msg-5');
    });

    test('getMessagesPage returns older page with cursor', () async {
      for (var i = 1; i <= 5; i++) {
        await repo.saveMessage(
          makeMessage(
            id: 'msg-$i',
            timestamp: '2026-02-09T${10 + i}:00:00.000Z',
          ),
        );
      }

      final page = await repo.getMessagesPage(
        'contact-peer',
        limit: 3,
        beforeTimestamp: '2026-02-09T13:00:00.000Z',
      );
      expect(page.length, 2);
      expect(page[0].id, 'msg-1');
      expect(page[1].id, 'msg-2');
    });
  });

  group('Plan 355 private terminal publication', () {
    ConversationMessage privateParent({
      required String id,
      PrivateMediaLifecycleState state = PrivateMediaLifecycleState.available,
      String? hiddenAt,
      String? deletedAt,
    }) => ConversationMessage(
      id: id,
      contactPeerId: 'peer-private',
      senderPeerId: 'peer-private',
      text: '',
      timestamp: '2026-08-10T19:00:00.000Z',
      status: 'delivered',
      isIncoming: true,
      createdAt: '2026-08-10T19:00:00.000Z',
      hiddenAt: hiddenAt,
      deletedAt: deletedAt,
      deletedByPeerId: deletedAt == null ? null : 'peer-private',
      privateMediaPolicy: const PrivateMediaPolicy.protected(),
      privateMediaState: state,
    );

    MediaAttachment attachmentFor(String messageId) => MediaAttachment(
      id: '$messageId-a',
      messageId: messageId,
      mime: 'image/jpeg',
      size: 13,
      mediaType: 'image',
      downloadStatus: 'pending',
      createdAt: '2026-08-10T19:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );

    test('TC-355-04c private terminal publication emits no message', () async {
      // Consumed and expired are terminal too: publishing behind them would
      // push stale private media into an open conversation stream.
      for (final terminal in const <PrivateMediaLifecycleState>[
        PrivateMediaLifecycleState.consumed,
        PrivateMediaLifecycleState.expired,
      ]) {
        final id = 'private-terminal-${terminal.wireValue}';
        final parent = privateParent(id: id, state: terminal);
        await repo.saveMessage(parent);
        final emitted = <ConversationMessage>[];
        final sub = repo.messageChanges.listen(emitted.add);
        addTearDown(sub.cancel);

        expect(
          await repo.publishIncomingDirectMediaMessage(
            message: parent,
            attachments: <MediaAttachment>[attachmentFor(id)],
          ),
          StrictIncomingMediaPublicationDisposition.durablySuperseded,
          reason: terminal.wireValue,
        );
        await Future<void>.delayed(Duration.zero);
        expect(emitted, isEmpty, reason: terminal.wireValue);
      }

      // Deleted and hidden keep their existing suppression.
      for (final suppressed in <String, ConversationMessage>{
        'deleted': privateParent(
          id: 'private-terminal-deleted',
          deletedAt: '2026-08-10T19:05:00.000Z',
        ),
        'hidden': privateParent(
          id: 'private-terminal-hidden',
          hiddenAt: '2026-08-10T19:05:00.000Z',
        ),
      }.entries) {
        await repo.saveMessage(suppressed.value);
        expect(
          await repo.publishIncomingDirectMediaMessage(
            message: suppressed.value,
            attachments: <MediaAttachment>[attachmentFor(suppressed.value.id)],
          ),
          StrictIncomingMediaPublicationDisposition.durablySuperseded,
          reason: suppressed.key,
        );
      }

      // An ACTIVE private parent still publishes exactly once.
      const activeId = 'private-active';
      final active = privateParent(id: activeId);
      await repo.saveMessage(active);
      final activeEmitted = <ConversationMessage>[];
      final activeSub = repo.messageChanges.listen(activeEmitted.add);
      addTearDown(activeSub.cancel);
      expect(
        await repo.publishIncomingDirectMediaMessage(
          message: active,
          attachments: <MediaAttachment>[attachmentFor(activeId)],
        ),
        StrictIncomingMediaPublicationDisposition.published,
      );
      await Future<void>.delayed(Duration.zero);
      expect(activeEmitted, hasLength(1));
      expect(activeEmitted.single.id, activeId);
      expect(activeEmitted.single.media, hasLength(1));
    });
  });

  group('Plan 356 private deletion custody publication', () {
    ConversationMessage privateParent(String id) => ConversationMessage(
      id: id,
      contactPeerId: 'peer-private',
      senderPeerId: 'peer-self',
      text: 'private',
      timestamp: '2026-08-10T19:00:00.000Z',
      status: 'delivered',
      isIncoming: false,
      createdAt: '2026-08-10T19:00:00.000Z',
      privateMediaPolicy: const PrivateMediaPolicy.protected(),
    );

    test('TC-356-01c repository returns exact private deletion custody after '
        'atomic commit', () async {
      const messageId = 'tc356-01c-private';
      const eventId = '35600000-0000-4000-8000-00000000010c';
      const envelope =
          '{"type":"message_deletion","version":"2","eventId":"$eventId",'
          '"senderPeerId":"peer-self",'
          '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
      final expected = privateParent(messageId);
      final tombstone = expected.copyWith(
        text: '',
        status: 'sending',
        deletedAt: '2026-08-10T19:00:01.000Z',
        deletedByPeerId: 'peer-self',
        wireEnvelope: envelope,
      );
      final committedRow = <String, Object?>{...tombstone.toMap(), 'text': ''};

      // The capability is fail-closed: a repository without the DB delegate
      // refuses instead of silently committing a tombstone-only row.
      expect(repo.supportsDirectPrivateDeletionInboxCustody, isTrue);

      nextPrivateDeletionStage = DbDirectPrivateDeletionCustodyStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.applied,
        messageRow: committedRow,
        custodyRow: <String, Object?>{
          'recipient_peer_id': 'peer-private',
          'event_id': eventId,
          'wire_envelope': envelope,
          'retry_count': 0,
          'last_attempt_at': null,
          'last_error_code': null,
          'created_at': '2026-08-10T19:00:00.000Z',
          'updated_at': '2026-08-10T19:00:00.000Z',
        },
      );
      // The parent is physically gone by the time any post-commit publication
      // reload could run: committed custody must survive that anyway.
      store.remove(messageId);

      final staged = await repo.stageOutgoingDirectPrivateDeletionInboxCustody(
        expected: expected,
        tombstone: tombstone,
        recipientPeerId: 'peer-private',
        eventId: eventId,
        wireEnvelope: envelope,
      );

      expect(privateDeletionStageCallCount, 1);
      expect(lastPrivateDeletionStageArgs?.eventId, eventId);
      expect(lastPrivateDeletionStageArgs?.recipientPeerId, 'peer-private');
      expect(
        lastPrivateDeletionStageArgs?.tombstoneRow['wire_envelope'],
        envelope,
      );
      expect(staged.authorizesTransport, isTrue);
      expect(staged.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect(staged.custody?.eventId, eventId);
      expect(staged.custody?.wireEnvelope, envelope);
      expect(staged.message?.id, messageId);
      expect(staged.message?.isDeleted, isTrue);

      // A refusal returns neither a message nor custody.
      nextPrivateDeletionStage =
          const DbDirectPrivateDeletionCustodyStageResult.refused();
      final refused = await repo.stageOutgoingDirectPrivateDeletionInboxCustody(
        expected: expected,
        tombstone: tombstone,
        recipientPeerId: 'peer-private',
        eventId: eventId,
        wireEnvelope: envelope,
      );
      expect(refused.authorizesTransport, isFalse);
      expect(refused.message, isNull);
      expect(refused.custody, isNull);

      // Crossed identity never reaches storage at all.
      final crossed = await repo.stageOutgoingDirectPrivateDeletionInboxCustody(
        expected: expected,
        tombstone: tombstone.copyWith(id: 'other-message'),
        recipientPeerId: 'peer-private',
        eventId: eventId,
        wireEnvelope: envelope,
      );
      expect(crossed.authorizesTransport, isFalse);
      expect(privateDeletionStageCallCount, 2);
    });
  });

  test('TC-366-01b message repository forwards plural private Barrier B without '
      'singular collapse', () async {
    const messageId = 'tc366-01b-private-fanout';
    const senderTransportPeerId = 'peer-self-device';
    const contactAccountPeerId = 'peer-contact-account';
    const pendingLocalPath = '/private/tc366-01b.pending';
    const completedAttachment = MediaAttachment(
      id: 'tc366-01b-attachment',
      messageId: messageId,
      mime: 'image/jpeg',
      size: 366,
      mediaType: 'image',
      localPath: '/private/tc366-01b.enc',
      downloadStatus: 'done',
      createdAt: '2026-08-14T12:00:00.000Z',
      contentHash:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      ownerLane: MediaOwnerLane.direct,
    );
    const snapshot = DirectContactFanoutSnapshot(
      contactAccountPeerId: contactAccountPeerId,
      contactAccountSigningPublicKey: 'contact-signing-key',
      rosterInitialized: true,
      targets: <DirectContactFanoutTargetFact>[
        DirectContactFanoutTargetFact(
          peerId: 'peer-device-a',
          mlKemPublicKey: 'mlkem-device-a',
          isLegacyAccountTarget: false,
          fingerprint:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          deviceId: 'device-a',
        ),
        DirectContactFanoutTargetFact(
          peerId: 'peer-device-b',
          mlKemPublicKey: 'mlkem-device-b',
          isLegacyAccountTarget: false,
          fingerprint:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          deviceId: 'device-b',
        ),
      ],
    );
    final targetBindings = <DirectPrivateMediaFanoutTargetBinding>[
      const DirectPrivateMediaFanoutTargetBinding(
        recipientPeerId: 'peer-device-a',
        recipientMlKemPublicKey: 'mlkem-device-a',
        wireEnvelope: 'wire-envelope-a',
        wireMediaBlobManifestHash:
            '1111111111111111111111111111111111111111111111111111111111111111',
        wireMediaBlobExpiresAtMs: 1770000000001,
      ),
      const DirectPrivateMediaFanoutTargetBinding(
        recipientPeerId: 'peer-device-b',
        recipientMlKemPublicKey: 'mlkem-device-b',
        wireEnvelope: 'wire-envelope-b',
        wireMediaBlobManifestHash:
            '2222222222222222222222222222222222222222222222222222222222222222',
        wireMediaBlobExpiresAtMs: 1770000000002,
      ),
    ];
    Map<String, Object?> custodyRow(
      DirectPrivateMediaFanoutTargetBinding binding,
      String incarnationId,
    ) => <String, Object?>{
      'recipient_peer_id': binding.recipientPeerId,
      'message_id': messageId,
      'incarnation_id': incarnationId,
      'wire_envelope': binding.wireEnvelope,
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'media_blob_manifest_hash': binding.wireMediaBlobManifestHash,
      'media_blob_expires_at_ms': binding.wireMediaBlobExpiresAtMs,
      'contact_account_peer_id': contactAccountPeerId,
      'created_at': '2026-08-14T12:00:01.000Z',
      'updated_at': '2026-08-14T12:00:01.000Z',
    };

    store[messageId] = makeMessage(
      id: messageId,
      contactPeerId: contactAccountPeerId,
      senderPeerId: senderTransportPeerId,
      status: 'sending',
    ).toMap();
    nextPrivateFanoutBarrierResult =
        OutgoingDirectPrivateFanoutInboxCustodyDbResult(
          outcome: OutgoingDirectPrivateEnvelopeHandoffOutcome.committed,
          custodyRows: <Map<String, Object?>>[
            custodyRow(targetBindings[0], 'incarnation-a'),
            custodyRow(targetBindings[1], 'incarnation-b'),
          ],
        );

    Future<OutgoingDirectPrivateFanoutInboxCustodyResult> commit({
      DirectPrivateMediaFanoutStageAuthority authority =
          DirectPrivateMediaFanoutStageAuthority.currentRosterSnapshot,
      DirectContactFanoutSnapshot? expectedSnapshot = snapshot,
      List<DirectPrivateMediaFanoutTargetBinding>? bindings,
    }) => repo.commitOutgoingDirectPrivateWireEnvelopeFanoutWithInboxCustody(
      messageId: messageId,
      completedAttachment: completedAttachment,
      expectedPendingLocalPath: pendingLocalPath,
      hasOwnedPendingCompletion: true,
      senderTransportPeerId: senderTransportPeerId,
      contactAccountPeerId: contactAccountPeerId,
      authority: authority,
      expectedSnapshot: expectedSnapshot,
      targetBindings: bindings ?? targetBindings,
    );

    expect(repo.supportsOutgoingDirectPrivateMediaFanoutInboxCustody, isTrue);
    final committed = await commit();

    expect(privateFanoutBarrierCallCount, 1);
    final forwarded = lastPrivateFanoutBarrierArgs!;
    expect(
      forwarded.completionRow,
      completedAttachment.copyWith(ownerLane: MediaOwnerLane.direct).toMap(),
    );
    expect(forwarded.expectedPendingLocalPath, pendingLocalPath);
    expect(forwarded.hasOwnedPendingCompletion, isTrue);
    expect(forwarded.senderTransportPeerId, senderTransportPeerId);
    expect(forwarded.contactAccountPeerId, contactAccountPeerId);
    expect(
      forwarded.authority,
      DirectPrivateMediaFanoutStageAuthority.currentRosterSnapshot,
    );
    expect(forwarded.expectedSnapshot, same(snapshot));
    expect(forwarded.targetBindings, same(targetBindings));
    expect(
      forwarded.targetBindings.map((binding) => binding.recipientPeerId),
      <String>['peer-device-a', 'peer-device-b'],
    );
    expect(committed.authorizesTransport, isTrue);
    expect(
      committed.outcome,
      OutgoingDirectPrivateEnvelopeHandoffOutcome.committed,
    );
    expect(committed.custodies, hasLength(2));
    expect(
      committed.custodies.map((custody) => custody.recipientPeerId),
      <String>['peer-device-a', 'peer-device-b'],
    );
    expect(
      committed.custodies.map((custody) => custody.incarnationId),
      <String>['incarnation-a', 'incarnation-b'],
    );
    expect(committed.custodies.map((custody) => custody.wireEnvelope), <String>[
      'wire-envelope-a',
      'wire-envelope-b',
    ]);
    expect(dbLoadMessageCallCount, 1, reason: 'refresh the parent cache once');

    nextPrivateFanoutBarrierResult =
        OutgoingDirectPrivateFanoutInboxCustodyDbResult(
          outcome: OutgoingDirectPrivateEnvelopeHandoffOutcome.committed,
          custodyRows: <Map<String, Object?>>[
            custodyRow(targetBindings[0], 'partial-incarnation-a'),
          ],
        );
    final partial = await commit();
    expect(partial.authorizesTransport, isFalse);
    expect(partial.custodies, isEmpty);
    expect(privateFanoutBarrierCallCount, 2);
    expect(dbLoadMessageCallCount, 1);

    nextPrivateFanoutBarrierResult =
        OutgoingDirectPrivateFanoutInboxCustodyDbResult(
          outcome: OutgoingDirectPrivateEnvelopeHandoffOutcome.committed,
          custodyRows: <Map<String, Object?>>[
            custodyRow(targetBindings[0], 'malformed-incarnation-a'),
            <String, Object?>{
              ...custodyRow(targetBindings[1], 'malformed-incarnation-b'),
              'incarnation_id': null,
            },
          ],
        );
    final malformed = await commit();
    expect(malformed.authorizesTransport, isFalse);
    expect(malformed.custodies, isEmpty);
    expect(privateFanoutBarrierCallCount, 3);
    expect(dbLoadMessageCallCount, 1);

    final duplicateTargets = <DirectPrivateMediaFanoutTargetBinding>[
      targetBindings[0],
      targetBindings[0],
    ];
    final duplicate = await commit(
      authority: DirectPrivateMediaFanoutStageAuthority.persistedV114Survivors,
      expectedSnapshot: null,
      bindings: duplicateTargets,
    );
    expect(duplicate.authorizesTransport, isFalse);
    expect(duplicate.custodies, isEmpty);
    expect(
      privateFanoutBarrierCallCount,
      3,
      reason: 'duplicate physical targets must fail before the DB delegate',
    );
    expect(dbLoadMessageCallCount, 1);
  });

  test('TC-361-02a the fanout capability is all-or-nothing and the adapters '
      'delegate exactly', () async {
    expect(
      repo.supportsDirectEventFanout,
      isFalse,
      reason: 'a repository lacking any fanout delegate must fail closed',
    );

    var snapshotCalls = 0;
    var textStageCalls = 0;
    var mutationStageCalls = 0;
    const snapshot = DirectContactFanoutSnapshot(
      contactAccountPeerId: 'peer-contact',
      contactAccountSigningPublicKey: 'signing-key',
      rosterInitialized: true,
      targets: <DirectContactFanoutTargetFact>[
        DirectContactFanoutTargetFact(
          peerId: 'peer-device-a',
          mlKemPublicKey: 'mlkem-a',
          isLegacyAccountTarget: false,
          fingerprint:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
          deviceId: 'device-a',
        ),
      ],
    );
    final fanoutRepo = MessageRepositoryImpl(
      dbInsertMessage: (row) async {},
      dbLoadMessagesForContact: (_) async => const [],
      dbLoadLatestMessageForContact: (_) async => null,
      dbUpdateMessageStatus: (_, _) async => 0,
      dbLoadMessage: (_) async => null,
      dbCountMessagesForContact: (_) async => 0,
      dbMarkConversationAsRead: (_) async => 0,
      dbCountUnreadForContact: (_) async => 0,
      dbCountTotalUnread: () async => 0,
      dbCountTotalUnreadExcludingArchived: () async => 0,
      dbDeleteMessagesForContact: (_) async => 0,
      dbDeleteMessage: (_) async => 0,
      dbExistsMessageByContent: (_, _, _, _) async => false,
      dbLoadMessagesPage: (_, {limit = 50, beforeTimestamp}) async => const [],
      dbLoadFailedOutgoingMessages: () async => const [],
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) async =>
          const [],
      dbLoadConversationThreadSummaries: (_) async => const [],
      dbRecoverStuckSendingMessages: ({required olderThan, limit = 50}) async =>
          0,
      dbLoadStuckSendingOutgoingMessages:
          ({required olderThan, limit = 50}) async => const [],
      dbLoadSendingOutgoingMessages: () async => const [],
      dbConditionalTransitionStatus:
          (_, {required fromStatus, required toStatus}) async => 0,
      dbStageOutgoingDirectTextInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required recipientPeerId,
            required messageId,
            required incarnationId,
            required wireEnvelope,
          }) async => OutgoingOrdinaryMutationOutcome.refused,
      dbLoadDirectInboxCustodyOutbox: ({limit = 50}) async => const [],
      dbLoadDirectInboxCustodyOutboxForMessage:
          ({required recipientPeerId, required messageId}) async => null,
      dbLoadDirectInboxCustodyOutboxOwnerForMessageId:
          ({required messageId}) async => null,
      dbRecordDirectInboxCustodyFailureIfExact:
          ({
            required recipientPeerId,
            required messageId,
            required expectedIncarnationId,
            required expectedWireEnvelope,
            required errorCode,
            required attemptedAt,
          }) async => false,
      dbCompleteAcceptedDirectInboxCustodyIfExact:
          ({
            required recipientPeerId,
            required messageId,
            required expectedIncarnationId,
            required expectedWireEnvelope,
            required relayExpiresAt,
          }) async => DirectInboxCustodyCompletionOutcome.stale,
      dbStageOutgoingDirectTextMutationInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required recipientPeerId,
            required eventId,
            required wireEnvelope,
          }) async => const DbDirectTextMutationCustodyStageResult(
            outcome: OutgoingOrdinaryMutationOutcome.refused,
            custodyRow: null,
          ),
      dbLoadDirectTextMutationInboxCustodyForEvent:
          ({required recipientPeerId, required eventId}) async => null,
      dbRecordDirectTextMutationInboxCustodyFailureIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
            required errorCode,
            required attemptedAt,
          }) async => false,
      dbCompleteAcceptedDirectTextMutationInboxCustodyIfExact:
          ({
            required recipientPeerId,
            required eventId,
            required expectedWireEnvelope,
            required relayExpiresAt,
          }) async => DirectMutationInboxCustodyCompletionOutcome.stale,
      dbReadDirectContactFanoutSnapshot:
          ({required contactAccountPeerId}) async {
            snapshotCalls++;
            return snapshot;
          },
      dbLoadDirectInboxCustodyOutboxRowsForMessageId:
          ({required messageId}) async => const [],
      dbLoadDirectReactionInboxCustodyOutboxRowsForEventId:
          ({required eventId}) async => const [],
      dbStageOutgoingDirectTextFanoutInboxCustody:
          ({
            required stagedRow,
            required messageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) async {
            textStageCalls++;
            return const DbDirectEventFanoutStageResult(
              outcome: DirectEventFanoutStageOutcome.terminal,
              rows: <Map<String, Object?>>[],
            );
          },
      dbStageOutgoingDirectTextMutationFanoutInboxCustody:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required eventId,
            required parentMessageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) async {
            mutationStageCalls++;
            return const DbDirectEventFanoutStageResult.refused();
          },
    );

    expect(fanoutRepo.supportsDirectEventFanout, isTrue);
    expect(
      await fanoutRepo.readDirectContactFanoutSnapshot('peer-contact'),
      same(snapshot),
    );
    expect(snapshotCalls, 1);
    final stagedText = await fanoutRepo.stageDirectTextFanout(
      stagedRow: const <String, Object?>{},
      messageId: 'm1',
      contactAccountPeerId: 'peer-contact',
      senderTransportPeerId: 'peer-self',
      expectedSnapshot: snapshot,
      candidates: const <DirectEventFanoutTargetCandidate>[],
    );
    expect(stagedText.outcome, DirectEventFanoutStageOutcome.terminal);
    expect(textStageCalls, 1);
    final stagedMutation = await fanoutRepo.stageDirectTextMutationFanout(
      expectedRow: null,
      stagedRow: const <String, Object?>{},
      kind: OutgoingOrdinaryAttemptKind.edit,
      eventId: 'e1',
      parentMessageId: 'm1',
      contactAccountPeerId: 'peer-contact',
      senderTransportPeerId: 'peer-self',
      expectedSnapshot: snapshot,
      candidates: const <DirectEventFanoutTargetCandidate>[],
    );
    expect(stagedMutation.outcome, DirectEventFanoutStageOutcome.refused);
    expect(mutationStageCalls, 1);
  });
}

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
