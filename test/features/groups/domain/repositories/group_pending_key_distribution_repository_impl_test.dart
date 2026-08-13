import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_pending_key_distributions_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/078_group_pending_key_distributions.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_key_distribution_repository_impl.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late GroupPendingKeyDistributionRepositoryImpl repo;

  GroupPendingKeyDistributionRepositoryImpl buildRepository() {
    return GroupPendingKeyDistributionRepositoryImpl(
      dbUpsertGroupPendingKeyDistribution: (row) =>
          dbUpsertGroupPendingKeyDistribution(db, row),
      dbReopenGroupPendingKeyDistributionForRedelivery: (row) =>
          dbReopenGroupPendingKeyDistributionForRedelivery(db, row),
      dbLoadGroupPendingKeyDistribution: (id) =>
          dbLoadGroupPendingKeyDistribution(db, id),
      dbLoadPendingGroupKeyDistributionsForPeer:
          ({required peerId, groupId, limit = 50}) =>
              dbLoadPendingGroupKeyDistributionsForPeer(
                db,
                peerId: peerId,
                groupId: groupId,
                limit: limit,
              ),
      dbLoadPendingGroupKeyDistributionsForGroup:
          ({required groupId, limit = 50}) =>
              dbLoadPendingGroupKeyDistributionsForGroup(
                db,
                groupId: groupId,
                limit: limit,
              ),
      dbRecordGroupPendingKeyDistributionAttempt:
          (id, {required lastError, required updatedAt}) =>
              dbRecordGroupPendingKeyDistributionAttempt(
                db,
                id,
                lastError: lastError,
                updatedAt: updatedAt,
              ),
      dbRecordGroupPendingKeyDistributionAttemptIfExact:
          (expected, {required lastError, required updatedAt}) =>
              dbRecordGroupPendingKeyDistributionAttemptIfExact(
                db,
                expected,
                lastError: lastError,
                updatedAt: updatedAt,
              ),
      dbFinalizeGroupPendingKeyDistribution:
          (id, {required status, required lastError, required finalizedAt}) =>
              dbFinalizeGroupPendingKeyDistribution(
                db,
                id,
                status: status,
                lastError: lastError,
                finalizedAt: finalizedAt,
              ),
      dbFinalizeGroupPendingKeyDistributionIfExact:
          (
            expected, {
            required status,
            required lastError,
            required finalizedAt,
          }) => dbFinalizeGroupPendingKeyDistributionIfExact(
            db,
            expected,
            status: status,
            lastError: lastError,
            finalizedAt: finalizedAt,
          ),
    );
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupPendingKeyDistributionsMigration(db);
    repo = buildRepository();
  });

  tearDown(() async {
    await db.close();
  });

  GroupPendingKeyDistribution distribution({
    String groupId = 'group-1',
    String peerId = 'peer-carol',
    int keyEpoch = 2,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final operationStartedAt = createdAt ?? DateTime.utc(2026, 6, 16, 12);
    return GroupPendingKeyDistribution(
      id: groupPendingKeyDistributionId(groupId, peerId),
      groupId: groupId,
      peerId: peerId,
      transportPeerId: 'transport-$peerId',
      deviceId: 'device-$peerId',
      keyEpoch: keyEpoch,
      createdAt: operationStartedAt,
      updatedAt: updatedAt ?? operationStartedAt,
    );
  }

  test('returns created only for the first enqueue', () async {
    final first = await repo.enqueue(distribution());
    final duplicate = await repo.enqueue(
      distribution(
        keyEpoch: 3,
        createdAt: DateTime.utc(2026, 6, 16, 13),
        updatedAt: DateTime.utc(2026, 6, 16, 13),
      ),
    );

    expect(first.created, isTrue);
    expect(duplicate.created, isFalse);
    expect(duplicate.distribution.keyEpoch, 3); // merged forward
    expect(
      duplicate.distribution.operationGeneration,
      first.distribution.operationGeneration,
    ); // ordinary pending merge does not create a new operation
  });

  test(
    'reopen generation survives map and repository reconstruction and fences stale owner',
    () async {
      final stale = (await repo.enqueue(distribution())).distribution;

      await repo.reopenForRedelivery(
        distribution(createdAt: stale.createdAt, updatedAt: stale.updatedAt),
      );
      final reopened = (await repo.getDistribution(stale.id))!;
      expect(reopened.operationGeneration, stale.operationGeneration + 1);

      final mapRoundTrip = GroupPendingKeyDistribution.fromMap(
        reopened.toMap(),
      );
      expect(mapRoundTrip.operationGeneration, reopened.operationGeneration);
      expect(mapRoundTrip.createdAt, reopened.createdAt);

      // Reconstruct the repository over the same durable database, as a
      // process restart would, and recover the exact generation unchanged.
      final restartedRepository = buildRepository();
      final afterRestart = (await restartedRepository.getDistribution(
        stale.id,
      ))!;
      expect(afterRestart.operationGeneration, reopened.operationGeneration);

      expect(
        await restartedRepository.finalizeDistributedIfExact(stale),
        isFalse,
      );
      expect(
        await restartedRepository.finalizeDistributedIfExact(afterRestart),
        isTrue,
      );
    },
  );

  test('lists pending by peer/group then finalizes safely', () async {
    await repo.enqueue(distribution());
    await repo.enqueue(distribution(peerId: 'peer-dave'));

    final byPeer = await repo.getPendingForPeer(peerId: 'peer-carol');
    expect(byPeer, hasLength(1));
    expect(byPeer.single.peerId, 'peer-carol');

    final byGroup = await repo.getPendingForGroup(groupId: 'group-1');
    expect(byGroup, hasLength(2));

    await repo.recordAttempt(
      groupPendingKeyDistributionId('group-1', 'peer-carol'),
      lastError: 'still keyless',
    );
    await repo.finalizeDistributed(
      groupPendingKeyDistributionId('group-1', 'peer-carol'),
    );

    final finalized = await repo.getDistribution(
      groupPendingKeyDistributionId('group-1', 'peer-carol'),
    );
    expect(finalized!.attempts, 1);
    expect(finalized.status, groupPendingKeyDistributionStatusDistributed);
    expect(finalized.finalizedAt, isNotNull);
    // Only Dave's row remains pending.
    expect(await repo.getPendingForGroup(groupId: 'group-1'), hasLength(1));
  });
}
