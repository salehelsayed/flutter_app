import 'dart:io';

import 'package:flutter_app/core/database/helpers/group_history_gap_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/065_group_history_gap_repairs.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupHistoryGapRepairsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> repairRow({
    String groupId = 'group-1',
    String gapId = 'gap-1',
    String status = groupHistoryGapRepairStatusDetected,
    String updatedAt = '2026-05-01T12:00:00.000Z',
    String attemptedJson = '[]',
    String repairedJson = '[]',
    String? failureReason,
    String? repairedAt,
    String? failedAt,
  }) {
    return {
      'group_id': groupId,
      'gap_id': gapId,
      'missing_after_message_id': 'msg-before',
      'missing_before_message_id': 'msg-after',
      'expected_range_hash': 'range-hash',
      'expected_head_message_id': 'msg-after',
      'candidate_source_peer_ids_json': '["peer-bad","peer-good"]',
      'attempted_source_peer_ids_json': attemptedJson,
      'repaired_message_ids_json': repairedJson,
      'status': status,
      'failure_reason': failureReason,
      'created_at': '2026-05-01T12:00:00.000Z',
      'updated_at': updatedAt,
      'repaired_at': repairedAt,
      'failed_at': failedAt,
    };
  }

  GroupHistoryGapRepairRepositoryImpl repo() {
    return GroupHistoryGapRepairRepositoryImpl(
      dbUpsertGroupHistoryGapRepair: (row) =>
          dbUpsertGroupHistoryGapRepair(db, row),
      dbSaveGroupHistoryGapRepair: (row) =>
          dbSaveGroupHistoryGapRepair(db, row),
      dbLoadGroupHistoryGapRepair: ({required groupId, required gapId}) =>
          dbLoadGroupHistoryGapRepair(db, groupId: groupId, gapId: gapId),
      dbLoadLatestGroupHistoryGapRepair: ({required groupId}) =>
          dbLoadLatestGroupHistoryGapRepair(db, groupId: groupId),
      dbLoadVisibleGroupHistoryGapRepairs: ({required groupId, limit = 20}) =>
          dbLoadVisibleGroupHistoryGapRepairs(
            db,
            groupId: groupId,
            limit: limit,
          ),
    );
  }

  test(
    'PREREQ-HISTORY-GAP-REPAIR stores detected lifecycle idempotently by group and gap',
    () async {
      final created = await dbUpsertGroupHistoryGapRepair(db, repairRow());
      final duplicate = await dbUpsertGroupHistoryGapRepair(
        db,
        repairRow(updatedAt: '2026-05-01T12:01:00.000Z'),
      );

      expect(created, isTrue);
      expect(duplicate, isFalse);

      final loaded = await dbLoadGroupHistoryGapRepair(
        db,
        groupId: 'group-1',
        gapId: 'gap-1',
      );
      expect(loaded, isNotNull);
      expect(loaded!['status'], groupHistoryGapRepairStatusDetected);
      expect(loaded['updated_at'], '2026-05-01T12:01:00.000Z');

      final visible = await dbLoadVisibleGroupHistoryGapRepairs(
        db,
        groupId: 'group-1',
      );
      expect(visible, hasLength(1));
    },
  );

  test(
    'PREREQ-HISTORY-GAP-REPAIR records repairing attempts then repaired terminal state',
    () async {
      final repository = repo();
      await repository.upsertDetected(
        GroupHistoryGapRepair.fromMap(repairRow()),
      );

      await repository.markRepairing(groupId: 'group-1', gapId: 'gap-1');
      await repository.recordAttempt(
        groupId: 'group-1',
        gapId: 'gap-1',
        sourcePeerId: 'peer-bad',
        lastError: 'hash_mismatch',
      );
      await repository.markRepaired(
        groupId: 'group-1',
        gapId: 'gap-1',
        repairedMessageIds: const ['msg-gap-1', 'msg-gap-2'],
      );

      final loaded = await repository.getRepair(
        groupId: 'group-1',
        gapId: 'gap-1',
      );
      expect(loaded!.status, groupHistoryGapRepairStatusRepaired);
      expect(loaded.attemptedSourcePeerIds, contains('peer-bad'));
      expect(loaded.repairedMessageIds, ['msg-gap-1', 'msg-gap-2']);
      expect(loaded.failureReason, isNull);
      expect(loaded.repairedAt, isNotNull);
    },
  );

  test(
    'PREREQ-HISTORY-GAP-REPAIR preserves lifecycle rows across database reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'group_history_gap_repairs_',
      );
      final path = '${dir.path}/repairs.db';
      var persistentDb = await databaseFactoryFfi.openDatabase(path);
      var persistentDbClosed = false;

      try {
        await runGroupHistoryGapRepairsMigration(persistentDb);
        await dbUpsertGroupHistoryGapRepair(persistentDb, repairRow());

        await persistentDb.close();
        persistentDbClosed = true;

        persistentDb = await databaseFactoryFfi.openDatabase(path);
        persistentDbClosed = false;

        final loaded = await dbLoadGroupHistoryGapRepair(
          persistentDb,
          groupId: 'group-1',
          gapId: 'gap-1',
        );
        expect(loaded, isNotNull);
        expect(loaded!['status'], groupHistoryGapRepairStatusDetected);
        expect(loaded['expected_range_hash'], 'range-hash');
      } finally {
        if (!persistentDbClosed) {
          await persistentDb.close();
        }
        await dir.delete(recursive: true);
      }
    },
  );
}
