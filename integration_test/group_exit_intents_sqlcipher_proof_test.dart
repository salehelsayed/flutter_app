@Tags(['device'])
library;

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/103_group_exit_intents.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

Future<int> _userVersion(sqlcipher.Database db) async =>
    ((await db.rawQuery('PRAGMA user_version')).single.values.single as num)
        .toInt();

Future<String> _cipherVersion(sqlcipher.Database db) async =>
    (await db.rawQuery(
      'PRAGMA cipher_version',
    )).single.values.single.toString();

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

Map<String, Object?> _queuedIntent({
  String groupId = 'group-upgrade',
  String intentId = 'intent-upgrade',
  String pendingBroadcastId = 'leave-outbox-upgrade',
}) => <String, Object?>{
  'group_id': groupId,
  'intent_id': intentId,
  'self_peer_id': 'peer-self',
  'self_joined_at': '2026-07-21T09:01:00.000Z',
  'state': 'queued',
  'pending_broadcast_id': pendingBroadcastId,
  'source_event_id': null,
  'event_at': null,
  'revision': 0,
  'last_error_code': null,
  'created_at': '2026-07-21T09:03:00.000Z',
  'updated_at': '2026-07-21T09:03:00.000Z',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PB264-05 real SQLCipher v102 to v103 survives reopen and rejects wrong key/downgrade',
    (_) async {
      final temp = await Directory.systemTemp.createTemp(
        'group_exit_intents_v103_',
      );
      final upgradePath = p.join(temp.path, 'upgrade.db');
      final freshPath = p.join(temp.path, 'fresh.db');
      const password = 'plan-264-v103-correct-password';
      sqlcipher.Database? db;
      try {
        // Build a literal encrypted v102 predecessor through the production
        // callback, with an active exact membership and a role row. Migration
        // 103 must never infer an exit intent from this legacy work.
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 102,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 102);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'group_exit_intents'",
          ),
          isEmpty,
        );
        await db.insert('identity', <String, Object?>{
          'id': 1,
          'peer_id': 'peer-self',
          'public_key': '',
          'private_key': null,
          'mnemonic12': null,
          'username': 'Self',
          'created_at': '2026-07-21T09:00:00.000Z',
          'updated_at': '2026-07-21T09:00:00.000Z',
        });
        await db.insert('groups', <String, Object?>{
          'id': 'group-upgrade',
          'name': 'Upgrade group',
          'type': 'chat',
          'topic_name': 'topic-group-upgrade',
          'created_at': '2026-07-21T09:00:00.000Z',
          'created_by': 'peer-admin',
          'my_role': 'member',
          'last_membership_event_at': '2026-07-21T09:02:00.000Z',
        });
        await db.insert('group_members', <String, Object?>{
          'group_id': 'group-upgrade',
          'peer_id': 'peer-self',
          'username': 'Self',
          'role': 'writer',
          'joined_at': '2026-07-21T09:01:00.000Z',
        });
        await db.insert('pending_group_broadcasts', <String, Object?>{
          'id': 'legacy-role-row',
          'group_id': 'group-upgrade',
          'kind': 'member_role_updated',
          'sys_text': '{"signed":true}',
          'recipient_peer_ids': '["peer-other"]',
          'event_at': '2026-07-21T09:02:00.000Z',
          'source_message_id': 'legacy-role-source',
          'created_at': '2026-07-21T09:02:00.000Z',
          'updated_at': '2026-07-21T09:02:00.000Z',
        });
        final legacyGroups = await db.query('groups');
        final legacyMembers = await db.query('group_members');
        final legacyBroadcasts = await db.query('pending_group_broadcasts');
        await db.close();
        db = null;

        // Exercise the actual encrypted production v102 -> v103 boundary.
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 103,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(currentIdentityDatabaseVersion, 117);
        expect(await _userVersion(db), 103);
        expect(await _cipherVersion(db), isNotEmpty);
        final entry = productionUpgradeMigrations.singleWhere(
          (candidate) => candidate.version == 103,
        );
        expect(entry.name, '103_group_exit_intents');
        expect(entry.run, same(runGroupExitIntentsMigration));
        expect(await db.query('group_exit_intents'), isEmpty);
        expect(await db.query('groups'), legacyGroups);
        expect(await db.query('group_members'), legacyMembers);
        expect(await db.query('pending_group_broadcasts'), legacyBroadcasts);

        final columns = await db.rawQuery(
          'PRAGMA table_info(group_exit_intents)',
        );
        expect(columns.map((row) => row['name']), <String>[
          'group_id',
          'intent_id',
          'self_peer_id',
          'self_joined_at',
          'state',
          'pending_broadcast_id',
          'source_event_id',
          'event_at',
          'revision',
          'last_error_code',
          'created_at',
          'updated_at',
        ]);
        expect(
          await _indexColumns(db, 'idx_group_exit_intents_state_updated'),
          <String>['state', 'updated_at'],
        );
        expect(
          await db.rawQuery('PRAGMA foreign_key_list(group_exit_intents)'),
          isEmpty,
        );

        // Rerun the actual registry function twice on the encrypted engine,
        // then prove its state-shape CHECK accepts only coherent rows.
        await entry.run(db);
        await entry.run(db);
        final queued = _queuedIntent();
        await db.insert('group_exit_intents', queued);
        await expectLater(
          db.insert(
            'group_exit_intents',
            _queuedIntent(
                groupId: 'invalid-queued',
                intentId: 'invalid-queued',
                pendingBroadcastId: 'invalid-queued',
              )
              ..['source_event_id'] = 'must-be-null'
              ..['event_at'] = '2026-07-21T09:04:00.000Z',
          ),
          throwsA(anything),
        );
        await expectLater(
          db.insert('group_exit_intents', <String, Object?>{
            ..._queuedIntent(
              groupId: 'invalid-later',
              intentId: 'invalid-later',
              pendingBroadcastId: 'invalid-later',
            ),
            'state': 'native_leave_pending',
            'source_event_id': 'source-without-time',
          }),
          throwsA(anything),
        );
        await db.close();
        db = null;

        // An encrypted database is neither plaintext nor downgrade-openable.
        await expectLater(() async {
          final wrong = await sqlcipher.openDatabase(
            upgradePath,
            password: 'wrong-password',
            singleInstance: false,
          );
          try {
            await wrong.query('group_exit_intents');
          } finally {
            await wrong.close();
          }
        }(), throwsA(anything));
        await expectLater(
          sqlcipher.openDatabase(
            upgradePath,
            password: password,
            version: 102,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        // Reopen through the current production registry after both refusals:
        // the historical v103 authority remains exact while this sentinel
        // deliberately advances its current-schema pin through v116.
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 117);
        expect(await _cipherVersion(db), isNotEmpty);
        expect((await db.query('group_exit_intents')).single, queued);
        expect(await db.query('groups'), legacyGroups);
        expect(await db.query('group_members'), legacyMembers);
        expect(await db.query('pending_group_broadcasts'), legacyBroadcasts);
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'direct_media_blob_custody'",
          ),
          hasLength(1),
        );
        await db.close();
        db = null;

        // Fresh-install production callback also materializes the exact v103
        // table and index on a separately encrypted database.
        db = await sqlcipher.openDatabase(
          freshPath,
          password: password,
          version: 103,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 103);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(await db.query('group_exit_intents'), isEmpty);
        expect(
          await _indexColumns(db, 'idx_group_exit_intents_state_updated'),
          <String>['state', 'updated_at'],
        );
        await db.insert('group_exit_intents', <String, Object?>{
          ..._queuedIntent(
            groupId: 'fresh-later',
            intentId: 'fresh-later',
            pendingBroadcastId: 'fresh-later',
          ),
          'state': 'cleanup_pending',
          'source_event_id': 'fresh-source',
          'event_at': '2026-07-21T10:00:00.000Z',
          'revision': 5,
        });
        expect(
          (await db.query('group_exit_intents')).single['state'],
          'cleanup_pending',
        );
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );
}
