import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';

final class DirectConversationReadCommit {
  const DirectConversationReadCommit({
    required this.markedCount,
    required this.notificationAcknowledged,
  });

  final int markedCount;
  final bool notificationAcknowledged;
}

typedef CommitDirectConversationRead =
    Future<DirectConversationReadCommit> Function(
      String peerId,
      ConversationNotificationContentMetadata? metadata,
    );

typedef DirectConversationReadCommitSettlement =
    Future<void> Function(String peerId);

/// Captures the exact current direct-card generation before the atomic SQL
/// read commit, then cancels that same generation after commit.
final class DirectNotificationReadProjector {
  const DirectNotificationReadProjector({
    required DirectNotificationPresentationCoordinator coordinator,
    required ConversationNotificationGenerationCancellation cancellation,
    required CommitDirectConversationRead commitRead,
    DirectConversationReadCommitSettlement? onReadCommitted,
  }) : _coordinator = coordinator,
       _cancellation = cancellation,
       _commitRead = commitRead,
       _onReadCommitted = onReadCommitted;

  final DirectNotificationPresentationCoordinator _coordinator;
  final ConversationNotificationGenerationCancellation _cancellation;
  final CommitDirectConversationRead _commitRead;
  final DirectConversationReadCommitSettlement? _onReadCommitted;

  Future<int> markConversationRead(String rawPeerId) {
    final peerId = rawPeerId.trim();
    if (peerId.isEmpty) {
      throw ArgumentError.value(rawPeerId, 'peerId', 'must not be empty');
    }
    return _coordinator.runForPeer(peerId, () async {
      // Snapshot before SQL. The durable registry compares this generation
      // again at native cancellation, preserving a later B replacement.
      final metadata = await _cancellation
          .lookupConversationNotificationContentMetadata(peerId);
      final commit = await _commitRead(peerId, metadata);
      final generation = metadata?.generation?.trim();
      try {
        if (commit.notificationAcknowledged &&
            generation != null &&
            generation.isNotEmpty) {
          await _cancellation.cancelConversationNotificationGeneration(
            peerId,
            generation,
          );
        }
      } finally {
        // APNs/NSE notifications do not necessarily have Flutter-local
        // generation metadata. The committed SQLite unread state must still
        // become the absolute iOS badge state before this read route returns.
        await _onReadCommitted?.call(peerId);
      }
      return commit.markedCount;
    });
  }
}
