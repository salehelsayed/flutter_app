import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_rejoin_state_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/088_group_rejoin_state.dart';

/// Host (sqflite_common_ffi) real-DB coverage for the Finding 05 Phase 3
/// `group_rejoin_state` helpers + migration 088.
///
/// This exercises the SAME raw SQL as the device proof
/// (`integration_test/group_rejoin_state_db_proof_test.dart`) but runs in the
/// default `flutter test` host suite — no device build — so a regression in the
/// `ON CONFLICT … + 1` upsert, the schema, or the epoch-ms persistence is caught
/// in routine CI. The use-case suite only exercises `InMemoryGroupRepository`,
/// which reimplements the increment/clear in pure Dart, so without this the
/// production SQL path ships untested on the host. Mirrors the established
/// `*_db_helpers_test.dart` pattern used across `test/core/database/helpers/`.
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupRejoinStateMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('088 migration', () {
    test('creates group_rejoin_state with the expected columns + PK', () async {
      final cols = await db.rawQuery('PRAGMA table_info(group_rejoin_state)');
      final byName = {for (final c in cols) c['name'] as String: c};

      expect(
        byName.keys,
        containsAll(['group_id', 'rejoin_attempt_count', 'next_eligible_at']),
      );
      // group_id is the single-column primary key (needed by ON CONFLICT).
      expect(byName['group_id']!['pk'], 1);
      // next_eligible_at is nullable.
      expect(byName['next_eligible_at']!['notnull'], 0);
    });

    test('rejoin_attempt_count is NOT NULL DEFAULT 0 (behavioural)', () async {
      // A bare insert (group_id only) must default the counter to 0 and leave
      // next_eligible_at NULL — proves the DEFAULT 0 + nullable schema.
      await db.rawInsert(
        'INSERT INTO group_rejoin_state (group_id) VALUES (?)',
        ['g0'],
      );
      final rows = await dbLoadGroupRejoinStates(db);
      expect(rows.single['rejoin_attempt_count'], 0);
      expect(rows.single['next_eligible_at'], isNull);
    });

    test(
      'is idempotent — safe to re-run (CREATE TABLE IF NOT EXISTS)',
      () async {
        await runGroupRejoinStateMigration(db);
        await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 1);
        expect(await dbLoadGroupRejoinStates(db), hasLength(1));
      },
    );
  });

  group(
    'dbRecordGroupRejoinFailure / dbLoadGroupRejoinStates / dbClearGroupRejoinState',
    () {
      test('first failure inserts a row at attempt 1', () async {
        expect(await dbLoadGroupRejoinStates(db), isEmpty);

        await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 1000);

        final rows = await dbLoadGroupRejoinStates(db);
        expect(rows, hasLength(1));
        expect(rows.single['group_id'], 'g1');
        expect(rows.single['rejoin_attempt_count'], 1);
        expect(rows.single['next_eligible_at'], 1000);
      });

      test(
        'repeated failures upsert via ON CONFLICT (count climbs, one row)',
        () async {
          await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 1000);
          await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 2000);
          await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 4000);

          final rows = await dbLoadGroupRejoinStates(db);
          expect(rows, hasLength(1)); // upsert, not a duplicate insert.
          expect(rows.single['rejoin_attempt_count'], 3);
          expect(
            rows.single['next_eligible_at'],
            4000,
          ); // reschedules each time.
        },
      );

      test('groups are independent', () async {
        await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 1000);
        await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 2000);
        await dbRecordGroupRejoinFailure(db, 'g2', nextEligibleAtMs: 500);

        final byGroup = {
          for (final r in await dbLoadGroupRejoinStates(db))
            r['group_id'] as String: r,
        };
        expect(byGroup['g1']!['rejoin_attempt_count'], 2);
        expect(byGroup['g2']!['rejoin_attempt_count'], 1);
      });

      test('clear removes only the target row', () async {
        await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 1000);
        await dbRecordGroupRejoinFailure(db, 'g2', nextEligibleAtMs: 500);

        await dbClearGroupRejoinState(db, 'g1');

        final remaining = await dbLoadGroupRejoinStates(db);
        expect(remaining, hasLength(1));
        expect(remaining.single['group_id'], 'g2');
      });

      test('clear on an absent group is a no-op', () async {
        await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 1000);
        await dbClearGroupRejoinState(db, 'missing');
        expect(await dbLoadGroupRejoinStates(db), hasLength(1));
      });

      test(
        'G2: forceGroupRejoinEligible collapses next_eligible_at to 0 and '
        'keeps the row + attempt count',
        () async {
          // A stuck group: 11 failures (past the cap), backoff far in the future.
          for (var i = 0; i < 11; i++) {
            await dbRecordGroupRejoinFailure(
              db,
              'g1',
              nextEligibleAtMs: 9999999999999,
            );
          }
          final before = (await dbLoadGroupRejoinStates(db)).single;
          expect(before['rejoin_attempt_count'], 11);
          expect(before['next_eligible_at'], 9999999999999);

          await dbForceGroupRejoinEligible(db, 'g1');

          final after = (await dbLoadGroupRejoinStates(db)).single;
          // Row + attempt count preserved (no auto-delete), backoff collapsed so
          // the next rejoin pass (which gates only on next_eligible_at) retries.
          expect(after['group_id'], 'g1');
          expect(after['rejoin_attempt_count'], 11);
          expect(after['next_eligible_at'], 0);
        },
      );

      test('G2: forceGroupRejoinEligible on an absent group is a no-op', () async {
        await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: 1000);
        await dbForceGroupRejoinEligible(db, 'missing');
        final rows = await dbLoadGroupRejoinStates(db);
        expect(rows, hasLength(1));
        expect(rows.single['next_eligible_at'], 1000);
      });

      test(
        'next_eligible_at persists the exact epoch-ms (UTC DateTime round-trip)',
        () async {
          // GroupRepositoryImpl.recordGroupRejoinFailure stores
          // nextEligibleAt.toUtc().millisecondsSinceEpoch, and the load side rebuilds
          // it via DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true). Locking the
          // exact ms here guarantees that pure mapping round-trips losslessly.
          final dt = DateTime.utc(2026, 6, 17, 12, 34, 56, 789);
          final ms = dt.millisecondsSinceEpoch;

          await dbRecordGroupRejoinFailure(db, 'g1', nextEligibleAtMs: ms);

          final stored =
              (await dbLoadGroupRejoinStates(db)).single['next_eligible_at']
                  as int;
          expect(stored, ms);
          expect(DateTime.fromMillisecondsSinceEpoch(stored, isUtc: true), dt);
        },
      );
    },
  );
}
