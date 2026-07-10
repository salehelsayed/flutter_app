import 'dart:io';

import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

// 236 TC-236-06D: migration 099 (`group_messages.is_forwarded`) on REAL
// password-protected SQLCipher through the production registry callbacks and
// the production fail-closed downgrade guard. The populated COMPLETE v98
// predecessor (v96 media owner/viewer state + indexes, the v97 direct
// forwarded marker, plan 235's populated deletion journal + indexes, and
// non-default group-message reliability state) must survive the upgrade, the
// rejected wrong-password/downgrade opens, and the final correct v99 reopen.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'GMF-06D encrypted v99 rejects downgrade and preserves complete group predecessor',
    (_) async {
      final tempDir = await Directory.systemTemp.createTemp('forward_v99_');
      final path = p.join(tempDir.path, 'identity.db');
      const password = 'plan-236-correct-password';
      sqlcipher.Database? db;
      try {
        // ---- Populated COMPLETE v98 predecessor through production create.
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 98,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        await db.insert('messages', {
          'id': 'direct-forwarded',
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
          'id': 'group-msg-1',
          'group_id': 'group-1',
          'sender_peer_id': 'peer-g',
          'transport_peer_id': 'transport-peer-g',
          'sender_username': 'Group Sender',
          'text': 'group body',
          'timestamp': '2026-07-10T00:00:00.000Z',
          'last_send_attempt_at': '2026-07-10T00:00:05.000Z',
          'quoted_message_id': 'quoted-parent-1',
          'logical_delivery_id': 'logical-delivery-1',
          'key_generation': 4,
          'status': 'pending',
          'is_incoming': 0,
          'created_at': '2026-07-10T00:00:00.000Z',
          'wire_envelope': '{"groupId":"group-1","text":"group body"}',
          'inbox_stored': 1,
          'inbox_retry_payload': '{"groupId":"group-1","message":"envelope"}',
          'retry_attempt_count': 3,
          'next_eligible_at': 1783700000000,
        });
        for (final row in const [
          ('direct-att', 'direct-forwarded', 'direct'),
          ('group-att', 'group-msg-1', 'group'),
          ('unresolved-att', 'missing-parent', 'unresolved'),
        ]) {
          await db.insert('media_attachments', {
            'id': row.$1,
            'message_id': row.$2,
            'mime': 'image/jpeg',
            'size': 5,
            'media_type': 'image',
            'local_path': 'media/group-1/${row.$1}.jpg',
            'download_status': 'done',
            'created_at': '2026-07-10T00:00:01.000Z',
            'owner_lane': row.$3,
            'is_bookmarked': 1,
            'last_playback_position_ms': 123,
          });
        }
        for (final attachmentId in const ['journal-att-1', 'journal-att-2']) {
          await db.insert('group_media_deletion_journal', {
            'attachment_id': attachmentId,
            'operation_id': 'op-1',
            'message_id': 'deleted-parent',
            'group_id': 'group-1',
            'operation_intent': 'delete_for_me',
            'normalized_mime': 'image/jpeg',
            'canonical_relative_path': 'media/group-1/$attachmentId.jpg',
            'created_at': '2026-07-10T00:00:02.000Z',
          });
        }
        await db.close();
        db = null;

        // ---- Production upgrade v98 -> v99 on the encrypted database.
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 99,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        final cipherVersion = (await db.rawQuery(
          'PRAGMA cipher_version',
        )).first.values.first.toString();
        expect(cipherVersion, isNotEmpty, reason: 'real SQLCipher, not plain');

        // Actual registry entry reruns non-vacuously (idempotence).
        final actual099 = productionUpgradeMigrations.singleWhere(
          (entry) => entry.version == 99,
        );
        expect(actual099.name, '099_group_messages_is_forwarded');
        await actual099.run(db);

        // Default false for the pre-existing row; typed true persists; the
        // CHECK rejects non-0/1 on insert and update.
        expect(
          (await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: ['group-msg-1'],
          )).single['is_forwarded'],
          0,
        );
        await db.insert('group_messages', {
          'id': 'group-msg-forwarded',
          'group_id': 'group-1',
          'sender_peer_id': 'peer-g',
          'text': 'forwarded body',
          'timestamp': '2026-07-10T00:00:10.000Z',
          'status': 'sent',
          'is_incoming': 0,
          'created_at': '2026-07-10T00:00:10.000Z',
          'is_forwarded': 1,
        });
        await expectLater(
          db.insert('group_messages', {
            'id': 'group-msg-bad',
            'group_id': 'group-1',
            'sender_peer_id': 'peer-g',
            'text': 'bad',
            'timestamp': '2026-07-10T00:00:11.000Z',
            'status': 'sent',
            'is_incoming': 1,
            'created_at': '2026-07-10T00:00:11.000Z',
            'is_forwarded': 2,
          }),
          throwsA(anything),
        );
        await expectLater(
          db.update(
            'group_messages',
            {'is_forwarded': 9},
            where: 'id = ?',
            whereArgs: ['group-msg-1'],
          ),
          throwsA(anything),
        );
        await db.close();
        db = null;

        // ---- Fail closed: wrong password and a requested v99 -> v98
        // downgrade are both rejected.
        await expectLater(() async {
          final wrong = await sqlcipher.openDatabase(
            path,
            password: 'wrong-password',
            singleInstance: false,
          );
          try {
            await wrong.query('group_messages');
          } finally {
            await wrong.close();
          }
        }(), throwsA(anything));
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 98,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        // ---- Correct v99 reopen: version, marker, and EVERY predecessor
        // artifact unchanged.
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 99,
          singleInstance: false,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(
          (await db.rawQuery('PRAGMA user_version')).first.values.first,
          99,
        );
        final preserved = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['group-msg-1'],
        )).single;
        expect(preserved['is_forwarded'], 0);
        expect(preserved['quoted_message_id'], 'quoted-parent-1');
        expect(
          preserved['wire_envelope'],
          '{"groupId":"group-1","text":"group body"}',
        );
        expect(preserved['inbox_stored'], 1);
        expect(
          preserved['inbox_retry_payload'],
          '{"groupId":"group-1","message":"envelope"}',
        );
        expect(preserved['transport_peer_id'], 'transport-peer-g');
        expect(preserved['last_send_attempt_at'], '2026-07-10T00:00:05.000Z');
        expect(preserved['logical_delivery_id'], 'logical-delivery-1');
        expect(preserved['retry_attempt_count'], 3);
        expect(preserved['next_eligible_at'], 1783700000000);
        expect(
          (await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: ['group-msg-forwarded'],
          )).single['is_forwarded'],
          1,
          reason: 'the durable marker survives the reopen',
        );
        final groupMessageIndexes = (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND tbl_name='group_messages'",
        )).map((row) => row['name']).toSet();
        expect(
          groupMessageIndexes,
          containsAll({
            'idx_group_messages_group',
            'idx_group_messages_ts',
            'idx_group_messages_logical_delivery',
            'idx_group_messages_group_ts',
          }),
        );
        final journalRows = await db.query(
          'group_media_deletion_journal',
          orderBy: 'attachment_id',
        );
        expect(journalRows, hasLength(2));
        expect(journalRows.map((row) => row['attachment_id']), [
          'journal-att-1',
          'journal-att-2',
        ]);
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
        expect(
          (await db.query('messages')).single['is_forwarded'],
          1,
          reason: 'the v97 direct marker survives v99',
        );
        final media = await db.query('media_attachments', orderBy: 'id');
        expect(media, hasLength(3));
        expect(media.map((row) => row['owner_lane']).toSet(), {
          'direct',
          'group',
          'unresolved',
        });
        expect(media.every((row) => row['is_bookmarked'] == 1), isTrue);
        expect(
          media.every((row) => row['last_playback_position_ms'] == 123),
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
        await db.close();
        db = null;

        // ---- Fresh chain: a brand-new encrypted v99 install through the
        // production create registry ships the same constrained column.
        final freshPath = p.join(tempDir.path, 'fresh.db');
        db = await sqlcipher.openDatabase(
          freshPath,
          password: password,
          version: 99,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        await db.insert('group_messages', {
          'id': 'fresh-msg',
          'group_id': 'group-1',
          'sender_peer_id': 'peer-g',
          'text': 'fresh',
          'timestamp': '2026-07-10T00:00:00.000Z',
          'status': 'sent',
          'is_incoming': 1,
          'created_at': '2026-07-10T00:00:00.000Z',
        });
        expect(
          (await db.query('group_messages')).single['is_forwarded'],
          0,
        );
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    },
  );
}
