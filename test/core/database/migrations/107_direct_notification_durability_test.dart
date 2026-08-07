// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reaction_terminal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_display_outbox_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_reaction_terminal_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_read_acknowledgement_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/direct_notification_reconciliation_outbox_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_read_acknowledgement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _t0 = '2026-08-03T10:00:00.000Z';
const _t1 = '2026-08-03T10:00:01.000Z';
const _t2 = '2026-08-03T10:00:02.000Z';
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

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String path;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'direct_notification_durability_v107_',
    );
    path = '${tempDir.path}/identity.db';
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'TC-331-07 v106 to current installs v107 typed direct authority and repairs partial migration',
    () async {
      var db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 106,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      await _insertContact(db, 'peer-a');
      await _insertMessage(db, peerId: 'peer-a', messageId: 'same-id');
      await db.insert('message_reactions', <String, Object?>{
        'id': 'shared-reaction',
        'message_id': 'same-id',
        'emoji': '\u{1f44d}',
        'sender_peer_id': 'same-actor',
        'timestamp': _t0,
        'created_at': _t0,
        'notification_display_terminal_event_id': 'group-terminal',
      });
      await db.close();

      db = await databaseFactoryFfi.openDatabase(
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

      expect(currentIdentityDatabaseVersion, 109);
      expect(await _userVersion(db), 109);
      for (final registry in <List<ProductionMigrationEntry>>[
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        final entries = registry.where((entry) => entry.version == 107);
        expect(entries, hasLength(1));
        expect(entries.single.name, '107_direct_notification_durability');
        expect(
          entries.single.run,
          same(runDirectNotificationDurabilityMigration),
        );
        expect(registry.last.version, 109);
      }

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
        (await db.query(
          'message_reactions',
          where: 'id = ?',
          whereArgs: const <Object?>['shared-reaction'],
        )).single['notification_display_terminal_event_id'],
        'group-terminal',
      );
      expect(
        await _schemaObjectNames(db, 'index', 'idx_direct_'),
        _currentDirectIndexes,
      );
      expect(
        await _schemaObjectNames(db, 'trigger', 'trg_direct_'),
        _v107Triggers,
      );

      for (final table in const <String>[
        'direct_notification_display_outbox',
        'direct_notification_read_acknowledgements',
        'direct_notification_reaction_terminal_events',
        'direct_notification_reconciliation_outbox',
      ]) {
        expect(await db.rawQuery('PRAGMA foreign_key_list($table)'), isEmpty);
        final columns = await _columns(db, table);
        expect(
          columns,
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

      for (final index in _v107Indexes) {
        await db.execute('DROP INDEX $index');
      }
      for (final trigger in _v107Triggers) {
        await db.execute('DROP TRIGGER $trigger');
      }
      await runDirectNotificationDurabilityMigration(db);
      await runDirectNotificationDurabilityMigration(db);
      expect(
        await _schemaObjectNames(db, 'index', 'idx_direct_'),
        _currentDirectIndexes,
      );
      expect(
        await _schemaObjectNames(db, 'trigger', 'trg_direct_'),
        _v107Triggers,
      );
      expect(await db.query('messages'), hasLength(1));
    },
  );

  test(
    'TC-331-07 direct repositories keep colliding reaction terminal facts typed and use exact CAS',
    () async {
      final db = await _openCurrent(path);
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });
      await _insertContact(db, 'peer-a');
      await _insertMessage(db, peerId: 'peer-a', messageId: 'same-id');
      await db.insert('message_reactions', <String, Object?>{
        'id': 'shared-group-reaction',
        'message_id': 'same-id',
        'emoji': '\u{1f44d}',
        'sender_peer_id': 'same-actor',
        'timestamp': _t0,
        'created_at': _t0,
        'notification_display_terminal_event_id': 'group-event',
      });

      var now = DateTime.parse(_t0).toUtc();
      final display = _displayRepository(db, now: () => now);
      const reaction = DirectNotificationDisplayOutboxEntry.reaction(
        eventId: 'direct-event',
        peerId: 'peer-a',
        messageId: 'same-id',
        actorPeerId: 'same-actor',
        eventTimestamp: _t0,
        reactionId: 'direct-reaction',
        reactionAction: 'add',
        reactionTombstone: false,
        createdAt: _t0,
        updatedAt: _t0,
      );
      await display.stage(reaction);
      await display.stage(reaction.copyWith(peerId: 'peer-b'));
      expect(
        await db.query(
          'direct_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const ['direct-event'],
        ),
        hasLength(2),
      );
      expect(
        await display.promoteReadyIfExact(
          peerId: reaction.peerId,
          eventKind: reaction.eventKind,
          eventId: reaction.eventId,
          expectedRevision: 1,
        ),
        isTrue,
      );
      final ready = (await display.loadReady()).single;
      expect(ready.revision, 2);
      expect(
        await display.completeIfExact(ready.copyWith(revision: 1)),
        isFalse,
      );
      expect(await display.completeIfExact(ready), isTrue);

      expect(
        await dbLoadDirectNotificationReactionTerminalEvent(
          db,
          peerId: 'peer-a',
          messageId: 'same-id',
          actorPeerId: 'same-actor',
        ),
        containsPair('terminal_event_id', 'direct-event'),
      );
      expect(
        (await db.query(
          'message_reactions',
          where: 'id = ?',
          whereArgs: const <Object?>['shared-group-reaction'],
        )).single['notification_display_terminal_event_id'],
        'group-event',
      );

      const staleRemove = DirectNotificationDisplayOutboxEntry.reaction(
        eventId: 'stale-remove-event',
        peerId: 'peer-a',
        messageId: 'same-id',
        actorPeerId: 'same-actor',
        eventTimestamp: _t1,
        reactionId: 'direct-reaction',
        reactionAction: 'remove',
        reactionTombstone: true,
        createdAt: _t1,
        updatedAt: _t1,
      );
      await display.stage(staleRemove);
      expect(
        await display.promoteReadyIfExact(
          peerId: staleRemove.peerId,
          eventKind: staleRemove.eventKind,
          eventId: staleRemove.eventId,
          expectedRevision: 1,
        ),
        isTrue,
      );
      await dbUpsertDirectNotificationReactionTerminalEvent(
        db,
        peerId: 'peer-a',
        messageId: 'same-id',
        actorPeerId: 'same-actor',
        reactionId: 'newer-reaction',
        terminalEventId: 'newer-direct-event',
        updatedAt: _t2,
      );
      expect(
        await display.completeIfExact(
          (await display.loadExact(
            peerId: staleRemove.peerId,
            eventKind: staleRemove.eventKind,
            eventId: staleRemove.eventId,
          ))!,
        ),
        isTrue,
      );
      expect(
        await dbLoadDirectNotificationReactionTerminalEvent(
          db,
          peerId: 'peer-a',
          messageId: 'same-id',
          actorPeerId: 'same-actor',
        ),
        containsPair('terminal_event_id', 'newer-direct-event'),
      );

      await dbRecordDirectNotificationReadAcknowledgement(
        db,
        peerId: 'peer-a',
        contentKind: 'message',
        eventIdentity: 'late-message',
        messageId: 'late-message',
        actorPeerId: null,
        generation: 'card-generation-4',
        acknowledgedAt: _t1,
      );
      await _insertMessage(db, peerId: 'peer-a', messageId: 'late-message');
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>['late-message'],
        )).single['read_at'],
        _t1,
      );
      expect(
        await dbLoadExactDirectNotificationReadAcknowledgement(
          db,
          peerId: 'peer-a',
          contentKind: 'message',
          eventIdentity: 'late-message',
          generation: 'card-generation-4',
        ),
        isNull,
      );

      final reconciliation = _reconciliationRepository(db, now: () => now);
      final queued = (await reconciliation.loadEligible()).singleWhere(
        (entry) => entry.peerId == 'peer-a',
      );
      now = DateTime.parse(_t2).toUtc();
      expect(
        await reconciliation.recordFailureIfExact(
          expected: queued,
          nextAttemptAt: now.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
      expect(await reconciliation.completeIfExact(queued), isFalse);
      await dbEnqueueDirectNotificationReconciliationOutbox(
        db,
        peerId: 'peer-a',
      );
      final current = (await reconciliation.loadEligible()).single;
      expect(current.revision, greaterThan(queued.revision));
      expect(await reconciliation.completeIfExact(current), isTrue);
    },
  );

  test(
    'TC-331-07 current version is a one-way floor and refused downgrade preserves v107 data',
    () async {
      var db = await _openCurrent(path);
      await dbUpsertDirectNotificationReactionTerminalEvent(
        db,
        peerId: 'peer-floor',
        messageId: 'message-floor',
        actorPeerId: 'actor-floor',
        reactionId: 'reaction-floor',
        terminalEventId: 'event-floor',
        updatedAt: _t0,
      );
      await db.close();

      await expectLater(
        databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 106,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: onDatabaseVersionChangeError,
          ),
        ),
        throwsA(anything),
      );

      db = await _openCurrent(path);
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });
      expect(await _userVersion(db), 109);
      expect(
        await dbLoadDirectNotificationReactionTerminalEvent(
          db,
          peerId: 'peer-floor',
          messageId: 'message-floor',
          actorPeerId: 'actor-floor',
        ),
        containsPair('terminal_event_id', 'event-floor'),
      );
    },
  );

  test(
    'TC-331-07 contact and message lifecycle coalesce cleanup without touching group authority',
    () async {
      final db = await _openCurrent(path);
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });
      await _insertContact(db, 'peer-a');
      await _insertMessage(db, peerId: 'peer-a', messageId: 'message-a');
      await dbUpsertDirectNotificationReactionTerminalEvent(
        db,
        peerId: 'peer-a',
        messageId: 'message-a',
        actorPeerId: 'actor-a',
        reactionId: 'reaction-a',
        terminalEventId: 'event-a',
        updatedAt: _t0,
      );
      await dbRecordDirectNotificationReadAcknowledgement(
        db,
        peerId: 'peer-a',
        contentKind: 'reaction',
        eventIdentity: 'event-a',
        messageId: 'message-a',
        actorPeerId: 'actor-a',
        generation: 'generation-a',
        acknowledgedAt: _t0,
      );

      await db.update(
        'messages',
        <String, Object?>{'hidden_at': _t1},
        where: 'id = ?',
        whereArgs: const <Object?>['message-a'],
      );
      final afterLogicalHide =
          await dbLoadDirectNotificationReconciliationOutboxEntry(db, 'peer-a');
      expect(afterLogicalHide, isNotNull);

      await db.update(
        'messages',
        <String, Object?>{'read_at': _t1},
        where: 'id = ?',
        whereArgs: const <Object?>['message-a'],
      );
      final afterRead = await dbLoadDirectNotificationReconciliationOutboxEntry(
        db,
        'peer-a',
      );
      expect(afterRead, isNotNull);
      expect(
        afterRead!['revision'],
        greaterThan(afterLogicalHide!['revision'] as int),
      );

      await db.update(
        'contacts',
        <String, Object?>{'is_archived': 1, 'archived_at': _t1},
        where: 'peer_id = ?',
        whereArgs: const <Object?>['peer-a'],
      );
      final afterArchive =
          await dbLoadDirectNotificationReconciliationOutboxEntry(db, 'peer-a');
      expect(
        afterArchive!['revision'],
        greaterThan(afterRead['revision'] as int),
      );

      await db.delete(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: const <Object?>['peer-a'],
      );
      expect(
        await db.query(
          'direct_notification_read_acknowledgements',
          where: 'peer_id = ?',
          whereArgs: const <Object?>['peer-a'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'direct_notification_reaction_terminal_events',
          where: 'peer_id = ?',
          whereArgs: const <Object?>['peer-a'],
        ),
        isEmpty,
      );
      expect(
        await dbLoadDirectNotificationReconciliationOutboxEntry(db, 'peer-a'),
        isNotNull,
      );
    },
  );

  test(
    'TC-331-07 typed repositories keep peer kind and generation authority exact',
    () async {
      final db = await _openCurrent(path);
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });
      final acknowledgements = _readAcknowledgementRepository(db);
      final terminals = _reactionTerminalRepository(db);

      const messageAcknowledgement =
          DirectNotificationReadAcknowledgement.message(
            peerId: 'peer-a',
            messageId: 'same-event',
            generation: 'generation-a',
            acknowledgedAt: _t0,
          );
      const reactionAcknowledgement =
          DirectNotificationReadAcknowledgement.reaction(
            peerId: 'peer-a',
            eventIdentity: 'same-event',
            messageId: 'message-b',
            actorPeerId: 'actor-b',
            generation: 'generation-a',
            acknowledgedAt: _t1,
          );
      expect(await acknowledgements.record(messageAcknowledgement), isTrue);
      expect(await acknowledgements.record(reactionAcknowledgement), isTrue);

      expect(
        await acknowledgements.loadExact(
          peerId: 'peer-a',
          contentKind: DirectNotificationReadAcknowledgementKind.message,
          eventIdentity: 'same-event',
          generation: 'generation-a',
        ),
        messageAcknowledgement,
      );
      expect(
        await acknowledgements.loadExact(
          peerId: 'peer-a',
          contentKind: DirectNotificationReadAcknowledgementKind.reaction,
          eventIdentity: 'same-event',
          generation: 'generation-a',
        ),
        reactionAcknowledgement,
      );

      expect(
        await terminals.upsert(
          peerId: 'peer-a',
          messageId: 'message-b',
          actorPeerId: 'actor-b',
          reactionId: 'reaction-b',
          terminalEventId: 'same-event',
        ),
        isTrue,
      );
      expect(
        await terminals.consumeAcknowledgementIfExact(
          peerId: 'peer-a',
          messageId: 'message-b',
          actorPeerId: 'actor-b',
          terminalEventId: 'same-event',
          generation: 'generation-a',
        ),
        isTrue,
      );
      final terminal = await terminals.loadExact(
        peerId: 'peer-a',
        messageId: 'message-b',
        actorPeerId: 'actor-b',
      );
      expect(terminal!.notificationAcknowledgedAt, _t1);
      expect(
        await acknowledgements.loadExact(
          peerId: 'peer-a',
          contentKind: DirectNotificationReadAcknowledgementKind.message,
          eventIdentity: 'same-event',
          generation: 'generation-a',
        ),
        messageAcknowledgement,
      );
    },
  );
}

Future<Database> _openCurrent(String path) => databaseFactoryFfi.openDatabase(
  path,
  options: OpenDatabaseOptions(
    version: currentIdentityDatabaseVersion,
    singleInstance: false,
    onCreate: runProductionOnCreate,
    onUpgrade: runProductionOnUpgrade,
    onDowngrade: onDatabaseVersionChangeError,
  ),
);

Future<void> _insertContact(Database db, String peerId) =>
    db.insert('contacts', <String, Object?>{
      'peer_id': peerId,
      'public_key': 'public-$peerId',
      'rendezvous': 'relay-$peerId',
      'username': peerId,
      'signature': 'signature-$peerId',
      'scanned_at': _t0,
    });

Future<void> _insertMessage(
  Database db, {
  required String peerId,
  required String messageId,
}) => db.insert('messages', <String, Object?>{
  'id': messageId,
  'contact_peer_id': peerId,
  'sender_peer_id': peerId,
  'text': 'canonical content',
  'timestamp': _t0,
  'status': 'delivered',
  'is_incoming': 1,
  'created_at': _t0,
});

DirectNotificationDisplayOutboxRepositoryImpl _displayRepository(
  Database db, {
  required DateTime Function() now,
}) => DirectNotificationDisplayOutboxRepositoryImpl(
  dbStage: (row) => dbStageDirectNotificationDisplayOutboxEntry(db, row),
  dbLoadExact: ({required peerId, required eventKind, required eventId}) =>
      dbLoadDirectNotificationDisplayOutboxEntry(
        db,
        peerId: peerId,
        eventKind: eventKind,
        eventId: eventId,
      ),
  dbPromoteReadyIfExact:
      ({
        required peerId,
        required eventKind,
        required eventId,
        required expectedRevision,
        required updatedAt,
      }) => dbPromoteDirectNotificationDisplayOutboxReadyIfExact(
        db,
        peerId: peerId,
        eventKind: eventKind,
        eventId: eventId,
        expectedRevision: expectedRevision,
        updatedAt: updatedAt,
      ),
  dbLoadReady: ({limit = 20, required eligibleAt}) =>
      dbLoadReadyDirectNotificationDisplayOutboxEntries(
        db,
        limit: limit,
        eligibleAt: eligibleAt,
      ),
  dbLoadEarliestNextAttemptAt: () =>
      dbLoadEarliestDirectNotificationDisplayOutboxNextAttemptAt(db),
  dbRecordRetryIfExact:
      ({
        required peerId,
        required eventKind,
        required eventId,
        required expectedRevision,
        required lastErrorCode,
        required lastAttemptAt,
        required nextAttemptAt,
        required updatedAt,
      }) => dbRecordDirectNotificationDisplayOutboxRetryIfExact(
        db,
        peerId: peerId,
        eventKind: eventKind,
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
        required expectedPeerId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
        required completedAt,
      }) => dbCompleteDirectNotificationDisplayOutboxEntryIfExact(
        db,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedPeerId: expectedPeerId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
        completedAt: completedAt,
      ),
  dbRetireIfExact:
      ({
        required eventId,
        required expectedRevision,
        required expectedEventKind,
        required expectedPeerId,
        required expectedMessageId,
        required expectedActorPeerId,
        required expectedEventTimestamp,
        required expectedReactionId,
        required expectedReactionAction,
        required expectedReactionTombstone,
      }) => dbRetireDirectNotificationDisplayOutboxEntryIfExact(
        db,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: expectedEventKind,
        expectedPeerId: expectedPeerId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
      ),
  dbDeleteForPeer: (peerId) =>
      dbDeleteDirectNotificationDisplayOutboxForPeer(db, peerId),
  dbDeleteForMessage: ({required peerId, required messageId}) =>
      dbDeleteDirectNotificationDisplayOutboxForMessage(
        db,
        peerId: peerId,
        messageId: messageId,
      ),
  dbDeleteForReactionActor:
      ({required peerId, required messageId, required actorPeerId}) =>
          dbDeleteDirectNotificationDisplayOutboxForReactionActor(
            db,
            peerId: peerId,
            messageId: messageId,
            actorPeerId: actorPeerId,
          ),
  now: now,
);

DirectNotificationReconciliationOutboxRepositoryImpl _reconciliationRepository(
  Database db, {
  required DateTime Function() now,
}) => DirectNotificationReconciliationOutboxRepositoryImpl(
  dbLoadEligible: ({limit = 20, required eligibleAt}) =>
      dbLoadEligibleDirectNotificationReconciliationOutboxEntries(
        db,
        limit: limit,
        eligibleAt: eligibleAt,
      ),
  dbLoadEarliestNextAttemptAt: () =>
      dbLoadEarliestDirectNotificationReconciliationOutboxNextAttemptAt(db),
  dbRecordFailureIfExact:
      ({
        required peerId,
        required expectedIncarnationId,
        required expectedRevision,
        required lastAttemptAt,
        required nextAttemptAt,
        required updatedAt,
      }) => dbRecordDirectNotificationReconciliationOutboxFailureIfExact(
        db,
        peerId: peerId,
        expectedIncarnationId: expectedIncarnationId,
        expectedRevision: expectedRevision,
        lastAttemptAt: lastAttemptAt,
        nextAttemptAt: nextAttemptAt,
        updatedAt: updatedAt,
      ),
  dbCompleteIfExact:
      ({
        required peerId,
        required expectedIncarnationId,
        required expectedRevision,
      }) => dbCompleteDirectNotificationReconciliationOutboxIfExact(
        db,
        peerId: peerId,
        expectedIncarnationId: expectedIncarnationId,
        expectedRevision: expectedRevision,
      ),
  now: now,
);

DirectNotificationReadAcknowledgementRepositoryImpl
_readAcknowledgementRepository(Database db) =>
    DirectNotificationReadAcknowledgementRepositoryImpl(
      dbRecord:
          ({
            required peerId,
            required contentKind,
            required eventIdentity,
            required messageId,
            required actorPeerId,
            required generation,
            required acknowledgedAt,
          }) => dbRecordDirectNotificationReadAcknowledgement(
            db,
            peerId: peerId,
            contentKind: contentKind,
            eventIdentity: eventIdentity,
            messageId: messageId,
            actorPeerId: actorPeerId,
            generation: generation,
            acknowledgedAt: acknowledgedAt,
          ),
      dbLoadExact:
          ({
            required peerId,
            required contentKind,
            required eventIdentity,
            generation,
          }) => dbLoadExactDirectNotificationReadAcknowledgement(
            db,
            peerId: peerId,
            contentKind: contentKind,
            eventIdentity: eventIdentity,
            generation: generation,
          ),
      dbConsumeExact:
          ({required peerId, required contentKind, required eventIdentity}) =>
              dbConsumeExactDirectNotificationReadAcknowledgement(
                db,
                peerId: peerId,
                contentKind: contentKind,
                eventIdentity: eventIdentity,
              ),
      dbDeleteForPeer: (peerId) =>
          dbDeleteDirectNotificationReadAcknowledgementsForPeer(db, peerId),
    );

DirectNotificationReactionTerminalRepositoryImpl _reactionTerminalRepository(
  Database db,
) => DirectNotificationReactionTerminalRepositoryImpl(
  dbUpsert:
      ({
        required peerId,
        required messageId,
        required actorPeerId,
        required reactionId,
        required terminalEventId,
        required updatedAt,
      }) => dbUpsertDirectNotificationReactionTerminalEvent(
        db,
        peerId: peerId,
        messageId: messageId,
        actorPeerId: actorPeerId,
        reactionId: reactionId,
        terminalEventId: terminalEventId,
        updatedAt: updatedAt,
      ),
  dbLoadExact: ({required peerId, required messageId, required actorPeerId}) =>
      dbLoadDirectNotificationReactionTerminalEvent(
        db,
        peerId: peerId,
        messageId: messageId,
        actorPeerId: actorPeerId,
      ),
  dbLoadByTerminalEvent: ({required peerId, required terminalEventId}) =>
      dbLoadDirectNotificationReactionTerminalEventByIdentity(
        db,
        peerId: peerId,
        terminalEventId: terminalEventId,
      ),
  dbMarkAcknowledgedIfExact:
      ({
        required peerId,
        required messageId,
        required actorPeerId,
        required terminalEventId,
        required acknowledgedAt,
      }) => dbMarkDirectNotificationReactionTerminalAcknowledgedIfExact(
        db,
        peerId: peerId,
        messageId: messageId,
        actorPeerId: actorPeerId,
        terminalEventId: terminalEventId,
        acknowledgedAt: acknowledgedAt,
      ),
  dbConsumeAcknowledgementIfExact:
      ({
        required peerId,
        required messageId,
        required actorPeerId,
        required terminalEventId,
        required generation,
      }) =>
          dbConsumeDirectNotificationReactionAcknowledgementIntoTerminalIfExact(
            db,
            peerId: peerId,
            messageId: messageId,
            actorPeerId: actorPeerId,
            terminalEventId: terminalEventId,
            generation: generation,
          ),
  dbDeleteForActor:
      ({required peerId, required messageId, required actorPeerId}) =>
          dbDeleteDirectNotificationReactionTerminalForActor(
            db,
            peerId: peerId,
            messageId: messageId,
            actorPeerId: actorPeerId,
          ),
  dbDeleteForMessage: ({required peerId, required messageId}) =>
      dbDeleteDirectNotificationReactionTerminalsForMessage(
        db,
        peerId: peerId,
        messageId: messageId,
      ),
  dbDeleteForPeer: (peerId) =>
      dbDeleteDirectNotificationReactionTerminalsForPeer(db, peerId),
  now: () => DateTime.parse(_t0).toUtc(),
);

Future<int> _userVersion(Database db) async =>
    (await db.rawQuery('PRAGMA user_version')).single.values.single as int;

Future<List<String>> _columns(Database db, String table) async =>
    (await db.rawQuery(
      'PRAGMA table_info($table)',
    )).map((row) => row['name'] as String).toList(growable: false);

Future<Set<String>> _schemaObjectNames(
  Database db,
  String type,
  String prefix,
) async => (await db.rawQuery(
  'SELECT name FROM sqlite_master WHERE type = ? AND name LIKE ? ORDER BY name',
  <Object?>[type, '$prefix%'],
)).map((row) => row['name'] as String).toSet();
