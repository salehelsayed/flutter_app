@Tags(['device'])
library;

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/102_groups_self_removed_at.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

Future<int> _userVersion(sqlcipher.Database db) async =>
    ((await db.rawQuery('PRAGMA user_version')).single.values.single as num)
        .toInt();

Map<String, Object?> _withoutSelfRemovedAt(Map<String, Object?> row) =>
    Map<String, Object?>.from(row)..remove('self_removed_at');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'GSR-102D real SQLCipher v101 to v102 preserves removed-shell authority across reopen',
    (_) async {
      final temp = await Directory.systemTemp.createTemp(
        'group_self_removed_v102_',
      );
      final upgradePath = p.join(temp.path, 'upgrade.db');
      final freshPath = p.join(temp.path, 'fresh.db');
      const password = 'plan-263-v102-correct-password';
      sqlcipher.Database? db;
      try {
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
        expect(
          (await db.rawQuery(
            'PRAGMA cipher_version',
          )).single.values.single.toString(),
          isNotEmpty,
        );
        await db.insert('identity', {
          'id': 1,
          'peer_id': 'peer-self',
          'public_key': '',
          'private_key': null,
          'mnemonic12': null,
          'username': 'Self',
          'created_at': '2026-07-20T12:00:00.000Z',
          'updated_at': '2026-07-20T12:00:00.000Z',
        });
        await db.insert('groups', {
          'id': 'removed-shell',
          'name': 'Removed shell',
          'type': 'chat',
          'topic_name': 'topic-removed-shell',
          'created_at': '2026-07-20T12:00:00.000Z',
          'created_by': 'peer-admin',
          'my_role': 'member',
          'last_membership_event_at': '2026-07-20T13:00:00.000Z',
        });
        await db.insert('groups', {
          'id': 'active-member-control',
          'name': 'Active member control',
          'type': 'chat',
          'topic_name': 'topic-active-member-control',
          'created_at': '2026-07-20T12:10:00.000Z',
          'created_by': 'peer-admin',
          'my_role': 'member',
          'last_membership_event_at': '2026-07-20T13:10:00.000Z',
        });
        await db.insert('group_members', {
          'group_id': 'active-member-control',
          'peer_id': 'peer-self',
          'username': 'Self',
          'role': 'writer',
          'public_key': 'pk-self',
          'ml_kem_public_key': 'mlkem-self',
          'joined_at': '2026-07-20T12:10:00.000Z',
        });
        await db.insert('groups', {
          'id': 'keyed-control',
          'name': 'Keyed control',
          'type': 'chat',
          'topic_name': 'topic-keyed-control',
          'created_at': '2026-07-20T12:20:00.000Z',
          'created_by': 'peer-admin',
          'my_role': 'member',
          'last_membership_event_at': '2026-07-20T13:20:00.000Z',
        });
        await db.insert('group_keys', {
          'group_id': 'keyed-control',
          'key_generation': 7,
          'encrypted_key': 'encrypted-key-control',
          'created_at': '2026-07-20T12:20:00.000Z',
        });
        final excludedGroupsBefore = await db.query(
          'groups',
          where: 'id IN (?, ?)',
          whereArgs: ['active-member-control', 'keyed-control'],
          orderBy: 'id ASC',
        );
        final excludedMembersBefore = await db.query(
          'group_members',
          where: 'group_id = ?',
          whereArgs: ['active-member-control'],
        );
        final excludedKeysBefore = await db.query(
          'group_keys',
          where: 'group_id = ?',
          whereArgs: ['keyed-control'],
        );
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 102,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(currentIdentityDatabaseVersion, 113);
        expect(await _userVersion(db), 102);
        final entry = productionUpgradeMigrations.singleWhere(
          (candidate) => candidate.version == 102,
        );
        expect(entry.name, '102_groups_self_removed_at');
        expect(entry.run, same(runGroupsSelfRemovedAtMigration));
        expect(
          (await db.query(
            'groups',
            where: 'id = ?',
            whereArgs: ['removed-shell'],
          )).single['self_removed_at'],
          '2026-07-20T13:00:00.000Z',
        );
        final excludedGroupsAfter = await db.query(
          'groups',
          where: 'id IN (?, ?)',
          whereArgs: ['active-member-control', 'keyed-control'],
          orderBy: 'id ASC',
        );
        expect(
          excludedGroupsAfter.map(_withoutSelfRemovedAt).toList(),
          excludedGroupsBefore,
        );
        expect(
          excludedGroupsAfter.map((row) => row['self_removed_at']),
          everyElement(isNull),
        );
        expect(
          await db.query(
            'group_members',
            where: 'group_id = ?',
            whereArgs: ['active-member-control'],
          ),
          excludedMembersBefore,
        );
        expect(
          await db.query(
            'group_keys',
            where: 'group_id = ?',
            whereArgs: ['keyed-control'],
          ),
          excludedKeysBefore,
        );
        await entry.run(db);
        await entry.run(db);
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 102,
          singleInstance: false,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(
          (await db.query(
            'groups',
            where: 'id = ?',
            whereArgs: ['removed-shell'],
          )).single['self_removed_at'],
          '2026-07-20T13:00:00.000Z',
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
            await wrong.query('groups');
          } finally {
            await wrong.close();
          }
        }(), throwsA(anything));
        await expectLater(
          sqlcipher.openDatabase(
            upgradePath,
            password: password,
            version: 101,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        // Deliberately advance this existing encrypted proof through the
        // current production registry while retaining its historical v102
        // boundary assertions above.
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 112);
        expect(
          (await db.query(
            'groups',
            where: 'id = ?',
            whereArgs: ['removed-shell'],
          )).single['self_removed_at'],
          '2026-07-20T13:00:00.000Z',
        );
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'direct_media_blob_custody'",
          ),
          hasLength(1),
        );
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          freshPath,
          password: password,
          version: 102,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 102);
        final columns = await db.rawQuery('PRAGMA table_info(groups)');
        final marker = columns.singleWhere(
          (column) => column['name'] == 'self_removed_at',
        );
        expect(marker['type'], 'TEXT');
        expect(marker['notnull'], 0);
        expect(marker['dflt_value'], isNull);
      } finally {
        await db?.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
