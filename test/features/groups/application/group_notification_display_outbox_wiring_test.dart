import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_notification_display_retry_coordinator.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_reaction.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_notification_display_outbox_repository.dart';

import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_pending_reaction_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

const _groupId = 'group-outbox';
const _selfPeerId = 'peer-self';
const _senderPeerId = 'peer-sender';
final _createdAt = DateTime.utc(2026, 8, 3, 10);
const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

List<Map<String, dynamic>> _mediaDescriptor(String id, DateTime createdAt) => [
  {
    'id': id,
    'mime': 'image/png',
    'size': 4096,
    'mediaType': 'image',
    'contentHash': _contentHash,
    'encryptionKeyBase64': 'group-outbox-key',
    'encryptionNonce': 'group-outbox-nonce',
    'encryptionScheme': 'blob_aes_256_gcm_v1',
    'downloadStatus': 'pending',
    'createdAt': createdAt.toUtc().toIso8601String(),
  },
];

final class _MemoryNotificationDisplayOutbox
    implements GroupNotificationDisplayOutboxRepository {
  final Map<String, GroupNotificationDisplayOutboxEntry> entries = {};
  final List<String> operations = [];
  final List<GroupNotificationDisplayOutboxEntry> completionAttempts = [];
  final List<NotificationCompletedOutcomeCandidate?> completionOutcomes = [];
  Future<void> Function(GroupNotificationDisplayOutboxEntry entry)? onStage;
  Future<void> Function(GroupNotificationDisplayOutboxEntry entry)? onComplete;
  bool rejectRetryCas = false;

  void seedReady(GroupNotificationDisplayOutboxEntry entry) {
    entries[entry.eventId] = entry.copyWith(
      readiness: GroupNotificationDisplayOutboxReadiness.ready,
    );
  }

  @override
  Future<void> stage(GroupNotificationDisplayOutboxEntry entry) async {
    operations.add('stage:${entry.eventId}:${entry.readiness}');
    await onStage?.call(entry);
    final current = entries[entry.eventId];
    if (current == null) {
      entries[entry.eventId] = entry;
      return;
    }
    if (current.eventKind != entry.eventKind ||
        current.groupId != entry.groupId ||
        current.messageId != entry.messageId ||
        current.actorPeerId != entry.actorPeerId ||
        current.eventTimestamp != entry.eventTimestamp ||
        current.reactionId != entry.reactionId ||
        current.reactionAction != entry.reactionAction ||
        current.reactionTombstone != entry.reactionTombstone) {
      throw StateError('conflicting notification transition event id');
    }
  }

  @override
  Future<GroupNotificationDisplayOutboxEntry?> loadByEventId(
    String eventId,
  ) async => entries[eventId];

  @override
  Future<bool> promoteReadyIfExact({
    required String eventId,
    required int expectedRevision,
  }) async {
    operations.add('promote:$eventId:$expectedRevision');
    final current = entries[eventId];
    if (current == null || current.revision != expectedRevision) return false;
    entries[eventId] = current.copyWith(
      readiness: GroupNotificationDisplayOutboxReadiness.ready,
      revision: current.revision + 1,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    return true;
  }

  @override
  Future<List<GroupNotificationDisplayOutboxEntry>> loadReady({
    int limit = 20,
  }) async =>
      entries.values.where((entry) => entry.isReady).take(limit).toList();

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async {
    final attempts = entries.values
        .where((entry) => entry.isReady && entry.nextAttemptAt != null)
        .map((entry) => DateTime.parse(entry.nextAttemptAt!).toUtc())
        .toList(growable: false);
    if (attempts.isEmpty) return null;
    return attempts.reduce(
      (left, right) => left.isBefore(right) ? left : right,
    );
  }

  @override
  Future<bool> recordRetryIfExact({
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  }) async {
    operations.add('retry:$eventId:$expectedRevision:$lastErrorCode');
    if (rejectRetryCas) return false;
    final current = entries[eventId];
    if (current == null || current.revision != expectedRevision) return false;
    final now = DateTime.now().toUtc().toIso8601String();
    entries[eventId] = current.copyWith(
      revision: current.revision + 1,
      retryCount: current.retryCount + 1,
      lastErrorCode: lastErrorCode,
      lastAttemptAt: now,
      nextAttemptAt: nextAttemptAt.toUtc().toIso8601String(),
      updatedAt: now,
    );
    return true;
  }

  @override
  Future<bool> completeIfExact(
    GroupNotificationDisplayOutboxEntry expected, {
    NotificationCompletedOutcomeCandidate? outcome,
  }) async {
    operations.add('complete:${expected.eventId}:${expected.revision}');
    completionAttempts.add(expected);
    completionOutcomes.add(outcome);
    await onComplete?.call(expected);
    final current = entries[expected.eventId];
    if (current == null ||
        current.revision != expected.revision ||
        current.eventKind != expected.eventKind ||
        current.groupId != expected.groupId ||
        current.messageId != expected.messageId ||
        current.actorPeerId != expected.actorPeerId ||
        current.eventTimestamp != expected.eventTimestamp ||
        current.reactionId != expected.reactionId ||
        current.reactionAction != expected.reactionAction ||
        current.reactionTombstone != expected.reactionTombstone) {
      return false;
    }
    entries.remove(expected.eventId);
    return true;
  }

  @override
  Future<bool> retireIfExact(
    GroupNotificationDisplayOutboxEntry expected,
  ) async {
    operations.add('retire:${expected.eventId}:${expected.revision}');
    final current = entries[expected.eventId];
    if (current == null ||
        current.revision != expected.revision ||
        current.eventKind != expected.eventKind ||
        current.groupId != expected.groupId ||
        current.messageId != expected.messageId ||
        current.actorPeerId != expected.actorPeerId ||
        current.eventTimestamp != expected.eventTimestamp ||
        current.reactionId != expected.reactionId ||
        current.reactionAction != expected.reactionAction ||
        current.reactionTombstone != expected.reactionTombstone) {
      return false;
    }
    entries.remove(expected.eventId);
    return true;
  }

  @override
  Future<bool> reconcileMessageAliasReady({
    required String aliasEventId,
    required GroupMessage canonicalMessage,
  }) async {
    operations.add('reconcile:$aliasEventId:${canonicalMessage.id}');
    final canonical = entries[canonicalMessage.id];
    final alias = entries[aliasEventId];
    if (canonical == null && alias == null) return false;
    if (canonical != null) {
      entries[canonicalMessage.id] = canonical.isReady
          ? canonical
          : canonical.copyWith(
              readiness: GroupNotificationDisplayOutboxReadiness.ready,
              revision: canonical.revision + 1,
              lastErrorCode: null,
              lastAttemptAt: null,
              nextAttemptAt: null,
            );
      if (aliasEventId != canonicalMessage.id) entries.remove(aliasEventId);
      return true;
    }
    entries.remove(aliasEventId);
    entries[canonicalMessage.id] = alias!.copyWith(
      eventId: canonicalMessage.id,
      messageId: canonicalMessage.id,
      readiness: GroupNotificationDisplayOutboxReadiness.ready,
      revision: alias.revision + 1,
      lastErrorCode: null,
      lastAttemptAt: null,
      nextAttemptAt: null,
    );
    return true;
  }

  @override
  Future<int> deleteForGroup(String groupId) async {
    final before = entries.length;
    entries.removeWhere((_, entry) => entry.groupId == groupId);
    return before - entries.length;
  }

  @override
  Future<int> deleteForMessage({
    required String groupId,
    required String messageId,
  }) async {
    final before = entries.length;
    entries.removeWhere(
      (_, entry) => entry.groupId == groupId && entry.messageId == messageId,
    );
    return before - entries.length;
  }

  @override
  Future<int> deleteForReaction({
    required String groupId,
    required String messageId,
    required String reactionId,
  }) async {
    final before = entries.length;
    entries.removeWhere(
      (_, entry) =>
          entry.groupId == groupId &&
          entry.messageId == messageId &&
          entry.reactionId == reactionId,
    );
    return before - entries.length;
  }

  @override
  Future<int> deleteForReactionActor({
    required String groupId,
    required String messageId,
    required String actorPeerId,
  }) async {
    final before = entries.length;
    entries.removeWhere(
      (_, entry) =>
          entry.groupId == groupId &&
          entry.messageId == messageId &&
          entry.actorPeerId == actorPeerId &&
          entry.eventKind == GroupNotificationDisplayOutboxKind.reaction,
    );
    return before - entries.length;
  }
}

final class _FaultingNotificationService extends FakeNotificationService
    implements ConversationNotificationCancellation {
  int failuresRemaining;
  int showAttempts = 0;
  final cancelledConversationKeys = <String>[];

  _FaultingNotificationService({this.failuresRemaining = 0});

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
  }) async {
    showAttempts++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('simulated notification plugin failure');
    }
    await super.showMessageNotification(
      contactPeerId: contactPeerId,
      senderUsername: senderUsername,
      messageText: messageText,
      payload: payload,
      silent: silent,
      contentKind: contentKind,
      contentEventIdentity: contentEventIdentity,
      snapshot: snapshot,
    );
  }

  @override
  Future<void> cancelConversationNotification(
    String conversationKey, {
    ConversationNotificationContentKind? onlyIfContentKind,
    ConversationNotificationContentCancellationPredicate? shouldCancelContent,
  }) async {
    if (onlyIfContentKind == null ||
        onlyIfContentKind == ConversationNotificationContentKind.message) {
      cancelledConversationKeys.add(conversationKey);
    }
  }
}

final class _TrackingUnreadGroupMessageRepository
    extends InMemoryGroupMessageRepository {
  int unreadQueries = 0;

  @override
  Future<int> getUnreadCount(String groupId) async {
    unreadQueries++;
    return super.getUnreadCount(groupId);
  }
}

final class _NoopRecentRemoteNotificationGate
    extends RecentRemoteNotificationGate {
  _NoopRecentRemoteNotificationGate()
    : super(filePath: '${Directory.systemTemp.path}/unused-group-outbox-gate');

  @override
  Future<bool> consumeIfRecentAnnouncement({
    required String payload,
    String? messageId,
  }) async => false;

  @override
  Future<void> markAnnouncement({
    required String payload,
    String? messageId,
  }) async {}
}

final class _Fixture {
  _Fixture({
    required this.groupRepo,
    required this.messageRepo,
    required this.reactionRepo,
    required this.outbox,
    required this.notifications,
    required this.mediaRepo,
    required this.listener,
  });

  final InMemoryGroupRepository groupRepo;
  final InMemoryGroupMessageRepository messageRepo;
  final FakeReactionRepository reactionRepo;
  final _MemoryNotificationDisplayOutbox outbox;
  final _FaultingNotificationService notifications;
  final InMemoryMediaAttachmentRepository mediaRepo;
  final GroupMessageListener listener;
}

GroupModel _group({
  GroupType type = GroupType.chat,
  bool isMuted = false,
  bool isArchived = false,
  bool isDissolved = false,
  DateTime? dissolvedAt,
  DateTime? selfRemovedAt,
}) => GroupModel(
  id: _groupId,
  name: 'Reliable Group',
  type: type,
  topicName: 'topic-reliable-group',
  createdAt: _createdAt,
  createdBy: 'peer-admin',
  myRole: GroupRole.member,
  isMuted: isMuted,
  isArchived: isArchived,
  isDissolved: isDissolved,
  dissolvedAt: dissolvedAt,
  selfRemovedAt: selfRemovedAt,
);

GroupMessage _incomingMessage({
  required String id,
  DateTime? timestamp,
  DateTime? readAt,
}) {
  final sentAt = timestamp ?? DateTime.utc(2026, 8, 3, 10, 1);
  return GroupMessage(
    id: id,
    groupId: _groupId,
    senderPeerId: _senderPeerId,
    senderUsername: 'Sender',
    text: 'Durable notification',
    timestamp: sentAt,
    isIncoming: true,
    readAt: readAt,
    createdAt: sentAt,
  );
}

GroupMessage _selfAuthoredTarget(String id) {
  final sentAt = DateTime.utc(2026, 8, 3, 10, 2);
  return GroupMessage(
    id: id,
    groupId: _groupId,
    senderPeerId: _selfPeerId,
    senderUsername: 'Me',
    text: 'Target',
    timestamp: sentAt,
    isIncoming: false,
    createdAt: sentAt,
  );
}

GroupNotificationDisplayOutboxEntry _readyMessageEntry(
  GroupMessage message, {
  String? eventId,
}) {
  final now = _createdAt.toIso8601String();
  return GroupNotificationDisplayOutboxEntry.message(
    eventId: eventId ?? message.id,
    groupId: message.groupId,
    messageId: message.id,
    actorPeerId: message.senderPeerId,
    eventTimestamp: message.timestamp.toUtc().toIso8601String(),
    readiness: GroupNotificationDisplayOutboxReadiness.ready,
    createdAt: now,
    updatedAt: now,
  );
}

GroupNotificationDisplayOutboxEntry _readyReactionEntry({
  required String eventId,
  required String messageId,
  String reactionId = 'reaction-state',
  String reactionAction = 'add',
  bool reactionTombstone = false,
  String timestamp = '2026-08-03T10:03:00.000Z',
}) {
  final now = _createdAt.toIso8601String();
  return GroupNotificationDisplayOutboxEntry.reaction(
    eventId: eventId,
    groupId: _groupId,
    messageId: messageId,
    actorPeerId: _senderPeerId,
    eventTimestamp: timestamp,
    reactionId: reactionId,
    reactionAction: reactionAction,
    reactionTombstone: reactionTombstone,
    readiness: GroupNotificationDisplayOutboxReadiness.ready,
    createdAt: now,
    updatedAt: now,
  );
}

Future<_Fixture> _buildFixture({
  GroupModel? group,
  InMemoryGroupMessageRepository? messageRepo,
  FakeReactionRepository? reactionRepo,
  InMemoryGroupPendingReactionRepository? pendingReactionRepo,
  _MemoryNotificationDisplayOutbox? outbox,
  _FaultingNotificationService? notifications,
  InMemoryMediaAttachmentRepository? mediaRepo,
  Future<DurableNotificationToneLease> Function()? durableResolver,
  Future<String?> Function()? getSelfPeerId,
  Future<String?> Function()? resolveCompletedOutcomePhysicalPeerId,
  bool completedOutcomeProducerEnabled = false,
  GroupNotificationEventAcknowledgedResolver?
  isGroupNotificationEventAcknowledged,
}) async {
  final groups = InMemoryGroupRepository();
  final messages = messageRepo ?? InMemoryGroupMessageRepository();
  final reactions = reactionRepo ?? FakeReactionRepository();
  final displayOutbox = outbox ?? _MemoryNotificationDisplayOutbox();
  final notificationService = notifications ?? _FaultingNotificationService();
  final media = mediaRepo ?? InMemoryMediaAttachmentRepository();
  await groups.saveGroup(group ?? _group());
  await groups.saveMember(
    GroupMember(
      groupId: _groupId,
      peerId: _selfPeerId,
      username: 'Me',
      role: MemberRole.writer,
      joinedAt: _createdAt,
    ),
  );
  await groups.saveMember(
    GroupMember(
      groupId: _groupId,
      peerId: _senderPeerId,
      username: 'Sender',
      role: MemberRole.writer,
      joinedAt: _createdAt,
    ),
  );
  final listener = GroupMessageListener(
    groupRepo: groups,
    msgRepo: messages,
    mediaAttachmentRepo: media,
    reactionRepo: reactions,
    pendingReactionRepo: pendingReactionRepo,
    getSelfPeerId: getSelfPeerId ?? () async => _selfPeerId,
    notificationService: notificationService,
    groupConversationTracker: ActiveConversationTracker(),
    getAppLifecycleState: () => AppLifecycleState.resumed,
    remoteNotificationGate: _NoopRecentRemoteNotificationGate(),
    notificationDisplayOutbox: displayOutbox,
    resolveCompletedOutcomePhysicalPeerId:
        resolveCompletedOutcomePhysicalPeerId,
    completedOutcomeProducerEnabled: completedOutcomeProducerEnabled,
    isGroupNotificationEventAcknowledged: isGroupNotificationEventAcknowledged,
    durableNotificationCoordinatorResolver: durableResolver,
  );
  return _Fixture(
    groupRepo: groups,
    messageRepo: messages,
    reactionRepo: reactions,
    outbox: displayOutbox,
    notifications: notificationService,
    mediaRepo: media,
    listener: listener,
  );
}

Future<void> _seedPendingReaction({
  required InMemoryGroupPendingReactionRepository repository,
  required String messageId,
  required String reactionId,
  required String eventId,
  required DateTime timestamp,
}) async {
  final payload = GroupReactionPayload(
    id: reactionId,
    messageId: messageId,
    emoji: '👍',
    action: GroupReactionPayload.actionAdd,
    senderPeerId: _senderPeerId,
    timestamp: timestamp.toUtc().toIso8601String(),
    eventId: eventId,
  );
  await repository.savePendingReaction(
    GroupPendingReaction(
      id: reactionId,
      groupId: _groupId,
      messageId: messageId,
      senderPeerId: _senderPeerId,
      reactionJson: payload.toInnerJson(),
      receivedAt: timestamp.toUtc(),
      createdAt: timestamp.toUtc(),
      updatedAt: timestamp.toUtc(),
    ),
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'TC-369-02 exact display completion and outcome are one transaction',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'group_outcome_atomic_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final db = await databaseFactoryFfi.openDatabase(
        '${tempDir.path}/identity.db',
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      );
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });
      const completedAt = '2026-08-15T10:00:00.000Z';
      const groupId = 'group-atomic';

      Future<void> insertMessage(String messageId) =>
          db.insert('group_messages', <String, Object?>{
            'id': messageId,
            'group_id': groupId,
            'sender_peer_id': _senderPeerId,
            'text': 'canonical group content',
            'timestamp': completedAt,
            'created_at': completedAt,
          });
      GroupNotificationDisplayOutboxEntry readyEntry(String messageId) =>
          GroupNotificationDisplayOutboxEntry.message(
            eventId: messageId,
            groupId: groupId,
            messageId: messageId,
            actorPeerId: _senderPeerId,
            eventTimestamp: completedAt,
            readiness: GroupNotificationDisplayOutboxReadiness.ready,
            createdAt: completedAt,
            updatedAt: completedAt,
          );
      NotificationCompletedOutcomeCandidate candidate(
        String messageId,
        NotificationCompletedOutcomeCategory outcome,
      ) => NotificationCompletedOutcomeCandidate(
        physicalPeerId: '12D3KooWgroup-physical',
        producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
        eventKey: 'logical-$messageId',
        outcome: outcome,
        completedAt: DateTime.parse(completedAt),
      );
      Future<bool> complete(
        GroupNotificationDisplayOutboxEntry entry,
        NotificationCompletedOutcomeCandidate outcome,
      ) => dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
        db,
        eventId: entry.eventId,
        expectedRevision: entry.revision,
        expectedEventKind: entry.eventKind,
        expectedGroupId: entry.groupId,
        expectedMessageId: entry.messageId,
        expectedActorPeerId: entry.actorPeerId,
        expectedEventTimestamp: entry.eventTimestamp,
        expectedReactionId: entry.reactionId,
        expectedReactionAction: entry.reactionAction,
        expectedReactionTombstone: entry.reactionTombstone,
        completedAt: completedAt,
        outcome: outcome,
      );

      const exactId = 'group-exact-message';
      await insertMessage(exactId);
      final exact = readyEntry(exactId);
      await db.insert('group_notification_display_outbox', exact.toMap());
      expect(
        await complete(
          exact,
          candidate(exactId, NotificationCompletedOutcomeCategory.osPosted),
        ),
        isTrue,
      );
      expect(
        await db.query(
          'group_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[exactId],
        ),
        isEmpty,
      );
      expect(
        (await db.query(
          'group_messages',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>[exactId],
        )).single['notification_display_terminal_event_id'],
        exactId,
      );
      final correlation = tryComputeNotificationCompletedOutcomeCorrelation(
        physicalPeerId: '12D3KooWgroup-physical',
        producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
        eventKey: 'logical-$exactId',
      );
      expect(
        (await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[correlation],
        )).single['outcome'],
        'os_posted',
      );

      await db.insert('group_notification_display_outbox', exact.toMap());
      expect(
        await complete(
          exact,
          candidate(
            exactId,
            NotificationCompletedOutcomeCategory.suppressedPolicy,
          ),
        ),
        isTrue,
      );
      expect(
        (await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[correlation],
        )).single['outcome'],
        'os_posted',
      );

      // A zero-row terminal update is not authority: custody and outcome stay.
      const missingId = 'group-missing-canonical-message';
      final missing = readyEntry(missingId);
      await db.insert('group_notification_display_outbox', missing.toMap());
      expect(
        await complete(
          missing,
          candidate(missingId, NotificationCompletedOutcomeCategory.osPosted),
        ),
        isFalse,
      );
      expect(
        await db.query(
          'group_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[missingId],
        ),
        hasLength(1),
      );
      final missingCorrelation =
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: '12D3KooWgroup-physical',
            producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
            eventKey: 'logical-$missingId',
          );
      expect(
        await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[missingCorrelation],
        ),
        isEmpty,
      );

      Future<void> insertReactionTarget(String messageId) =>
          db.insert('group_messages', <String, Object?>{
            'id': messageId,
            'group_id': groupId,
            'sender_peer_id': _selfPeerId,
            'text': 'self-authored reaction target',
            'timestamp': completedAt,
            'created_at': completedAt,
          });
      Future<void> insertReaction({
        required String reactionId,
        required String messageId,
        String? terminalEventId,
      }) => db.insert('message_reactions', <String, Object?>{
        'id': reactionId,
        'message_id': messageId,
        'emoji': '👍',
        'sender_peer_id': _senderPeerId,
        'timestamp': completedAt,
        'created_at': completedAt,
        'notification_display_terminal_event_id': terminalEventId,
      });
      GroupNotificationDisplayOutboxEntry reactionEntry({
        required String eventId,
        required String messageId,
        required String reactionId,
      }) => GroupNotificationDisplayOutboxEntry.reaction(
        eventId: eventId,
        groupId: groupId,
        messageId: messageId,
        actorPeerId: _senderPeerId,
        eventTimestamp: completedAt,
        reactionId: reactionId,
        reactionAction: GroupReactionPayload.actionAdd,
        reactionTombstone: false,
        readiness: GroupNotificationDisplayOutboxReadiness.ready,
        createdAt: completedAt,
        updatedAt: completedAt,
      );
      NotificationCompletedOutcomeCandidate reactionCandidate(String eventId) =>
          NotificationCompletedOutcomeCandidate(
            physicalPeerId: '12D3KooWgroup-physical',
            producerKind:
                NotificationCompletedOutcomeProducerKind.groupReaction,
            eventKey: eventId,
            outcome: NotificationCompletedOutcomeCategory.osPosted,
            completedAt: DateTime.parse(completedAt),
          );
      Future<void> appendProtectedReactionSource({
        required String eventId,
        required String messageId,
        required String reactionId,
      }) => dbAppendGroupEventLogEntry(
        db,
        groupId: groupId,
        eventType: 'protected_reaction',
        sourcePeerId: _senderPeerId,
        sourceEventId: 'pr1:$eventId',
        sourceTimestamp: completedAt,
        payload: <String, Object?>{
          'custodyKind': 'group_content_v1',
          'groupId': groupId,
          'payloadType': 'group_reaction',
          'contentEventId': eventId,
          'logicalSenderPeerId': _senderPeerId,
          'payload': <String, Object?>{
            'id': reactionId,
            'eventId': eventId,
            'messageId': messageId,
            'senderPeerId': _senderPeerId,
            'action': GroupReactionPayload.actionAdd,
            'timestamp': completedAt,
          },
        },
      );
      Future<bool> completeReaction(
        GroupNotificationDisplayOutboxEntry entry,
      ) => dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
        db,
        eventId: entry.eventId,
        expectedRevision: entry.revision,
        expectedEventKind: entry.eventKind,
        expectedGroupId: entry.groupId,
        expectedMessageId: entry.messageId,
        expectedActorPeerId: entry.actorPeerId,
        expectedEventTimestamp: entry.eventTimestamp,
        expectedReactionId: entry.reactionId,
        expectedReactionAction: entry.reactionAction,
        expectedReactionTombstone: entry.reactionTombstone,
        completedAt: completedAt,
        outcome: reactionCandidate(entry.eventId),
      );

      const reactionTargetId = 'group-exact-reaction-target';
      const reactionId = 'group-exact-reaction-state';
      const reactionEventId = 'group-exact-reaction-transition';
      await insertReactionTarget(reactionTargetId);
      await insertReaction(reactionId: reactionId, messageId: reactionTargetId);
      await appendProtectedReactionSource(
        eventId: reactionEventId,
        messageId: reactionTargetId,
        reactionId: reactionId,
      );
      final exactReaction = reactionEntry(
        eventId: reactionEventId,
        messageId: reactionTargetId,
        reactionId: reactionId,
      );
      await db.insert(
        'group_notification_display_outbox',
        exactReaction.toMap(),
      );
      expect(await completeReaction(exactReaction), isTrue);
      expect(
        (await db.query(
          'message_reactions',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>[reactionId],
        )).single['notification_display_terminal_event_id'],
        boundedReactionEventIdentity(reactionEventId),
      );
      expect(
        await db.query(
          'group_event_log',
          where: 'group_id = ? AND source_event_id = ? AND event_type = ?',
          whereArgs: const <Object?>[
            groupId,
            'prdt1:$reactionEventId',
            'protected_reaction_display_terminal',
          ],
        ),
        hasLength(1),
        reason:
            'the exact protected source must append its durable display terminal',
      );
      final reactionCorrelation =
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: '12D3KooWgroup-physical',
            producerKind:
                NotificationCompletedOutcomeProducerKind.groupReaction,
            eventKey: reactionEventId,
          );
      expect(
        (await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[reactionCorrelation],
        )).single['outcome'],
        'os_posted',
      );
      expect(
        await db.query(
          'group_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[reactionEventId],
        ),
        isEmpty,
      );

      const missingReactionTargetId = 'group-missing-reaction-target';
      const missingReactionId = 'group-missing-reaction-state';
      const missingReactionEventId = 'group-missing-reaction-transition';
      await insertReactionTarget(missingReactionTargetId);
      final missingReaction = reactionEntry(
        eventId: missingReactionEventId,
        messageId: missingReactionTargetId,
        reactionId: missingReactionId,
      );
      await db.insert(
        'group_notification_display_outbox',
        missingReaction.toMap(),
      );
      expect(await completeReaction(missingReaction), isFalse);
      expect(
        await db.query(
          'group_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[missingReactionEventId],
        ),
        hasLength(1),
      );
      expect(
        await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[
            tryComputeNotificationCompletedOutcomeCorrelation(
              physicalPeerId: '12D3KooWgroup-physical',
              producerKind:
                  NotificationCompletedOutcomeProducerKind.groupReaction,
              eventKey: missingReactionEventId,
            ),
          ],
        ),
        isEmpty,
      );

      const staleReactionTargetId = 'group-stale-reaction-target';
      const staleReactionId = 'group-stale-reaction-state';
      const staleReactionEventId = 'group-stale-reaction-transition';
      await insertReactionTarget(staleReactionTargetId);
      await insertReaction(
        reactionId: staleReactionId,
        messageId: staleReactionTargetId,
        terminalEventId: 'newer-reaction-terminal',
      );
      final staleReaction = reactionEntry(
        eventId: staleReactionEventId,
        messageId: staleReactionTargetId,
        reactionId: staleReactionId,
      );
      await db.insert(
        'group_notification_display_outbox',
        staleReaction.toMap(),
      );
      expect(await completeReaction(staleReaction), isFalse);
      expect(
        (await db.query(
          'message_reactions',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>[staleReactionId],
        )).single['notification_display_terminal_event_id'],
        'newer-reaction-terminal',
      );
      expect(
        await db.query(
          'group_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[staleReactionEventId],
        ),
        hasLength(1),
      );

      const faultReactionTargetId = 'group-fault-reaction-target';
      const faultReactionId = 'group-fault-reaction-state';
      const faultReactionEventId = 'group-fault-reaction-transition';
      await insertReactionTarget(faultReactionTargetId);
      await insertReaction(
        reactionId: faultReactionId,
        messageId: faultReactionTargetId,
      );
      await appendProtectedReactionSource(
        eventId: faultReactionEventId,
        messageId: faultReactionTargetId,
        reactionId: faultReactionId,
      );
      final faultReaction = reactionEntry(
        eventId: faultReactionEventId,
        messageId: faultReactionTargetId,
        reactionId: faultReactionId,
      );
      await db.insert(
        'group_notification_display_outbox',
        faultReaction.toMap(),
      );
      await db.execute('''
        CREATE TRIGGER tc369_group_reaction_delete_fault
        BEFORE DELETE ON group_notification_display_outbox
        WHEN OLD.event_id = '$faultReactionEventId'
        BEGIN
          SELECT RAISE(ABORT, 'tc369 injected reaction delete fault');
        END
      ''');
      await expectLater(
        completeReaction(faultReaction),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query(
          'message_reactions',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>[faultReactionId],
        )).single['notification_display_terminal_event_id'],
        isNull,
      );
      expect(
        await db.query(
          'group_event_log',
          where: 'group_id = ? AND source_event_id = ?',
          whereArgs: const <Object?>[groupId, 'prdt1:$faultReactionEventId'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[
            tryComputeNotificationCompletedOutcomeCorrelation(
              physicalPeerId: '12D3KooWgroup-physical',
              producerKind:
                  NotificationCompletedOutcomeProducerKind.groupReaction,
              eventKey: faultReactionEventId,
            ),
          ],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'group_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[faultReactionEventId],
        ),
        hasLength(1),
      );

      // An injected final-delete fault proves the terminal and outcome writes
      // cannot escape their shared exclusive transaction.
      const faultId = 'group-fault-message';
      await insertMessage(faultId);
      final fault = readyEntry(faultId);
      await db.insert('group_notification_display_outbox', fault.toMap());
      await db.execute('''
        CREATE TRIGGER tc369_group_delete_fault
        BEFORE DELETE ON group_notification_display_outbox
        WHEN OLD.event_id = '$faultId'
        BEGIN
          SELECT RAISE(ABORT, 'tc369 injected delete fault');
        END
      ''');
      await expectLater(
        complete(
          fault,
          candidate(faultId, NotificationCompletedOutcomeCategory.osPosted),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query(
          'group_messages',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>[faultId],
        )).single['notification_display_terminal_event_id'],
        isNull,
      );
      expect(
        await db.query(
          'group_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[faultId],
        ),
        hasLength(1),
      );
      final faultCorrelation =
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: '12D3KooWgroup-physical',
            producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
            eventKey: 'logical-$faultId',
          );
      expect(
        await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[faultCorrelation],
        ),
        isEmpty,
      );
    },
  );

  test(
    'TC-369-05 canonical display custody is the sole group outcome producer',
    () async {
      final defaultOff = await _buildFixture();
      addTearDown(defaultOff.listener.dispose);
      final defaultMessage = _incomingMessage(id: 'default-off-message');
      await defaultOff.messageRepo.saveMessage(defaultMessage);
      defaultOff.outbox.seedReady(_readyMessageEntry(defaultMessage));
      await defaultOff.listener.retryPendingNotificationDisplays();
      expect(defaultOff.outbox.completionOutcomes, const [null]);

      final enabled = await _buildFixture(
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWgroup-physical-installation',
        completedOutcomeProducerEnabled: true,
      );
      addTearDown(enabled.listener.dispose);
      final aliasedMessage = GroupMessage(
        id: 'canonical-message-id',
        logicalDeliveryId: 'authenticated-logical-delivery-id',
        groupId: _groupId,
        senderPeerId: _senderPeerId,
        senderUsername: 'Sender',
        text: 'Canonical alias',
        timestamp: DateTime.utc(2026, 8, 15, 10, 1),
        isIncoming: true,
        createdAt: DateTime.utc(2026, 8, 15, 10, 1),
      );
      await enabled.messageRepo.saveMessage(aliasedMessage);
      enabled.outbox.seedReady(_readyMessageEntry(aliasedMessage));
      await enabled.listener.retryPendingNotificationDisplays();

      final messageOutcome = enabled.outbox.completionOutcomes.single;
      expect(messageOutcome, isNotNull);
      expect(
        messageOutcome!.physicalPeerId,
        '12D3KooWgroup-physical-installation',
      );
      expect(
        messageOutcome.producerKind,
        NotificationCompletedOutcomeProducerKind.groupMessage,
      );
      expect(messageOutcome.eventKey, 'authenticated-logical-delivery-id');

      final target = _selfAuthoredTarget('reaction-target');
      const rawTransition =
          'raw-notification-transition-that-must-not-be-bounded';
      await enabled.messageRepo.saveMessage(target);
      await enabled.reactionRepo.saveReaction(
        const MessageReaction(
          id: 'reaction-state',
          messageId: 'reaction-target',
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: '2026-08-03T10:03:00.000Z',
          createdAt: '2026-08-03T10:03:00.000Z',
        ),
      );
      enabled.outbox.seedReady(
        _readyReactionEntry(eventId: rawTransition, messageId: target.id),
      );
      await enabled.listener.retryPendingNotificationDisplays();

      final reactionOutcome = enabled.outbox.completionOutcomes.last;
      expect(reactionOutcome, isNotNull);
      expect(
        reactionOutcome!.producerKind,
        NotificationCompletedOutcomeProducerKind.groupReaction,
      );
      expect(reactionOutcome.eventKey, rawTransition);

      final authenticatedLegacyMessage = _incomingMessage(
        id: 'authenticated-legacy-message-id',
        timestamp: DateTime.utc(2026, 8, 15, 10, 2),
      );
      await enabled.messageRepo.saveMessage(authenticatedLegacyMessage);
      enabled.outbox.seedReady(_readyMessageEntry(authenticatedLegacyMessage));
      await enabled.listener.retryPendingNotificationDisplays();
      expect(
        enabled.outbox.completionOutcomes.last?.eventKey,
        authenticatedLegacyMessage.id,
        reason:
            'an authenticated legacy envelope may fall back to its exact message id',
      );

      final siblingWithoutIdentity = await _buildFixture(
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async => null,
      );
      addTearDown(siblingWithoutIdentity.listener.dispose);
      final siblingMessage = _incomingMessage(
        id: 'same-event-on-sibling-installation',
      );
      await siblingWithoutIdentity.messageRepo.saveMessage(siblingMessage);
      siblingWithoutIdentity.outbox.seedReady(
        _readyMessageEntry(siblingMessage),
      );
      await siblingWithoutIdentity.listener.retryPendingNotificationDisplays();
      expect(siblingWithoutIdentity.notifications.showAttempts, 1);
      expect(
        siblingWithoutIdentity.outbox.completionOutcomes,
        const [null],
        reason:
            'a sibling with no local physical identity cannot inherit another installation outcome',
      );
      expect(
        messageOutcome.physicalPeerId,
        '12D3KooWgroup-physical-installation',
      );

      final muted = await _buildFixture(
        group: _group(isMuted: true),
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWgroup-physical-installation',
      );
      addTearDown(muted.listener.dispose);
      final mutedMessage = _incomingMessage(id: 'muted-policy-message');
      await muted.messageRepo.saveMessage(mutedMessage);
      muted.outbox.seedReady(_readyMessageEntry(mutedMessage));
      await muted.listener.retryPendingNotificationDisplays();
      expect(muted.notifications.showAttempts, 0);
      expect(muted.outbox.completionOutcomes, const [null]);

      final acknowledged = await _buildFixture(
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWgroup-physical-installation',
        isGroupNotificationEventAcknowledged:
            ({
              required groupId,
              required contentKind,
              required eventIdentity,
            }) async => true,
      );
      addTearDown(acknowledged.listener.dispose);
      final acknowledgedMessage = _incomingMessage(
        id: 'delivery-acknowledged-message',
      );
      await acknowledged.messageRepo.saveMessage(acknowledgedMessage);
      acknowledged.outbox.seedReady(_readyMessageEntry(acknowledgedMessage));
      await acknowledged.listener.retryPendingNotificationDisplays();
      expect(acknowledged.notifications.showAttempts, 0);
      expect(
        acknowledged.outbox.completionOutcomes,
        const [null],
        reason: 'delivery/read acknowledgement is not completed-effect proof',
      );

      final compatibility = await _buildFixture(
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWgroup-physical-installation',
      );
      addTearDown(compatibility.listener.dispose);
      await compatibility.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'messageId': 'history-compatibility-message',
        'text': 'History only',
        'timestamp': '2026-08-14T10:00:00.000Z',
      }, deliveryDisposition: GroupMessageDeliveryDisposition.historyRepair);
      expect(compatibility.notifications.showAttempts, 0);
      expect(compatibility.outbox.entries, isEmpty);
      expect(compatibility.outbox.completionOutcomes, isEmpty);

      final unauthenticatedMessage = await _buildFixture(
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWgroup-physical-installation',
      );
      addTearDown(unauthenticatedMessage.listener.dispose);
      final locallyGeneratedMessage = _incomingMessage(
        id: '${kUnauthenticatedIncomingGroupMessageIdPrefix}tc369',
      );
      await unauthenticatedMessage.messageRepo.saveMessage(
        locallyGeneratedMessage,
      );
      unauthenticatedMessage.outbox.seedReady(
        _readyMessageEntry(locallyGeneratedMessage),
      );
      await unauthenticatedMessage.listener.retryPendingNotificationDisplays();
      expect(unauthenticatedMessage.notifications.showAttempts, 1);
      expect(
        unauthenticatedMessage.outbox.completionOutcomes,
        const [null],
        reason:
            'a locally generated compatibility id has no authenticated event authority',
      );

      final whitespaceLogical = await _buildFixture(
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWgroup-physical-installation',
      );
      addTearDown(whitespaceLogical.listener.dispose);
      final whitespaceLogicalMessage = GroupMessage(
        id: 'whitespace-logical-message',
        logicalDeliveryId: ' logical-delivery-with-edge-space ',
        groupId: _groupId,
        senderPeerId: _senderPeerId,
        senderUsername: 'Sender',
        text: 'Canonical content',
        timestamp: DateTime.utc(2026, 8, 15, 10, 3),
        isIncoming: true,
        createdAt: DateTime.utc(2026, 8, 15, 10, 3),
      );
      await whitespaceLogical.messageRepo.saveMessage(whitespaceLogicalMessage);
      whitespaceLogical.outbox.seedReady(
        _readyMessageEntry(whitespaceLogicalMessage),
      );
      await whitespaceLogical.listener.retryPendingNotificationDisplays();
      expect(whitespaceLogical.notifications.showAttempts, 1);
      expect(
        whitespaceLogical.outbox.completionOutcomes,
        const [null],
        reason:
            'a present non-canonical logical id cannot fall back to message id',
      );

      Future<void> proveReactionWithoutOutcome({
        required _Fixture fixture,
        required String targetId,
        required String reactionId,
        required String eventId,
        required String timestamp,
      }) async {
        final reactionTarget = _selfAuthoredTarget(targetId);
        await fixture.messageRepo.saveMessage(reactionTarget);
        await fixture.reactionRepo.saveReaction(
          MessageReaction(
            id: reactionId,
            messageId: targetId,
            emoji: '👍',
            senderPeerId: _senderPeerId,
            timestamp: timestamp,
            createdAt: timestamp,
          ),
        );
        fixture.outbox.seedReady(
          _readyReactionEntry(
            eventId: eventId,
            messageId: targetId,
            reactionId: reactionId,
            timestamp: timestamp,
          ),
        );
        await fixture.listener.retryPendingNotificationDisplays();
        expect(fixture.notifications.showAttempts, 1);
        expect(fixture.outbox.completionOutcomes, const [null]);
      }

      final legacyReaction = await _buildFixture(
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWgroup-physical-installation',
      );
      addTearDown(legacyReaction.listener.dispose);
      const legacyReactionTimestamp = '2026-08-15T10:04:00.000Z';
      const legacyReactionId = 'legacy-reaction-state';
      const legacyReactionTargetId = 'legacy-reaction-target';
      final syntheticLegacyTransition = const GroupReactionPayload(
        id: legacyReactionId,
        messageId: legacyReactionTargetId,
        emoji: '👍',
        action: GroupReactionPayload.actionAdd,
        senderPeerId: _senderPeerId,
        timestamp: legacyReactionTimestamp,
      ).notificationTransitionId;
      expect(syntheticLegacyTransition, startsWith('legacy-reaction:'));
      await proveReactionWithoutOutcome(
        fixture: legacyReaction,
        targetId: legacyReactionTargetId,
        reactionId: legacyReactionId,
        eventId: syntheticLegacyTransition,
        timestamp: legacyReactionTimestamp,
      );

      final whitespaceReaction = await _buildFixture(
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWgroup-physical-installation',
      );
      addTearDown(whitespaceReaction.listener.dispose);
      await proveReactionWithoutOutcome(
        fixture: whitespaceReaction,
        targetId: 'whitespace-reaction-target',
        reactionId: 'whitespace-reaction-state',
        eventId: ' raw-reaction-transition ',
        timestamp: '2026-08-15T10:05:00.000Z',
      );
    },
  );

  test(
    'TC-366-04a history repair cannot stage or reconcile a display claim',
    () async {
      final fixture = await _buildFixture();
      addTearDown(fixture.listener.dispose);

      await fixture.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'messageId': 'tc366-wiring-history-fresh',
        'text': 'Fresh repaired history',
        'timestamp': '2026-08-14T10:00:00.000Z',
      }, deliveryDisposition: GroupMessageDeliveryDisposition.historyRepair);

      expect(
        (await fixture.messageRepo.getMessage(
          'tc366-wiring-history-fresh',
        ))?.readAt,
        isNotNull,
      );
      expect(fixture.outbox.operations, isEmpty);
      expect(fixture.notifications.showAttempts, 0);

      final canonicalReadAt = DateTime.utc(2026, 8, 14, 10, 2);
      final canonical = GroupMessage(
        id: 'tc366-wiring-canonical',
        groupId: _groupId,
        senderPeerId: _senderPeerId,
        senderUsername: 'Sender',
        text: 'Canonical history duplicate',
        timestamp: DateTime.utc(2026, 8, 14, 10, 1),
        logicalDeliveryId: 'tc366-wiring-logical',
        isIncoming: true,
        readAt: canonicalReadAt,
        createdAt: DateTime.utc(2026, 8, 14, 10, 1),
      );
      await fixture.messageRepo.saveMessage(canonical);
      fixture.outbox.entries[canonical.id] = _readyMessageEntry(
        canonical,
      ).copyWith(readiness: GroupNotificationDisplayOutboxReadiness.notReady);

      await fixture.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'messageId': 'tc366-wiring-alias',
        'logicalDeliveryId': canonical.logicalDeliveryId,
        'text': canonical.text,
        'timestamp': canonical.timestamp.toIso8601String(),
      }, deliveryDisposition: GroupMessageDeliveryDisposition.historyRepair);

      expect(
        (await fixture.messageRepo.getMessage(canonical.id))?.readAt,
        canonicalReadAt,
      );
      expect(
        await fixture.messageRepo.getMessage('tc366-wiring-alias'),
        isNull,
      );
      expect(fixture.outbox.operations, isEmpty);
      expect(fixture.outbox.entries[canonical.id]?.isReady, isFalse);
      expect(fixture.notifications.showAttempts, 0);

      await fixture.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'messageId': 'tc366-wiring-ordinary',
        'text': 'Ordinary replay display control',
        'timestamp': '2026-08-14T10:03:00.000Z',
      });

      expect(
        (await fixture.messageRepo.getMessage('tc366-wiring-ordinary'))?.readAt,
        isNull,
      );
      expect(
        fixture.outbox.operations,
        containsAllInOrder([
          'stage:tc366-wiring-ordinary:not_ready',
          'promote:tc366-wiring-ordinary:1',
          'complete:tc366-wiring-ordinary:2',
        ]),
      );
      expect(fixture.notifications.showAttempts, 1);
      expect(fixture.notifications.shown, hasLength(1));
    },
  );

  test(
    'TC-366-04a history repair flushes pending reaction notification-inert',
    () async {
      final pendingReactions = InMemoryGroupPendingReactionRepository();
      final fixture = await _buildFixture(
        pendingReactionRepo: pendingReactions,
      );
      addTearDown(fixture.listener.dispose);
      final changes = <ReactionChange>[];
      final changesSubscription = fixture.listener.groupReactionChangeStream
          .listen(changes.add);
      addTearDown(changesSubscription.cancel);
      final retainedReady = _incomingMessage(
        id: 'tc366-history-unrelated-ready',
      );
      await fixture.messageRepo.saveMessage(retainedReady);
      fixture.outbox.seedReady(_readyMessageEntry(retainedReady));
      await _seedPendingReaction(
        repository: pendingReactions,
        messageId: 'tc366-history-reaction-target',
        reactionId: 'tc366-history-reaction-state',
        eventId: 'tc366-history-reaction-event',
        timestamp: DateTime.utc(2026, 8, 14, 10, 5),
      );

      await fixture.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _selfPeerId,
        'senderUsername': 'Me',
        'keyEpoch': 0,
        'messageId': 'tc366-history-reaction-target',
        'text': 'Repaired local-account target',
        'timestamp': '2026-08-14T10:04:00.000Z',
      }, deliveryDisposition: GroupMessageDeliveryDisposition.historyRepair);

      expect(pendingReactions.reactions, isEmpty);
      expect(
        await fixture.reactionRepo.getReactionsForMessage(
          'tc366-history-reaction-target',
        ),
        hasLength(1),
      );
      expect(changes, hasLength(1));
      expect(changes.single.messageId, 'tc366-history-reaction-target');
      expect(changes.single.type, ReactionChangeType.upserted);
      expect(
        fixture.outbox.entries,
        containsPair(
          retainedReady.id,
          isA<GroupNotificationDisplayOutboxEntry>(),
        ),
      );
      expect(fixture.outbox.entries[retainedReady.id]?.isReady, isTrue);
      expect(fixture.outbox.operations, isEmpty);
      expect(fixture.notifications.showAttempts, 0);
      expect(fixture.notifications.shown, isEmpty);
    },
  );

  test(
    'ordinary replay pending reaction retains display custody and notification',
    () async {
      final pendingReactions = InMemoryGroupPendingReactionRepository();
      final fixture = await _buildFixture(
        pendingReactionRepo: pendingReactions,
      );
      addTearDown(fixture.listener.dispose);
      final changes = <ReactionChange>[];
      final changesSubscription = fixture.listener.groupReactionChangeStream
          .listen(changes.add);
      addTearDown(changesSubscription.cancel);
      await _seedPendingReaction(
        repository: pendingReactions,
        messageId: 'ordinary-reaction-target',
        reactionId: 'ordinary-reaction-state',
        eventId: 'ordinary-reaction-event',
        timestamp: DateTime.utc(2026, 8, 14, 10, 7),
      );

      await fixture.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _selfPeerId,
        'senderUsername': 'Me',
        'keyEpoch': 0,
        'messageId': 'ordinary-reaction-target',
        'text': 'Ordinary local-account target',
        'timestamp': '2026-08-14T10:06:00.000Z',
      });

      expect(pendingReactions.reactions, isEmpty);
      expect(
        await fixture.reactionRepo.getReactionsForMessage(
          'ordinary-reaction-target',
        ),
        hasLength(1),
      );
      expect(changes, hasLength(1));
      expect(
        fixture.outbox.operations,
        containsAllInOrder([
          'stage:ordinary-reaction-event:not_ready',
          'promote:ordinary-reaction-event:1',
          'complete:ordinary-reaction-event:2',
        ]),
      );
      expect(fixture.notifications.showAttempts, 1);
      expect(fixture.notifications.shown, hasLength(1));
    },
  );

  test(
    'canonical reaction acknowledged after ADD suppresses its loaded retry',
    () async {
      final reactions = FakeReactionRepository();
      final fixture = await _buildFixture(reactionRepo: reactions);
      addTearDown(fixture.listener.dispose);
      await fixture.messageRepo.saveMessage(
        _selfAuthoredTarget('canonical-read-target'),
      );
      await reactions.saveReaction(
        const MessageReaction(
          id: 'canonical-read-state',
          messageId: 'canonical-read-target',
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: '2026-08-03T10:08:30.000Z',
          createdAt: '2026-08-03T10:08:30.000Z',
          notificationAcknowledgedAt: '2026-08-03T10:08:31.000Z',
        ),
      );
      fixture.outbox.seedReady(
        _readyReactionEntry(
          eventId: 'canonical-read-event',
          messageId: 'canonical-read-target',
          reactionId: 'canonical-read-state',
          timestamp: '2026-08-03T10:08:30.000Z',
        ).copyWith(revision: 2),
      );

      await fixture.listener.retryPendingNotificationDisplays();

      expect(fixture.notifications.showAttempts, 0);
      expect(fixture.outbox.entries, isEmpty);
    },
  );

  test(
    'acknowledgement committed after ready load suppresses foreground reaction show',
    () async {
      var acknowledged = false;
      final fixture = await _buildFixture(
        isGroupNotificationEventAcknowledged:
            ({
              required groupId,
              required contentKind,
              required eventIdentity,
            }) async =>
                acknowledged &&
                groupId == _groupId &&
                contentKind == ConversationNotificationContentKind.reaction &&
                eventIdentity ==
                    boundedReactionEventIdentity('loaded-before-read'),
      );
      addTearDown(fixture.listener.dispose);
      await fixture.messageRepo.saveMessage(
        _selfAuthoredTarget('loaded-before-read-target'),
      );
      await fixture.reactionRepo.saveReaction(
        const MessageReaction(
          id: 'loaded-before-read-state',
          messageId: 'loaded-before-read-target',
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: '2026-08-03T10:09:00.000Z',
          createdAt: '2026-08-03T10:09:00.000Z',
        ),
      );
      fixture.outbox.seedReady(
        _readyReactionEntry(
          eventId: 'loaded-before-read',
          messageId: 'loaded-before-read-target',
          reactionId: 'loaded-before-read-state',
          timestamp: '2026-08-03T10:09:00.000Z',
        ).copyWith(revision: 2),
      );

      acknowledged = true;
      await fixture.listener.retryPendingNotificationDisplays();

      expect(fixture.notifications.showAttempts, 0);
      expect(fixture.outbox.entries, isEmpty);
    },
  );

  test(
    'cold startup keeps a headless message card until canonical group recovery completes',
    () async {
      final messages = _TrackingUnreadGroupMessageRepository();
      final fixture = await _buildFixture(messageRepo: messages);
      final source = StreamController<Map<String, dynamic>>();
      addTearDown(source.close);
      addTearDown(fixture.listener.dispose);

      fixture.listener.start(source.stream);
      await Future<void>.delayed(Duration.zero);

      expect(
        messages.unreadQueries,
        0,
        reason: 'startup unread=0 is not canonical before inbox recovery',
      );
      expect(fixture.notifications.cancelledConversationKeys, isEmpty);

      fixture.listener.beginCanonicalNotificationRecovery();
      await messages.saveMessage(
        _incomingMessage(id: 'headless-card-materialized'),
      );
      await fixture.listener.endCanonicalNotificationRecovery(
        canonicalStateComplete: true,
      );
      expect(messages.unreadQueries, 0, reason: 'startup hold still owns scan');

      fixture.listener.beginCanonicalNotificationRecovery();
      await fixture.listener.endCanonicalNotificationRecovery(
        canonicalStateComplete: true,
        releaseStartupHold: true,
      );
      for (
        var attempt = 0;
        attempt < 20 && messages.unreadQueries == 0;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(messages.unreadQueries, greaterThan(0));
      expect(
        fixture.notifications.cancelledConversationKeys,
        isEmpty,
        reason: 'materialized unread custody preserves the headless card',
      );
    },
  );

  test(
    'TC-330-02/04 message replay stages before canonical save and retains a failed display until retry',
    () async {
      final outbox = _MemoryNotificationDisplayOutbox();
      final notifications = _FaultingNotificationService(failuresRemaining: 1);
      final fixture = await _buildFixture(
        outbox: outbox,
        notifications: notifications,
      );
      addTearDown(fixture.listener.dispose);
      outbox.onStage = (entry) async {
        expect(
          entry.readiness,
          GroupNotificationDisplayOutboxReadiness.notReady,
        );
        expect(await fixture.messageRepo.getMessage(entry.messageId), isNull);
      };

      final timestamp = DateTime.utc(2026, 8, 3, 10, 4);
      await fixture.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Persist before presenting',
        'timestamp': timestamp.toIso8601String(),
        'messageId': 'message-transition',
      }, rethrowOnError: true);

      expect(
        await fixture.messageRepo.getMessage('message-transition'),
        isNotNull,
      );
      final retained = outbox.entries['message-transition'];
      expect(retained, isNotNull);
      expect(retained!.isReady, isTrue);
      expect(retained.retryCount, 1);
      expect(
        retained.lastErrorCode,
        GroupNotificationDisplayOutboxErrorCode.displayFailed,
      );
      expect(notifications.showAttempts, 1);
      expect(notifications.shown, isEmpty);
      expect(
        outbox.operations,
        containsAllInOrder([
          'stage:message-transition:not_ready',
          'promote:message-transition:1',
          'retry:message-transition:2:display_failed',
        ]),
      );

      await fixture.listener.retryPendingNotificationDisplays();

      expect(outbox.entries, isEmpty);
      expect(notifications.showAttempts, 2);
      expect(notifications.shown, hasLength(1));
      expect(outbox.operations, contains('complete:message-transition:3'));
    },
  );

  test(
    'TC-330-P1 missing self identity aborts message mutation until custody can be evaluated',
    () async {
      var identityAvailable = false;
      final fixture = await _buildFixture(
        getSelfPeerId: () async => identityAvailable ? _selfPeerId : null,
      );
      addTearDown(fixture.listener.dispose);
      final envelope = <String, dynamic>{
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Identity-gated custody',
        'timestamp': '2026-08-03T10:04:01.000Z',
        'messageId': 'message-identity-custody',
      };

      await expectLater(
        fixture.listener.handleReplayEnvelope(envelope, rethrowOnError: true),
        throwsA(isA<GroupNotificationDisplayStateUnavailableException>()),
      );
      expect(
        await fixture.messageRepo.getMessage('message-identity-custody'),
        isNull,
      );
      expect(fixture.outbox.entries, isEmpty);

      identityAvailable = true;
      await fixture.listener.handleReplayEnvelope(
        envelope,
        rethrowOnError: true,
      );

      expect(
        await fixture.messageRepo.getMessage('message-identity-custody'),
        isNotNull,
      );
      expect(fixture.notifications.shown, hasLength(1));
      expect(fixture.outbox.entries, isEmpty);
    },
  );

  test(
    'TC-330-P1 logical aliases reconcile canonical custody for ordinary and enriched duplicates',
    () async {
      for (final enriched in <bool>[false, true]) {
        final fixture = await _buildFixture();
        addTearDown(fixture.listener.dispose);
        final suffix = enriched ? 'enriched' : 'ordinary';
        final timestamp = DateTime.utc(2026, 8, 3, 10, 4, enriched ? 2 : 1);
        final canonical = GroupMessage(
          id: 'canonical-$suffix',
          groupId: _groupId,
          senderPeerId: _senderPeerId,
          senderUsername: 'Sender',
          text: 'Logical duplicate $suffix',
          timestamp: timestamp,
          logicalDeliveryId: 'logical-$suffix',
          isIncoming: true,
          createdAt: timestamp,
        );
        await fixture.messageRepo.saveMessage(canonical);
        fixture.outbox.entries[canonical.id] = _readyMessageEntry(
          canonical,
        ).copyWith(readiness: GroupNotificationDisplayOutboxReadiness.notReady);
        final aliasId = 'alias-$suffix';

        await fixture.listener.handleReplayEnvelope({
          'groupId': _groupId,
          'senderId': _senderPeerId,
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': canonical.text,
          'timestamp': timestamp.toIso8601String(),
          'messageId': aliasId,
          'logicalDeliveryId': canonical.logicalDeliveryId,
          if (enriched)
            'media': _mediaDescriptor(
              'attachment-$suffix',
              timestamp.add(const Duration(seconds: 1)),
            ),
        }, rethrowOnError: true);

        expect(await fixture.messageRepo.getMessage(aliasId), isNull);
        expect(fixture.outbox.entries[aliasId], isNull);
        expect(fixture.outbox.entries[canonical.id], isNull);
        expect(fixture.notifications.shown, hasLength(1));
        expect(
          fixture.outbox.operations,
          containsAllInOrder([
            'stage:$aliasId:not_ready',
            'reconcile:$aliasId:${canonical.id}',
          ]),
        );
        expect(
          await fixture.mediaRepo.getAttachmentsForMessage(
            canonical.id,
            owner: MediaOwnerLane.group,
          ),
          enriched ? hasLength(1) : isEmpty,
        );
      }
    },
  );

  test(
    'TC-330-P1 rejected cross-group sender conflict cannot promote another event custody',
    () async {
      final fixture = await _buildFixture();
      addTearDown(fixture.listener.dispose);
      final timestamp = DateTime.utc(2026, 8, 3, 10, 4, 30);
      final original = GroupMessage(
        id: 'wire-id-authority-conflict',
        groupId: _groupId,
        senderPeerId: _senderPeerId,
        senderUsername: 'Sender',
        text: 'Canonical parent whose media commit is incomplete',
        timestamp: timestamp,
        logicalDeliveryId: 'logical-authority-conflict',
        isIncoming: true,
        createdAt: timestamp,
      );
      await fixture.messageRepo.saveMessage(original);
      fixture.outbox.entries[original.id] = _readyMessageEntry(
        original,
      ).copyWith(readiness: GroupNotificationDisplayOutboxReadiness.notReady);

      await fixture.listener.handleReplayEnvelope({
        'groupId': 'different-group',
        'senderId': 'different-sender',
        'senderUsername': 'Mallory',
        'keyEpoch': 0,
        'text': 'Conflicting authority',
        'timestamp': timestamp.toIso8601String(),
        'messageId': original.id,
      }, rethrowOnError: true);

      expect(
        fixture.outbox.entries[original.id],
        isA<GroupNotificationDisplayOutboxEntry>()
            .having((entry) => entry.isReady, 'isReady', isFalse)
            .having((entry) => entry.revision, 'revision', 1)
            .having((entry) => entry.groupId, 'groupId', _groupId)
            .having((entry) => entry.actorPeerId, 'actorPeerId', _senderPeerId),
      );
      expect(fixture.notifications.shown, isEmpty);
      expect(
        fixture.outbox.operations,
        isNot(contains('promote:${original.id}:1')),
      );
    },
  );

  test(
    'TC-330-P1 authority-exact stable-ID replay recovers crash custody',
    () async {
      final fixture = await _buildFixture();
      addTearDown(fixture.listener.dispose);
      final timestamp = DateTime.utc(2026, 8, 3, 10, 4, 31);
      final canonical = GroupMessage(
        id: 'stable-id-crash-recovery',
        groupId: _groupId,
        senderPeerId: _senderPeerId,
        senderUsername: 'Sender',
        text: 'Canonical parent committed before crash',
        timestamp: timestamp,
        logicalDeliveryId: 'logical-crash-recovery',
        isIncoming: true,
        createdAt: timestamp,
      );
      await fixture.messageRepo.saveMessage(canonical);
      fixture.outbox.entries[canonical.id] = _readyMessageEntry(
        canonical,
      ).copyWith(readiness: GroupNotificationDisplayOutboxReadiness.notReady);

      await fixture.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': canonical.text,
        'timestamp': timestamp.toIso8601String(),
        'messageId': canonical.id,
        'logicalDeliveryId': canonical.logicalDeliveryId,
      }, rethrowOnError: true);

      expect(fixture.outbox.entries[canonical.id], isNull);
      expect(fixture.notifications.shown, hasLength(1));
      expect(
        fixture.outbox.operations,
        containsAllInOrder([
          'reconcile:${canonical.id}:${canonical.id}',
          'complete:${canonical.id}:2',
        ]),
      );
    },
  );

  test('TC-330-P1 legacy reaction fallback is generation-specific', () {
    const firstAdd = GroupReactionPayload(
      id: 'legacy-reaction-state',
      messageId: 'legacy-target',
      emoji: '👍',
      action: GroupReactionPayload.actionAdd,
      senderPeerId: _senderPeerId,
      timestamp: '2026-08-03T10:05:00.000Z',
    );
    const reAdd = GroupReactionPayload(
      id: 'legacy-reaction-state',
      messageId: 'legacy-target',
      emoji: '👍',
      action: GroupReactionPayload.actionAdd,
      senderPeerId: _senderPeerId,
      timestamp: '2026-08-03T10:05:02.000Z',
    );
    const explicit = GroupReactionPayload(
      id: 'legacy-reaction-state',
      messageId: 'legacy-target',
      emoji: '👍',
      action: GroupReactionPayload.actionAdd,
      senderPeerId: _senderPeerId,
      timestamp: '2026-08-03T10:05:03.000Z',
      eventId: ' explicit-transition ',
    );

    expect(firstAdd.notificationTransitionId, isNot(firstAdd.id));
    expect(
      reAdd.notificationTransitionId,
      isNot(firstAdd.notificationTransitionId),
    );
    expect(explicit.notificationTransitionId, ' explicit-transition ');
  });

  test(
    'TC-330-P1 legacy reaction stage and promotion share one derived transition id',
    () async {
      final fixture = await _buildFixture();
      addTearDown(fixture.listener.dispose);
      await fixture.messageRepo.saveMessage(
        _selfAuthoredTarget('legacy-derived-target'),
      );
      const payload = GroupReactionPayload(
        id: 'legacy-derived-state',
        messageId: 'legacy-derived-target',
        emoji: '👍',
        action: GroupReactionPayload.actionAdd,
        senderPeerId: _senderPeerId,
        timestamp: '2026-08-03T10:05:04.000Z',
      );

      await fixture.listener.handleReplayReaction({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'reaction': payload.toInnerJson(),
      }, rethrowOnError: true);

      final transitionId = payload.notificationTransitionId;
      expect(
        fixture.outbox.operations,
        containsAllInOrder([
          'stage:$transitionId:not_ready',
          'promote:$transitionId:1',
          'complete:$transitionId:2',
        ]),
      );
      expect(fixture.outbox.entries, isEmpty);
    },
  );

  test(
    'TC-330-P1 stale completion cannot ABA-delete a same-id reaction re-add',
    () async {
      final fixture = await _buildFixture();
      addTearDown(fixture.listener.dispose);
      const targetId = 'aba-reaction-target';
      const reusedEventId = 'legacy-reused-reaction-id';
      const firstTimestamp = '2026-08-03T10:06:00.000Z';
      const secondTimestamp = '2026-08-03T10:06:02.000Z';
      await fixture.messageRepo.saveMessage(_selfAuthoredTarget(targetId));
      await fixture.reactionRepo.saveReaction(
        const MessageReaction(
          id: reusedEventId,
          messageId: targetId,
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: firstTimestamp,
          createdAt: firstTimestamp,
        ),
      );
      fixture.outbox.seedReady(
        _readyReactionEntry(
          eventId: reusedEventId,
          messageId: targetId,
          reactionId: reusedEventId,
          timestamp: firstTimestamp,
        ).copyWith(revision: 2),
      );
      final completionEntered = Completer<void>();
      final releaseCompletion = Completer<void>();
      fixture.outbox.onComplete = (entry) async {
        if (entry.eventTimestamp != firstTimestamp) return;
        completionEntered.complete();
        await releaseCompletion.future;
      };

      final staleRun = fixture.listener.retryPendingNotificationDisplays();
      await completionEntered.future;

      await fixture.outbox.deleteForReactionActor(
        groupId: _groupId,
        messageId: targetId,
        actorPeerId: _senderPeerId,
      );
      await fixture.reactionRepo.saveReaction(
        const MessageReaction(
          id: reusedEventId,
          messageId: targetId,
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: secondTimestamp,
          createdAt: secondTimestamp,
        ),
      );
      await fixture.outbox.stage(
        _readyReactionEntry(
          eventId: reusedEventId,
          messageId: targetId,
          reactionId: reusedEventId,
          timestamp: secondTimestamp,
        ).copyWith(readiness: GroupNotificationDisplayOutboxReadiness.notReady),
      );
      expect(
        await fixture.outbox.promoteReadyIfExact(
          eventId: reusedEventId,
          expectedRevision: 1,
        ),
        isTrue,
      );
      fixture.outbox.rejectRetryCas = true;

      releaseCompletion.complete();
      await staleRun;
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (fixture.outbox.entries.containsKey(reusedEventId) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(fixture.outbox.entries[reusedEventId], isNull);
      expect(
        fixture.outbox.completionAttempts
            .map((entry) => entry.eventTimestamp)
            .toList(),
        [firstTimestamp, secondTimestamp],
      );
      expect(
        fixture.outbox.operations,
        contains('retry:$reusedEventId:2:claim_pending'),
      );
    },
  );

  test(
    'TC-330-03/04 reaction replay stages its transition id before mutation then promotes and completes it',
    () async {
      final outbox = _MemoryNotificationDisplayOutbox();
      final fixture = await _buildFixture(outbox: outbox);
      addTearDown(fixture.listener.dispose);
      await fixture.messageRepo.saveMessage(
        _selfAuthoredTarget('reaction-target'),
      );
      outbox.onStage = (entry) async {
        expect(entry.eventId, 'reaction-transition');
        expect(entry.reactionId, 'reaction-state');
        expect(
          entry.readiness,
          GroupNotificationDisplayOutboxReadiness.notReady,
        );
        expect(
          await fixture.reactionRepo.getReactionForSenderIncludingRemoved(
            messageId: entry.messageId,
            senderPeerId: entry.actorPeerId,
          ),
          isNull,
        );
      };

      await fixture.listener.handleReplayReaction({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'reaction': jsonEncode({
          'id': 'reaction-state',
          'eventId': 'reaction-transition',
          'messageId': 'reaction-target',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-08-03T10:03:00.000Z',
        }),
      }, rethrowOnError: true);

      final canonical = await fixture.reactionRepo
          .getReactionForSenderIncludingRemoved(
            messageId: 'reaction-target',
            senderPeerId: _senderPeerId,
          );
      expect(canonical?.id, 'reaction-state');
      expect(outbox.entries, isEmpty);
      expect(fixture.notifications.shown, hasLength(1));
      expect(
        outbox.operations,
        containsAllInOrder([
          'stage:reaction-transition:not_ready',
          'promote:reaction-transition:1',
          'complete:reaction-transition:2',
        ]),
      );
    },
  );

  test(
    'TC-330-P1 missing self identity aborts reaction mutation until custody can be evaluated',
    () async {
      var identityAvailable = false;
      final fixture = await _buildFixture(
        getSelfPeerId: () async => identityAvailable ? _selfPeerId : null,
      );
      addTearDown(fixture.listener.dispose);
      await fixture.messageRepo.saveMessage(
        _selfAuthoredTarget('reaction-identity-target'),
      );
      final envelope = <String, dynamic>{
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'reaction': jsonEncode({
          'id': 'reaction-identity-state',
          'eventId': 'reaction-identity-transition',
          'messageId': 'reaction-identity-target',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-08-03T10:03:01.000Z',
        }),
      };

      await expectLater(
        fixture.listener.handleReplayReaction(envelope, rethrowOnError: true),
        throwsA(isA<GroupNotificationDisplayStateUnavailableException>()),
      );
      expect(
        await fixture.reactionRepo.getReactionForSenderIncludingRemoved(
          messageId: 'reaction-identity-target',
          senderPeerId: _senderPeerId,
        ),
        isNull,
      );
      expect(fixture.outbox.entries, isEmpty);

      identityAvailable = true;
      await fixture.listener.handleReplayReaction(
        envelope,
        rethrowOnError: true,
      );

      expect(
        await fixture.reactionRepo.getReactionForSenderIncludingRemoved(
          messageId: 'reaction-identity-target',
          senderPeerId: _senderPeerId,
        ),
        isNotNull,
      );
      expect(fixture.notifications.shown, hasLength(1));
      expect(fixture.outbox.entries, isEmpty);
    },
  );

  test(
    'TC-330-05 a pending durable claim is retryable and keeps ready custody',
    () async {
      final claimDirectory = await Directory.systemTemp.createTemp(
        'group-notification-pending-claim-',
      );
      addTearDown(() => claimDirectory.delete(recursive: true));
      final lease = DurableNotificationToneLease(
        directory: claimDirectory,
        pendingClaimWait: Duration.zero,
      );
      final owner = await lease.acquireMessageEventClaim(
        type: 'group_message',
        eventIdentity: 'message-contended',
      );
      expect(owner.disposition, DurableNotificationClaimDisposition.acquired);
      addTearDown(() async => owner.claim?.release());
      final fixture = await _buildFixture(durableResolver: () async => lease);
      addTearDown(fixture.listener.dispose);

      await fixture.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Another producer still owns this event',
        'timestamp': '2026-08-03T10:05:00.000Z',
        'messageId': 'message-contended',
      }, rethrowOnError: true);

      final retained = fixture.outbox.entries['message-contended'];
      expect(retained, isNotNull);
      expect(retained!.isReady, isTrue);
      expect(retained.retryCount, 1);
      expect(
        retained.lastErrorCode,
        GroupNotificationDisplayOutboxErrorCode.claimPending,
      );
      expect(fixture.notifications.showAttempts, 0);
      expect(fixture.notifications.shown, isEmpty);
    },
  );

  test(
    'TC-330-16 current read mute archive dissolve self-removal and QA state terminalize message custody',
    () async {
      final cases = <({String name, GroupModel group, bool read})>[
        (name: 'read', group: _group(), read: true),
        (name: 'muted', group: _group(isMuted: true), read: false),
        (name: 'archived', group: _group(isArchived: true), read: false),
        (
          name: 'dissolved',
          group: _group(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 8, 3, 10, 6),
          ),
          read: false,
        ),
        (
          name: 'self-removed',
          group: _group(selfRemovedAt: DateTime.utc(2026, 8, 3, 10, 6)),
          read: false,
        ),
        (name: 'qa', group: _group(type: GroupType.qa), read: false),
      ];

      for (final testCase in cases) {
        final fixture = await _buildFixture(group: testCase.group);
        addTearDown(fixture.listener.dispose);
        final message = _incomingMessage(
          id: 'terminal-${testCase.name}',
          readAt: testCase.read ? DateTime.utc(2026, 8, 3, 10, 7) : null,
        );
        await fixture.messageRepo.saveMessage(message);
        fixture.outbox.seedReady(_readyMessageEntry(message));

        await fixture.listener.retryPendingNotificationDisplays();

        expect(
          fixture.outbox.entries,
          isEmpty,
          reason: '${testCase.name} must terminalize stale attention custody',
        );
        expect(
          fixture.notifications.shown,
          isEmpty,
          reason: '${testCase.name} must not publish an OS card',
        );
      }
    },
  );

  test(
    'TC-330-16 missing canonical message retains custody as state unavailable',
    () async {
      final fixture = await _buildFixture();
      addTearDown(fixture.listener.dispose);
      final absent = _incomingMessage(id: 'message-not-materialized');
      fixture.outbox.seedReady(_readyMessageEntry(absent));

      await fixture.listener.retryPendingNotificationDisplays();

      final retained = fixture.outbox.entries[absent.id];
      expect(retained, isNotNull);
      expect(retained!.retryCount, 1);
      expect(
        retained.lastErrorCode,
        GroupNotificationDisplayOutboxErrorCode.stateUnavailable,
      );
      expect(fixture.notifications.shown, isEmpty);
    },
  );

  test(
    'TC-330-03/16 reaction projection requires exact active transition comparands',
    () async {
      final cases =
          <
            ({
              String name,
              String canonicalId,
              String canonicalTimestamp,
              String? removedAt,
              String markerAction,
              bool markerTombstone,
              bool shouldShow,
            })
          >[
            (
              name: 'exact-active',
              canonicalId: 'reaction-state',
              canonicalTimestamp: '2026-08-03T10:03:00.000Z',
              removedAt: null,
              markerAction: 'add',
              markerTombstone: false,
              shouldShow: true,
            ),
            (
              name: 'different-reaction-id',
              canonicalId: 'newer-reaction-state',
              canonicalTimestamp: '2026-08-03T10:03:00.000Z',
              removedAt: null,
              markerAction: 'add',
              markerTombstone: false,
              shouldShow: false,
            ),
            (
              name: 'different-event-time',
              canonicalId: 'reaction-state',
              canonicalTimestamp: '2026-08-03T10:04:00.000Z',
              removedAt: null,
              markerAction: 'add',
              markerTombstone: false,
              shouldShow: false,
            ),
            (
              name: 'canonical-tombstone',
              canonicalId: 'reaction-state',
              canonicalTimestamp: '2026-08-03T10:03:00.000Z',
              removedAt: '2026-08-03T10:05:00.000Z',
              markerAction: 'add',
              markerTombstone: false,
              shouldShow: false,
            ),
            (
              name: 'remove-transition',
              canonicalId: 'reaction-state',
              canonicalTimestamp: '2026-08-03T10:03:00.000Z',
              removedAt: null,
              markerAction: 'remove',
              markerTombstone: false,
              shouldShow: false,
            ),
            (
              name: 'marker-tombstone',
              canonicalId: 'reaction-state',
              canonicalTimestamp: '2026-08-03T10:03:00.000Z',
              removedAt: null,
              markerAction: 'add',
              markerTombstone: true,
              shouldShow: false,
            ),
          ];

      for (final testCase in cases) {
        final fixture = await _buildFixture();
        addTearDown(fixture.listener.dispose);
        final targetId = 'target-${testCase.name}';
        await fixture.messageRepo.saveMessage(_selfAuthoredTarget(targetId));
        await fixture.reactionRepo.saveReaction(
          MessageReaction(
            id: testCase.canonicalId,
            messageId: targetId,
            emoji: '👍',
            senderPeerId: _senderPeerId,
            timestamp: testCase.canonicalTimestamp,
            createdAt: '2026-08-03T10:03:01.000Z',
            removedAt: testCase.removedAt,
          ),
        );
        final eventId = 'transition-${testCase.name}';
        fixture.outbox.seedReady(
          _readyReactionEntry(
            eventId: eventId,
            messageId: targetId,
            reactionAction: testCase.markerAction,
            reactionTombstone: testCase.markerTombstone,
          ),
        );

        await fixture.listener.retryPendingNotificationDisplays();

        expect(
          fixture.outbox.entries,
          isEmpty,
          reason: '${testCase.name} is terminal after canonical comparison',
        );
        expect(
          fixture.notifications.shown.length,
          testCase.shouldShow ? 1 : 0,
          reason: testCase.name,
        );
      }
    },
  );

  test(
    'TC-330-P1 startup flush cannot present before the first canonical drain begins',
    () async {
      final fixture = await _buildFixture();
      final messages = StreamController<Map<String, dynamic>>();
      final reactions = StreamController<Map<String, dynamic>>();
      addTearDown(messages.close);
      addTearDown(reactions.close);
      addTearDown(fixture.listener.dispose);
      fixture.listener.start(
        messages.stream,
        incomingGroupReactions: reactions.stream,
      );
      await fixture.messageRepo.saveMessage(
        _selfAuthoredTarget('startup-reaction-target'),
      );

      await fixture.listener.handleReplayReaction({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'reaction': jsonEncode({
          'id': 'startup-reaction-add-state',
          'eventId': 'startup-reaction-add-transition',
          'messageId': 'startup-reaction-target',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-08-03T10:08:00.000Z',
        }),
      }, rethrowOnError: true);

      expect(fixture.notifications.shown, isEmpty);
      expect(
        fixture.outbox.entries['startup-reaction-add-transition']?.isReady,
        isTrue,
      );

      // A different recovery owner (for example account projection rebuild)
      // must not release the startup hold before the full native inbox drain.
      fixture.listener.beginCanonicalNotificationRecovery();
      await fixture.listener.endCanonicalNotificationRecovery(
        canonicalStateComplete: true,
      );
      expect(fixture.notifications.shown, isEmpty);
      expect(
        fixture.outbox.entries['startup-reaction-add-transition']?.isReady,
        isTrue,
      );

      // The native drain begins only after startup flushing has already run;
      // its later REMOVE must win before any card is published.
      fixture.listener.beginCanonicalNotificationRecovery();
      await fixture.listener.handleReplayReaction({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'reaction': jsonEncode({
          'id': 'startup-reaction-remove-state',
          'eventId': 'startup-reaction-remove-transition',
          'messageId': 'startup-reaction-target',
          'emoji': '👍',
          'action': 'remove',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-08-03T10:09:00.000Z',
        }),
      }, rethrowOnError: true);
      await fixture.listener.endCanonicalNotificationRecovery(
        canonicalStateComplete: true,
        releaseStartupHold: true,
      );

      expect(fixture.notifications.shown, isEmpty);
      expect(fixture.outbox.entries, isEmpty);
    },
  );

  test(
    'TC-330-13 multi-page recovery never presents page-one ADD before page-two REMOVE',
    () async {
      final fixture = await _buildFixture();
      addTearDown(fixture.listener.dispose);
      await fixture.messageRepo.saveMessage(
        _selfAuthoredTarget('paged-reaction-target'),
      );

      fixture.listener.beginCanonicalNotificationRecovery();
      await fixture.listener.handleReplayReaction({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'reaction': jsonEncode({
          'id': 'paged-reaction-add-state',
          'eventId': 'paged-reaction-add-transition',
          'messageId': 'paged-reaction-target',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-08-03T10:10:00.000Z',
        }),
      }, rethrowOnError: true);

      expect(fixture.notifications.shown, isEmpty);
      expect(
        fixture.outbox.entries['paged-reaction-add-transition']?.isReady,
        isTrue,
      );

      await fixture.listener.handleReplayReaction({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'reaction': jsonEncode({
          'id': 'paged-reaction-remove-state',
          'eventId': 'paged-reaction-remove-transition',
          'messageId': 'paged-reaction-target',
          'emoji': '👍',
          'action': 'remove',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-08-03T10:11:00.000Z',
        }),
      }, rethrowOnError: true);
      await fixture.listener.endCanonicalNotificationRecovery(
        canonicalStateComplete: true,
      );

      expect(fixture.notifications.shown, isEmpty);
      expect(fixture.outbox.entries, isEmpty);
    },
  );

  test(
    'TC-330-13 incomplete drain retains ready custody until a later exhausted drain',
    () async {
      final fixture = await _buildFixture();
      addTearDown(fixture.listener.dispose);

      fixture.listener.beginCanonicalNotificationRecovery();
      await fixture.listener.handleReplayEnvelope({
        'groupId': _groupId,
        'senderId': _senderPeerId,
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Wait for canonical convergence',
        'timestamp': '2026-08-03T10:12:00.000Z',
        'messageId': 'incomplete-drain-message',
      }, rethrowOnError: true);
      await fixture.listener.endCanonicalNotificationRecovery(
        canonicalStateComplete: false,
      );

      await fixture.listener.retryPendingNotificationDisplays();
      expect(fixture.notifications.shown, isEmpty);
      expect(fixture.outbox.entries, hasLength(1));

      fixture.listener.beginCanonicalNotificationRecovery();
      await fixture.listener.endCanonicalNotificationRecovery(
        canonicalStateComplete: true,
      );

      expect(fixture.notifications.shown, hasLength(1));
      expect(fixture.outbox.entries, isEmpty);
    },
  );
}
