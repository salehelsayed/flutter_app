import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/109_direct_reaction_inbox_custody_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

const _recipient = 'tc343-recipient-peer';
const _sender = 'tc343-self-peer';
const _target = 'tc343-target-message';
const _addEvent = 'tc343-reaction-add-event';
const _removeEvent = 'tc343-reaction-remove-event';
const _t0 = '2026-08-07T07:00:00.000Z';
const _t1 = '2026-08-07T07:00:01.000Z';
const _t2 = '2026-08-07T07:00:02.000Z';

Future<int> _userVersion(sqlcipher.Database db) async =>
    (await db.rawQuery('PRAGMA user_version')).single.values.single! as int;

Future<String> _cipherVersion(sqlcipher.Database db) async =>
    (await db.rawQuery(
      'PRAGMA cipher_version',
    )).single.values.single.toString();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TC-343-10 Android SQLCipher v108-to-v109 direct-reaction custody survives reopen and completion rollback',
    (_) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'TC-343-10 is an Android SQLCipher plugin boundary proof',
      );
      expect(currentIdentityDatabaseVersion, 116);

      final previousFlowEventLoggingEnabled = flowEventLoggingEnabled;
      flowEventLoggingEnabled = false;
      final temp = await Directory.systemTemp.createTemp(
        'direct_reaction_custody_sqlcipher_',
      );
      final path = '${temp.path}/identity.db';
      const password = 'tc343-sqlcipher-correct-password';
      sqlcipher.Database? db;
      var proofStage = 'create-production-v108';

      try {
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 108,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 108);
        expect(await _cipherVersion(db), isNotEmpty);
        await db.insert('messages', _targetMessageRow());
        final textCustody = _v108TextCustodyRow();
        await db.insert('direct_inbox_custody_outbox', textCustody);
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'direct_reaction_inbox_custody_outbox'",
          ),
          isEmpty,
        );
        await db.close();
        db = null;

        proofStage = 'upgrade-v108-through-v109-to-current-v116';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 116);
        expect(await _cipherVersion(db), isNotEmpty);
        final currentTextCustody = <String, Object?>{
          ...textCustody,
          'media_blob_expires_at_ms': null,
          'media_blob_manifest_hash': null,
        };
        expect(
          await db.query('direct_inbox_custody_outbox'),
          <Map<String, Object?>>[currentTextCustody],
        );
        expect(
          await db.query('direct_reaction_inbox_custody_outbox'),
          isEmpty,
          reason: 'historical reactions receive no ciphertext backfill',
        );

        proofStage = 'idempotent-production-v109-migration';
        await runDirectReactionInboxCustodyOutboxMigration(db);
        await runDirectReactionInboxCustodyOutboxMigration(db);

        proofStage = 'atomic-add-and-remove-stage';
        final addRow = _reactionRow(eventId: _addEvent, timestamp: _t1);
        final addEnvelope = _reactionEnvelope(
          eventId: _addEvent,
          action: 'add',
          cipher: 'tc343-add-ciphertext',
        );
        final addStage = await dbStageOutgoingDirectReactionInboxCustody(
          db,
          reactionRow: addRow,
          recipientPeerId: _recipient,
          action: 'add',
          wireEnvelope: addEnvelope,
        );
        expect(addStage.outcome, DirectReactionCustodyStageOutcome.applied);

        final removeRow = _reactionRow(eventId: _removeEvent, timestamp: _t2);
        final removeEnvelope = _reactionEnvelope(
          eventId: _removeEvent,
          action: 'remove',
          cipher: 'tc343-remove-ciphertext',
        );
        final removeStage = await dbStageOutgoingDirectReactionInboxCustody(
          db,
          reactionRow: removeRow,
          recipientPeerId: _recipient,
          action: 'remove',
          wireEnvelope: removeEnvelope,
        );
        expect(removeStage.outcome, DirectReactionCustodyStageOutcome.applied);
        expect(
          await db.query(
            'direct_reaction_inbox_custody_outbox',
            orderBy: 'created_at ASC',
          ),
          <Map<String, Object?>>[addStage.custodyRow!, removeStage.custodyRow!],
        );
        final canonical = (await db.query(
          'message_reactions',
          where: 'message_id = ? AND sender_peer_id = ?',
          whereArgs: const <Object?>[_target, _sender],
        )).single;
        expect(canonical['id'], _removeEvent);
        expect(canonical['removed_at'], _t2);
        final stagedSnapshot = await _authoritySnapshot(db);
        await db.close();
        db = null;

        proofStage = 'close-reopen-retains-exact-sibling-events';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _authoritySnapshot(db), stagedSnapshot);
        await db.close();
        db = null;

        proofStage = 'read-only-wrong-key-refusal';
        await expectLater(() async {
          sqlcipher.Database? wrong;
          try {
            wrong = await sqlcipher.openDatabase(
              path,
              password: 'tc343-deliberately-wrong-password',
              readOnly: true,
              singleInstance: false,
            );
            await wrong.query('direct_reaction_inbox_custody_outbox');
          } finally {
            if (wrong != null && wrong.isOpen) await wrong.close();
          }
        }(), throwsA(anything));

        proofStage = 'correct-key-reopen-after-wrong-key';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _authoritySnapshot(db), stagedSnapshot);

        proofStage = 'accepted-then-local-completion-delete-rollback';
        await db.execute('''
CREATE TRIGGER tc343_abort_reaction_custody_completion
BEFORE DELETE ON direct_reaction_inbox_custody_outbox
WHEN OLD.event_id = '$_addEvent'
BEGIN
  SELECT RAISE(ABORT, 'simulated local completion failure');
END
''');
        final addEntry = DirectReactionInboxCustodyOutboxEntry.fromMap(
          addStage.custodyRow!,
        );
        await expectLater(
          dbCompleteAcceptedDirectReactionInboxCustodyIfExact(
            db,
            recipientPeerId: addEntry.recipientPeerId,
            eventId: addEntry.eventId,
            expectedWireEnvelope: addEntry.wireEnvelope,
          ),
          throwsA(anything),
        );
        expect(
          await dbRecordDirectReactionInboxCustodyFailureIfExact(
            db,
            recipientPeerId: addEntry.recipientPeerId,
            eventId: addEntry.eventId,
            expectedWireEnvelope: addEntry.wireEnvelope,
            errorCode:
                DirectReactionInboxCustodyErrorCode.localCompletionFailed,
            attemptedAt: '2026-08-07T07:01:00.000Z',
          ),
          isTrue,
        );
        expect(
          await dbLoadDirectReactionInboxCustodyOutboxForEvent(
            db,
            recipientPeerId: addEntry.recipientPeerId,
            eventId: addEntry.eventId,
          ),
          isNotNull,
        );
        await db.close();
        db = null;

        proofStage = 'duplicate-reopen-convergence';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        final retainedAdd = DirectReactionInboxCustodyOutboxEntry.fromMap(
          (await dbLoadDirectReactionInboxCustodyOutboxForEvent(
            db,
            recipientPeerId: _recipient,
            eventId: _addEvent,
          ))!,
        );
        expect(retainedAdd.retryCount, 1);
        expect(
          retainedAdd.lastErrorCode,
          DirectReactionInboxCustodyErrorCode.localCompletionFailed,
        );
        await db.execute(
          'DROP TRIGGER tc343_abort_reaction_custody_completion',
        );
        final duplicate =
            InboxStoreOutcome.fromBridgeResponse(<String, dynamic>{
              'ok': true,
              'storeStatus': 'duplicate',
              'expiresAtMs': 0,
              'occupancy': 2,
              'capacity': 100,
            });
        expect(duplicate.status, InboxStoreStatus.duplicate);
        expect(duplicate.accepted, isTrue);
        expect(
          await dbCompleteAcceptedDirectReactionInboxCustodyIfExact(
            db,
            recipientPeerId: retainedAdd.recipientPeerId,
            eventId: retainedAdd.eventId,
            expectedWireEnvelope: retainedAdd.wireEnvelope,
          ),
          DirectReactionInboxCustodyCompletionOutcome.completed,
        );
        expect(
          await dbCompleteAcceptedDirectReactionInboxCustodyIfExact(
            db,
            recipientPeerId: retainedAdd.recipientPeerId,
            eventId: retainedAdd.eventId,
            expectedWireEnvelope: retainedAdd.wireEnvelope,
          ),
          DirectReactionInboxCustodyCompletionOutcome.absent,
        );
        final retainedRemove = DirectReactionInboxCustodyOutboxEntry.fromMap(
          (await dbLoadDirectReactionInboxCustodyOutboxForEvent(
            db,
            recipientPeerId: _recipient,
            eventId: _removeEvent,
          ))!,
        );
        expect(
          await dbCompleteAcceptedDirectReactionInboxCustodyIfExact(
            db,
            recipientPeerId: retainedRemove.recipientPeerId,
            eventId: retainedRemove.eventId,
            expectedWireEnvelope: retainedRemove.wireEnvelope,
          ),
          DirectReactionInboxCustodyCompletionOutcome.completed,
        );
        expect(await db.query('direct_reaction_inbox_custody_outbox'), isEmpty);
        expect(
          await db.query('direct_inbox_custody_outbox'),
          <Map<String, Object?>>[currentTextCustody],
        );
        final convergedSnapshot = await _authoritySnapshot(db);

        proofStage = 'second-production-migration-pass-is-stable';
        await runProductionOnUpgrade(db, 108, 109);
        await runDirectReactionInboxCustodyOutboxMigration(db);
        expect(await _userVersion(db), 116);
        expect(await _authoritySnapshot(db), convergedSnapshot);
        await db.close();
        db = null;

        proofStage = 'v111-to-v108-downgrade-refusal';
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 108,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        proofStage = 'correct-current-v116-reopen-unchanged-after-refusal';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 116);
        expect(await _authoritySnapshot(db), convergedSnapshot);
      } catch (error, stackTrace) {
        fail('TC-343-10 failed at $proofStage: $error\n$stackTrace');
      } finally {
        flowEventLoggingEnabled = previousFlowEventLoggingEnabled;
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );
}

Map<String, Object?> _targetMessageRow() => const <String, Object?>{
  'id': _target,
  'contact_peer_id': _recipient,
  'sender_peer_id': 'peer-contact',
  'text': 'reaction target',
  'timestamp': _t0,
  'status': 'delivered',
  'is_incoming': 1,
  'created_at': _t0,
};

Map<String, Object?> _v108TextCustodyRow() => const <String, Object?>{
  'recipient_peer_id': _recipient,
  'message_id': 'tc343-prior-v108-text-event',
  'incarnation_id': '1234567890abcdef1234567890abcdef',
  'wire_envelope': '{"type":"chat_message","cipher":"prior-v108"}',
  'retry_count': 1,
  'last_attempt_at': _t0,
  'last_error_code': 'store_failed',
  'created_at': _t0,
  'updated_at': _t0,
};

Map<String, Object?> _reactionRow({
  required String eventId,
  required String timestamp,
}) => <String, Object?>{
  'id': eventId,
  'message_id': _target,
  'emoji': '👍',
  'sender_peer_id': _sender,
  'timestamp': timestamp,
  'created_at': timestamp,
  'removed_at': null,
};

String _reactionEnvelope({
  required String eventId,
  required String action,
  required String cipher,
}) => jsonEncode(<String, Object?>{
  'type': 'message_reaction',
  'version': '2',
  'senderPeerId': _sender,
  'eventId': eventId,
  'action': action,
  'targetMessageId': _target,
  'encrypted': <String, Object?>{
    'kem': 'tc343-kem-$eventId',
    'ciphertext': cipher,
    'nonce': 'tc343-nonce-$eventId',
  },
});

Future<Map<String, Object?>> _authoritySnapshot(sqlcipher.Database db) async =>
    <String, Object?>{
      'user_version': await _userVersion(db),
      'text_custody': await db.query(
        'direct_inbox_custody_outbox',
        orderBy: 'recipient_peer_id, message_id',
      ),
      'reaction_custody': await db.query(
        'direct_reaction_inbox_custody_outbox',
        orderBy: 'recipient_peer_id, event_id',
      ),
      'canonical_reaction': await db.query(
        'message_reactions',
        where: 'message_id = ? AND sender_peer_id = ?',
        whereArgs: const <Object?>[_target, _sender],
      ),
      'target': await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>[_target],
      ),
    };
