@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/group_exit_diagnostics_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/104_group_exit_diagnostics.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/data/repositories/group_exit_diagnostic_repository_impl.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/settings/presentation/widgets/group_exit_diagnostics_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PB266-15 release SQLCipher diagnostic survives database reopen and Settings remount',
    (tester) async {
      expect(
        kDebugMode,
        isFalse,
        reason: 'This proof must run with --release.',
      );
      expect(currentIdentityDatabaseVersion, 109);

      final temp = await Directory.systemTemp.createTemp(
        'group_exit_release_diagnostics_',
      );
      final upgradePath = p.join(temp.path, 'upgrade.db');
      final freshPath = p.join(temp.path, 'fresh.db');
      const password = 'plan-266-release-sqlcipher-password';
      const hostileGroup =
          'group-hostile-/private/key/path-secret-peer-12D3KooWForbidden';
      const hostileIntent = 'intent-hostile-private-stack-secret';
      sqlcipher.Database? db;
      try {
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 103,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 103);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'group_exit_diagnostics'",
          ),
          isEmpty,
        );
        await db.insert('group_exit_intents', <String, Object?>{
          'group_id': hostileGroup,
          'intent_id': hostileIntent,
          'self_peer_id': 'peer-self',
          'self_joined_at': '2026-07-21T09:01:00.000Z',
          'state': 'queued',
          'pending_broadcast_id': 'pending-proof',
          'source_event_id': null,
          'event_at': null,
          'revision': 0,
          'last_error_code': null,
          'created_at': '2026-07-21T09:02:00.000Z',
          'updated_at': '2026-07-21T09:02:00.000Z',
        });
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 109);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(await db.query('group_exit_diagnostics'), isEmpty);
        expect(await db.query('group_exit_intents'), hasLength(1));
        final migration = productionUpgradeMigrations.singleWhere(
          (entry) => entry.version == 104,
        );
        expect(migration.name, '104_group_exit_diagnostics');
        expect(migration.run, same(runGroupExitDiagnosticsMigration));
        await migration.run(db);
        await migration.run(db);

        late final GroupExitDiagnosticRepositoryImpl repository;
        repository = GroupExitDiagnosticRepositoryImpl(
          dbAppendOutcome: (rows) =>
              dbAppendGroupExitDiagnosticOutcome(db!, rows),
          dbLoadNewest: () => dbLoadNewestGroupExitDiagnostics(db!),
          dbLoadForAction: ({required groupRef, required intentRef}) =>
              dbLoadGroupExitDiagnosticsForAction(
                db!,
                groupRef: groupRef,
                intentRef: intentRef,
              ),
          dbClear: () => dbClearGroupExitDiagnostics(db!),
        );
        await repository.appendOutcome(<GroupExitDiagnostic>[
          GroupExitDiagnostic.create(
            occurredAt: DateTime.utc(2026, 7, 21, 9, 3, 0, 123, 456),
            groupId: hostileGroup,
            intentId: hostileIntent,
            kind: GroupExitDiagnosticKind.voluntary,
            severity: GroupExitDiagnosticSeverity.failure,
            phase: GroupExitDiagnosticPhase.native,
            publicCode: GroupExitDiagnosticPublicCode.ex04,
            reason: GroupExitDiagnosticReason.nodeNotInitialized,
          ),
        ]);
        final storedJson = jsonEncode(await db.query('group_exit_diagnostics'));
        expect(storedJson, isNot(contains(hostileGroup)));
        expect(storedJson, isNot(contains(hostileIntent)));
        expect(storedJson, isNot(contains('private')));
        expect(storedJson, isNot(contains('stack')));
        await db.close();
        db = null;

        await expectLater(() async {
          final wrong = await sqlcipher.openDatabase(
            upgradePath,
            password: 'wrong-plan-266-password',
            singleInstance: false,
          );
          try {
            await wrong.query('group_exit_diagnostics');
          } finally {
            await wrong.close();
          }
        }(), throwsA(anything));
        await expectLater(
          sqlcipher.openDatabase(
            upgradePath,
            password: password,
            version: 103,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await repository.loadNewest(), hasLength(1));
        expect(
          (await repository.loadForAction(
            groupId: hostileGroup,
            intentId: hostileIntent,
          )).single.publicCode,
          GroupExitDiagnosticPublicCode.ex04,
        );

        Future<void> pumpUntilFound(Finder finder) async {
          for (var attempt = 0; attempt < 30; attempt += 1) {
            await tester.pump(const Duration(milliseconds: 100));
            if (finder.evaluate().isNotEmpty) return;
          }
          fail('Timed out waiting for the PB266 release-proof widget.');
        }

        Future<void> pumpSettings() async {
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: SettingsScreen(
                username: 'Release proof',
                showNavigationBar: false,
                onSwitchView: (_) {},
                activeTab: 'settings',
                groupExitDiagnosticsSection: GroupExitDiagnosticsSection(
                  repository: repository,
                  backgroundPreference: BackgroundPreference.defaultBackground,
                ),
              ),
            ),
          );
          final row = find.byKey(
            const ValueKey('group-exit-diagnostics-open-row'),
          );
          await pumpUntilFound(row);
          await tester.ensureVisible(row);
          await tester.tap(row);
          final code = find.textContaining('EX04');
          await pumpUntilFound(code);
          expect(code, findsOneWidget);
          expect(find.textContaining(hostileGroup), findsNothing);
          expect(find.textContaining(hostileIntent), findsNothing);
        }

        await pumpSettings();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await pumpSettings();

        final fresh = await sqlcipher.openDatabase(
          freshPath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        try {
          expect(await _userVersion(fresh), 109);
          expect(await _cipherVersion(fresh), isNotEmpty);
          expect(await fresh.query('group_exit_diagnostics'), isEmpty);
          await migration.run(fresh);
          expect(await fresh.query('group_exit_diagnostics'), isEmpty);
        } finally {
          await fresh.close();
        }
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );
}
