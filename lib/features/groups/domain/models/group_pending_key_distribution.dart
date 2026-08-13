const groupPendingKeyDistributionStatusPending = 'pending';
const groupPendingKeyDistributionStatusDistributed = 'distributed';
const groupPendingKeyDistributionStatusUnreachable = 'unreachable';

bool sameExactGroupPendingKeyDistribution(
  GroupPendingKeyDistribution current,
  GroupPendingKeyDistribution expected,
) =>
    current.id == expected.id &&
    current.groupId == expected.groupId &&
    current.peerId == expected.peerId &&
    current.transportPeerId == expected.transportPeerId &&
    current.deviceId == expected.deviceId &&
    current.keyEpoch == expected.keyEpoch &&
    current.status == expected.status &&
    current.attempts == expected.attempts &&
    current.lastError == expected.lastError &&
    current.createdAt.toUtc() == expected.createdAt.toUtc() &&
    current.updatedAt.toUtc() == expected.updatedAt.toUtc() &&
    current.finalizedAt?.toUtc() == expected.finalizedAt?.toUtc();

/// Deterministic row id for a `(group, peer)` deferred-distribution entry, so a
/// re-enqueue from a later rotation merges via `UNIQUE(group_id, peer_id)`
/// instead of duplicating (INV-D4).
String groupPendingKeyDistributionId(String groupId, String peerId) =>
    'gpkd:$groupId:$peerId';

/// A sender-side record that group member [peerId] was keyless / undelivered
/// when group [groupId]'s key rotated, and owes a re-distribution of the current
/// key once it gains a usable ML-KEM key. [keyEpoch] is provenance only — the
/// drain always re-reads `getLatestKey` (INV-D2).
class GroupPendingKeyDistribution {
  final String id;
  final String groupId;
  final String peerId;
  final String? transportPeerId;
  final String? deviceId;
  final int keyEpoch;
  final String status;
  final int attempts;
  final String? lastError;

  /// Durable start of this delivery operation.
  ///
  /// A deliberate re-open advances this value even when the key epoch and
  /// device set are unchanged. Ordinary retries and pending-row merges retain
  /// it, so it is safe to bind into the protected authority identity without a
  /// schema change.
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? finalizedAt;

  /// Stable identity for this specific enqueue/re-open operation.
  int get operationGeneration => createdAt.toUtc().microsecondsSinceEpoch;

  const GroupPendingKeyDistribution({
    required this.id,
    required this.groupId,
    required this.peerId,
    this.transportPeerId,
    this.deviceId,
    required this.keyEpoch,
    this.status = groupPendingKeyDistributionStatusPending,
    this.attempts = 0,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
    this.finalizedAt,
  });

  factory GroupPendingKeyDistribution.fromMap(Map<String, Object?> map) {
    return GroupPendingKeyDistribution(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      peerId: map['peer_id'] as String,
      transportPeerId: map['transport_peer_id'] as String?,
      deviceId: map['device_id'] as String?,
      keyEpoch: map['key_epoch'] as int,
      status:
          map['status'] as String? ?? groupPendingKeyDistributionStatusPending,
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
      'peer_id': peerId,
      'transport_peer_id': transportPeerId,
      'device_id': deviceId,
      'key_epoch': keyEpoch,
      'status': status,
      'attempts': attempts,
      'last_error': lastError,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'finalized_at': finalizedAt?.toUtc().toIso8601String(),
    };
  }

  GroupPendingKeyDistribution copyWith({
    String? id,
    String? groupId,
    String? peerId,
    Object? transportPeerId = _sentinel,
    Object? deviceId = _sentinel,
    int? keyEpoch,
    String? status,
    int? attempts,
    Object? lastError = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? finalizedAt = _sentinel,
  }) {
    return GroupPendingKeyDistribution(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      peerId: peerId ?? this.peerId,
      transportPeerId: transportPeerId == _sentinel
          ? this.transportPeerId
          : transportPeerId as String?,
      deviceId: deviceId == _sentinel ? this.deviceId : deviceId as String?,
      keyEpoch: keyEpoch ?? this.keyEpoch,
      status: status ?? this.status,
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
