import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_pending_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/081_group_pending_reactions.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupPendingReactionsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> row({
    required String id,
    String groupId = 'group-1',
    String messageId = 'msg-1',
    String senderPeerId = 'peer-sender',
    String receivedAt = '2026-03-08T00:00:00.000Z',
  }) {
    return {
      'id': id,
      'group_id': groupId,
      'message_id': messageId,
      'sender_peer_id': senderPeerId,
      'transport_peer_id': 'transport-1',
      'sender_device_id': 'device-1',
      'sender_public_key': 'pk-1',
      'reaction_json': '{"id":"$id"}',
      'received_at': receivedAt,
      'created_at': receivedAt,
      'updated_at': receivedAt,
    };
  }

  test('dedup by id: re-upserting the same id keeps a single row', () async {
    await dbUpsertGroupPendingReaction(db, row(id: 'rxn-1'));
    await dbUpsertGroupPendingReaction(
      db,
      row(id: 'rxn-1', receivedAt: '2026-03-08T00:00:05.000Z'),
    );

    final all = await dbLoadGroupPendingReactions(db);
    expect(all, hasLength(1));
    expect(all.single['received_at'], '2026-03-08T00:00:05.000Z');
  });

  test('load-for-message filters by group + message, oldest-first', () async {
    await dbUpsertGroupPendingReaction(
      db,
      row(id: 'rxn-2', receivedAt: '2026-03-08T00:00:02.000Z'),
    );
    await dbUpsertGroupPendingReaction(
      db,
      row(id: 'rxn-1', receivedAt: '2026-03-08T00:00:01.000Z'),
    );
    await dbUpsertGroupPendingReaction(
      db,
      row(id: 'rxn-other', messageId: 'msg-2'),
    );

    final forMsg = await dbLoadGroupPendingReactionsForMessage(
      db,
      groupId: 'group-1',
      messageId: 'msg-1',
    );
    expect(forMsg.map((r) => r['id']), ['rxn-1', 'rxn-2']);
  });

  test('delete returns the claimed row count (exactly-once)', () async {
    await dbUpsertGroupPendingReaction(db, row(id: 'rxn-1'));
    expect(await dbDeleteGroupPendingReaction(db, 'rxn-1'), 1);
    expect(await dbDeleteGroupPendingReaction(db, 'rxn-1'), 0);
  });

  test('prune evicts oldest rows beyond the per-group cap', () async {
    for (var i = 0; i < 5; i++) {
      await dbUpsertGroupPendingReaction(
        db,
        row(
          id: 'rxn-$i',
          messageId: 'msg-$i',
          receivedAt: '2026-03-08T00:00:0$i.000Z',
        ),
      );
    }

    await dbPruneGroupPendingReactions(db, 'group-1', maxRows: 2);

    final remaining = await dbLoadGroupPendingReactions(db);
    // Newest two survive (rxn-3, rxn-4); oldest three evicted.
    expect(remaining.map((r) => r['id']).toSet(), {'rxn-3', 'rxn-4'});
  });

  test('deleteExpired removes rows older than the cutoff', () async {
    await dbUpsertGroupPendingReaction(
      db,
      row(id: 'old', receivedAt: '2026-03-01T00:00:00.000Z'),
    );
    await dbUpsertGroupPendingReaction(
      db,
      row(id: 'fresh', receivedAt: '2026-03-08T00:00:00.000Z'),
    );

    await dbDeleteExpiredGroupPendingReactions(
      db,
      olderThanIso: '2026-03-05T00:00:00.000Z',
    );

    final remaining = await dbLoadGroupPendingReactions(db);
    expect(remaining.map((r) => r['id']), ['fresh']);
  });
}
