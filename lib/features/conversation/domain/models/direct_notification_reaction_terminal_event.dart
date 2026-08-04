/// Current typed direct-reaction notification terminal authority.
///
/// The peer/message/actor tuple is deliberately complete so consumers never
/// need to infer direct ownership from the legacy shared reaction table.
class DirectNotificationReactionTerminalEvent {
  final String peerId;
  final String messageId;
  final String actorPeerId;
  final String reactionId;
  final String terminalEventId;
  final String? notificationAcknowledgedAt;
  final String updatedAt;

  const DirectNotificationReactionTerminalEvent({
    required this.peerId,
    required this.messageId,
    required this.actorPeerId,
    required this.reactionId,
    required this.terminalEventId,
    required this.notificationAcknowledgedAt,
    required this.updatedAt,
  });

  factory DirectNotificationReactionTerminalEvent.fromMap(
    Map<String, Object?> map,
  ) => DirectNotificationReactionTerminalEvent(
    peerId: map['peer_id'] as String,
    messageId: map['message_id'] as String,
    actorPeerId: map['actor_peer_id'] as String,
    reactionId: map['reaction_id'] as String,
    terminalEventId: map['terminal_event_id'] as String,
    notificationAcknowledgedAt: map['notification_acknowledged_at'] as String?,
    updatedAt: map['updated_at'] as String,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'peer_id': peerId,
    'message_id': messageId,
    'actor_peer_id': actorPeerId,
    'reaction_id': reactionId,
    'terminal_event_id': terminalEventId,
    'notification_acknowledged_at': notificationAcknowledgedAt,
    'updated_at': updatedAt,
  };
}
