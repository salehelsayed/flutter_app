import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/086_pending_group_broadcasts.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository_impl.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late GroupPendingBroadcastRepositoryImpl repo;

  GroupPendingBroadcast broadcast({
    String id = 'b1',
    String groupId = 'group-1',
    String? sourceMessageId = 'src-1',
    String kind = 'group_metadata_updated',
    String sysText = '{"__sys":"group_metadata_updated"}',
    List<String> recipientPeerIds = const ['peer-alice', 'peer-bob'],
    DateTime? eventAt,
  }) => GroupPendingBroadcast(
    id: id,
    groupId: groupId,
    kind: kind,
    sysText: sysText,
    recipientPeerIds: recipientPeerIds,
    eventAt: eventAt ?? DateTime.utc(2026, 6, 17, 9),
    sourceMessageId: sourceMessageId,
    createdAt: DateTime.utc(2026, 6, 17, 9),
    updatedAt: DateTime.utc(2026, 6, 17, 9),
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runPendingGroupBroadcastsMigration(db);
    repo = GroupPendingBroadcastRepositoryImpl(
      dbInsert: (row) => dbInsertPendingGroupBroadcast(db, row),
      dbLoadForGroup: (groupId) =>
          dbLoadPendingGroupBroadcastsForGroup(db, groupId),
      dbLoadAll: () => dbLoadAllPendingGroupBroadcasts(db),
      dbCountForGroup: (groupId) =>
          dbCountPendingGroupBroadcastsForGroup(db, groupId),
      dbDelete: (id) => dbDeletePendingGroupBroadcast(db, id),
      dbDeleteForGroup: (groupId) =>
          dbDeletePendingGroupBroadcastsForGroup(db, groupId),
    );
  });

  tearDown(() async => db.close());

  test('migration creates the pending_group_broadcasts table', () async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      ['pending_group_broadcasts'],
    );
    expect(tables, hasLength(1));
  });

  test('enqueue then forGroup round-trips all fields', () async {
    await repo.enqueue(broadcast());
    final rows = await repo.forGroup('group-1');
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.kind, 'group_metadata_updated');
    expect(row.recipientPeerIds, ['peer-alice', 'peer-bob']);
    expect(row.eventAt, DateTime.utc(2026, 6, 17, 9));
    expect(row.sourceMessageId, 'src-1');
  });

  test('enqueue is idempotent on (groupId, sourceMessageId)', () async {
    await repo.enqueue(broadcast(id: 'b1'));
    await repo.enqueue(broadcast(id: 'b2')); // same group + sourceMessageId
    expect(await repo.countForGroup('group-1'), 1);
  });

  test('enqueue atomically activates a prepared member role row', () async {
    await repo.enqueue(
      broadcast(
        id: 'prepared-id',
        kind: groupPendingBroadcastKindMemberRolePrepared,
        sysText: '{"phase":"prepared"}',
        recipientPeerIds: const ['peer-old'],
      ),
    );
    await repo.enqueue(
      broadcast(
        id: 'active-id',
        kind: groupPendingBroadcastKindMemberRoleUpdated,
        sysText: '{"phase":"active"}',
        recipientPeerIds: const ['peer-new'],
      ),
    );

    final rows = await repo.forGroup('group-1');
    expect(rows, hasLength(1));
    expect(rows.single.id, 'active-id');
    expect(rows.single.kind, groupPendingBroadcastKindMemberRoleUpdated);
    expect(rows.single.sysText, '{"phase":"active"}');
    expect(rows.single.recipientPeerIds, ['peer-new']);
  });

  test('concurrent prepared and active enqueue settles active', () async {
    final prepared = broadcast(
      id: 'prepared-id',
      kind: groupPendingBroadcastKindMemberRolePrepared,
    );
    final active = broadcast(
      id: 'active-id',
      kind: groupPendingBroadcastKindMemberRoleUpdated,
    );

    await Future.wait([repo.enqueue(prepared), repo.enqueue(active)]);

    final rows = await repo.forGroup('group-1');
    expect(rows, hasLength(1));
    expect(rows.single.id, 'active-id');
    expect(rows.single.kind, groupPendingBroadcastKindMemberRoleUpdated);
  });

  test('distinct sourceMessageId enqueues separate rows', () async {
    await repo.enqueue(broadcast(id: 'b1', sourceMessageId: 'src-1'));
    await repo.enqueue(broadcast(id: 'b2', sourceMessageId: 'src-2'));
    expect(await repo.countForGroup('group-1'), 2);
  });

  test('remove clears a drained row', () async {
    await repo.enqueue(broadcast(id: 'b1'));
    await repo.remove('b1');
    expect(await repo.countForGroup('group-1'), 0);
    expect(await repo.forGroup('group-1'), isEmpty);
  });

  test('removeForGroup deletes only the target group rows', () async {
    await repo.enqueue(broadcast(id: 'b1', groupId: 'group-1'));
    await repo.enqueue(
      broadcast(id: 'b2', groupId: 'group-1', sourceMessageId: 'src-2'),
    );
    await repo.enqueue(broadcast(id: 'b3', groupId: 'group-2'));

    await repo.removeForGroup('group-1');

    expect(await repo.forGroup('group-1'), isEmpty);
    expect((await repo.forGroup('group-2')).map((row) => row.id), ['b3']);
  });

  test('all returns rows across groups', () async {
    await repo.enqueue(broadcast(id: 'b1', groupId: 'group-1'));
    await repo.enqueue(broadcast(id: 'b2', groupId: 'group-2'));
    expect(await repo.all(), hasLength(2));
  });

  test('migration is idempotent', () async {
    await runPendingGroupBroadcastsMigration(db);
    await repo.enqueue(broadcast());
    expect(await repo.countForGroup('group-1'), 1);
  });
}
