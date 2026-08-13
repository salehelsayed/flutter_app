import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_pending_key_distributions_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/078_group_pending_key_distributions.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupPendingKeyDistributionsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> distributionRow({
    String id = 'gpkd:group-1:peer-carol',
    String groupId = 'group-1',
    String peerId = 'peer-carol',
    int keyEpoch = 2,
    String status = groupPendingKeyDistributionStatusPending,
    int attempts = 0,
    String? transportPeerId = 'transport-carol',
    String? deviceId = 'device-carol',
    String createdAt = '2026-06-16T12:00:00.000Z',
    String updatedAt = '2026-06-16T12:00:00.000Z',
    String? finalizedAt,
  }) {
    return {
      'id': id,
      'group_id': groupId,
      'peer_id': peerId,
      'transport_peer_id': transportPeerId,
      'device_id': deviceId,
      'key_epoch': keyEpoch,
      'status': status,
      'attempts': attempts,
      'last_error': null,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'finalized_at': finalizedAt,
    };
  }

  test('upserts pending distribution idempotently and merges epoch', () async {
    final created = await dbUpsertGroupPendingKeyDistribution(
      db,
      distributionRow(),
    );
    final duplicate = await dbUpsertGroupPendingKeyDistribution(
      db,
      distributionRow(
        keyEpoch: 3,
        createdAt: '2026-06-16T12:01:00.000Z',
        updatedAt: '2026-06-16T12:01:00.000Z',
      ),
    );

    expect(created, isTrue);
    expect(duplicate, isFalse);

    final loaded = await dbLoadGroupPendingKeyDistribution(
      db,
      'gpkd:group-1:peer-carol',
    );
    expect(loaded, isNotNull);
    expect(loaded!['key_epoch'], 3); // merged forward to the newer rotation
    expect(
      loaded['created_at'],
      '2026-06-16T12:00:00.000Z',
    ); // pending merge is still the same operation
    expect(loaded['updated_at'], '2026-06-16T12:01:00.000Z');
    expect(loaded['attempts'], 0); // attempts NOT reset

    final byPeer = await dbLoadPendingGroupKeyDistributionsForPeer(
      db,
      peerId: 'peer-carol',
    );
    expect(byPeer, hasLength(1));
    final byGroup = await dbLoadPendingGroupKeyDistributionsForGroup(
      db,
      groupId: 'group-1',
    );
    expect(byGroup, hasLength(1));
  });

  test('records attempts (gated on pending) and finalizes once', () async {
    await dbUpsertGroupPendingKeyDistribution(db, distributionRow());

    await dbRecordGroupPendingKeyDistributionAttempt(
      db,
      'gpkd:group-1:peer-carol',
      lastError: 'still keyless',
      updatedAt: '2026-06-16T12:02:00.000Z',
    );
    await dbFinalizeGroupPendingKeyDistribution(
      db,
      'gpkd:group-1:peer-carol',
      status: groupPendingKeyDistributionStatusUnreachable,
      lastError: 'attempt cap reached',
      finalizedAt: '2026-06-16T12:03:00.000Z',
    );
    // Second finalize ignored (finalized_at IS NULL gate).
    await dbFinalizeGroupPendingKeyDistribution(
      db,
      'gpkd:group-1:peer-carol',
      status: groupPendingKeyDistributionStatusDistributed,
      lastError: 'second call ignored',
      finalizedAt: '2026-06-16T12:04:00.000Z',
    );
    // recordAttempt after finalize is a no-op (status != pending).
    await dbRecordGroupPendingKeyDistributionAttempt(
      db,
      'gpkd:group-1:peer-carol',
      lastError: 'ignored',
      updatedAt: '2026-06-16T12:05:00.000Z',
    );

    final loaded = await dbLoadGroupPendingKeyDistribution(
      db,
      'gpkd:group-1:peer-carol',
    );
    expect(loaded!['attempts'], 1);
    expect(loaded['status'], groupPendingKeyDistributionStatusUnreachable);
    expect(loaded['last_error'], 'attempt cap reached');
    expect(loaded['finalized_at'], '2026-06-16T12:03:00.000Z');

    // Finalized rows are excluded from the pending scans.
    expect(
      await dbLoadPendingGroupKeyDistributionsForPeer(db, peerId: 'peer-carol'),
      isEmpty,
    );
  });

  test('re-upsert over a terminal row does not reopen it', () async {
    await dbUpsertGroupPendingKeyDistribution(db, distributionRow());
    await dbFinalizeGroupPendingKeyDistribution(
      db,
      'gpkd:group-1:peer-carol',
      status: groupPendingKeyDistributionStatusDistributed,
      lastError: '',
      finalizedAt: '2026-06-16T12:03:00.000Z',
    );

    final reopened = await dbUpsertGroupPendingKeyDistribution(
      db,
      distributionRow(keyEpoch: 4, updatedAt: '2026-06-16T12:06:00.000Z'),
    );
    expect(reopened, isFalse);

    final loaded = await dbLoadGroupPendingKeyDistribution(
      db,
      'gpkd:group-1:peer-carol',
    );
    expect(loaded!['status'], groupPendingKeyDistributionStatusDistributed);
    expect(loaded['key_epoch'], 2); // not merged (terminal)
  });

  test(
    'reopenForRedelivery DOES reopen a terminal row (resets attempts/finalizedAt)',
    () async {
      await dbUpsertGroupPendingKeyDistribution(db, distributionRow());
      await dbFinalizeGroupPendingKeyDistribution(
        db,
        'gpkd:group-1:peer-carol',
        status: groupPendingKeyDistributionStatusUnreachable,
        lastError: 'offline',
        finalizedAt: '2026-06-16T12:03:00.000Z',
      );

      // Unlike a plain upsert (which leaves a terminal row terminal), reopen
      // re-arms it for re-delivery because the member's device set changed.
      await dbReopenGroupPendingKeyDistributionForRedelivery(
        db,
        distributionRow(keyEpoch: 4, updatedAt: '2026-06-16T12:06:00.000Z'),
      );

      final loaded = await dbLoadGroupPendingKeyDistribution(
        db,
        'gpkd:group-1:peer-carol',
      );
      expect(loaded!['status'], groupPendingKeyDistributionStatusPending);
      expect(loaded['key_epoch'], 4); // refreshed to the current epoch
      expect(loaded['attempts'], 0); // reset
      expect(loaded['last_error'], isNull);
      expect(loaded['finalized_at'], isNull);
      expect(loaded['created_at'], '2026-06-16T12:00:00.000001Z');
      expect(
        GroupPendingKeyDistribution.fromMap(loaded).operationGeneration,
        DateTime.parse('2026-06-16T12:00:00.000001Z').microsecondsSinceEpoch,
      );
    },
  );

  test(
    'every reopen advances operation generation despite same or older clocks',
    () async {
      await dbUpsertGroupPendingKeyDistribution(db, distributionRow());

      await dbReopenGroupPendingKeyDistributionForRedelivery(
        db,
        distributionRow(
          createdAt: '2026-06-16T11:59:00.000Z',
          updatedAt: '2026-06-16T12:01:00.000Z',
        ),
      );
      var loaded = await dbLoadGroupPendingKeyDistribution(
        db,
        'gpkd:group-1:peer-carol',
      );
      expect(loaded!['created_at'], '2026-06-16T12:00:00.000001Z');

      // The row is already pending and the caller repeats an older timestamp.
      // This is an intentional same-device re-arm, not an idempotent enqueue.
      await dbReopenGroupPendingKeyDistributionForRedelivery(
        db,
        distributionRow(
          createdAt: '2026-06-16T11:59:00.000Z',
          updatedAt: '2026-06-16T12:02:00.000Z',
        ),
      );
      loaded = await dbLoadGroupPendingKeyDistribution(
        db,
        'gpkd:group-1:peer-carol',
      );
      expect(loaded!['created_at'], '2026-06-16T12:00:00.000002Z');

      await dbReopenGroupPendingKeyDistributionForRedelivery(
        db,
        distributionRow(
          createdAt: '2026-06-16T12:10:00.000Z',
          updatedAt: '2026-06-16T12:10:00.000Z',
        ),
      );
      loaded = await dbLoadGroupPendingKeyDistribution(
        db,
        'gpkd:group-1:peer-carol',
      );
      expect(loaded!['created_at'], '2026-06-16T12:10:00.000Z');
    },
  );

  test('reopen generation fences a stale exact tuple', () async {
    await dbUpsertGroupPendingKeyDistribution(db, distributionRow());
    final stale = await dbLoadGroupPendingKeyDistribution(
      db,
      'gpkd:group-1:peer-carol',
    );

    // Keep every mutable field identical so `created_at` is the only changed
    // exact-CAS component.
    await dbReopenGroupPendingKeyDistributionForRedelivery(
      db,
      distributionRow(),
    );

    expect(
      await dbRecordGroupPendingKeyDistributionAttemptIfExact(
        db,
        stale!,
        lastError: 'stale owner',
        updatedAt: '2026-06-16T12:01:00.000Z',
      ),
      isFalse,
    );
    final current = await dbLoadGroupPendingKeyDistribution(
      db,
      'gpkd:group-1:peer-carol',
    );
    expect(current!['attempts'], 0);
    expect(current['created_at'], '2026-06-16T12:00:00.000001Z');
    expect(
      await dbRecordGroupPendingKeyDistributionAttemptIfExact(
        db,
        current,
        lastError: null,
        updatedAt: '2026-06-16T12:01:00.000Z',
      ),
      isTrue,
    );
  });

  test('reopenForRedelivery creates the row when none exists', () async {
    await dbReopenGroupPendingKeyDistributionForRedelivery(
      db,
      distributionRow(),
    );
    final loaded = await dbLoadGroupPendingKeyDistribution(
      db,
      'gpkd:group-1:peer-carol',
    );
    expect(loaded, isNotNull);
    expect(loaded!['status'], groupPendingKeyDistributionStatusPending);
  });
}
