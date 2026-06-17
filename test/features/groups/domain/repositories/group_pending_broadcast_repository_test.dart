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
    DateTime? eventAt,
  }) => GroupPendingBroadcast(
    id: id,
    groupId: groupId,
    kind: 'group_metadata_updated',
    sysText: '{"__sys":"group_metadata_updated"}',
    recipientPeerIds: const ['peer-alice', 'peer-bob'],
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
