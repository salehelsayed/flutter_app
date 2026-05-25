String groupPendingMembershipMessageId({
  required String groupId,
  required String senderPeerId,
  required String? messageId,
  required DateTime receivedAt,
  required String payloadJson,
}) {
  final normalizedMessageId = messageId?.trim();
  if (normalizedMessageId != null && normalizedMessageId.isNotEmpty) {
    return 'membership:$groupId:$normalizedMessageId';
  }
  final payloadHash = payloadJson.codeUnits.fold<int>(
    0,
    (hash, unit) => 0x3fffffff & (hash * 31 + unit),
  );
  return 'membership:$groupId:$senderPeerId:${receivedAt.microsecondsSinceEpoch}:$payloadHash';
}

class GroupPendingMembershipMessage {
  final String id;
  final String groupId;
  final String senderPeerId;
  final String? messageId;
  final String payloadJson;
  final DateTime receivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupPendingMembershipMessage({
    required this.id,
    required this.groupId,
    required this.senderPeerId,
    this.messageId,
    required this.payloadJson,
    required this.receivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupPendingMembershipMessage.fromMap(Map<String, Object?> map) {
    return GroupPendingMembershipMessage(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      messageId: map['message_id'] as String?,
      payloadJson: map['payload_json'] as String,
      receivedAt: DateTime.parse(map['received_at'] as String).toUtc(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'sender_peer_id': senderPeerId,
      'message_id': messageId,
      'payload_json': payloadJson,
      'received_at': receivedAt.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  GroupPendingMembershipMessage copyWith({
    String? id,
    String? groupId,
    String? senderPeerId,
    Object? messageId = _sentinel,
    String? payloadJson,
    DateTime? receivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupPendingMembershipMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      messageId: messageId == _sentinel ? this.messageId : messageId as String?,
      payloadJson: payloadJson ?? this.payloadJson,
      receivedAt: receivedAt ?? this.receivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const _sentinel = Object();
