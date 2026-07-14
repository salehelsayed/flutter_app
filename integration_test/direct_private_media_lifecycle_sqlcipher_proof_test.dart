import 'dart:io';

import 'package:flutter_app/core/database/migrations/100_direct_private_media_lifecycle.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

Future<int> _userVersion(sqlcipher.Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.single.values.single as num).toInt();
}

Future<List<String>> _indexColumns(
  sqlcipher.Database db,
  String indexName,
) async {
  final rows = await db.rawQuery('PRAGMA index_info($indexName)');
  final ordered = [...rows]
    ..sort(
      (a, b) =>
          (a['seqno'] as num).toInt().compareTo((b['seqno'] as num).toInt()),
    );
  return ordered.map((row) => row['name'] as String).toList();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real SQLCipher fresh and 99 to 100 lifecycle migration is durable and one-way',
    (_) async {
      final tempDir = await Directory.systemTemp.createTemp(
        'direct_private_v100_',
      );
      final upgradePath = p.join(tempDir.path, 'upgrade.db');
      final freshPath = p.join(tempDir.path, 'fresh.db');
      const password = 'plan-234-v100-correct-password';
      sqlcipher.Database? db;
      try {
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 99,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 99);
        expect(
          (await db.rawQuery(
            'PRAGMA cipher_version',
          )).single.values.single.toString(),
          isNotEmpty,
        );

        await db.insert('messages', {
          'id': 'shared-parent',
          'contact_peer_id': 'contact-1',
          'sender_peer_id': 'contact-1',
          'text': 'direct predecessor',
          'timestamp': '2026-07-11T00:00:00.000Z',
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-07-11T00:00:00.000Z',
          'is_forwarded': 1,
        });
        await db.insert('group_messages', {
          'id': 'shared-parent',
          'group_id': 'group-1',
          'sender_peer_id': 'group-peer',
          'sender_username': 'Group peer',
          'text': 'group predecessor',
          'timestamp': '2026-07-11T00:00:00.000Z',
          'key_generation': 3,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-07-11T00:00:00.000Z',
          'is_forwarded': 1,
        });
        for (final fixture in const [
          ('direct-att', 'direct'),
          ('group-att', 'group'),
          ('unresolved-att', 'unresolved'),
        ]) {
          await db.insert('media_attachments', {
            'id': fixture.$1,
            'message_id': fixture.$2 == 'unresolved'
                ? 'missing-parent'
                : 'shared-parent',
            'mime': 'image/jpeg',
            'size': 42,
            'media_type': 'image',
            'local_path': '/media/${fixture.$1}.jpg',
            'download_status': 'done',
            'created_at': '2026-07-11T00:00:01.000Z',
            'owner_lane': fixture.$2,
            'is_bookmarked': 1,
            'last_playback_position_ms': 321,
          });
        }
        await db.insert('group_media_deletion_journal', {
          'attachment_id': 'journal-att',
          'operation_id': 'operation-1',
          'message_id': 'shared-parent',
          'group_id': 'group-1',
          'operation_intent': 'delete_for_me',
          'normalized_mime': 'image/jpeg',
          'canonical_relative_path': 'media/group-1/journal-att.jpg',
          'created_at': '2026-07-11T00:00:02.000Z',
        });
        final groupSchemaBefore = (await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='group_messages'",
        )).single['sql'];
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 100,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 100);
        final columns = await db.rawQuery('PRAGMA table_info(messages)');
        final byName = {for (final row in columns) row['name'] as String: row};
        expect(byName['private_media_policy_version']!['notnull'], 1);
        expect(byName['private_media_policy_version']!['dflt_value'], '0');
        expect(byName['private_media_mode']!['dflt_value'], "'ordinary'");
        expect(byName['private_media_duration_seconds']!['notnull'], 0);
        expect(byName['private_media_state']!['dflt_value'], "'none'");
        expect(await _indexColumns(db, 'idx_messages_private_media_expiry'), [
          'private_media_expires_at_ms',
        ]);

        final entry = productionUpgradeMigrations.singleWhere(
          (candidate) => candidate.version == 100,
        );
        expect(entry.name, '100_direct_private_media_lifecycle');
        expect(entry.run, same(runDirectPrivateMediaLifecycleMigration));
        await entry.run(db);
        await entry.run(db);

        final direct = (await db.query('messages')).single;
        expect(direct['is_forwarded'], 1);
        expect(direct['private_media_policy_version'], 0);
        expect(direct['private_media_mode'], 'ordinary');
        expect(direct['private_media_state'], 'none');
        expect((await db.query('group_messages')).single['is_forwarded'], 1);
        expect(
          (await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='group_messages'",
          )).single['sql'],
          groupSchemaBefore,
        );
        final media = await db.query('media_attachments', orderBy: 'id');
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
        expect(await db.query('group_media_deletion_journal'), hasLength(1));

        await db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'disappearing',
            'private_media_duration_seconds': 86400,
            'private_media_state': 'viewing',
            'private_media_received_at_ms': 1000,
            'private_media_expires_at_ms': 86401000,
            'private_media_revealed_at_ms': 2000,
            'private_media_terminal_at_ms': 3000,
            'private_media_clock_high_water_ms': 4000,
          },
          where: 'id = ?',
          whereArgs: ['shared-parent'],
        );
        await db.close();
        db = null;

        await expectLater(() async {
          final wrong = await sqlcipher.openDatabase(
            upgradePath,
            password: 'wrong-password',
            singleInstance: false,
          );
          try {
            await wrong.query('messages');
          } finally {
            await wrong.close();
          }
        }(), throwsA(anything));
        await expectLater(
          sqlcipher.openDatabase(
            upgradePath,
            password: password,
            version: 99,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 100,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        final reopened = (await db.query('messages')).single;
        expect(reopened['private_media_mode'], 'disappearing');
        expect(reopened['private_media_duration_seconds'], 86400);
        expect(reopened['private_media_state'], 'viewing');
        expect(reopened['private_media_received_at_ms'], 1000);
        expect(reopened['private_media_expires_at_ms'], 86401000);
        expect(reopened['private_media_revealed_at_ms'], 2000);
        expect(reopened['private_media_terminal_at_ms'], 3000);
        expect(reopened['private_media_clock_high_water_ms'], 4000);
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          freshPath,
          password: password,
          version: 100,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 100);
        expect(await _indexColumns(db, 'idx_messages_private_media_expiry'), [
          'private_media_expires_at_ms',
        ]);
        await db.insert('messages', {
          'id': 'fresh-default',
          'contact_peer_id': 'contact-1',
          'sender_peer_id': 'contact-1',
          'text': 'fresh',
          'timestamp': '2026-07-11T00:00:00.000Z',
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-07-11T00:00:00.000Z',
        });
        final fresh = (await db.query('messages')).single;
        expect(fresh['private_media_policy_version'], 0);
        expect(fresh['private_media_mode'], 'ordinary');
        expect(fresh['private_media_state'], 'none');
        expect(
          productionCreateMigrations.any((entry) => entry.version == 101),
          isFalse,
        );
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    },
  );
}
