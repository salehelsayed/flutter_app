import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

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
}
