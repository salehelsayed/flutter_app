import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/update_group_member_role_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  const groupId = 'group-gm029-producers';
  const adminPeerId = 'peer-gm029-admin';
  const targetPeerId = 'peer-gm029-target';
  final createdAt = DateTime.utc(2026, 5, 11, 8);
  final membershipEventAt = createdAt.add(const Duration(minutes: 5));
  final laterMetadataEventAt = createdAt.add(const Duration(minutes: 20));

  GroupModel baseGroup() {
    return GroupModel(
      id: groupId,
      name: 'GM-029 Producer Group',
      type: GroupType.chat,
      topicName: 'topic-gm029-producers',
      createdAt: createdAt,
      createdBy: adminPeerId,
      myRole: GroupRole.admin,
      lastMetadataEventAt: laterMetadataEventAt,
    );
  }

  GroupMember member({
    required String peerId,
    required String username,
    required MemberRole role,
    DateTime? joinedAt,
  }) {
    return GroupMember(
      groupId: groupId,
      peerId: peerId,
      username: username,
      role: role,
      publicKey: 'pk-$peerId',
      joinedAt: joinedAt ?? createdAt,
    );
  }

  Map<String, dynamic> latestGroupConfig() {
    for (final raw in bridge.sentMessages.reversed) {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      if (parsed['cmd'] != 'group:updateConfig') {
        continue;
      }
      final payload = parsed['payload'] as Map<String, dynamic>;
      return Map<String, dynamic>.from(payload['groupConfig'] as Map);
    }
    fail('No group:updateConfig payload was emitted');
  }

  Future<void> seedGroup({bool includeTarget = false}) async {
    await groupRepo.saveGroup(baseGroup());
    await groupRepo.saveMember(
      member(peerId: adminPeerId, username: 'Admin', role: MemberRole.admin),
    );
    if (includeTarget) {
      await groupRepo.saveMember(
        member(
          peerId: targetPeerId,
          username: 'Target',
          role: MemberRole.writer,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        ),
      );
    }
  }

  Future<void> expectMembershipVersionWatermarkAlignment() async {
    final groupConfig = latestGroupConfig();
    expect(
      groupConfig[groupConfigVersionField],
      membershipEventAt.toUtc().toIso8601String(),
    );
    expect(
      isGroupConfigStateHashValid(groupId: groupId, groupConfig: groupConfig),
      isTrue,
    );

    final persistedGroup = await groupRepo.getGroup(groupId);
    expect(persistedGroup, isNotNull);
    expect(persistedGroup!.lastMembershipEventAt, membershipEventAt);
    expect(persistedGroup.lastMetadataEventAt, laterMetadataEventAt);
  }

  setUp(() {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    groupRecoveryGate.resetForTest();
  });

  tearDown(() {
    groupRecoveryGate.resetForTest();
  });

  test(
    'GM-029 add producer emits membership configVersion when metadata is newer',
    () async {
      await seedGroup();

      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        newMember: member(
          peerId: targetPeerId,
          username: 'Target',
          role: MemberRole.writer,
          joinedAt: membershipEventAt,
        ),
        selfPeerId: adminPeerId,
      );

      await expectMembershipVersionWatermarkAlignment();
      expect(await groupRepo.getMember(groupId, targetPeerId), isNotNull);
      final members = (latestGroupConfig()['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(members.map((member) => member['peerId']), contains(targetPeerId));
    },
  );

  test(
    'GM-029 remove producer emits membership configVersion when metadata is newer',
    () async {
      await seedGroup(includeTarget: true);

      await removeGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: targetPeerId,
        selfPeerId: adminPeerId,
        eventAt: membershipEventAt,
      );

      await expectMembershipVersionWatermarkAlignment();
      expect(await groupRepo.getMember(groupId, targetPeerId), isNull);
      final members = (latestGroupConfig()['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        members.map((member) => member['peerId']),
        isNot(contains(targetPeerId)),
      );
    },
  );

  test(
    'GM-029 role-update producer emits membership configVersion when metadata is newer',
    () async {
      await seedGroup(includeTarget: true);

      await updateGroupMemberRole(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        memberPeerId: targetPeerId,
        role: MemberRole.reader,
        selfPeerId: adminPeerId,
        eventAt: membershipEventAt,
      );

      await expectMembershipVersionWatermarkAlignment();
      expect(
        (await groupRepo.getMember(groupId, targetPeerId))!.role,
        MemberRole.reader,
      );
      final members = (latestGroupConfig()['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final target = members.singleWhere(
        (member) => member['peerId'] == targetPeerId,
      );
      expect(target['role'], 'reader');
    },
  );

  test(
    'GM-029 default config payload still uses later metadata version without override',
    () async {
      final group = baseGroup().copyWith(
        lastMembershipEventAt: membershipEventAt,
      );
      final payload = buildGroupConfigPayload(group, [
        member(peerId: adminPeerId, username: 'Admin', role: MemberRole.admin),
      ]);

      expect(
        payload[groupConfigVersionField],
        laterMetadataEventAt.toUtc().toIso8601String(),
      );
      expect(
        isGroupConfigStateHashValid(groupId: groupId, groupConfig: payload),
        isTrue,
      );
    },
  );
}
