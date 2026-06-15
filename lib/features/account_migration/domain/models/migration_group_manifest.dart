enum MigrationGroupDevicePolicy { preserveExisting, legacyFallback, invalid }

enum MigrationGroupManifestIssueCode {
  missingRetainedGroupKey,
  missingPrimaryGroupKeyMaterial,
  missingSharedGroupKeyMirror,
  sharedGroupKeyMirrorMismatch,
  missingPendingGroupKeyMaterial,
  missingMovedAccountDevice,
  duplicateMovedAccountActiveDevice,
  missingPendingKeyRepair,
  malformedPendingKeyRepair,
  malformedPendingMembershipMessage,
  malformedWelcomeKeyPackageTombstone,
  missingGroupInboxCursor,
  malformedGroupInboxCursor,
}

class MigrationGroupRetainedGenerationRange {
  final int minGeneration;
  final int latestGeneration;

  const MigrationGroupRetainedGenerationRange({
    required this.minGeneration,
    required this.latestGeneration,
  });

  List<int> get generations {
    if (latestGeneration < minGeneration) {
      return const [];
    }
    return [
      for (
        var generation = minGeneration;
        generation <= latestGeneration;
        generation++
      )
        generation,
    ];
  }

  Map<String, Object?> toJson() {
    return {
      'min_generation': minGeneration,
      'latest_generation': latestGeneration,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MigrationGroupRetainedGenerationRange &&
            other.minGeneration == minGeneration &&
            other.latestGeneration == latestGeneration;
  }

  @override
  int get hashCode => Object.hash(minGeneration, latestGeneration);
}

class MigrationGroupKeyManifestItem {
  final String groupId;
  final int keyGeneration;
  final String sourceTable;
  final String sourceId;
  final String primaryKeyName;
  final String primaryKeySha256;
  final bool requiresSharedMirror;
  final String? sharedKeyName;
  final String? sharedKeySha256;

  const MigrationGroupKeyManifestItem({
    required this.groupId,
    required this.keyGeneration,
    required this.sourceTable,
    required this.sourceId,
    required this.primaryKeyName,
    required this.primaryKeySha256,
    required this.requiresSharedMirror,
    this.sharedKeyName,
    this.sharedKeySha256,
  });

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      'key_generation': keyGeneration,
      'source_table': sourceTable,
      'source_id': sourceId,
      'primary_key_name': primaryKeyName,
      'primary_key_sha256': primaryKeySha256,
      'requires_shared_mirror': requiresSharedMirror,
      if (sharedKeyName != null) 'shared_key_name': sharedKeyName,
      if (sharedKeySha256 != null) 'shared_key_sha256': sharedKeySha256,
    };
  }
}

class MigrationGroupDeviceManifestItem {
  final String deviceId;
  final String transportPeerId;
  final String deviceSigningPublicKey;
  final String? mlKemPublicKey;
  final String? keyPackageId;
  final String? keyPackagePublicMaterialSha256;
  final String status;
  final String? revokedAt;

  const MigrationGroupDeviceManifestItem({
    required this.deviceId,
    required this.transportPeerId,
    required this.deviceSigningPublicKey,
    this.mlKemPublicKey,
    this.keyPackageId,
    this.keyPackagePublicMaterialSha256,
    required this.status,
    this.revokedAt,
  });

  bool get isActive => status == 'active' && revokedAt == null;

  Map<String, Object?> toJson() {
    return {
      'device_id': deviceId,
      'transport_peer_id': transportPeerId,
      'device_signing_public_key': deviceSigningPublicKey,
      if (mlKemPublicKey != null) 'ml_kem_public_key': mlKemPublicKey,
      if (keyPackageId != null) 'key_package_id': keyPackageId,
      if (keyPackagePublicMaterialSha256 != null)
        'key_package_public_material_sha256': keyPackagePublicMaterialSha256,
      'status': status,
      if (revokedAt != null) 'revoked_at': revokedAt,
    };
  }
}

class MigrationGroupMemberManifestItem {
  final String groupId;
  final String peerId;
  final String? role;
  final List<MigrationGroupDeviceManifestItem> devices;

  const MigrationGroupMemberManifestItem({
    required this.groupId,
    required this.peerId,
    this.role,
    this.devices = const [],
  });

  List<MigrationGroupDeviceManifestItem> get activeDevices {
    return devices.where((device) => device.isActive).toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      'peer_id': peerId,
      if (role != null) 'role': role,
      'devices': devices.map((device) => device.toJson()).toList(),
    };
  }
}

class MigrationGroupSenderMetadata {
  final String groupId;
  final String messageId;
  final String senderPeerId;
  final int? keyGeneration;
  final String? transportPeerId;
  final String? logicalDeliveryId;

  const MigrationGroupSenderMetadata({
    required this.groupId,
    required this.messageId,
    required this.senderPeerId,
    this.keyGeneration,
    this.transportPeerId,
    this.logicalDeliveryId,
  });

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      'message_id': messageId,
      'sender_peer_id': senderPeerId,
      if (keyGeneration != null) 'key_generation': keyGeneration,
      if (transportPeerId != null) 'transport_peer_id': transportPeerId,
      if (logicalDeliveryId != null) 'logical_delivery_id': logicalDeliveryId,
    };
  }
}

class MigrationGroupReceiptMetadata {
  final String groupId;
  final String messageId;
  final String receiptType;
  final String memberPeerId;
  final String? senderDeviceId;
  final String? receiptAt;
  final String? sourceEventId;
  final String? createdAt;
  final String? updatedAt;

  const MigrationGroupReceiptMetadata({
    required this.groupId,
    required this.messageId,
    required this.receiptType,
    required this.memberPeerId,
    this.senderDeviceId,
    this.receiptAt,
    this.sourceEventId,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      'message_id': messageId,
      'receipt_type': receiptType,
      'member_peer_id': memberPeerId,
      if (senderDeviceId != null) 'sender_device_id': senderDeviceId,
      if (receiptAt != null) 'receipt_at': receiptAt,
      if (sourceEventId != null) 'source_event_id': sourceEventId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }
}

class MigrationGroupWelcomePackageMetadata {
  final String groupId;
  final String packageId;
  final String? recipientPeerId;
  final String? recipientDeviceId;
  final String? recipientTransportPeerId;
  final String? recipientMlKemPublicKey;
  final String? inviteId;
  final String? publicMaterialHash;
  final int? keyEpoch;
  final String? issuedAt;
  final String? expiresAt;

  const MigrationGroupWelcomePackageMetadata({
    required this.groupId,
    required this.packageId,
    this.recipientPeerId,
    this.recipientDeviceId,
    this.recipientTransportPeerId,
    this.recipientMlKemPublicKey,
    this.inviteId,
    this.publicMaterialHash,
    this.keyEpoch,
    this.issuedAt,
    this.expiresAt,
  });

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      'package_id': packageId,
      if (recipientPeerId != null) 'recipient_peer_id': recipientPeerId,
      if (recipientDeviceId != null) 'recipient_device_id': recipientDeviceId,
      if (recipientTransportPeerId != null)
        'recipient_transport_peer_id': recipientTransportPeerId,
      if (recipientMlKemPublicKey != null)
        'recipient_ml_kem_public_key': recipientMlKemPublicKey,
      if (inviteId != null) 'invite_id': inviteId,
      if (publicMaterialHash != null)
        'public_material_hash': publicMaterialHash,
      if (keyEpoch != null) 'key_epoch': keyEpoch,
      if (issuedAt != null) 'issued_at': issuedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }
}

class MigrationGroupPendingKeyRepairMetadata {
  final String groupId;
  final String id;
  final String messageId;
  final String? senderPeerId;
  final String? transportPeerId;
  final String payloadType;
  final int keyEpoch;
  final String? replayEnvelopeSha256;
  final String status;
  final int? triggerCount;
  final int? attempts;
  final String? createdAt;
  final String? updatedAt;
  final String? finalizedAt;

  const MigrationGroupPendingKeyRepairMetadata({
    required this.groupId,
    required this.id,
    required this.messageId,
    this.senderPeerId,
    this.transportPeerId,
    required this.payloadType,
    required this.keyEpoch,
    this.replayEnvelopeSha256,
    required this.status,
    this.triggerCount,
    this.attempts,
    this.createdAt,
    this.updatedAt,
    this.finalizedAt,
  });

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      'id': id,
      'message_id': messageId,
      if (senderPeerId != null) 'sender_peer_id': senderPeerId,
      if (transportPeerId != null) 'transport_peer_id': transportPeerId,
      'payload_type': payloadType,
      'key_epoch': keyEpoch,
      if (replayEnvelopeSha256 != null)
        'replay_envelope_sha256': replayEnvelopeSha256,
      'status': status,
      if (triggerCount != null) 'trigger_count': triggerCount,
      if (attempts != null) 'attempts': attempts,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (finalizedAt != null) 'finalized_at': finalizedAt,
    };
  }
}

class MigrationGroupPendingMembershipMetadata {
  final String groupId;
  final String id;
  final String senderPeerId;
  final String? messageId;
  final String payloadSha256;
  final String receivedAt;
  final String? createdAt;
  final String? updatedAt;

  const MigrationGroupPendingMembershipMetadata({
    required this.groupId,
    required this.id,
    required this.senderPeerId,
    this.messageId,
    required this.payloadSha256,
    required this.receivedAt,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      'id': id,
      'sender_peer_id': senderPeerId,
      if (messageId != null) 'message_id': messageId,
      'payload_sha256': payloadSha256,
      'received_at': receivedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }
}

class MigrationGroupWelcomePackageTombstoneMetadata {
  final String groupId;
  final String packageId;
  final String recipientDeviceId;
  final String inviteId;
  final String publicMaterialHash;
  final String consumedAt;
  final String expiresAt;

  const MigrationGroupWelcomePackageTombstoneMetadata({
    required this.groupId,
    required this.packageId,
    required this.recipientDeviceId,
    required this.inviteId,
    required this.publicMaterialHash,
    required this.consumedAt,
    required this.expiresAt,
  });

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      'package_id': packageId,
      'recipient_device_id': recipientDeviceId,
      'invite_id': inviteId,
      'public_material_hash': publicMaterialHash,
      'consumed_at': consumedAt,
      'expires_at': expiresAt,
    };
  }
}

class MigrationGroupInboxCursorMetadata {
  final String groupId;
  final String cursor;
  final String createdAt;
  final String updatedAt;

  const MigrationGroupInboxCursorMetadata({
    required this.groupId,
    required this.cursor,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      'cursor': cursor,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class MigrationGroupManifestIssue {
  final MigrationGroupManifestIssueCode code;
  final String groupId;
  final int? keyGeneration;
  final String sourceTable;
  final String sourceId;
  final bool blocking;

  const MigrationGroupManifestIssue({
    required this.code,
    required this.groupId,
    this.keyGeneration,
    required this.sourceTable,
    required this.sourceId,
    this.blocking = true,
  });

  Map<String, Object?> toJson() {
    return {
      'code': code.name,
      'group_id': groupId,
      if (keyGeneration != null) 'key_generation': keyGeneration,
      'source_table': sourceTable,
      'source_id': sourceId,
      'blocking': blocking,
    };
  }
}

class MigrationGroupManifestGroup {
  final String groupId;
  final String? name;
  final MigrationGroupRetainedGenerationRange? retainedGenerationRange;
  final List<MigrationGroupKeyManifestItem> committedKeys;
  final List<MigrationGroupKeyManifestItem> pendingDrafts;
  final List<MigrationGroupMemberManifestItem> members;
  final List<MigrationGroupSenderMetadata> senderMetadata;
  final List<MigrationGroupReceiptMetadata> receiptMetadata;
  final List<MigrationGroupWelcomePackageMetadata> welcomePackageMetadata;
  final List<MigrationGroupPendingKeyRepairMetadata> pendingKeyRepairs;
  final List<MigrationGroupPendingMembershipMetadata> pendingMembershipMessages;
  final List<MigrationGroupWelcomePackageTombstoneMetadata>
  welcomePackageTombstones;
  final List<MigrationGroupInboxCursorMetadata> inboxCursors;
  final MigrationGroupDevicePolicy devicePolicy;
  final String? movedAccountActiveDeviceId;
  final bool pushPreviewReady;

  const MigrationGroupManifestGroup({
    required this.groupId,
    this.name,
    this.retainedGenerationRange,
    this.committedKeys = const [],
    this.pendingDrafts = const [],
    this.members = const [],
    this.senderMetadata = const [],
    this.receiptMetadata = const [],
    this.welcomePackageMetadata = const [],
    this.pendingKeyRepairs = const [],
    this.pendingMembershipMessages = const [],
    this.welcomePackageTombstones = const [],
    this.inboxCursors = const [],
    this.devicePolicy = MigrationGroupDevicePolicy.invalid,
    this.movedAccountActiveDeviceId,
    this.pushPreviewReady = false,
  });

  Map<String, Object?> toJson() {
    return {
      'group_id': groupId,
      if (name != null) 'name': name,
      if (retainedGenerationRange != null)
        'retained_generation_range': retainedGenerationRange!.toJson(),
      'committed_keys': committedKeys.map((key) => key.toJson()).toList(),
      'pending_drafts': pendingDrafts.map((key) => key.toJson()).toList(),
      'members': members.map((member) => member.toJson()).toList(),
      'sender_metadata': senderMetadata
          .map((metadata) => metadata.toJson())
          .toList(),
      'receipt_metadata': receiptMetadata
          .map((metadata) => metadata.toJson())
          .toList(),
      'welcome_package_metadata': welcomePackageMetadata
          .map((metadata) => metadata.toJson())
          .toList(),
      'pending_key_repairs': pendingKeyRepairs
          .map((metadata) => metadata.toJson())
          .toList(),
      'pending_membership_messages': pendingMembershipMessages
          .map((metadata) => metadata.toJson())
          .toList(),
      'welcome_package_tombstones': welcomePackageTombstones
          .map((metadata) => metadata.toJson())
          .toList(),
      'inbox_cursors': inboxCursors
          .map((metadata) => metadata.toJson())
          .toList(),
      'device_policy': devicePolicy.name,
      if (movedAccountActiveDeviceId != null)
        'moved_account_active_device_id': movedAccountActiveDeviceId,
      'push_preview_ready': pushPreviewReady,
    };
  }
}

class MigrationGroupManifest {
  final List<MigrationGroupManifestGroup> groups;
  final List<MigrationGroupManifestIssue> issues;

  const MigrationGroupManifest({
    this.groups = const [],
    this.issues = const [],
  });

  bool get isValid => issues.every((issue) => !issue.blocking);

  bool hasIssue(MigrationGroupManifestIssueCode code) {
    return issues.any((issue) => issue.code == code);
  }

  Map<String, Object?> toJson() {
    return {
      'groups': groups.map((group) => group.toJson()).toList(),
      'issues': issues.map((issue) => issue.toJson()).toList(),
      'valid': isValid,
    };
  }
}
