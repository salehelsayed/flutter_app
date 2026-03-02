import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
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

  // 1. Try v2 encrypted envelope first, then fallback to v1
  GroupInvitePayload? payload;

  final v2Envelope =
      GroupInvitePayload.parseEncryptedEnvelope(message.content);
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_HANDLE_ENVELOPE_CHECK',
    details: {
      'isV2': v2Envelope != null,
      'contentLength': message.content.length,
    },
  );
  if (v2Envelope != null) {
    // v2 encrypted path — decrypt first
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
      return (HandleGroupInviteResult.decryptionFailed, null);
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
        return (HandleGroupInviteResult.decryptionFailed, null);
      }

      final plaintext = decryptResult['plaintext'] as String;
      payload = GroupInvitePayload.fromInnerJson(plaintext);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_DECRYPT_ERROR',
        details: {'error': e.toString()},
      );
      return (HandleGroupInviteResult.decryptionFailed, null);
    }
  } else {
    // v1 plaintext path
    payload = GroupInvitePayload.fromJson(message.content);
  }

  // 2. Validate required fields
  if (payload == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_INVALID_PAYLOAD',
      details: {},
    );
    return (HandleGroupInviteResult.invalidPayload, null);
  }

  // 3. Verify sender is a known contact
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
    return (HandleGroupInviteResult.unknownSender, null);
  }

  // 4. Check for duplicate group
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

  // 5. Parse groupConfig
  final config = payload.groupConfig;
  final groupName = config['name'] as String? ?? 'Unnamed Group';
  final groupTypeStr = config['groupType'] as String? ?? 'chat';
  final description = config['description'] as String?;
  final createdBy = config['createdBy'] as String? ?? senderPeerId;
  final createdAtStr = config['createdAt'] as String?;
  final createdAt = createdAtStr != null
      ? DateTime.tryParse(createdAtStr) ?? DateTime.now().toUtc()
      : DateTime.now().toUtc();

  // 6. Persist GroupModel with myRole = member
  final groupModel = GroupModel(
    id: payload.groupId,
    name: groupName,
    type: _parseGroupType(groupTypeStr),
    topicName: '/mknoon/group/${payload.groupId}',
    description: description,
    createdAt: createdAt,
    createdBy: createdBy,
    myRole: GroupRole.member,
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
