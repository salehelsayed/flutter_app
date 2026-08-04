import '../models/direct_notification_reaction_terminal_event.dart';

abstract interface class DirectNotificationReactionTerminalRepository {
  Future<bool> upsert({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String reactionId,
    required String terminalEventId,
  });

  Future<DirectNotificationReactionTerminalEvent?> loadExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  });

  Future<DirectNotificationReactionTerminalEvent?> loadByTerminalEvent({
    required String peerId,
    required String terminalEventId,
  });

  Future<bool> markAcknowledgedIfExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
  });

  Future<bool> consumeAcknowledgementIfExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
    required String generation,
  });

  Future<int> deleteForActor({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  });

  Future<int> deleteForMessage({
    required String peerId,
    required String messageId,
  });

  Future<int> deleteForPeer(String peerId);
}
