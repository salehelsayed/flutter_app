@Tags(['device'])
library;

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/106_group_notification_display_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_active_importer.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

const _terminalColumn = 'notification_display_terminal_event_id';
const _legacyMessageDeleteTrigger =
    'trg_group_message_delete_clear_reaction_notification_terminal';
const _reconciliationTable = 'group_notification_reconciliation_outbox';
const _readAcknowledgementTable = 'group_notification_read_acknowledgements';
const _messageDeleteReconciliationTrigger =
    'trg_group_notification_reconcile_message_delete';
const _messageReadReconciliationTrigger =
    'trg_group_notification_reconcile_message_read';
const _t0 = '2026-08-02T20:00:00.000Z';
const _t1 = '2026-08-02T20:00:01.000Z';

Future<int> _userVersion(sqlcipher.Database db) async =>
    ((await db.rawQuery('PRAGMA user_version')).single.values.single as num)
        .toInt();

Future<void> _expectFinalV106Artifacts(sqlcipher.Database db) async {
  expect(
    (await db.rawQuery(
      'PRAGMA table_info(group_messages)',
    )).map((row) => row['name']),
    contains(_terminalColumn),
  );
  expect(
    (await db.rawQuery(
      'PRAGMA table_info(message_reactions)',
    )).map((row) => row['name']),
    containsAll(<String>[_terminalColumn, 'notification_acknowledged_at']),
  );
  expect(
    await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = ?",
      const <Object?>[_legacyMessageDeleteTrigger],
    ),
    isEmpty,
    reason:
        'target deletion must retain the exact identifier-only event binding '
        'until canonical reconciliation retires the OS card',
  );
  expect(
    await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      const <Object?>[_reconciliationTable],
    ),
    hasLength(1),
  );
  expect(
    await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      const <Object?>[_readAcknowledgementTable],
    ),
    hasLength(1),
  );
  expect(
    await db.rawQuery('PRAGMA foreign_key_list($_readAcknowledgementTable)'),
    isEmpty,
  );
  expect(
    await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = ?",
      const <Object?>[_messageDeleteReconciliationTrigger],
    ),
    hasLength(1),
  );
  expect(
    await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = ?",
      const <Object?>[_messageReadReconciliationTrigger],
    ),
    hasLength(1),
  );
}

Future<String?> _terminalEventId(
  sqlcipher.Database db, {
  required String table,
  required String id,
}) async {
  final rows = await db.query(
    table,
    columns: const <String>[_terminalColumn],
    where: 'id = ?',
    whereArgs: <Object?>[id],
  );
  expect(rows, hasLength(1));
  return rows.single[_terminalColumn] as String?;
}

Future<bool> _completeDisplayEntry(
  sqlcipher.Database db,
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
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real SQLCipher v105 to v106 preserves custody and terminal facts across reopen/export',
    (_) async {
      expect(currentIdentityDatabaseVersion, 112);

      final temp = await Directory.systemTemp.createTemp(
        'group_notification_display_outbox_sqlcipher_',
      );
      final upgradePath = p.join(temp.path, 'upgrade.db');
      final freshPath = p.join(temp.path, 'fresh.db');
      final transferPath = p.join(temp.path, 'transfer.db');
      final activeImportPath = p.join(temp.path, 'active-import.db');
      const password = 'plan-330-display-outbox-sqlcipher-key';
      const transferPassword = 'plan-330-display-outbox-transfer-key';
      sqlcipher.Database? db;
      final previousFlowEventLogging = flowEventLoggingEnabled;
      flowEventLoggingEnabled = false;
      var proofStage = 'open-v105-database';
      try {
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: 105,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 105);
        proofStage = 'seed-v105-database';
        expect(
          (await db.rawQuery('PRAGMA cipher_version')).single.values.single,
          isNotEmpty,
        );
        await db.insert('group_reaction_replay_outbox', <String, Object?>{
          'reaction_id': 'old-row',
          'group_id': 'old-group',
          'message_id': 'old-message',
          'sender_peer_id': 'old-peer',
          'emoji': '\u{1F44D}',
          'action': 'add',
          'inbox_retry_payload': '{"old":true}',
          'delivery_status': 'failed',
          'last_error': null,
          'created_at': '2026-08-02T20:00:00.000Z',
          'updated_at': '2026-08-02T20:00:00.000Z',
        });
        await db.close();
        db = null;

        proofStage = 'reopen-v106-database';
        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 112);
        expect(await db.query('group_reaction_replay_outbox'), hasLength(1));
        await _expectFinalV106Artifacts(db);
        for (final groupId in const <String>[
          'group-a',
          'terminal-group',
          'deleted-group',
        ]) {
          await db.insert('groups', <String, Object?>{
            'id': groupId,
            'name': 'Plan 330 $groupId',
            'type': 'chat',
            'topic_name': '/mknoon/groups/$groupId',
            'created_at': _t0,
            'created_by': 'terminal-message-peer',
            'my_role': 'admin',
          });
        }
        for (final row in <Map<String, Object?>>[
          const <String, Object?>{
            'id': 'terminal-message',
            'group_id': 'terminal-group',
            'sender_peer_id': 'terminal-message-peer',
            'text': 'terminal message fact',
            'timestamp': _t0,
            'created_at': _t0,
            'read_at': _t0,
          },
          const <String, Object?>{
            'id': 'terminal-reaction-target',
            'group_id': 'terminal-group',
            'sender_peer_id': 'terminal-target-peer',
            'text': 'terminal reaction target',
            'timestamp': _t0,
            'created_at': _t0,
            'is_incoming': 0,
          },
          const <String, Object?>{
            'id': 'deleted-message-target',
            'group_id': 'deleted-group',
            'sender_peer_id': 'deleted-message-peer',
            'text': 'deleted reaction target',
            'timestamp': _t0,
            'created_at': _t0,
          },
        ]) {
          await db.insert('group_messages', row);
        }
        await db.insert('message_reactions', const <String, Object?>{
          'id': 'terminal-reaction',
          'message_id': 'terminal-reaction-target',
          'emoji': '\u{1F44D}',
          'sender_peer_id': 'terminal-reaction-peer',
          'timestamp': _t0,
          'created_at': _t0,
        });
        await db.insert('message_reactions', const <String, Object?>{
          'id': 'deleted-message-reaction',
          'message_id': 'deleted-message-target',
          'emoji': '\u{1F389}',
          'sender_peer_id': 'deleted-reaction-peer',
          'timestamp': _t0,
          'created_at': _t0,
          _terminalColumn: 'deleted-reaction-terminal-event',
        });
        await dbStageGroupNotificationDisplayOutboxEntry(
          db,
          const GroupNotificationDisplayOutboxEntry.message(
            eventId: 'display-event',
            groupId: 'group-a',
            messageId: 'message-a',
            actorPeerId: 'peer-a',
            eventTimestamp: _t0,
            createdAt: _t0,
            updatedAt: _t0,
          ).toMap(),
        );
        const terminalMessageCustody =
            GroupNotificationDisplayOutboxEntry.message(
              eventId: 'terminal-message-event',
              groupId: 'terminal-group',
              messageId: 'terminal-message',
              actorPeerId: 'terminal-message-peer',
              eventTimestamp: _t0,
              createdAt: _t0,
              updatedAt: _t0,
            );
        await dbStageGroupNotificationDisplayOutboxEntry(
          db,
          terminalMessageCustody.toMap(),
        );
        proofStage = 'verify-v106-custody-and-artifacts';
        expect(
          await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
            db,
            eventId: terminalMessageCustody.eventId,
            expectedRevision: 1,
            updatedAt: _t1,
          ),
          isTrue,
        );
        expect(
          await _completeDisplayEntry(
            db,
            terminalMessageCustody.copyWith(
              readiness: GroupNotificationDisplayOutboxReadiness.ready,
              revision: 2,
              updatedAt: _t1,
            ),
          ),
          isTrue,
        );
        const terminalReactionCustody =
            GroupNotificationDisplayOutboxEntry.reaction(
              eventId: 'terminal-reaction-event',
              groupId: 'terminal-group',
              messageId: 'terminal-reaction-target',
              actorPeerId: 'terminal-reaction-peer',
              eventTimestamp: _t0,
              reactionId: 'terminal-reaction',
              reactionAction: 'add',
              reactionTombstone: false,
              createdAt: _t0,
              updatedAt: _t0,
            );
        await dbStageGroupNotificationDisplayOutboxEntry(
          db,
          terminalReactionCustody.toMap(),
        );
        expect(
          await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
            db,
            eventId: terminalReactionCustody.eventId,
            expectedRevision: 1,
            updatedAt: _t1,
          ),
          isTrue,
        );
        expect(
          await _completeDisplayEntry(
            db,
            terminalReactionCustody.copyWith(
              readiness: GroupNotificationDisplayOutboxReadiness.ready,
              revision: 2,
              updatedAt: _t1,
            ),
          ),
          isTrue,
        );
        proofStage = 'persist-reaction-only-read-acknowledgement';
        expect(await dbMarkGroupMessagesAsRead(db, 'terminal-group'), 0);
        expect(
          (await db.query(
            'message_reactions',
            where: 'id = ?',
            whereArgs: const <Object?>['terminal-reaction'],
          )).single['notification_acknowledged_at'],
          isNotNull,
        );
        expect(
          await db.query(
            _reconciliationTable,
            where: 'group_id = ?',
            whereArgs: const <Object?>['terminal-group'],
          ),
          hasLength(1),
        );
        proofStage = 'transfer-push-before-inbox-acknowledgements';
        expect(
          await dbMarkGroupMessagesAsRead(
            db,
            'group-a',
            acknowledgedContentKind: 'message',
            acknowledgedEventIdentity: 'late-sqlcipher-message',
            acknowledgedGeneration: 'late-sqlcipher-message-generation',
          ),
          0,
        );
        expect(
          await dbLoadExactGroupNotificationReadAcknowledgement(
            db,
            groupId: 'group-a',
            contentKind: 'message',
            eventIdentity: 'late-sqlcipher-message',
          ),
          isNotNull,
        );
        expect(
          await dbInsertGroupMessage(db, const <String, Object?>{
            'id': 'late-sqlcipher-message',
            'group_id': 'group-a',
            'sender_peer_id': 'late-message-peer',
            'text': 'materialized after read',
            'timestamp': _t1,
            'created_at': _t1,
            'is_incoming': 1,
          }),
          isTrue,
        );
        expect(
          (await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: const <Object?>['late-sqlcipher-message'],
          )).single['read_at'],
          isNotNull,
        );
        expect(
          await dbLoadExactGroupNotificationReadAcknowledgement(
            db,
            groupId: 'group-a',
            contentKind: 'message',
            eventIdentity: 'late-sqlcipher-message',
          ),
          isNull,
        );

        const lateReactionEvent = 'late-sqlcipher-reaction-event';
        final lateReactionIdentity = boundedReactionEventIdentity(
          lateReactionEvent,
        );
        expect(
          await dbMarkGroupMessagesAsRead(
            db,
            'terminal-group',
            acknowledgedContentKind: 'reaction',
            acknowledgedEventIdentity: lateReactionIdentity,
            acknowledgedGeneration: 'late-sqlcipher-reaction-generation',
          ),
          0,
        );
        expect(
          await dbApplyIncomingReactionMutation(
            db,
            const <String, Object?>{
              'id': 'late-sqlcipher-reaction',
              'message_id': 'terminal-reaction-target',
              'emoji': '\u{1F44D}',
              'sender_peer_id': 'late-reaction-peer',
              'timestamp': _t1,
              'created_at': _t1,
            },
            mutation: DbIncomingReactionMutation.add,
            groupIdForNotificationCleanup: 'terminal-group',
            notificationEventIdForStaleAddCleanup: lateReactionEvent,
          ),
          DbIncomingReactionApplyResult.inserted,
        );
        final lateReaction = (await db.query(
          'message_reactions',
          where: 'id = ?',
          whereArgs: const <Object?>['late-sqlcipher-reaction'],
        )).single;
        expect(lateReaction['notification_acknowledged_at'], isNotNull);
        expect(lateReaction[_terminalColumn], lateReactionIdentity);
        expect(
          await dbLoadExactGroupNotificationReadAcknowledgement(
            db,
            groupId: 'terminal-group',
            contentKind: 'reaction',
            eventIdentity: lateReactionIdentity,
          ),
          isNull,
        );

        const retainedPendingIdentity = 'pending-sqlcipher-reaction-event';
        expect(
          await dbMarkGroupMessagesAsRead(
            db,
            'group-a',
            acknowledgedContentKind: 'reaction',
            acknowledgedEventIdentity: retainedPendingIdentity,
            acknowledgedGeneration: 'pending-sqlcipher-generation',
          ),
          0,
        );
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(
          await dbLoadGroupNotificationDisplayOutboxEntry(db, 'display-event'),
          allOf(
            containsPair('event_kind', 'message'),
            containsPair('group_id', 'group-a'),
            containsPair('message_id', 'message-a'),
            containsPair('readiness', 'not_ready'),
            containsPair('revision', 1),
          ),
        );
        await _expectFinalV106Artifacts(db);
        expect(
          await _terminalEventId(
            db,
            table: 'group_messages',
            id: 'terminal-message',
          ),
          terminalMessageCustody.eventId,
        );
        expect(
          await _terminalEventId(
            db,
            table: 'message_reactions',
            id: 'terminal-reaction',
          ),
          boundedReactionEventIdentity(terminalReactionCustody.eventId),
        );
        expect(
          await dbLoadExactGroupNotificationReadAcknowledgement(
            db,
            groupId: 'group-a',
            contentKind: 'reaction',
            eventIdentity: retainedPendingIdentity,
          ),
          containsPair('generation', 'pending-sqlcipher-generation'),
        );
        expect(
          await _terminalEventId(
            db,
            table: 'message_reactions',
            id: 'deleted-message-reaction',
          ),
          'deleted-reaction-terminal-event',
        );
        proofStage = 'repair-partial-v106-migration';
        final migration = productionUpgradeMigrations.singleWhere(
          (entry) => entry.version == 106,
        );
        expect(migration.run, same(runGroupNotificationDisplayOutboxMigration));
        // Model interruption after the table and some draft artifacts
        // committed. The idempotent migration must repair the index and remove
        // the legacy marker-clearing trigger without disturbing custody or
        // canonical terminal facts.
        await db.execute(
          'DROP INDEX idx_group_notification_display_outbox_ready',
        );
        await db.execute('DROP TRIGGER $_messageDeleteReconciliationTrigger');
        await db.execute('DROP TRIGGER $_messageReadReconciliationTrigger');
        await db.execute('''
          CREATE TRIGGER $_legacyMessageDeleteTrigger
          AFTER DELETE ON group_messages
          BEGIN
            UPDATE message_reactions
            SET $_terminalColumn = NULL
            WHERE message_id = OLD.id;
          END
        ''');
        await migration.run(db);
        expect(
          (await db.rawQuery(
            "PRAGMA index_list('group_notification_display_outbox')",
          )).map((row) => row['name']),
          contains('idx_group_notification_display_outbox_ready'),
        );
        await _expectFinalV106Artifacts(db);
        await migration.run(db);
        expect(
          await db.query('group_notification_display_outbox'),
          hasLength(1),
        );
        expect(
          await db.delete(
            'group_messages',
            where: 'id = ?',
            whereArgs: const <Object?>['deleted-message-target'],
          ),
          1,
        );
        expect(
          await _terminalEventId(
            db,
            table: 'message_reactions',
            id: 'deleted-message-reaction',
          ),
          'deleted-reaction-terminal-event',
        );
        expect(
          await db.query(
            _reconciliationTable,
            where: 'group_id = ?',
            whereArgs: const <Object?>['deleted-group'],
          ),
          hasLength(1),
        );
        expect(
          await _terminalEventId(
            db,
            table: 'message_reactions',
            id: 'terminal-reaction',
          ),
          boundedReactionEventIdentity(terminalReactionCustody.eventId),
        );
        proofStage = 'close-repaired-v106-database';
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          upgradePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        await _expectFinalV106Artifacts(db);
        expect(await db.query('group_reaction_replay_outbox'), hasLength(1));
        expect(
          await dbLoadGroupNotificationDisplayOutboxEntry(db, 'display-event'),
          isNotNull,
        );
        expect(
          await _terminalEventId(
            db,
            table: 'group_messages',
            id: 'terminal-message',
          ),
          terminalMessageCustody.eventId,
        );
        expect(
          await _terminalEventId(
            db,
            table: 'message_reactions',
            id: 'terminal-reaction',
          ),
          boundedReactionEventIdentity(terminalReactionCustody.eventId),
        );
        expect(
          await _terminalEventId(
            db,
            table: 'message_reactions',
            id: 'deleted-message-reaction',
          ),
          'deleted-reaction-terminal-event',
        );

        final transfer = await const MigrationDatabaseSnapshotExporter()
            .exportSnapshot(
              sourceDb: db,
              destinationPath: transferPath,
              destinationKey: transferPassword,
              sourceAppVersion: 'plan-330-device-proof',
              sourceBuildNumber: '1',
            );
        expect(transfer.manifest.databaseVersion, 112);
        expect(transfer.manifest.compatibility().isAccepted, isTrue);
        expect(
          transfer.manifest.schemaInventory.hasColumn(
            'group_messages',
            _terminalColumn,
          ),
          isTrue,
        );
        expect(
          transfer.manifest.schemaInventory.hasColumn(
            'message_reactions',
            _terminalColumn,
          ),
          isTrue,
        );
        expect(
          transfer.manifest.schemaInventory.tableNames,
          containsAll(<String>[
            'group_notification_display_outbox',
            _readAcknowledgementTable,
          ]),
        );
        expect(
          transfer.manifest.databaseChecksumSha256,
          await MigrationDatabaseSnapshotExporter.computeFileChecksum(
            transfer.destinationPath,
          ),
        );
        final transferred = await sqlcipher.openDatabase(
          transfer.destinationPath,
          password: transferPassword,
          singleInstance: false,
        );
        try {
          await _expectFinalV106Artifacts(transferred);
          expect(
            await dbLoadGroupNotificationDisplayOutboxEntry(
              transferred,
              'display-event',
            ),
            allOf(
              containsPair('event_kind', 'message'),
              containsPair('group_id', 'group-a'),
              containsPair('message_id', 'message-a'),
              containsPair('readiness', 'not_ready'),
              containsPair('revision', 1),
            ),
          );
          expect(
            await transferred.query('group_reaction_replay_outbox'),
            hasLength(1),
          );
          expect(
            await dbLoadExactGroupNotificationReadAcknowledgement(
              transferred,
              groupId: 'group-a',
              contentKind: 'reaction',
              eventIdentity: retainedPendingIdentity,
            ),
            isNotNull,
          );
          expect(
            await _terminalEventId(
              transferred,
              table: 'group_messages',
              id: 'terminal-message',
            ),
            terminalMessageCustody.eventId,
          );
          expect(
            await _terminalEventId(
              transferred,
              table: 'message_reactions',
              id: 'terminal-reaction',
            ),
            boundedReactionEventIdentity(terminalReactionCustody.eventId),
          );
          expect(
            await _terminalEventId(
              transferred,
              table: 'message_reactions',
              id: 'deleted-message-reaction',
            ),
            'deleted-reaction-terminal-event',
          );
          expect(
            await transferred.query(
              'group_messages',
              where: 'id = ?',
              whereArgs: const <Object?>['deleted-message-target'],
            ),
            isEmpty,
          );

          proofStage = 'trigger-safe-active-import';
          final activeImport = await sqlcipher.openDatabase(
            activeImportPath,
            password: password,
            version: currentIdentityDatabaseVersion,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          );
          try {
            final stagedLogicalChecksum =
                await MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting(
                  transferred,
                );
            final imported =
                await MigrationDatabaseActiveImporter(
                  activeDatabase: activeImport,
                ).importVerifiedStagedDatabase(
                  MigrationDatabaseImportStagingResult(
                    database: transferred,
                    manifest: transfer.manifest,
                    stagedDatabasePath: transfer.destinationPath,
                  ),
                );
            expect(imported.importedTables, contains('groups'));
            expect(imported.importedTables, contains(_reconciliationTable));
            expect(
              await MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting(
                activeImport,
              ),
              stagedLogicalChecksum,
            );
            await _expectFinalV106Artifacts(activeImport);
            expect(
              (await activeImport.query(
                'message_reactions',
                where: 'id = ?',
                whereArgs: const <Object?>['terminal-reaction'],
              )).single['notification_acknowledged_at'],
              isNotNull,
            );
            expect(
              await dbLoadExactGroupNotificationReadAcknowledgement(
                activeImport,
                groupId: 'group-a',
                contentKind: 'reaction',
                eventIdentity: retainedPendingIdentity,
              ),
              isNotNull,
            );
          } finally {
            await activeImport.close();
          }
        } finally {
          await transferred.close();
        }
        await db.close();
        db = null;

        await expectLater(() async {
          final wrong = await sqlcipher.openDatabase(
            upgradePath,
            password: 'wrong-plan-330-key',
            singleInstance: false,
          );
          try {
            await wrong.query('group_notification_display_outbox');
          } finally {
            await wrong.close();
          }
        }(), throwsA(anything));

        await expectLater(
          sqlcipher.openDatabase(
            upgradePath,
            password: password,
            version: 105,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        final fresh = await sqlcipher.openDatabase(
          freshPath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        try {
          expect(await _userVersion(fresh), 112);
          await _expectFinalV106Artifacts(fresh);
          expect(
            await fresh.query('group_notification_display_outbox'),
            isEmpty,
          );
          expect(await fresh.query(_readAcknowledgementTable), isEmpty);
        } finally {
          await fresh.close();
        }
      } catch (error, stackTrace) {
        // Keep failures actionable on physical Android, where verbose migration
        // flow events can otherwise hide the integration-test matcher output.
        stderr.writeln(
          'PLAN330_SQLCIPHER_PROOF_FAILURE stage=$proofStage error=$error',
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
