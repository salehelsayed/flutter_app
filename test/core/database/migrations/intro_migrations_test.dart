import 'package:flutter_app/core/database/migrations/019_introductions_table.dart';
import 'package:flutter_app/core/database/migrations/022_introduction_keys.dart';
import 'package:flutter_app/core/database/migrations/023_introduction_recipient_keys.dart';
import 'package:flutter_app/core/database/migrations/025_introduction_already_connected_status.dart';
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
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> columnNames(String table) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    return columns.map((column) => column['name'] as String).toList();
  }

  Future<List<String>> indexNames(String table) async {
    final indexes = await db.rawQuery('PRAGMA index_list($table)');
    return indexes.map((index) => index['name'] as String).toList();
  }

  Map<String, Object?> makeIntroductionRow({
    String id = 'intro-1',
    String introducerId = 'peer-a',
    String recipientId = 'peer-b',
    String introducedId = 'peer-c',
    String recipientStatus = 'pending',
    String introducedStatus = 'pending',
    String status = 'pending',
    String createdAt = '2026-04-03T10:00:00.000Z',
    String? introducedPublicKey,
    String? introducedMlKemPublicKey,
    String? recipientPublicKey,
    String? recipientMlKemPublicKey,
    bool includeKeyColumns = false,
  }) {
    final row = <String, Object?>{
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
    };

    if (includeKeyColumns) {
      row.addAll({
        'introduced_public_key': introducedPublicKey,
        'introduced_ml_kem_public_key': introducedMlKemPublicKey,
        'recipient_public_key': recipientPublicKey,
        'recipient_ml_kem_public_key': recipientMlKemPublicKey,
      });
    }

    return row;
  }

  Map<String, Object?> makeOutboxRow({
    String deliveryId = 'delivery-1',
    String introductionId = 'intro-1',
    String action = 'send',
    String deliveryStatus = 'failed',
    String deliveryPath = 'relay',
    String createdAt = '2026-04-03T10:00:00.000Z',
    String updatedAt = '2026-04-03T10:00:00.000Z',
  }) {
    return {
      'delivery_id': deliveryId,
      'introduction_id': introductionId,
      'action': action,
      'target_peer_id': 'peer-target',
      'sender_peer_id': 'peer-source',
      'raw_envelope': '{"action":"$action"}',
      'delivery_status': deliveryStatus,
      'delivery_path': deliveryPath,
      'last_error': deliveryStatus == 'failed' ? 'network' : null,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  group('Migration 019: introductions', () {
    test('creates the introductions table with expected indexes', () async {
      await runIntroductionsTableMigration(db);

      expect(
        await columnNames('introductions'),
        containsAll([
          'id',
          'introducer_id',
          'recipient_id',
          'introduced_id',
          'recipient_status',
          'introduced_status',
          'status',
          'created_at',
        ]),
      );
      expect(
        await indexNames('introductions'),
        containsAll([
          'idx_introductions_recipient',
          'idx_introductions_introduced',
          'idx_introductions_introducer',
        ]),
      );

      await db.insert('introductions', makeIntroductionRow());

      final rows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-1'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['status'], 'pending');
      expect(rows.single['recipient_username'], 'Bob');
    });

    test('is idempotent when rerun', () async {
      await runIntroductionsTableMigration(db);
      await runIntroductionsTableMigration(db);

      expect(await columnNames('introductions'), contains('id'));
      expect(
        await indexNames('introductions'),
        contains('idx_introductions_recipient'),
      );
    });
  });

  group('Migrations 022 and 023: introduction key columns', () {
    test('add introduced and recipient key columns', () async {
      await runIntroductionsTableMigration(db);
      await runIntroductionKeysMigration(db);
      await runIntroductionRecipientKeysMigration(db);

      expect(
        await columnNames('introductions'),
        containsAll([
          'introduced_public_key',
          'introduced_ml_kem_public_key',
          'recipient_public_key',
          'recipient_ml_kem_public_key',
        ]),
      );

      await db.insert(
        'introductions',
        makeIntroductionRow(
          includeKeyColumns: true,
          introducedPublicKey: 'intro-pk',
          introducedMlKemPublicKey: 'intro-mlkem',
          recipientPublicKey: 'recipient-pk',
          recipientMlKemPublicKey: 'recipient-mlkem',
        ),
      );

      final rows = await db.query(
        'introductions',
        where: 'id = ?',
        whereArgs: ['intro-1'],
      );
      expect(rows.single['introduced_public_key'], 'intro-pk');
      expect(rows.single['recipient_public_key'], 'recipient-pk');
    });
  });

  group('Migration 025: already_connected rebuild', () {
    test(
      'preserves existing key data and allows already_connected status',
      () async {
        await runIntroductionsTableMigration(db);
        await runIntroductionKeysMigration(db);
        await runIntroductionRecipientKeysMigration(db);
        await db.insert(
          'introductions',
          makeIntroductionRow(
            includeKeyColumns: true,
            introducedPublicKey: 'intro-pk',
            introducedMlKemPublicKey: 'intro-mlkem',
            recipientPublicKey: 'recipient-pk',
            recipientMlKemPublicKey: 'recipient-mlkem',
          ),
        );

        await runIntroductionAlreadyConnectedMigration(db);

        expect(
          await columnNames('introductions'),
          containsAll([
            'introduced_public_key',
            'introduced_ml_kem_public_key',
            'recipient_public_key',
            'recipient_ml_kem_public_key',
          ]),
        );
        expect(
          await indexNames('introductions'),
          containsAll([
            'idx_introductions_recipient',
            'idx_introductions_introduced',
            'idx_introductions_introducer',
          ]),
        );

        await db.update(
          'introductions',
          {'status': 'already_connected'},
          where: 'id = ?',
          whereArgs: ['intro-1'],
        );

        final rows = await db.query(
          'introductions',
          where: 'id = ?',
          whereArgs: ['intro-1'],
        );
        expect(rows, hasLength(1));
        expect(rows.single['status'], 'already_connected');
        expect(rows.single['introduced_public_key'], 'intro-pk');
        expect(rows.single['recipient_public_key'], 'recipient-pk');
      },
    );
  });

  group('Migration 047: introduction_outbox_deliveries', () {
    test('creates the outbox table with retry indexes', () async {
      await runIntroductionOutboxMigration(db);

      expect(
        await columnNames('introduction_outbox_deliveries'),
        containsAll([
          'delivery_id',
          'introduction_id',
          'action',
          'target_peer_id',
          'sender_peer_id',
          'raw_envelope',
          'delivery_status',
          'delivery_path',
          'created_at',
          'updated_at',
        ]),
      );
      expect(
        await indexNames('introduction_outbox_deliveries'),
        containsAll([
          'idx_intro_outbox_retry',
          'idx_intro_outbox_intro',
          'idx_intro_outbox_target',
        ]),
      );

      await db.insert(
        'introduction_outbox_deliveries',
        makeOutboxRow(deliveryStatus: 'sent', deliveryPath: 'direct'),
      );

      final rows = await db.query(
        'introduction_outbox_deliveries',
        where: 'delivery_id = ?',
        whereArgs: ['delivery-1'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['delivery_status'], 'sent');
      expect(rows.single['delivery_path'], 'direct');
    });

    test('is idempotent when rerun', () async {
      await runIntroductionOutboxMigration(db);
      await runIntroductionOutboxMigration(db);

      expect(
        await indexNames('introduction_outbox_deliveries'),
        contains('idx_intro_outbox_retry'),
      );
    });
  });
}
