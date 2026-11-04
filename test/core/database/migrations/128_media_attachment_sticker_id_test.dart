// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/migrations/128_media_attachment_sticker_id.dart';
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
    'created_at': '2026-11-02T10:00:00.000Z',
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sticker-id-128-');
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

  test('adds a nullable sticker_id; existing rows keep NULL', () async {
    await runMediaAttachmentStickerIdMigration(database);
    final row = (await database.query('media_attachments')).single;
    expect(row, {...legacyRow, 'sticker_id': null});
  });

  test('is idempotent', () async {
    await runMediaAttachmentStickerIdMigration(database);
    await runMediaAttachmentStickerIdMigration(database);
    final columns = await database.rawQuery(
      'PRAGMA table_info(media_attachments)',
    );
    expect(columns.where((c) => c['name'] == 'sticker_id'), hasLength(1));
  });

  test('a sticker row restores its id after reopen', () async {
    await runMediaAttachmentStickerIdMigration(database);
    await database.insert('media_attachments', {
      ...legacyRow,
      'id': 'sticker-1',
      'mime': 'image/webp',
      'sticker_id': 'orbit_crew.planet.angry',
    });
    await database.close();
    database = await databaseFactoryFfi.openDatabase('${directory.path}/db');
    final row = (await database.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: ['sticker-1'],
    )).single;
    expect(MediaAttachment.fromMap(row).stickerId, 'orbit_crew.planet.angry');
  });

  test('v128 is the create and upgrade step before v129', () {
    for (final registry in [
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      expect(registry.where((e) => e.version == 128), hasLength(1));
      final entry = registry[registry.length - 2];
      expect(entry.version, 128);
      expect(entry.name, '128_media_attachment_sticker_id');
      expect(entry.run, same(runMediaAttachmentStickerIdMigration));
      expect(registry[registry.length - 3].version, 127);
    }
  });
}
