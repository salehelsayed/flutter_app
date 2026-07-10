// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/migrations/099_group_messages_is_forwarded.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 236: DB v99 `group_messages.is_forwarded` — the durable origin-minimizing
// group forwarding marker. Default-false with a 0/1 CHECK; appended exactly
// once to BOTH production registry arms after a populated COMPLETE v98
// predecessor (v96 media owner/viewer state + indexes, the v97 direct
// forwarded marker, plan 235's populated deletion journal + indexes, and
// non-default group-message retry/transport/logical-delivery state).

Future<void> _seedCompleteV98State(Database db) async {
  // v97 artifact: a direct message row with the forwarded marker set.
  await db.insert('messages', {
    'id': 'direct-forwarded',
    'contact_peer_id': 'contact-1',
    'sender_peer_id': 'contact-1',
    'text': 'caption',
    'timestamp': '2026-07-10T00:00:00.000Z',
    'status': 'delivered',
    'is_incoming': 1,
    'created_at': '2026-07-10T00:00:00.000Z',
    'is_forwarded': 1,
  });

  // A group message row with NON-DEFAULT reliability/transport state — every
  // value below must survive v99 byte-for-byte.
  await db.insert('group_messages', {
    'id': 'group-msg-1',
    'group_id': 'group-1',
    'sender_peer_id': 'peer-g',
    'transport_peer_id': 'transport-peer-g',
    'sender_username': 'Group Sender',
    'text': 'group body',
    'timestamp': '2026-07-10T00:00:00.000Z',
    'last_send_attempt_at': '2026-07-10T00:00:05.000Z',
    'quoted_message_id': 'quoted-parent-1',
    'logical_delivery_id': 'logical-delivery-1',
    'key_generation': 4,
    'status': 'pending',
    'is_incoming': 0,
    'created_at': '2026-07-10T00:00:00.000Z',
    'wire_envelope': '{"groupId":"group-1","text":"group body"}',
    'inbox_stored': 1,
    'inbox_retry_payload': '{"groupId":"group-1","message":"envelope"}',
    'retry_attempt_count': 3,
    'next_eligible_at': 1783700000000,
  });

  // v96 artifacts: owner-laned media rows with viewer state.
  for (final row in [
    ('direct-att', 'direct-forwarded', 'direct'),
    ('group-att', 'group-msg-1', 'group'),
    ('unresolved-att', 'missing-parent', 'unresolved'),
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

  // Plan 235 artifacts: POPULATED deletion-journal rows.
  for (final attachmentId in ['journal-att-1', 'journal-att-2']) {
    await db.insert('group_media_deletion_journal', {
      'attachment_id': attachmentId,
      'operation_id': 'op-1',
      'message_id': 'deleted-parent',
      'group_id': 'group-1',
      'operation_intent': 'delete_for_me',
      'normalized_mime': 'image/jpeg',
      'canonical_relative_path': 'media/group-1/$attachmentId.jpg',
      'created_at': '2026-07-10T00:00:02.000Z',
    });
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'GMF-06 v99 extends registries and preserves populated complete v98 state',
    () async {
      // Own-source guards: the upgrade must replay the REAL 98->99 registry
      // range (never a vacuous equal-version range), and the actual entry
      // must additionally re-run for idempotence.
      final ownSource = File(
        'test/core/database/migrations/099_group_messages_is_forwarded_test.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r'runProductionOnUpgrade\(db, 98, 99\)',
        ).allMatches(ownSource).length,
        greaterThanOrEqualTo(2),
        reason: 'the upgrade arm must replay the real 98->99 registry range',
      );
      const vacuousCall =
          'runProductionOnUpgrade(db, '
          '99, 99)';
      expect(
        ownSource,
        isNot(contains(vacuousCall)),
        reason: 'an equal-version registry guard is a vacuous rerun',
      );

      // Exactly ONE 099 entry per production registry arm, both bound to the
      // real migration function.
      final upgradeEntry = productionUpgradeMigrations.singleWhere(
        (candidate) => candidate.version == 99,
      );
      expect(upgradeEntry.name, '099_group_messages_is_forwarded');
      expect(upgradeEntry.run, same(runGroupMessagesIsForwardedMigration));
      final createEntry = productionCreateMigrations.singleWhere(
        (candidate) => candidate.version == 99,
      );
      expect(createEntry.name, '099_group_messages_is_forwarded');
      expect(createEntry.run, same(runGroupMessagesIsForwardedMigration));

      // ---- Upgrade arm: populated complete v98 predecessor -> v99.
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await runProductionOnCreate(db, 98);
      await _seedCompleteV98State(db);

      await runProductionOnUpgrade(db, 98, 99);
      // Idempotence: rerunning the real registry range AND the raw entry is
      // harmless.
      await runProductionOnUpgrade(db, 98, 99);
      await upgradeEntry.run(db);

      // Exact column shape: NOT NULL, literal default 0.
      final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
      final byName = {for (final row in columns) row['name'] as String: row};
      expect(byName, contains('is_forwarded'));
      expect(byName['is_forwarded']!['notnull'], 1);
      expect(byName['is_forwarded']!['dflt_value'], '0');

      // Pre-existing rows read as NOT forwarded, with every non-default
      // reliability/transport value preserved byte-for-byte.
      final preserved = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['group-msg-1'],
      )).single;
      expect(preserved['is_forwarded'], 0);
      expect(preserved['quoted_message_id'], 'quoted-parent-1');
      expect(
        preserved['wire_envelope'],
        '{"groupId":"group-1","text":"group body"}',
      );
      expect(preserved['inbox_stored'], 1);
      expect(
        preserved['inbox_retry_payload'],
        '{"groupId":"group-1","message":"envelope"}',
      );
      expect(preserved['transport_peer_id'], 'transport-peer-g');
      expect(preserved['last_send_attempt_at'], '2026-07-10T00:00:05.000Z');
      expect(preserved['logical_delivery_id'], 'logical-delivery-1');
      expect(preserved['retry_attempt_count'], 3);
      expect(preserved['next_eligible_at'], 1783700000000);
      expect(preserved['key_generation'], 4);
      expect(preserved['status'], 'pending');
      final legacyModel = GroupMessage.fromMap(preserved);
      expect(legacyModel.isForwarded, isFalse);
      expect(legacyModel.retryAttemptCount, 3);
      expect(legacyModel.logicalDeliveryId, 'logical-delivery-1');

      // The named group_messages indexes survive.
      final groupMessageIndexes = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND tbl_name='group_messages'",
      )).map((row) => row['name']).toSet();
      expect(
        groupMessageIndexes,
        containsAll({
          'idx_group_messages_group',
          'idx_group_messages_ts',
          'idx_group_messages_logical_delivery',
          'idx_group_messages_group_ts',
        }),
      );

      // CHECK constraint: only 0/1 are storable, on insert AND update.
      await expectLater(
        db.insert('group_messages', {
          'id': 'group-msg-bad',
          'group_id': 'group-1',
          'sender_peer_id': 'peer-g',
          'text': 'bad',
          'timestamp': '2026-07-10T00:00:00.000Z',
          'status': 'sent',
          'is_incoming': 1,
          'created_at': '2026-07-10T00:00:00.000Z',
          'is_forwarded': 2,
        }),
        throwsA(anything),
        reason: 'is_forwarded outside 0/1 must be rejected',
      );
      await expectLater(
        db.update(
          'group_messages',
          {'is_forwarded': 7},
          where: 'id = ?',
          whereArgs: ['group-msg-1'],
        ),
        throwsA(anything),
        reason: 'an update outside 0/1 must be rejected',
      );

      // A true marker round-trips through the model mapping.
      await db.insert('group_messages', {
        'id': 'group-msg-forwarded',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-g',
        'text': 'forwarded body',
        'timestamp': '2026-07-10T00:00:10.000Z',
        'status': 'sent',
        'is_incoming': 0,
        'created_at': '2026-07-10T00:00:10.000Z',
        'is_forwarded': 1,
      });
      final forwardedRow = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['group-msg-forwarded'],
      )).single;
      expect(GroupMessage.fromMap(forwardedRow).isForwarded, isTrue);
      // An INSERT that omits the column takes the false default.
      await db.insert('group_messages', {
        'id': 'group-msg-defaulted',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-g',
        'text': 'ordinary body',
        'timestamp': '2026-07-10T00:00:11.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-07-10T00:00:11.000Z',
      });
      final defaultedRow = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: ['group-msg-defaulted'],
      )).single;
      expect(defaultedRow['is_forwarded'], 0);
      expect(GroupMessage.fromMap(defaultedRow).isForwarded, isFalse);

      // Complete-v98 predecessor artifacts survive: the POPULATED journal
      // rows and both journal indexes, the v97 direct marker, and the v96
      // media owner/viewer state and indexes.
      final journalRows = await db.query(
        'group_media_deletion_journal',
        orderBy: 'attachment_id',
      );
      expect(journalRows, hasLength(2));
      expect(
        journalRows.map((row) => row['attachment_id']),
        ['journal-att-1', 'journal-att-2'],
      );
      expect(
        journalRows.every(
          (row) => row['operation_intent'] == 'delete_for_me',
        ),
        isTrue,
      );
      final journalIndexes = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND tbl_name='group_media_deletion_journal'",
      )).map((row) => row['name']).toSet();
      expect(
        journalIndexes,
        containsAll({
          'idx_group_media_deletion_journal_group_message',
          'idx_group_media_deletion_journal_operation',
        }),
      );
      expect(
        (await db.query('messages')).single['is_forwarded'],
        1,
        reason: 'the v97 direct forwarded marker survives v99',
      );
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

      // ---- Create arm: a fresh v99 install ships the same default-false
      // constrained column.
      final freshDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(freshDb.close);
      await runProductionOnCreate(freshDb, 99);
      final freshColumns = await freshDb.rawQuery(
        'PRAGMA table_info(group_messages)',
      );
      final freshByName = {
        for (final row in freshColumns) row['name'] as String: row,
      };
      expect(freshByName, contains('is_forwarded'));
      expect(freshByName['is_forwarded']!['notnull'], 1);
      expect(freshByName['is_forwarded']!['dflt_value'], '0');
      await freshDb.insert('group_messages', {
        'id': 'fresh-msg',
        'group_id': 'group-1',
        'sender_peer_id': 'peer-g',
        'text': 'fresh',
        'timestamp': '2026-07-10T00:00:00.000Z',
        'status': 'sent',
        'is_incoming': 1,
        'created_at': '2026-07-10T00:00:00.000Z',
      });
      expect(
        (await freshDb.query('group_messages')).single['is_forwarded'],
        0,
      );
      await expectLater(
        freshDb.insert('group_messages', {
          'id': 'fresh-msg-bad',
          'group_id': 'group-1',
          'sender_peer_id': 'peer-g',
          'text': 'bad',
          'timestamp': '2026-07-10T00:00:00.000Z',
          'status': 'sent',
          'is_incoming': 1,
          'created_at': '2026-07-10T00:00:00.000Z',
          'is_forwarded': 5,
        }),
        throwsA(anything),
      );
    },
  );
}
