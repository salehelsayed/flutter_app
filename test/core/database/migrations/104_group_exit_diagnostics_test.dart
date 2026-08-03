// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/104_group_exit_diagnostics.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _at = '2026-07-21T09:03:00.000Z';
const _groupRef = 'abcdef012345';
const _intentRef = 'abcdef0123456789abcdef01';

Map<String, Object?> _diagnostic({
  String occurredAt = _at,
  String groupRef = _groupRef,
  String? intentRef = _intentRef,
  String exitKind = 'voluntary',
  String severity = 'failure',
  String phase = 'native',
  String publicCode = 'EX04',
  String reasonCode = 'node_not_initialized',
}) => <String, Object?>{
  'occurred_at': occurredAt,
  'group_ref': groupRef,
  'intent_ref': intentRef,
  'exit_kind': exitKind,
  'severity': severity,
  'phase': phase,
  'public_code': publicCode,
  'reason_code': reasonCode,
};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'PB266-05 v104 diagnostic schema constraints registry and empty rerun are exact',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'group_exit_diagnostics_v104_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final path = '${tempDir.path}/identity.db';

      final predecessor = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 103,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(() async {
        if (predecessor.isOpen) await predecessor.close();
      });
      await predecessor.insert('groups', <String, Object?>{
        'id': 'legacy-group',
        'name': 'Legacy Group',
        'type': 'chat',
        'topic_name': 'topic-legacy',
        'created_at': _at,
        'created_by': 'peer-admin',
        'my_role': 'member',
      });
      await predecessor.insert('group_exit_intents', <String, Object?>{
        'group_id': 'legacy-group',
        'intent_id': 'legacy-intent',
        'self_peer_id': 'peer-self',
        'self_joined_at': _at,
        'state': 'queued',
        'pending_broadcast_id': 'legacy-pending',
        'source_event_id': null,
        'event_at': null,
        'revision': 0,
        'last_error_code': null,
        'created_at': _at,
        'updated_at': _at,
      });
      final groupBefore = await predecessor.query('groups');
      final intentBefore = await predecessor.query('group_exit_intents');
      await predecessor.close();

      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 104,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });

      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        104,
      );
      expect(currentIdentityDatabaseVersion, 106);
      for (final registry in <List<ProductionMigrationEntry>>[
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        expect(registry.where((entry) => entry.version == 104), hasLength(1));
        expect(registry.last.version, 106);
        expect(registry.last.name, '106_group_notification_display_outbox');
        expect(registry[registry.length - 2].version, 105);
        expect(registry[registry.length - 3].version, 104);
      }

      expect(await db.query('group_exit_diagnostics'), isEmpty);
      expect(await db.query('groups'), groupBefore);
      expect(await db.query('group_exit_intents'), intentBefore);

      await runGroupExitDiagnosticsMigration(db);
      await runGroupExitDiagnosticsMigration(db);
      expect(await db.query('group_exit_diagnostics'), isEmpty);

      final columns = await db.rawQuery(
        'PRAGMA table_info(group_exit_diagnostics)',
      );
      expect(columns.map((row) => row['name']), <String>[
        'id',
        'occurred_at',
        'group_ref',
        'intent_ref',
        'exit_kind',
        'severity',
        'phase',
        'public_code',
        'reason_code',
      ]);
      expect(
        await db.rawQuery('PRAGMA foreign_key_list(group_exit_diagnostics)'),
        isEmpty,
      );
      final tableSql =
          (await db.rawQuery(
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                const ['group_exit_diagnostics'],
              )).single['sql']
              as String;
      expect(tableSql.toLowerCase(), isNot(contains('autoincrement')));
      expect(tableSql.toLowerCase(), isNot(contains('payload')));
      expect(tableSql.toLowerCase(), isNot(contains('detail')));

      await db.insert('group_exit_diagnostics', _diagnostic());
      await db.insert(
        'group_exit_diagnostics',
        _diagnostic(
          groupRef: '012345abcdef',
          intentRef: null,
          exitKind: 'self_removed_shell',
          phase: 'authority',
          publicCode: 'EX01',
          reasonCode: 'authority_unavailable',
        ),
      );
      await db.insert(
        'group_exit_diagnostics',
        _diagnostic(
          groupRef: '123456abcdef',
          intentRef: null,
          exitKind: 'dissolved_shell',
          phase: 'local_delete',
          publicCode: 'EX10',
          reasonCode: 'terminal_shell_cleanup',
        ),
      );

      final invalidRows = <Map<String, Object?>>[
        _diagnostic(occurredAt: '2026-07-21T09:03:00.123456Z'),
        _diagnostic(occurredAt: '2026-07-21T09:03:00+00:00'),
        _diagnostic(occurredAt: '2026-02-30T09:03:00.000Z'),
        _diagnostic(groupRef: 'ABCDEF012345'),
        _diagnostic(intentRef: 'ABCDEF0123456789ABCDEF01'),
        _diagnostic(severity: 'warning'),
        _diagnostic(
          intentRef: null,
          publicCode: 'EX03',
          phase: 'notice',
          reasonCode: 'notice_prepare_failed',
        ),
        _diagnostic(exitKind: 'self_removed_shell'),
        _diagnostic(
          intentRef: null,
          publicCode: 'EX10',
          phase: 'local_delete',
          reasonCode: 'terminal_shell_cleanup',
        ),
        _diagnostic(
          publicCode: 'EX99',
          phase: 'local_delete',
          reasonCode: 'unexpected',
        ),
      ];
      for (final row in invalidRows) {
        await expectLater(
          db.insert('group_exit_diagnostics', row),
          throwsA(isA<DatabaseException>()),
        );
      }

      expect(await db.query('group_exit_diagnostics'), hasLength(3));
      final sequenceTable = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sqlite_sequence'",
      );
      if (sequenceTable.isNotEmpty) {
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_sequence WHERE name = ?",
            const ['group_exit_diagnostics'],
          ),
          isEmpty,
        );
      }
    },
  );
}
