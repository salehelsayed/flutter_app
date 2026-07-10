import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/096_media_library_state.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';

void main() {
  // TC-228-02: migration 096 adds the owner-lane + local viewer-state columns
  // with an enforced three-value CHECK and exact composite indexes, backfills
  // deterministically (unique parent only), keeps both-parent/orphan rows
  // fail-closed at 'unresolved', preserves row bytes/metadata, and is stable
  // across a second run. Plain sqflite FFI (cipher behavior is TC-228-02D).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // Literal v95 baseline through the shared production create registry.
    await runProductionOnCreate(db, 95);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedDirectParent(String id) async {
    await db.insert('messages', {
      'id': id,
      'contact_peer_id': 'contact-1',
      'sender_peer_id': 'contact-1',
      'text': 'direct parent $id',
      'timestamp': '2026-07-01T00:00:00.000Z',
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': '2026-07-01T00:00:00.000Z',
    });
  }

  Future<void> seedGroupParent(String id) async {
    await db.insert('group_messages', {
      'id': id,
      'group_id': 'group-1',
      'sender_peer_id': 'peer-g',
      'sender_username': 'GroupSender',
      'text': 'group parent $id',
      'timestamp': '2026-07-01T00:00:00.000Z',
      'key_generation': 0,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': '2026-07-01T00:00:00.000Z',
    });
  }

  Future<void> seedAttachment(String id, String messageId) async {
    await db.insert('media_attachments', {
      'id': id,
      'message_id': messageId,
      'mime': 'image/jpeg',
      'size': 1234,
      'media_type': 'image',
      'local_path': '/media/$id.jpg',
      'download_status': 'done',
      'created_at': '2026-07-01T00:00:01.000Z',
      'encryption_key_base64': 'key-$id',
      'encryption_nonce': 'nonce-$id',
      'encryption_scheme': 'blob_aes_256_gcm_v1',
    });
  }

  Future<Map<String, Object?>> attachmentRow(String id) async {
    final rows = await db.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: [id],
    );
    expect(rows, hasLength(1), reason: 'attachment $id must survive');
    return rows.single;
  }

  Future<List<String>> indexColumns(String indexName) async {
    final info = await db.rawQuery('PRAGMA index_info($indexName)');
    final ordered = [...info]..sort(
      (a, b) => ((a['seqno'] as num).toInt()).compareTo(
        (b['seqno'] as num).toInt(),
      ),
    );
    return ordered.map((r) => r['name'] as String).toList();
  }

  test(
    'v95 to v96 backfills owner lanes fail closed and enforces owner '
    'constraint idempotently',
    () async {
      // v95 fixture: direct-only, group-only, same-parent-ID collision, orphan.
      await seedDirectParent('msg-direct-only');
      await seedGroupParent('msg-group-only');
      await seedDirectParent('msg-shared');
      await seedGroupParent('msg-shared');
      await seedAttachment('att-direct', 'msg-direct-only');
      await seedAttachment('att-group', 'msg-group-only');
      await seedAttachment('att-ambiguous', 'msg-shared');
      await seedAttachment('att-orphan', 'msg-missing');

      // v95 has none of the new columns.
      final preCols = (await db.rawQuery(
        'PRAGMA table_info(media_attachments)',
      )).map((c) => c['name'] as String).toSet();
      expect(preCols, isNot(contains('owner_lane')));
      expect(preCols, isNot(contains('is_bookmarked')));
      expect(preCols, isNot(contains('last_playback_position_ms')));

      await runMediaLibraryStateMigration(db);

      // Columns, NOT NULL flags and defaults.
      final cols = await db.rawQuery('PRAGMA table_info(media_attachments)');
      final byName = {for (final c in cols) c['name'] as String: c};
      expect(byName['owner_lane'], isNotNull);
      expect(byName['owner_lane']!['type'], 'TEXT');
      expect(byName['owner_lane']!['notnull'], 1);
      expect(byName['owner_lane']!['dflt_value'], "'unresolved'");
      expect(byName['is_bookmarked'], isNotNull);
      expect(byName['is_bookmarked']!['type'], 'INTEGER');
      expect(byName['is_bookmarked']!['notnull'], 1);
      expect(byName['is_bookmarked']!['dflt_value'], '0');
      expect(byName['last_playback_position_ms'], isNotNull);
      expect(byName['last_playback_position_ms']!['type'], 'INTEGER');
      expect(byName['last_playback_position_ms']!['notnull'], 1);
      expect(byName['last_playback_position_ms']!['dflt_value'], '0');

      // Exact composite indexes, exact column order.
      expect(await indexColumns('idx_media_attachments_owner_message'), [
        'owner_lane',
        'message_id',
      ]);
      expect(
        await indexColumns('idx_media_attachments_owner_bookmark_message'),
        ['owner_lane', 'is_bookmarked', 'message_id'],
      );

      // Deterministic backfill: unique parents classify, ambiguity and
      // orphans stay fail-closed at 'unresolved'.
      expect((await attachmentRow('att-direct'))['owner_lane'], 'direct');
      expect((await attachmentRow('att-group'))['owner_lane'], 'group');
      expect(
        (await attachmentRow('att-ambiguous'))['owner_lane'],
        'unresolved',
      );
      expect((await attachmentRow('att-orphan'))['owner_lane'], 'unresolved');

      // Bytes/metadata preserved, local-state defaults applied.
      for (final id in [
        'att-direct',
        'att-group',
        'att-ambiguous',
        'att-orphan',
      ]) {
        final row = await attachmentRow(id);
        expect(row['mime'], 'image/jpeg');
        expect(row['size'], 1234);
        expect(row['local_path'], '/media/$id.jpg');
        expect(row['encryption_key_base64'], 'key-$id');
        expect(row['encryption_nonce'], 'nonce-$id');
        expect(row['is_bookmarked'], 0);
        expect(row['last_playback_position_ms'], 0);
      }

      // CHECK proof by behavior, not PRAGMA: invalid INSERT throws...
      await expectLater(
        () => db.insert('media_attachments', {
          'id': 'att-bogus',
          'message_id': 'msg-direct-only',
          'mime': 'image/jpeg',
          'size': 1,
          'media_type': 'image',
          'download_status': 'pending',
          'created_at': '2026-07-01T00:00:02.000Z',
          'owner_lane': 'not_a_lane',
        }),
        throwsA(anything),
      );
      expect(
        await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['att-bogus'],
        ),
        isEmpty,
      );
      // ...and an invalid UPDATE throws and leaves the row unchanged.
      await expectLater(
        () => db.update(
          'media_attachments',
          {'owner_lane': 'not_a_lane'},
          where: 'id = ?',
          whereArgs: ['att-direct'],
        ),
        throwsA(anything),
      );
      expect((await attachmentRow('att-direct'))['owner_lane'], 'direct');

      // All three legal values are accepted.
      for (final lane in ['direct', 'group', 'unresolved']) {
        await db.insert('media_attachments', {
          'id': 'att-legal-$lane',
          'message_id': 'msg-direct-only',
          'mime': 'image/jpeg',
          'size': 1,
          'media_type': 'image',
          'download_status': 'pending',
          'created_at': '2026-07-01T00:00:03.000Z',
          'owner_lane': lane,
        });
        expect((await attachmentRow('att-legal-$lane'))['owner_lane'], lane);
      }

      // Second run is stable: no owner mutation, including rows whose owner
      // was explicitly changed after the first run, and fail-closed rows.
      await db.update(
        'media_attachments',
        {'owner_lane': 'group', 'is_bookmarked': 1},
        where: 'id = ?',
        whereArgs: ['att-legal-unresolved'],
      );
      await runMediaLibraryStateMigration(db);
      expect((await attachmentRow('att-direct'))['owner_lane'], 'direct');
      expect((await attachmentRow('att-group'))['owner_lane'], 'group');
      expect(
        (await attachmentRow('att-ambiguous'))['owner_lane'],
        'unresolved',
      );
      expect((await attachmentRow('att-orphan'))['owner_lane'], 'unresolved');
      final flipped = await attachmentRow('att-legal-unresolved');
      expect(flipped['owner_lane'], 'group');
      expect(flipped['is_bookmarked'], 1);
    },
  );
}
