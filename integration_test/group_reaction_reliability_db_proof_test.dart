/// Real-SQLCipher device proof for Finding 10 (group-reaction reliability),
/// the DB-layer changes that unit tests (sqflite_ffi / plain SQLite) cannot
/// cover because the device runs sqflite_sqlcipher:
///
///   * Phase 4 migration 081 `group_pending_reactions` durable buffer table +
///     its upsert/dedup/cap/TTL/claim helpers.
///   * Phase 5 migration 082 `message_reactions.removed_at` tombstone + the
///     soft-delete / tombstone-aware-loader semantics (INV-T1..T4).
///
/// The last-writer-wins *decision* lives in the pure-Dart use cases and is
/// proven exhaustively by the unit suites; this proof validates that the
/// underlying SQL behaves identically on the real encrypted engine.
@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/database/helpers/group_pending_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/016_message_reactions.dart';
import 'package:flutter_app/core/database/migrations/081_group_pending_reactions.dart';
import 'package:flutter_app/core/database/migrations/082_message_reaction_tombstone.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('real-SQLCipher reaction reliability DB proof (Finding 10)', () {
    late Database db;
    late String path;

    setUp(() async {
      final dir = await getDatabasesPath();
      // Unique-per-run name (no Math.random on device APIs available here, use
      // the high-resolution clock) so a crashed prior run can't collide.
      path = '$dir/reaction_reliability_proof_'
          '${DateTime.now().microsecondsSinceEpoch}.db';
      await databaseFactory.deleteDatabase(path);
      // Real SQLCipher: a non-empty password forces the encrypted engine.
      db = await openDatabase(path, password: 'proof-key');
      await runMessageReactionsMigration(db);
      await runGroupPendingReactionsMigration(db);
      await runMessageReactionTombstoneMigration(db);
    });

    tearDown(() async {
      await db.close();
      await databaseFactory.deleteDatabase(path);
    });

    Map<String, Object?> reactionRow({
      required String id,
      String messageId = 'msg-1',
      String emoji = '👍',
      String senderPeerId = 'peer-1',
      String timestamp = '2026-03-08T00:00:00.000Z',
      String? removedAt,
    }) => {
          'id': id,
          'message_id': messageId,
          'emoji': emoji,
          'sender_peer_id': senderPeerId,
          'timestamp': timestamp,
          'created_at': timestamp,
          'removed_at': removedAt,
        };

    testWidgets('082 tombstone: remove hides, comparand sees it, re-add clears',
        (tester) async {
      // The migrations applied on the real encrypted engine.
      final cols = await db.rawQuery('PRAGMA table_info(message_reactions)');
      expect(cols.any((c) => c['name'] == 'removed_at'), isTrue);

      // Add at T1.
      await dbInsertReaction(db, reactionRow(id: 'r-add'));
      expect(await dbLoadReactionsForMessage(db, 'msg-1'), hasLength(1));

      // Remove at T2 → tombstone: hidden from the loader, retained for LWW.
      final tombstoned = await dbDeleteReaction(db, 'msg-1', 'peer-1',
          removedAtTimestamp: '2026-03-08T00:00:05.000Z');
      expect(tombstoned, 1);
      expect(await dbLoadReactionsForMessage(db, 'msg-1'), isEmpty);
      final comparand =
          await dbLoadActiveOrTombstonedReactionForSender(db, 'msg-1', 'peer-1');
      expect(comparand, isNotNull);
      expect(comparand!['removed_at'], '2026-03-08T00:00:05.000Z');

      // A fresh add (removed_at null) REPLACEs the tombstone → visible again.
      await dbInsertReaction(db, reactionRow(id: 'r-readd', emoji: '🔥'));
      final visible = await dbLoadReactionsForMessage(db, 'msg-1');
      expect(visible, hasLength(1));
      expect(visible.single['emoji'], '🔥');
      expect(visible.single['removed_at'], isNull);
    });

    testWidgets('082 tombstone is hard-removed by bulk message cleanup (no leak)',
        (tester) async {
      await dbInsertReaction(db, reactionRow(id: 'r-add'));
      await dbDeleteReaction(db, 'msg-1', 'peer-1',
          removedAtTimestamp: '2026-03-08T00:00:05.000Z');

      final removed = await dbDeleteReactionsForMessage(db, 'msg-1');
      expect(removed, 1);
      expect(await db.query('message_reactions'), isEmpty);
    });

    testWidgets('081 buffer: dedup, message lookup, claim-delete, cap, TTL',
        (tester) async {
      Map<String, Object?> bufRow({
        required String id,
        String messageId = 'm-1',
        String received = '2026-03-08T00:00:00.000Z',
      }) => {
            'id': id,
            'group_id': 'g-1',
            'message_id': messageId,
            'sender_peer_id': 'peer-1',
            'transport_peer_id': 't-1',
            'sender_device_id': 'd-1',
            'sender_public_key': 'pk-1',
            'reaction_json': '{"id":"$id"}',
            'received_at': received,
            'created_at': received,
            'updated_at': received,
          };

      // Dedup by id (PK upsert).
      await dbUpsertGroupPendingReaction(db, bufRow(id: 'rx-1'));
      await dbUpsertGroupPendingReaction(
          db, bufRow(id: 'rx-1', received: '2026-03-08T00:00:09.000Z'));
      expect(await dbLoadGroupPendingReactions(db), hasLength(1));

      // Lookup by (group, message).
      await dbUpsertGroupPendingReaction(db, bufRow(id: 'rx-2', messageId: 'm-2'));
      final forM1 = await dbLoadGroupPendingReactionsForMessage(
          db, groupId: 'g-1', messageId: 'm-1');
      expect(forM1.map((r) => r['id']), ['rx-1']);

      // Atomic claim-delete (exactly-once).
      expect(await dbDeleteGroupPendingReaction(db, 'rx-1'), 1);
      expect(await dbDeleteGroupPendingReaction(db, 'rx-1'), 0);

      // Per-group cap, oldest-first.
      for (var i = 0; i < 4; i++) {
        await dbUpsertGroupPendingReaction(db,
            bufRow(id: 'cap-$i', messageId: 'mc-$i', received: '2026-03-08T00:00:0$i.000Z'));
      }
      await dbPruneGroupPendingReactions(db, 'g-1', maxRows: 2);
      final afterCap = await dbLoadGroupPendingReactionsForMessage(
          db, groupId: 'g-1', messageId: 'mc-3');
      expect(afterCap, hasLength(1)); // newest survived

      // TTL.
      await dbDeleteExpiredGroupPendingReactions(db,
          olderThanIso: '2026-03-09T00:00:00.000Z');
      expect(await dbLoadGroupPendingReactions(db), isEmpty);
    });
  });
}
