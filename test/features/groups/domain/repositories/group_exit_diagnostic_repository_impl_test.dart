import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/group_exit_diagnostics_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _at = '2026-07-21T09:03:00.000Z';

GroupExitDiagnosticRepositoryImpl _realRepository(Database db) =>
    GroupExitDiagnosticRepositoryImpl(
      dbAppendOutcome: (rows) => dbAppendGroupExitDiagnosticOutcome(db, rows),
      dbLoadNewest: () => dbLoadNewestGroupExitDiagnostics(db),
      dbLoadForAction: ({required groupRef, required intentRef}) =>
          dbLoadGroupExitDiagnosticsForAction(
            db,
            groupRef: groupRef,
            intentRef: intentRef,
          ),
      dbClear: () => dbClearGroupExitDiagnostics(db),
    );

GroupExitDiagnostic _native({
  required String groupId,
  required String intentId,
  GroupExitDiagnosticPublicCode publicCode = GroupExitDiagnosticPublicCode.ex04,
}) {
  final rejected = publicCode == GroupExitDiagnosticPublicCode.ex05;
  return GroupExitDiagnostic.create(
    occurredAt: DateTime.parse('2026-07-21T11:03:00.000+02:00'),
    groupId: groupId,
    intentId: intentId,
    kind: GroupExitDiagnosticKind.voluntary,
    severity: GroupExitDiagnosticSeverity.failure,
    phase: GroupExitDiagnosticPhase.native,
    publicCode: publicCode,
    reason: rejected
        ? GroupExitDiagnosticReason.nativeRejected
        : GroupExitDiagnosticReason.nodeNotInitialized,
  );
}

Map<String, Object?> _row({
  int id = 1,
  String groupRef = 'abcdef012345',
  String? intentRef = 'abcdef0123456789abcdef01',
  String exitKind = 'voluntary',
  String severity = 'failure',
  String phase = 'native',
  String publicCode = 'EX04',
  String reasonCode = 'node_not_initialized',
}) => <String, Object?>{
  'id': id,
  'occurred_at': _at,
  'group_ref': groupRef,
  'intent_ref': intentRef,
  'exit_kind': exitKind,
  'severity': severity,
  'phase': phase,
  'public_code': publicCode,
  'reason_code': reasonCode,
};

Future<void> _seedGroupAndIntent(
  Database db, {
  required String groupId,
  required String intentId,
}) async {
  await db.insert('groups', <String, Object?>{
    'id': groupId,
    'name': 'opaque test group',
    'type': 'chat',
    'topic_name': 'topic-$groupId',
    'created_at': _at,
    'created_by': 'peer-admin',
    'my_role': 'member',
  });
  await db.insert('group_exit_intents', <String, Object?>{
    'group_id': groupId,
    'intent_id': intentId,
    'self_peer_id': 'peer-self',
    'self_joined_at': _at,
    'state': 'queued',
    'pending_broadcast_id': 'pending-$intentId',
    'source_event_id': null,
    'event_at': null,
    'revision': 0,
    'last_error_code': null,
    'created_at': _at,
    'updated_at': _at,
  });
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'repository hashes exact ids and round-trips only typed opaque rows',
    () async {
      List<Map<String, Object?>>? appended;
      String? queriedGroupRef;
      String? queriedIntentRef;
      var cleared = false;
      final newestRows = <Map<String, Object?>>[
        _row(id: 2),
        _row(
          intentRef: null,
          phase: 'authority',
          publicCode: 'EX01',
          reasonCode: 'authority_unavailable',
        ),
      ];
      final repository = GroupExitDiagnosticRepositoryImpl(
        dbAppendOutcome: (rows) async => appended = rows,
        dbLoadNewest: () async => newestRows,
        dbLoadForAction: ({required groupRef, required intentRef}) async {
          queriedGroupRef = groupRef;
          queriedIntentRef = intentRef;
          return <Map<String, Object?>>[newestRows.first];
        },
        dbClear: () async => cleared = true,
      );

      expect(groupExitGroupRef(' Group/Ω '), 'a348ef5623d1');
      expect(groupExitIntentRef('Intent/Ä/Case'), '2ebf13a57525bf9ce9ad47bc');
      expect(groupExitGroupRef(' group '), 'c3b38665a9f5');
      expect(groupExitGroupRef('Group'), '34ca0e766088');

      final diagnostic = GroupExitDiagnostic.create(
        occurredAt: DateTime.parse('2026-07-21T11:03:00.123999+02:00'),
        groupId: ' Group/Ω ',
        intentId: 'Intent/Ä/Case',
        kind: GroupExitDiagnosticKind.voluntary,
        severity: GroupExitDiagnosticSeverity.failure,
        phase: GroupExitDiagnosticPhase.native,
        publicCode: GroupExitDiagnosticPublicCode.ex04,
        reason: GroupExitDiagnosticReason.nodeNotInitialized,
      );
      expect(diagnostic.groupRef, 'a348ef5623d1');
      expect(diagnostic.intentRef, '2ebf13a57525bf9ce9ad47bc');
      expect(diagnostic.occurredAt, DateTime.utc(2026, 7, 21, 9, 3, 0, 123));
      await repository.appendOutcome(<GroupExitDiagnostic>[diagnostic]);
      expect(appended, hasLength(1));
      expect(appended!.single['id'], isNull);
      expect(appended!.single['occurred_at'], '2026-07-21T09:03:00.123Z');
      expect(jsonEncode(appended), isNot(contains(' Group/Ω ')));
      expect(jsonEncode(appended), isNot(contains('Intent/Ä/Case')));

      final newest = await repository.loadNewest();
      expect(newest.map((row) => row.id), <int?>[2, 1]);
      expect(newest.last.intentRef, isNull);
      expect(() => newest.add(diagnostic), throwsUnsupportedError);

      final current = await repository.loadForAction(
        groupId: ' Group/Ω ',
        intentId: 'Intent/Ä/Case',
      );
      expect(current, hasLength(1));
      expect(queriedGroupRef, 'a348ef5623d1');
      expect(queriedIntentRef, '2ebf13a57525bf9ce9ad47bc');

      await repository.clear();
      expect(cleared, isTrue);
      expect(
        () => GroupExitDiagnostic.create(
          occurredAt: DateTime.now(),
          groupId: 'group',
          kind: GroupExitDiagnosticKind.voluntary,
          severity: GroupExitDiagnosticSeverity.warning,
          phase: GroupExitDiagnosticPhase.native,
          publicCode: GroupExitDiagnosticPublicCode.ex04,
          reason: GroupExitDiagnosticReason.nodeNotInitialized,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'PB266-07 cleanup preserves history and exact intent reference rejects stale membership diagnostics',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'group_exit_diagnostic_repository_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final path = '${directory.path}/identity.db';
      var db = await databaseFactoryFfi.openDatabase(
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
      var repository = _realRepository(db);
      const groupId = 'same-group-rejoined';

      await _seedGroupAndIntent(db, groupId: groupId, intentId: 'intent-A');
      await repository.appendOutcome(<GroupExitDiagnostic>[
        _native(groupId: groupId, intentId: 'intent-A'),
      ]);
      await db.delete(
        'group_exit_intents',
        where: 'group_id = ?',
        whereArgs: const [groupId],
      );
      await db.delete('groups', where: 'id = ?', whereArgs: const [groupId]);

      await _seedGroupAndIntent(db, groupId: groupId, intentId: 'intent-B');
      await repository.appendOutcome(<GroupExitDiagnostic>[
        _native(
          groupId: groupId,
          intentId: 'intent-B',
          publicCode: GroupExitDiagnosticPublicCode.ex05,
        ),
      ]);
      await repository.appendOutcome(<GroupExitDiagnostic>[
        GroupExitDiagnostic.create(
          occurredAt: DateTime.utc(2026, 7, 21, 9, 4),
          groupId: groupId,
          kind: GroupExitDiagnosticKind.dissolvedShell,
          severity: GroupExitDiagnosticSeverity.failure,
          phase: GroupExitDiagnosticPhase.localDelete,
          publicCode: GroupExitDiagnosticPublicCode.ex10,
          reason: GroupExitDiagnosticReason.terminalShellCleanup,
        ),
      ]);

      await db.close();
      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 104,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      repository = _realRepository(db);

      expect(await repository.loadNewest(), hasLength(3));
      final current = await repository.loadForAction(
        groupId: groupId,
        intentId: 'intent-B',
      );
      expect(current, hasLength(1));
      expect(current.single.publicCode, GroupExitDiagnosticPublicCode.ex05);
      final old = await repository.loadForAction(
        groupId: groupId,
        intentId: 'intent-A',
      );
      expect(old, hasLength(1));
      expect(old.single.publicCode, GroupExitDiagnosticPublicCode.ex04);
      expect(
        await repository.loadForAction(groupId: groupId, intentId: 'intent-C'),
        isEmpty,
      );
    },
  );

  test(
    'PB266-08 hostile cause identifiers paths and secrets never cross storage or rendering',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await runProductionOnCreate(db, 104);
      final repository = _realRepository(db);
      const rawGroup = 'secret-group-id-/private/user/alice-key-material';
      const rawIntent = 'secret-intent-peer-name-stacktrace-token';

      await repository.appendOutcome(<GroupExitDiagnostic>[
        _native(groupId: rawGroup, intentId: rawIntent),
      ]);
      final encodedRows = jsonEncode(await db.query('group_exit_diagnostics'));
      for (final forbidden in const <String>[
        rawGroup,
        rawIntent,
        'secret-group',
        'secret-intent',
        '/private/user',
        'alice',
        'key-material',
        'stacktrace',
        'token',
      ]) {
        expect(encodedRows, isNot(contains(forbidden)));
      }
      expect(encodedRows, contains(groupExitGroupRef(rawGroup)));
      expect(encodedRows, contains(groupExitIntentRef(rawIntent)));
    },
  );
}
