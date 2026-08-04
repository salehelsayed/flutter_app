class DirectNotificationReadAcknowledgementKind {
  static const String message = 'message';
  static const String reaction = 'reaction';
}

/// Exact, identifier-only read custody for one direct notification generation.
class DirectNotificationReadAcknowledgement {
  final String peerId;
  final String contentKind;
  final String eventIdentity;
  final String messageId;
  final String? actorPeerId;
  final String generation;
  final String acknowledgedAt;

  const DirectNotificationReadAcknowledgement({
    required this.peerId,
    required this.contentKind,
    required this.eventIdentity,
    required this.messageId,
    required this.actorPeerId,
    required this.generation,
    required this.acknowledgedAt,
  });

  const DirectNotificationReadAcknowledgement.message({
    required String peerId,
    required String messageId,
    required String generation,
    required String acknowledgedAt,
  }) : this(
         peerId: peerId,
         contentKind: DirectNotificationReadAcknowledgementKind.message,
         eventIdentity: messageId,
         messageId: messageId,
         actorPeerId: null,
         generation: generation,
         acknowledgedAt: acknowledgedAt,
       );

  const DirectNotificationReadAcknowledgement.reaction({
    required String peerId,
    required String eventIdentity,
    required String messageId,
    required String actorPeerId,
    required String generation,
    required String acknowledgedAt,
  }) : this(
         peerId: peerId,
         contentKind: DirectNotificationReadAcknowledgementKind.reaction,
         eventIdentity: eventIdentity,
         messageId: messageId,
         actorPeerId: actorPeerId,
         generation: generation,
         acknowledgedAt: acknowledgedAt,
       );

  factory DirectNotificationReadAcknowledgement.fromMap(
    Map<String, Object?> map,
  ) => DirectNotificationReadAcknowledgement(
    peerId: map['peer_id'] as String,
    contentKind: map['content_kind'] as String,
    eventIdentity: map['event_identity'] as String,
    messageId: map['message_id'] as String,
    actorPeerId: map['actor_peer_id'] as String?,
    generation: map['generation'] as String,
    acknowledgedAt: map['acknowledged_at'] as String,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'peer_id': peerId,
    'content_kind': contentKind,
    'event_identity': eventIdentity,
    'message_id': messageId,
    'actor_peer_id': actorPeerId,
    'generation': generation,
    'acknowledged_at': acknowledgedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectNotificationReadAcknowledgement &&
          other.peerId == peerId &&
          other.contentKind == contentKind &&
          other.eventIdentity == eventIdentity &&
          other.messageId == messageId &&
          other.actorPeerId == actorPeerId &&
          other.generation == generation &&
          other.acknowledgedAt == acknowledgedAt;

  @override
  int get hashCode => Object.hash(
    peerId,
    contentKind,
    eventIdentity,
    messageId,
    actorPeerId,
    generation,
    acknowledgedAt,
  );
}
