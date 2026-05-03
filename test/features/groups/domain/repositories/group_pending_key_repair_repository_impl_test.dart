import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_pending_key_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/063_group_pending_key_repairs.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late GroupPendingKeyRepairRepositoryImpl repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupPendingKeyRepairsMigration(db);
    repo = GroupPendingKeyRepairRepositoryImpl(
      dbUpsertGroupPendingKeyRepair: (row) =>
          dbUpsertGroupPendingKeyRepair(db, row),
      dbLoadGroupPendingKeyRepair: (id) => dbLoadGroupPendingKeyRepair(db, id),
      dbLoadPendingGroupKeyRepairsForEpoch:
          ({required groupId, required keyEpoch, limit = 50}) =>
              dbLoadPendingGroupKeyRepairsForEpoch(
                db,
                groupId: groupId,
                keyEpoch: keyEpoch,
                limit: limit,
              ),
      dbRecordGroupPendingKeyRepairAttempt:
          (id, {required lastError, required updatedAt}) =>
              dbRecordGroupPendingKeyRepairAttempt(
                db,
                id,
                lastError: lastError,
                updatedAt: updatedAt,
              ),
      dbFinalizeGroupPendingKeyRepair:
          (id, {required status, required lastError, required finalizedAt}) =>
              dbFinalizeGroupPendingKeyRepair(
                db,
                id,
                status: status,
                lastError: lastError,
                finalizedAt: finalizedAt,
              ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  GroupPendingKeyRepair repair({
    String id = 'offline:group-1:msg-1',
    String groupId = 'group-1',
    String messageId = 'msg-1',
    int keyEpoch = 2,
    String status = groupPendingKeyRepairStatusPendingKey,
    String? replayEnvelopeJson = '{"kind":"group_offline_replay"}',
  }) {
    return GroupPendingKeyRepair(
      id: id,
      groupId: groupId,
      messageId: messageId,
      senderPeerId: 'peer-sender',
      transportPeerId: 'transport-sender',
      payloadType: 'group_message',
      keyEpoch: keyEpoch,
      replayEnvelopeJson: replayEnvelopeJson,
      status: status,
      triggerCount: 1,
      attempts: 0,
      createdAt: DateTime.utc(2026, 5, 1, 12),
      updatedAt: DateTime.utc(2026, 5, 1, 12),
    );
  }

  test('returns created only for the first pending repair upsert', () async {
    final first = await repo.upsertPendingRepair(repair());
    final duplicate = await repo.upsertPendingRepair(
      repair().copyWith(updatedAt: DateTime.utc(2026, 5, 1, 12, 1)),
    );

    expect(first.created, isTrue);
    expect(duplicate.created, isFalse);
    expect(duplicate.repair.triggerCount, 1);
    expect(duplicate.repair.updatedAt, DateTime.utc(2026, 5, 1, 12, 1));
  });

  test(
    'loads pending repairs by group and epoch then finalizes safely',
    () async {
      await repo.upsertPendingRepair(repair());
      await repo.upsertPendingRepair(
        repair(id: 'offline:group-1:msg-2', messageId: 'msg-2', keyEpoch: 3),
      );

      final pendingEpoch2 = await repo.getPendingRepairsForGroupEpoch(
        groupId: 'group-1',
        keyEpoch: 2,
      );
      expect(pendingEpoch2, hasLength(1));
      expect(pendingEpoch2.single.messageId, 'msg-1');

      await repo.recordAttempt(
        'offline:group-1:msg-1',
        lastError: 'missing key',
      );
      await repo.finalizeUndecryptable(
        'offline:group-1:msg-1',
        lastError: 'missing key',
      );

      final finalized = await repo.getRepair('offline:group-1:msg-1');
      expect(finalized!.attempts, 1);
      expect(finalized.status, groupPendingKeyRepairStatusUndecryptable);
      expect(finalized.finalizedAt, isNotNull);
    },
  );
}
