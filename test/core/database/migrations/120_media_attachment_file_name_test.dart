// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/120_media_attachment_file_name.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late Database database;
  const legacyRow = <String, Object?>{
    'id': 'img-1',
    'message_id': 'msg-1',
    'mime': 'image/jpeg',
    'size': 10,
    'media_type': 'image',
    'download_status': 'done',
    'created_at': '2026-10-10T10:00:00.000Z',
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('file-name-120-');
    database = await databaseFactoryFfi.openDatabase('${directory.path}/db');
    await database.execute('''CREATE TABLE media_attachments (
      id TEXT PRIMARY KEY, message_id TEXT NOT NULL, mime TEXT NOT NULL,
      size INTEGER NOT NULL, media_type TEXT NOT NULL,
      download_status TEXT NOT NULL, created_at TEXT NOT NULL
    )''');
    await database.insert('media_attachments', legacyRow);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('adds a nullable file_name; existing rows keep NULL', () async {
    await runMediaAttachmentFileNameMigration(database);
    final row = (await database.query('media_attachments')).single;
    expect(row, {...legacyRow, 'file_name': null});
  });

  test('is idempotent', () async {
    await runMediaAttachmentFileNameMigration(database);
    await runMediaAttachmentFileNameMigration(database);
    final columns = await database.rawQuery(
      'PRAGMA table_info(media_attachments)',
    );
    expect(columns.where((c) => c['name'] == 'file_name'), hasLength(1));
  });

  test('a document row stores and restores its name after reopen', () async {
    await runMediaAttachmentFileNameMigration(database);
    await database.insert('media_attachments', {
      ...legacyRow,
      'id': 'pdf-1',
      'mime': 'application/pdf',
      'media_type': 'file',
      'file_name': 'Invoice.pdf',
    });
    await database.close();
    database = await databaseFactoryFfi.openDatabase('${directory.path}/db');
    final row = (await database.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: ['pdf-1'],
    )).single;
    expect(MediaAttachment.fromMap(row).fileName, 'Invoice.pdf');
  });

  test('v120 is the last entry of both production registries', () {
    expect(currentIdentityDatabaseVersion, 120);
    for (final registry in [
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      expect(registry.where((e) => e.version == 120), hasLength(1));
      expect(registry.last.version, 120);
      expect(registry.last.name, '120_media_attachment_file_name');
      expect(registry.last.run, same(runMediaAttachmentFileNameMigration));
    }
  });
}
