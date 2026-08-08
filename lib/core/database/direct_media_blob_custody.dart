import '../media/direct_media_blob_artifact_store.dart'
    show kDirectMediaBlobArtifactRootDirectory;
import '../media/direct_media_blob_custody.dart'
    show
        kDirectMediaBlobCustodyContract,
        kDirectMediaBlobCustodyKind,
        kDirectMediaBlobTransportMime;

export '../media/direct_media_blob_custody.dart'
    show
        kDirectMediaBlobCustodyContract,
        kDirectMediaBlobCustodyKind,
        kDirectMediaBlobTransportMime;

final RegExp _lowerHex32 = RegExp(r'^[0-9a-f]{32}$');
final RegExp _lowerSha256 = RegExp(r'^[0-9a-f]{64}$');

enum DirectMediaBlobCustodyDirection {
  outgoing('outgoing'),
  incoming('incoming');

  const DirectMediaBlobCustodyDirection(this.dbValue);

  final String dbValue;

  static DirectMediaBlobCustodyDirection parse(String value) =>
      DirectMediaBlobCustodyDirection.values.singleWhere(
        (candidate) => candidate.dbValue == value,
        orElse: () => throw FormatException(
          'Unknown direct-media blob custody direction: $value',
        ),
      );
}

enum DirectMediaBlobCustodyState {
  outgoingPrepared(
    'outgoing_prepared',
    DirectMediaBlobCustodyDirection.outgoing,
  ),
  outgoingStored('outgoing_stored', DirectMediaBlobCustodyDirection.outgoing),
  outgoingCleanupPending(
    'outgoing_cleanup_pending',
    DirectMediaBlobCustodyDirection.outgoing,
  ),
  incomingCommitted(
    'incoming_committed',
    DirectMediaBlobCustodyDirection.incoming,
  ),
  incomingAckPending(
    'incoming_ack_pending',
    DirectMediaBlobCustodyDirection.incoming,
  );

  const DirectMediaBlobCustodyState(this.dbValue, this.direction);

  final String dbValue;
  final DirectMediaBlobCustodyDirection direction;

  static DirectMediaBlobCustodyState parse(String value) =>
      DirectMediaBlobCustodyState.values.singleWhere(
        (candidate) => candidate.dbValue == value,
        orElse: () => throw FormatException(
          'Unknown direct-media blob custody state: $value',
        ),
      );
}

/// One independent v111 authority row for an exact encrypted media blob.
///
/// The model mirrors the migration's cross-field constraints. Construction and
/// row parsing fail closed so application owners cannot accidentally publish a
/// half-proof, mix outgoing and incoming state, or assign an ACK source before
/// the local commit that moves a row to [DirectMediaBlobCustodyState.incomingAckPending].
class DirectMediaBlobCustodyRow {
  factory DirectMediaBlobCustodyRow({
    required String attachmentId,
    required String messageId,
    required DirectMediaBlobCustodyDirection direction,
    required DirectMediaBlobCustodyState state,
    required String? inboxCustodyIncarnationId,
    required String? recipientPeerId,
    required String? ciphertextRelativePath,
    String custodyKind = kDirectMediaBlobCustodyKind,
    String custodyContract = kDirectMediaBlobCustodyContract,
    required String contentHash,
    required int ciphertextSize,
    String transportMime = kDirectMediaBlobTransportMime,
    required int? expiresAtMs,
    required String? custodyRelayPeerId,
    int retryCount = 0,
    required String? lastAttemptAt,
    required String? nextAttemptAt,
    required String createdAt,
    required String updatedAt,
  }) {
    final row = DirectMediaBlobCustodyRow._(
      attachmentId: attachmentId,
      messageId: messageId,
      direction: direction,
      state: state,
      inboxCustodyIncarnationId: inboxCustodyIncarnationId,
      recipientPeerId: recipientPeerId,
      ciphertextRelativePath: ciphertextRelativePath,
      custodyKind: custodyKind,
      custodyContract: custodyContract,
      contentHash: contentHash,
      ciphertextSize: ciphertextSize,
      transportMime: transportMime,
      expiresAtMs: expiresAtMs,
      custodyRelayPeerId: custodyRelayPeerId,
      retryCount: retryCount,
      lastAttemptAt: lastAttemptAt,
      nextAttemptAt: nextAttemptAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
    final error = row.validationError;
    if (error != null) throw ArgumentError(error);
    return row;
  }

  const DirectMediaBlobCustodyRow._({
    required this.attachmentId,
    required this.messageId,
    required this.direction,
    required this.state,
    required this.inboxCustodyIncarnationId,
    required this.recipientPeerId,
    required this.ciphertextRelativePath,
    required this.custodyKind,
    required this.custodyContract,
    required this.contentHash,
    required this.ciphertextSize,
    required this.transportMime,
    required this.expiresAtMs,
    required this.custodyRelayPeerId,
    required this.retryCount,
    required this.lastAttemptAt,
    required this.nextAttemptAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DirectMediaBlobCustodyRow.fromMap(Map<String, Object?> map) {
    try {
      return DirectMediaBlobCustodyRow(
        attachmentId: map['attachment_id'] as String,
        messageId: map['message_id'] as String,
        direction: DirectMediaBlobCustodyDirection.parse(
          map['direction'] as String,
        ),
        state: DirectMediaBlobCustodyState.parse(map['state'] as String),
        inboxCustodyIncarnationId:
            map['inbox_custody_incarnation_id'] as String?,
        recipientPeerId: map['recipient_peer_id'] as String?,
        ciphertextRelativePath: map['ciphertext_relative_path'] as String?,
        custodyKind: map['custody_kind'] as String,
        custodyContract: map['custody_contract'] as String,
        contentHash: map['content_hash'] as String,
        ciphertextSize: (map['ciphertext_size'] as num).toInt(),
        transportMime: map['transport_mime'] as String,
        expiresAtMs: (map['expires_at_ms'] as num?)?.toInt(),
        custodyRelayPeerId: map['custody_relay_peer_id'] as String?,
        retryCount: (map['retry_count'] as num).toInt(),
        lastAttemptAt: map['last_attempt_at'] as String?,
        nextAttemptAt: map['next_attempt_at'] as String?,
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );
    } on Object catch (error) {
      throw FormatException('Invalid direct-media blob custody row', error);
    }
  }

  final String attachmentId;
  final String messageId;
  final DirectMediaBlobCustodyDirection direction;
  final DirectMediaBlobCustodyState state;
  final String? inboxCustodyIncarnationId;
  final String? recipientPeerId;
  final String? ciphertextRelativePath;
  final String custodyKind;
  final String custodyContract;
  final String contentHash;
  final int ciphertextSize;
  final String transportMime;
  final int? expiresAtMs;
  final String? custodyRelayPeerId;
  final int retryCount;
  final String? lastAttemptAt;
  final String? nextAttemptAt;
  final String createdAt;
  final String updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
    'attachment_id': attachmentId,
    'message_id': messageId,
    'direction': direction.dbValue,
    'state': state.dbValue,
    'inbox_custody_incarnation_id': inboxCustodyIncarnationId,
    'recipient_peer_id': recipientPeerId,
    'ciphertext_relative_path': ciphertextRelativePath,
    'custody_kind': custodyKind,
    'custody_contract': custodyContract,
    'content_hash': contentHash,
    'ciphertext_size': ciphertextSize,
    'transport_mime': transportMime,
    'expires_at_ms': expiresAtMs,
    'custody_relay_peer_id': custodyRelayPeerId,
    'retry_count': retryCount,
    'last_attempt_at': lastAttemptAt,
    'next_attempt_at': nextAttemptAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  String? get validationError {
    if (_isBlank(attachmentId) || _isBlank(messageId)) {
      return 'attachmentId and messageId must be non-blank';
    }
    if (state.direction != direction) {
      return 'state does not belong to direction';
    }
    if (custodyKind != kDirectMediaBlobCustodyKind ||
        custodyContract != kDirectMediaBlobCustodyContract ||
        transportMime != kDirectMediaBlobTransportMime ||
        !_lowerSha256.hasMatch(contentHash) ||
        ciphertextSize <= 0 ||
        _isBlank(createdAt) ||
        _isBlank(updatedAt) ||
        retryCount < 0) {
      return 'invalid immutable proof or timestamp fields';
    }
    if (inboxCustodyIncarnationId != null &&
        !_lowerHex32.hasMatch(inboxCustodyIncarnationId!)) {
      return 'inbox custody incarnation must be lowercase 32-hex';
    }
    if (expiresAtMs != null && expiresAtMs! <= 0) {
      return 'expiry must be positive';
    }
    if (_isBlankNullable(custodyRelayPeerId) ||
        _isBlankNullable(lastAttemptAt) ||
        _isBlankNullable(nextAttemptAt)) {
      return 'optional relay and retry timestamps must be non-blank';
    }

    if (direction == DirectMediaBlobCustodyDirection.outgoing) {
      if (_isBlank(recipientPeerId) ||
          !isValidDirectMediaBlobCustodyRelativePath(ciphertextRelativePath) ||
          retryCount != 0 ||
          lastAttemptAt != null ||
          nextAttemptAt != null) {
        return 'invalid outgoing-only fields';
      }
    } else if (recipientPeerId != null ||
        ciphertextRelativePath != null ||
        inboxCustodyIncarnationId != null) {
      return 'incoming rows cannot own outgoing-only fields';
    }

    switch (state) {
      case DirectMediaBlobCustodyState.outgoingPrepared:
        if (inboxCustodyIncarnationId != null ||
            expiresAtMs != null ||
            custodyRelayPeerId != null) {
          return 'outgoing_prepared cannot contain relay proof or v108 binding';
        }
      case DirectMediaBlobCustodyState.outgoingStored:
        if (expiresAtMs == null || _isBlank(custodyRelayPeerId)) {
          return 'outgoing_stored requires exact relay proof';
        }
      case DirectMediaBlobCustodyState.outgoingCleanupPending:
        final hasExpiry = expiresAtMs != null;
        final hasRelay = custodyRelayPeerId != null;
        if (hasExpiry != hasRelay ||
            (inboxCustodyIncarnationId != null && !hasExpiry)) {
          return 'outgoing cleanup must retain a complete proof tuple';
        }
      case DirectMediaBlobCustodyState.incomingCommitted:
        if (expiresAtMs == null ||
            custodyRelayPeerId != null ||
            retryCount != 0 ||
            lastAttemptAt != null ||
            nextAttemptAt != null) {
          return 'incoming_committed requires commitment without ACK source';
        }
      case DirectMediaBlobCustodyState.incomingAckPending:
        if (expiresAtMs == null || _isBlank(custodyRelayPeerId)) {
          return 'incoming_ack_pending requires an exact ACK source';
        }
        final validRetry = retryCount == 0
            ? lastAttemptAt == null && nextAttemptAt == null
            : lastAttemptAt != null && nextAttemptAt != null;
        if (!validRetry) return 'invalid ACK retry projection';
    }
    return null;
  }

  /// True only for an allowed one-way state transition preserving exact blob
  /// identity and proof material.
  bool canTransitionTo(DirectMediaBlobCustodyRow next) {
    if (!_sameImmutableIdentity(next) || next.updatedAt.trim().isEmpty) {
      return false;
    }
    switch ((state, next.state)) {
      case (
        DirectMediaBlobCustodyState.outgoingPrepared,
        DirectMediaBlobCustodyState.outgoingStored,
      ):
        return inboxCustodyIncarnationId == null &&
            next.inboxCustodyIncarnationId == null &&
            expiresAtMs == null &&
            custodyRelayPeerId == null &&
            next.expiresAtMs != null &&
            next.custodyRelayPeerId != null;
      case (
        DirectMediaBlobCustodyState.outgoingPrepared,
        DirectMediaBlobCustodyState.outgoingCleanupPending,
      ):
        return next.inboxCustodyIncarnationId == null &&
            next.expiresAtMs == null &&
            next.custodyRelayPeerId == null;
      case (
        DirectMediaBlobCustodyState.outgoingStored,
        DirectMediaBlobCustodyState.outgoingStored,
      ):
        final bindingPreservedOrAdded =
            next.inboxCustodyIncarnationId == inboxCustodyIncarnationId ||
            (inboxCustodyIncarnationId == null &&
                next.inboxCustodyIncarnationId != null);
        return bindingPreservedOrAdded && _sameMutableProof(next);
      case (
        DirectMediaBlobCustodyState.outgoingStored,
        DirectMediaBlobCustodyState.outgoingCleanupPending,
      ):
        return next.inboxCustodyIncarnationId == inboxCustodyIncarnationId &&
            _sameMutableProof(next);
      case (
        DirectMediaBlobCustodyState.incomingCommitted,
        DirectMediaBlobCustodyState.incomingAckPending,
      ):
        return next.expiresAtMs == expiresAtMs &&
            next.custodyRelayPeerId != null &&
            next.retryCount == 0 &&
            next.lastAttemptAt == null &&
            next.nextAttemptAt == null;
      case (
        DirectMediaBlobCustodyState.incomingAckPending,
        DirectMediaBlobCustodyState.incomingAckPending,
      ):
        return next.expiresAtMs == expiresAtMs &&
            next.custodyRelayPeerId == custodyRelayPeerId &&
            next.retryCount == retryCount + 1 &&
            next.lastAttemptAt != null &&
            next.nextAttemptAt != null;
      default:
        return false;
    }
  }

  bool exactDatabaseProjectionMatches(DirectMediaBlobCustodyRow other) {
    final left = toMap();
    final right = other.toMap();
    for (final key in left.keys) {
      if (left[key] != right[key]) return false;
    }
    return true;
  }

  DirectMediaBlobCustodyRow copyWith({
    DirectMediaBlobCustodyState? state,
    Object? inboxCustodyIncarnationId = _unset,
    Object? expiresAtMs = _unset,
    Object? custodyRelayPeerId = _unset,
    int? retryCount,
    Object? lastAttemptAt = _unset,
    Object? nextAttemptAt = _unset,
    String? updatedAt,
  }) => DirectMediaBlobCustodyRow(
    attachmentId: attachmentId,
    messageId: messageId,
    direction: direction,
    state: state ?? this.state,
    inboxCustodyIncarnationId: identical(inboxCustodyIncarnationId, _unset)
        ? this.inboxCustodyIncarnationId
        : inboxCustodyIncarnationId as String?,
    recipientPeerId: recipientPeerId,
    ciphertextRelativePath: ciphertextRelativePath,
    custodyKind: custodyKind,
    custodyContract: custodyContract,
    contentHash: contentHash,
    ciphertextSize: ciphertextSize,
    transportMime: transportMime,
    expiresAtMs: identical(expiresAtMs, _unset)
        ? this.expiresAtMs
        : expiresAtMs as int?,
    custodyRelayPeerId: identical(custodyRelayPeerId, _unset)
        ? this.custodyRelayPeerId
        : custodyRelayPeerId as String?,
    retryCount: retryCount ?? this.retryCount,
    lastAttemptAt: identical(lastAttemptAt, _unset)
        ? this.lastAttemptAt
        : lastAttemptAt as String?,
    nextAttemptAt: identical(nextAttemptAt, _unset)
        ? this.nextAttemptAt
        : nextAttemptAt as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  bool _sameImmutableIdentity(DirectMediaBlobCustodyRow other) =>
      attachmentId == other.attachmentId &&
      messageId == other.messageId &&
      direction == other.direction &&
      recipientPeerId == other.recipientPeerId &&
      ciphertextRelativePath == other.ciphertextRelativePath &&
      custodyKind == other.custodyKind &&
      custodyContract == other.custodyContract &&
      contentHash == other.contentHash &&
      ciphertextSize == other.ciphertextSize &&
      transportMime == other.transportMime &&
      createdAt == other.createdAt;

  bool _sameMutableProof(DirectMediaBlobCustodyRow other) =>
      expiresAtMs == other.expiresAtMs &&
      custodyRelayPeerId == other.custodyRelayPeerId &&
      retryCount == other.retryCount &&
      lastAttemptAt == other.lastAttemptAt &&
      nextAttemptAt == other.nextAttemptAt;
}

/// Validates the DB-owned root and at least one identity-scope segment without
/// resolving a caller-controlled path against the filesystem.
bool isValidDirectMediaBlobCustodyRelativePath(String? value) {
  if (value == null || value.isEmpty || value != value.trim()) return false;
  if (value.contains('\u0000') ||
      value.contains(r'\') ||
      value.contains(':') ||
      value.startsWith('/') ||
      value.contains('//')) {
    return false;
  }
  final segments = value.split('/');
  if (segments.length < 3 ||
      segments.first != kDirectMediaBlobArtifactRootDirectory) {
    return false;
  }
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

bool _isBlank(String? value) => value == null || value.trim().isEmpty;

bool _isBlankNullable(String? value) => value != null && value.trim().isEmpty;

const Object _unset = Object();
