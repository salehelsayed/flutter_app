import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
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

  test(
    'fresh projector preserves one terminal row after SQLite reopen',
    () async {
      final startedAt = DateTime.utc(2026, 9, 17, 12);
      final terminal = CallSessionSnapshot.active(
        callId: CallId.parse('66666666-6666-4666-8666-666666666666'),
        contactPeerId: 'contact-a',
        direction: CallDirection.outgoing,
        state: CallState.ended,
        callerAccountPeerId: 'local-account',
        callerDeviceId: 'local-device',
        startedAt: startedAt,
        connectedAt: startedAt.add(const Duration(seconds: 1)),
        endedAt: startedAt.add(const Duration(seconds: 11)),
        endReason: CallEndReason.localHangup,
      );
      final firstAnnouncements = <bool>[];
      final first = await CallHistoryProjector(
        repository,
        clock: () => startedAt.add(const Duration(seconds: 12)),
        onTerminalProjected: (_, inserted) => firstAnnouncements.add(inserted),
      ).projectTerminal(terminal);
      final durableRows = await db.query(kCallHistoryTable);
      expect(firstAnnouncements, <bool>[true]);
      expect(durableRows, hasLength(1));

      await db.close();
      db = await openDatabase(
        p.join(tempDirectory.path, 'history.db'),
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      );
      repository = CallHistoryRepositoryImpl(db);
      final replayAnnouncements = <bool>[];
      final reopenedProjector = CallHistoryProjector(
        repository,
        clock: () => startedAt.add(const Duration(minutes: 2)),
        onTerminalProjected: (_, inserted) => replayAnnouncements.add(inserted),
      );
      final replayed = await reopenedProjector.projectTerminal(terminal);
      final conflictingReplay = await reopenedProjector.projectTerminal(
        terminal.copyWith(
          connectedAt: null,
          endedAt: startedAt.add(const Duration(minutes: 1)),
          endReason: CallEndReason.signalingFailed,
        ),
      );

      expect(replayAnnouncements, <bool>[false, false]);
      expect(replayed.toMap(), first.toMap());
      expect(conflictingReplay.toMap(), first.toMap());
      expect(await db.query(kCallHistoryTable), durableRows);
      expect(
        (await reopenedProjector.timelineForContact(
          'contact-a',
        )).map((entry) => entry.toMap()),
        <Map<String, Object?>>[first.toMap()],
      );
    },
  );

  test(
    'global history pages have one row per call, stable equal-time order, local search and current names',
    () async {
      final browser = repository as CallHistoryBrowser;
      final stamp = DateTime.utc(2026, 10, 13);
      await db.insert('contacts', {
        'peer_id': 'contact-a',
        'username': 'Alice',
        'public_key': 'synthetic',
        'rendezvous': 'synthetic',
        'signature': 'synthetic',
        'scanned_at': stamp.toIso8601String(),
      });
      for (final id in [
        '66666666-6666-4666-8666-666666666666',
        '77777777-7777-4777-8777-777777777777',
      ]) {
        await repository.upsertTerminal(row(id: id, startedAt: stamp));
      }
      await repository.upsertTerminal(
        row(
          id: '88888888-8888-4888-8888-888888888888',
          contact: 'removed-contact',
          startedAt: stamp.subtract(const Duration(seconds: 1)),
        ),
      );
      final first = await browser.browse(pageSize: 1);
      final second = await browser.browse(cursor: first.next, pageSize: 1);
      final third = await browser.browse(cursor: second.next, pageSize: 1);
      expect(
        [
          first.rows.single.entry.callId.value,
          second.rows.single.entry.callId.value,
          third.rows.single.entry.callId.value,
        ],
        [
          '66666666-6666-4666-8666-666666666666',
          '77777777-7777-4777-8777-777777777777',
          '88888888-8888-4888-8888-888888888888',
        ],
      );
      expect(first.total, 3);
      expect(third.next, isNull);
      expect(third.rows.single.contactName, isNull);
      expect((await browser.browse(search: 'ALICE')).rows, hasLength(2));
      await db.update(
        'contacts',
        {'username': 'Renamed'},
        where: 'peer_id = ?',
        whereArgs: ['contact-a'],
      );
      expect((await browser.browse(search: 'alice')).rows, isEmpty);
      expect((await browser.browse(search: 'renamed')).total, 2);
      await db.delete(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: ['contact-a'],
      );
      final removed = await browser.browse();
      expect(removed.rows, hasLength(3));
      expect(removed.rows.map((r) => r.contactName), everyElement(isNull));
    },
  );

  test(
    'global paging orders mixed millisecond and microsecond timestamps chronologically',
    () async {
      final stamp = DateTime.utc(2026, 10, 13);
      final entries = [
        row(id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', startedAt: stamp),
        row(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          startedAt: stamp.add(const Duration(microseconds: 1)),
        ),
        row(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          startedAt: stamp.add(const Duration(microseconds: 999)),
        ),
        row(
          id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          startedAt: stamp.add(const Duration(milliseconds: 1)),
        ),
      ];
      for (final entry in entries) {
        await repository.upsertTerminal(entry);
      }
      final repo = repository as CallHistoryBrowser;
      final observed = <CallId>[];
      CallHistoryCursor? cursor;
      do {
        final page = await repo.browse(pageSize: 1, cursor: cursor);
        observed.addAll(page.rows.map((r) => r.entry.callId));
        cursor = page.next;
      } while (cursor != null);
      expect(observed, entries.reversed.map((entry) => entry.callId));
      expect(
        await db.query(kCallHistoryTable),
        hasLength(4),
        reason: 'browsing does not rewrite stored timestamps',
      );
    },
  );

  test(
    'Missed filter uses incoming missed/cancelled/busy and leaves unread counts intact',
    () async {
      final stamp = DateTime.utc(2026, 10, 13);
      var i = 0;
      for (final direction in CallDirection.values) {
        for (final status in CallHistoryStatus.values) {
          final id =
              'aaaaaaaa-aaaa-4aaa-8aaa-${(++i).toString().padLeft(12, '0')}';
          await repository.upsertTerminal(
            CallHistoryEntry(
              callId: CallId.parse(id),
              contactAccountPeerId: 'contact-a',
              direction: direction,
              terminalReason: CallEndReason.noAnswer,
              status: status,
              startedAt: stamp,
              connectedAt: null,
              endedAt: stamp.add(const Duration(seconds: 30)),
              transportRoute: null,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
        }
      }
      final repo = repository as CallHistoryRepositoryImpl;
      final before = await repo.unreadCallCountsForContacts(['contact-a']);
      final page = await repo.browse(missedOnly: true, pageSize: 2);
      final next = await repo.browse(
        missedOnly: true,
        cursor: page.next,
        pageSize: 2,
      );
      expect(page.total, 12);
      expect(page.missed, 3);
      expect(page.rows, hasLength(2));
      expect(next.rows, hasLength(1));
      expect(
        [...page.rows, ...next.rows].map((r) => r.entry.direction),
        everyElement(CallDirection.incoming),
      );
      expect(await repo.unreadCallCountsForContacts(['contact-a']), before);
      expect(before, {'contact-a': 3});
      expect(() => repo.browse(pageSize: 0), throwsArgumentError);
    },
  );

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
