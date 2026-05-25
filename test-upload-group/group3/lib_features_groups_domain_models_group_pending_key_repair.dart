const groupPendingKeyRepairStatusPendingKey = 'pending_key';
const groupPendingKeyRepairStatusRepaired = 'repaired';
const groupPendingKeyRepairStatusUndecryptable = 'undecryptable';

const groupPendingKeyRepairPlaceholderText =
    'Waiting for a newer group key to decrypt this message.';

class GroupPendingKeyRepair {
  final String id;
  final String groupId;
  final String messageId;
  final String? senderPeerId;
  final String? transportPeerId;
  final String payloadType;
  final int keyEpoch;
  final String? replayEnvelopeJson;
  final String status;
  final int triggerCount;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? finalizedAt;

  const GroupPendingKeyRepair({
    required this.id,
    required this.groupId,
    required this.messageId,
    this.senderPeerId,
    this.transportPeerId,
    required this.payloadType,
    required this.keyEpoch,
    this.replayEnvelopeJson,
    this.status = groupPendingKeyRepairStatusPendingKey,
    this.triggerCount = 1,
    this.attempts = 0,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
    this.finalizedAt,
  });

  factory GroupPendingKeyRepair.fromMap(Map<String, Object?> map) {
    return GroupPendingKeyRepair(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      messageId: map['message_id'] as String,
      senderPeerId: map['sender_peer_id'] as String?,
      transportPeerId: map['transport_peer_id'] as String?,
      payloadType: map['payload_type'] as String,
      keyEpoch: map['key_epoch'] as int,
      replayEnvelopeJson: map['replay_envelope_json'] as String?,
      status: map['status'] as String? ?? groupPendingKeyRepairStatusPendingKey,
      triggerCount: map['trigger_count'] as int? ?? 0,
      attempts: map['attempts'] as int? ?? 0,
      lastError: map['last_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      finalizedAt: map['finalized_at'] == null
          ? null
          : DateTime.parse(map['finalized_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'message_id': messageId,
      'sender_peer_id': senderPeerId,
      'transport_peer_id': transportPeerId,
      'payload_type': payloadType,
      'key_epoch': keyEpoch,
      'replay_envelope_json': replayEnvelopeJson,
      'status': status,
      'trigger_count': triggerCount,
      'attempts': attempts,
      'last_error': lastError,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'finalized_at': finalizedAt?.toUtc().toIso8601String(),
    };
  }

  GroupPendingKeyRepair copyWith({
    String? id,
    String? groupId,
    String? messageId,
    Object? senderPeerId = _sentinel,
    Object? transportPeerId = _sentinel,
    String? payloadType,
    int? keyEpoch,
    Object? replayEnvelopeJson = _sentinel,
    String? status,
    int? triggerCount,
    int? attempts,
    Object? lastError = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? finalizedAt = _sentinel,
  }) {
    return GroupPendingKeyRepair(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      messageId: messageId ?? this.messageId,
      senderPeerId: senderPeerId == _sentinel
          ? this.senderPeerId
          : senderPeerId as String?,
      transportPeerId: transportPeerId == _sentinel
          ? this.transportPeerId
          : transportPeerId as String?,
      payloadType: payloadType ?? this.payloadType,
      keyEpoch: keyEpoch ?? this.keyEpoch,
      replayEnvelopeJson: replayEnvelopeJson == _sentinel
          ? this.replayEnvelopeJson
          : replayEnvelopeJson as String?,
      status: status ?? this.status,
      triggerCount: triggerCount ?? this.triggerCount,
      attempts: attempts ?? this.attempts,
      lastError: lastError == _sentinel ? this.lastError : lastError as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      finalizedAt: finalizedAt == _sentinel
          ? this.finalizedAt
          : finalizedAt as DateTime?,
    );
  }
}

const _sentinel = Object();
