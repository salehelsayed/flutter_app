import '../../../../core/database/direct_reaction_inbox_custody_outbox_contract.dart';
import 'message_reaction.dart';

export '../../../../core/database/direct_reaction_inbox_custody_outbox_contract.dart';

/// One immutable sender-owned copy of an encrypted direct-reaction event.
class DirectReactionInboxCustodyOutboxEntry {
  const DirectReactionInboxCustodyOutboxEntry({
    required this.recipientPeerId,
    required this.eventId,
    required this.wireEnvelope,
    required this.retryCount,
    required this.lastAttemptAt,
    required this.lastErrorCode,
    this.contactAccountPeerId,
    this.parentMessageId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String recipientPeerId;
  final String eventId;
  final String wireEnvelope;
  final int retryCount;
  final String? lastAttemptAt;
  final String? lastErrorCode;

  /// 361: the LOGICAL contact of a v113 fanout sibling. NULL retains the
  /// incumbent single-target meaning ([recipientPeerId] IS the contact).
  final String? contactAccountPeerId;

  /// 361: the logical parent a new fanout event names at authoring time. A
  /// historical deletion may keep NULL even after its parent/contact is gone.
  final String? parentMessageId;

  final String createdAt;
  final String updatedAt;

  factory DirectReactionInboxCustodyOutboxEntry.fromMap(
    Map<String, Object?> map,
  ) => DirectReactionInboxCustodyOutboxEntry(
    recipientPeerId: map['recipient_peer_id'] as String,
    eventId: map['event_id'] as String,
    wireEnvelope: map['wire_envelope'] as String,
    retryCount: (map['retry_count'] as num).toInt(),
    lastAttemptAt: map['last_attempt_at'] as String?,
    lastErrorCode: map['last_error_code'] as String?,
    contactAccountPeerId: map['contact_account_peer_id'] as String?,
    parentMessageId: map['parent_message_id'] as String?,
    createdAt: map['created_at'] as String,
    updatedAt: map['updated_at'] as String,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'recipient_peer_id': recipientPeerId,
    'event_id': eventId,
    'wire_envelope': wireEnvelope,
    'retry_count': retryCount,
    'last_attempt_at': lastAttemptAt,
    'last_error_code': lastErrorCode,
    'contact_account_peer_id': contactAccountPeerId,
    'parent_message_id': parentMessageId,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  DirectReactionInboxCustodyOutboxEntry copyWith({
    String? recipientPeerId,
    String? eventId,
    String? wireEnvelope,
    int? retryCount,
    Object? lastAttemptAt = _unset,
    Object? lastErrorCode = _unset,
    Object? contactAccountPeerId = _unset,
    Object? parentMessageId = _unset,
    String? createdAt,
    String? updatedAt,
  }) => DirectReactionInboxCustodyOutboxEntry(
    recipientPeerId: recipientPeerId ?? this.recipientPeerId,
    eventId: eventId ?? this.eventId,
    wireEnvelope: wireEnvelope ?? this.wireEnvelope,
    retryCount: retryCount ?? this.retryCount,
    lastAttemptAt: identical(lastAttemptAt, _unset)
        ? this.lastAttemptAt
        : lastAttemptAt as String?,
    lastErrorCode: identical(lastErrorCode, _unset)
        ? this.lastErrorCode
        : lastErrorCode as String?,
    contactAccountPeerId: identical(contactAccountPeerId, _unset)
        ? this.contactAccountPeerId
        : contactAccountPeerId as String?,
    parentMessageId: identical(parentMessageId, _unset)
        ? this.parentMessageId
        : parentMessageId as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Repository-level stage result. [reaction] is the exact authored transition
/// whose encrypted obligation committed; the canonical projection may already
/// contain a newer distinct transition. [custody] is its exact CAS handle.
class DirectReactionCustodyStageResult {
  const DirectReactionCustodyStageResult({
    required this.outcome,
    required this.reaction,
    required this.custody,
  });

  const DirectReactionCustodyStageResult.refused()
    : outcome = DirectReactionCustodyStageOutcome.refused,
      reaction = null,
      custody = null;

  final DirectReactionCustodyStageOutcome outcome;
  final MessageReaction? reaction;
  final DirectReactionInboxCustodyOutboxEntry? custody;

  bool get authorizesTransport => outcome.authorizesTransport;
}

const Object _unset = Object();
