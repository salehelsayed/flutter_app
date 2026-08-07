import '../../../../core/database/direct_inbox_custody_outbox_contract.dart';
import 'conversation_message.dart';

export '../../../../core/database/direct_inbox_custody_outbox_contract.dart';

/// One immutable sender-owned copy of an encrypted direct-text event.
///
/// The envelope is deliberately opaque. Consumers must replay it byte-for-byte
/// and must never decrypt, replace, or log it while this incarnation is owned.
class DirectInboxCustodyOutboxEntry {
  const DirectInboxCustodyOutboxEntry({
    required this.recipientPeerId,
    required this.messageId,
    required this.incarnationId,
    required this.wireEnvelope,
    required this.retryCount,
    required this.lastAttemptAt,
    required this.lastErrorCode,
    required this.createdAt,
    required this.updatedAt,
  });

  final String recipientPeerId;
  final String messageId;
  final String incarnationId;
  final String wireEnvelope;
  final int retryCount;
  final String? lastAttemptAt;
  final String? lastErrorCode;
  final String createdAt;
  final String updatedAt;

  factory DirectInboxCustodyOutboxEntry.fromMap(Map<String, Object?> map) =>
      DirectInboxCustodyOutboxEntry(
        recipientPeerId: map['recipient_peer_id'] as String,
        messageId: map['message_id'] as String,
        incarnationId: map['incarnation_id'] as String,
        wireEnvelope: map['wire_envelope'] as String,
        retryCount: (map['retry_count'] as num).toInt(),
        lastAttemptAt: map['last_attempt_at'] as String?,
        lastErrorCode: map['last_error_code'] as String?,
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  Map<String, Object?> toMap() => <String, Object?>{
    'recipient_peer_id': recipientPeerId,
    'message_id': messageId,
    'incarnation_id': incarnationId,
    'wire_envelope': wireEnvelope,
    'retry_count': retryCount,
    'last_attempt_at': lastAttemptAt,
    'last_error_code': lastErrorCode,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  DirectInboxCustodyOutboxEntry copyWith({
    String? recipientPeerId,
    String? messageId,
    String? incarnationId,
    String? wireEnvelope,
    int? retryCount,
    Object? lastAttemptAt = _unset,
    Object? lastErrorCode = _unset,
    String? createdAt,
    String? updatedAt,
  }) => DirectInboxCustodyOutboxEntry(
    recipientPeerId: recipientPeerId ?? this.recipientPeerId,
    messageId: messageId ?? this.messageId,
    incarnationId: incarnationId ?? this.incarnationId,
    wireEnvelope: wireEnvelope ?? this.wireEnvelope,
    retryCount: retryCount ?? this.retryCount,
    lastAttemptAt: identical(lastAttemptAt, _unset)
        ? this.lastAttemptAt
        : lastAttemptAt as String?,
    lastErrorCode: identical(lastErrorCode, _unset)
        ? this.lastErrorCode
        : lastErrorCode as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Repository-level accepted-completion result with authoritative message
/// state. [message] is null for a removed message and for a stale incarnation.
class DirectInboxCustodyCompletionResult {
  const DirectInboxCustodyCompletionResult({
    required this.outcome,
    required this.message,
  });

  final DirectInboxCustodyCompletionOutcome outcome;
  final ConversationMessage? message;

  bool get completed => outcome.completed;
  bool get messageChanged => outcome.messageChanged;
}

const Object _unset = Object();
