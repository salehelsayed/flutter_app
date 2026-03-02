import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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

  // 1. Call bridge to join the group topic
  await callGroupJoin(
    bridge,
    groupId: group.id,
    topicName: group.topicName,
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
