// ignore_for_file: file_names
import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _legacyAttachment = <String, Object?>{
  'media_id': 'media-1',
  'post_id': 'thought-1',
  'blob_id': 'blob-1',
  'kind': 'voice',
  'mime': 'audio/mp4',
  'size_bytes': 12,
  'position': 0,
  'download_status': 'done',
  'created_at': '2026-11-04T10:00:00.000Z',
};

const _legacyRecovery = <String, Object?>{
  'post_id': 'thought-1',
  'position': 0,
  'local_file_path': '/tmp/voice.m4a',
  'mime': 'audio/mp4',
  'kind': 'voice',
  'created_at': '2026-11-04T10:00:00.000Z',
};

Future<List<String>> _columns(Database db, String table) async =>
    (await db.rawQuery(
      'PRAGMA table_info($table)',
    )).map((column) => column['name'] as String).toList();

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late String path;

  Future<Database> open(int version) =>
      databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('post-media-caption-129-');
    path = '${dir.path}/db.sqlite';
  });

  tearDown(() => dir.delete(recursive: true));

  Future<Database> upgradedFrom128() async {
    final old = await open(128);
    await old.insert('post_media_attachments', _legacyAttachment);
    await old.insert('post_media_upload_recovery', _legacyRecovery);
    await old.close();
    return open(currentIdentityDatabaseVersion);
  }

  test(
    'upgrade adds a nullable caption to both tables; old rows keep NULL',
    () async {
      final db = await upgradedFrom128();
      addTearDown(db.close);

      expect(await _columns(db, 'post_media_attachments'), contains('caption'));
      expect(
        await _columns(db, 'post_media_upload_recovery'),
        contains('caption'),
      );
      final attachment = (await db.query('post_media_attachments')).single;
      expect({
        for (final key in _legacyAttachment.keys) key: attachment[key],
      }, _legacyAttachment);
      expect(attachment['caption'], isNull);
      final recovery = (await db.query('post_media_upload_recovery')).single;
      expect({
        for (final key in _legacyRecovery.keys) key: recovery[key],
      }, _legacyRecovery);
      expect(recovery['caption'], isNull);
    },
  );

  test('a fresh install has the caption column on both tables', () async {
    final db = await open(currentIdentityDatabaseVersion);
    addTearDown(db.close);

    expect(await _columns(db, 'post_media_attachments'), contains('caption'));
    expect(
      await _columns(db, 'post_media_upload_recovery'),
      contains('caption'),
    );
  });

  test('running the upgrade step again adds nothing', () async {
    final db = await upgradedFrom128();
    addTearDown(db.close);

    await runProductionOnUpgrade(db, 128, currentIdentityDatabaseVersion);

    for (final table in [
      'post_media_attachments',
      'post_media_upload_recovery',
    ]) {
      expect(
        (await _columns(db, table)).where((name) => name == 'caption'),
        hasLength(1),
        reason: table,
      );
    }
  });

  test('a captioned row survives a reopen through the models', () async {
    final db = await upgradedFrom128();
    await db.insert('post_media_attachments', {
      ..._legacyAttachment,
      'media_id': 'media-2',
      'caption': 'what I think so far',
    });
    await db.insert('post_media_upload_recovery', {
      ..._legacyRecovery,
      'position': 1,
      'caption': 'still thinking',
    });
    await db.close();

    final reopened = await open(currentIdentityDatabaseVersion);
    addTearDown(reopened.close);
    final attachment = (await reopened.query(
      'post_media_attachments',
      where: 'media_id = ?',
      whereArgs: ['media-2'],
    )).single;
    final recovery = (await reopened.query(
      'post_media_upload_recovery',
      where: 'position = ?',
      whereArgs: [1],
    )).single;

    expect(
      PostMediaAttachmentModel.fromMap(attachment).toMap()['caption'],
      'what I think so far',
    );
    expect(
      PostMediaUploadRecoveryItem.fromMap(recovery).toMap()['caption'],
      'still thinking',
    );
  });

  test('v129 is the last create and upgrade step', () {
    expect(currentIdentityDatabaseVersion, 129);
    for (final registry in [
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      expect(registry.where((e) => e.version == 129), hasLength(1));
      expect(registry.last.version, 129);
      expect(registry.last.name, '129_post_media_caption');
      expect(registry[registry.length - 2].version, 128);
    }
  });
}
