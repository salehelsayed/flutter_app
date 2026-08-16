import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';

import '../../domain/models/group_message.dart';
import '../../domain/models/group_notification_display_outbox_entry.dart';
import '../../domain/repositories/group_notification_display_outbox_repository.dart';

class GroupNotificationDisplayOutboxRepositoryImpl
    implements GroupNotificationDisplayOutboxRepository {
  final Future<void> Function(Map<String, Object?> row) dbStage;
  final Future<Map<String, Object?>?> Function(String eventId) dbLoadByEventId;
  final Future<Map<String, Object?>?> Function({
    required String eventId,
    required int expectedRevision,
    required String expectedEventKind,
    required String expectedGroupId,
    required String expectedMessageId,
    required String expectedActorPeerId,
    required String expectedEventTimestamp,
    required String? expectedReactionId,
    required String? expectedReactionAction,
    required bool? expectedReactionTombstone,
    required String durableEventCorrelation,
    required String updatedAt,
  })?
  dbBindDurableCorrelationIfExact;
  final Future<bool> Function({
    required String eventId,
    required int expectedRevision,
    required String updatedAt,
  })
  dbPromoteReadyIfExact;
  final Future<List<Map<String, Object?>>> Function({
    int limit,
    required String eligibleAt,
  })
  dbLoadReady;
  final Future<String?> Function() dbLoadEarliestNextAttemptAt;
  final Future<bool> Function({
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required String lastAttemptAt,
    required String nextAttemptAt,
    required String updatedAt,
  })
  dbRecordRetryIfExact;
  final Future<bool> Function({
    required String eventId,
    required int expectedRevision,
    required String expectedEventKind,
    required String expectedGroupId,
    required String expectedMessageId,
    required String expectedActorPeerId,
    required String expectedEventTimestamp,
    required String? expectedReactionId,
    required String? expectedReactionAction,
    required bool? expectedReactionTombstone,
    required String completedAt,
    NotificationCompletedOutcomeCandidate? outcome,
  })
  dbCompleteIfExact;
  final Future<DurableLocalNotificationSqlHandoffResult> Function({
    required String eventId,
    required int expectedRevision,
    required String expectedEventKind,
    required String expectedGroupId,
    required String expectedMessageId,
    required String expectedActorPeerId,
    required String expectedEventTimestamp,
    required String? expectedReactionId,
    required String? expectedReactionAction,
    required bool? expectedReactionTombstone,
    required String completedAt,
    NotificationCompletedOutcomeCandidate? outcome,
    String? durableEventCorrelation,
  })?
  dbCompleteOrVerifyIfExact;
  final Future<bool> Function({
    required String eventId,
    required int expectedRevision,
    required String expectedEventKind,
    required String expectedGroupId,
    required String expectedMessageId,
    required String expectedActorPeerId,
    required String expectedEventTimestamp,
    required String? expectedReactionId,
    required String? expectedReactionAction,
    required bool? expectedReactionTombstone,
    String? durableEventCorrelation,
  })?
  dbRetireAfterDurableSettlementIfExact;
  final Future<bool> Function({
    required String eventId,
    required int expectedRevision,
    required String expectedEventKind,
    required String expectedGroupId,
    required String expectedMessageId,
    required String expectedActorPeerId,
    required String expectedEventTimestamp,
    required String? expectedReactionId,
    required String? expectedReactionAction,
    required bool? expectedReactionTombstone,
  })
  dbRetireIfExact;
  final Future<bool> Function({
    required String aliasEventId,
    required String canonicalEventId,
    required String groupId,
    required String actorPeerId,
    required String eventTimestamp,
    required String updatedAt,
  })
  dbReconcileMessageAliasReady;
  final Future<int> Function(String groupId) dbDeleteForGroup;
  final Future<int> Function({
    required String groupId,
    required String messageId,
  })
  dbDeleteForMessage;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String reactionId,
  })
  dbDeleteForReaction;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String actorPeerId,
  })
  dbDeleteForReactionActor;
  final DateTime Function() now;

  GroupNotificationDisplayOutboxRepositoryImpl({
    required this.dbStage,
    required this.dbLoadByEventId,
    this.dbBindDurableCorrelationIfExact,
    required this.dbPromoteReadyIfExact,
    required this.dbLoadReady,
    required this.dbLoadEarliestNextAttemptAt,
    required this.dbRecordRetryIfExact,
    required this.dbCompleteIfExact,
    this.dbCompleteOrVerifyIfExact,
    this.dbRetireAfterDurableSettlementIfExact,
    required this.dbRetireIfExact,
    required this.dbReconcileMessageAliasReady,
    required this.dbDeleteForGroup,
    required this.dbDeleteForMessage,
    required this.dbDeleteForReaction,
    required this.dbDeleteForReactionActor,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  Future<void> stage(GroupNotificationDisplayOutboxEntry entry) {
    return dbStage(entry.toMap());
  }

  @override
  Future<GroupNotificationDisplayOutboxEntry?> bindDurableCorrelationIfExact(
    GroupNotificationDisplayOutboxEntry expected, {
    required String durableEventCorrelation,
  }) async {
    final bind = dbBindDurableCorrelationIfExact;
    if (bind == null) return null;
    final row = await bind(
      eventId: expected.eventId,
      expectedRevision: expected.revision,
      expectedEventKind: expected.eventKind,
      expectedGroupId: expected.groupId,
      expectedMessageId: expected.messageId,
      expectedActorPeerId: expected.actorPeerId,
      expectedEventTimestamp: expected.eventTimestamp,
      expectedReactionId: expected.reactionId,
      expectedReactionAction: expected.reactionAction,
      expectedReactionTombstone: expected.reactionTombstone,
      durableEventCorrelation: durableEventCorrelation,
      updatedAt: now().toUtc().toIso8601String(),
    );
    return row == null
        ? null
        : GroupNotificationDisplayOutboxEntry.fromMap(row);
  }

  @override
  Future<bool> retireAfterDurableSettlementIfExact(
    GroupNotificationDisplayOutboxEntry expected, {
    String? durableEventCorrelation,
  }) {
    final retireAfterSettlement = dbRetireAfterDurableSettlementIfExact;
    if (retireAfterSettlement == null) {
      return durableEventCorrelation == null
          ? retireIfExact(expected)
          : Future<bool>.value(false);
    }
    return retireAfterSettlement(
      eventId: expected.eventId,
      expectedRevision: expected.revision,
      expectedEventKind: expected.eventKind,
      expectedGroupId: expected.groupId,
      expectedMessageId: expected.messageId,
      expectedActorPeerId: expected.actorPeerId,
      expectedEventTimestamp: expected.eventTimestamp,
      expectedReactionId: expected.reactionId,
      expectedReactionAction: expected.reactionAction,
      expectedReactionTombstone: expected.reactionTombstone,
      durableEventCorrelation: durableEventCorrelation,
    );
  }

  @override
  Future<GroupNotificationDisplayOutboxEntry?> loadByEventId(
    String eventId,
  ) async {
    final row = await dbLoadByEventId(eventId);
    return row == null
        ? null
        : GroupNotificationDisplayOutboxEntry.fromMap(row);
  }

  @override
  Future<bool> promoteReadyIfExact({
    required String eventId,
    required int expectedRevision,
  }) {
    return dbPromoteReadyIfExact(
      eventId: eventId,
      expectedRevision: expectedRevision,
      updatedAt: now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<List<GroupNotificationDisplayOutboxEntry>> loadReady({
    int limit = 20,
  }) async {
    final rows = await dbLoadReady(
      limit: limit,
      eligibleAt: now().toUtc().toIso8601String(),
    );
    return rows
        .map(GroupNotificationDisplayOutboxEntry.fromMap)
        .toList(growable: false);
  }

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async {
    final encoded = await dbLoadEarliestNextAttemptAt();
    return encoded == null ? null : DateTime.parse(encoded).toUtc();
  }

  @override
  Future<bool> recordRetryIfExact({
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  }) {
    final timestamp = now().toUtc().toIso8601String();
    return dbRecordRetryIfExact(
      eventId: eventId,
      expectedRevision: expectedRevision,
      lastErrorCode: lastErrorCode,
      lastAttemptAt: timestamp,
      nextAttemptAt: nextAttemptAt.toUtc().toIso8601String(),
      updatedAt: timestamp,
    );
  }

  @override
  Future<bool> completeIfExact(
    GroupNotificationDisplayOutboxEntry expected, {
    NotificationCompletedOutcomeCandidate? outcome,
  }) {
    return dbCompleteIfExact(
      eventId: expected.eventId,
      expectedRevision: expected.revision,
      expectedEventKind: expected.eventKind,
      expectedGroupId: expected.groupId,
      expectedMessageId: expected.messageId,
      expectedActorPeerId: expected.actorPeerId,
      expectedEventTimestamp: expected.eventTimestamp,
      expectedReactionId: expected.reactionId,
      expectedReactionAction: expected.reactionAction,
      expectedReactionTombstone: expected.reactionTombstone,
      completedAt: now().toUtc().toIso8601String(),
      outcome: outcome,
    );
  }

  @override
  Future<DurableLocalNotificationSqlHandoffResult> completeOrVerifyIfExact(
    GroupNotificationDisplayOutboxEntry expected, {
    NotificationCompletedOutcomeCandidate? outcome,
    String? durableEventCorrelation,
  }) async {
    final completeOrVerify = dbCompleteOrVerifyIfExact;
    if (completeOrVerify == null) {
      if (durableEventCorrelation != null) {
        return DurableLocalNotificationSqlHandoffResult.retryableMismatch;
      }
      return await completeIfExact(expected, outcome: outcome)
          ? DurableLocalNotificationSqlHandoffResult.committed
          : DurableLocalNotificationSqlHandoffResult.retryableMismatch;
    }
    return completeOrVerify(
      eventId: expected.eventId,
      expectedRevision: expected.revision,
      expectedEventKind: expected.eventKind,
      expectedGroupId: expected.groupId,
      expectedMessageId: expected.messageId,
      expectedActorPeerId: expected.actorPeerId,
      expectedEventTimestamp: expected.eventTimestamp,
      expectedReactionId: expected.reactionId,
      expectedReactionAction: expected.reactionAction,
      expectedReactionTombstone: expected.reactionTombstone,
      completedAt: now().toUtc().toIso8601String(),
      outcome: outcome,
      durableEventCorrelation: durableEventCorrelation,
    );
  }

  @override
  Future<bool> retireIfExact(GroupNotificationDisplayOutboxEntry expected) =>
      dbRetireIfExact(
        eventId: expected.eventId,
        expectedRevision: expected.revision,
        expectedEventKind: expected.eventKind,
        expectedGroupId: expected.groupId,
        expectedMessageId: expected.messageId,
        expectedActorPeerId: expected.actorPeerId,
        expectedEventTimestamp: expected.eventTimestamp,
        expectedReactionId: expected.reactionId,
        expectedReactionAction: expected.reactionAction,
        expectedReactionTombstone: expected.reactionTombstone,
      );

  @override
  Future<bool> reconcileMessageAliasReady({
    required String aliasEventId,
    required GroupMessage canonicalMessage,
  }) {
    return dbReconcileMessageAliasReady(
      aliasEventId: aliasEventId,
      canonicalEventId: canonicalMessage.id,
      groupId: canonicalMessage.groupId,
      actorPeerId: canonicalMessage.senderPeerId,
      eventTimestamp: canonicalMessage.timestamp.toUtc().toIso8601String(),
      updatedAt: now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<int> deleteForGroup(String groupId) => dbDeleteForGroup(groupId);

  @override
  Future<int> deleteForMessage({
    required String groupId,
    required String messageId,
  }) => dbDeleteForMessage(groupId: groupId, messageId: messageId);

  @override
  Future<int> deleteForReaction({
    required String groupId,
    required String messageId,
    required String reactionId,
  }) => dbDeleteForReaction(
    groupId: groupId,
    messageId: messageId,
    reactionId: reactionId,
  );

  @override
  Future<int> deleteForReactionActor({
    required String groupId,
    required String messageId,
    required String actorPeerId,
  }) => dbDeleteForReactionActor(
    groupId: groupId,
    messageId: messageId,
    actorPeerId: actorPeerId,
  );
}
