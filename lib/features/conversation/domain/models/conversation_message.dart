import 'package:flutter_app/core/media/private_media_policy.dart';

import 'media_attachment.dart';

/// Model representing a single message in a conversation.
///
/// Maps to the `messages` database table. Each message belongs to a
/// conversation identified by `contactPeerId`.
class ConversationMessage {
  /// Unique message ID (UUID v4).
  final String id;

  /// The peer ID of the contact this conversation belongs to.
  final String contactPeerId;

  /// The peer ID of the message sender.
  final String senderPeerId;

  /// The message text content.
  final String text;

  /// ISO-8601 timestamp when the message was created.
  final String timestamp;

  /// Delivery status: 'sending', 'sent', 'delivered', 'failed'.
  /// Legacy rows may still contain 'queued' until status-cleanup migration runs.
  final String status;

  /// Whether this message was received from the contact.
  final bool isIncoming;

  /// ISO-8601 timestamp when the row was created locally.
  final String createdAt;

  /// ISO-8601 timestamp when the message was last edited. NULL means original.
  final String? editedAt;

  /// ISO-8601 timestamp when the message was read. NULL means unread.
  final String? readAt;

  /// The ID of the message being quoted (quote-reply). NULL means no quote.
  final String? quotedMessageId;

  /// ISO-8601 timestamp when the message was deleted. NULL means not deleted.
  final String? deletedAt;

  /// Peer ID that initiated the deletion. NULL means not deleted.
  final String? deletedByPeerId;

  /// ISO-8601 timestamp when the row became hidden locally.
  ///
  /// This is used for sender-side delete-for-everyone semantics: keep a
  /// durable retry row locally without surfacing the deleted content.
  final String? hiddenAt;

  /// Transport type: 'wifi', 'local', 'direct', legacy-only 'reuse',
  /// 'relay', 'inbox', or null (unknown/pre-migration).
  final String? transport;

  /// Serialized wire envelope (JSON) for retry. NULL once delivered.
  final String? wireEnvelope;

  /// Relay-stamped custody expiry (ms epoch) for 'inboxed' rows. NULL when
  /// the relay did not report one (old relay) or the row never rode inbox
  /// custody.
  final int? relayExpiresAt;

  /// ISO-8601 timestamp of the last custody-sweep check on an 'inboxed' row.
  final String? custodyCheckedAt;

  /// F8 tier-2: wire-stamped logical-delivery identifier (a normal send stamps
  /// its own id; one explicit Forward action stamps a random operation token).
  /// Survives that action's id+timestamp re-mint; the receiver dedups on
  /// `(contact_peer_id, sender_peer_id, dedup_key)`. NULL for legacy rows.
  final String? dedupKey;

  /// Whether this direct message was created by an explicit in-app Forward.
  /// Legacy database rows default to false.
  final bool isForwarded;

  /// Versioned policy carried only in encrypted direct-message payloads.
  final PrivateMediaPolicy privateMediaPolicy;

  /// Durable device-local lifecycle state for the direct parent row.
  final PrivateMediaLifecycleState privateMediaState;

  final int? privateMediaReceivedAtMs;
  final int? privateMediaExpiresAtMs;
  final int? privateMediaRevealedAtMs;
  final int? privateMediaTerminalAtMs;
  final int? privateMediaClockHighWaterMs;

  /// Transient media attachments — populated via copyWith() after batch-loading
  /// from media_attachments table. NOT serialized to DB.
  final List<MediaAttachment> media;

  const ConversationMessage({
    required this.id,
    required this.contactPeerId,
    required this.senderPeerId,
    required this.text,
    required this.timestamp,
    required this.status,
    required this.isIncoming,
    required this.createdAt,
    this.editedAt,
    this.readAt,
    this.quotedMessageId,
    this.deletedAt,
    this.deletedByPeerId,
    this.hiddenAt,
    this.transport,
    this.wireEnvelope,
    this.relayExpiresAt,
    this.custodyCheckedAt,
    this.dedupKey,
    this.isForwarded = false,
    this.privateMediaPolicy = const PrivateMediaPolicy.ordinary(),
    this.privateMediaState = PrivateMediaLifecycleState.none,
    this.privateMediaReceivedAtMs,
    this.privateMediaExpiresAtMs,
    this.privateMediaRevealedAtMs,
    this.privateMediaTerminalAtMs,
    this.privateMediaClockHighWaterMs,
    this.media = const [],
  });

  /// Creates a ConversationMessage from a database row map.
  factory ConversationMessage.fromMap(Map<String, dynamic> map) {
    final privateMediaPolicy = PrivateMediaPolicy.fromDatabase(
      version: map['private_media_policy_version'],
      mode: map['private_media_mode'],
      durationSeconds: map['private_media_duration_seconds'],
    );
    final rawPrivateState = map['private_media_state'];
    final parsedPrivateState = rawPrivateState == null
        ? privateMediaPolicy.initialState
        : PrivateMediaLifecycleState.fromWireValue(rawPrivateState);
    return ConversationMessage(
      id: map['id'] as String,
      contactPeerId: map['contact_peer_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      text: map['text'] as String,
      timestamp: map['timestamp'] as String,
      status: map['status'] as String? ?? 'sent',
      isIncoming: (map['is_incoming'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String,
      editedAt: map['edited_at'] as String?,
      readAt: map['read_at'] as String?,
      quotedMessageId: map['quoted_message_id'] as String?,
      deletedAt: map['deleted_at'] as String?,
      deletedByPeerId: map['deleted_by_peer_id'] as String?,
      hiddenAt: map['hidden_at'] as String?,
      transport: map['transport'] as String?,
      wireEnvelope: map['wire_envelope'] as String?,
      relayExpiresAt: map['relay_expires_at'] as int?,
      custodyCheckedAt: map['custody_checked_at'] as String?,
      dedupKey: map['dedup_key'] as String?,
      isForwarded: ((map['is_forwarded'] as num?)?.toInt() ?? 0) == 1,
      privateMediaPolicy: privateMediaPolicy,
      privateMediaState: privateMediaPolicy.isUnsupported
          ? PrivateMediaLifecycleState.unsupported
          : parsedPrivateState,
      privateMediaReceivedAtMs: (map['private_media_received_at_ms'] as num?)
          ?.toInt(),
      privateMediaExpiresAtMs: (map['private_media_expires_at_ms'] as num?)
          ?.toInt(),
      privateMediaRevealedAtMs: (map['private_media_revealed_at_ms'] as num?)
          ?.toInt(),
      privateMediaTerminalAtMs: (map['private_media_terminal_at_ms'] as num?)
          ?.toInt(),
      privateMediaClockHighWaterMs:
          (map['private_media_clock_high_water_ms'] as num?)?.toInt(),
    );
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contact_peer_id': contactPeerId,
      'sender_peer_id': senderPeerId,
      'text': text,
      'timestamp': timestamp,
      'status': status,
      'is_incoming': isIncoming ? 1 : 0,
      'created_at': createdAt,
      'edited_at': editedAt,
      'read_at': readAt,
      'quoted_message_id': quotedMessageId,
      'deleted_at': deletedAt,
      'deleted_by_peer_id': deletedByPeerId,
      'hidden_at': hiddenAt,
      'transport': transport,
      'wire_envelope': wireEnvelope,
      'relay_expires_at': relayExpiresAt,
      'custody_checked_at': custodyCheckedAt,
      'dedup_key': dedupKey,
      'is_forwarded': isForwarded ? 1 : 0,
      'private_media_policy_version': privateMediaPolicy.version,
      'private_media_mode': privateMediaPolicy.mode.wireValue,
      'private_media_duration_seconds': privateMediaPolicy.durationSeconds,
      'private_media_state': privateMediaState.wireValue,
      'private_media_received_at_ms': privateMediaReceivedAtMs,
      'private_media_expires_at_ms': privateMediaExpiresAtMs,
      'private_media_revealed_at_ms': privateMediaRevealedAtMs,
      'private_media_terminal_at_ms': privateMediaTerminalAtMs,
      'private_media_clock_high_water_ms': privateMediaClockHighWaterMs,
    };
  }

  /// Creates a copy with updated fields.
  ///
  /// To explicitly set a nullable field to null, use the sentinel pattern:
  /// `copyWith(wireEnvelope: '')` won't work — use [copyWithNulled] instead.
  ConversationMessage copyWith({
    String? id,
    String? contactPeerId,
    String? senderPeerId,
    String? text,
    String? timestamp,
    String? status,
    bool? isIncoming,
    String? createdAt,
    Object? editedAt = _sentinel,
    Object? readAt = _sentinel,
    Object? quotedMessageId = _sentinel,
    Object? deletedAt = _sentinel,
    Object? deletedByPeerId = _sentinel,
    Object? hiddenAt = _sentinel,
    Object? transport = _sentinel,
    Object? wireEnvelope = _sentinel,
    Object? relayExpiresAt = _sentinel,
    Object? custodyCheckedAt = _sentinel,
    Object? dedupKey = _sentinel,
    bool? isForwarded,
    PrivateMediaPolicy? privateMediaPolicy,
    PrivateMediaLifecycleState? privateMediaState,
    Object? privateMediaReceivedAtMs = _sentinel,
    Object? privateMediaExpiresAtMs = _sentinel,
    Object? privateMediaRevealedAtMs = _sentinel,
    Object? privateMediaTerminalAtMs = _sentinel,
    Object? privateMediaClockHighWaterMs = _sentinel,
    List<MediaAttachment>? media,
  }) {
    return ConversationMessage(
      id: id ?? this.id,
      contactPeerId: contactPeerId ?? this.contactPeerId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isIncoming: isIncoming ?? this.isIncoming,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt == _sentinel ? this.editedAt : editedAt as String?,
      readAt: readAt == _sentinel ? this.readAt : readAt as String?,
      quotedMessageId: quotedMessageId == _sentinel
          ? this.quotedMessageId
          : quotedMessageId as String?,
      deletedAt: deletedAt == _sentinel ? this.deletedAt : deletedAt as String?,
      deletedByPeerId: deletedByPeerId == _sentinel
          ? this.deletedByPeerId
          : deletedByPeerId as String?,
      hiddenAt: hiddenAt == _sentinel ? this.hiddenAt : hiddenAt as String?,
      transport: transport == _sentinel ? this.transport : transport as String?,
      wireEnvelope: wireEnvelope == _sentinel
          ? this.wireEnvelope
          : wireEnvelope as String?,
      relayExpiresAt: relayExpiresAt == _sentinel
          ? this.relayExpiresAt
          : relayExpiresAt as int?,
      custodyCheckedAt: custodyCheckedAt == _sentinel
          ? this.custodyCheckedAt
          : custodyCheckedAt as String?,
      dedupKey: dedupKey == _sentinel ? this.dedupKey : dedupKey as String?,
      isForwarded: isForwarded ?? this.isForwarded,
      privateMediaPolicy: privateMediaPolicy ?? this.privateMediaPolicy,
      privateMediaState: privateMediaState ?? this.privateMediaState,
      privateMediaReceivedAtMs: privateMediaReceivedAtMs == _sentinel
          ? this.privateMediaReceivedAtMs
          : privateMediaReceivedAtMs as int?,
      privateMediaExpiresAtMs: privateMediaExpiresAtMs == _sentinel
          ? this.privateMediaExpiresAtMs
          : privateMediaExpiresAtMs as int?,
      privateMediaRevealedAtMs: privateMediaRevealedAtMs == _sentinel
          ? this.privateMediaRevealedAtMs
          : privateMediaRevealedAtMs as int?,
      privateMediaTerminalAtMs: privateMediaTerminalAtMs == _sentinel
          ? this.privateMediaTerminalAtMs
          : privateMediaTerminalAtMs as int?,
      privateMediaClockHighWaterMs: privateMediaClockHighWaterMs == _sentinel
          ? this.privateMediaClockHighWaterMs
          : privateMediaClockHighWaterMs as int?,
      media: media ?? this.media,
    );
  }

  int get privateMediaPolicyVersion => privateMediaPolicy.version;

  PrivateMediaMode get privateMediaMode => privateMediaPolicy.mode;

  int? get privateMediaDurationSeconds => privateMediaPolicy.durationSeconds;

  bool get isDeleted => deletedAt != null;

  bool get isHidden => hiddenAt != null;

  /// The [timestamp] parsed to a [DateTime], or null when the stored string is
  /// not valid ISO-8601 (fail-safe, matching the run-grouping/sort fallbacks at
  /// conversation_screen.dart and conversation_wired.dart).
  ///
  /// 159: a const-safe, transient, derived getter — NOT a DB column, NOT part
  /// of [==]/[hashCode] (id-only) nor [toMap]/[fromMap]. The `const` constructor
  /// plus all-`final` fields forbid a non-final instance cache, and the grouping
  /// memo (159 sub-change 2) already collapses re-parsing to once-per-recompute,
  /// so a plain non-cached getter is sufficient (no `Expando` needed yet).
  DateTime? get parsedTimestamp => DateTime.tryParse(timestamp);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConversationMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ConversationMessage(id: $id, contactPeerId: ${contactPeerId.length > 10 ? contactPeerId.substring(0, 10) : contactPeerId}..., isIncoming: $isIncoming)';
  }
}

const _sentinel = Object();
