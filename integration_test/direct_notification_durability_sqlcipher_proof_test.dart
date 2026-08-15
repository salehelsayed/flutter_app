@Tags(['device'])
library;

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reaction_terminal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

const _t0 = '2026-08-03T10:00:00.000Z';
const _t1 = '2026-08-03T10:00:01.000Z';
const _ownerId = 'collision-owner';
const _messageId = 'collision-message';
const _actorId = 'collision-actor';
const _eventId = 'collision-event';
const _reactionRowId = 'collision-reaction-row';
const _generation = 'collision-generation';
const _groupTerminalEvent = 'group-terminal-event';

const _v107Indexes = <String>{
  'idx_direct_notification_read_acknowledgements_peer',
  'idx_direct_notification_read_acknowledgements_message',
  'idx_direct_notification_reaction_terminal_event',
  'idx_direct_notification_reaction_terminal_message',
  'idx_direct_notification_display_outbox_ready',
  'idx_direct_notification_display_outbox_peer_message',
  'idx_direct_notification_display_outbox_reaction',
  'idx_direct_notification_reconciliation_outbox_eligible',
};
const _currentDirectIndexes = <String>{
  ..._v107Indexes,
  'idx_direct_inbox_custody_outbox_fair_load',
  'idx_direct_reaction_inbox_custody_outbox_fair_load',
  'idx_direct_media_blob_custody_inbox_incarnation',
  'idx_direct_media_blob_custody_message',
  'idx_direct_media_blob_custody_state_retry',
};

const _v107Triggers = <String>{
  'trg_direct_notification_read_ack_message_insert',
  'trg_direct_notification_reconcile_contact_policy',
  'trg_direct_notification_reconcile_contact_insert',
  'trg_direct_notification_reconcile_contact_delete',
  'trg_direct_notification_reconcile_message_read',
  'trg_direct_notification_reconcile_message_delete',
  'trg_direct_notification_reconcile_message_eligibility',
};

Future<int> _userVersion(sqlcipher.Database db) async =>
    ((await db.rawQuery('PRAGMA user_version')).single.values.single as num)
        .toInt();

Future<String> _cipherVersion(sqlcipher.Database db) async =>
    (await db.rawQuery(
      'PRAGMA cipher_version',
    )).single.values.single.toString();

Future<bool> _tableExists(sqlcipher.Database db, String table) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      <Object?>[table],
    )).isNotEmpty;

Future<List<String>> _columns(sqlcipher.Database db, String table) async =>
    (await db.rawQuery(
      'PRAGMA table_info($table)',
    )).map((row) => row['name'] as String).toList(growable: false);

Future<Set<String>> _schemaObjectNames(
  sqlcipher.Database db,
  String type,
  String prefix,
) async => (await db.rawQuery(
  'SELECT name FROM sqlite_master WHERE type = ? AND name LIKE ? ORDER BY name',
  <Object?>[type, '$prefix%'],
)).map((row) => row['name'] as String).toSet();

Future<void> _expectV107Artifacts(sqlcipher.Database db) async {
  expect(await _userVersion(db), 116);
  expect(await _cipherVersion(db), isNotEmpty);
  expect(await _columns(db, 'direct_notification_display_outbox'), <String>[
    'event_id',
    'event_kind',
    'peer_id',
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
    await _columns(db, 'direct_notification_read_acknowledgements'),
    <String>[
      'peer_id',
      'content_kind',
      'event_identity',
      'message_id',
      'actor_peer_id',
      'generation',
      'acknowledged_at',
    ],
  );
  expect(
    await _columns(db, 'direct_notification_reaction_terminal_events'),
    <String>[
      'peer_id',
      'message_id',
      'actor_peer_id',
      'reaction_id',
      'terminal_event_id',
      'notification_acknowledged_at',
      'updated_at',
    ],
  );
  expect(
    await _columns(db, 'direct_notification_reconciliation_outbox'),
    <String>[
      'peer_id',
      'incarnation_id',
      'revision',
      'retry_count',
      'last_attempt_at',
      'next_attempt_at',
      'created_at',
      'updated_at',
    ],
  );
  expect(
    await _columns(db, 'messages'),
    contains('notification_display_terminal_event_id'),
  );
  expect(
    await _columns(db, 'message_reactions'),
    isNot(contains('direct_peer_id')),
  );
  expect(
    await _schemaObjectNames(db, 'index', 'idx_direct_'),
    _currentDirectIndexes,
  );
  expect(await _schemaObjectNames(db, 'trigger', 'trg_direct_'), _v107Triggers);
  for (final table in const <String>[
    'direct_notification_display_outbox',
    'direct_notification_read_acknowledgements',
    'direct_notification_reaction_terminal_events',
    'direct_notification_reconciliation_outbox',
  ]) {
    expect(await db.rawQuery('PRAGMA foreign_key_list($table)'), isEmpty);
    expect(
      await _columns(db, table),
      isNot(
        containsAll(<String>[
          'title',
          'body',
          'text',
          'emoji',
          'payload',
          'preview',
        ]),
      ),
    );
  }
}

Future<void> _seedV106(sqlcipher.Database db) async {
  await db.insert('contacts', <String, Object?>{
    'peer_id': _ownerId,
    'public_key': 'public-$_ownerId',
    'rendezvous': 'relay-$_ownerId',
    'username': _ownerId,
    'signature': 'signature-$_ownerId',
    'scanned_at': _t0,
  });
  await db.insert('messages', <String, Object?>{
    'id': _messageId,
    'contact_peer_id': _ownerId,
    'sender_peer_id': _actorId,
    'text': 'direct collision sentinel',
    'timestamp': _t0,
    'status': 'delivered',
    'is_incoming': 1,
    'created_at': _t0,
  });
  await db.insert('groups', <String, Object?>{
    'id': _ownerId,
    'name': 'Group collision sentinel',
    'type': 'chat',
    'topic_name': '/mknoon/groups/$_ownerId',
    'created_at': _t0,
    'created_by': _actorId,
    'my_role': 'admin',
  });
  await db.insert('group_messages', <String, Object?>{
    'id': _messageId,
    'group_id': _ownerId,
    'sender_peer_id': _actorId,
    'text': 'group collision sentinel',
    'timestamp': _t0,
    'created_at': _t0,
  });
  await db.insert('message_reactions', <String, Object?>{
    'id': _reactionRowId,
    'message_id': _messageId,
    'emoji': '\u{1f44d}',
    'sender_peer_id': _actorId,
    'timestamp': _t0,
    'created_at': _t0,
    'notification_display_terminal_event_id': _groupTerminalEvent,
  });
  await db.insert('group_notification_display_outbox', <String, Object?>{
    'event_id': _eventId,
    'event_kind': 'reaction',
    'group_id': _ownerId,
    'message_id': _messageId,
    'actor_peer_id': _actorId,
    'event_timestamp': _t0,
    'reaction_id': _reactionRowId,
    'reaction_action': 'add',
    'reaction_tombstone': 0,
    'readiness': 'ready',
    'revision': 2,
    'retry_count': 0,
    'last_error_code': null,
    'last_attempt_at': null,
    'next_attempt_at': null,
    'created_at': _t0,
    'updated_at': _t1,
  });
  await db.insert('group_notification_read_acknowledgements', <String, Object?>{
    'group_id': _ownerId,
    'content_kind': 'reaction',
    'event_identity': _eventId,
    'generation': _generation,
    'acknowledged_at': _t0,
  });
  await db.insert(
    'group_notification_reconciliation_outbox',
    <String, Object?>{
      'group_id': _ownerId,
      'incarnation_id': '11111111111111111111111111111111',
      'revision': 1,
      'retry_count': 0,
      'last_attempt_at': null,
      'next_attempt_at': null,
      'created_at': _t0,
      'updated_at': _t0,
    },
    conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
  );
}

Future<Map<String, List<Map<String, Object?>>>> _groupSentinels(
  sqlcipher.Database db,
) async => <String, List<Map<String, Object?>>>{
  'group': await db.query(
    'groups',
    where: 'id = ?',
    whereArgs: const <Object?>[_ownerId],
  ),
  'message': await db.query(
    'group_messages',
    where: 'id = ? AND group_id = ?',
    whereArgs: const <Object?>[_messageId, _ownerId],
  ),
  'reaction': await db.query(
    'message_reactions',
    where: 'id = ?',
    whereArgs: const <Object?>[_reactionRowId],
  ),
  'display': await db.query(
    'group_notification_display_outbox',
    where: 'event_id = ?',
    whereArgs: const <Object?>[_eventId],
  ),
  'read': await db.query(
    'group_notification_read_acknowledgements',
    where: 'group_id = ? AND event_identity = ?',
    whereArgs: const <Object?>[_ownerId, _eventId],
  ),
  'reconciliation': await db.query(
    'group_notification_reconciliation_outbox',
    where: 'group_id = ?',
    whereArgs: const <Object?>[_ownerId],
  ),
};

Future<void> _expectTypedIsolation(sqlcipher.Database db) async {
  expect(
    await dbLoadDirectNotificationReactionTerminalEvent(
      db,
      peerId: _ownerId,
      messageId: _messageId,
      actorPeerId: _actorId,
    ),
    allOf(
      containsPair('reaction_id', 'direct-reaction'),
      containsPair('terminal_event_id', _eventId),
    ),
  );
  expect(
    (await db.query(
      'message_reactions',
      where: 'id = ?',
      whereArgs: const <Object?>[_reactionRowId],
    )).single['notification_display_terminal_event_id'],
    _groupTerminalEvent,
  );
  expect(
    await dbLoadExactDirectNotificationReadAcknowledgement(
      db,
      peerId: _ownerId,
      contentKind: 'reaction',
      eventIdentity: _eventId,
      generation: _generation,
    ),
    allOf(
      containsPair('message_id', _messageId),
      containsPair('actor_peer_id', _actorId),
    ),
  );
  expect(
    await db.query(
      'group_notification_read_acknowledgements',
      where: 'group_id = ? AND content_kind = ? AND event_identity = ?',
      whereArgs: const <Object?>[_ownerId, 'reaction', _eventId],
    ),
    hasLength(1),
  );
  expect(
    await dbLoadDirectNotificationReconciliationOutboxEntry(db, _ownerId),
    isNotNull,
  );
  expect(
    await db.query(
      'group_notification_reconciliation_outbox',
      where: 'group_id = ?',
      whereArgs: const <Object?>[_ownerId],
    ),
    hasLength(1),
  );
  expect(
    await db.query(
      'group_notification_display_outbox',
      where: 'event_id = ?',
      whereArgs: const <Object?>[_eventId],
    ),
    hasLength(1),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TC-331-22 real SQLCipher v106 to current preserves typed direct and group authority across refusal and reopen',
    (_) async {
      expect(currentIdentityDatabaseVersion, 116);

      final temp = await Directory.systemTemp.createTemp(
        'direct_notification_durability_sqlcipher_',
      );
      final upgradePath = p.join(temp.path, 'upgrade.db');
      final freshPath = p.join(temp.path, 'fresh.db');
      const password = 'plan-331-direct-notification-sqlcipher-key';
      sqlcipher.Database? db;
      final previousFlowEventLogging = flowEventLoggingEnabled;
      flowEventLoggingEnabled = false;
      var proofStage = 'open-v106-database';
      try {
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 106,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 106);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(
          await _tableExists(db, 'direct_notification_display_outbox'),
          isFalse,
        );
        expect(
          await _columns(db, 'messages'),
          isNot(contains('notification_display_terminal_event_id')),
        );

        proofStage = 'seed-v106-collision-sentinels';
        await _seedV106(db);
        final groupBefore = await _groupSentinels(db);
        await db.close();
        db = null;

        proofStage = 'upgrade-v106-to-current-v116';
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        await _expectV107Artifacts(db);
        expect(await _groupSentinels(db), groupBefore);
        expect(
          (await db.query(
            'messages',
            where: 'id = ? AND contact_peer_id = ?',
            whereArgs: const <Object?>[_messageId, _ownerId],
          )).single,
          allOf(
            containsPair('text', 'direct collision sentinel'),
            containsPair('notification_display_terminal_event_id', null),
          ),
        );

        final registryEntries = productionUpgradeMigrations.where(
          (entry) => entry.version == 107,
        );
        expect(registryEntries, hasLength(1));
        final migration = registryEntries.single;
        expect(migration.name, '107_direct_notification_durability');
        expect(migration.run, same(runDirectNotificationDurabilityMigration));
        expect(
          productionCreateMigrations
              .where((entry) => entry.version == 107)
              .single
              .run,
          same(runDirectNotificationDurabilityMigration),
        );

        proofStage = 'prove-typed-direct-group-isolation';
        const directReaction = DirectNotificationDisplayOutboxEntry.reaction(
          eventId: _eventId,
          peerId: _ownerId,
          messageId: _messageId,
          actorPeerId: _actorId,
          eventTimestamp: _t0,
          reactionId: 'direct-reaction',
          reactionAction: 'add',
          reactionTombstone: false,
          createdAt: _t0,
          updatedAt: _t0,
        );
        await dbStageDirectNotificationDisplayOutboxEntry(
          db,
          directReaction.toMap(),
        );
        expect(
          await db.query(
            'direct_notification_display_outbox',
            where: 'event_id = ?',
            whereArgs: const <Object?>[_eventId],
          ),
          hasLength(1),
        );
        expect(
          await db.query(
            'group_notification_display_outbox',
            where: 'event_id = ?',
            whereArgs: const <Object?>[_eventId],
          ),
          hasLength(1),
        );
        expect(
          await dbPromoteDirectNotificationDisplayOutboxReadyIfExact(
            db,
            peerId: _ownerId,
            eventKind: 'reaction',
            eventId: _eventId,
            expectedRevision: 1,
            updatedAt: _t1,
          ),
          isTrue,
        );
        expect(
          await dbCompleteDirectNotificationDisplayOutboxEntryIfExact(
            db,
            eventId: _eventId,
            expectedRevision: 2,
            expectedEventKind: 'reaction',
            expectedPeerId: _ownerId,
            expectedMessageId: _messageId,
            expectedActorPeerId: _actorId,
            expectedEventTimestamp: _t0,
            expectedReactionId: 'direct-reaction',
            expectedReactionAction: 'add',
            expectedReactionTombstone: false,
            completedAt: _t1,
          ),
          isTrue,
        );
        expect(
          await dbRecordDirectNotificationReadAcknowledgement(
            db,
            peerId: _ownerId,
            contentKind: 'reaction',
            eventIdentity: _eventId,
            messageId: _messageId,
            actorPeerId: _actorId,
            generation: _generation,
            acknowledgedAt: _t1,
          ),
          isTrue,
        );
        await dbEnqueueDirectNotificationReconciliationOutbox(
          db,
          peerId: _ownerId,
        );
        await _expectTypedIsolation(db);
        expect(await _groupSentinels(db), groupBefore);

        proofStage = 'repair-and-rerun-actual-v107-registry-entry';
        for (final index in _v107Indexes) {
          await db.execute('DROP INDEX $index');
        }
        for (final trigger in _v107Triggers) {
          await db.execute('DROP TRIGGER $trigger');
        }
        await migration.run(db);
        await migration.run(db);
        await _expectV107Artifacts(db);
        await _expectTypedIsolation(db);
        expect(await _groupSentinels(db), groupBefore);
        await db.close();
        db = null;

        proofStage = 'wrong-key-refusal';
        await expectLater(() async {
          final wrong = await sqlcipher.openDatabase(
            upgradePath,
            password: 'wrong-plan-331-key',
            singleInstance: false,
          );
          try {
            await wrong.query('direct_notification_reaction_terminal_events');
          } finally {
            await wrong.close();
          }
        }(), throwsA(anything));

        proofStage = 'v111-to-v106-downgrade-refusal';
        await expectLater(
          sqlcipher.openDatabase(
            upgradePath,
            password: password,
            version: 106,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        proofStage = 'reopen-current-v116-after-refusals';
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        await _expectV107Artifacts(db);
        await _expectTypedIsolation(db);
        expect(await _groupSentinels(db), groupBefore);
        expect(
          (await db.query(
            'messages',
            where: 'id = ? AND contact_peer_id = ?',
            whereArgs: const <Object?>[_messageId, _ownerId],
          )).single['text'],
          'direct collision sentinel',
        );
        await db.close();
        db = null;

        proofStage = 'fresh-current-v116-database';
        db = await sqlcipher.openDatabase(
          freshPath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        await _expectV107Artifacts(db);
        expect(await db.query('direct_notification_display_outbox'), isEmpty);
        expect(
          await db.query('direct_notification_reaction_terminal_events'),
          isEmpty,
        );
      } catch (error, stackTrace) {
        stderr.writeln(
          'PLAN331_SQLCIPHER_PROOF_FAILURE stage=$proofStage error=$error',
        );
        stderr.writeln(stackTrace);
        rethrow;
      } finally {
        flowEventLoggingEnabled = previousFlowEventLogging;
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );
}
