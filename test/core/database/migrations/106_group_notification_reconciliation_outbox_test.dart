// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/group_notification_canonical_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/106_group_notification_display_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/group_notification_canonical_reconciler.dart';
import 'package:flutter_app/features/groups/data/repositories/group_notification_reconciliation_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_reconciliation_outbox_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _t0 = '2026-08-03T10:00:00.000Z';
const _t1 = '2026-08-03T10:00:01.000Z';
const _t2 = '2026-08-03T10:00:02.000Z';

Future<void> _insertGroup(
  Database db,
  String groupId, {
  bool retainInsertReconciliation = false,
}) async {
  await db.insert('groups', <String, Object?>{
    'id': groupId,
    'name': 'Canonical group',
    'type': 'chat',
    'topic_name': '/mknoon/groups/$groupId',
    'created_at': _t0,
    'created_by': 'peer-creator',
    'my_role': 'admin',
  });
  if (!retainInsertReconciliation) {
    await db.delete(
      'group_notification_reconciliation_outbox',
      where: 'group_id = ?',
      whereArgs: <Object?>[groupId],
    );
  }
}

Future<void> _insertGroupMember(
  Database db, {
  required String groupId,
  required String peerId,
}) => db.insert('group_members', <String, Object?>{
  'group_id': groupId,
  'peer_id': peerId,
  'username': peerId,
  'role': 'writer',
  'joined_at': _t0,
});

Future<void> _insertGroupMessage(
  Database db, {
  required String groupId,
  required String messageId,
}) {
  return db.insert('group_messages', <String, Object?>{
    'id': messageId,
    'group_id': groupId,
    'sender_peer_id': 'peer-sender',
    'text': 'canonical message content',
    'timestamp': _t0,
    'created_at': _t0,
  });
}

Map<String, Object?> _removeRow({
  required String id,
  required String messageId,
  String senderPeerId = 'peer-reactor',
  String timestamp = _t1,
}) => <String, Object?>{
  'id': id,
  'message_id': messageId,
  'emoji': '\u{1F44D}',
  'sender_peer_id': senderPeerId,
  'timestamp': timestamp,
  'created_at': timestamp,
};

GroupNotificationReconciliationOutboxRepositoryImpl _repository(
  Database db, {
  required DateTime Function() now,
}) {
  return GroupNotificationReconciliationOutboxRepositoryImpl(
    dbLoadEligible: ({limit = 20, required eligibleAt}) =>
        dbLoadEligibleGroupNotificationReconciliationOutboxEntries(
          db,
          limit: limit,
          eligibleAt: eligibleAt,
        ),
    dbLoadEarliestNextAttemptAt: () =>
        dbLoadEarliestGroupNotificationReconciliationOutboxNextAttemptAt(db),
    dbRecordFailureIfExact:
        ({
          required groupId,
          required expectedIncarnationId,
          required expectedRevision,
          required lastAttemptAt,
          required nextAttemptAt,
          required updatedAt,
        }) => dbRecordGroupNotificationReconciliationOutboxFailureIfExact(
          db,
          groupId: groupId,
          expectedIncarnationId: expectedIncarnationId,
          expectedRevision: expectedRevision,
          lastAttemptAt: lastAttemptAt,
          nextAttemptAt: nextAttemptAt,
          updatedAt: updatedAt,
        ),
    dbCompleteIfExact:
        ({
          required groupId,
          required expectedIncarnationId,
          required expectedRevision,
        }) => dbCompleteGroupNotificationReconciliationOutboxIfExact(
          db,
          groupId: groupId,
          expectedIncarnationId: expectedIncarnationId,
          expectedRevision: expectedRevision,
        ),
    now: now,
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late Directory tempDir;
  late String path;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'group_notification_reconciliation_v106_',
    );
    path = '${tempDir.path}/identity.db';
    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await runProductionOnCreate(db, currentIdentityDatabaseVersion);
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'v106 reconciliation custody is identifier-only no-FK and idempotent',
    () async {
      final columns = await db.rawQuery(
        'PRAGMA table_info(group_notification_reconciliation_outbox)',
      );
      expect(columns.map((row) => row['name']).toList(), <String>[
        'group_id',
        'incarnation_id',
        'revision',
        'retry_count',
        'last_attempt_at',
        'next_attempt_at',
        'created_at',
        'updated_at',
      ]);
      final columnNames = columns.map((row) => row['name']).toSet();
      expect(
        columnNames.intersection(<Object?>{
          'title',
          'body',
          'copy',
          'text',
          'emoji',
          'payload',
          'message_id',
          'reaction_id',
          'actor_peer_id',
        }),
        isEmpty,
      );
      expect(
        await db.rawQuery(
          'PRAGMA foreign_key_list(group_notification_reconciliation_outbox)',
        ),
        isEmpty,
      );
      expect(
        (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' "
          "AND name LIKE 'trg_group_notification_reconcile_%' ORDER BY name",
        )).map((row) => row['name']),
        <String>[
          'trg_group_notification_reconcile_group_delete',
          'trg_group_notification_reconcile_group_insert',
          'trg_group_notification_reconcile_member_delete',
          'trg_group_notification_reconcile_message_delete',
          'trg_group_notification_reconcile_message_read',
          'trg_group_notification_reconcile_policy_change',
        ],
      );

      await runGroupNotificationDisplayOutboxMigration(db);
      await runGroupNotificationDisplayOutboxMigration(db);
      expect(
        await db.query('group_notification_reconciliation_outbox'),
        isEmpty,
      );
    },
  );

  test(
    'group INSERT OR REPLACE durably invalidates without relying on UPDATE',
    () async {
      await _insertGroup(db, 'group-replace', retainInsertReconciliation: true);
      final inserted = await dbLoadGroupNotificationReconciliationOutboxEntry(
        db,
        'group-replace',
      );
      expect(inserted, containsPair('revision', 1));

      await db.insert('groups', <String, Object?>{
        'id': 'group-replace',
        'name': 'Replaced group',
        'type': 'qa',
        'topic_name': '/mknoon/groups/group-replace',
        'created_at': _t0,
        'created_by': 'peer-creator',
        'my_role': 'admin',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(
          db,
          'group-replace',
        ),
        allOf(
          containsPair('revision', 2),
          containsPair('incarnation_id', inserted!['incarnation_id']),
        ),
      );
    },
  );

  test(
    'type and dissolved timestamp independently enqueue policy invalidation',
    () async {
      await _insertGroup(db, 'group-policy-fields');

      await db.update(
        'groups',
        const <String, Object?>{'type': 'qa'},
        where: 'id = ?',
        whereArgs: const <Object?>['group-policy-fields'],
      );
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(
          db,
          'group-policy-fields',
        ),
        containsPair('revision', 1),
      );

      await db.update(
        'groups',
        const <String, Object?>{'dissolved_at': _t1},
        where: 'id = ?',
        whereArgs: const <Object?>['group-policy-fields'],
      );
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(
          db,
          'group-policy-fields',
        ),
        containsPair('revision', 2),
      );

      await db.update(
        'groups',
        const <String, Object?>{'dissolved_at': _t1},
        where: 'id = ?',
        whereArgs: const <Object?>['group-policy-fields'],
      );
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(
          db,
          'group-policy-fields',
        ),
        containsPair('revision', 2),
      );
    },
  );

  test('member deletion durably invalidates and coalesces by group', () async {
    await _insertGroup(db, 'group-membership');
    await _insertGroupMember(
      db,
      groupId: 'group-membership',
      peerId: 'peer-self',
    );
    await _insertGroupMember(
      db,
      groupId: 'group-membership',
      peerId: 'peer-other',
    );

    await db.delete(
      'group_members',
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: const <Object?>['group-membership', 'peer-other'],
    );
    await db.delete(
      'group_members',
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: const <Object?>['group-membership', 'peer-self'],
    );

    expect(
      await dbLoadGroupNotificationReconciliationOutboxEntry(
        db,
        'group-membership',
      ),
      allOf(
        containsPair('group_id', 'group-membership'),
        containsPair('revision', 2),
      ),
    );
  });

  test(
    'mute archive dissolve self-removal and delete atomically coalesce one surviving row',
    () async {
      await _insertGroup(db, 'group-policy');
      expect(
        await db.query('group_notification_reconciliation_outbox'),
        isEmpty,
      );

      await db.update(
        'groups',
        const <String, Object?>{'is_muted': 1},
        where: 'id = ?',
        whereArgs: const <Object?>['group-policy'],
      );
      final first = await dbLoadGroupNotificationReconciliationOutboxEntry(
        db,
        'group-policy',
      );
      expect(first, containsPair('revision', 1));

      expect(
        await dbRecordGroupNotificationReconciliationOutboxFailureIfExact(
          db,
          groupId: 'group-policy',
          expectedIncarnationId: first!['incarnation_id'] as String,
          expectedRevision: 1,
          lastAttemptAt: _t1,
          nextAttemptAt: _t2,
          updatedAt: _t1,
        ),
        isTrue,
      );
      await db.update(
        'groups',
        const <String, Object?>{'is_archived': 1, 'archived_at': _t1},
        where: 'id = ?',
        whereArgs: const <Object?>['group-policy'],
      );
      await db.update(
        'groups',
        const <String, Object?>{
          'is_dissolved': 1,
          'dissolved_at': _t1,
          'dissolved_by': 'peer-admin',
        },
        where: 'id = ?',
        whereArgs: const <Object?>['group-policy'],
      );
      await db.update(
        'groups',
        const <String, Object?>{'self_removed_at': _t2},
        where: 'id = ?',
        whereArgs: const <Object?>['group-policy'],
      );

      final coalesced = await dbLoadGroupNotificationReconciliationOutboxEntry(
        db,
        'group-policy',
      );
      expect(
        coalesced,
        allOf(
          containsPair('revision', 5),
          containsPair('retry_count', 0),
          containsPair('last_attempt_at', isNull),
          containsPair('next_attempt_at', isNull),
          containsPair('incarnation_id', first['incarnation_id']),
        ),
      );

      await db.update(
        'groups',
        const <String, Object?>{'self_removed_at': _t2},
        where: 'id = ?',
        whereArgs: const <Object?>['group-policy'],
      );
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(
          db,
          'group-policy',
        ),
        containsPair('revision', 5),
      );

      await db.delete(
        'groups',
        where: 'id = ?',
        whereArgs: const <Object?>['group-policy'],
      );
      expect(
        await db.query(
          'groups',
          where: 'id = ?',
          whereArgs: const <Object?>['group-policy'],
        ),
        isEmpty,
      );
      await db.close();
      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(
          db,
          'group-policy',
        ),
        allOf(
          containsPair('revision', 6),
          containsPair('retry_count', 0),
          containsPair('next_attempt_at', isNull),
        ),
      );
    },
  );

  test('group-message deletion enqueues and coalesces its group', () async {
    await _insertGroup(db, 'group-message-delete');
    await _insertGroupMessage(
      db,
      groupId: 'group-message-delete',
      messageId: 'message-delete-a',
    );
    await _insertGroupMessage(
      db,
      groupId: 'group-message-delete',
      messageId: 'message-delete-b',
    );

    await db.delete(
      'group_messages',
      where: 'id = ?',
      whereArgs: const <Object?>['message-delete-a'],
    );
    await db.delete(
      'group_messages',
      where: 'id = ?',
      whereArgs: const <Object?>['message-delete-b'],
    );

    expect(
      await dbLoadGroupNotificationReconciliationOutboxEntry(
        db,
        'group-message-delete',
      ),
      allOf(
        containsPair('group_id', 'group-message-delete'),
        containsPair('revision', 2),
      ),
    );
  });

  test(
    'reaction-only conversation acknowledgement survives reopen for startup reconciliation',
    () async {
      await _insertGroup(db, 'group-read-reopen');
      await db.insert('group_messages', <String, Object?>{
        'id': 'reaction-target',
        'group_id': 'group-read-reopen',
        'sender_peer_id': 'peer-self',
        'text': 'outgoing target',
        'timestamp': _t0,
        'created_at': _t0,
        'is_incoming': 0,
      });
      await db.insert('message_reactions', <String, Object?>{
        'id': 'reaction-before-read',
        'message_id': 'reaction-target',
        'emoji': '👍',
        'sender_peer_id': 'peer-reactor',
        'timestamp': _t1,
        'created_at': _t1,
        'notification_display_terminal_event_id': 'event-before-read',
      });

      expect(await dbMarkGroupMessagesAsRead(db, 'group-read-reopen'), 0);
      await db.close();
      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );

      expect(
        (await db.query(
          'message_reactions',
          where: 'id = ?',
          whereArgs: const <Object?>['reaction-before-read'],
        )).single['notification_acknowledged_at'],
        isNotNull,
      );
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(
          db,
          'group-read-reopen',
        ),
        isNotNull,
      );
      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-read-reopen',
          selfPeerId: 'peer-self',
          eventIdentity: 'event-before-read',
        ),
        GroupNotificationCanonicalContentDecision.retire,
      );
    },
  );

  test(
    'group-message read commit durably enqueues exactly on null transition',
    () async {
      await _insertGroup(db, 'group-message-read');
      await _insertGroupMessage(
        db,
        groupId: 'group-message-read',
        messageId: 'message-read',
      );

      await db.update(
        'group_messages',
        const <String, Object?>{'read_at': _t1},
        where: 'id = ?',
        whereArgs: const <Object?>['message-read'],
      );
      final first = await dbLoadGroupNotificationReconciliationOutboxEntry(
        db,
        'group-message-read',
      );
      expect(first, containsPair('revision', 1));

      await db.update(
        'group_messages',
        const <String, Object?>{'read_at': _t2},
        where: 'id = ?',
        whereArgs: const <Object?>['message-read'],
      );
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(
          db,
          'group-message-read',
        ),
        containsPair('revision', 1),
      );
    },
  );

  test(
    'accepted and exact-replay group REMOVE enqueue reconciliation',
    () async {
      await _insertGroup(db, 'group-remove');
      await _insertGroupMessage(
        db,
        groupId: 'group-remove',
        messageId: 'message-remove',
      );
      final row = _removeRow(
        id: 'reaction-remove',
        messageId: 'message-remove',
      );

      expect(
        await dbApplyIncomingReactionMutation(
          db,
          row,
          mutation: DbIncomingReactionMutation.remove,
          groupIdForNotificationCleanup: 'group-remove',
        ),
        DbIncomingReactionApplyResult.removed,
      );
      final accepted = await dbLoadGroupNotificationReconciliationOutboxEntry(
        db,
        'group-remove',
      );
      expect(accepted, containsPair('revision', 1));

      expect(
        await dbApplyIncomingReactionMutation(
          db,
          row,
          mutation: DbIncomingReactionMutation.remove,
          groupIdForNotificationCleanup: 'group-remove',
        ),
        DbIncomingReactionApplyResult.exactReplay,
      );
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(
          db,
          'group-remove',
        ),
        allOf(
          containsPair('revision', 2),
          containsPair('incarnation_id', accepted!['incarnation_id']),
        ),
      );
    },
  );

  test(
    'accepted direct REMOVE does not enqueue group reconciliation',
    () async {
      expect(
        await dbApplyIncomingReactionMutation(
          db,
          _removeRow(id: 'direct-remove', messageId: 'direct-message'),
          mutation: DbIncomingReactionMutation.remove,
        ),
        DbIncomingReactionApplyResult.removed,
      );
      expect(
        await db.query('group_notification_reconciliation_outbox'),
        isEmpty,
      );
    },
  );

  test('stale group REMOVE does not enqueue reconciliation', () async {
    await _insertGroup(db, 'group-stale-remove');
    await _insertGroupMessage(
      db,
      groupId: 'group-stale-remove',
      messageId: 'message-stale-remove',
    );
    expect(
      await dbApplyIncomingReactionMutation(
        db,
        _removeRow(
          id: 'newer-remove',
          messageId: 'message-stale-remove',
          timestamp: _t2,
        ),
        mutation: DbIncomingReactionMutation.remove,
      ),
      DbIncomingReactionApplyResult.removed,
    );

    expect(
      await dbApplyIncomingReactionMutation(
        db,
        _removeRow(
          id: 'older-remove',
          messageId: 'message-stale-remove',
          timestamp: _t1,
        ),
        mutation: DbIncomingReactionMutation.remove,
        groupIdForNotificationCleanup: 'group-stale-remove',
      ),
      DbIncomingReactionApplyResult.stale,
    );
    expect(await db.query('group_notification_reconciliation_outbox'), isEmpty);
  });

  test(
    'exact completion rejects delete-reinsert ABA for one group id',
    () async {
      final repository = _repository(db, now: () => DateTime.parse(_t1));
      await dbEnqueueGroupNotificationReconciliationOutbox(
        db,
        groupId: 'group-aba',
      );
      final first = (await repository.loadEligible()).single;
      expect(await repository.completeIfExact(first), isTrue);

      await dbEnqueueGroupNotificationReconciliationOutbox(
        db,
        groupId: 'group-aba',
      );
      final replacement = (await repository.loadEligible()).single;
      expect(replacement.revision, first.revision);
      expect(replacement.incarnationId, isNot(first.incarnationId));

      expect(await repository.completeIfExact(first), isFalse);
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(db, 'group-aba'),
        containsPair('incarnation_id', replacement.incarnationId),
      );
    },
  );

  test(
    'failure CAS persists and enforces its earliest retry deadline',
    () async {
      var now = DateTime.parse(_t1);
      final repository = _repository(db, now: () => now);
      await dbEnqueueGroupNotificationReconciliationOutbox(
        db,
        groupId: 'group-retry',
      );
      final pristine = (await repository.loadEligible()).single;

      expect(
        await repository.recordFailureIfExact(
          expected: pristine,
          nextAttemptAt: DateTime.parse(_t2),
        ),
        isTrue,
      );
      expect(
        await repository.recordFailureIfExact(
          expected: pristine,
          nextAttemptAt: DateTime.parse(_t2),
        ),
        isFalse,
      );
      expect(await repository.loadEligible(), isEmpty);
      expect(await repository.loadEarliestNextAttemptAt(), DateTime.parse(_t2));

      now = DateTime.parse(_t2);
      expect(
        (await repository.loadEligible()).single,
        isA<GroupNotificationReconciliationOutboxEntry>()
            .having((entry) => entry.revision, 'revision', 2)
            .having((entry) => entry.retryCount, 'retryCount', 1)
            .having((entry) => entry.lastAttemptAt, 'lastAttemptAt', _t1)
            .having((entry) => entry.nextAttemptAt, 'nextAttemptAt', _t2),
      );
    },
  );
}
