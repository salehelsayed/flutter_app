// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/migrations/097_direct_message_forwarded.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('actual 097 entry extends complete v96 idempotently', () async {
    final ownSource = File(
      'test/core/database/migrations/097_direct_message_forwarded_test.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'await entry\.run\(db\);').allMatches(ownSource),
      hasLength(2),
      reason: 'the actual registry entry must execute on both migration runs',
    );
    const vacuousCall =
        'runProductionOnUpgrade(db, '
        '97, 97)';
    expect(
      ownSource,
      isNot(contains(vacuousCall)),
      reason: 'an equal-version registry guard is a vacuous rerun',
    );
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await runProductionOnCreate(db, 96);
    await db.insert('messages', {
      'id': 'direct-parent',
      'contact_peer_id': 'contact-1',
      'sender_peer_id': 'contact-1',
      'text': 'caption',
      'timestamp': '2026-07-10T00:00:00.000Z',
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': '2026-07-10T00:00:00.000Z',
    });
    await db.insert('group_messages', {
      'id': 'group-parent',
      'group_id': 'group-1',
      'sender_peer_id': 'peer-g',
      'sender_username': 'Group',
      'text': 'group',
      'timestamp': '2026-07-10T00:00:00.000Z',
      'key_generation': 0,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': '2026-07-10T00:00:00.000Z',
    });
    for (final row in [
      ('direct-att', 'direct-parent', 'direct'),
      ('group-att', 'group-parent', 'group'),
      ('unresolved-att', 'missing-parent', 'unresolved'),
    ]) {
      await db.insert('media_attachments', {
        'id': row.$1,
        'message_id': row.$2,
        'mime': 'image/jpeg',
        'size': 5,
        'media_type': 'image',
        'local_path': '/media/${row.$1}.jpg',
        'download_status': 'done',
        'created_at': '2026-07-10T00:00:01.000Z',
        'owner_lane': row.$3,
        'is_bookmarked': 1,
        'last_playback_position_ms': 123,
      });
    }

    final entry = productionUpgradeMigrations.singleWhere(
      (candidate) =>
          candidate.version == 97 &&
          candidate.name == '097_direct_message_forwarded',
    );
    expect(entry.run, same(runDirectMessageForwardedMigration));
    await entry.run(db);
    await entry.run(db);

    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    final forwarded = columns.singleWhere(
      (row) => row['name'] == 'is_forwarded',
    );
    expect(forwarded['notnull'], 1);
    expect(forwarded['dflt_value'], '0');
    expect((await db.query('messages')).single['is_forwarded'], 0);
    await db.update(
      'messages',
      {'is_forwarded': 1},
      where: 'id = ?',
      whereArgs: ['direct-parent'],
    );
    expect((await db.query('messages')).single['is_forwarded'], 1);
    await expectLater(
      db.update(
        'messages',
        {'is_forwarded': 2},
        where: 'id = ?',
        whereArgs: ['direct-parent'],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.insert('messages', {
        'id': 'invalid-forwarded-insert',
        'contact_peer_id': 'contact-1',
        'sender_peer_id': 'contact-1',
        'text': 'invalid',
        'timestamp': '2026-07-10T00:00:02.000Z',
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-07-10T00:00:02.000Z',
        'is_forwarded': -1,
      }),
      throwsA(anything),
    );

    final marked = ConversationMessage.fromMap({
      ...(await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['direct-parent'],
      )).single,
      'is_forwarded': 1,
    });
    expect(marked.isForwarded, isTrue);
    expect(marked.toMap()['is_forwarded'], 1);
    expect(marked.copyWith(text: 'edited').isForwarded, isTrue);
    expect(marked.copyWith(isForwarded: false).toMap()['is_forwarded'], 0);
    final legacyMap = Map<String, dynamic>.from(marked.toMap())
      ..remove('is_forwarded');
    expect(ConversationMessage.fromMap(legacyMap).isForwarded, isFalse);

    final indexes = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='media_attachments'",
    )).map((row) => row['name']);
    expect(indexes, contains('idx_media_attachments_owner_message'));
    expect(indexes, contains('idx_media_attachments_owner_bookmark_message'));
    final attachmentRows = await db.query('media_attachments', orderBy: 'id');
    expect(attachmentRows, hasLength(3));
    expect(attachmentRows.map((row) => row['owner_lane']).toSet(), {
      'direct',
      'group',
      'unresolved',
    });
    expect(attachmentRows.every((row) => row['is_bookmarked'] == 1), isTrue);
    expect(
      attachmentRows.every((row) => row['last_playback_position_ms'] == 123),
      isTrue,
    );
  });
}
