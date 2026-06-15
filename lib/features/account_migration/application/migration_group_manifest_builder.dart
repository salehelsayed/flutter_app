import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_group_manifest.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';

class MigrationGroupManifestBuilder {
  final SecureKeyStore primaryStore;
  final SecureKeyStore sharedStore;
  final String movedAccountPeerId;

  const MigrationGroupManifestBuilder({
    required this.primaryStore,
    required this.sharedStore,
    required this.movedAccountPeerId,
  });

  Future<MigrationGroupManifest> build({
    Iterable<Map<String, Object?>> groupRows = const [],
    Iterable<Map<String, Object?>> committedGroupKeyRows = const [],
    Iterable<Map<String, Object?>> pendingGroupKeyRows = const [],
    Iterable<Map<String, Object?>> groupMemberRows = const [],
    Iterable<Map<String, Object?>> groupMessageRows = const [],
    Iterable<Map<String, Object?>> groupMessageReceiptRows = const [],
    Iterable<Map<String, Object?>> welcomeKeyPackageRows = const [],
    Iterable<Map<String, Object?>> pendingKeyRepairRows = const [],
    Iterable<Map<String, Object?>> pendingMembershipMessageRows = const [],
    Iterable<Map<String, Object?>> welcomeKeyPackageTombstoneRows = const [],
    Iterable<Map<String, Object?>> groupInboxCursorRows = const [],
  }) async {
    final groupIds = <String>{};
    final groupNames = <String, String?>{};
    final committedByGroup = <String, List<Map<String, Object?>>>{};
    final pendingByGroup = <String, List<Map<String, Object?>>>{};
    final membersByGroup = <String, List<Map<String, Object?>>>{};
    final messagesByGroup = <String, List<Map<String, Object?>>>{};
    final receiptsByGroup = <String, List<Map<String, Object?>>>{};
    final welcomeByGroup = <String, List<Map<String, Object?>>>{};
    final pendingRepairsByGroup = <String, List<Map<String, Object?>>>{};
    final pendingMembershipByGroup = <String, List<Map<String, Object?>>>{};
    final tombstonesByGroup = <String, List<Map<String, Object?>>>{};
    final cursorsByGroup = <String, List<Map<String, Object?>>>{};

    for (final row in groupRows) {
      final groupId = _stringValue(row['id']);
      if (groupId == null) {
        continue;
      }
      groupIds.add(groupId);
      groupNames[groupId] = _stringValue(row['name']);
    }
    _indexByGroupId(committedGroupKeyRows, committedByGroup, groupIds);
    _indexByGroupId(pendingGroupKeyRows, pendingByGroup, groupIds);
    _indexByGroupId(groupMemberRows, membersByGroup, groupIds);
    _indexByGroupId(groupMessageRows, messagesByGroup, groupIds);
    _indexByGroupId(groupMessageReceiptRows, receiptsByGroup, groupIds);
    _indexByGroupId(welcomeKeyPackageRows, welcomeByGroup, groupIds);
    _indexByGroupId(pendingKeyRepairRows, pendingRepairsByGroup, groupIds);
    _indexByGroupId(
      pendingMembershipMessageRows,
      pendingMembershipByGroup,
      groupIds,
    );
    _indexByGroupId(
      welcomeKeyPackageTombstoneRows,
      tombstonesByGroup,
      groupIds,
    );
    _indexByGroupId(groupInboxCursorRows, cursorsByGroup, groupIds);

    final groups = <MigrationGroupManifestGroup>[];
    final issues = <MigrationGroupManifestIssue>[];
    for (final groupId in groupIds.toList()..sort()) {
      groups.add(
        await _buildGroup(
          groupId: groupId,
          name: groupNames[groupId],
          committedRows: committedByGroup[groupId] ?? const [],
          pendingRows: pendingByGroup[groupId] ?? const [],
          memberRows: membersByGroup[groupId] ?? const [],
          messageRows: messagesByGroup[groupId] ?? const [],
          receiptRows: receiptsByGroup[groupId] ?? const [],
          welcomeRows: welcomeByGroup[groupId] ?? const [],
          pendingRepairRows: pendingRepairsByGroup[groupId] ?? const [],
          pendingMembershipRows: pendingMembershipByGroup[groupId] ?? const [],
          tombstoneRows: tombstonesByGroup[groupId] ?? const [],
          cursorRows: cursorsByGroup[groupId] ?? const [],
          issues: issues,
        ),
      );
    }

    issues.sort((a, b) {
      final groupCompare = a.groupId.compareTo(b.groupId);
      if (groupCompare != 0) return groupCompare;
      final generationCompare = (a.keyGeneration ?? -1).compareTo(
        b.keyGeneration ?? -1,
      );
      if (generationCompare != 0) return generationCompare;
      return a.code.name.compareTo(b.code.name);
    });

    return MigrationGroupManifest(groups: groups, issues: issues);
  }

  Future<MigrationGroupManifestGroup> _buildGroup({
    required String groupId,
    required String? name,
    required List<Map<String, Object?>> committedRows,
    required List<Map<String, Object?>> pendingRows,
    required List<Map<String, Object?>> memberRows,
    required List<Map<String, Object?>> messageRows,
    required List<Map<String, Object?>> receiptRows,
    required List<Map<String, Object?>> welcomeRows,
    required List<Map<String, Object?>> pendingRepairRows,
    required List<Map<String, Object?>> pendingMembershipRows,
    required List<Map<String, Object?>> tombstoneRows,
    required List<Map<String, Object?>> cursorRows,
    required List<MigrationGroupManifestIssue> issues,
  }) async {
    final committedByGeneration = <int, Map<String, Object?>>{};
    for (final row in committedRows) {
      final generation = _intValue(row['key_generation']);
      if (generation != null) {
        committedByGeneration[generation] = row;
      }
    }

    MigrationGroupRetainedGenerationRange? retainedRange;
    final committedItems = <MigrationGroupKeyManifestItem>[];
    final generations = committedByGeneration.keys.toList()..sort();
    if (generations.isNotEmpty) {
      final latestGeneration = generations.last;
      retainedRange = MigrationGroupRetainedGenerationRange(
        minGeneration: minRetainedGroupKeyGeneration(latestGeneration),
        latestGeneration: latestGeneration,
      );
      for (final generation in retainedRange.generations) {
        final row = committedByGeneration[generation];
        if (row == null) {
          issues.add(
            MigrationGroupManifestIssue(
              code: MigrationGroupManifestIssueCode.missingRetainedGroupKey,
              groupId: groupId,
              keyGeneration: generation,
              sourceTable: 'group_keys',
              sourceId: '$groupId:$generation',
            ),
          );
          continue;
        }
        final item = await _buildCommittedKeyItem(
          groupId: groupId,
          row: row,
          keyGeneration: generation,
          issues: issues,
        );
        if (item != null) {
          committedItems.add(item);
        }
      }
    }

    final pendingItems = <MigrationGroupKeyManifestItem>[];
    for (final row in pendingRows) {
      final generation = _intValue(row['key_generation']);
      if (generation == null) {
        continue;
      }
      final item = await _buildPendingKeyItem(
        groupId: groupId,
        row: row,
        keyGeneration: generation,
        issues: issues,
      );
      if (item != null) {
        pendingItems.add(item);
      }
    }

    final members = _buildMembers(groupId, memberRows);
    final devicePolicy = _devicePolicyFor(groupId, members, issues);
    final movedAccountActiveDeviceId = _movedAccountActiveDeviceId(members);
    final senderMetadata = _buildSenderMetadata(groupId, messageRows);
    final receiptMetadata = _buildReceiptMetadata(groupId, receiptRows);
    final welcomeMetadata = _buildWelcomeMetadata(groupId, welcomeRows);
    final pendingRepairs = _buildPendingKeyRepairs(
      groupId: groupId,
      messageRows: messageRows,
      repairRows: pendingRepairRows,
      issues: issues,
    );
    final pendingMembershipMessages = _buildPendingMembershipMessages(
      groupId,
      pendingMembershipRows,
      issues,
    );
    final welcomeTombstones = _buildWelcomePackageTombstones(
      groupId,
      tombstoneRows,
      issues,
    );
    final inboxCursors = _buildInboxCursors(
      groupId: groupId,
      cursorRows: cursorRows,
      receiptRows: receiptRows,
      issues: issues,
    );
    final pushPreviewReady = _pushPreviewReady(groupId, issues);

    return MigrationGroupManifestGroup(
      groupId: groupId,
      name: name,
      retainedGenerationRange: retainedRange,
      committedKeys: committedItems..sort(_compareKeyItems),
      pendingDrafts: pendingItems..sort(_compareKeyItems),
      members: members..sort((a, b) => a.peerId.compareTo(b.peerId)),
      senderMetadata: senderMetadata
        ..sort((a, b) => a.messageId.compareTo(b.messageId)),
      receiptMetadata: receiptMetadata
        ..sort((a, b) => a.messageId.compareTo(b.messageId)),
      welcomePackageMetadata: welcomeMetadata
        ..sort((a, b) => a.packageId.compareTo(b.packageId)),
      pendingKeyRepairs: pendingRepairs..sort((a, b) => a.id.compareTo(b.id)),
      pendingMembershipMessages: pendingMembershipMessages
        ..sort((a, b) => a.id.compareTo(b.id)),
      welcomePackageTombstones: welcomeTombstones
        ..sort((a, b) {
          final packageCompare = a.packageId.compareTo(b.packageId);
          if (packageCompare != 0) return packageCompare;
          return a.recipientDeviceId.compareTo(b.recipientDeviceId);
        }),
      inboxCursors: inboxCursors
        ..sort((a, b) => a.groupId.compareTo(b.groupId)),
      devicePolicy: devicePolicy,
      movedAccountActiveDeviceId: movedAccountActiveDeviceId,
      pushPreviewReady: pushPreviewReady,
    );
  }

  Future<MigrationGroupKeyManifestItem?> _buildCommittedKeyItem({
    required String groupId,
    required Map<String, Object?> row,
    required int keyGeneration,
    required List<MigrationGroupManifestIssue> issues,
  }) async {
    final primary = await _resolvePrimaryKeyValue(row['encrypted_key']);
    final sourceId = '$groupId:$keyGeneration';
    if (primary == null) {
      issues.add(
        MigrationGroupManifestIssue(
          code: MigrationGroupManifestIssueCode.missingPrimaryGroupKeyMaterial,
          groupId: groupId,
          keyGeneration: keyGeneration,
          sourceTable: 'group_keys',
          sourceId: sourceId,
        ),
      );
      return null;
    }

    final sharedKeyName = sharedGroupPushKeyName(groupId, keyGeneration);
    final shared = await sharedStore.read(sharedKeyName);
    String? sharedSha256;
    if (shared == null || shared.isEmpty) {
      issues.add(
        MigrationGroupManifestIssue(
          code: MigrationGroupManifestIssueCode.missingSharedGroupKeyMirror,
          groupId: groupId,
          keyGeneration: keyGeneration,
          sourceTable: 'ios_shared_access_group',
          sourceId: sharedKeyName,
        ),
      );
    } else {
      sharedSha256 = _hash(shared);
      if (shared != primary.value) {
        issues.add(
          MigrationGroupManifestIssue(
            code: MigrationGroupManifestIssueCode.sharedGroupKeyMirrorMismatch,
            groupId: groupId,
            keyGeneration: keyGeneration,
            sourceTable: 'ios_shared_access_group',
            sourceId: sharedKeyName,
          ),
        );
      }
    }

    return MigrationGroupKeyManifestItem(
      groupId: groupId,
      keyGeneration: keyGeneration,
      sourceTable: 'group_keys',
      sourceId: sourceId,
      primaryKeyName: primary.keyName,
      primaryKeySha256: _hash(primary.value),
      requiresSharedMirror: true,
      sharedKeyName: sharedKeyName,
      sharedKeySha256: sharedSha256,
    );
  }

  Future<MigrationGroupKeyManifestItem?> _buildPendingKeyItem({
    required String groupId,
    required Map<String, Object?> row,
    required int keyGeneration,
    required List<MigrationGroupManifestIssue> issues,
  }) async {
    final primary = await _resolvePrimaryKeyValue(row['encrypted_key']);
    final sourceId = '$groupId:$keyGeneration';
    if (primary == null) {
      issues.add(
        MigrationGroupManifestIssue(
          code: MigrationGroupManifestIssueCode.missingPendingGroupKeyMaterial,
          groupId: groupId,
          keyGeneration: keyGeneration,
          sourceTable: 'group_key_rotation_drafts',
          sourceId: sourceId,
        ),
      );
      return null;
    }
    return MigrationGroupKeyManifestItem(
      groupId: groupId,
      keyGeneration: keyGeneration,
      sourceTable: 'group_key_rotation_drafts',
      sourceId: sourceId,
      primaryKeyName: primary.keyName,
      primaryKeySha256: _hash(primary.value),
      requiresSharedMirror: false,
    );
  }

  List<MigrationGroupMemberManifestItem> _buildMembers(
    String groupId,
    List<Map<String, Object?>> rows,
  ) {
    return rows
        .map((row) {
          final devices = GroupMemberDeviceIdentity.listFromJsonString(
            _stringValue(row['devices_json']),
          ).map(_deviceItem).toList(growable: false);
          return MigrationGroupMemberManifestItem(
            groupId: groupId,
            peerId: _stringValue(row['peer_id']) ?? '',
            role: _stringValue(row['role']),
            devices: devices,
          );
        })
        .toList(growable: false);
  }

  MigrationGroupDeviceManifestItem _deviceItem(
    GroupMemberDeviceIdentity device,
  ) {
    return MigrationGroupDeviceManifestItem(
      deviceId: device.deviceId,
      transportPeerId: device.transportPeerId,
      deviceSigningPublicKey: device.deviceSigningPublicKey,
      mlKemPublicKey: device.mlKemPublicKey,
      keyPackageId: device.keyPackageId,
      keyPackagePublicMaterialSha256: _hashNullable(
        device.keyPackagePublicMaterial,
      ),
      status: device.status.toValue(),
      revokedAt: device.revokedAt?.toUtc().toIso8601String(),
    );
  }

  MigrationGroupDevicePolicy _devicePolicyFor(
    String groupId,
    List<MigrationGroupMemberManifestItem> members,
    List<MigrationGroupManifestIssue> issues,
  ) {
    final movedMembers = members
        .where((member) => member.peerId == movedAccountPeerId)
        .toList(growable: false);
    final activeDevices = movedMembers
        .expand((member) => member.activeDevices)
        .toList(growable: false);
    if (activeDevices.isEmpty) {
      issues.add(
        MigrationGroupManifestIssue(
          code: MigrationGroupManifestIssueCode.missingMovedAccountDevice,
          groupId: groupId,
          sourceTable: 'group_members',
          sourceId: movedAccountPeerId,
        ),
      );
      return MigrationGroupDevicePolicy.invalid;
    }
    if (activeDevices.length > 1) {
      issues.add(
        MigrationGroupManifestIssue(
          code:
              MigrationGroupManifestIssueCode.duplicateMovedAccountActiveDevice,
          groupId: groupId,
          sourceTable: 'group_members',
          sourceId: movedAccountPeerId,
        ),
      );
      return MigrationGroupDevicePolicy.invalid;
    }
    return MigrationGroupDevicePolicy.preserveExisting;
  }

  String? _movedAccountActiveDeviceId(
    List<MigrationGroupMemberManifestItem> members,
  ) {
    final activeDevices = members
        .where((member) => member.peerId == movedAccountPeerId)
        .expand((member) => member.activeDevices)
        .toList(growable: false);
    return activeDevices.length == 1 ? activeDevices.single.deviceId : null;
  }

  List<MigrationGroupSenderMetadata> _buildSenderMetadata(
    String groupId,
    List<Map<String, Object?>> rows,
  ) {
    return rows
        .map((row) {
          return MigrationGroupSenderMetadata(
            groupId: groupId,
            messageId: _stringValue(row['id']) ?? '',
            senderPeerId: _stringValue(row['sender_peer_id']) ?? '',
            keyGeneration: _intValue(row['key_generation']),
            transportPeerId: _stringValue(row['transport_peer_id']),
            logicalDeliveryId: _stringValue(row['logical_delivery_id']),
          );
        })
        .toList(growable: false);
  }

  List<MigrationGroupReceiptMetadata> _buildReceiptMetadata(
    String groupId,
    List<Map<String, Object?>> rows,
  ) {
    return rows
        .map((row) {
          return MigrationGroupReceiptMetadata(
            groupId: groupId,
            messageId: _stringValue(row['message_id']) ?? '',
            receiptType: _stringValue(row['receipt_type']) ?? '',
            memberPeerId: _stringValue(row['member_peer_id']) ?? '',
            senderDeviceId: _stringValue(row['sender_device_id']),
            receiptAt: _stringValue(row['receipt_at']),
            sourceEventId: _stringValue(row['source_event_id']),
            createdAt: _stringValue(row['created_at']),
            updatedAt: _stringValue(row['updated_at']),
          );
        })
        .toList(growable: false);
  }

  List<MigrationGroupWelcomePackageMetadata> _buildWelcomeMetadata(
    String groupId,
    List<Map<String, Object?>> rows,
  ) {
    return rows
        .map((row) {
          return MigrationGroupWelcomePackageMetadata(
            groupId: groupId,
            packageId: _stringValue(row['package_id']) ?? '',
            recipientPeerId: _stringValue(row['recipient_peer_id']),
            recipientDeviceId: _stringValue(row['recipient_device_id']),
            recipientTransportPeerId: _stringValue(
              row['recipient_transport_peer_id'],
            ),
            recipientMlKemPublicKey: _stringValue(
              row['recipient_ml_kem_public_key'],
            ),
            inviteId: _stringValue(row['invite_id']),
            publicMaterialHash: _stringValue(row['public_material_hash']),
            keyEpoch: _intValue(row['key_epoch']),
            issuedAt: _stringValue(row['issued_at']),
            expiresAt: _stringValue(row['expires_at']),
          );
        })
        .toList(growable: false);
  }

  List<MigrationGroupPendingKeyRepairMetadata> _buildPendingKeyRepairs({
    required String groupId,
    required List<Map<String, Object?>> messageRows,
    required List<Map<String, Object?>> repairRows,
    required List<MigrationGroupManifestIssue> issues,
  }) {
    final repairsByMessageId = <String, Map<String, Object?>>{};
    for (final row in repairRows) {
      final messageId = _stringValue(row['message_id']);
      if (messageId != null) {
        repairsByMessageId[messageId] = row;
      }
    }

    for (final row in messageRows) {
      final status = _stringValue(row['status']);
      if (!_requiresPendingKeyRepair(status)) {
        continue;
      }
      final messageId = _stringValue(row['id']);
      if (messageId != null && !repairsByMessageId.containsKey(messageId)) {
        issues.add(
          MigrationGroupManifestIssue(
            code: MigrationGroupManifestIssueCode.missingPendingKeyRepair,
            groupId: groupId,
            sourceTable: 'group_pending_key_repairs',
            sourceId: messageId,
          ),
        );
      }
    }

    final items = <MigrationGroupPendingKeyRepairMetadata>[];
    for (final row in repairRows) {
      final id = _stringValue(row['id']);
      final messageId = _stringValue(row['message_id']);
      final payloadType = _stringValue(row['payload_type']);
      final keyEpoch = _intValue(row['key_epoch']);
      final status = _stringValue(row['status']);
      final createdAt = _stringValue(row['created_at']);
      final updatedAt = _stringValue(row['updated_at']);
      if (id == null ||
          messageId == null ||
          payloadType == null ||
          keyEpoch == null ||
          status == null ||
          createdAt == null ||
          updatedAt == null) {
        issues.add(
          MigrationGroupManifestIssue(
            code: MigrationGroupManifestIssueCode.malformedPendingKeyRepair,
            groupId: groupId,
            keyGeneration: keyEpoch,
            sourceTable: 'group_pending_key_repairs',
            sourceId: id ?? messageId ?? groupId,
          ),
        );
        continue;
      }
      items.add(
        MigrationGroupPendingKeyRepairMetadata(
          groupId: groupId,
          id: id,
          messageId: messageId,
          senderPeerId: _stringValue(row['sender_peer_id']),
          transportPeerId: _stringValue(row['transport_peer_id']),
          payloadType: payloadType,
          keyEpoch: keyEpoch,
          replayEnvelopeSha256: _hashNullable(
            _stringValue(row['replay_envelope_json']),
          ),
          status: status,
          triggerCount: _intValue(row['trigger_count']),
          attempts: _intValue(row['attempts']),
          createdAt: createdAt,
          updatedAt: updatedAt,
          finalizedAt: _stringValue(row['finalized_at']),
        ),
      );
    }
    return items;
  }

  List<MigrationGroupPendingMembershipMetadata> _buildPendingMembershipMessages(
    String groupId,
    List<Map<String, Object?>> rows,
    List<MigrationGroupManifestIssue> issues,
  ) {
    final items = <MigrationGroupPendingMembershipMetadata>[];
    for (final row in rows) {
      final id = _stringValue(row['id']);
      final senderPeerId = _stringValue(row['sender_peer_id']);
      final payloadJson = _stringValue(row['payload_json']);
      final receivedAt = _stringValue(row['received_at']);
      if (id == null ||
          senderPeerId == null ||
          payloadJson == null ||
          receivedAt == null) {
        issues.add(
          MigrationGroupManifestIssue(
            code: MigrationGroupManifestIssueCode
                .malformedPendingMembershipMessage,
            groupId: groupId,
            sourceTable: 'group_pending_membership_messages',
            sourceId: id ?? _stringValue(row['message_id']) ?? groupId,
          ),
        );
        continue;
      }
      items.add(
        MigrationGroupPendingMembershipMetadata(
          groupId: groupId,
          id: id,
          senderPeerId: senderPeerId,
          messageId: _stringValue(row['message_id']),
          payloadSha256: _hash(payloadJson),
          receivedAt: receivedAt,
          createdAt: _stringValue(row['created_at']),
          updatedAt: _stringValue(row['updated_at']),
        ),
      );
    }
    return items;
  }

  List<MigrationGroupWelcomePackageTombstoneMetadata>
  _buildWelcomePackageTombstones(
    String groupId,
    List<Map<String, Object?>> rows,
    List<MigrationGroupManifestIssue> issues,
  ) {
    final items = <MigrationGroupWelcomePackageTombstoneMetadata>[];
    for (final row in rows) {
      final packageId = _stringValue(row['package_id']);
      final recipientDeviceId = _stringValue(row['recipient_device_id']);
      final inviteId = _stringValue(row['invite_id']);
      final publicMaterialHash = _stringValue(row['public_material_hash']);
      final consumedAt = _stringValue(row['consumed_at']);
      final expiresAt = _stringValue(row['expires_at']);
      if (packageId == null ||
          recipientDeviceId == null ||
          inviteId == null ||
          publicMaterialHash == null ||
          consumedAt == null ||
          expiresAt == null) {
        issues.add(
          MigrationGroupManifestIssue(
            code: MigrationGroupManifestIssueCode
                .malformedWelcomeKeyPackageTombstone,
            groupId: groupId,
            sourceTable: 'group_welcome_key_package_tombstones',
            sourceId: packageId ?? recipientDeviceId ?? groupId,
          ),
        );
        continue;
      }
      items.add(
        MigrationGroupWelcomePackageTombstoneMetadata(
          groupId: groupId,
          packageId: packageId,
          recipientDeviceId: recipientDeviceId,
          inviteId: inviteId,
          publicMaterialHash: publicMaterialHash,
          consumedAt: consumedAt,
          expiresAt: expiresAt,
        ),
      );
    }
    return items;
  }

  List<MigrationGroupInboxCursorMetadata> _buildInboxCursors({
    required String groupId,
    required List<Map<String, Object?>> cursorRows,
    required List<Map<String, Object?>> receiptRows,
    required List<MigrationGroupManifestIssue> issues,
  }) {
    if (cursorRows.isEmpty && receiptRows.isNotEmpty) {
      issues.add(
        MigrationGroupManifestIssue(
          code: MigrationGroupManifestIssueCode.missingGroupInboxCursor,
          groupId: groupId,
          sourceTable: 'group_inbox_cursors',
          sourceId: groupId,
        ),
      );
    }

    final items = <MigrationGroupInboxCursorMetadata>[];
    for (final row in cursorRows) {
      final cursor = _stringValueAllowEmpty(row['cursor']);
      final createdAt = _stringValue(row['created_at']);
      final updatedAt = _stringValue(row['updated_at']);
      if (cursor == null || createdAt == null || updatedAt == null) {
        issues.add(
          MigrationGroupManifestIssue(
            code: MigrationGroupManifestIssueCode.malformedGroupInboxCursor,
            groupId: groupId,
            sourceTable: 'group_inbox_cursors',
            sourceId: groupId,
          ),
        );
        continue;
      }
      items.add(
        MigrationGroupInboxCursorMetadata(
          groupId: groupId,
          cursor: cursor,
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
    }
    return items;
  }

  bool _pushPreviewReady(
    String groupId,
    List<MigrationGroupManifestIssue> issues,
  ) {
    return !issues.any(
      (issue) =>
          issue.groupId == groupId &&
          (issue.code ==
                  MigrationGroupManifestIssueCode.missingSharedGroupKeyMirror ||
              issue.code ==
                  MigrationGroupManifestIssueCode.sharedGroupKeyMirrorMismatch),
    );
  }

  Future<_ResolvedKeyValue?> _resolvePrimaryKeyValue(Object? rawValue) async {
    final value = _stringValue(rawValue);
    if (value == null || value.isEmpty) {
      return null;
    }
    if (!isSecureStoreReference(value)) {
      return _ResolvedKeyValue(keyName: 'inline', value: value);
    }
    final keyName = secureStoreKeyFromReference(value);
    final resolved = await primaryStore.read(keyName);
    if (resolved == null || resolved.isEmpty) {
      return null;
    }
    return _ResolvedKeyValue(keyName: keyName, value: resolved);
  }

  static void _indexByGroupId(
    Iterable<Map<String, Object?>> rows,
    Map<String, List<Map<String, Object?>>> target,
    Set<String> groupIds,
  ) {
    for (final row in rows) {
      final groupId = _stringValue(row['group_id']);
      if (groupId == null) {
        continue;
      }
      groupIds.add(groupId);
      target.putIfAbsent(groupId, () => []).add(row);
    }
  }

  static int _compareKeyItems(
    MigrationGroupKeyManifestItem a,
    MigrationGroupKeyManifestItem b,
  ) {
    return a.keyGeneration.compareTo(b.keyGeneration);
  }

  static String _hash(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static String? _hashNullable(String? value) {
    if (value == null) {
      return null;
    }
    return _hash(value);
  }

  static bool _requiresPendingKeyRepair(String? status) {
    return status == 'pending_key' || status == 'undecryptable';
  }

  static String? _stringValue(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _stringValueAllowEmpty(Object? value) {
    if (value is! String) {
      return null;
    }
    return value.trim();
  }

  static int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}

class _ResolvedKeyValue {
  final String keyName;
  final String value;

  const _ResolvedKeyValue({required this.keyName, required this.value});
}
