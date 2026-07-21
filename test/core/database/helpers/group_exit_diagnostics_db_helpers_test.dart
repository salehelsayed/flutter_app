import 'dart:io';

import 'package:flutter_app/core/database/helpers/group_exit_diagnostics_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

GroupExitDiagnosticRepositoryImpl _repository(Database db) =>
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

GroupExitDiagnostic _nativeDiagnostic({
  required DateTime occurredAt,
  String groupId = 'group-1',
  String intentId = 'intent-1',
}) => GroupExitDiagnostic.create(
  occurredAt: occurredAt,
  groupId: groupId,
  intentId: intentId,
  kind: GroupExitDiagnosticKind.voluntary,
  severity: GroupExitDiagnosticSeverity.failure,
  phase: GroupExitDiagnosticPhase.native,
  publicCode: GroupExitDiagnosticPublicCode.ex04,
  reason: GroupExitDiagnosticReason.nodeNotInitialized,
);

GroupExitDiagnostic _warning(
  GroupExitDiagnosticPublicCode code, {
  DateTime? occurredAt,
}) {
  final isDelivery = code == GroupExitDiagnosticPublicCode.ex08;
  return GroupExitDiagnostic.create(
    occurredAt: occurredAt ?? DateTime.utc(2026, 7, 21, 9, 3),
    groupId: 'group-warnings',
    intentId: 'intent-warnings',
    kind: GroupExitDiagnosticKind.voluntary,
    severity: GroupExitDiagnosticSeverity.warning,
    phase: isDelivery
        ? GroupExitDiagnosticPhase.delivery
        : GroupExitDiagnosticPhase.rotation,
    publicCode: code,
    reason: isDelivery
        ? GroupExitDiagnosticReason.noticeDeliveryDegraded
        : GroupExitDiagnosticReason.rotationDeferred,
  );
}

Future<({Directory directory, Database first, Database second})> _openPair(
  String prefix,
) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  final path = '${directory.path}/identity.db';
  final first = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 104,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
  final second = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 104,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
  await first.execute('PRAGMA busy_timeout = 5000');
  await second.execute('PRAGMA busy_timeout = 5000');
  return (directory: directory, first: first, second: second);
}

Future<void> _closePair(
  ({Directory directory, Database first, Database second}) pair,
) async {
  if (pair.second.isOpen) await pair.second.close();
  if (pair.first.isOpen) await pair.first.close();
  if (await pair.directory.exists()) {
    await pair.directory.delete(recursive: true);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'PB266-06 diagnostic batches are atomic canonical bounded and clear-linearizable',
    () async {
      final pair = await _openPair('group_exit_diagnostic_helper_');
      addTearDown(() => _closePair(pair));
      final first = _repository(pair.first);
      final second = _repository(pair.second);

      expect(
        () => first.appendOutcome(const <GroupExitDiagnostic>[]),
        throwsArgumentError,
      );

      await first.appendOutcome(<GroupExitDiagnostic>[
        _nativeDiagnostic(
          occurredAt: DateTime.parse('2026-07-21T11:03:00.123456+02:00'),
        ),
      ]);
      expect(
        (await first.loadNewest()).single.occurredAt,
        DateTime.utc(2026, 7, 21, 9, 3, 0, 123),
      );
      expect(
        (await pair.first.query(
          'group_exit_diagnostics',
        )).single['occurred_at'],
        '2026-07-21T09:03:00.123Z',
      );

      final countBeforeFault = (await first.loadNewest()).length;
      final validDelivery = _warning(
        GroupExitDiagnosticPublicCode.ex08,
      ).toMap(includeId: false);
      final invalidRotation = <String, Object?>{
        ..._warning(GroupExitDiagnosticPublicCode.ex09).toMap(includeId: false),
        'reason_code': 'native_rejected',
      };
      await expectLater(
        dbAppendGroupExitDiagnosticOutcome(pair.first, <Map<String, Object?>>[
          validDelivery,
          invalidRotation,
        ]),
        throwsA(isA<DatabaseException>()),
      );
      expect(await first.loadNewest(), hasLength(countBeforeFault));

      await first.clear();
      for (var index = 0; index < 25; index++) {
        // Deliberately reverse wall clock so id, not timestamp, owns recency.
        await first.appendOutcome(<GroupExitDiagnostic>[
          _nativeDiagnostic(
            occurredAt: DateTime.utc(
              2026,
              7,
              21,
            ).subtract(Duration(minutes: index)),
            intentId: 'intent-$index',
          ),
        ]);
      }
      final capped = await first.loadNewest();
      expect(capped, hasLength(20));
      expect(
        capped.map((row) => row.id),
        orderedEquals(List<int>.generate(20, (index) => 25 - index)),
      );
      expect(capped.first.occurredAt.isBefore(capped.last.occurredAt), isTrue);

      await Future.wait(<Future<void>>[
        first.appendOutcome(<GroupExitDiagnostic>[
          _nativeDiagnostic(
            occurredAt: DateTime.utc(2026, 7, 22),
            intentId: 'first-0',
          ),
        ]),
        second.appendOutcome(<GroupExitDiagnostic>[
          _nativeDiagnostic(
            occurredAt: DateTime.utc(2026, 7, 23),
            intentId: 'second-0',
          ),
        ]),
      ]);
      for (var index = 1; index < 8; index++) {
        await first.appendOutcome(<GroupExitDiagnostic>[
          _nativeDiagnostic(
            occurredAt: DateTime.utc(2026, 7, 22, 0, index),
            intentId: 'first-$index',
          ),
        ]);
        await second.appendOutcome(<GroupExitDiagnostic>[
          _nativeDiagnostic(
            occurredAt: DateTime.utc(2026, 7, 23, 0, index),
            intentId: 'second-$index',
          ),
        ]);
      }
      final concurrentRows = await first.loadNewest();
      expect(concurrentRows, hasLength(20));
      expect(concurrentRows.map((row) => row.id).toSet(), hasLength(20));

      await first.appendOutcome(<GroupExitDiagnostic>[
        _warning(GroupExitDiagnosticPublicCode.ex08),
        _warning(GroupExitDiagnosticPublicCode.ex09),
      ]);
      await second.clear();
      expect(await first.loadNewest(), isEmpty);

      await second.clear();
      await first.appendOutcome(<GroupExitDiagnostic>[
        _warning(GroupExitDiagnosticPublicCode.ex08),
        _warning(GroupExitDiagnosticPublicCode.ex09),
      ]);
      expect(await second.loadNewest(), hasLength(2));

      await pair.second.close();
      await pair.first.close();
      final reopened = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/identity.db',
        options: OpenDatabaseOptions(
          version: 104,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(() async {
        if (reopened.isOpen) await reopened.close();
      });
      expect(await _repository(reopened).loadNewest(), hasLength(2));

      await _repository(reopened).clear();
      await _repository(reopened).clear();
      expect(await _repository(reopened).loadNewest(), isEmpty);
      final sequenceTable = await reopened.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sqlite_sequence'",
      );
      if (sequenceTable.isNotEmpty) {
        expect(
          await reopened.rawQuery(
            "SELECT name FROM sqlite_sequence WHERE name = ?",
            const ['group_exit_diagnostics'],
          ),
          isEmpty,
        );
      }
    },
  );

  test(
    'PB266-11 delivery and rotation warnings commit together while leave remains successful',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await runProductionOnCreate(db, 104);
      final repository = _repository(db);

      final facts = <GroupExitDiagnostic>[
        _warning(GroupExitDiagnosticPublicCode.ex08),
        _warning(GroupExitDiagnosticPublicCode.ex09),
      ];
      await repository.appendOutcome(facts);
      expect(
        (await repository.loadNewest()).map((row) => row.publicCode).toSet(),
        <GroupExitDiagnosticPublicCode>{
          GroupExitDiagnosticPublicCode.ex08,
          GroupExitDiagnosticPublicCode.ex09,
        },
      );

      await repository.clear();
      final invalidSecond = <String, Object?>{
        ...facts.last.toMap(includeId: false),
        'severity': 'failure',
      };
      await expectLater(
        dbAppendGroupExitDiagnosticOutcome(db, <Map<String, Object?>>[
          facts.first.toMap(includeId: false),
          invalidSecond,
        ]),
        throwsA(isA<DatabaseException>()),
      );
      expect(await repository.loadNewest(), isEmpty);
    },
  );
}
