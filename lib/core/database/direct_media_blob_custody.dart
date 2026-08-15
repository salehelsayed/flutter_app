import '../media/direct_media_blob_artifact_store.dart'
    show kDirectMediaBlobArtifactRootDirectory;
import '../media/direct_media_blob_custody.dart'
    show
        kDirectMediaBlobCustodyContract,
        kDirectMediaBlobCustodyKind,
        kDirectMediaBlobTransportMime;
import '../media/group_media_blob_artifact_store.dart'
    show kGroupMediaBlobArtifactRootDirectory;
import '../media/group_media_blob_custody.dart' show kGroupMediaBlobCustodyKind;

export '../media/direct_media_blob_custody.dart'
    show
        kDirectMediaBlobCustodyContract,
        kDirectMediaBlobCustodyKind,
        kDirectMediaBlobTransportMime;
export '../media/group_media_blob_custody.dart' show kGroupMediaBlobCustodyKind;

final RegExp _lowerHex32 = RegExp(r'^[0-9a-f]{32}$');
final RegExp _lowerSha256 = RegExp(r'^[0-9a-f]{64}$');

enum MediaBlobCustodyOwnerLane {
  direct('direct'),
  group('group');

  const MediaBlobCustodyOwnerLane(this.dbValue);

  final String dbValue;

  static MediaBlobCustodyOwnerLane parse(String value) =>
      MediaBlobCustodyOwnerLane.values.singleWhere(
        (candidate) => candidate.dbValue == value,
        orElse: () => throw FormatException(
          'Unknown media-blob custody owner lane: $value',
        ),
      );
}

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

/// One independent v115 authority row for an exact encrypted media blob.
///
/// The model mirrors the migration's cross-field constraints. Construction and
/// row parsing fail closed so application owners cannot accidentally publish a
/// half-proof, mix outgoing and incoming state, or assign an ACK source before
/// the local commit that moves a row to [DirectMediaBlobCustodyState.incomingAckPending].
///
/// DB v115 lane-qualifies the v114 natural identity with [ownerLane],
/// [groupId], and [custodyBlobId]. Direct construction defaults preserve the
/// old API (`direct`, null, `attachmentId`). One canonical attachment may own
/// one outgoing row per physical target plus at most one incoming row. A
/// LINKED direct row additionally carries the logical [contactAccountPeerId];
/// an outgoing linked row must also persist the exact
/// [recipientMlKemPublicKey] its target envelope will be encrypted with.
class DirectMediaBlobCustodyRow {
  factory DirectMediaBlobCustodyRow({
    required String attachmentId,
    required String messageId,
    MediaBlobCustodyOwnerLane ownerLane = MediaBlobCustodyOwnerLane.direct,
    String? groupId,
    String? custodyBlobId,
    required DirectMediaBlobCustodyDirection direction,
    required DirectMediaBlobCustodyState state,
    required String? inboxCustodyIncarnationId,
    required String? recipientPeerId,
    String? contactAccountPeerId,
    String? recipientMlKemPublicKey,
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
      ownerLane: ownerLane,
      groupId: groupId,
      custodyBlobId: custodyBlobId ?? attachmentId,
      direction: direction,
      state: state,
      inboxCustodyIncarnationId: inboxCustodyIncarnationId,
      recipientPeerId: recipientPeerId,
      contactAccountPeerId: contactAccountPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
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
    required this.ownerLane,
    required this.groupId,
    required this.custodyBlobId,
    required this.direction,
    required this.state,
    required this.inboxCustodyIncarnationId,
    required this.recipientPeerId,
    required this.contactAccountPeerId,
    required this.recipientMlKemPublicKey,
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
        ownerLane: MediaBlobCustodyOwnerLane.parse(
          map['owner_lane'] as String? ??
              MediaBlobCustodyOwnerLane.direct.dbValue,
        ),
        groupId: map['group_id'] as String?,
        custodyBlobId:
            map['custody_blob_id'] as String? ?? map['attachment_id'] as String,
        direction: DirectMediaBlobCustodyDirection.parse(
          map['direction'] as String,
        ),
        state: DirectMediaBlobCustodyState.parse(map['state'] as String),
        inboxCustodyIncarnationId:
            map['inbox_custody_incarnation_id'] as String?,
        recipientPeerId: map['recipient_peer_id'] as String?,
        contactAccountPeerId: map['contact_account_peer_id'] as String?,
        recipientMlKemPublicKey: map['recipient_ml_kem_public_key'] as String?,
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
  final MediaBlobCustodyOwnerLane ownerLane;
  final String? groupId;
  final String custodyBlobId;
  final DirectMediaBlobCustodyDirection direction;
  final DirectMediaBlobCustodyState state;
  final String? inboxCustodyIncarnationId;
  final String? recipientPeerId;
  final String? contactAccountPeerId;
  final String? recipientMlKemPublicKey;
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

  /// True only for a row authored by the Plan-362 linked fanout adopter.
  bool get isLinkedFanoutRow =>
      ownerLane == MediaBlobCustodyOwnerLane.direct &&
      contactAccountPeerId != null;

  Map<String, Object?> toMap() => <String, Object?>{
    'attachment_id': attachmentId,
    'message_id': messageId,
    'owner_lane': ownerLane.dbValue,
    'group_id': groupId,
    'custody_blob_id': custodyBlobId,
    'direction': direction.dbValue,
    'state': state.dbValue,
    'inbox_custody_incarnation_id': inboxCustodyIncarnationId,
    'recipient_peer_id': recipientPeerId,
    'contact_account_peer_id': contactAccountPeerId,
    'recipient_ml_kem_public_key': recipientMlKemPublicKey,
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
    if (_isBlank(attachmentId) ||
        _isBlank(messageId) ||
        _isBlank(custodyBlobId) ||
        custodyBlobId != custodyBlobId.trim()) {
      return 'attachmentId, messageId and custodyBlobId must be non-blank';
    }
    if (state.direction != direction) {
      return 'state does not belong to direction';
    }
    if (custodyContract != kDirectMediaBlobCustodyContract ||
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
    if (_isBlankNullable(contactAccountPeerId) ||
        contactAccountPeerId != contactAccountPeerId?.trim() ||
        _isBlankNullable(recipientMlKemPublicKey) ||
        recipientMlKemPublicKey != recipientMlKemPublicKey?.trim()) {
      return 'linked fanout columns must be null or non-blank trimmed';
    }
    switch (ownerLane) {
      case MediaBlobCustodyOwnerLane.direct:
        if (groupId != null ||
            custodyBlobId != attachmentId ||
            custodyKind != kDirectMediaBlobCustodyKind) {
          return 'direct custody requires direct identity and kind';
        }
      case MediaBlobCustodyOwnerLane.group:
        if (_isBlank(groupId) ||
            groupId != groupId?.trim() ||
            custodyKind != kGroupMediaBlobCustodyKind ||
            contactAccountPeerId != null ||
            recipientMlKemPublicKey != null) {
          return 'group custody requires exact group ownership and kind';
        }
    }

    if (direction == DirectMediaBlobCustodyDirection.outgoing) {
      if (_isBlank(recipientPeerId) ||
          !isValidMediaBlobCustodyRelativePath(
            ciphertextRelativePath,
            ownerLane: ownerLane,
          ) ||
          retryCount != 0 ||
          lastAttemptAt != null ||
          nextAttemptAt != null) {
        return 'invalid outgoing-only fields';
      }
      // v114 linked shape: a LINKED outgoing row persists the logical contact
      // AND the exact target ML-KEM key together; a historical/single-target
      // row carries neither and gains no inferred fanout authority.
      if ((contactAccountPeerId == null) != (recipientMlKemPublicKey == null)) {
        return 'outgoing linked rows require logical contact and target key '
            'together';
      }
    } else {
      if (recipientPeerId != null ||
          ciphertextRelativePath != null ||
          inboxCustodyIncarnationId != null) {
        return 'incoming rows cannot own outgoing-only fields';
      }
      // Linked incoming keeps the physical transport out of the row: only the
      // logical contact marker is durable and no recipient key is persisted.
      if (recipientMlKemPublicKey != null) {
        return 'incoming rows cannot persist a recipient ML-KEM key';
      }
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
        if (!bindingPreservedOrAdded) return false;
        final groupProofRefreshBeforeBinding =
            ownerLane == MediaBlobCustodyOwnerLane.group &&
            inboxCustodyIncarnationId == null &&
            next.inboxCustodyIncarnationId == null &&
            next.retryCount == retryCount &&
            next.lastAttemptAt == lastAttemptAt &&
            next.nextAttemptAt == nextAttemptAt;
        return groupProofRefreshBeforeBinding || _sameMutableProof(next);
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
    ownerLane: ownerLane,
    groupId: groupId,
    custodyBlobId: custodyBlobId,
    direction: direction,
    state: state ?? this.state,
    inboxCustodyIncarnationId: identical(inboxCustodyIncarnationId, _unset)
        ? this.inboxCustodyIncarnationId
        : inboxCustodyIncarnationId as String?,
    recipientPeerId: recipientPeerId,
    contactAccountPeerId: contactAccountPeerId,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
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
      ownerLane == other.ownerLane &&
      groupId == other.groupId &&
      custodyBlobId == other.custodyBlobId &&
      direction == other.direction &&
      recipientPeerId == other.recipientPeerId &&
      contactAccountPeerId == other.contactAccountPeerId &&
      recipientMlKemPublicKey == other.recipientMlKemPublicKey &&
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
  return isValidMediaBlobCustodyRelativePath(
    value,
    ownerLane: MediaBlobCustodyOwnerLane.direct,
  );
}

bool isValidGroupMediaBlobCustodyRelativePath(String? value) {
  return isValidMediaBlobCustodyRelativePath(
    value,
    ownerLane: MediaBlobCustodyOwnerLane.group,
  );
}

bool isValidMediaBlobCustodyRelativePath(
  String? value, {
  required MediaBlobCustodyOwnerLane ownerLane,
}) {
  if (value == null || value.isEmpty || value != value.trim()) return false;
  if (value.contains('\u0000') ||
      value.contains(r'\') ||
      value.contains(':') ||
      value.startsWith('/') ||
      value.contains('//')) {
    return false;
  }
  final segments = value.split('/');
  final expectedRoot = switch (ownerLane) {
    MediaBlobCustodyOwnerLane.direct => kDirectMediaBlobArtifactRootDirectory,
    MediaBlobCustodyOwnerLane.group => kGroupMediaBlobArtifactRootDirectory,
  };
  final minimumSegments = ownerLane == MediaBlobCustodyOwnerLane.direct ? 3 : 4;
  if (segments.length < minimumSegments || segments.first != expectedRoot) {
    return false;
  }
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

bool _isBlank(String? value) => value == null || value.trim().isEmpty;

bool _isBlankNullable(String? value) => value != null && value.trim().isEmpty;

const Object _unset = Object();
