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

/// Captures the exact current direct-card generation before the atomic SQL
/// read commit, then cancels that same generation after commit.
final class DirectNotificationReadProjector {
  const DirectNotificationReadProjector({
    required DirectNotificationPresentationCoordinator coordinator,
    required ConversationNotificationGenerationCancellation cancellation,
    required CommitDirectConversationRead commitRead,
  }) : _coordinator = coordinator,
       _cancellation = cancellation,
       _commitRead = commitRead;

  final DirectNotificationPresentationCoordinator _coordinator;
  final ConversationNotificationGenerationCancellation _cancellation;
  final CommitDirectConversationRead _commitRead;

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
      if (commit.notificationAcknowledged &&
          generation != null &&
          generation.isNotEmpty) {
        await _cancellation.cancelConversationNotificationGeneration(
          peerId,
          generation,
        );
      }
      return commit.markedCount;
    });
  }
}
