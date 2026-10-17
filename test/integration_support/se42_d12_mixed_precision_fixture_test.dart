import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../integration_test/_support/se42_d12_mixed_precision_fixture.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late Database db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('d12_fixture_');
    db = await openDatabase(
      p.join(directory.path, 'identity.db'),
      version: currentIdentityDatabaseVersion,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    );
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  final base = DateTime.utc(2026, 10, 15, 19, 30, 5, 123);

  test(
    'seeds an exact-millisecond and a later same-millisecond microsecond missed call',
    () async {
      await seedD12Fixture(db, base: base);

      final snapshot = await d12Snapshot(db);

      expect(snapshot.rows.map((row) => row['started_at']), <String>[
        '2026-10-15T19:30:05.123500Z',
        '2026-10-15T19:30:05.123Z',
      ]);
      expect(snapshot.rows.map((row) => row['call_id']), <String>[
        D12Fixture.synthetic.newerCallId,
        D12Fixture.synthetic.olderCallId,
      ]);
      expect(snapshot.rows.map((row) => row['status']).toSet(), {'missed'});
      expect(snapshot.rows.map((row) => row['direction']).toSet(), {
        'incoming',
      });
      expect(snapshot.rows.map((row) => row['read_at']).toSet(), {null});
      expect(snapshot.unreadCalls, 2);
      expect(snapshot.contactUsername, d12ContactUsername);
    },
  );

  test('the repository lists the microsecond call first', () async {
    await seedD12Fixture(db, base: base);

    final page = await CallHistoryRepositoryImpl(db).browse();

    expect(page.rows.map((row) => row.entry.callId.value).take(2), <String>[
      D12Fixture.synthetic.newerCallId,
      D12Fixture.synthetic.olderCallId,
    ]);
    expect(page.missed, 2);
  });

  test('seeding twice keeps the first rows and adds nothing', () async {
    await seedD12Fixture(db, base: base);
    final first = await d12Snapshot(db);

    await seedD12Fixture(db, base: base.add(const Duration(minutes: 5)));

    expect((await d12Snapshot(db)).toJson(), first.toJson());
  });

  test('a paired-peer fixture refuses a peer that is not a contact', () async {
    await expectLater(
      seedD12Fixture(
        db,
        base: base,
        fixture: D12Fixture.pairedPeer('12D3KooWNotAContact'),
      ),
      throwsStateError,
    );
    expect(await db.query('call_history'), isEmpty);
  });

  test(
    'a paired-peer fixture keeps the existing contact and uses its own call ids',
    () async {
      const peer = '12D3KooWDisposablePairedPeerForD12';
      await db.insert('contacts', <String, Object?>{
        'peer_id': peer,
        'public_key': 'paired-key',
        'rendezvous': 'paired',
        'username': 'paired-emulator',
        'signature': 'paired-signature',
        'scanned_at': '2026-10-15T10:00:00.000Z',
      });
      final fixture = D12Fixture.pairedPeer(peer);

      await seedD12Fixture(db, base: base);
      await seedD12Fixture(db, base: base, fixture: fixture);
      final snapshot = await d12Snapshot(db, fixture: fixture);

      expect(snapshot.contactUsername, 'paired-emulator');
      expect(snapshot.rows.map((row) => row['call_id']), <String>[
        fixture.newerCallId,
        fixture.olderCallId,
      ]);
      expect(snapshot.unreadCalls, 2);
      expect((await d12Snapshot(db)).rows, hasLength(2));
    },
  );

  test('a later round seeds a new, newer pair beside the first', () async {
    const peer = '12D3KooWDisposablePairedPeerForD12';
    await db.insert('contacts', <String, Object?>{
      'peer_id': peer,
      'public_key': 'paired-key',
      'rendezvous': 'paired',
      'username': 'paired-emulator',
      'signature': 'paired-signature',
      'scanned_at': '2026-10-15T10:00:00.000Z',
    });
    final first = D12Fixture.pairedPeer(peer);
    final second = D12Fixture.pairedPeer(peer, round: 2);
    await seedD12Fixture(db, base: base, fixture: first);
    await seedD12Fixture(
      db,
      base: base.add(const Duration(minutes: 1)),
      fixture: second,
    );

    expect(second.olderCallId, 'd1200000-0000-4000-8000-000000000005');
    expect(second.newerCallId, 'd1200000-0000-4000-8000-000000000006');
    final page = await CallHistoryRepositoryImpl(db).browse();
    expect(page.rows.map((row) => row.entry.callId.value), <String>[
      second.newerCallId,
      second.olderCallId,
      first.newerCallId,
      first.olderCallId,
    ]);
    expect(() => D12Fixture.pairedPeer(peer, round: 5), throwsRangeError);
  });
}
