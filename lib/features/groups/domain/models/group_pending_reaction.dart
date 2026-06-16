/// A fully-validated group reaction durably buffered because its target
/// message had not yet arrived. Replayed through the reaction use case once the
/// message lands (INV-R4). The [id] is the deterministic reaction id, which
/// doubles as the dedup key (INV-R5).
class GroupPendingReaction {
  final String id;
  final String groupId;
  final String messageId;
  final String senderPeerId;
  final String? transportPeerId;
  final String? senderDeviceId;
  final String? senderPublicKey;

  /// The raw decrypted inner reaction JSON, replayed verbatim on flush.
  final String reactionJson;
  final DateTime receivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupPendingReaction({
    required this.id,
    required this.groupId,
    required this.messageId,
    required this.senderPeerId,
    this.transportPeerId,
    this.senderDeviceId,
    this.senderPublicKey,
    required this.reactionJson,
    required this.receivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupPendingReaction.fromMap(Map<String, Object?> map) {
    return GroupPendingReaction(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      messageId: map['message_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      transportPeerId: map['transport_peer_id'] as String?,
      senderDeviceId: map['sender_device_id'] as String?,
      senderPublicKey: map['sender_public_key'] as String?,
      reactionJson: map['reaction_json'] as String,
      receivedAt: DateTime.parse(map['received_at'] as String).toUtc(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'message_id': messageId,
      'sender_peer_id': senderPeerId,
      'transport_peer_id': transportPeerId,
      'sender_device_id': senderDeviceId,
      'sender_public_key': senderPublicKey,
      'reaction_json': reactionJson,
      'received_at': receivedAt.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  GroupPendingReaction copyWith({
    String? id,
    String? groupId,
    String? messageId,
    String? senderPeerId,
    Object? transportPeerId = _sentinel,
    Object? senderDeviceId = _sentinel,
    Object? senderPublicKey = _sentinel,
    String? reactionJson,
    DateTime? receivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupPendingReaction(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      messageId: messageId ?? this.messageId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      transportPeerId: transportPeerId == _sentinel
          ? this.transportPeerId
          : transportPeerId as String?,
      senderDeviceId: senderDeviceId == _sentinel
          ? this.senderDeviceId
          : senderDeviceId as String?,
      senderPublicKey: senderPublicKey == _sentinel
          ? this.senderPublicKey
          : senderPublicKey as String?,
      reactionJson: reactionJson ?? this.reactionJson,
      receivedAt: receivedAt ?? this.receivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const _sentinel = Object();
