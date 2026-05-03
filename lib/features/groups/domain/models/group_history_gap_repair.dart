import 'dart:convert';

const groupHistoryGapRepairStatusDetected = 'detected';
const groupHistoryGapRepairStatusRepairing = 'repairing';
const groupHistoryGapRepairStatusRepaired = 'repaired';
const groupHistoryGapRepairStatusFailed = 'failed';

class GroupHistoryGapRepair {
  final String groupId;
  final String gapId;
  final String missingAfterMessageId;
  final String missingBeforeMessageId;
  final String expectedRangeHash;
  final String expectedHeadMessageId;
  final List<String> candidateSourcePeerIds;
  final List<String> attemptedSourcePeerIds;
  final List<String> repairedMessageIds;
  final String status;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? repairedAt;
  final DateTime? failedAt;

  const GroupHistoryGapRepair({
    required this.groupId,
    required this.gapId,
    required this.missingAfterMessageId,
    required this.missingBeforeMessageId,
    required this.expectedRangeHash,
    required this.expectedHeadMessageId,
    required this.candidateSourcePeerIds,
    this.attemptedSourcePeerIds = const <String>[],
    this.repairedMessageIds = const <String>[],
    this.status = groupHistoryGapRepairStatusDetected,
    this.failureReason,
    required this.createdAt,
    required this.updatedAt,
    this.repairedAt,
    this.failedAt,
  });

  bool get isTerminal =>
      status == groupHistoryGapRepairStatusRepaired ||
      status == groupHistoryGapRepairStatusFailed;

  factory GroupHistoryGapRepair.fromMap(Map<String, Object?> map) {
    return GroupHistoryGapRepair(
      groupId: map['group_id'] as String,
      gapId: map['gap_id'] as String,
      missingAfterMessageId: map['missing_after_message_id'] as String,
      missingBeforeMessageId: map['missing_before_message_id'] as String,
      expectedRangeHash: map['expected_range_hash'] as String,
      expectedHeadMessageId: map['expected_head_message_id'] as String,
      candidateSourcePeerIds: _decodeStringList(
        map['candidate_source_peer_ids_json'],
      ),
      attemptedSourcePeerIds: _decodeStringList(
        map['attempted_source_peer_ids_json'],
      ),
      repairedMessageIds: _decodeStringList(map['repaired_message_ids_json']),
      status: map['status'] as String? ?? groupHistoryGapRepairStatusDetected,
      failureReason: map['failure_reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      repairedAt: _parseOptionalDateTime(map['repaired_at']),
      failedAt: _parseOptionalDateTime(map['failed_at']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'group_id': groupId,
      'gap_id': gapId,
      'missing_after_message_id': missingAfterMessageId,
      'missing_before_message_id': missingBeforeMessageId,
      'expected_range_hash': expectedRangeHash,
      'expected_head_message_id': expectedHeadMessageId,
      'candidate_source_peer_ids_json': jsonEncode(candidateSourcePeerIds),
      'attempted_source_peer_ids_json': jsonEncode(attemptedSourcePeerIds),
      'repaired_message_ids_json': jsonEncode(repairedMessageIds),
      'status': status,
      'failure_reason': failureReason,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'repaired_at': repairedAt?.toUtc().toIso8601String(),
      'failed_at': failedAt?.toUtc().toIso8601String(),
    };
  }

  GroupHistoryGapRepair copyWith({
    String? groupId,
    String? gapId,
    String? missingAfterMessageId,
    String? missingBeforeMessageId,
    String? expectedRangeHash,
    String? expectedHeadMessageId,
    List<String>? candidateSourcePeerIds,
    List<String>? attemptedSourcePeerIds,
    List<String>? repairedMessageIds,
    String? status,
    Object? failureReason = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? repairedAt = _sentinel,
    Object? failedAt = _sentinel,
  }) {
    return GroupHistoryGapRepair(
      groupId: groupId ?? this.groupId,
      gapId: gapId ?? this.gapId,
      missingAfterMessageId:
          missingAfterMessageId ?? this.missingAfterMessageId,
      missingBeforeMessageId:
          missingBeforeMessageId ?? this.missingBeforeMessageId,
      expectedRangeHash: expectedRangeHash ?? this.expectedRangeHash,
      expectedHeadMessageId:
          expectedHeadMessageId ?? this.expectedHeadMessageId,
      candidateSourcePeerIds:
          candidateSourcePeerIds ?? this.candidateSourcePeerIds,
      attemptedSourcePeerIds:
          attemptedSourcePeerIds ?? this.attemptedSourcePeerIds,
      repairedMessageIds: repairedMessageIds ?? this.repairedMessageIds,
      status: status ?? this.status,
      failureReason: failureReason == _sentinel
          ? this.failureReason
          : failureReason as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      repairedAt: repairedAt == _sentinel
          ? this.repairedAt
          : repairedAt as DateTime?,
      failedAt: failedAt == _sentinel ? this.failedAt : failedAt as DateTime?,
    );
  }

  static List<String> _decodeStringList(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return const <String>[];
  }

  static DateTime? _parseOptionalDateTime(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }
}

const _sentinel = Object();
