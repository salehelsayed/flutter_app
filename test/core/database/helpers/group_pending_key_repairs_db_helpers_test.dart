import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_pending_key_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/063_group_pending_key_repairs.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupPendingKeyRepairsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> repairRow({
    String id = 'offline:group-1:msg-1',
    String groupId = 'group-1',
    String messageId = 'msg-1',
    int keyEpoch = 2,
    String status = groupPendingKeyRepairStatusPendingKey,
    int triggerCount = 1,
    int attempts = 0,
    String? replayEnvelopeJson = '{"kind":"group_offline_replay"}',
    String updatedAt = '2026-05-01T12:00:00.000Z',
    String? finalizedAt,
  }) {
    return {
      'id': id,
      'group_id': groupId,
      'message_id': messageId,
      'sender_peer_id': 'peer-sender',
      'transport_peer_id': 'transport-sender',
      'payload_type': 'group_message',
      'key_epoch': keyEpoch,
      'replay_envelope_json': replayEnvelopeJson,
      'status': status,
      'trigger_count': triggerCount,
      'attempts': attempts,
      'last_error': null,
      'created_at': '2026-05-01T12:00:00.000Z',
      'updated_at': updatedAt,
      'finalized_at': finalizedAt,
    };
  }

  test('upserts pending repair idempotently and loads by epoch', () async {
    final created = await dbUpsertGroupPendingKeyRepair(db, repairRow());
    final duplicate = await dbUpsertGroupPendingKeyRepair(
      db,
      repairRow(updatedAt: '2026-05-01T12:01:00.000Z'),
    );

    expect(created, isTrue);
    expect(duplicate, isFalse);

    final loaded = await dbLoadGroupPendingKeyRepair(
      db,
      'offline:group-1:msg-1',
    );
    expect(loaded, isNotNull);
    expect(loaded!['trigger_count'], 1);
    expect(loaded['updated_at'], '2026-05-01T12:01:00.000Z');

    final pending = await dbLoadPendingGroupKeyRepairsForEpoch(
      db,
      groupId: 'group-1',
      keyEpoch: 2,
    );
    expect(pending, hasLength(1));
    expect(pending.single['message_id'], 'msg-1');
  });

  test('records attempts and finalizes idempotently', () async {
    await dbUpsertGroupPendingKeyRepair(db, repairRow());

    await dbRecordGroupPendingKeyRepairAttempt(
      db,
      'offline:group-1:msg-1',
      lastError: 'decrypt failed',
      updatedAt: '2026-05-01T12:02:00.000Z',
    );
    await dbFinalizeGroupPendingKeyRepair(
      db,
      'offline:group-1:msg-1',
      status: groupPendingKeyRepairStatusUndecryptable,
      lastError: 'decrypt failed',
      finalizedAt: '2026-05-01T12:03:00.000Z',
    );
    await dbFinalizeGroupPendingKeyRepair(
      db,
      'offline:group-1:msg-1',
      status: groupPendingKeyRepairStatusUndecryptable,
      lastError: 'second call ignored',
      finalizedAt: '2026-05-01T12:04:00.000Z',
    );

    final loaded = await dbLoadGroupPendingKeyRepair(
      db,
      'offline:group-1:msg-1',
    );
    expect(loaded!['attempts'], 1);
    expect(loaded['status'], groupPendingKeyRepairStatusUndecryptable);
    expect(loaded['last_error'], 'decrypt failed');
    expect(loaded['finalized_at'], '2026-05-01T12:03:00.000Z');
  });

  test('persists pending repair rows across database reopen', () async {
    final dir = await Directory.systemTemp.createTemp(
      'group_pending_key_repairs_',
    );
    final path = '${dir.path}/repairs.db';
    var persistentDb = await databaseFactoryFfi.openDatabase(path);
    var persistentDbClosed = false;

    try {
      await runGroupPendingKeyRepairsMigration(persistentDb);
      await dbUpsertGroupPendingKeyRepair(
        persistentDb,
        repairRow(
          id: 'offline:group-1:msg-restart',
          messageId: 'msg-restart',
          replayEnvelopeJson: '{"kind":"group_offline_replay","epoch":2}',
        ),
      );

      await persistentDb.close();
      persistentDbClosed = true;

      persistentDb = await databaseFactoryFfi.openDatabase(path);
      persistentDbClosed = false;

      final loaded = await dbLoadGroupPendingKeyRepair(
        persistentDb,
        'offline:group-1:msg-restart',
      );
      expect(loaded, isNotNull);
      expect(loaded!['message_id'], 'msg-restart');
      expect(loaded['status'], groupPendingKeyRepairStatusPendingKey);
      expect(
        loaded['replay_envelope_json'],
        '{"kind":"group_offline_replay","epoch":2}',
      );

      final pending = await dbLoadPendingGroupKeyRepairsForEpoch(
        persistentDb,
        groupId: 'group-1',
        keyEpoch: 2,
      );
      expect(pending.map((row) => row['message_id']), contains('msg-restart'));
    } finally {
      if (!persistentDbClosed) {
        await persistentDb.close();
      }
      await dir.delete(recursive: true);
    }
  });
}
