import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/013_waveform_column.dart';

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

  group('Migration 013: waveform column', () {
    Future<void> runPrerequisites() async {
      await runIdentityTableMigration(db);
      await runMessagesTableMigration(db);
      await runMediaAttachmentsMigration(db);
    }

    test('adds waveform column to media_attachments', () async {
      await runPrerequisites();
      await runWaveformColumnMigration(db);

      final columns =
          await db.rawQuery('PRAGMA table_info(media_attachments)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('waveform'));
    });

    test('column is nullable (insert with null)', () async {
      await runPrerequisites();
      await runWaveformColumnMigration(db);

      await db.insert('media_attachments', {
        'id': 'att-null-wf',
        'message_id': 'msg-001',
        'mime': 'audio/mp4',
        'size': 5000,
        'media_type': 'audio',
        'download_status': 'done',
        'created_at': '2026-02-26T10:00:00.000Z',
        'waveform': null,
      });

      final rows = await db.query('media_attachments',
          where: 'id = ?', whereArgs: ['att-null-wf']);
      expect(rows[0]['waveform'], isNull);
    });

    test('can store waveform JSON string', () async {
      await runPrerequisites();
      await runWaveformColumnMigration(db);

      const wfJson = '[0.1,0.5,0.8,0.3]';
      await db.insert('media_attachments', {
        'id': 'att-with-wf',
        'message_id': 'msg-002',
        'mime': 'audio/mp4',
        'size': 8000,
        'media_type': 'audio',
        'download_status': 'done',
        'created_at': '2026-02-26T10:00:00.000Z',
        'waveform': wfJson,
      });

      final rows = await db.query('media_attachments',
          where: 'id = ?', whereArgs: ['att-with-wf']);
      expect(rows[0]['waveform'], wfJson);
    });

    test('existing rows get NULL waveform', () async {
      await runPrerequisites();

      // Insert a row BEFORE running 013
      await db.insert('media_attachments', {
        'id': 'att-existing',
        'message_id': 'msg-003',
        'mime': 'image/jpeg',
        'size': 2000,
        'media_type': 'image',
        'download_status': 'done',
        'created_at': '2026-02-20T10:00:00.000Z',
      });

      await runWaveformColumnMigration(db);

      final rows = await db.query('media_attachments',
          where: 'id = ?', whereArgs: ['att-existing']);
      expect(rows[0]['waveform'], isNull);
    });

    test('idempotent: running twice does not throw', () async {
      await runPrerequisites();
      await runWaveformColumnMigration(db);
      // Running again should not throw
      await runWaveformColumnMigration(db);

      final columns =
          await db.rawQuery('PRAGMA table_info(media_attachments)');
      final columnNames =
          columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('waveform'));
    });

    test('migration handles missing media_attachments table', () async {
      // Do NOT run prerequisites — table does not exist
      expect(
        () => runWaveformColumnMigration(db),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
