// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/migrations/098_group_media_deletion_journal.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 235: DB v98 `group_media_deletion_journal` — the ONLY cleanup authority for
// group received-media Delete-for-me. Local-only: no wire mapping, no foreign
// key, no cascade, and NO inferred legacy backfill (an orphaned group-owned
// row plus a same-ID tombstone is not proof plan 235 created it).

Future<void> _seedCompleteV97State(Database db) async {
  await db.insert('messages', {
    'id': 'shared-parent',
    'contact_peer_id': 'contact-1',
    'sender_peer_id': 'contact-1',
    'text': 'caption',
    'timestamp': '2026-07-10T00:00:00.000Z',
    'status': 'delivered',
    'is_incoming': 1,
    'created_at': '2026-07-10T00:00:00.000Z',
    'is_forwarded': 1,
  });
  await db.insert('group_messages', {
    'id': 'shared-parent',
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
    ('direct-att', 'shared-parent', 'direct'),
    ('group-att', 'shared-parent', 'group'),
    ('unresolved-att', 'missing-parent', 'unresolved'),
    // A group-owned orphan next to a same-ID tombstone: the classic shape the
    // refuted reconciler design would have mis-deleted. v98 must NOT backfill
    // a journal row for it.
    ('orphan-att', 'tombstoned-parent', 'group'),
  ]) {
    await db.insert('media_attachments', {
      'id': row.$1,
      'message_id': row.$2,
      'mime': 'image/jpeg',
      'size': 5,
      'media_type': 'image',
      'local_path': 'media/group-1/${row.$1}.jpg',
      'download_status': 'done',
      'created_at': '2026-07-10T00:00:01.000Z',
      'owner_lane': row.$3,
      'is_bookmarked': 1,
      'last_playback_position_ms': 123,
    });
  }
  await db.insert('group_message_local_deletions', {
    'message_id': 'tombstoned-parent',
    'group_id': 'group-1',
    'deleted_at': '2026-07-09T00:00:00.000Z',
    'created_at': '2026-07-09T00:00:00.000Z',
  });
}

Map<String, Object?> _validJournalRow({
  String attachmentId = 'journal-att-1',
  String? canonicalRelativePath = 'media/group-1/journal-att-1.jpg',
}) {
  return {
    'attachment_id': attachmentId,
    'operation_id': 'op-1',
    'message_id': 'deleted-parent',
    'group_id': 'group-1',
    'operation_intent': 'delete_for_me',
    'normalized_mime': 'image/jpeg',
    'canonical_relative_path': canonicalRelativePath,
    'created_at': '2026-07-10T00:00:02.000Z',
  };
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'GMA-06 v98 journal extends complete v97 production registries safely',
    () async {
      final ownSource = File(
        'test/core/database/migrations/098_group_media_deletion_journal_test.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'await entry\.run\(db\);').allMatches(ownSource),
        hasLength(2),
        reason: 'the actual registry entry must execute on both migration runs',
      );
      const vacuousCall =
          'runProductionOnUpgrade(db, '
          '98, 98)';
      expect(
        ownSource,
        isNot(contains(vacuousCall)),
        reason: 'an equal-version registry guard is a vacuous rerun',
      );

      // ---- Upgrade arm: complete v97 predecessor -> v98.
      // singleInstance false: the fresh-create arm below must get its OWN
      // in-memory database, not this cached instance.
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await runProductionOnCreate(db, 97);
      await _seedCompleteV97State(db);

      final entry = productionUpgradeMigrations.singleWhere(
        (candidate) =>
            candidate.version == 98 &&
            candidate.name == '098_group_media_deletion_journal',
      );
      expect(entry.run, same(runGroupMediaDeletionJournalMigration));
      await entry.run(db);
      await entry.run(db);

      // Exact schema: columns, notnull, nullable path, PK.
      final columns = await db.rawQuery(
        'PRAGMA table_info(group_media_deletion_journal)',
      );
      final byName = {for (final row in columns) row['name'] as String: row};
      expect(
        byName.keys.toSet(),
        {
          'attachment_id',
          'operation_id',
          'message_id',
          'group_id',
          'operation_intent',
          'normalized_mime',
          'canonical_relative_path',
          'created_at',
        },
        reason: 'exact journal columns',
      );
      expect(byName['attachment_id']!['pk'], 1);
      for (final required in [
        'operation_id',
        'message_id',
        'group_id',
        'operation_intent',
        'normalized_mime',
        'created_at',
      ]) {
        expect(byName[required]!['notnull'], 1, reason: '$required NOT NULL');
      }
      expect(
        byName['canonical_relative_path']!['notnull'],
        0,
        reason: 'a noncanonical snapshot is stored as null',
      );

      // Exact indexes.
      final indexes = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND tbl_name='group_media_deletion_journal'",
      )).map((row) => row['name']).toSet();
      expect(
        indexes,
        containsAll({
          'idx_group_media_deletion_journal_group_message',
          'idx_group_media_deletion_journal_operation',
        }),
      );
      final groupIndexColumns = (await db.rawQuery(
        'PRAGMA index_info(idx_group_media_deletion_journal_group_message)',
      )).map((row) => row['name']).toList();
      expect(groupIndexColumns, [
        'group_id',
        'message_id',
        'operation_intent',
        'attachment_id',
      ]);
      final operationIndexColumns = (await db.rawQuery(
        'PRAGMA index_info(idx_group_media_deletion_journal_operation)',
      )).map((row) => row['name']).toList();
      expect(operationIndexColumns, ['operation_id', 'attachment_id']);

      // Empty legacy backfill: the group-owned orphan + same-ID tombstone
      // seeded above must NOT be classified into the journal.
      expect(
        await db.query('group_media_deletion_journal'),
        isEmpty,
        reason: 'upgrade starts empty — legacy orphans cannot be classified',
      );

      // Intent CHECK: only 'delete_for_me' inserts/updates are accepted.
      await db.insert('group_media_deletion_journal', _validJournalRow());
      await db.insert(
        'group_media_deletion_journal',
        _validJournalRow(
          attachmentId: 'journal-att-2',
          canonicalRelativePath: null,
        ),
      );
      await expectLater(
        db.insert('group_media_deletion_journal', {
          ..._validJournalRow(attachmentId: 'journal-att-bad'),
          'operation_intent': 'delete_for_everyone',
        }),
        throwsA(anything),
        reason: 'unknown operation intent must be rejected',
      );
      await expectLater(
        db.update(
          'group_media_deletion_journal',
          {'operation_intent': 'revoke'},
          where: 'attachment_id = ?',
          whereArgs: ['journal-att-1'],
        ),
        throwsA(anything),
        reason: 'an intent update away from delete_for_me must be rejected',
      );
      final journalRows = await db.query(
        'group_media_deletion_journal',
        orderBy: 'attachment_id',
      );
      expect(journalRows, hasLength(2));
      expect(journalRows.first['canonical_relative_path'], isNotNull);
      expect(journalRows.last['canonical_relative_path'], isNull);

      // Complete-v97 predecessor artifacts survive: owner lanes, viewer
      // state, both v96 media-owner indexes, and the v97 forwarded marker.
      final mediaIndexes = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND tbl_name='media_attachments'",
      )).map((row) => row['name']);
      expect(mediaIndexes, contains('idx_media_attachments_owner_message'));
      expect(
        mediaIndexes,
        contains('idx_media_attachments_owner_bookmark_message'),
      );
      final attachmentRows = await db.query('media_attachments', orderBy: 'id');
      expect(attachmentRows, hasLength(4));
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
      expect(
        (await db.query('messages')).single['is_forwarded'],
        1,
        reason: 'v97 forwarded marker survives v98',
      );
      expect(
        (await db.query('group_message_local_deletions')).single['message_id'],
        'tombstoned-parent',
        reason: 'the 069 tombstone journal is untouched',
      );

      // ---- Create arm: a fresh v98 install creates the same journal.
      final freshDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(freshDb.close);
      final createEntry = productionCreateMigrations.singleWhere(
        (candidate) =>
            candidate.version == 98 &&
            candidate.name == '098_group_media_deletion_journal',
      );
      expect(createEntry.run, same(runGroupMediaDeletionJournalMigration));
      await runProductionOnCreate(freshDb, 98);
      expect(
        await freshDb.query('group_media_deletion_journal'),
        isEmpty,
        reason: 'fresh create has the journal table, empty',
      );
      await freshDb.insert('group_media_deletion_journal', _validJournalRow());
      expect(await freshDb.query('group_media_deletion_journal'), hasLength(1));
    },
  );
}
