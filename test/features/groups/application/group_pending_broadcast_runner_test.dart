import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_pending_broadcast_repush.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

class _FakeRepo implements GroupPendingBroadcastRepository {
  final Map<String, GroupPendingBroadcast> rows = {};

  @override
  Future<void> enqueue(GroupPendingBroadcast b) async => rows[b.id] = b;

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async =>
      rows.values.where((b) => b.groupId == groupId).toList();

  @override
  Future<List<GroupPendingBroadcast>> all() async => rows.values.toList();

  @override
  Future<int> countForGroup(String groupId) async =>
      rows.values.where((b) => b.groupId == groupId).length;

  @override
  Future<void> remove(String id) async => rows.remove(id);

  @override
  Future<void> removeForGroup(String groupId) async {
    rows.removeWhere((_, broadcast) => broadcast.groupId == groupId);
  }
}

GroupPendingBroadcast _b(String id, {String groupId = 'group-1'}) =>
    GroupPendingBroadcast(
      id: id,
      groupId: groupId,
      kind: 'group_metadata_updated',
      sysText: '{}',
      recipientPeerIds: const ['peer-a'],
      eventAt: DateTime.utc(2026, 6, 17),
      sourceMessageId: 'src-$id',
      createdAt: DateTime.utc(2026, 6, 17),
      updatedAt: DateTime.utc(2026, 6, 17),
    );

void main() {
  late _FakeRepo repo;

  setUp(() => repo = _FakeRepo());

  test('drainForGroup re-pushes and clears every row on success', () async {
    await repo.enqueue(_b('b1'));
    await repo.enqueue(_b('b2'));
    final pushed = <String>[];
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async {
        pushed.add(b.id);
        return true;
      },
    );

    final drained = await runner.drainForGroup('group-1');
    expect(drained, 2);
    expect(pushed.toSet(), {'b1', 'b2'});
    expect(await repo.countForGroup('group-1'), 0);
  });

  test('a failed re-push retains the row for the next drain', () async {
    await repo.enqueue(_b('b1'));
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async => false,
    );

    expect(await runner.drainForGroup('group-1'), 0);
    expect(await repo.countForGroup('group-1'), 1);
  });

  test('a throwing re-push retains the row (never bubbles)', () async {
    await repo.enqueue(_b('b1'));
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async => throw Exception('bridge down'),
    );

    expect(await runner.drainForGroup('group-1'), 0);
    expect(await repo.countForGroup('group-1'), 1);
  });

  test('partial success clears only the succeeded rows', () async {
    await repo.enqueue(_b('b1'));
    await repo.enqueue(_b('b2'));
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async => b.id == 'b1',
    );

    expect(await runner.drainForGroup('group-1'), 1);
    final remaining = await repo.forGroup('group-1');
    expect(remaining.map((b) => b.id), ['b2']);
  });

  test('drainAll sweeps across groups', () async {
    await repo.enqueue(_b('b1', groupId: 'group-1'));
    await repo.enqueue(_b('b2', groupId: 'group-2'));
    final runner = GroupPendingBroadcastRunner(
      repository: repo,
      rePush: (b) async => true,
    );

    expect(await runner.drainAll(), 2);
    expect(await repo.all(), isEmpty);
  });

  test(
    'prepared role rows wait in flight and ambiguous commits stay retained',
    () async {
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-other',
          username: 'Other',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 6, 17),
        ),
      );
      final bridge = FakeBridge();
      final rePush = buildGroupPendingBroadcastRePush(
        bridge: bridge,
        groupRepo: groupRepo,
        loadIdentity: () async => null,
      );
      final prepared = GroupPendingBroadcast(
        id: 'prepared-role',
        groupId: 'group-1',
        kind: groupPendingBroadcastKindMemberRolePrepared,
        sysText: '{"member":{"peerId":"peer-other","role":"admin"}}',
        recipientPeerIds: const ['peer-other'],
        eventAt: DateTime.utc(2026, 6, 17),
        sourceMessageId: 'role-source',
        createdAt: DateTime.utc(2026, 6, 17),
        updatedAt: DateTime.utc(2026, 6, 17),
      );

      markGroupRolePreparationInFlight(prepared.id);
      addTearDown(() => clearGroupRolePreparationInFlight(prepared.id));
      expect(await rePush(prepared), isFalse);
      expect(bridge.commandLog, isNot(contains('group:publish')));

      await groupRepo.updateMemberRole(
        'group-1',
        'peer-other',
        MemberRole.admin,
      );
      expect(await rePush(prepared), isFalse);
      expect(bridge.commandLog, isNot(contains('group:publish')));

      clearGroupRolePreparationInFlight(prepared.id);
      expect(await rePush(prepared), isFalse);
      expect(bridge.commandLog, isNot(contains('group:publish')));
    },
  );

  test('prepared role row sends only with exact commit watermark', () async {
    final eventAt = DateTime.utc(2026, 6, 17);
    const sourceEventId = 'role-source';
    final groupRepo = InMemoryGroupRepository();
    await groupRepo.saveGroup(
      GroupModel(
        id: 'group-1',
        name: 'Group',
        type: GroupType.chat,
        topicName: 'topic-group-1',
        createdAt: eventAt,
        createdBy: 'peer-self',
        myRole: GroupRole.admin,
        lastMembershipEventAt: eventAt,
        lastMembershipEventId: sourceEventId,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-self',
        username: 'Self',
        role: MemberRole.admin,
        publicKey: 'pk-self',
        mlKemPublicKey: 'mlkem-self',
        joinedAt: eventAt,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-other',
        username: 'Other',
        role: MemberRole.admin,
        publicKey: 'pk-other',
        mlKemPublicKey: 'mlkem-other',
        joinedAt: eventAt,
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'group-key-1',
        createdAt: eventAt,
      ),
    );
    final identityRepo = FakeIdentityRepository();
    identityRepo.seed(
      FakeIdentityRepository.makeIdentity(
        peerId: 'peer-self',
        publicKey: 'pk-self',
        privateKey: 'sk-self',
        mlKemPublicKey: 'mlkem-self',
      ),
    );
    final bridge = FakeBridge();
    final rePush = buildGroupPendingBroadcastRePush(
      bridge: bridge,
      groupRepo: groupRepo,
      loadIdentity: identityRepo.loadIdentity,
    );
    final prepared = GroupPendingBroadcast(
      id: 'prepared-role-exact',
      groupId: 'group-1',
      kind: groupPendingBroadcastKindMemberRolePrepared,
      sysText: '{"member":{"peerId":"peer-other","role":"admin"}}',
      recipientPeerIds: const ['peer-other'],
      eventAt: eventAt,
      sourceMessageId: sourceEventId,
      createdAt: eventAt,
      updatedAt: eventAt,
    );

    expect(await rePush(prepared), isTrue);
    expect(bridge.commandLog, contains('group:publish'));
    expect(bridge.commandLog, contains('group:inboxStore'));
  });
}
