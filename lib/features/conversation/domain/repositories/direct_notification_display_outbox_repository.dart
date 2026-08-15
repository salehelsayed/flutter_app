import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';

import '../models/direct_notification_display_outbox_entry.dart';

abstract class DirectNotificationDisplayOutboxRepository {
  Future<void> stage(DirectNotificationDisplayOutboxEntry entry);

  Future<DirectNotificationDisplayOutboxEntry?> loadExact({
    required String peerId,
    required String eventKind,
    required String eventId,
  });

  Future<bool> promoteReadyIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
  });

  Future<List<DirectNotificationDisplayOutboxEntry>> loadReady({
    int limit = 20,
  });

  Future<DateTime?> loadEarliestNextAttemptAt();

  Future<bool> recordRetryIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  });

  Future<bool> completeIfExact(
    DirectNotificationDisplayOutboxEntry expected, {
    NotificationCompletedOutcomeCandidate? outcome,
  });

  Future<bool> retireIfExact(DirectNotificationDisplayOutboxEntry expected);

  Future<int> deleteForPeer(String peerId);

  Future<int> deleteForMessage({
    required String peerId,
    required String messageId,
  });

  Future<int> deleteForReactionActor({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  });
}
