// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/106_group_notification_display_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/groups/data/repositories/group_notification_display_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _t0 = '2026-08-02T20:00:00.000Z';
const _t1 = '2026-08-02T20:00:01.000Z';
const _t2 = '2026-08-02T20:00:02.000Z';

GroupNotificationDisplayOutboxEntry _message(
  String eventId, {
  String groupId = 'group-a',
  String messageId = 'message-a',
  String timestamp = _t0,
}) => GroupNotificationDisplayOutboxEntry.message(
  eventId: eventId,
  groupId: groupId,
  messageId: messageId,
  actorPeerId: 'peer-sender',
  eventTimestamp: timestamp,
  createdAt: _t0,
  updatedAt: _t0,
);

GroupNotificationDisplayOutboxEntry _reaction(
  String eventId, {
  String groupId = 'group-a',
  String messageId = 'message-a',
  String reactionId = 'reaction-a',
  bool tombstone = false,
  String timestamp = _t0,
}) => GroupNotificationDisplayOutboxEntry.reaction(
  eventId: eventId,
  groupId: groupId,
  messageId: messageId,
  actorPeerId: 'peer-reactor',
  eventTimestamp: timestamp,
  reactionId: reactionId,
  reactionAction: tombstone ? 'remove' : 'add',
  reactionTombstone: tombstone,
  createdAt: _t0,
  updatedAt: _t0,
);

Map<String, Object?> _legacyReactionReplayRow(String id) => <String, Object?>{
  'reaction_id': id,
  'group_id': 'legacy-group',
  'message_id': 'legacy-message',
  'sender_peer_id': 'legacy-peer',
  'emoji': '\u{1F44D}',
  'action': 'add',
  'inbox_retry_payload': '{"kind":"group-reaction"}',
  'delivery_status': 'failed',
  'last_error': 'legacy-error',
  'created_at': _t0,
  'updated_at': _t0,
};

Future<bool> _completeDisplayEntry(
  Database db,
  GroupNotificationDisplayOutboxEntry expected,
) => dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
  db,
  eventId: expected.eventId,
  expectedRevision: expected.revision,
  expectedEventKind: expected.eventKind,
  expectedGroupId: expected.groupId,
  expectedMessageId: expected.messageId,
  expectedActorPeerId: expected.actorPeerId,
  expectedEventTimestamp: expected.eventTimestamp,
  expectedReactionId: expected.reactionId,
  expectedReactionAction: expected.reactionAction,
  expectedReactionTombstone: expected.reactionTombstone,
  completedAt: _t0,
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String path;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'group_notification_display_outbox_v106_',
    );
    path = '${tempDir.path}/identity.db';
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'v105 to v106 and fresh create install an identifier-only no-FK outbox losslessly and idempotently',
    () async {
      final predecessor = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 105,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      await predecessor.insert(
        'group_reaction_replay_outbox',
        _legacyReactionReplayRow('legacy-reaction'),
      );
      await predecessor.close();

      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      );
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });

      expect(currentIdentityDatabaseVersion, 117);
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        117,
      );
      expect(await db.query('group_reaction_replay_outbox'), hasLength(1));

      final columns = await db.rawQuery(
        'PRAGMA table_info(group_notification_display_outbox)',
      );
      expect(columns.map((row) => row['name']).toList(), <String>[
        'event_id',
        'event_kind',
        'group_id',
        'message_id',
        'actor_peer_id',
        'event_timestamp',
        'reaction_id',
        'reaction_action',
        'reaction_tombstone',
        'readiness',
        'revision',
        'retry_count',
        'last_error_code',
        'last_attempt_at',
        'next_attempt_at',
        'created_at',
        'updated_at',
      ]);
      expect(
        columns.map((row) => row['name']),
        isNot(
          containsAll(<String>[
            'title',
            'body',
            'copy',
            'text',
            'emoji',
            'payload',
          ]),
        ),
      );
      expect(
        (await db.rawQuery(
          'PRAGMA table_info(group_messages)',
        )).map((row) => row['name']),
        contains('notification_display_terminal_event_id'),
      );
      expect(
        (await db.rawQuery(
          'PRAGMA table_info(message_reactions)',
        )).map((row) => row['name']),
        containsAll(<String>[
          'notification_display_terminal_event_id',
          'notification_acknowledged_at',
        ]),
      );
      expect(
        await db.rawQuery(
          'PRAGMA foreign_key_list(group_notification_display_outbox)',
        ),
        isEmpty,
      );
      final acknowledgementColumns = await db.rawQuery(
        'PRAGMA table_info(group_notification_read_acknowledgements)',
      );
      expect(
        acknowledgementColumns.map((row) => row['name']).toList(),
        <String>[
          'group_id',
          'content_kind',
          'event_identity',
          'generation',
          'acknowledged_at',
        ],
      );
      expect(
        await db.rawQuery(
          'PRAGMA foreign_key_list('
          'group_notification_read_acknowledgements)',
        ),
        isEmpty,
      );
      final migrationInventory =
          await MigrationDatabaseSchemaInventory.fromDatabase(db);
      expect(
        migrationInventory.tableNames,
        containsAll(<String>[
          'group_notification_display_outbox',
          'group_notification_read_acknowledgements',
        ]),
      );
      expect(
        migrationInventory.tables['group_notification_display_outbox'],
        containsAll(<String>['event_id', 'readiness', 'revision']),
      );
      final indexes = (await db.rawQuery(
        "PRAGMA index_list('group_notification_display_outbox')",
      )).map((row) => row['name']).toSet();
      expect(
        indexes,
        containsAll(<String>{
          'idx_group_notification_display_outbox_ready',
          'idx_group_notification_display_outbox_group_message',
          'idx_group_notification_display_outbox_reaction',
        }),
      );
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = ?",
          const <Object?>[
            'trg_group_message_delete_clear_reaction_notification_terminal',
          ],
        ),
        isEmpty,
        reason:
            'target deletion must retain the exact identifier-only event '
            'binding until canonical reconciliation retires the OS card',
      );

      final migration = productionUpgradeMigrations.singleWhere(
        (entry) => entry.version == 106,
      );
      expect(migration.name, '106_group_notification_display_outbox');
      expect(migration.run, same(runGroupNotificationDisplayOutboxMigration));
      final createIndex = productionCreateMigrations.indexWhere(
        (entry) => entry.version == 106,
      );
      expect(productionCreateMigrations[createIndex + 1].version, 107);
      await migration.run(db);
      await migration.run(db);
      expect(await db.query('group_notification_display_outbox'), isEmpty);

      await expectLater(
        db.insert(
          'group_notification_display_outbox',
          _message('invalid-message').toMap()
            ..['reaction_id'] = 'must-not-exist',
        ),
        throwsA(anything),
      );

      final freshPath = '${tempDir.path}/fresh.db';
      final fresh = await databaseFactoryFfi.openDatabase(
        freshPath,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      );
      expect(await fresh.query('group_notification_display_outbox'), isEmpty);
      expect(
        await fresh.query('group_notification_read_acknowledgements'),
        isEmpty,
      );
      expect(
        (await fresh.rawQuery('PRAGMA user_version')).single.values.single,
        117,
      );
      await fresh.close();
    },
  );

  test(
    'read acknowledgement custody is exact and refuses capacity eviction',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);

      for (
        var index = 0;
        index < maxPendingGroupNotificationReadAcknowledgements;
        index += 1
      ) {
        expect(
          await dbRecordExactGroupNotificationReadAcknowledgement(
            db,
            groupId: 'group-$index',
            contentKind: index.isEven ? 'message' : 'reaction',
            eventIdentity: 'event-$index',
            generation: 'generation-$index',
            acknowledgedAt: _t0,
          ),
          isTrue,
        );
      }
      expect(
        await db.query('group_notification_read_acknowledgements'),
        hasLength(maxPendingGroupNotificationReadAcknowledgements),
      );
      expect(
        await dbRecordExactGroupNotificationReadAcknowledgement(
          db,
          groupId: 'group-0',
          contentKind: 'message',
          eventIdentity: 'event-0',
          generation: 'generation-0',
          acknowledgedAt: _t1,
        ),
        isTrue,
        reason: 'an idempotent exact tuple does not consume capacity',
      );
      await expectLater(
        dbRecordExactGroupNotificationReadAcknowledgement(
          db,
          groupId: 'overflow-group',
          contentKind: 'reaction',
          eventIdentity: 'overflow-event',
          generation: 'overflow-generation',
          acknowledgedAt: _t1,
        ),
        throwsStateError,
      );
      expect(
        await dbLoadExactGroupNotificationReadAcknowledgement(
          db,
          groupId: 'group-0',
          contentKind: 'message',
          eventIdentity: 'event-0',
          generation: 'generation-0',
        ),
        containsPair('acknowledged_at', _t1),
      );
      expect(
        await db.query('group_notification_read_acknowledgements'),
        hasLength(maxPendingGroupNotificationReadAcknowledgements),
      );
    },
  );

  test(
    'stage is exact and fail-closed at capacity without evicting custody',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);

      final first = _message('event-1');
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        first.toMap(),
        capacity: 2,
      );
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        first.toMap(),
        capacity: 2,
      );
      expect(await db.query('group_notification_display_outbox'), hasLength(1));

      await expectLater(
        dbStageGroupNotificationDisplayOutboxEntry(
          db,
          _message('event-1', messageId: 'conflicting-message').toMap(),
          capacity: 2,
        ),
        throwsStateError,
      );
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        _reaction('event-2').toMap(),
        capacity: 2,
      );
      await expectLater(
        dbStageGroupNotificationDisplayOutboxEntry(
          db,
          _message('event-3').toMap(),
          capacity: 2,
        ),
        throwsStateError,
      );
      expect(
        (await db.query(
          'group_notification_display_outbox',
          orderBy: 'event_id',
        )).map((row) => row['event_id']),
        <String>['event-1', 'event-2'],
      );

      await db.delete('group_notification_display_outbox');
      final concurrent = await Future.wait(
        <GroupNotificationDisplayOutboxEntry>[
          _message('concurrent-a'),
          _message('concurrent-b'),
        ].map((entry) async {
          try {
            await dbStageGroupNotificationDisplayOutboxEntry(
              db,
              entry.toMap(),
              capacity: 1,
            );
            return 'staged';
          } on StateError {
            return 'capacity';
          }
        }),
      );
      expect(concurrent.where((result) => result == 'staged'), hasLength(1));
      expect(concurrent.where((result) => result == 'capacity'), hasLength(1));
      expect(await db.query('group_notification_display_outbox'), hasLength(1));
    },
  );

  test(
    'ready retry and completion use exact revisions and bounded oldest-first loading',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);

      await db.insert('group_messages', <String, Object?>{
        'id': 'message-a',
        'group_id': 'group-a',
        'sender_peer_id': 'peer-sender',
        'text': 'retry target',
        'timestamp': _t0,
        'created_at': _t0,
      });
      await dbInsertReaction(db, <String, Object?>{
        'id': 'reaction-a',
        'message_id': 'message-a',
        'emoji': '\u{1F44D}',
        'sender_peer_id': 'peer-reactor',
        'timestamp': _t0,
        'created_at': _t0,
      });
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        _message(
          'later',
          timestamp: _t1,
        ).copyWith(createdAt: _t1, updatedAt: _t1).toMap(),
      );
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        _reaction('earlier').toMap(),
      );
      expect(
        await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
          db,
          eventId: 'earlier',
          expectedRevision: 9,
          updatedAt: _t1,
        ),
        isFalse,
      );
      for (final id in <String>['later', 'earlier']) {
        expect(
          await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
            db,
            eventId: id,
            expectedRevision: 1,
            updatedAt: _t1,
          ),
          isTrue,
        );
      }

      final ready = await dbLoadReadyGroupNotificationDisplayOutboxEntries(
        db,
        limit: 1,
        eligibleAt: _t2,
      );
      expect(ready, hasLength(1));
      expect(ready.single['event_id'], 'earlier');
      expect(ready.single['revision'], 2);

      await expectLater(
        dbRecordGroupNotificationDisplayOutboxRetryIfExact(
          db,
          eventId: 'earlier',
          expectedRevision: 2,
          lastErrorCode: 'SocketException: private host and stack',
          lastAttemptAt: _t1,
          nextAttemptAt: _t2,
          updatedAt: _t1,
        ),
        throwsA(anything),
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, 'earlier'),
        containsPair('revision', 2),
      );

      expect(
        await dbRecordGroupNotificationDisplayOutboxRetryIfExact(
          db,
          eventId: 'earlier',
          expectedRevision: 2,
          lastErrorCode: 'display_failed',
          lastAttemptAt: _t1,
          nextAttemptAt: '2026-08-02T21:00:00.000Z',
          updatedAt: _t1,
        ),
        isTrue,
      );
      expect(
        await _completeDisplayEntry(
          db,
          _reaction('earlier').copyWith(
            readiness: GroupNotificationDisplayOutboxReadiness.ready,
            revision: 2,
          ),
        ),
        isFalse,
      );
      final retried = await dbLoadGroupNotificationDisplayOutboxEntry(
        db,
        'earlier',
      );
      expect(retried, containsPair('revision', 3));
      expect(retried, containsPair('retry_count', 1));
      expect(
        await dbLoadReadyGroupNotificationDisplayOutboxEntries(
          db,
          limit: 20,
          eligibleAt: _t2,
        ),
        everyElement(isNot(containsPair('event_id', 'earlier'))),
      );
      expect(
        await _completeDisplayEntry(
          db,
          GroupNotificationDisplayOutboxEntry.fromMap(retried!),
        ),
        isTrue,
      );
    },
  );

  test(
    'group reaction remove atomically tombstones and retires only explicit actor custody',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);

      await db.insert('group_messages', <String, Object?>{
        'id': 'message-a',
        'group_id': 'group-a',
        'sender_peer_id': 'peer-self',
        'text': 'canonical target',
        'timestamp': _t0,
        'created_at': _t0,
      });
      await dbInsertReaction(db, <String, Object?>{
        'id': 'reaction-add',
        'message_id': 'message-a',
        'emoji': '\u{1F44D}',
        'sender_peer_id': 'peer-reactor',
        'timestamp': _t0,
        'created_at': _t0,
      });
      for (final entry in <GroupNotificationDisplayOutboxEntry>[
        _reaction('matching-add'),
        _reaction('sibling-actor').copyWith(actorPeerId: 'peer-other'),
        _reaction('sibling-group', groupId: 'group-b'),
        _message('message-marker'),
      ]) {
        await dbStageGroupNotificationDisplayOutboxEntry(db, entry.toMap());
      }

      final result = await dbApplyIncomingReactionMutation(
        db,
        <String, Object?>{
          'id': 'reaction-remove',
          'message_id': 'message-a',
          'emoji': '\u{1F44D}',
          'sender_peer_id': 'peer-reactor',
          'timestamp': _t1,
          'created_at': _t1,
        },
        mutation: DbIncomingReactionMutation.remove,
        groupIdForNotificationCleanup: 'group-a',
      );

      expect(result, DbIncomingReactionApplyResult.removed);
      expect(
        await dbLoadActiveOrTombstonedReactionForSender(
          db,
          'message-a',
          'peer-reactor',
        ),
        containsPair('removed_at', _t1),
      );
      expect(
        (await db.query(
          'group_notification_display_outbox',
          orderBy: 'event_id',
        )).map((row) => row['event_id']),
        <String>['message-marker', 'sibling-actor', 'sibling-group'],
      );
    },
  );

  test(
    'message alias reconciliation atomically promotes or rekeys canonical custody',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);

      for (final canonicalAlreadyExists in <bool>[true, false]) {
        final suffix = canonicalAlreadyExists ? 'existing' : 'rekey';
        final canonicalId = 'canonical-$suffix';
        final aliasId = 'alias-$suffix';
        if (canonicalAlreadyExists) {
          await dbStageGroupNotificationDisplayOutboxEntry(
            db,
            _message(canonicalId, messageId: canonicalId).toMap(),
          );
        }
        await dbStageGroupNotificationDisplayOutboxEntry(
          db,
          _message(aliasId, messageId: aliasId).toMap(),
        );

        expect(
          await dbReconcileGroupNotificationDisplayOutboxMessageAliasReady(
            db,
            aliasEventId: aliasId,
            canonicalEventId: canonicalId,
            groupId: 'group-a',
            actorPeerId: 'peer-sender',
            eventTimestamp: _t0,
            updatedAt: _t1,
          ),
          isTrue,
        );

        expect(
          await dbLoadGroupNotificationDisplayOutboxEntry(db, aliasId),
          isNull,
        );
        expect(
          await dbLoadGroupNotificationDisplayOutboxEntry(db, canonicalId),
          allOf(
            containsPair('readiness', 'ready'),
            containsPair('revision', 2),
            containsPair('message_id', canonicalId),
          ),
        );
      }
    },
  );

  test(
    'late logical alias after completed display retires without re-alerting',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      const canonicalId = 'canonical-terminal-display';
      const aliasId = 'very-late-reminted-alias';
      await db.insert('group_messages', <String, Object?>{
        'id': canonicalId,
        'group_id': 'group-a',
        'sender_peer_id': 'peer-sender',
        'text': 'canonical logical delivery',
        'timestamp': _t0,
        'logical_delivery_id': 'logical-terminal-display',
        'created_at': _t0,
      });
      final canonicalCustody = _message(canonicalId, messageId: canonicalId);
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        canonicalCustody.toMap(),
      );
      await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
        db,
        eventId: canonicalId,
        expectedRevision: 1,
        updatedAt: _t1,
      );
      expect(
        await _completeDisplayEntry(
          db,
          canonicalCustody.copyWith(
            readiness: GroupNotificationDisplayOutboxReadiness.ready,
            revision: 2,
          ),
        ),
        isTrue,
      );
      expect(
        (await db.query(
          'group_messages',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>[canonicalId],
        )).single['notification_display_terminal_event_id'],
        canonicalId,
      );

      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        _message(aliasId, messageId: aliasId).toMap(),
      );
      expect(
        await dbReconcileGroupNotificationDisplayOutboxMessageAliasReady(
          db,
          aliasEventId: aliasId,
          canonicalEventId: canonicalId,
          groupId: 'group-a',
          actorPeerId: 'peer-sender',
          eventTimestamp: _t0,
          updatedAt: _t1,
        ),
        isTrue,
      );

      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, aliasId),
        isNull,
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, canonicalId),
        isNull,
      );
      expect(
        await dbLoadReadyGroupNotificationDisplayOutboxEntries(
          db,
          eligibleAt: _t2,
        ),
        isEmpty,
      );
    },
  );

  test(
    'terminal alias reconciliation retains canonical READY until durable settlement',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      const canonicalId = 'canonical-terminal-ready';
      const aliasId = 'alias-after-terminal-ready';
      const correlation =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      await db.insert('group_messages', <String, Object?>{
        'id': canonicalId,
        'group_id': 'group-a',
        'sender_peer_id': 'peer-sender',
        'text': 'terminal retained raw custody',
        'timestamp': _t0,
        'created_at': _t0,
        'notification_display_terminal_event_id': canonicalId,
      });
      final ready = _message(canonicalId, messageId: canonicalId);
      await dbStageGroupNotificationDisplayOutboxEntry(db, ready.toMap());
      await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
        db,
        eventId: canonicalId,
        expectedRevision: 1,
        updatedAt: _t1,
      );
      final bound =
          await dbBindGroupNotificationDisplayOutboxDurableCorrelationIfExact(
            db,
            eventId: canonicalId,
            expectedRevision: 2,
            expectedEventKind: ready.eventKind,
            expectedGroupId: ready.groupId,
            expectedMessageId: ready.messageId,
            expectedActorPeerId: ready.actorPeerId,
            expectedEventTimestamp: ready.eventTimestamp,
            expectedReactionId: null,
            expectedReactionAction: null,
            expectedReactionTombstone: null,
            durableEventCorrelation: correlation,
            updatedAt: _t1,
          );
      expect(bound, isNotNull);
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        _message(aliasId, messageId: aliasId).toMap(),
      );

      expect(
        await dbReconcileGroupNotificationDisplayOutboxMessageAliasReady(
          db,
          aliasEventId: aliasId,
          canonicalEventId: canonicalId,
          groupId: 'group-a',
          actorPeerId: 'peer-sender',
          eventTimestamp: _t0,
          updatedAt: _t2,
        ),
        isTrue,
      );

      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, aliasId),
        isNull,
      );
      final retained = await dbLoadGroupNotificationDisplayOutboxEntry(
        db,
        canonicalId,
      );
      expect(retained, containsPair('readiness', 'ready'));
      expect(
        groupNotificationDisplayDurableCorrelationFromMarker(
          retained?['last_attempt_at'] as String?,
        ),
        correlation,
      );
    },
  );

  test(
    'protected exact-terminal duplicate branches retain correlation-bound READY',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      const groupId = 'group-protected-terminal';
      const messageId = 'message-protected-terminal';
      const reactionId = 'reaction-protected-terminal';
      const actorPeerId = 'peer-protected-actor';
      const timestamp = '2026-08-02T20:00:00.000000Z';
      const correlation =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      await db.insert('groups', const <String, Object?>{
        'id': groupId,
        'name': 'Protected terminal group',
        'type': 'chat',
        'topic_name': 'protected-terminal-topic',
        'created_at': timestamp,
        'created_by': 'peer-self',
        'my_role': 'admin',
      });
      await db.insert('group_messages', const <String, Object?>{
        'id': messageId,
        'group_id': groupId,
        'sender_peer_id': 'peer-self',
        'text': 'protected reaction target',
        'timestamp': timestamp,
        'created_at': timestamp,
      });
      final transitionId = buildGroupReactionTransitionId(
        groupId: groupId,
        messageId: messageId,
        logicalActorPeerId: actorPeerId,
        action: 'add',
        emoji: '👍',
        timestamp: DateTime.parse(timestamp),
      );
      final reactionRow = <String, Object?>{
        'id': reactionId,
        'message_id': messageId,
        'emoji': '👍',
        'sender_peer_id': actorPeerId,
        'timestamp': timestamp,
        'created_at': timestamp,
      };
      final eventPayload = <String, Object?>{
        'custodyKind': 'group_content_v1',
        'groupId': groupId,
        'payloadType': 'group_reaction',
        'contentEventId': transitionId,
        'logicalSenderPeerId': actorPeerId,
        'payload': <String, Object?>{
          'id': reactionId,
          'eventId': transitionId,
          'messageId': messageId,
          'senderPeerId': actorPeerId,
          'action': 'add',
          'timestamp': timestamp,
        },
      };
      final ready = GroupNotificationDisplayOutboxEntry.reaction(
        eventId: transitionId,
        groupId: groupId,
        messageId: messageId,
        actorPeerId: actorPeerId,
        eventTimestamp: timestamp,
        reactionId: reactionId,
        reactionAction: 'add',
        reactionTombstone: false,
        readiness: GroupNotificationDisplayOutboxReadiness.ready,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(
        await dbCommitProtectedGroupReaction(
          db,
          groupId: groupId,
          sourcePeerId: actorPeerId,
          sourceEventId: 'pr1:$transitionId',
          sourceTimestamp: timestamp,
          eventPayload: eventPayload,
          reactionRow: reactionRow,
          transitionId: transitionId,
          action: 'add',
          readyDisplayOutboxRow: ready.toMap(),
        ),
        DbProtectedGroupContentCommitResult.applied,
      );
      expect(
        await dbBindGroupNotificationDisplayOutboxDurableCorrelationIfExact(
          db,
          eventId: ready.eventId,
          expectedRevision: ready.revision,
          expectedEventKind: ready.eventKind,
          expectedGroupId: ready.groupId,
          expectedMessageId: ready.messageId,
          expectedActorPeerId: ready.actorPeerId,
          expectedEventTimestamp: ready.eventTimestamp,
          expectedReactionId: ready.reactionId,
          expectedReactionAction: ready.reactionAction,
          expectedReactionTombstone: ready.reactionTombstone,
          durableEventCorrelation: correlation,
          updatedAt: timestamp,
        ),
        isNotNull,
      );
      expect(
        await dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
          db,
          eventId: ready.eventId,
          expectedRevision: ready.revision,
          expectedEventKind: ready.eventKind,
          expectedGroupId: ready.groupId,
          expectedMessageId: ready.messageId,
          expectedActorPeerId: ready.actorPeerId,
          expectedEventTimestamp: ready.eventTimestamp,
          expectedReactionId: ready.reactionId,
          expectedReactionAction: ready.reactionAction,
          expectedReactionTombstone: ready.reactionTombstone,
          completedAt: timestamp,
          durableEventCorrelation: correlation,
        ),
        DurableLocalNotificationSqlHandoffResult.committed,
      );

      expect(
        await dbCommitProtectedGroupReaction(
          db,
          groupId: groupId,
          sourcePeerId: actorPeerId,
          sourceEventId: 'pr1:$transitionId',
          sourceTimestamp: timestamp,
          eventPayload: eventPayload,
          reactionRow: reactionRow,
          transitionId: transitionId,
          action: 'add',
          readyDisplayOutboxRow: ready.toMap(),
        ),
        DbProtectedGroupContentCommitResult.exactDuplicate,
      );
      var retained = await dbLoadGroupNotificationDisplayOutboxEntry(
        db,
        transitionId,
      );
      expect(retained, containsPair('readiness', 'ready'));
      expect(
        groupNotificationDisplayDurableCorrelationFromMarker(
          retained?['last_attempt_at'] as String?,
        ),
        correlation,
      );

      await db.delete(
        'message_reactions',
        where: 'id = ?',
        whereArgs: const <Object?>[reactionId],
      );
      expect(
        await dbCommitProtectedGroupReaction(
          db,
          groupId: groupId,
          sourcePeerId: actorPeerId,
          sourceEventId: 'pr1:$transitionId',
          sourceTimestamp: timestamp,
          eventPayload: eventPayload,
          reactionRow: reactionRow,
          transitionId: transitionId,
          action: 'add',
          readyDisplayOutboxRow: ready.toMap(),
        ),
        DbProtectedGroupContentCommitResult.applied,
      );
      retained = await dbLoadGroupNotificationDisplayOutboxEntry(
        db,
        transitionId,
      );
      expect(retained, containsPair('readiness', 'ready'));
      expect(
        groupNotificationDisplayDurableCorrelationFromMarker(
          retained?['last_attempt_at'] as String?,
        ),
        correlation,
      );
      expect(
        await db.query(
          'group_notification_reconciliation_outbox',
          where: 'group_id = ?',
          whereArgs: const <Object?>[groupId],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'settled group display retires exact READY without immediate reconciliation',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      const eventId = 'settled-group-message';
      const correlation =
          'abababababababababababababababababababababababababababababababab';
      await db.insert('group_messages', <String, Object?>{
        'id': eventId,
        'group_id': 'group-a',
        'sender_peer_id': 'peer-sender',
        'text': 'one settled group notification',
        'timestamp': _t0,
        'created_at': _t0,
      });
      final custody = _message(eventId, messageId: eventId);
      await dbStageGroupNotificationDisplayOutboxEntry(db, custody.toMap());
      expect(
        await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
          db,
          eventId: eventId,
          expectedRevision: 1,
          updatedAt: _t1,
        ),
        isTrue,
      );
      final ready = GroupNotificationDisplayOutboxEntry.fromMap(
        (await dbBindGroupNotificationDisplayOutboxDurableCorrelationIfExact(
          db,
          eventId: eventId,
          expectedRevision: 2,
          expectedEventKind: custody.eventKind,
          expectedGroupId: custody.groupId,
          expectedMessageId: custody.messageId,
          expectedActorPeerId: custody.actorPeerId,
          expectedEventTimestamp: custody.eventTimestamp,
          expectedReactionId: custody.reactionId,
          expectedReactionAction: custody.reactionAction,
          expectedReactionTombstone: custody.reactionTombstone,
          durableEventCorrelation: correlation,
          updatedAt: _t1,
        ))!,
      );
      expect(
        await dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
          db,
          eventId: ready.eventId,
          expectedRevision: ready.revision,
          expectedEventKind: ready.eventKind,
          expectedGroupId: ready.groupId,
          expectedMessageId: ready.messageId,
          expectedActorPeerId: ready.actorPeerId,
          expectedEventTimestamp: ready.eventTimestamp,
          expectedReactionId: ready.reactionId,
          expectedReactionAction: ready.reactionAction,
          expectedReactionTombstone: ready.reactionTombstone,
          completedAt: _t2,
          durableEventCorrelation: correlation,
        ),
        DurableLocalNotificationSqlHandoffResult.committed,
      );
      expect(
        await db.query(
          'group_notification_reconciliation_outbox',
          where: 'group_id = ?',
          whereArgs: const <Object?>['group-a'],
        ),
        isEmpty,
      );

      expect(
        await dbRetireGroupNotificationDisplayOutboxAfterDurableSettlementIfExact(
          db,
          eventId: ready.eventId,
          expectedRevision: ready.revision,
          expectedEventKind: ready.eventKind,
          expectedGroupId: ready.groupId,
          expectedMessageId: ready.messageId,
          expectedActorPeerId: ready.actorPeerId,
          expectedEventTimestamp: ready.eventTimestamp,
          expectedReactionId: ready.reactionId,
          expectedReactionAction: ready.reactionAction,
          expectedReactionTombstone: ready.reactionTombstone,
          durableEventCorrelation: correlation,
        ),
        isTrue,
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, eventId),
        isNull,
      );
      expect(
        await db.query(
          'group_notification_reconciliation_outbox',
          where: 'group_id = ?',
          whereArgs: const <Object?>['group-a'],
        ),
        isEmpty,
        reason:
            'a successfully settled display already published canonical content',
      );
    },
  );

  test(
    'message terminal marker and exact custody completion roll back together',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      const eventId = 'atomic-terminal-message';
      await db.insert('group_messages', <String, Object?>{
        'id': eventId,
        'group_id': 'group-a',
        'sender_peer_id': 'peer-sender',
        'text': 'atomic terminal fact',
        'timestamp': _t0,
        'created_at': _t0,
      });
      final custody = _message(eventId, messageId: eventId);
      await dbStageGroupNotificationDisplayOutboxEntry(db, custody.toMap());
      await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
        db,
        eventId: eventId,
        expectedRevision: 1,
        updatedAt: _t1,
      );
      await db.execute('''
        CREATE TRIGGER reject_terminal_custody_delete
        BEFORE DELETE ON group_notification_display_outbox
        BEGIN
          SELECT RAISE(ABORT, 'injected completion failure');
        END
      ''');

      await expectLater(
        _completeDisplayEntry(
          db,
          custody.copyWith(
            readiness: GroupNotificationDisplayOutboxReadiness.ready,
            revision: 2,
          ),
        ),
        throwsA(anything),
      );

      expect(
        (await db.query(
          'group_messages',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>[eventId],
        )).single['notification_display_terminal_event_id'],
        isNull,
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, eventId),
        containsPair('readiness', 'ready'),
      );
    },
  );

  test(
    'late exact reaction ADD retires after terminal display while crash custody survives',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      await db.insert('group_messages', <String, Object?>{
        'id': 'message-a',
        'group_id': 'group-a',
        'sender_peer_id': 'peer-self',
        'text': 'reaction target',
        'timestamp': _t0,
        'created_at': _t0,
      });
      final reactionRow = <String, Object?>{
        'id': 'terminal-reaction-add',
        'message_id': 'message-a',
        'emoji': '\u{1F44D}',
        'sender_peer_id': 'peer-reactor',
        'timestamp': _t0,
        'created_at': _t0,
      };
      await dbInsertReaction(db, reactionRow);
      final custody = _reaction(
        'terminal-reaction-transition',
        reactionId: 'terminal-reaction-add',
      );
      await dbStageGroupNotificationDisplayOutboxEntry(db, custody.toMap());
      await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
        db,
        eventId: custody.eventId,
        expectedRevision: 1,
        updatedAt: _t1,
      );
      expect(
        await _completeDisplayEntry(
          db,
          custody.copyWith(
            readiness: GroupNotificationDisplayOutboxReadiness.ready,
            revision: 2,
          ),
        ),
        isTrue,
      );
      expect(
        (await db.query(
          'message_reactions',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>['terminal-reaction-add'],
        )).single['notification_display_terminal_event_id'],
        boundedReactionEventIdentity(custody.eventId),
      );

      await dbStageGroupNotificationDisplayOutboxEntry(db, custody.toMap());
      expect(
        await dbApplyIncomingReactionMutation(
          db,
          reactionRow,
          mutation: DbIncomingReactionMutation.add,
          groupIdForNotificationCleanup: 'group-a',
          notificationEventIdForStaleAddCleanup: custody.eventId,
        ),
        DbIncomingReactionApplyResult.exactReplay,
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, custody.eventId),
        isNull,
      );

      final newerAdd = <String, Object?>{
        'id': 'newer-reaction-add',
        'message_id': 'message-a',
        'emoji': '\u{1F389}',
        'sender_peer_id': 'peer-reactor',
        'timestamp': _t1,
        'created_at': _t1,
      };
      expect(
        await dbApplyIncomingReactionMutation(
          db,
          newerAdd,
          mutation: DbIncomingReactionMutation.add,
          groupIdForNotificationCleanup: 'group-a',
          notificationEventIdForStaleAddCleanup: 'newer-add-transition',
        ),
        DbIncomingReactionApplyResult.updated,
      );
      expect(
        (await db.query(
          'message_reactions',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'message_id = ? AND sender_peer_id = ?',
          whereArgs: const <Object?>['message-a', 'peer-reactor'],
        )).single['notification_display_terminal_event_id'],
        isNull,
      );
      await db.update(
        'message_reactions',
        const <String, Object?>{
          'notification_display_terminal_event_id': 'new-generation-terminal',
        },
        where: 'message_id = ? AND sender_peer_id = ?',
        whereArgs: const <Object?>['message-a', 'peer-reactor'],
      );
      expect(
        await dbApplyIncomingReactionMutation(
          db,
          <String, Object?>{
            'id': 'newer-reaction-remove',
            'message_id': 'message-a',
            'emoji': '\u{1F389}',
            'sender_peer_id': 'peer-reactor',
            'timestamp': _t2,
            'created_at': _t2,
          },
          mutation: DbIncomingReactionMutation.remove,
          groupIdForNotificationCleanup: 'group-a',
        ),
        DbIncomingReactionApplyResult.removed,
      );
      expect(
        (await db.query(
          'message_reactions',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'message_id = ? AND sender_peer_id = ?',
          whereArgs: const <Object?>['message-a', 'peer-reactor'],
        )).single['notification_display_terminal_event_id'],
        'new-generation-terminal',
      );

      const crashReactionId = 'crash-before-display-add';
      const crashEventId = 'crash-before-display-transition';
      final crashRow = <String, Object?>{
        'id': crashReactionId,
        'message_id': 'message-a',
        'emoji': '\u{1F44D}',
        'sender_peer_id': 'peer-crash',
        'timestamp': _t1,
        'created_at': _t1,
      };
      await dbInsertReaction(db, crashRow);
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        _reaction(
          crashEventId,
          reactionId: crashReactionId,
          timestamp: _t1,
        ).copyWith(actorPeerId: 'peer-crash').toMap(),
      );
      expect(
        await dbApplyIncomingReactionMutation(
          db,
          crashRow,
          mutation: DbIncomingReactionMutation.add,
          groupIdForNotificationCleanup: 'group-a',
          notificationEventIdForStaleAddCleanup: crashEventId,
        ),
        DbIncomingReactionApplyResult.exactReplay,
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, crashEventId),
        containsPair('readiness', 'not_ready'),
      );
    },
  );

  test(
    'exact reaction terminal replay preserves correlation-bound READY until settlement',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      const eventId = 'durable-reaction-terminal-replay';
      const reactionId = 'durable-reaction-id';
      const correlation =
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      const siblingEventId = 'durable-reaction-sibling';
      await db.insert('group_messages', <String, Object?>{
        'id': 'message-a',
        'group_id': 'group-a',
        'sender_peer_id': 'peer-self',
        'text': 'reaction terminal target',
        'timestamp': _t0,
        'created_at': _t0,
      });
      final reactionRow = <String, Object?>{
        'id': reactionId,
        'message_id': 'message-a',
        'emoji': '\u{1F44D}',
        'sender_peer_id': 'peer-reactor',
        'timestamp': _t0,
        'created_at': _t0,
      };
      await dbInsertReaction(db, reactionRow);
      final custody = _reaction(eventId, reactionId: reactionId);
      await dbStageGroupNotificationDisplayOutboxEntry(db, custody.toMap());
      await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
        db,
        eventId: eventId,
        expectedRevision: 1,
        updatedAt: _t1,
      );
      final bound =
          await dbBindGroupNotificationDisplayOutboxDurableCorrelationIfExact(
            db,
            eventId: eventId,
            expectedRevision: 2,
            expectedEventKind: custody.eventKind,
            expectedGroupId: custody.groupId,
            expectedMessageId: custody.messageId,
            expectedActorPeerId: custody.actorPeerId,
            expectedEventTimestamp: custody.eventTimestamp,
            expectedReactionId: custody.reactionId,
            expectedReactionAction: custody.reactionAction,
            expectedReactionTombstone: custody.reactionTombstone,
            durableEventCorrelation: correlation,
            updatedAt: _t1,
          );
      expect(bound, isNotNull);
      final sibling = _reaction(
        siblingEventId,
        reactionId: 'durable-reaction-sibling-id',
        timestamp: _t1,
      ).copyWith(actorPeerId: 'peer-sibling');
      await dbStageGroupNotificationDisplayOutboxEntry(db, sibling.toMap());
      await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
        db,
        eventId: siblingEventId,
        expectedRevision: 1,
        updatedAt: _t1,
      );

      expect(
        await dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
          db,
          eventId: eventId,
          expectedRevision: 2,
          expectedEventKind: custody.eventKind,
          expectedGroupId: custody.groupId,
          expectedMessageId: custody.messageId,
          expectedActorPeerId: custody.actorPeerId,
          expectedEventTimestamp: custody.eventTimestamp,
          expectedReactionId: custody.reactionId,
          expectedReactionAction: custody.reactionAction,
          expectedReactionTombstone: custody.reactionTombstone,
          completedAt: _t1,
          durableEventCorrelation: correlation,
        ),
        DurableLocalNotificationSqlHandoffResult.committed,
      );
      expect(
        await dbApplyIncomingReactionMutation(
          db,
          reactionRow,
          mutation: DbIncomingReactionMutation.add,
          groupIdForNotificationCleanup: 'group-a',
          notificationEventIdForStaleAddCleanup: eventId,
        ),
        DbIncomingReactionApplyResult.exactReplay,
      );

      final retained = await dbLoadGroupNotificationDisplayOutboxEntry(
        db,
        eventId,
      );
      expect(retained, containsPair('readiness', 'ready'));
      expect(retained, containsPair('revision', 3));
      expect(
        groupNotificationDisplayDurableCorrelationFromMarker(
          retained?['last_attempt_at'] as String?,
        ),
        correlation,
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, siblingEventId),
        isNotNull,
      );
      expect(
        await dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
          db,
          eventId: eventId,
          expectedRevision: 3,
          expectedEventKind: custody.eventKind,
          expectedGroupId: custody.groupId,
          expectedMessageId: custody.messageId,
          expectedActorPeerId: custody.actorPeerId,
          expectedEventTimestamp: custody.eventTimestamp,
          expectedReactionId: custody.reactionId,
          expectedReactionAction: custody.reactionAction,
          expectedReactionTombstone: custody.reactionTombstone,
          completedAt: _t2,
          durableEventCorrelation: correlation,
        ),
        DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
      );
      expect(
        await db.query(
          'group_notification_reconciliation_outbox',
          where: 'group_id = ?',
          whereArgs: const <Object?>['group-a'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'authority-exact completion rejects delete-reinsert ABA at one reaction event id',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      const reusedEventId = 'legacy-reused-event';
      final first = _reaction(
        reusedEventId,
        reactionId: reusedEventId,
        timestamp: _t0,
      );
      await dbStageGroupNotificationDisplayOutboxEntry(db, first.toMap());
      await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
        db,
        eventId: reusedEventId,
        expectedRevision: 1,
        updatedAt: _t0,
      );
      final staleCompletion = first.copyWith(
        readiness: GroupNotificationDisplayOutboxReadiness.ready,
        revision: 2,
      );

      await dbDeleteGroupNotificationDisplayOutboxForReactionActor(
        db,
        groupId: 'group-a',
        messageId: 'message-a',
        actorPeerId: 'peer-reactor',
      );
      final reAdd = _reaction(
        reusedEventId,
        reactionId: reusedEventId,
        timestamp: _t1,
      );
      await dbStageGroupNotificationDisplayOutboxEntry(db, reAdd.toMap());
      await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
        db,
        eventId: reusedEventId,
        expectedRevision: 1,
        updatedAt: _t1,
      );

      expect(await _completeDisplayEntry(db, staleCompletion), isFalse);
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, reusedEventId),
        allOf(
          containsPair('revision', 2),
          containsPair('event_timestamp', _t1),
        ),
      );
    },
  );

  test(
    'repository adapter preserves exact revisions and UTC retry metadata',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);

      await db.insert('group_messages', <String, Object?>{
        'id': 'message-a',
        'group_id': 'group-a',
        'sender_peer_id': 'peer-sender',
        'text': 'adapter target',
        'timestamp': _t0,
        'created_at': _t0,
      });
      var clock = DateTime.parse(_t1);
      final repository = GroupNotificationDisplayOutboxRepositoryImpl(
        dbStage: (row) => dbStageGroupNotificationDisplayOutboxEntry(db, row),
        dbLoadByEventId: (eventId) =>
            dbLoadGroupNotificationDisplayOutboxEntry(db, eventId),
        dbPromoteReadyIfExact:
            ({
              required eventId,
              required expectedRevision,
              required updatedAt,
            }) => dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
              db,
              eventId: eventId,
              expectedRevision: expectedRevision,
              updatedAt: updatedAt,
            ),
        dbLoadReady: ({limit = 20, required eligibleAt}) =>
            dbLoadReadyGroupNotificationDisplayOutboxEntries(
              db,
              limit: limit,
              eligibleAt: eligibleAt,
            ),
        dbLoadEarliestNextAttemptAt: () =>
            dbLoadEarliestGroupNotificationDisplayOutboxNextAttemptAt(db),
        dbRecordRetryIfExact:
            ({
              required eventId,
              required expectedRevision,
              required lastErrorCode,
              required lastAttemptAt,
              required nextAttemptAt,
              required updatedAt,
            }) => dbRecordGroupNotificationDisplayOutboxRetryIfExact(
              db,
              eventId: eventId,
              expectedRevision: expectedRevision,
              lastErrorCode: lastErrorCode,
              lastAttemptAt: lastAttemptAt,
              nextAttemptAt: nextAttemptAt,
              updatedAt: updatedAt,
            ),
        dbCompleteIfExact:
            ({
              required eventId,
              required expectedRevision,
              required expectedEventKind,
              required expectedGroupId,
              required expectedMessageId,
              required expectedActorPeerId,
              required expectedEventTimestamp,
              required expectedReactionId,
              required expectedReactionAction,
              required expectedReactionTombstone,
              required completedAt,
              outcome,
            }) => dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
              db,
              eventId: eventId,
              expectedRevision: expectedRevision,
              expectedEventKind: expectedEventKind,
              expectedGroupId: expectedGroupId,
              expectedMessageId: expectedMessageId,
              expectedActorPeerId: expectedActorPeerId,
              expectedEventTimestamp: expectedEventTimestamp,
              expectedReactionId: expectedReactionId,
              expectedReactionAction: expectedReactionAction,
              expectedReactionTombstone: expectedReactionTombstone,
              completedAt: completedAt,
              outcome: outcome,
            ),
        dbRetireIfExact:
            ({
              required eventId,
              required expectedRevision,
              required expectedEventKind,
              required expectedGroupId,
              required expectedMessageId,
              required expectedActorPeerId,
              required expectedEventTimestamp,
              required expectedReactionId,
              required expectedReactionAction,
              required expectedReactionTombstone,
            }) => dbRetireGroupNotificationDisplayOutboxEntryIfExact(
              db,
              eventId: eventId,
              expectedRevision: expectedRevision,
              expectedEventKind: expectedEventKind,
              expectedGroupId: expectedGroupId,
              expectedMessageId: expectedMessageId,
              expectedActorPeerId: expectedActorPeerId,
              expectedEventTimestamp: expectedEventTimestamp,
              expectedReactionId: expectedReactionId,
              expectedReactionAction: expectedReactionAction,
              expectedReactionTombstone: expectedReactionTombstone,
            ),
        dbReconcileMessageAliasReady:
            ({
              required aliasEventId,
              required canonicalEventId,
              required groupId,
              required actorPeerId,
              required eventTimestamp,
              required updatedAt,
            }) => dbReconcileGroupNotificationDisplayOutboxMessageAliasReady(
              db,
              aliasEventId: aliasEventId,
              canonicalEventId: canonicalEventId,
              groupId: groupId,
              actorPeerId: actorPeerId,
              eventTimestamp: eventTimestamp,
              updatedAt: updatedAt,
            ),
        dbDeleteForGroup: (groupId) =>
            dbDeleteGroupNotificationDisplayOutboxForGroup(db, groupId),
        dbDeleteForMessage: ({required groupId, required messageId}) =>
            dbDeleteGroupNotificationDisplayOutboxForMessage(
              db,
              groupId: groupId,
              messageId: messageId,
            ),
        dbDeleteForReaction:
            ({required groupId, required messageId, required reactionId}) =>
                dbDeleteGroupNotificationDisplayOutboxForReaction(
                  db,
                  groupId: groupId,
                  messageId: messageId,
                  reactionId: reactionId,
                ),
        dbDeleteForReactionActor:
            ({required groupId, required messageId, required actorPeerId}) =>
                dbDeleteGroupNotificationDisplayOutboxForReactionActor(
                  db,
                  groupId: groupId,
                  messageId: messageId,
                  actorPeerId: actorPeerId,
                ),
        now: () => clock,
      );

      await repository.stage(_message('adapter-event'));
      expect(
        await repository.loadByEventId('adapter-event'),
        isA<GroupNotificationDisplayOutboxEntry>()
            .having((entry) => entry.revision, 'revision', 1)
            .having((entry) => entry.isReady, 'isReady', isFalse),
      );
      expect(
        await repository.promoteReadyIfExact(
          eventId: 'adapter-event',
          expectedRevision: 1,
        ),
        isTrue,
      );
      expect((await repository.loadReady()).single.revision, 2);

      expect(
        await repository.recordRetryIfExact(
          eventId: 'adapter-event',
          expectedRevision: 2,
          lastErrorCode: 'claim_pending',
          nextAttemptAt: DateTime.parse(_t2),
        ),
        isTrue,
      );
      final retried = await repository.loadByEventId('adapter-event');
      expect(retried?.revision, 3);
      expect(retried?.retryCount, 1);
      expect(retried?.lastAttemptAt, _t1);
      expect(retried?.nextAttemptAt, _t2);
      expect(await repository.loadEarliestNextAttemptAt(), DateTime.parse(_t2));

      clock = DateTime.parse(_t2);
      expect((await repository.loadReady()).single.revision, 3);
      expect(await repository.completeIfExact(retried!), isTrue);
      expect(await repository.loadByEventId('adapter-event'), isNull);
    },
  );

  test(
    'group message and reaction cleanup is exact and preserves siblings',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);

      for (final entry in <GroupNotificationDisplayOutboxEntry>[
        _message('a-message'),
        _reaction('a-reaction-1', reactionId: 'reaction-1'),
        _reaction('a-reaction-2', reactionId: 'reaction-2'),
        _message('a-other-message', messageId: 'message-b'),
        _message('b-message', groupId: 'group-b'),
      ]) {
        await dbStageGroupNotificationDisplayOutboxEntry(db, entry.toMap());
      }

      expect(
        await dbDeleteGroupNotificationDisplayOutboxForReaction(
          db,
          groupId: 'group-a',
          messageId: 'message-a',
          reactionId: 'reaction-1',
        ),
        1,
      );
      expect(
        await dbDeleteGroupNotificationDisplayOutboxForMessage(
          db,
          groupId: 'group-a',
          messageId: 'message-a',
        ),
        2,
      );
      expect(
        await dbDeleteGroupNotificationDisplayOutboxForGroup(db, 'group-a'),
        1,
      );
      expect(
        (await db.query(
          'group_notification_display_outbox',
        )).single['event_id'],
        'b-message',
      );
    },
  );

  test(
    'message and group deletion retain bounded reaction terminal facts exactly',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      for (final row in <Map<String, Object?>>[
        {
          'id': 'delete-target-a',
          'group_id': 'group-a',
          'sender_peer_id': 'peer-self',
          'text': 'delete A',
          'timestamp': _t0,
          'created_at': _t0,
        },
        {
          'id': 'delete-target-b',
          'group_id': 'group-b',
          'sender_peer_id': 'peer-self',
          'text': 'delete B',
          'timestamp': _t0,
          'created_at': _t0,
        },
      ]) {
        await db.insert('group_messages', row);
      }
      for (final row in <Map<String, Object?>>[
        {
          'id': 'delete-reaction-a',
          'message_id': 'delete-target-a',
          'emoji': '\u{1F44D}',
          'sender_peer_id': 'peer-reactor-a',
          'timestamp': _t0,
          'created_at': _t0,
          'notification_display_terminal_event_id': 'terminal-a',
        },
        {
          'id': 'delete-reaction-b',
          'message_id': 'delete-target-b',
          'emoji': '\u{1F44D}',
          'sender_peer_id': 'peer-reactor-b',
          'timestamp': _t0,
          'created_at': _t0,
          'notification_display_terminal_event_id': 'terminal-b',
        },
      ]) {
        await db.insert('message_reactions', row);
      }

      expect(await dbDeleteGroupMessagesForGroup(db, 'group-a'), 1);
      expect(
        (await db.query(
          'message_reactions',
          where: 'id = ?',
          whereArgs: const <Object?>['delete-reaction-a'],
        )).single['notification_display_terminal_event_id'],
        'terminal-a',
      );
      expect(
        (await db.query(
          'message_reactions',
          where: 'id = ?',
          whereArgs: const <Object?>['delete-reaction-b'],
        )).single['notification_display_terminal_event_id'],
        'terminal-b',
      );

      await dbDeleteGroupMessage(db, 'delete-target-b');
      expect(
        (await db.query(
          'message_reactions',
          where: 'id = ?',
          whereArgs: const <Object?>['delete-reaction-b'],
        )).single['notification_display_terminal_event_id'],
        'terminal-b',
      );
    },
  );

  test(
    'message deletion rolls back its display cleanup when canonical delete fails',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      addTearDown(db.close);
      await db.insert('group_messages', <String, Object?>{
        'id': 'message-a',
        'group_id': 'group-a',
        'sender_peer_id': 'peer-self',
        'text': 'canonical target',
        'timestamp': _t0,
        'created_at': _t0,
      });
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        _message('message-delete-marker').toMap(),
      );
      await db.execute('''
        CREATE TRIGGER fail_group_message_delete
        BEFORE DELETE ON group_messages
        BEGIN
          SELECT RAISE(ABORT, 'injected delete failure');
        END
      ''');

      await expectLater(
        dbDeleteGroupMessage(db, 'message-a'),
        throwsA(anything),
      );

      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(
          db,
          'message-delete-marker',
        ),
        isNotNull,
      );
      expect(
        await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: const <Object?>['message-a'],
        ),
        hasLength(1),
      );
      expect(
        await db.query(
          'group_message_local_deletions',
          where: 'message_id = ?',
          whereArgs: const <Object?>['message-a'],
        ),
        isEmpty,
      );
    },
  );
}
