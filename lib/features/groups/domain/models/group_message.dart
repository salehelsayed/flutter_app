import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// Model representing a single message in a group conversation.
///
/// Maps to the `group_messages` database table.
class GroupMessage {
  /// Unique message ID (UUID v4).
  final String id;

  /// The group this message belongs to.
  final String groupId;

  /// The peer ID of the message sender.
  final String senderPeerId;

  /// The verified transport Peer ID observed at the live or replay boundary.
  final String? transportPeerId;

  /// The display name of the sender at the time of sending.
  final String? senderUsername;

  /// The message text content.
  final String text;

  /// When the message was sent/received.
  final DateTime timestamp;

  /// When an outgoing send attempt most recently entered `sending`.
  final DateTime? lastSendAttemptAt;

  /// The message ID this message is quoting, if any.
  final String? quotedMessageId;

  /// Sender-generated identity for one logical delivery, stable across
  /// retry/replay even when local row ids diverge.
  final String? logicalDeliveryId;

  /// The key generation used to encrypt this message.
  final int keyGeneration;

  /// Delivery status: 'sending', 'pending', 'sent', 'delivered', 'failed', or
  /// the terminal [statusSendFailed] (retry budget exhausted — no longer
  /// auto-retried; only a manual retry re-arms it).
  final String status;

  /// Terminal send status: the background retrier exhausted its attempt budget
  /// for this row and stopped auto-retrying. Distinct from 'failed' (still
  /// retryable). Treated as a read-only superset of 'failed' on display paths.
  static const String statusSendFailed = 'send_failed';

  /// 210: an outgoing message composed while the sender is offline (relay
  /// unreachable). It is durably queued and self-healing — NOT a failure — so it
  /// renders a CLOCK (waiting-to-send), never a tick or an error, and the
  /// composer is not restored to a Retry state. The stuck-sending recovery sweep
  /// re-drives it into the normal retry lane when connectivity returns, where it
  /// settles to 'sent' (tick). Distinct from 'pending' (online in-doubt, still a
  /// tick) and 'sending' (online in-flight, a tick).
  static const String statusQueuedOffline = 'queued_offline';

  /// Whether this message was received from another group member.
  final bool isIncoming;

  /// When the message was read. NULL means unread.
  final DateTime? readAt;

  /// When the row was created locally.
  final DateTime createdAt;

  /// Media attachments (loaded from media_attachments table, not from this row).
  final List<MediaAttachment> media;

  /// Cached plaintext publish parameters (JSON) for retry.
  /// Not the encrypted v3 envelope — stores the inputs needed to reconstruct
  /// a `callGroupPublish` call. Does NOT contain `senderPrivateKey`.
  final String? wireEnvelope;

  /// Whether the message was stored in the inbox relay for offline members.
  /// Maps to `inbox_stored` INTEGER (0/1) in the database.
  final bool inboxStored;

  /// Cached plaintext inbox-store parameters (JSON) for retrying
  /// `callGroupInboxStore` without guessing push recipients or payload structure.
  final String? inboxRetryPayload;

  /// How many times the background retrier has re-sent this outgoing row.
  /// Drives exponential backoff and the flip to [statusSendFailed]. Read from
  /// the DB only; persisted exclusively via dedicated setters (never via
  /// [toMap]) so ordinary row updates cannot reset the backoff state.
  final int retryAttemptCount;

  /// Earliest time the retrier should re-attempt this row; null means
  /// immediately eligible. DB-read-only (see [retryAttemptCount]).
  final DateTime? nextEligibleAt;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderPeerId,
    this.transportPeerId,
    this.senderUsername,
    required this.text,
    required this.timestamp,
    this.lastSendAttemptAt,
    this.quotedMessageId,
    this.logicalDeliveryId,
    this.keyGeneration = 0,
    this.status = 'sent',
    this.isIncoming = true,
    this.readAt,
    required this.createdAt,
    this.media = const [],
    this.wireEnvelope,
    this.inboxStored = false,
    this.inboxRetryPayload,
    this.retryAttemptCount = 0,
    this.nextEligibleAt,
  });

  /// Creates a GroupMessage from a database row map.
  factory GroupMessage.fromMap(Map<String, dynamic> map) {
    return GroupMessage(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      transportPeerId: map['transport_peer_id'] as String?,
      senderUsername: map['sender_username'] as String?,
      text: map['text'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      lastSendAttemptAt: map['last_send_attempt_at'] != null
          ? DateTime.parse(map['last_send_attempt_at'] as String).toUtc()
          : null,
      quotedMessageId: map['quoted_message_id'] as String?,
      logicalDeliveryId: map['logical_delivery_id'] as String?,
      keyGeneration: map['key_generation'] as int? ?? 0,
      status: map['status'] as String? ?? 'sent',
      isIncoming: (map['is_incoming'] as int? ?? 1) == 1,
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      wireEnvelope: map['wire_envelope'] as String?,
      inboxStored: (map['inbox_stored'] as int? ?? 0) == 1,
      inboxRetryPayload: map['inbox_retry_payload'] as String?,
      retryAttemptCount: map['retry_attempt_count'] as int? ?? 0,
      nextEligibleAt: map['next_eligible_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              map['next_eligible_at'] as int,
              isUtc: true,
            )
          : null,
    );
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    final row = <String, dynamic>{
      'id': id,
      'group_id': groupId,
      'sender_peer_id': senderPeerId,
      'transport_peer_id': transportPeerId,
      'sender_username': senderUsername,
      'text': text,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'last_send_attempt_at': lastSendAttemptAt?.toUtc().toIso8601String(),
      'quoted_message_id': quotedMessageId,
      'key_generation': keyGeneration,
      'status': status,
      'is_incoming': isIncoming ? 1 : 0,
      'read_at': readAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'wire_envelope': wireEnvelope,
      'inbox_stored': inboxStored ? 1 : 0,
      'inbox_retry_payload': inboxRetryPayload,
    };
    if (logicalDeliveryId != null) {
      row['logical_delivery_id'] = logicalDeliveryId;
    }
    return row;
  }

  /// Creates a copy with updated fields.
  GroupMessage copyWith({
    String? id,
    String? groupId,
    String? senderPeerId,
    Object? transportPeerId = _sentinel,
    String? senderUsername,
    String? text,
    DateTime? timestamp,
    Object? lastSendAttemptAt = _sentinel,
    Object? quotedMessageId = _sentinel,
    Object? logicalDeliveryId = _sentinel,
    int? keyGeneration,
    String? status,
    bool? isIncoming,
    Object? readAt = _sentinel,
    DateTime? createdAt,
    List<MediaAttachment>? media,
    Object? wireEnvelope = _sentinel,
    bool? inboxStored,
    Object? inboxRetryPayload = _sentinel,
    int? retryAttemptCount,
    Object? nextEligibleAt = _sentinel,
  }) {
    return GroupMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      transportPeerId: transportPeerId == _sentinel
          ? this.transportPeerId
          : transportPeerId as String?,
      senderUsername: senderUsername ?? this.senderUsername,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      lastSendAttemptAt: lastSendAttemptAt == _sentinel
          ? this.lastSendAttemptAt
          : lastSendAttemptAt as DateTime?,
      quotedMessageId: quotedMessageId == _sentinel
          ? this.quotedMessageId
          : quotedMessageId as String?,
      logicalDeliveryId: logicalDeliveryId == _sentinel
          ? this.logicalDeliveryId
          : logicalDeliveryId as String?,
      keyGeneration: keyGeneration ?? this.keyGeneration,
      status: status ?? this.status,
      isIncoming: isIncoming ?? this.isIncoming,
      readAt: readAt == _sentinel ? this.readAt : readAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      media: media ?? this.media,
      wireEnvelope: wireEnvelope == _sentinel
          ? this.wireEnvelope
          : wireEnvelope as String?,
      inboxStored: inboxStored ?? this.inboxStored,
      inboxRetryPayload: inboxRetryPayload == _sentinel
          ? this.inboxRetryPayload
          : inboxRetryPayload as String?,
      retryAttemptCount: retryAttemptCount ?? this.retryAttemptCount,
      nextEligibleAt: nextEligibleAt == _sentinel
          ? this.nextEligibleAt
          : nextEligibleAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'GroupMessage(id: $id, groupId: $groupId, isIncoming: $isIncoming)';
  }
}

const _sentinel = Object();
