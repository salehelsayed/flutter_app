import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  final adminGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  final memberGroup = GroupModel(
    id: 'group-2',
    name: 'Member Group',
    type: GroupType.chat,
    topicName: 'group-topic-2',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    groupRecoveryGate.resetForTest();

    await groupRepo.saveGroup(adminGroup);
    await groupRepo.saveGroup(memberGroup);
  });

  tearDown(() {
    groupRecoveryGate.resetForTest();
  });

  Future<void> seedGroupMembers({
    required String groupId,
    required int totalMembers,
  }) async {
    for (var index = 0; index < totalMembers; index++) {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: index == 0 ? 'peer-admin' : 'peer-seed-$index',
          username: index == 0 ? 'Admin' : 'Seed $index',
          role: index == 0 ? MemberRole.admin : MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  test('adds member successfully when caller is admin', () async {
    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-new',
      username: 'NewUser',
      role: MemberRole.writer,
      publicKey: 'pk-peer-new',
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: newMember,
      selfPeerId: 'peer-admin',
    );

    final members = await groupRepo.getMembers('group-1');
    expect(members.length, 1);
    expect(members.first.peerId, 'peer-new');
  });

  test('allows adding the 50th member under the shared contract', () async {
    await seedGroupMembers(
      groupId: 'group-1',
      totalMembers: groupMembershipLimit - 1,
    );

    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-50',
      username: 'Member Fifty',
      role: MemberRole.writer,
      publicKey: 'pk-peer-50',
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: newMember,
      selfPeerId: 'peer-admin',
    );

    final saved = await groupRepo.getMember('group-1', 'peer-50');
    expect(saved, isNotNull);
    final members = await groupRepo.getMembers('group-1');
    expect(members.length, groupMembershipLimit);
  });

  test('GM-002 addGroupMember syncs updated A/B/C/D config payload', () async {
    final joinedAt = DateTime.utc(2026, 5, 10, 9);

    GroupMemberDeviceIdentity device(String peerId) =>
        GroupMemberDeviceIdentity(
          deviceId: '$peerId-device',
          transportPeerId: '$peerId-device',
          deviceSigningPublicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-$peerId-device',
          keyPackageId: 'key-package-$peerId-device',
          keyPackagePublicMaterial: 'key-package-public-$peerId-device',
        );

    GroupMember member({
      required String peerId,
      required String username,
      required MemberRole role,
    }) {
      return GroupMember(
        groupId: 'group-1',
        peerId: peerId,
        username: username,
        role: role,
        publicKey: 'pk-$peerId',
        mlKemPublicKey: 'mlkem-$peerId',
        devices: [device(peerId)],
        joinedAt: joinedAt,
      );
    }

    await groupRepo.saveMember(
      member(peerId: 'peer-admin', username: 'Admin', role: MemberRole.admin),
    );
    await groupRepo.saveMember(
      member(peerId: 'peer-b', username: 'Bob', role: MemberRole.writer),
    );
    await groupRepo.saveMember(
      member(peerId: 'peer-c', username: 'Charlie', role: MemberRole.writer),
    );

    final diana = member(
      peerId: 'peer-d',
      username: 'Diana',
      role: MemberRole.writer,
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: diana,
      selfPeerId: 'peer-admin',
    );

    final saved = await groupRepo.getMember('group-1', 'peer-d');
    expect(saved, isNotNull);
    expect(saved!.publicKey, 'pk-peer-d');
    expect(saved.mlKemPublicKey, 'mlkem-peer-d');
    expect(saved.devices.map((device) => device.deviceId), ['peer-d-device']);

    expect(
      bridge.commandLog.where((command) => command == 'group:updateConfig'),
      hasLength(1),
    );

    final updateConfigMessage = bridge.sentMessages.firstWhere((message) {
      final parsed = jsonDecode(message) as Map<String, dynamic>;
      return parsed['cmd'] == 'group:updateConfig';
    });
    final payload =
        (jsonDecode(updateConfigMessage) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(payload['groupId'], 'group-1');

    final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
    expect(
      isGroupConfigStateHashValid(groupId: 'group-1', groupConfig: groupConfig),
      isTrue,
    );

    final members = (groupConfig['members'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(members.map((member) => member['peerId']).toSet(), {
      'peer-admin',
      'peer-b',
      'peer-c',
      'peer-d',
    });

    final dianaConfig = members.singleWhere(
      (member) => member['peerId'] == 'peer-d',
    );
    expect(dianaConfig['username'], 'Diana');
    expect(dianaConfig['role'], 'writer');
    expect(dianaConfig['publicKey'], 'pk-peer-d');
    expect(dianaConfig['mlKemPublicKey'], 'mlkem-peer-d');
    final dianaDevices = (dianaConfig['devices'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(dianaDevices, hasLength(1));
    expect(dianaDevices.single['deviceId'], 'peer-d-device');
    expect(dianaDevices.single['transportPeerId'], 'peer-d-device');
    expect(dianaDevices.single['deviceSigningPublicKey'], 'pk-peer-d');
  });

  test(
    'GM-022 buildGroupConfigPayload emits one active Charlie after repeated re-add shadows',
    () {
      final baseAt = DateTime.utc(2026, 5, 11, 8);

      GroupMemberDeviceIdentity device({
        required String keyPackageId,
        GroupMemberDeviceStatus status = GroupMemberDeviceStatus.active,
        DateTime? revokedAt,
      }) {
        return GroupMemberDeviceIdentity(
          deviceId: 'charlie-device',
          transportPeerId: 'charlie-device',
          deviceSigningPublicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-charlie-device',
          keyPackageId: keyPackageId,
          keyPackagePublicMaterial: 'public-$keyPackageId',
          status: status,
          revokedAt: revokedAt,
        );
      }

      GroupMember charlie({
        required String keyPackageId,
        required DateTime joinedAt,
        GroupMemberDeviceStatus status = GroupMemberDeviceStatus.active,
        DateTime? revokedAt,
      }) {
        return GroupMember(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-charlie',
          devices: <GroupMemberDeviceIdentity>[
            device(
              keyPackageId: keyPackageId,
              status: status,
              revokedAt: revokedAt,
            ),
          ],
          joinedAt: joinedAt,
        );
      }

      final payload = buildGroupConfigPayload(adminGroup, [
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: baseAt,
        ),
        charlie(
          keyPackageId: 'kp-charlie-stale',
          joinedAt: baseAt,
          status: GroupMemberDeviceStatus.revoked,
          revokedAt: baseAt.add(const Duration(minutes: 1)),
        ),
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          joinedAt: baseAt,
        ),
        charlie(
          keyPackageId: 'kp-charlie-active',
          joinedAt: baseAt.add(const Duration(minutes: 20)),
        ),
      ]);

      final members = (payload['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final memberPeerIds = members.map((member) => member['peerId']).toList();
      expect(memberPeerIds.where((peerId) => peerId == 'peer-charlie'), [
        'peer-charlie',
      ]);
      expect(memberPeerIds.toSet(), {'peer-admin', 'peer-bob', 'peer-charlie'});

      final charlieConfig = members.singleWhere(
        (member) => member['peerId'] == 'peer-charlie',
      );
      final devices = (charlieConfig['devices'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(devices, hasLength(1));
      expect(devices.single['keyPackageId'], 'kp-charlie-active');
      expect(jsonEncode(payload), isNot(contains('kp-charlie-stale')));
      expect(
        isGroupConfigStateHashValid(groupId: 'group-1', groupConfig: payload),
        isTrue,
      );
    },
  );

  test(
    'GM-023 buildGroupConfigPayload selects active Charlie after inactive shadow',
    () {
      final baseAt = DateTime.utc(2026, 5, 11, 9);

      GroupMemberDeviceIdentity device({
        required String keyPackageId,
        required GroupMemberDeviceStatus status,
        DateTime? revokedAt,
      }) {
        return GroupMemberDeviceIdentity(
          deviceId: 'charlie-device',
          transportPeerId: 'charlie-device',
          deviceSigningPublicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-charlie-device',
          keyPackageId: keyPackageId,
          keyPackagePublicMaterial: 'public-$keyPackageId',
          status: status,
          revokedAt: revokedAt,
        );
      }

      GroupMember charlie({
        required String keyPackageId,
        required DateTime joinedAt,
        required GroupMemberDeviceStatus status,
        DateTime? revokedAt,
      }) {
        return GroupMember(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-charlie',
          devices: <GroupMemberDeviceIdentity>[
            device(
              keyPackageId: keyPackageId,
              status: status,
              revokedAt: revokedAt,
            ),
          ],
          joinedAt: joinedAt,
        );
      }

      final inactiveShadow = charlie(
        keyPackageId: 'kp-charlie-inactive',
        joinedAt: baseAt,
        status: GroupMemberDeviceStatus.revoked,
        revokedAt: baseAt.add(const Duration(minutes: 1)),
      );
      final activeCharlie = charlie(
        keyPackageId: 'kp-charlie-active',
        joinedAt: baseAt.add(const Duration(minutes: 10)),
        status: GroupMemberDeviceStatus.active,
      );
      final payload = buildGroupConfigPayload(adminGroup, [
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: baseAt,
        ),
        inactiveShadow,
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          joinedAt: baseAt,
        ),
        activeCharlie,
      ]);

      final members = (payload['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        members
            .map((member) => member['peerId'])
            .where((peerId) => peerId == 'peer-charlie'),
        ['peer-charlie'],
      );
      final charlieConfig = members.singleWhere(
        (member) => member['peerId'] == 'peer-charlie',
      );
      final devices = (charlieConfig['devices'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(devices, hasLength(1));
      expect(devices.single['status'], 'active');
      expect(devices.single['keyPackageId'], 'kp-charlie-active');
      expect(jsonEncode(payload), isNot(contains('kp-charlie-inactive')));
      expect(
        isGroupConfigStateHashValid(groupId: 'group-1', groupConfig: payload),
        isTrue,
      );
    },
  );

  test(
    'GM-027 rejects unknown member without deliverable peer/device identity before save or config sync',
    () async {
      final invalidMember = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-gm027-unknown',
        username: 'Unknown',
        role: MemberRole.writer,
        joinedAt: DateTime.utc(2026, 5, 11, 10),
      );

      await expectLater(
        addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          newMember: invalidMember,
          selfPeerId: 'peer-admin',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('delivery identity'),
          ),
        ),
      );

      expect(
        await groupRepo.getMember('group-1', 'peer-gm027-unknown'),
        isNull,
      );
      expect(
        bridge.commandLog.where((command) => command == 'group:updateConfig'),
        isEmpty,
      );
    },
  );

  test('GM-028 rejects empty PeerId before save or config sync', () async {
    final invalidMember = GroupMember(
      groupId: 'group-1',
      peerId: '   ',
      username: 'Blank Peer',
      role: MemberRole.writer,
      publicKey: 'pk-gm028-blank',
      mlKemPublicKey: 'mlkem-gm028-blank',
      devices: const <GroupMemberDeviceIdentity>[
        GroupMemberDeviceIdentity(
          deviceId: 'gm028-blank-device',
          transportPeerId: 'gm028-blank-device',
          deviceSigningPublicKey: 'pk-gm028-blank-device',
          mlKemPublicKey: 'mlkem-gm028-blank-device',
          keyPackageId: 'kp-gm028-blank-device',
          keyPackagePublicMaterial: 'public-kp-gm028-blank-device',
        ),
      ],
      joinedAt: DateTime.utc(2026, 5, 11, 10, 30),
    );

    await expectLater(
      addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        newMember: invalidMember,
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('delivery identity'),
        ),
      ),
    );

    final members = await groupRepo.getMembers('group-1');
    expect(members.where((member) => member.peerId.trim().isEmpty), isEmpty);
    expect(await groupRepo.getMember('group-1', ''), isNull);
    expect(await groupRepo.getMember('group-1', '   '), isNull);
    expect(
      bridge.commandLog.where((command) => command == 'group:updateConfig'),
      isEmpty,
    );
  });

  test('rejects when caller is not admin', () async {
    final newMember = GroupMember(
      groupId: 'group-2',
      peerId: 'peer-new',
      username: 'NewUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    expect(
      () => addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-2',
        newMember: newMember,
        selfPeerId: 'peer-member',
      ),
      throwsA(isA<StateError>()),
    );

    expect(await groupRepo.getMember('group-2', 'peer-new'), isNull);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'allows writer with invite permission override to add a member',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-inviter',
          username: 'Inviter',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(inviteMembers: true),
          publicKey: 'pk-inviter',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final newMember = GroupMember(
        groupId: 'group-2',
        peerId: 'peer-custom',
        username: 'CustomInvitee',
        role: MemberRole.reader,
        publicKey: 'pk-custom',
        joinedAt: DateTime.now().toUtc(),
      );

      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-2',
        newMember: newMember,
        selfPeerId: 'peer-inviter',
      );

      expect(await groupRepo.getMember('group-2', 'peer-custom'), isNotNull);
      expect(bridge.commandLog, contains('group:updateConfig'));

      final updateConfigMessage = bridge.sentMessages.firstWhere((message) {
        final parsed = jsonDecode(message) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:updateConfig';
      });
      final payload =
          (jsonDecode(updateConfigMessage) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
      final members = (groupConfig['members'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final inviterEntry = members.firstWhere(
        (member) => member['peerId'] == 'peer-inviter',
      );
      expect(inviterEntry['role'], 'writer');
      expect(inviterEntry['permissions'], {'inviteMembers': true});
    },
  );

  test(
    'rechecks revoked invite permission before adding a queued member',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-inviter',
          username: 'Inviter',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(inviteMembers: true),
          publicKey: 'pk-inviter',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-inviter',
          username: 'Inviter',
          role: MemberRole.writer,
          publicKey: 'pk-inviter',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final queuedMember = GroupMember(
        groupId: 'group-2',
        peerId: 'peer-stale-invite',
        username: 'StaleInvitee',
        role: MemberRole.reader,
        publicKey: 'pk-stale-invite',
        joinedAt: DateTime.now().toUtc(),
      );

      await expectLater(
        addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-2',
          newMember: queuedMember,
          selfPeerId: 'peer-inviter',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Only admins can add members'),
          ),
        ),
      );

      expect(await groupRepo.getMember('group-2', 'peer-stale-invite'), isNull);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('denies admin whose invite permission override is false', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        permissions: const GroupMemberPermissions(inviteMembers: false),
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-denied',
      username: 'DeniedUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    await expectLater(
      addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        newMember: newMember,
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Only admins can add members'),
        ),
      ),
    );

    expect(await groupRepo.getMember('group-1', 'peer-denied'), isNull);
    expect(bridge.commandLog, isEmpty);
  });

  test('rejects while group recovery is in progress', () async {
    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-new',
      username: 'NewUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    groupRecoveryGate.begin();
    try {
      await expectLater(
        addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          newMember: newMember,
          selfPeerId: 'peer-admin',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(groupRecoveryPendingError),
          ),
        ),
      );
    } finally {
      groupRecoveryGate.end();
    }

    expect(bridge.commandLog, isEmpty);
    final saved = await groupRepo.getMember('group-1', 'peer-new');
    expect(saved, isNull);
  });

  test('throws when group not found', () async {
    final newMember = GroupMember(
      groupId: 'nonexistent-group',
      peerId: 'peer-new',
      username: 'NewUser',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );

    expect(
      () => addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'nonexistent-group',
        newMember: newMember,
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Group not found'),
        ),
      ),
    );
  });

  test(
    'rejects duplicate member before sync and preserves original row',
    () async {
      final originalMember = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-duplicate',
        username: 'FirstAdd',
        role: MemberRole.writer,
        publicKey: 'pk-peer-duplicate',
        joinedAt: DateTime.now().toUtc(),
      );

      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        newMember: originalMember,
        selfPeerId: 'peer-admin',
      );

      bridge.commandLog.clear();

      final duplicateAttempt = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-duplicate',
        username: 'SecondAdd',
        role: MemberRole.reader,
        publicKey: 'pk-peer-duplicate-second',
        joinedAt: DateTime.now().toUtc(),
      );

      await expectLater(
        addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          newMember: duplicateAttempt,
          selfPeerId: 'peer-admin',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already exists'),
          ),
        ),
      );

      final members = await groupRepo.getMembers('group-1');
      final duplicates = members
          .where((m) => m.peerId == 'peer-duplicate')
          .toList();
      expect(duplicates.length, 1);
      expect(duplicates.first.username, 'FirstAdd');
      expect(duplicates.first.role, MemberRole.writer);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('rejects adding a 51st member before config sync', () async {
    await seedGroupMembers(
      groupId: 'group-1',
      totalMembers: groupMembershipLimit,
    );
    bridge.commandLog.clear();

    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-over-limit',
      username: 'Overflow',
      role: MemberRole.writer,
      publicKey: 'pk-peer-over-limit',
      joinedAt: DateTime.now().toUtc(),
    );

    await expectLater(
      addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        newMember: newMember,
        selfPeerId: 'peer-admin',
      ),
      throwsA(
        isA<GroupMembershipLimitException>()
            .having((e) => e.maxMembers, 'maxMembers', groupMembershipLimit)
            .having(
              (e) => e.currentMemberCount,
              'currentMemberCount',
              groupMembershipLimit,
            )
            .having(
              (e) => e.requestedAdditionalMembers,
              'requestedAdditionalMembers',
              1,
            ),
      ),
    );

    expect(await groupRepo.getMember('group-1', 'peer-over-limit'), isNull);
    expect(bridge.commandLog, isEmpty);
  });

  test('saves member to repo', () async {
    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-saved',
      username: 'SavedUser',
      role: MemberRole.reader,
      publicKey: 'pk-peer-saved',
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: newMember,
      selfPeerId: 'peer-admin',
    );

    final saved = await groupRepo.getMember('group-1', 'peer-saved');
    expect(saved, isNotNull);
    expect(saved!.username, 'SavedUser');
    expect(saved.role, MemberRole.reader);
  });

  test('rolls back DB when group:updateConfig fails', () async {
    bridge.responses['group:updateConfig'] = {
      'ok': false,
      'errorCode': 'CONFIG_SYNC_FAILED',
      'errorMessage': 'bridge rejected config',
    };

    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-rollback',
      username: 'RollbackUser',
      role: MemberRole.writer,
      publicKey: 'pk-peer-rollback',
      joinedAt: DateTime.now().toUtc(),
    );

    await expectLater(
      addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: 'group-1',
        newMember: newMember,
        selfPeerId: 'peer-admin',
      ),
      throwsA(isA<Exception>()),
    );

    final saved = await groupRepo.getMember('group-1', 'peer-rollback');
    expect(saved, isNull);
  });

  test('syncBridgeConfig false skips bridge config sync', () async {
    final newMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-no-sync',
      username: 'NoSyncUser',
      role: MemberRole.writer,
      publicKey: 'pk-peer-no-sync',
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      newMember: newMember,
      selfPeerId: 'peer-admin',
      syncBridgeConfig: false,
    );

    final saved = await groupRepo.getMember('group-1', 'peer-no-sync');
    expect(saved, isNotNull);
    expect(
      bridge.commandLog.where((command) => command == 'group:updateConfig'),
      isEmpty,
    );
  });
}
