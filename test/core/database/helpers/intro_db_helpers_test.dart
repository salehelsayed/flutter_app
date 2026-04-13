import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_introduction_responses_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/019_introductions_table.dart';
import 'package:flutter_app/core/database/migrations/022_introduction_keys.dart';
import 'package:flutter_app/core/database/migrations/023_introduction_recipient_keys.dart';
import 'package:flutter_app/core/database/migrations/025_introduction_already_connected_status.dart';
import 'package:flutter_app/core/database/migrations/046_pending_introduction_responses.dart';
import 'package:flutter_app/core/database/migrations/047_introduction_outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIntroductionsTableMigration(db);
    await runIntroductionKeysMigration(db);
    await runIntroductionRecipientKeysMigration(db);
    await runIntroductionAlreadyConnectedMigration(db);
    await runPendingIntroductionResponsesMigration(db);
    await runIntroductionOutboxMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeIntroductionRow({
    required String id,
    required String status,
    required String createdAt,
    String introducerId = 'peer-a',
    String recipientId = 'peer-b',
    String introducedId = 'peer-c',
  }) {
    return {
      'id': id,
      'introducer_id': introducerId,
      'recipient_id': recipientId,
      'introduced_id': introducedId,
      'introducer_username': 'Alice',
      'recipient_username': 'Bob',
      'introduced_username': 'Casey',
      'recipient_status': 'pending',
      'introduced_status': 'pending',
      'status': status,
      'created_at': createdAt,
      'recipient_responded_at': null,
      'introduced_responded_at': null,
      'introduced_public_key': null,
      'introduced_ml_kem_public_key': null,
      'recipient_public_key': null,
      'recipient_ml_kem_public_key': null,
    };
  }

  Map<String, Object?> makePendingResponseRow({
    required String responseKey,
    required String createdAt,
    String introductionId = 'intro-1',
    String action = 'accept',
    String responderId = 'peer-b',
  }) {
    return {
      'response_key': responseKey,
      'introduction_id': introductionId,
      'action': action,
      'responder_id': responderId,
      'responder_username': 'Responder',
      'created_at': createdAt,
    };
  }

  Map<String, Object?> makeOutboxRow({
    required String deliveryId,
    required String deliveryStatus,
    required String deliveryPath,
    required String createdAt,
    required String updatedAt,
    String introductionId = 'intro-1',
  }) {
    return {
      'delivery_id': deliveryId,
      'introduction_id': introductionId,
      'action': 'send',
      'target_peer_id': 'peer-target',
      'sender_peer_id': 'peer-source',
      'raw_envelope': '{"action":"send"}',
      'delivery_status': deliveryStatus,
      'delivery_path': deliveryPath,
      'last_error': deliveryStatus == 'failed' ? 'network' : null,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  group('dbLoadPendingIntroductionsForUser', () {
    test(
      'includes already_connected rows for visibility and orders newest first',
      () async {
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-pending-recipient',
            status: 'pending',
            createdAt: '2026-04-03T10:00:00.000Z',
          ),
        );
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-pending-introduced',
            status: 'pending',
            createdAt: '2026-04-03T10:01:00.000Z',
            recipientId: 'peer-z',
            introducedId: 'peer-b',
          ),
        );
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-already-connected',
            status: 'already_connected',
            createdAt: '2026-04-03T10:02:00.000Z',
          ),
        );
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-passed',
            status: 'passed',
            createdAt: '2026-04-03T10:03:00.000Z',
          ),
        );

        final rows = await dbLoadPendingIntroductionsForUser(db, 'peer-b');

        expect(rows.map((row) => row['id']).toList(), [
          'intro-already-connected',
          'intro-pending-introduced',
          'intro-pending-recipient',
        ]);
      },
    );
  });

  group('dbCountPendingIntroductions', () {
    test(
      'counts only true pending rows across recipient and introduced roles',
      () async {
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-pending-recipient',
            status: 'pending',
            createdAt: '2026-04-03T10:00:00.000Z',
          ),
        );
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-pending-introduced',
            status: 'pending',
            createdAt: '2026-04-03T10:01:00.000Z',
            recipientId: 'peer-z',
            introducedId: 'peer-b',
          ),
        );
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-already-connected',
            status: 'already_connected',
            createdAt: '2026-04-03T10:02:00.000Z',
          ),
        );
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-mutual',
            status: 'mutual_accepted',
            createdAt: '2026-04-03T10:03:00.000Z',
          ),
        );

        final count = await dbCountPendingIntroductions(db, 'peer-b');

        expect(count, 2);
      },
    );
  });

  group('dbLoadPendingIntroductionResponses', () {
    test('orders replay rows by created_at then response_key', () async {
      await dbUpsertPendingIntroductionResponse(
        db,
        makePendingResponseRow(
          responseKey: 'intro-1::peer-c::accept',
          createdAt: '2026-04-03T10:01:00.000Z',
          responderId: 'peer-c',
        ),
      );
      await dbUpsertPendingIntroductionResponse(
        db,
        makePendingResponseRow(
          responseKey: 'intro-1::peer-b::pass',
          createdAt: '2026-04-03T10:00:00.000Z',
          action: 'pass',
          responderId: 'peer-b',
        ),
      );
      await dbUpsertPendingIntroductionResponse(
        db,
        makePendingResponseRow(
          responseKey: 'intro-1::peer-a::accept',
          createdAt: '2026-04-03T10:00:00.000Z',
          responderId: 'peer-a',
        ),
      );

      final rows = await dbLoadPendingIntroductionResponses(db, 'intro-1');

      expect(rows.map((row) => row['response_key']).toList(), [
        'intro-1::peer-a::accept',
        'intro-1::peer-b::pass',
        'intro-1::peer-c::accept',
      ]);
    });
  });

  group('dbLoadRetryableIntroductionOutboxDeliveries', () {
    test(
      'returns only failed stale sending or sent and delivered via inbox rows in created order',
      () async {
        await dbUpsertIntroductionOutboxDelivery(
          db,
          makeOutboxRow(
            deliveryId: 'delivery-failed',
            deliveryStatus: 'failed',
            deliveryPath: 'relay',
            createdAt: '2026-04-03T10:00:00.000Z',
            updatedAt: '2026-04-03T10:00:00.000Z',
          ),
        );
        await dbUpsertIntroductionOutboxDelivery(
          db,
          makeOutboxRow(
            deliveryId: 'delivery-sending-stale',
            deliveryStatus: 'sending',
            deliveryPath: 'direct',
            createdAt: '2026-04-03T10:01:00.000Z',
            updatedAt: '2026-04-03T10:05:00.000Z',
          ),
        );
        await dbUpsertIntroductionOutboxDelivery(
          db,
          makeOutboxRow(
            deliveryId: 'delivery-sent-stale',
            deliveryStatus: 'sent',
            deliveryPath: 'relay',
            createdAt: '2026-04-03T10:02:00.000Z',
            updatedAt: '2026-04-03T10:05:00.000Z',
          ),
        );
        await dbUpsertIntroductionOutboxDelivery(
          db,
          makeOutboxRow(
            deliveryId: 'delivery-delivered-inbox',
            deliveryStatus: 'delivered',
            deliveryPath: 'inbox',
            createdAt: '2026-04-03T10:03:00.000Z',
            updatedAt: '2026-04-03T10:20:00.000Z',
          ),
        );
        await dbUpsertIntroductionOutboxDelivery(
          db,
          makeOutboxRow(
            deliveryId: 'delivery-sending-recent',
            deliveryStatus: 'sending',
            deliveryPath: 'direct',
            createdAt: '2026-04-03T10:04:00.000Z',
            updatedAt: '2026-04-03T10:15:00.000Z',
          ),
        );
        await dbUpsertIntroductionOutboxDelivery(
          db,
          makeOutboxRow(
            deliveryId: 'delivery-sent-recent',
            deliveryStatus: 'sent',
            deliveryPath: 'relay',
            createdAt: '2026-04-03T10:05:00.000Z',
            updatedAt: '2026-04-03T10:15:00.000Z',
          ),
        );
        await dbUpsertIntroductionOutboxDelivery(
          db,
          makeOutboxRow(
            deliveryId: 'delivery-delivered-direct',
            deliveryStatus: 'delivered',
            deliveryPath: 'direct',
            createdAt: '2026-04-03T10:06:00.000Z',
            updatedAt: '2026-04-03T10:05:00.000Z',
          ),
        );

        final rows = await dbLoadRetryableIntroductionOutboxDeliveries(
          db,
          olderThan: '2026-04-03T10:10:00.000Z',
        );

        expect(rows.map((row) => row['delivery_id']).toList(), [
          'delivery-failed',
          'delivery-sending-stale',
          'delivery-sent-stale',
          'delivery-delivered-inbox',
        ]);
      },
    );
  });
}
