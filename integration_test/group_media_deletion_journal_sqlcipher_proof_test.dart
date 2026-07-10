import 'dart:io';

import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

// 235 (TC-235-06D): host SQLite proves SQL shape and transaction causality
// only — this closes the REAL production `sqflite_sqlcipher` boundary for the
// v98 `group_media_deletion_journal`: encrypted create/upgrade through the
// shared production registries, journal durability and CHECK constraints,
// rerun/reopen behavior, wrong-password rejection, and the fail-closed
// v98 -> v97 no-downgrade floor.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'GMA-06D real SQLCipher v98 journal upgrade reopen and downgrade refusal',
    (_) async {
      final tempDir = await Directory.systemTemp.createTemp('journal_v98_');
      final path = p.join(tempDir.path, 'identity.db');
      const password = 'plan-235-correct-password';
      sqlcipher.Database? db;
      try {
        // ---- Complete v97 predecessor with representative direct/group/
        // unresolved attachment state and forwarded-marker data.
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 97,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        await db.insert('messages', {
          'id': 'direct-parent',
          'contact_peer_id': 'contact-1',
          'sender_peer_id': 'contact-1',
          'text': 'caption',
          'timestamp': '2026-07-10T00:00:00.000Z',
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-07-10T00:00:00.000Z',
          'is_forwarded': 1,
        });
        await db.insert('group_messages', {
          'id': 'group-parent',
          'group_id': 'group-1',
          'sender_peer_id': 'group-peer',
          'sender_username': 'Group peer',
          'text': 'group predecessor',
          'timestamp': '2026-07-10T00:00:00.000Z',
          'key_generation': 0,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-07-10T00:00:00.000Z',
        });
        for (final row in const [
          ('direct-att', 'direct-parent', 'direct'),
          ('group-att', 'group-parent', 'group'),
          ('unresolved-att', 'missing-parent', 'unresolved'),
        ]) {
          await db.insert('media_attachments', {
            'id': row.$1,
            'message_id': row.$2,
            'mime': 'image/jpeg',
            'size': 10,
            'media_type': 'image',
            'local_path': 'media/group-1/${row.$1}.jpg',
            'download_status': 'done',
            'created_at': '2026-07-10T00:00:01.000Z',
            'owner_lane': row.$3,
            'is_bookmarked': 1,
            'last_playback_position_ms': 321,
          });
        }
        await db.close();
        db = null;

        // ---- Real encrypted v97 -> v98 upgrade through the registries.
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 98,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        final cipherVersion = (await db.rawQuery(
          'PRAGMA cipher_version',
        )).first.values.first.toString();
        expect(cipherVersion, isNotEmpty);
        expect(
          (await db.rawQuery('PRAGMA user_version')).first.values.first,
          98,
        );
        expect(
          await db.query('group_media_deletion_journal'),
          isEmpty,
          reason: 'the upgrade backfills nothing — orphans stay unclassified',
        );

        // Journal durability + exact CHECK behavior on the real engine.
        await db.insert('group_media_deletion_journal', {
          'attachment_id': 'journal-att-1',
          'operation_id': 'op-1',
          'message_id': 'deleted-parent',
          'group_id': 'group-1',
          'operation_intent': 'delete_for_me',
          'normalized_mime': 'image/jpeg',
          'canonical_relative_path': 'media/group-1/journal-att-1.jpg',
          'created_at': '2026-07-10T00:00:02.000Z',
        });
        await expectLater(
          db.insert('group_media_deletion_journal', {
            'attachment_id': 'journal-att-bad',
            'operation_id': 'op-1',
            'message_id': 'deleted-parent',
            'group_id': 'group-1',
            'operation_intent': 'delete_for_everyone',
            'normalized_mime': 'image/jpeg',
            'canonical_relative_path': null,
            'created_at': '2026-07-10T00:00:03.000Z',
          }),
          throwsA(anything),
        );
        await expectLater(
          db.update(
            'group_media_deletion_journal',
            {'operation_intent': 'revoke'},
            where: 'attachment_id = ?',
            whereArgs: ['journal-att-1'],
          ),
          throwsA(anything),
        );

        // On-device idempotence of the ACTUAL registry entry.
        final actual098 = productionUpgradeMigrations.singleWhere(
          (entry) => entry.version == 98,
        );
        await actual098.run(db);
        await db.close();
        db = null;

        // ---- Wrong password fails; v98 -> v97 downgrade open fails closed.
        await expectLater(() async {
          final wrong = await sqlcipher.openDatabase(
            path,
            password: 'wrong-password',
            singleInstance: false,
          );
          try {
            await wrong.query('group_media_deletion_journal');
          } finally {
            await wrong.close();
          }
        }(), throwsA(anything));
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 97,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        // ---- Reopen at 98: the refused downgrade changed NOTHING — version,
        // schema, journal rows, and all predecessor artifacts survive.
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 98,
          singleInstance: false,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(
          (await db.rawQuery('PRAGMA user_version')).first.values.first,
          98,
        );
        final journal = await db.query('group_media_deletion_journal');
        expect(journal.single['attachment_id'], 'journal-att-1');
        expect(journal.single['operation_intent'], 'delete_for_me');
        final journalIndexes = (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND tbl_name='group_media_deletion_journal'",
        )).map((row) => row['name']).toSet();
        expect(
          journalIndexes,
          containsAll({
            'idx_group_media_deletion_journal_group_message',
            'idx_group_media_deletion_journal_operation',
          }),
        );
        expect((await db.query('messages')).single['is_forwarded'], 1);
        final media = await db.query('media_attachments', orderBy: 'id');
        expect(media, hasLength(3));
        expect(media.map((row) => row['owner_lane']).toSet(), {
          'direct',
          'group',
          'unresolved',
        });
        expect(media.every((row) => row['is_bookmarked'] == 1), isTrue);
        expect(
          media.every((row) => row['last_playback_position_ms'] == 321),
          isTrue,
        );
        final mediaIndexes = (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND tbl_name='media_attachments'",
        )).map((row) => row['name']);
        expect(mediaIndexes, contains('idx_media_attachments_owner_message'));
        expect(
          mediaIndexes,
          contains('idx_media_attachments_owner_bookmark_message'),
        );
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    },
  );
}
