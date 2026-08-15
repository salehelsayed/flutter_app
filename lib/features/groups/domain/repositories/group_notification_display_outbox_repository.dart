import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';

import '../models/group_message.dart';
import '../models/group_notification_display_outbox_entry.dart';

abstract class GroupNotificationDisplayOutboxRepository {
  /// Acquires durable not-ready custody. Exact replay is idempotent; capacity
  /// or event-id authority conflict throws so canonical mutation can abort.
  Future<void> stage(GroupNotificationDisplayOutboxEntry entry);

  Future<GroupNotificationDisplayOutboxEntry?> loadByEventId(String eventId);

  Future<bool> promoteReadyIfExact({
    required String eventId,
    required int expectedRevision,
  });

  Future<List<GroupNotificationDisplayOutboxEntry>> loadReady({int limit = 20});

  /// Earliest persisted retry deadline among ready entries, or null when no
  /// deferred ready custody exists.
  Future<DateTime?> loadEarliestNextAttemptAt();

  Future<bool> recordRetryIfExact({
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  });

  /// Completes only when revision and every immutable authority field still
  /// match [expected], preventing delete/reinsert ABA at a reused event ID.
  Future<bool> completeIfExact(
    GroupNotificationDisplayOutboxEntry expected, {
    NotificationCompletedOutcomeCandidate? outcome,
  });

  /// Retires stale/ineligible custody without writing a terminal display fact.
  Future<bool> retireIfExact(GroupNotificationDisplayOutboxEntry expected);

  /// Promotes canonical message custody and atomically retires or re-keys a
  /// reminted logical-delivery alias marker.
  Future<bool> reconcileMessageAliasReady({
    required String aliasEventId,
    required GroupMessage canonicalMessage,
  });

  Future<int> deleteForGroup(String groupId);

  Future<int> deleteForMessage({
    required String groupId,
    required String messageId,
  });

  Future<int> deleteForReaction({
    required String groupId,
    required String messageId,
    required String reactionId,
  });

  /// Deletes ADD-transition custody for the canonical reaction owned by one
  /// actor. REMOVE payload ids intentionally cannot identify that custody.
  Future<int> deleteForReactionActor({
    required String groupId,
    required String messageId,
    required String actorPeerId,
  });
}
