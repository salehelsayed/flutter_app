import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Result of handling an incoming group invite.
enum HandleGroupInviteResult {
  success,
  duplicateGroup,
  invalidPayload,
  unknownSender,
  decryptionFailed,
  bridgeError,
}

enum StorePendingGroupInviteResult {
  storedPending,
  duplicateGroup,
  invalidPayload,
  unknownSender,
  decryptionFailed,
}

enum _ResolveIncomingGroupInviteResult {
  success,
  invalidPayload,
  unknownSender,
  decryptionFailed,
}

class _ResolvedGroupInvite {
  final GroupInvitePayload payload;

  const _ResolvedGroupInvite(this.payload);
}

Future<(_ResolveIncomingGroupInviteResult, _ResolvedGroupInvite?)>
_resolveIncomingGroupInvite({
  required ChatMessage message,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
}) async {
  GroupInvitePayload? payload;

  final v2Envelope = GroupInvitePayload.parseEncryptedEnvelope(message.content);
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_HANDLE_ENVELOPE_CHECK',
    details: {
      'isV2': v2Envelope != null,
      'contentLength': message.content.length,
    },
  );
  if (v2Envelope != null) {
    final encrypted = v2Envelope['encrypted'] as Map<String, dynamic>;
    final kem = encrypted['kem'] as String;
    final ciphertext = encrypted['ciphertext'] as String;
    final nonce = encrypted['nonce'] as String;

    if (ownMlKemSecretKey == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_NO_SECRET_KEY',
        details: {},
      );
      return (_ResolveIncomingGroupInviteResult.decryptionFailed, null);
    }

    try {
      final decryptResult = await callDecryptMessage(
        bridge: bridge,
        ownMlKemSecretKey: ownMlKemSecretKey,
        kem: kem,
        ciphertext: ciphertext,
        nonce: nonce,
      );

      if (decryptResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITE_HANDLE_DECRYPT_FAILED',
          details: {'errorCode': decryptResult['errorCode']},
        );
        return (_ResolveIncomingGroupInviteResult.decryptionFailed, null);
      }

      final plaintext = decryptResult['plaintext'] as String;
      payload = GroupInvitePayload.fromInnerJson(plaintext);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_DECRYPT_ERROR',
        details: {'error': e.toString()},
      );
      return (_ResolveIncomingGroupInviteResult.decryptionFailed, null);
    }
  } else {
    payload = GroupInvitePayload.fromJson(message.content);
  }

  if (payload == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_INVALID_PAYLOAD',
      details: {},
    );
    return (_ResolveIncomingGroupInviteResult.invalidPayload, null);
  }

  if (payload.senderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_SENDER_MISMATCH',
      details: {
        'transportSender': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'payloadSender': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (_ResolveIncomingGroupInviteResult.invalidPayload, null);
  }

  final senderPeerId = payload.senderPeerId;
  final contact = await contactRepo.getContact(senderPeerId);
  if (contact == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_UNKNOWN_SENDER',
      details: {
        'senderPeerId': senderPeerId.length > 10
            ? senderPeerId.substring(0, 10)
            : senderPeerId,
      },
    );
    return (_ResolveIncomingGroupInviteResult.unknownSender, null);
  }

  return (
    _ResolveIncomingGroupInviteResult.success,
    _ResolvedGroupInvite(payload),
  );
}

Future<(StorePendingGroupInviteResult, PendingGroupInvite?)>
storeIncomingPendingGroupInvite({
  required ChatMessage message,
  required GroupRepository groupRepo,
  required PendingGroupInviteRepository pendingInviteRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  DateTime? receivedAt,
  Duration ttl = pendingGroupInviteTtl,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_STORE_PENDING_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  final (resolveResult, resolvedInvite) = await _resolveIncomingGroupInvite(
    message: message,
    contactRepo: contactRepo,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
  );

  switch (resolveResult) {
    case _ResolveIncomingGroupInviteResult.invalidPayload:
      return (StorePendingGroupInviteResult.invalidPayload, null);
    case _ResolveIncomingGroupInviteResult.unknownSender:
      return (StorePendingGroupInviteResult.unknownSender, null);
    case _ResolveIncomingGroupInviteResult.decryptionFailed:
      return (StorePendingGroupInviteResult.decryptionFailed, null);
    case _ResolveIncomingGroupInviteResult.success:
      break;
  }

  final payload = resolvedInvite!.payload;
  final existingGroup = await groupRepo.getGroup(payload.groupId);
  if (existingGroup != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_STORE_PENDING_DUPLICATE_GROUP',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    return (StorePendingGroupInviteResult.duplicateGroup, null);
  }

  final invite = PendingGroupInvite.fromPayload(
    payload,
    receivedAt: (receivedAt ?? DateTime.now()).toUtc(),
    ttl: ttl,
  );
  await pendingInviteRepo.savePendingInvite(invite);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_STORE_PENDING_SUCCESS',
    details: {
      'groupId': payload.groupId.length > 8
          ? payload.groupId.substring(0, 8)
          : payload.groupId,
    },
  );
  return (StorePendingGroupInviteResult.storedPending, invite);
}

/// Processes an incoming group invite message.
///
/// Steps:
/// 1. Try v2 parse -> decrypt -> fromInnerJson. Fallback to v1 fromJson.
/// 2. Validate required fields (groupId, groupKey, groupConfig).
/// 3. Verify sender is a known contact.
/// 4. Check for duplicate group (getGroup(groupId) != null -> duplicateGroup).
/// 5. Parse groupConfig into GroupModel, members, key.
/// 6. Persist GroupModel with myRole = GroupRole.member.
/// 7. Persist each GroupMember from config.
/// 8. Persist GroupKeyInfo.
/// 9. Call callGroupJoinWithConfig (catch timeout -> bridgeError, but group is still persisted).
/// 10. Return success + groupId.
///
/// Returns a record of (result, groupId?) where groupId is non-null on success
/// or bridgeError (group was persisted).
Future<(HandleGroupInviteResult, String?)> handleIncomingGroupInvite({
  required ChatMessage message,
  required GroupRepository groupRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_HANDLE_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  final (resolveResult, resolvedInvite) = await _resolveIncomingGroupInvite(
    message: message,
    contactRepo: contactRepo,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
  );

  switch (resolveResult) {
    case _ResolveIncomingGroupInviteResult.invalidPayload:
      return (HandleGroupInviteResult.invalidPayload, null);
    case _ResolveIncomingGroupInviteResult.unknownSender:
      return (HandleGroupInviteResult.unknownSender, null);
    case _ResolveIncomingGroupInviteResult.decryptionFailed:
      return (HandleGroupInviteResult.decryptionFailed, null);
    case _ResolveIncomingGroupInviteResult.success:
      break;
  }

  return materializeAcceptedGroupInvitePayload(
    payload: resolvedInvite!.payload,
    groupRepo: groupRepo,
    bridge: bridge,
    downloadGroupAvatarFn: downloadGroupAvatarFn,
  );
}

Future<(HandleGroupInviteResult, String?)>
materializeAcceptedGroupInvitePayload({
  required GroupInvitePayload payload,
  required GroupRepository groupRepo,
  required Bridge bridge,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
}) async {
  final existingGroup = await groupRepo.getGroup(payload.groupId);
  if (existingGroup != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_DUPLICATE',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    return (HandleGroupInviteResult.duplicateGroup, null);
  }

  final config = payload.groupConfig;
  final groupName = config['name'] as String? ?? 'Unnamed Group';
  final groupTypeStr = config['groupType'] as String? ?? 'chat';
  final description = config['description'] as String?;
  final avatarBlobId = config['avatarBlobId'] as String?;
  final avatarMime = config['avatarMime'] as String?;
  final createdBy = config['createdBy'] as String? ?? payload.senderPeerId;
  final createdAtStr = config['createdAt'] as String?;
  final metadataUpdatedAtStr = config['metadataUpdatedAt'] as String?;
  final createdAt = createdAtStr != null
      ? DateTime.tryParse(createdAtStr) ?? DateTime.now().toUtc()
      : DateTime.now().toUtc();
  final metadataUpdatedAt = metadataUpdatedAtStr != null
      ? DateTime.tryParse(metadataUpdatedAtStr)?.toUtc()
      : null;

  // 6. Persist GroupModel with myRole = member
  final groupModel = GroupModel(
    id: payload.groupId,
    name: groupName,
    type: _parseGroupType(groupTypeStr),
    topicName: '/mknoon/group/${payload.groupId}',
    description: description,
    avatarBlobId: avatarBlobId,
    avatarMime: avatarMime,
    createdAt: createdAt,
    createdBy: createdBy,
    myRole: GroupRole.member,
    lastMetadataEventAt: metadataUpdatedAt,
  );
  await groupRepo.saveGroup(groupModel);

  // 7. Persist members from config
  final membersList = config['members'] as List<dynamic>? ?? [];
  for (final memberMap in membersList) {
    final m = memberMap as Map<String, dynamic>;
    final member = GroupMember(
      groupId: payload.groupId,
      peerId: m['peerId'] as String? ?? '',
      username: m['username'] as String?,
      role: _parseMemberRole(m['role'] as String? ?? 'member'),
      publicKey: m['publicKey'] as String?,
      mlKemPublicKey: m['mlKemPublicKey'] as String?,
      joinedAt: DateTime.now().toUtc(),
    );
    await groupRepo.saveMember(member);
  }

  // 8. Persist GroupKeyInfo
  final keyInfo = GroupKeyInfo(
    groupId: payload.groupId,
    keyGeneration: payload.keyEpoch,
    encryptedKey: payload.groupKey,
    createdAt: DateTime.now().toUtc(),
  );
  await groupRepo.saveKey(keyInfo);

  if (avatarBlobId != null && avatarMime != null) {
    final avatarPath = await (downloadGroupAvatarFn ?? downloadGroupAvatar)(
      bridge: bridge,
      groupId: payload.groupId,
      blobId: avatarBlobId,
    );
    if (avatarPath != null) {
      await groupRepo.updateGroup(groupModel.copyWith(avatarPath: avatarPath));
    }
  }

  // 9. Call bridge to join the group topic
  try {
    await callGroupJoinWithConfig(
      bridge,
      groupId: payload.groupId,
      groupConfig: config,
      groupKey: payload.groupKey,
      keyEpoch: payload.keyEpoch,
    );
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_BRIDGE_TIMEOUT',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    // Group is already persisted — bridge error just means we need to retry join later
    return (HandleGroupInviteResult.bridgeError, payload.groupId);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_BRIDGE_ERROR',
      details: {'error': e.toString()},
    );
    return (HandleGroupInviteResult.bridgeError, payload.groupId);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_HANDLE_SUCCESS',
    details: {
      'groupId': payload.groupId.length > 8
          ? payload.groupId.substring(0, 8)
          : payload.groupId,
    },
  );
  return (HandleGroupInviteResult.success, payload.groupId);
}

GroupType _parseGroupType(String value) {
  switch (value) {
    case 'chat':
      return GroupType.chat;
    case 'announcement':
      return GroupType.announcement;
    case 'qa':
      return GroupType.qa;
    default:
      return GroupType.chat;
  }
}

MemberRole _parseMemberRole(String value) {
  switch (value) {
    case 'admin':
      return MemberRole.admin;
    case 'writer':
      return MemberRole.writer;
    case 'reader':
      return MemberRole.reader;
    default:
      return MemberRole.writer;
  }
}
