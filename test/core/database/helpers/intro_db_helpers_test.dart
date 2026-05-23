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
    String recipientStatus = 'pending',
    String introducedStatus = 'pending',
  }) {
    return {
      'id': id,
      'introducer_id': introducerId,
      'recipient_id': recipientId,
      'introduced_id': introducedId,
      'introducer_username': 'Alice',
      'recipient_username': 'Bob',
      'introduced_username': 'Casey',
      'recipient_status': recipientStatus,
      'introduced_status': introducedStatus,
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
    String? transportSenderPeerId,
  }) {
    return {
      'response_key': responseKey,
      'introduction_id': introductionId,
      'action': action,
      'responder_id': responderId,
      'transport_sender_peer_id': transportSenderPeerId ?? responderId,
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

  group('dbUpdateRecipientStatus and dbUpdateIntroducedStatus', () {
    test('only updates a pending party on a pending intro', () async {
      await dbInsertIntroduction(
        db,
        makeIntroductionRow(
          id: 'intro-guarded-update',
          status: 'pending',
          createdAt: '2026-04-03T11:00:00.000Z',
        ),
      );

      await dbUpdateRecipientStatus(
        db,
        'intro-guarded-update',
        'accepted',
        '2026-04-03T11:01:00.000Z',
      );

      final rows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-guarded-update'],
      );
      expect(rows.single['recipient_status'], 'accepted');
      expect(rows.single['recipient_responded_at'], '2026-04-03T11:01:00.000Z');
    });

    test('does not overwrite an already answered party', () async {
      await dbInsertIntroduction(
        db,
        makeIntroductionRow(
          id: 'intro-party-answered',
          status: 'pending',
          recipientStatus: 'accepted',
          createdAt: '2026-04-03T11:00:00.000Z',
        ),
      );

      await dbUpdateRecipientStatus(
        db,
        'intro-party-answered',
        'passed',
        '2026-04-03T11:01:00.000Z',
      );

      final rows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-party-answered'],
      );
      expect(rows.single['recipient_status'], 'accepted');
      expect(rows.single['recipient_responded_at'], isNull);
    });

    test('does not overwrite terminal intro state', () async {
      await dbInsertIntroduction(
        db,
        makeIntroductionRow(
          id: 'intro-terminal-update',
          status: 'mutual_accepted',
          recipientStatus: 'accepted',
          introducedStatus: 'accepted',
          createdAt: '2026-04-03T11:00:00.000Z',
        ),
      );

      await dbUpdateIntroducedStatus(
        db,
        'intro-terminal-update',
        'passed',
        '2026-04-03T11:01:00.000Z',
      );

      final rows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-terminal-update'],
      );
      expect(rows.single['introduced_status'], 'accepted');
      expect(rows.single['introduced_responded_at'], isNull);
      expect(rows.single['status'], 'mutual_accepted');
    });
  });

  group('dbUpdateOverallStatus', () {
    test('updates a pending intro', () async {
      await dbInsertIntroduction(
        db,
        makeIntroductionRow(
          id: 'intro-overall-pending',
          status: 'pending',
          recipientStatus: 'passed',
          createdAt: '2026-04-03T11:00:00.000Z',
        ),
      );

      await dbUpdateOverallStatus(db, 'intro-overall-pending', 'passed');

      final rows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-overall-pending'],
      );
      expect(rows.single['status'], 'passed');
    });

    test('does not overwrite terminal intro state', () async {
      await dbInsertIntroduction(
        db,
        makeIntroductionRow(
          id: 'intro-overall-terminal',
          status: 'mutual_accepted',
          recipientStatus: 'accepted',
          introducedStatus: 'accepted',
          createdAt: '2026-04-03T11:00:00.000Z',
        ),
      );

      await dbUpdateOverallStatus(db, 'intro-overall-terminal', 'passed');

      final rows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-overall-terminal'],
      );
      expect(rows.single['status'], 'mutual_accepted');
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

  group('dbSaveIntroductionWithOutboxDeliveries', () {
    test('commits the intro row and both outbound rows together', () async {
      final introRow = makeIntroductionRow(
        id: 'intro-atomic',
        status: 'pending',
        createdAt: '2026-04-03T11:00:00.000Z',
      );
      final recipientDelivery = makeOutboxRow(
        deliveryId: 'delivery-recipient',
        introductionId: 'intro-atomic',
        deliveryStatus: 'sending',
        deliveryPath: 'pending',
        createdAt: '2026-04-03T11:00:00.000Z',
        updatedAt: '2026-04-03T11:00:00.000Z',
      );
      final introducedDelivery = makeOutboxRow(
        deliveryId: 'delivery-introduced',
        introductionId: 'intro-atomic',
        deliveryStatus: 'sending',
        deliveryPath: 'pending',
        createdAt: '2026-04-03T11:00:00.000Z',
        updatedAt: '2026-04-03T11:00:00.000Z',
      );

      await dbSaveIntroductionWithOutboxDeliveries(db, introRow, [
        recipientDelivery,
        introducedDelivery,
      ]);

      final introRows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-atomic'],
      );
      final outboxRows =
          await dbLoadIntroductionOutboxDeliveriesForIntroduction(
            db,
            'intro-atomic',
          );

      expect(introRows, hasLength(1));
      expect(outboxRows.map((row) => row['delivery_id']).toList(), [
        'delivery-introduced',
        'delivery-recipient',
      ]);
    });

    test('rolls back the intro row if any outbound row fails', () async {
      final introRow = makeIntroductionRow(
        id: 'intro-rollback',
        status: 'pending',
        createdAt: '2026-04-03T11:00:00.000Z',
      );
      final firstDelivery = makeOutboxRow(
        deliveryId: 'delivery-first',
        introductionId: 'intro-rollback',
        deliveryStatus: 'sending',
        deliveryPath: 'pending',
        createdAt: '2026-04-03T11:00:00.000Z',
        updatedAt: '2026-04-03T11:00:00.000Z',
      );
      final invalidDelivery = makeOutboxRow(
        deliveryId: 'delivery-invalid',
        introductionId: 'intro-rollback',
        deliveryStatus: 'sending',
        deliveryPath: 'pending',
        createdAt: '2026-04-03T11:00:00.000Z',
        updatedAt: '2026-04-03T11:00:00.000Z',
      )..remove('raw_envelope');

      await expectLater(
        dbSaveIntroductionWithOutboxDeliveries(db, introRow, [
          firstDelivery,
          invalidDelivery,
        ]),
        throwsA(isA<DatabaseException>()),
      );

      final introRows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-rollback'],
      );
      final outboxRows =
          await dbLoadIntroductionOutboxDeliveriesForIntroduction(
            db,
            'intro-rollback',
          );

      expect(introRows, isEmpty);
      expect(outboxRows, isEmpty);
    });
  });

  group('dbReplaceIntroductionWithPendingResponseMigration', () {
    test(
      'replaces old intro and rekeys staged responses to the new intro id',
      () async {
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-old',
            status: 'pending',
            createdAt: '2026-04-03T09:00:00.000Z',
          ),
        );
        await dbUpsertPendingIntroductionResponse(
          db,
          makePendingResponseRow(
            responseKey: 'intro-old::peer-c::accept',
            introductionId: 'intro-old',
            createdAt: '2026-04-03T09:05:00.000Z',
            responderId: 'peer-c',
          ),
        );
        await dbUpsertIntroductionOutboxDelivery(
          db,
          makeOutboxRow(
            deliveryId: 'delivery-old',
            introductionId: 'intro-old',
            deliveryStatus: 'sending',
            deliveryPath: 'relay',
            createdAt: '2026-04-03T09:00:00.000Z',
            updatedAt: '2026-04-03T09:00:00.000Z',
          ),
        );

        await dbReplaceIntroductionWithPendingResponseMigration(
          db,
          introductionRow: makeIntroductionRow(
            id: 'intro-new',
            status: 'pending',
            createdAt: '2026-04-03T10:00:00.000Z',
          ),
          deliveryRows: [
            makeOutboxRow(
              deliveryId: 'delivery-new',
              introductionId: 'intro-new',
              deliveryStatus: 'sending',
              deliveryPath: 'pending',
              createdAt: '2026-04-03T10:00:00.000Z',
              updatedAt: '2026-04-03T10:00:00.000Z',
            ),
          ],
          replacedIntroductionIds: ['intro-old'],
        );

        final oldIntroRows = await db.query(
          'introductions',
          where: 'id = ?',
          whereArgs: ['intro-old'],
        );
        final newIntroRows = await db.query(
          'introductions',
          where: 'id = ?',
          whereArgs: ['intro-new'],
        );
        final oldPendingRows = await dbLoadPendingIntroductionResponses(
          db,
          'intro-old',
        );
        final newPendingRows = await dbLoadPendingIntroductionResponses(
          db,
          'intro-new',
        );
        final oldOutboxRows =
            await dbLoadIntroductionOutboxDeliveriesForIntroduction(
              db,
              'intro-old',
            );
        final newOutboxRows =
            await dbLoadIntroductionOutboxDeliveriesForIntroduction(
              db,
              'intro-new',
            );

        expect(oldIntroRows, isEmpty);
        expect(newIntroRows, hasLength(1));
        expect(oldPendingRows, isEmpty);
        expect(
          newPendingRows.single['response_key'],
          'intro-new::peer-c::accept',
        );
        expect(newPendingRows.single['introduction_id'], 'intro-new');
        expect(oldOutboxRows, isEmpty);
        expect(newOutboxRows.single['delivery_id'], 'delivery-new');
      },
    );

    test('rolls back replacement if a new outbound row fails', () async {
      await dbInsertIntroduction(
        db,
        makeIntroductionRow(
          id: 'intro-old-rollback',
          status: 'pending',
          createdAt: '2026-04-03T09:00:00.000Z',
        ),
      );
      await dbUpsertPendingIntroductionResponse(
        db,
        makePendingResponseRow(
          responseKey: 'intro-old-rollback::peer-c::accept',
          introductionId: 'intro-old-rollback',
          createdAt: '2026-04-03T09:05:00.000Z',
          responderId: 'peer-c',
        ),
      );
      await dbUpsertIntroductionOutboxDelivery(
        db,
        makeOutboxRow(
          deliveryId: 'delivery-old-rollback',
          introductionId: 'intro-old-rollback',
          deliveryStatus: 'sending',
          deliveryPath: 'relay',
          createdAt: '2026-04-03T09:00:00.000Z',
          updatedAt: '2026-04-03T09:00:00.000Z',
        ),
      );
      final invalidDelivery = makeOutboxRow(
        deliveryId: 'delivery-invalid-replacement',
        introductionId: 'intro-new-rollback',
        deliveryStatus: 'sending',
        deliveryPath: 'pending',
        createdAt: '2026-04-03T10:00:00.000Z',
        updatedAt: '2026-04-03T10:00:00.000Z',
      )..remove('raw_envelope');

      await expectLater(
        dbReplaceIntroductionWithPendingResponseMigration(
          db,
          introductionRow: makeIntroductionRow(
            id: 'intro-new-rollback',
            status: 'pending',
            createdAt: '2026-04-03T10:00:00.000Z',
          ),
          deliveryRows: [invalidDelivery],
          replacedIntroductionIds: ['intro-old-rollback'],
        ),
        throwsA(isA<DatabaseException>()),
      );

      final oldIntroRows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-old-rollback'],
      );
      final newIntroRows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-new-rollback'],
      );
      final oldPendingRows = await dbLoadPendingIntroductionResponses(
        db,
        'intro-old-rollback',
      );
      final oldOutboxRows =
          await dbLoadIntroductionOutboxDeliveriesForIntroduction(
            db,
            'intro-old-rollback',
          );

      expect(oldIntroRows, hasLength(1));
      expect(newIntroRows, isEmpty);
      expect(
        oldPendingRows.single['response_key'],
        'intro-old-rollback::peer-c::accept',
      );
      expect(oldOutboxRows.single['delivery_id'], 'delivery-old-rollback');
    });
  });

  group('dbSaveIntroductionResponseWithOutboxDeliveries', () {
    test(
      'commits the local response and accept fan-out rows together',
      () async {
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-accept',
            status: 'pending',
            createdAt: '2026-05-22T11:00:00.000Z',
          ),
        );
        final introducerDelivery = makeOutboxRow(
          deliveryId: 'delivery-introducer',
          introductionId: 'intro-accept',
          deliveryStatus: 'sending',
          deliveryPath: 'pending',
          createdAt: '2026-04-03T11:01:00.000Z',
          updatedAt: '2026-04-03T11:01:00.000Z',
        );
        final otherPartyDelivery = makeOutboxRow(
          deliveryId: 'delivery-other-party',
          introductionId: 'intro-accept',
          deliveryStatus: 'sending',
          deliveryPath: 'pending',
          createdAt: '2026-04-03T11:01:00.000Z',
          updatedAt: '2026-04-03T11:01:00.000Z',
        );

        await dbSaveIntroductionResponseWithOutboxDeliveries(
          db,
          introductionId: 'intro-accept',
          isRecipient: true,
          responseStatus: 'accepted',
          respondedAt: '2026-04-03T11:01:00.000Z',
          overallStatus: 'pending',
          deliveryRows: [introducerDelivery, otherPartyDelivery],
        );

        final introRows = await db.query(
          'introductions',
          where: 'id = ?',
          whereArgs: ['intro-accept'],
        );
        final outboxRows =
            await dbLoadIntroductionOutboxDeliveriesForIntroduction(
              db,
              'intro-accept',
            );

        expect(introRows.single['recipient_status'], 'accepted');
        expect(
          introRows.single['recipient_responded_at'],
          '2026-04-03T11:01:00.000Z',
        );
        expect(introRows.single['introduced_status'], 'pending');
        expect(introRows.single['status'], 'pending');
        expect(outboxRows.map((row) => row['delivery_id']).toSet(), {
          'delivery-introducer',
          'delivery-other-party',
        });
      },
    );

    test(
      'derives overall status from the current row inside the transaction',
      () async {
        await dbInsertIntroduction(
          db,
          makeIntroductionRow(
            id: 'intro-accept-race',
            status: 'pending',
            recipientStatus: 'accepted',
            createdAt: '2026-04-03T11:00:00.000Z',
          ),
        );

        final didSave = await dbSaveIntroductionResponseWithOutboxDeliveries(
          db,
          introductionId: 'intro-accept-race',
          isRecipient: false,
          responseStatus: 'accepted',
          respondedAt: '2026-04-03T11:01:00.000Z',
          overallStatus: 'pending',
          deliveryRows: const [],
        );

        final introRows = await db.query(
          'introductions',
          where: 'id = ?',
          whereArgs: ['intro-accept-race'],
        );

        expect(didSave, isTrue);
        expect(introRows.single['recipient_status'], 'accepted');
        expect(introRows.single['introduced_status'], 'accepted');
        expect(introRows.single['status'], 'mutual_accepted');
      },
    );

    test('does not stage fan-out rows when the intro is terminal', () async {
      await dbInsertIntroduction(
        db,
        makeIntroductionRow(
          id: 'intro-accept-terminal',
          status: 'passed',
          recipientStatus: 'passed',
          introducedStatus: 'accepted',
          createdAt: '2026-04-03T11:00:00.000Z',
        ),
      );
      final delivery = makeOutboxRow(
        deliveryId: 'delivery-terminal',
        introductionId: 'intro-accept-terminal',
        deliveryStatus: 'sending',
        deliveryPath: 'pending',
        createdAt: '2026-04-03T11:01:00.000Z',
        updatedAt: '2026-04-03T11:01:00.000Z',
      );

      final didSave = await dbSaveIntroductionResponseWithOutboxDeliveries(
        db,
        introductionId: 'intro-accept-terminal',
        isRecipient: true,
        responseStatus: 'accepted',
        respondedAt: '2026-04-03T11:01:00.000Z',
        overallStatus: 'mutual_accepted',
        deliveryRows: [delivery],
      );

      final introRows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-accept-terminal'],
      );
      final outboxRows =
          await dbLoadIntroductionOutboxDeliveriesForIntroduction(
            db,
            'intro-accept-terminal',
          );

      expect(didSave, isFalse);
      expect(introRows.single['recipient_status'], 'passed');
      expect(introRows.single['status'], 'passed');
      expect(outboxRows, isEmpty);
    });

    test('rolls back the local response if any fan-out row fails', () async {
      await dbInsertIntroduction(
        db,
        makeIntroductionRow(
          id: 'intro-accept-rollback',
          status: 'pending',
          createdAt: '2026-04-03T11:00:00.000Z',
        ),
      );
      final firstDelivery = makeOutboxRow(
        deliveryId: 'delivery-first',
        introductionId: 'intro-accept-rollback',
        deliveryStatus: 'sending',
        deliveryPath: 'pending',
        createdAt: '2026-04-03T11:01:00.000Z',
        updatedAt: '2026-04-03T11:01:00.000Z',
      );
      final invalidDelivery = makeOutboxRow(
        deliveryId: 'delivery-invalid',
        introductionId: 'intro-accept-rollback',
        deliveryStatus: 'sending',
        deliveryPath: 'pending',
        createdAt: '2026-04-03T11:01:00.000Z',
        updatedAt: '2026-04-03T11:01:00.000Z',
      )..remove('raw_envelope');

      await expectLater(
        dbSaveIntroductionResponseWithOutboxDeliveries(
          db,
          introductionId: 'intro-accept-rollback',
          isRecipient: true,
          responseStatus: 'accepted',
          respondedAt: '2026-04-03T11:01:00.000Z',
          overallStatus: 'pending',
          deliveryRows: [firstDelivery, invalidDelivery],
        ),
        throwsA(isA<DatabaseException>()),
      );

      final introRows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-accept-rollback'],
      );
      final outboxRows =
          await dbLoadIntroductionOutboxDeliveriesForIntroduction(
            db,
            'intro-accept-rollback',
          );

      expect(introRows.single['recipient_status'], 'pending');
      expect(introRows.single['recipient_responded_at'], isNull);
      expect(introRows.single['status'], 'pending');
      expect(outboxRows, isEmpty);
    });
  });
}
