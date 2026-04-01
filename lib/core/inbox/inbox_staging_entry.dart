import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

class InboxStagingEntry {
  final String entryId;
  final String ownerPeerId;
  final String senderPeerId;
  final String? messageType;
  final String relayTimestamp;
  final String envelope;
  final String status;
  final int attemptCount;
  final String stagedAt;
  final String? lastAttemptedAt;
  final String? rejectReasonCode;
  final String? rejectReasonDetail;

  const InboxStagingEntry({
    required this.entryId,
    required this.ownerPeerId,
    required this.senderPeerId,
    required this.relayTimestamp,
    required this.envelope,
    required this.stagedAt,
    this.messageType,
    this.status = 'pending',
    this.attemptCount = 0,
    this.lastAttemptedAt,
    this.rejectReasonCode,
    this.rejectReasonDetail,
  });

  factory InboxStagingEntry.fromMap(Map<String, Object?> row) {
    return InboxStagingEntry(
      entryId: row['entry_id'] as String,
      ownerPeerId: row['owner_peer_id'] as String,
      senderPeerId: row['sender_peer_id'] as String,
      messageType: row['message_type'] as String?,
      relayTimestamp: row['relay_timestamp'] as String,
      envelope: row['envelope'] as String,
      status: row['status'] as String? ?? 'pending',
      attemptCount: row['attempt_count'] as int? ?? 0,
      stagedAt: row['staged_at'] as String,
      lastAttemptedAt: row['last_attempted_at'] as String?,
      rejectReasonCode: row['reject_reason_code'] as String?,
      rejectReasonDetail: row['reject_reason_detail'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'entry_id': entryId,
      'owner_peer_id': ownerPeerId,
      'sender_peer_id': senderPeerId,
      'message_type': messageType,
      'relay_timestamp': relayTimestamp,
      'envelope': envelope,
      'status': status,
      'attempt_count': attemptCount,
      'staged_at': stagedAt,
      'last_attempted_at': lastAttemptedAt,
      'reject_reason_code': rejectReasonCode,
      'reject_reason_detail': rejectReasonDetail,
    };
  }

  InboxStagingEntry copyWith({
    String? entryId,
    String? ownerPeerId,
    String? senderPeerId,
    String? messageType,
    String? relayTimestamp,
    String? envelope,
    String? status,
    int? attemptCount,
    String? stagedAt,
    String? lastAttemptedAt,
    String? rejectReasonCode,
    String? rejectReasonDetail,
  }) {
    return InboxStagingEntry(
      entryId: entryId ?? this.entryId,
      ownerPeerId: ownerPeerId ?? this.ownerPeerId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      messageType: messageType ?? this.messageType,
      relayTimestamp: relayTimestamp ?? this.relayTimestamp,
      envelope: envelope ?? this.envelope,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      stagedAt: stagedAt ?? this.stagedAt,
      lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
      rejectReasonCode: rejectReasonCode ?? this.rejectReasonCode,
      rejectReasonDetail: rejectReasonDetail ?? this.rejectReasonDetail,
    );
  }

  ChatMessage toChatMessage() {
    return ChatMessage(
      from: senderPeerId,
      to: ownerPeerId,
      content: envelope,
      timestamp: relayTimestamp,
      isIncoming: true,
      transport: 'inbox',
    );
  }
}
