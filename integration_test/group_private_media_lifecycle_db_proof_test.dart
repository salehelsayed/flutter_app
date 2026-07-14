@Tags(['device'])
library;

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/101_group_private_media_lifecycle.dart';
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

Map<String, Object?> _directPredecessor(String id) => <String, Object?>{
  'id': id,
  'contact_peer_id': 'contact-1',
  'sender_peer_id': 'contact-1',
  'text': 'direct predecessor',
  'timestamp': '2026-07-12T00:00:00.000Z',
  'status': 'delivered',
  'is_incoming': 1,
  'created_at': '2026-07-12T00:00:00.000Z',
  'is_forwarded': 1,
  'private_media_policy_version': 1,
  'private_media_mode': 'view_once',
  'private_media_state': 'available',
  'private_media_received_at_ms': 1000,
  'private_media_clock_high_water_ms': 1000,
};

Map<String, Object?> _groupMessage(String id) => <String, Object?>{
  'id': id,
  'group_id': 'group-1',
  'sender_peer_id': 'group-peer',
  'sender_username': 'Group peer',
  'text': 'group predecessor',
  'timestamp': '2026-07-12T00:00:00.000Z',
  'key_generation': 3,
  'status': 'delivered',
  'is_incoming': 1,
  'created_at': '2026-07-12T00:00:00.000Z',
  'is_forwarded': 1,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'GPL-01D real SQLCipher allocated vNEXT preserves legacy private state reopen and full chain',
    (_) async {
      final tempDir = await Directory.systemTemp.createTemp(
        'group_private_v101_',
      );
      final upgradePath = p.join(tempDir.path, 'upgrade.db');
      final freshPath = p.join(tempDir.path, 'fresh.db');
      const password = 'plan-238-v101-correct-password';
      sqlcipher.Database? db;
      try {
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
        expect(currentIdentityDatabaseVersion, 101);
        expect(
          (await db.rawQuery(
            'PRAGMA cipher_version',
          )).single.values.single.toString(),
          isNotEmpty,
        );

        const sharedParent = 'shared-parent';
        await db.insert('messages', _directPredecessor(sharedParent));
        await db.insert('group_messages', _groupMessage(sharedParent));
        for (final fixture in const [
          ('direct-att', sharedParent, 'direct'),
          ('group-att', sharedParent, 'group'),
          ('unresolved-att', 'missing-parent', 'unresolved'),
        ]) {
          await db.insert('media_attachments', {
            'id': fixture.$1,
            'message_id': fixture.$2,
            'mime': 'image/jpeg',
            'size': 42,
            'media_type': 'image',
            'local_path': '/media/${fixture.$1}.jpg',
            'download_status': 'done',
            'created_at': '2026-07-12T00:00:01.000Z',
            'owner_lane': fixture.$3,
            'is_bookmarked': 1,
            'last_playback_position_ms': 321,
          });
        }

        final directSchemaBefore = (await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='messages'",
        )).single['sql'];
        final directBefore = (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: [sharedParent],
        )).single;
        final attachmentsBefore = await db.query(
          'media_attachments',
          orderBy: 'id',
        );
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 101,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 101);

        final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
        final byName = {for (final row in columns) row['name'] as String: row};
        expect(byName['media_policy_version']!['notnull'], 1);
        expect(byName['media_policy_version']!['dflt_value'], '0');
        expect(byName['media_lifecycle']!['notnull'], 1);
        expect(byName['media_lifecycle']!['dflt_value'], "'standard'");
        expect(byName['media_duration_seconds']!['notnull'], 0);
        expect(byName['media_protected']!['notnull'], 1);
        expect(byName['media_protected']!['dflt_value'], '0');
        expect(byName['media_cleanup_pending']!['notnull'], 1);
        expect(byName['media_cleanup_pending']!['dflt_value'], '0');
        expect(
          await _indexColumns(db, 'idx_group_messages_private_media_expiry'),
          ['media_expires_at'],
        );

        final entry = productionUpgradeMigrations.singleWhere(
          (candidate) => candidate.version == 101,
        );
        expect(entry.name, '101_group_private_media_lifecycle');
        expect(entry.run, same(runGroupPrivateMediaLifecycleMigration));
        await entry.run(db);
        await entry.run(db);

        final legacy = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: [sharedParent],
        )).single;
        expect(legacy['is_forwarded'], 1);
        expect(legacy['media_policy_version'], 0);
        expect(legacy['media_lifecycle'], 'standard');
        expect(legacy['media_duration_seconds'], isNull);
        expect(legacy['media_protected'], 0);
        expect(legacy['media_received_at'], isNull);
        expect(legacy['media_expires_at'], isNull);
        expect(legacy['media_last_checked_at'], isNull);
        expect(legacy['media_consumed_at'], isNull);
        expect(legacy['media_expired_at'], isNull);
        expect(legacy['media_cleanup_pending'], 0);
        expect(
          (await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='messages'",
          )).single['sql'],
          directSchemaBefore,
        );
        expect(
          (await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: [sharedParent],
          )).single,
          directBefore,
        );
        expect(
          await db.query('media_attachments', orderBy: 'id'),
          attachmentsBefore,
        );

        await db.update(
          'group_messages',
          {
            'media_policy_version': 1,
            'media_lifecycle': 'disappearing',
            'media_duration_seconds': 86400,
            'media_protected': 1,
            'media_received_at': 1000,
            'media_expires_at': 86401000,
            'media_last_checked_at': 4000,
            'media_consumed_at': null,
            'media_expired_at': null,
            'media_cleanup_pending': 0,
          },
          where: 'id = ?',
          whereArgs: [sharedParent],
        );
        await db.insert('group_messages', {
          ..._groupMessage('view-once-consumed'),
          'media_policy_version': 1,
          'media_lifecycle': 'view_once',
          'media_duration_seconds': null,
          'media_protected': 1,
          'media_received_at': 2000,
          'media_expires_at': null,
          'media_last_checked_at': 3000,
          'media_consumed_at': 4000,
          'media_expired_at': null,
          'media_cleanup_pending': 1,
        });
        await db.close();
        db = null;

        await expectLater(() async {
          final wrong = await sqlcipher.openDatabase(
            upgradePath,
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
            upgradePath,
            password: password,
            version: 100,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 101,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        final reopened = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: [sharedParent],
        )).single;
        expect(reopened['media_policy_version'], 1);
        expect(reopened['media_lifecycle'], 'disappearing');
        expect(reopened['media_duration_seconds'], 86400);
        expect(reopened['media_protected'], 1);
        expect(reopened['media_received_at'], 1000);
        expect(reopened['media_expires_at'], 86401000);
        expect(reopened['media_last_checked_at'], 4000);
        expect(reopened['media_consumed_at'], isNull);
        expect(reopened['media_expired_at'], isNull);
        expect(reopened['media_cleanup_pending'], 0);
        final consumed = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['view-once-consumed'],
        )).single;
        expect(consumed['media_lifecycle'], 'view_once');
        expect(consumed['media_consumed_at'], 4000);
        expect(consumed['media_cleanup_pending'], 1);
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          freshPath,
          password: password,
          version: 101,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 101);
        expect(
          productionCreateMigrations.where(
            (candidate) => candidate.version == 101,
          ),
          hasLength(1),
        );
        expect(
          await _indexColumns(db, 'idx_group_messages_private_media_expiry'),
          ['media_expires_at'],
        );
        await db.insert('group_messages', _groupMessage('fresh-default'));
        final fresh = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['fresh-default'],
        )).single;
        expect(fresh['media_policy_version'], 0);
        expect(fresh['media_lifecycle'], 'standard');
        expect(fresh['media_duration_seconds'], isNull);
        expect(fresh['media_protected'], 0);
        expect(fresh['media_cleanup_pending'], 0);
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    },
  );
}
