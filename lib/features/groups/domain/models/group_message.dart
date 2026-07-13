import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import 'group_private_media_policy.dart';

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

  /// 236: whether this message was created by an explicit internal Forward.
  ///
  /// Origin-minimizing: true says only "forwarded" — no source sender, group,
  /// message, or attachment identity is ever stored or transported with it.
  /// Legacy rows and absent/malformed wire values decode as false.
  final bool isForwarded;

  /// Versioned group private-media policy persisted on this exact parent row.
  final GroupPrivateMediaPolicy privateMediaPolicy;

  /// Durable local receipt/custody anchor in UTC Unix epoch milliseconds.
  ///
  /// Incoming rows anchor at receiver commit; outgoing rows anchor at first
  /// custody success. The historical database column name is shared by both.
  final int? mediaReceivedAt;

  final int? mediaExpiresAt;
  final int? mediaLastCheckedAt;
  final int? mediaConsumedAt;
  final int? mediaExpiredAt;
  final bool mediaCleanupPending;

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
    this.isForwarded = false,
    this.privateMediaPolicy = const GroupPrivateMediaPolicy.ordinary(),
    this.mediaReceivedAt,
    this.mediaExpiresAt,
    this.mediaLastCheckedAt,
    this.mediaConsumedAt,
    this.mediaExpiredAt,
    this.mediaCleanupPending = false,
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
    var privateMediaPolicy = GroupPrivateMediaPolicy.fromDatabase(
      version: map['media_policy_version'],
      lifecycle: map['media_lifecycle'],
      durationSeconds: map['media_duration_seconds'],
      protected: map['media_protected'],
    );
    var mediaReceivedAt = _nonnegativeInt(map['media_received_at']);
    var mediaExpiresAt = _nonnegativeInt(map['media_expires_at']);
    var mediaLastCheckedAt = _nonnegativeInt(map['media_last_checked_at']);
    var mediaConsumedAt = _nonnegativeInt(map['media_consumed_at']);
    var mediaExpiredAt = _nonnegativeInt(map['media_expired_at']);
    final rawTimestamps = <Object?>[
      map['media_received_at'],
      map['media_expires_at'],
      map['media_last_checked_at'],
      map['media_consumed_at'],
      map['media_expired_at'],
    ];
    final hasMalformedTimestamp = rawTimestamps.any(
      (value) => value != null && _nonnegativeInt(value) == null,
    );
    final rawCleanupPending = map['media_cleanup_pending'];
    var mediaCleanupPending = rawCleanupPending == 1;
    final hasMalformedCleanup =
        rawCleanupPending != null &&
        rawCleanupPending != 0 &&
        rawCleanupPending != 1;
    if (hasMalformedTimestamp ||
        hasMalformedCleanup ||
        !_isConsistentPrivateMediaState(
          policy: privateMediaPolicy,
          receivedAt: mediaReceivedAt,
          expiresAt: mediaExpiresAt,
          lastCheckedAt: mediaLastCheckedAt,
          consumedAt: mediaConsumedAt,
          expiredAt: mediaExpiredAt,
          cleanupPending: mediaCleanupPending,
        )) {
      privateMediaPolicy = GroupPrivateMediaPolicy.unsupported(
        sourceVersion: privateMediaPolicy.version < 0
            ? 0
            : privateMediaPolicy.version,
      );
      mediaReceivedAt = null;
      mediaExpiresAt = null;
      mediaLastCheckedAt = null;
      mediaConsumedAt = null;
      mediaExpiredAt = null;
      mediaCleanupPending = false;
    }
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
      isForwarded: ((map['is_forwarded'] as num?)?.toInt() ?? 0) == 1,
      privateMediaPolicy: privateMediaPolicy,
      mediaReceivedAt: mediaReceivedAt,
      mediaExpiresAt: mediaExpiresAt,
      mediaLastCheckedAt: mediaLastCheckedAt,
      mediaConsumedAt: mediaConsumedAt,
      mediaExpiredAt: mediaExpiredAt,
      mediaCleanupPending: mediaCleanupPending,
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
      'is_forwarded': isForwarded ? 1 : 0,
      ...privateMediaPolicy.toDatabaseMap(),
      'media_received_at': mediaReceivedAt,
      'media_expires_at': mediaExpiresAt,
      'media_last_checked_at': mediaLastCheckedAt,
      'media_consumed_at': mediaConsumedAt,
      'media_expired_at': mediaExpiredAt,
      'media_cleanup_pending': mediaCleanupPending ? 1 : 0,
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
    bool? isForwarded,
    GroupPrivateMediaPolicy? privateMediaPolicy,
    Object? mediaReceivedAt = _sentinel,
    Object? mediaExpiresAt = _sentinel,
    Object? mediaLastCheckedAt = _sentinel,
    Object? mediaConsumedAt = _sentinel,
    Object? mediaExpiredAt = _sentinel,
    bool? mediaCleanupPending,
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
      isForwarded: isForwarded ?? this.isForwarded,
      privateMediaPolicy: privateMediaPolicy ?? this.privateMediaPolicy,
      mediaReceivedAt: mediaReceivedAt == _sentinel
          ? this.mediaReceivedAt
          : mediaReceivedAt as int?,
      mediaExpiresAt: mediaExpiresAt == _sentinel
          ? this.mediaExpiresAt
          : mediaExpiresAt as int?,
      mediaLastCheckedAt: mediaLastCheckedAt == _sentinel
          ? this.mediaLastCheckedAt
          : mediaLastCheckedAt as int?,
      mediaConsumedAt: mediaConsumedAt == _sentinel
          ? this.mediaConsumedAt
          : mediaConsumedAt as int?,
      mediaExpiredAt: mediaExpiredAt == _sentinel
          ? this.mediaExpiredAt
          : mediaExpiredAt as int?,
      mediaCleanupPending: mediaCleanupPending ?? this.mediaCleanupPending,
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

  int get mediaPolicyVersion => privateMediaPolicy.version;

  GroupPrivateMediaPolicy get mediaPolicy => privateMediaPolicy;

  GroupMediaLifecycle get mediaLifecycle => privateMediaPolicy.lifecycle;

  int? get mediaDurationSeconds => privateMediaPolicy.durationSeconds;

  bool get mediaProtected => privateMediaPolicy.protected;
}

const _sentinel = Object();

int? _nonnegativeInt(Object? value) =>
    value is int && value >= 0 ? value : null;

bool _isConsistentPrivateMediaState({
  required GroupPrivateMediaPolicy policy,
  required int? receivedAt,
  required int? expiresAt,
  required int? lastCheckedAt,
  required int? consumedAt,
  required int? expiredAt,
  required bool cleanupPending,
}) {
  final hasLocalClaim =
      receivedAt != null ||
      expiresAt != null ||
      lastCheckedAt != null ||
      consumedAt != null ||
      expiredAt != null ||
      cleanupPending;
  if (policy.isOrdinary) return !hasLocalClaim;
  if (policy.isUnsupported) {
    return expiresAt == null && consumedAt == null && expiredAt == null;
  }
  if (!policy.isPrivate) return false;
  if (cleanupPending && consumedAt == null && expiredAt == null) return false;
  switch (policy.lifecycle) {
    case GroupMediaLifecycle.standard:
      return expiresAt == null && consumedAt == null && expiredAt == null;
    case GroupMediaLifecycle.viewOnce:
      return expiresAt == null && expiredAt == null;
    case GroupMediaLifecycle.disappearing:
      return consumedAt == null;
    case GroupMediaLifecycle.unsupported:
      return false;
  }
}
