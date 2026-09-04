import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late Database db;
  late CallHistoryRepository repository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('call_history_');
    db = await openDatabase(
      p.join(tempDirectory.path, 'history.db'),
      version: currentIdentityDatabaseVersion,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    );
    repository = CallHistoryRepositoryImpl(db);
  });

  tearDown(() async {
    await db.close();
    await tempDirectory.delete(recursive: true);
  });

  CallHistoryEntry row({
    required String id,
    String contact = 'contact-a',
    required DateTime startedAt,
    CallHistoryStatus status = CallHistoryStatus.completed,
    CallEndReason reason = CallEndReason.localHangup,
  }) => CallHistoryEntry(
    callId: CallId.parse(id),
    contactAccountPeerId: contact,
    direction: CallDirection.outgoing,
    terminalReason: reason,
    status: status,
    startedAt: startedAt,
    connectedAt: startedAt.add(const Duration(seconds: 1)),
    endedAt: startedAt.add(const Duration(seconds: 11)),
    transportRoute: null,
    createdAt: startedAt.add(const Duration(seconds: 11)),
    updatedAt: startedAt.add(const Duration(seconds: 11)),
  );

  test('one monotonic row is retained per call id', () async {
    final original = row(
      id: '66666666-6666-4666-8666-666666666666',
      startedAt: DateTime.utc(2026, 8, 30, 12),
    );
    final conflictingDuplicate = CallHistoryEntry(
      callId: original.callId,
      contactAccountPeerId: original.contactAccountPeerId,
      direction: original.direction,
      terminalReason: CallEndReason.signalingFailed,
      status: CallHistoryStatus.failed,
      startedAt: original.startedAt,
      connectedAt: null,
      endedAt: original.endedAt.add(const Duration(minutes: 1)),
      transportRoute: CallRouteClass.ephemeralMailbox,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt.add(const Duration(minutes: 1)),
    );

    await repository.upsertTerminal(original);
    await repository.upsertTerminal(conflictingDuplicate);

    final stored = await repository.getByCallId(original.callId);
    expect(stored?.terminalReason, CallEndReason.localHangup);
    expect(stored?.status, CallHistoryStatus.completed);
    expect(stored?.connectedAt, original.connectedAt);
    expect(await db.query(kCallHistoryTable), hasLength(1));
  });

  test('contact history is scoped and newest first', () async {
    await repository.upsertTerminal(
      row(
        id: '77777777-7777-4777-8777-777777777777',
        startedAt: DateTime.utc(2026, 8, 30, 12),
      ),
    );
    await repository.upsertTerminal(
      row(
        id: '88888888-8888-4888-8888-888888888888',
        startedAt: DateTime.utc(2026, 8, 30, 13),
      ),
    );
    await repository.upsertTerminal(
      row(
        id: '99999999-9999-4999-8999-999999999999',
        contact: 'contact-b',
        startedAt: DateTime.utc(2026, 8, 30, 14),
      ),
    );

    final rows = await repository.listForContact('contact-a');
    expect(rows.map((entry) => entry.callId.value), <String>[
      '88888888-8888-4888-8888-888888888888',
      '77777777-7777-4777-8777-777777777777',
    ]);
  });

  test('duration is derived and diagnostics route is optional', () {
    final entry = row(
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      startedAt: DateTime.utc(2026, 8, 30, 12),
    );
    expect(entry.duration, const Duration(seconds: 10));
    expect(entry.toMap().containsKey('duration_ms'), isFalse);
    expect(entry.toMap()['transport_route_class'], isNull);
  });
}
