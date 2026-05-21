import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Joins an existing group by subscribing to the topic, saving the group,
/// saving self as member, and storing the provided group key.
Future<void> joinGroup({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupModel group,
  required String groupKey,
  required int keyEpoch,
  required Map<String, dynamic> groupConfig,
  required String selfPeerId,
  required String selfPublicKey,
  required MemberRole selfRole,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_JOIN_USE_CASE_BEGIN',
    details: {
      'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
    },
  );

  _validateFullJoinMaterial(
    group: group,
    groupConfig: groupConfig,
    groupKey: groupKey,
    keyEpoch: keyEpoch,
    selfPeerId: selfPeerId,
    selfPublicKey: selfPublicKey,
  );

  // 1. Call bridge with full private-group join material.
  await callGroupJoinWithConfig(
    bridge,
    groupId: group.id,
    groupConfig: groupConfig,
    groupKey: groupKey,
    keyEpoch: keyEpoch,
  );

  // 2. Save group to repo
  await groupRepo.saveGroup(group);

  // 3. Save self as member
  final now = DateTime.now().toUtc();
  final selfMember = GroupMember(
    groupId: group.id,
    peerId: selfPeerId,
    role: selfRole,
    publicKey: selfPublicKey,
    joinedAt: now,
  );
  await groupRepo.saveMember(selfMember);

  // 4. Save group key
  final keyInfo = GroupKeyInfo(
    groupId: group.id,
    keyGeneration: keyEpoch,
    encryptedKey: groupKey,
    createdAt: now,
  );
  await groupRepo.saveKey(keyInfo);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_JOIN_USE_CASE_SUCCESS',
    details: {
      'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
    },
  );
}

void _validateFullJoinMaterial({
  required GroupModel group,
  required Map<String, dynamic> groupConfig,
  required String groupKey,
  required int keyEpoch,
  required String selfPeerId,
  required String selfPublicKey,
}) {
  final key = groupKey.trim();
  if (key.isEmpty) {
    _throwInvalidJoinMaterial('missing group key');
  }
  if (keyEpoch <= 0) {
    _throwInvalidJoinMaterial('missing key epoch');
  }
  if (groupConfig['name'] != group.name ||
      groupConfig['groupType'] != group.type.toValue()) {
    _throwInvalidJoinMaterial('group config metadata mismatch');
  }
  if (!_hasNonEmptyString(groupConfig, 'createdBy') ||
      !_hasNonEmptyString(groupConfig, 'createdAt')) {
    _throwInvalidJoinMaterial('group config missing creation metadata');
  }
  if (!isGroupConfigStateHashValid(
    groupId: group.id,
    groupConfig: groupConfig,
  )) {
    _throwInvalidJoinMaterial('invalid group config state hash');
  }

  final members = groupConfig['members'];
  if (members is! List || members.isEmpty) {
    _throwInvalidJoinMaterial('group config missing members');
  }
  final keyMaterialRejectReason = groupConfigMemberKeyMaterialRejectReason(
    groupConfig,
  );
  if (keyMaterialRejectReason != null) {
    _throwInvalidJoinMaterial(
      'invalid group member key material: $keyMaterialRejectReason',
    );
  }

  Map<dynamic, dynamic>? selfMember;
  for (final rawMember in members) {
    if (rawMember is! Map) {
      continue;
    }
    if (rawMember['peerId'] == selfPeerId) {
      selfMember = rawMember;
      break;
    }
  }
  if (selfMember == null) {
    _throwInvalidJoinMaterial('group config missing self member');
  }

  final memberRole = selfMember['role'];
  final memberPublicKey = selfMember['publicKey'];
  if (memberRole is! String || memberRole.trim().isEmpty) {
    _throwInvalidJoinMaterial('self member missing role');
  }
  if (memberPublicKey is! String ||
      memberPublicKey.trim() != selfPublicKey.trim()) {
    _throwInvalidJoinMaterial('self member public key mismatch');
  }
}

bool _hasNonEmptyString(Map<String, dynamic> value, String key) {
  final raw = value[key];
  return raw is String && raw.trim().isNotEmpty;
}

Never _throwInvalidJoinMaterial(String message) {
  throw BridgeCommandException('group:join', 'INVALID_JOIN_MATERIAL', message);
}
