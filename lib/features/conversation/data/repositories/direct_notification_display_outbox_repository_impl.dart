import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';

import '../../domain/models/direct_notification_display_outbox_entry.dart';
import '../../domain/repositories/direct_notification_display_outbox_repository.dart';

class DirectNotificationDisplayOutboxRepositoryImpl
    implements DirectNotificationDisplayOutboxRepository {
  final Future<void> Function(Map<String, Object?> row) dbStage;
  final Future<Map<String, Object?>?> Function({
    required String peerId,
    required String eventKind,
    required String eventId,
  })
  dbLoadExact;
  final Future<bool> Function({
    required String peerId,
    required String eventKind,
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
    required String peerId,
    required String eventKind,
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
    required String expectedPeerId,
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
  final Future<bool> Function({
    required String eventId,
    required int expectedRevision,
    required String expectedEventKind,
    required String expectedPeerId,
    required String expectedMessageId,
    required String expectedActorPeerId,
    required String expectedEventTimestamp,
    required String? expectedReactionId,
    required String? expectedReactionAction,
    required bool? expectedReactionTombstone,
  })
  dbRetireIfExact;
  final Future<int> Function(String peerId) dbDeleteForPeer;
  final Future<int> Function({
    required String peerId,
    required String messageId,
  })
  dbDeleteForMessage;
  final Future<int> Function({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  })
  dbDeleteForReactionActor;
  final DateTime Function() now;

  DirectNotificationDisplayOutboxRepositoryImpl({
    required this.dbStage,
    required this.dbLoadExact,
    required this.dbPromoteReadyIfExact,
    required this.dbLoadReady,
    required this.dbLoadEarliestNextAttemptAt,
    required this.dbRecordRetryIfExact,
    required this.dbCompleteIfExact,
    required this.dbRetireIfExact,
    required this.dbDeleteForPeer,
    required this.dbDeleteForMessage,
    required this.dbDeleteForReactionActor,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  Future<void> stage(DirectNotificationDisplayOutboxEntry entry) =>
      dbStage(entry.toMap());

  @override
  Future<DirectNotificationDisplayOutboxEntry?> loadExact({
    required String peerId,
    required String eventKind,
    required String eventId,
  }) async {
    final row = await dbLoadExact(
      peerId: peerId,
      eventKind: eventKind,
      eventId: eventId,
    );
    return row == null
        ? null
        : DirectNotificationDisplayOutboxEntry.fromMap(row);
  }

  @override
  Future<bool> promoteReadyIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
  }) => dbPromoteReadyIfExact(
    eventId: eventId,
    peerId: peerId,
    eventKind: eventKind,
    expectedRevision: expectedRevision,
    updatedAt: now().toUtc().toIso8601String(),
  );

  @override
  Future<List<DirectNotificationDisplayOutboxEntry>> loadReady({
    int limit = 20,
  }) async => (await dbLoadReady(
    limit: limit,
    eligibleAt: now().toUtc().toIso8601String(),
  )).map(DirectNotificationDisplayOutboxEntry.fromMap).toList(growable: false);

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async {
    final encoded = await dbLoadEarliestNextAttemptAt();
    return encoded == null ? null : DateTime.parse(encoded).toUtc();
  }

  @override
  Future<bool> recordRetryIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  }) {
    final timestamp = now().toUtc().toIso8601String();
    return dbRecordRetryIfExact(
      eventId: eventId,
      peerId: peerId,
      eventKind: eventKind,
      expectedRevision: expectedRevision,
      lastErrorCode: lastErrorCode,
      lastAttemptAt: timestamp,
      nextAttemptAt: nextAttemptAt.toUtc().toIso8601String(),
      updatedAt: timestamp,
    );
  }

  @override
  Future<bool> completeIfExact(
    DirectNotificationDisplayOutboxEntry expected, {
    NotificationCompletedOutcomeCandidate? outcome,
  }) => dbCompleteIfExact(
    eventId: expected.eventId,
    expectedRevision: expected.revision,
    expectedEventKind: expected.eventKind,
    expectedPeerId: expected.peerId,
    expectedMessageId: expected.messageId,
    expectedActorPeerId: expected.actorPeerId,
    expectedEventTimestamp: expected.eventTimestamp,
    expectedReactionId: expected.reactionId,
    expectedReactionAction: expected.reactionAction,
    expectedReactionTombstone: expected.reactionTombstone,
    completedAt: now().toUtc().toIso8601String(),
    outcome: outcome,
  );

  @override
  Future<bool> retireIfExact(DirectNotificationDisplayOutboxEntry expected) =>
      dbRetireIfExact(
        eventId: expected.eventId,
        expectedRevision: expected.revision,
        expectedEventKind: expected.eventKind,
        expectedPeerId: expected.peerId,
        expectedMessageId: expected.messageId,
        expectedActorPeerId: expected.actorPeerId,
        expectedEventTimestamp: expected.eventTimestamp,
        expectedReactionId: expected.reactionId,
        expectedReactionAction: expected.reactionAction,
        expectedReactionTombstone: expected.reactionTombstone,
      );

  @override
  Future<int> deleteForPeer(String peerId) => dbDeleteForPeer(peerId);

  @override
  Future<int> deleteForMessage({
    required String peerId,
    required String messageId,
  }) => dbDeleteForMessage(peerId: peerId, messageId: messageId);

  @override
  Future<int> deleteForReactionActor({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) => dbDeleteForReactionActor(
    peerId: peerId,
    messageId: messageId,
    actorPeerId: actorPeerId,
  );
}
