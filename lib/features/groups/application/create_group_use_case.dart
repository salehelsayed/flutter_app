import 'dart:convert';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Creates a new group, saves it to the repository, adds the creator as admin,
/// and generates the initial group key.
///
/// Returns the created [GroupModel] on success. Throws on bridge or persistence errors.
Future<GroupModel> createGroup({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String name,
  required GroupType type,
  required String creatorPeerId,
  required String creatorPublicKey,
  required String creatorMlKemPublicKey,
  String? creatorUsername,
  String? creatorPrivateKey,
  AppendGroupEventLogEntry? appendGroupEventLogEntry,
  String? description,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_CREATE_USE_CASE_BEGIN',
    details: {'name': name, 'type': type.toValue()},
  );

  if (name.trim().isEmpty) {
    throw ArgumentError('Group name must not be empty');
  }

  // 1. Call bridge to create the group topic
  final result = await callGroupCreate(
    bridge,
    name: name,
    type: type.toValue(),
    creatorPeerId: creatorPeerId,
    creatorPublicKey: creatorPublicKey,
    creatorMlKemPublicKey: creatorMlKemPublicKey,
    description: description,
  );

  if (result['ok'] != true) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CREATE_USE_CASE_BRIDGE_ERROR',
      details: {'errorCode': result['errorCode']},
    );
    throw Exception(
      result['errorMessage'] ?? 'Failed to create group via bridge',
    );
  }

  // 2. Parse result
  final groupId = result['groupId'] as String? ?? const Uuid().v4();
  final topicName = result['topicName'] as String? ?? '/mknoon/group/$groupId';
  final now = DateTime.now().toUtc();

  // 3. Create GroupModel
  final group = GroupModel(
    id: groupId,
    name: name.trim(),
    type: type,
    topicName: topicName,
    description: description,
    createdAt: now,
    createdBy: creatorPeerId,
    myRole: GroupRole.admin,
  );

  // 4. Save group to repo
  await groupRepo.saveGroup(group);

  // 5. Save self as admin member
  final selfMember = GroupMember(
    groupId: groupId,
    peerId: creatorPeerId,
    username: creatorUsername,
    role: MemberRole.admin,
    publicKey: creatorPublicKey,
    mlKemPublicKey: creatorMlKemPublicKey,
    joinedAt: now,
  );
  await groupRepo.saveMember(selfMember);

  // 6. Save group key returned by GroupCreateTopic (Go already generates it)
  final groupKey = result['groupKey'] as String?;
  final keyEpoch = result['keyEpoch'] as int? ?? 0;
  final resolvedKeyEpoch = groupKey != null ? keyEpoch : 0;
  if (groupKey != null) {
    final keyInfo = GroupKeyInfo(
      groupId: groupId,
      keyGeneration: resolvedKeyEpoch,
      encryptedKey: groupKey,
      createdAt: now,
    );
    await groupRepo.saveKey(keyInfo);
  } else {
    // Fallback: generate key separately if create didn't return one
    try {
      final generatedKey = await callGroupKeygen(bridge);
      final keyInfo = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 0,
        encryptedKey: generatedKey,
        createdAt: now,
      );
      await groupRepo.saveKey(keyInfo);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CREATE_USE_CASE_KEYGEN_ERROR',
        details: {'error': e.toString()},
      );
      await _rollbackCreatedGroup(groupRepo, groupId);
      throw StateError(
        'Group creation did not finish because no usable group key was available.',
      );
    }
  }

  if (creatorPrivateKey != null &&
      creatorPrivateKey.isNotEmpty &&
      appendGroupEventLogEntry != null) {
    try {
      await _appendSignedCreateEvent(
        bridge: bridge,
        appendGroupEventLogEntry: appendGroupEventLogEntry,
        group: group,
        creatorMember: selfMember,
        initialKeyEpoch: resolvedKeyEpoch,
        creatorPrivateKey: creatorPrivateKey,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CREATE_USE_CASE_INITIAL_EVENT_ERROR',
        details: {'groupId': groupId, 'error': e.toString()},
      );
      await _rollbackCreatedGroup(groupRepo, groupId);
      throw StateError(
        'Group creation did not finish because the initial membership event could not be signed.',
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_CREATE_USE_CASE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  return group;
}

Future<void> _appendSignedCreateEvent({
  required Bridge bridge,
  required AppendGroupEventLogEntry appendGroupEventLogEntry,
  required GroupModel group,
  required GroupMember creatorMember,
  required int initialKeyEpoch,
  required String creatorPrivateKey,
}) async {
  final unsignedPayload = <String, Object?>{
    'schemaVersion': 1,
    'eventType': 'group_created',
    'groupId': group.id,
    'topicName': group.topicName,
    'groupName': group.name,
    'groupType': group.type.toValue(),
    'createdAt': group.createdAt.toUtc().toIso8601String(),
    'createdBy': group.createdBy,
    'creator': <String, Object?>{
      'peerId': creatorMember.peerId,
      'username': creatorMember.username,
      'role': creatorMember.role.toValue(),
      'publicKey': creatorMember.publicKey,
      'mlKemPublicKey': creatorMember.mlKemPublicKey,
      'joinedAt': creatorMember.joinedAt.toUtc().toIso8601String(),
    },
    'initialKeyEpoch': initialKeyEpoch,
  };
  final canonicalPayload = canonicalizeGroupEventLogPayload(unsignedPayload);
  final signResponse = await callSignPayload(
    bridge: bridge,
    dataToSign: canonicalPayload,
    privateKey: creatorPrivateKey,
  );
  final signature = signResponse['signature'];
  if (signResponse['ok'] != true || signature is! String || signature.isEmpty) {
    throw StateError(
      signResponse['errorMessage']?.toString() ??
          'Initial membership event signing failed',
    );
  }

  await appendGroupEventLogEntry(
    groupId: group.id,
    eventType: 'group_created',
    sourcePeerId: creatorMember.peerId,
    sourceEventId: 'group_created:${group.id}',
    sourceTimestamp: group.createdAt.toUtc().toIso8601String(),
    createdAt: group.createdAt,
    payload: {
      ...unsignedPayload,
      'signedPayload': jsonDecode(canonicalPayload),
      'signature': signature,
      'signatureAlgorithm': 'ed25519',
    },
  );
}

Future<void> _rollbackCreatedGroup(
  GroupRepository groupRepo,
  String groupId,
) async {
  await groupRepo.removeAllMembers(groupId);
  await groupRepo.removeAllKeys(groupId);
  await groupRepo.deleteGroup(groupId);
}
