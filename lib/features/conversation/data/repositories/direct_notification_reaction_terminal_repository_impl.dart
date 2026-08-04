import '../../domain/models/direct_notification_reaction_terminal_event.dart';
import '../../domain/repositories/direct_notification_reaction_terminal_repository.dart';

class DirectNotificationReactionTerminalRepositoryImpl
    implements DirectNotificationReactionTerminalRepository {
  final Future<bool> Function({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String reactionId,
    required String terminalEventId,
    required String updatedAt,
  })
  dbUpsert;
  final Future<Map<String, Object?>?> Function({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  })
  dbLoadExact;
  final Future<Map<String, Object?>?> Function({
    required String peerId,
    required String terminalEventId,
  })
  dbLoadByTerminalEvent;
  final Future<bool> Function({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
    required String acknowledgedAt,
  })
  dbMarkAcknowledgedIfExact;
  final Future<bool> Function({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
    required String generation,
  })
  dbConsumeAcknowledgementIfExact;
  final Future<int> Function({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  })
  dbDeleteForActor;
  final Future<int> Function({
    required String peerId,
    required String messageId,
  })
  dbDeleteForMessage;
  final Future<int> Function(String peerId) dbDeleteForPeer;
  final DateTime Function() now;

  DirectNotificationReactionTerminalRepositoryImpl({
    required this.dbUpsert,
    required this.dbLoadExact,
    required this.dbLoadByTerminalEvent,
    required this.dbMarkAcknowledgedIfExact,
    required this.dbConsumeAcknowledgementIfExact,
    required this.dbDeleteForActor,
    required this.dbDeleteForMessage,
    required this.dbDeleteForPeer,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  Future<bool> upsert({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String reactionId,
    required String terminalEventId,
  }) => dbUpsert(
    peerId: peerId,
    messageId: messageId,
    actorPeerId: actorPeerId,
    reactionId: reactionId,
    terminalEventId: terminalEventId,
    updatedAt: now().toUtc().toIso8601String(),
  );

  @override
  Future<DirectNotificationReactionTerminalEvent?> loadExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) async {
    final row = await dbLoadExact(
      peerId: peerId,
      messageId: messageId,
      actorPeerId: actorPeerId,
    );
    return row == null
        ? null
        : DirectNotificationReactionTerminalEvent.fromMap(row);
  }

  @override
  Future<DirectNotificationReactionTerminalEvent?> loadByTerminalEvent({
    required String peerId,
    required String terminalEventId,
  }) async {
    final row = await dbLoadByTerminalEvent(
      peerId: peerId,
      terminalEventId: terminalEventId,
    );
    return row == null
        ? null
        : DirectNotificationReactionTerminalEvent.fromMap(row);
  }

  @override
  Future<bool> markAcknowledgedIfExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
  }) => dbMarkAcknowledgedIfExact(
    peerId: peerId,
    messageId: messageId,
    actorPeerId: actorPeerId,
    terminalEventId: terminalEventId,
    acknowledgedAt: now().toUtc().toIso8601String(),
  );

  @override
  Future<bool> consumeAcknowledgementIfExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
    required String generation,
  }) => dbConsumeAcknowledgementIfExact(
    peerId: peerId,
    messageId: messageId,
    actorPeerId: actorPeerId,
    terminalEventId: terminalEventId,
    generation: generation,
  );

  @override
  Future<int> deleteForActor({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) => dbDeleteForActor(
    peerId: peerId,
    messageId: messageId,
    actorPeerId: actorPeerId,
  );

  @override
  Future<int> deleteForMessage({
    required String peerId,
    required String messageId,
  }) => dbDeleteForMessage(peerId: peerId, messageId: messageId);

  @override
  Future<int> deleteForPeer(String peerId) => dbDeleteForPeer(peerId);
}
