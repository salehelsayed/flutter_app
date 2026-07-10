import 'dart:async';

import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/groups/application/delete_group_media_for_me_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _validContentHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    'cccc';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  Future<void> seedGroupParent({
    required String messageId,
    String groupId = 'group-1',
  }) async {
    await db.insert('group_messages', {
      'id': messageId,
      'group_id': groupId,
      'sender_peer_id': 'peer-alice',
      'sender_username': 'Alice',
      'text': 'caption',
      'timestamp': '2026-07-10T00:00:00.000Z',
      'key_generation': 0,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': '2026-07-10T00:00:00.000Z',
    });
  }

  Future<void> seedGroupAttachment({
    required String id,
    required String messageId,
    String ownerLane = 'group',
    String mime = 'IMAGE/JPEG ',
    String? localPath,
  }) async {
    await db.insert('media_attachments', {
      'id': id,
      'message_id': messageId,
      'mime': mime,
      'size': 9,
      'media_type': 'image',
      'local_path': localPath,
      'download_status': 'done',
      'created_at': '2026-07-10T00:00:01.000Z',
      'owner_lane': ownerLane,
      'is_bookmarked': 0,
      'last_playback_position_ms': 0,
      'content_hash': _validContentHash,
    });
  }

  Future<void> seedPendingReaction({
    required String id,
    required String groupId,
    required String messageId,
  }) async {
    await db.insert('group_pending_reactions', {
      'id': id,
      'group_id': groupId,
      'message_id': messageId,
      'sender_peer_id': 'peer-bob',
      'reaction_json': '{}',
      'received_at': '2026-07-10T00:00:02.000Z',
      'created_at': '2026-07-10T00:00:02.000Z',
      'updated_at': '2026-07-10T00:00:02.000Z',
    });
  }

  Future<void> seedOutboxRow({
    required String reactionId,
    required String groupId,
    required String messageId,
    required String deliveryStatus,
  }) async {
    await db.insert('group_reaction_replay_outbox', {
      'reaction_id': reactionId,
      'group_id': groupId,
      'message_id': messageId,
      'sender_peer_id': 'peer-self',
      'emoji': '👍',
      'action': 'add',
      'inbox_retry_payload': '{}',
      'delivery_status': deliveryStatus,
      'created_at': '2026-07-10T00:00:03.000Z',
      'updated_at': '2026-07-10T00:00:03.000Z',
    });
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await runProductionOnCreate(db, currentIdentityDatabaseVersion);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'GMA-07 delete prepare is exact group scoped atomic and reaction safe',
    () async {
      // Group parent with two group-owned attachments — one on the exact
      // canonical relative path (snapshot kept), one on a noncanonical
      // absolute path (snapshot must be null).
      await seedGroupParent(messageId: 'msg-x');
      await seedGroupAttachment(
        id: 'att-1',
        messageId: 'msg-x',
        localPath: 'media/group-1/att-1.jpg',
      );
      await seedGroupAttachment(
        id: 'att-2',
        messageId: 'msg-x',
        localPath: '/abs/elsewhere/att-2.jpg',
      );
      // Same-ID direct collision: a direct message and a direct-owned
      // attachment under the SAME parent id must survive untouched.
      await db.insert('messages', {
        'id': 'msg-x',
        'contact_peer_id': 'contact-9',
        'sender_peer_id': 'contact-9',
        'text': 'direct twin',
        'timestamp': '2026-07-10T00:00:00.000Z',
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-07-10T00:00:00.000Z',
      });
      await seedGroupAttachment(
        id: 'att-direct',
        messageId: 'msg-x',
        ownerLane: 'direct',
        localPath: 'media/contact-9/att-direct.jpg',
      );
      // Ordinary untyped reaction rows are retained (hidden, never deleted).
      await db.insert('message_reactions', {
        'id': 'reaction-ordinary',
        'message_id': 'msg-x',
        'sender_peer_id': 'peer-bob',
        'emoji': '❤️',
        'timestamp': '2026-07-10T00:00:02.000Z',
        'created_at': '2026-07-10T00:00:02.000Z',
      });
      // Exact pending reactions: (group-1, msg-x) dies; (group-2, msg-x)
      // survives.
      await seedPendingReaction(
        id: 'pr-own',
        groupId: 'group-1',
        messageId: 'msg-x',
      );
      await seedPendingReaction(
        id: 'pr-other-group',
        groupId: 'group-2',
        messageId: 'msg-x',
      );
      // Replay outbox: pending+failed for the exact parent die; stored stays
      // as inert completed-delivery evidence; other-group rows survive.
      await seedOutboxRow(
        reactionId: 'ob-pending',
        groupId: 'group-1',
        messageId: 'msg-x',
        deliveryStatus: 'pending',
      );
      await seedOutboxRow(
        reactionId: 'ob-failed',
        groupId: 'group-1',
        messageId: 'msg-x',
        deliveryStatus: 'failed',
      );
      await seedOutboxRow(
        reactionId: 'ob-stored',
        groupId: 'group-1',
        messageId: 'msg-x',
        deliveryStatus: 'stored',
      );
      await seedOutboxRow(
        reactionId: 'ob-other-group',
        groupId: 'group-2',
        messageId: 'msg-x',
        deliveryStatus: 'pending',
      );

      var cleanupRuns = 0;
      final useCase = DeleteGroupMediaForMeUseCase(
        prepare:
            ({
              required String groupId,
              required String messageId,
              required String operationId,
            }) => dbPrepareGroupMediaDeleteForMe(
              db,
              groupId: groupId,
              messageId: messageId,
              operationId: operationId,
            ),
        runCleanup: () async {
          cleanupRuns += 1;
        },
        operationIdFactory: () => 'op-fixed-1',
      );

      await useCase.deleteForMe(groupId: 'group-1', messageId: 'msg-x');

      // Journal: exactly the two group-owned attachments, one shared
      // operation id, normalized MIME, canonical-or-null path snapshot.
      final journal = await db.query(
        'group_media_deletion_journal',
        orderBy: 'attachment_id',
      );
      expect(journal.map((row) => row['attachment_id']), ['att-1', 'att-2']);
      expect(journal.map((row) => row['operation_id']).toSet(), {'op-fixed-1'});
      expect(journal.map((row) => row['message_id']).toSet(), {'msg-x'});
      expect(journal.map((row) => row['group_id']).toSet(), {'group-1'});
      expect(
        journal.map((row) => row['operation_intent']).toSet(),
        {'delete_for_me'},
      );
      expect(
        journal.map((row) => row['normalized_mime']).toSet(),
        {'image/jpeg'},
        reason: 'MIME is normalized from the same row version',
      );
      expect(
        journal.first['canonical_relative_path'],
        'media/group-1/att-1.jpg',
      );
      expect(
        journal.last['canonical_relative_path'],
        isNull,
        reason: 'a noncanonical stored path never authorizes file deletion',
      );

      // Tombstone + parent delete, exact reaction cleanup, preserved rows.
      final tombstones = await db.query('group_message_local_deletions');
      expect(tombstones.single['message_id'], 'msg-x');
      expect(tombstones.single['group_id'], 'group-1');
      expect(await db.query('group_messages'), isEmpty);
      expect(
        (await db.query('messages')).single['text'],
        'direct twin',
        reason: 'the same-ID direct message survives',
      );
      final attachmentRows = await db.query(
        'media_attachments',
        orderBy: 'id',
      );
      expect(
        attachmentRows.map((row) => row['id']),
        ['att-1', 'att-2', 'att-direct'],
        reason: 'prepare journals rows; only post-commit cleanup deletes them',
      );
      expect(
        (await db.query('message_reactions')).single['emoji'],
        '❤️',
        reason: 'ordinary untyped reactions are retained',
      );
      expect(
        (await db.query('group_pending_reactions')).single['id'],
        'pr-other-group',
      );
      expect(
        (await db.query(
          'group_reaction_replay_outbox',
          orderBy: 'reaction_id',
        )).map((row) => row['reaction_id']),
        ['ob-other-group', 'ob-stored'],
      );
      expect(cleanupRuns, 1);

      // Idempotent second confirm: alreadyDeleted, zero new writes.
      await useCase.deleteForMe(groupId: 'group-1', messageId: 'msg-x');
      expect(await db.query('group_media_deletion_journal'), hasLength(2));
      expect(await db.query('group_message_local_deletions'), hasLength(1));
      expect(
        cleanupRuns,
        1,
        reason: 'a no-op repeat schedules no second cleanup',
      );

      // Zero-attachment delete: one tombstone/parent transaction, no
      // fabricated journal rows.
      await seedGroupParent(messageId: 'msg-empty');
      final direct = await dbPrepareGroupMediaDeleteForMe(
        db,
        groupId: 'group-1',
        messageId: 'msg-empty',
        operationId: 'op-empty',
      );
      expect(direct.outcome, GroupMediaDeletePrepareOutcome.prepared);
      expect(direct.journaledAttachments, 0);
      expect(
        (await db.query(
          'group_media_deletion_journal',
        )).map((row) => row['operation_id']),
        isNot(contains('op-empty')),
      );

      // Absent parent, no tombstone: parentMissing, zero writes.
      final missing = await dbPrepareGroupMediaDeleteForMe(
        db,
        groupId: 'group-1',
        messageId: 'msg-never-existed',
        operationId: 'op-missing',
      );
      expect(missing.outcome, GroupMediaDeletePrepareOutcome.parentMissing);
      expect(await db.query('group_message_local_deletions'), hasLength(2));

      // Conflicting same-ID tombstone: a LIVE group-2 parent whose message id
      // is tombstoned for group-1 fails closed with zero writes — deleting it
      // would clobber group-1's replay protection.
      await seedGroupParent(messageId: 'msg-conflict', groupId: 'group-2');
      await db.insert('group_message_local_deletions', {
        'message_id': 'msg-conflict',
        'group_id': 'group-1',
        'deleted_at': '2026-07-09T00:00:00.000Z',
        'created_at': '2026-07-09T00:00:00.000Z',
      });
      await seedGroupAttachment(
        id: 'att-conflict',
        messageId: 'msg-conflict',
        localPath: 'media/group-2/att-conflict.jpg',
      );
      final conflict = await dbPrepareGroupMediaDeleteForMe(
        db,
        groupId: 'group-2',
        messageId: 'msg-conflict',
        operationId: 'op-conflict',
      );
      expect(
        conflict.outcome,
        GroupMediaDeletePrepareOutcome.conflictingTombstone,
      );
      expect(
        (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['msg-conflict'],
        )),
        hasLength(1),
        reason: 'conflict makes zero writes — the live parent survives',
      );
      expect(
        (await db.query(
          'group_media_deletion_journal',
        )).map((row) => row['operation_id']),
        isNot(contains('op-conflict')),
      );

      // Forced second-operation failure rolls the WHOLE prepare back and no
      // file/key I/O starts: a leftover journal row for one attachment makes
      // the journal insert throw mid-transaction.
      await seedGroupParent(messageId: 'msg-rollback');
      await seedGroupAttachment(
        id: 'att-rb-1',
        messageId: 'msg-rollback',
        localPath: 'media/group-1/att-rb-1.jpg',
      );
      await seedGroupAttachment(
        id: 'att-rb-2',
        messageId: 'msg-rollback',
        localPath: 'media/group-1/att-rb-2.jpg',
      );
      await seedPendingReaction(
        id: 'pr-rollback',
        groupId: 'group-1',
        messageId: 'msg-rollback',
      );
      await db.insert('group_media_deletion_journal', {
        'attachment_id': 'att-rb-2',
        'operation_id': 'op-leftover',
        'message_id': 'msg-rollback',
        'group_id': 'group-1',
        'operation_intent': 'delete_for_me',
        'normalized_mime': 'image/jpeg',
        'canonical_relative_path': null,
        'created_at': '2026-07-09T00:00:00.000Z',
      });
      await expectLater(
        dbPrepareGroupMediaDeleteForMe(
          db,
          groupId: 'group-1',
          messageId: 'msg-rollback',
          operationId: 'op-rollback',
        ),
        throwsA(anything),
      );
      expect(
        (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['msg-rollback'],
        )),
        hasLength(1),
        reason: 'rollback restores the parent',
      );
      expect(
        (await db.query(
          'group_message_local_deletions',
          where: 'message_id = ?',
          whereArgs: ['msg-rollback'],
        )),
        isEmpty,
        reason: 'rollback removes the tombstone upsert',
      );
      expect(
        (await db.query(
          'group_pending_reactions',
          where: 'id = ?',
          whereArgs: ['pr-rollback'],
        )),
        hasLength(1),
        reason: 'rollback restores the pending reaction',
      );
      expect(
        (await db.query(
          'group_media_deletion_journal',
        )).map((row) => row['operation_id']),
        isNot(contains('op-rollback')),
      );

      // Double taps coalesce behind the (group, message) single-flight guard.
      await seedGroupParent(messageId: 'msg-flight');
      final gate = Completer<void>();
      var prepareCalls = 0;
      final gated = DeleteGroupMediaForMeUseCase(
        prepare:
            ({
              required String groupId,
              required String messageId,
              required String operationId,
            }) async {
              prepareCalls += 1;
              await gate.future;
              return dbPrepareGroupMediaDeleteForMe(
                db,
                groupId: groupId,
                messageId: messageId,
                operationId: operationId,
              );
            },
        runCleanup: () async {},
      );
      final first = gated.deleteForMe(groupId: 'group-1', messageId: 'msg-flight');
      final second = gated.deleteForMe(
        groupId: 'group-1',
        messageId: 'msg-flight',
      );
      gate.complete();
      await Future.wait([first, second]);
      expect(prepareCalls, 1, reason: 'double tap coalesces to one operation');
    },
  );
}
