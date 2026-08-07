import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/108_direct_inbox_custody_outbox.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

const _at = '2026-08-06T10:00:00.000Z';
const _attemptedAt = '2026-08-06T10:01:00.000Z';
const _recipientPeerId = 'peer-recipient';
const _messageId = 'tc342-message';
const _incarnationId = '1234567890abcdef1234567890abcdef';
const _wireEnvelope =
    '{"type":"chat_message","version":"2","id":"tc342-message",'
    '"senderPeerId":"self-peer",'
    '"encrypted":{"kem":"test-kem","ciphertext":"test-ciphertext",'
    '"nonce":"test-nonce"}}';

Future<int> _userVersion(sqlcipher.Database db) async =>
    (await db.rawQuery('PRAGMA user_version')).single.values.single! as int;

Future<String> _cipherVersion(sqlcipher.Database db) async =>
    (await db.rawQuery(
      'PRAGMA cipher_version',
    )).single.values.single.toString();

Map<String, Object?> _stagedMessage() => <String, Object?>{
  'id': _messageId,
  'contact_peer_id': _recipientPeerId,
  'sender_peer_id': 'self-peer',
  'text': 'opaque payload owner',
  'timestamp': _at,
  'status': 'sending',
  'is_incoming': 0,
  'created_at': _at,
  'edited_at': null,
  'read_at': null,
  'quoted_message_id': null,
  'deleted_at': null,
  'deleted_by_peer_id': null,
  'hidden_at': null,
  'transport': null,
  'wire_envelope': _wireEnvelope,
  'relay_expires_at': null,
  'custody_checked_at': null,
  'dedup_key': _messageId,
  'is_forwarded': 0,
  'private_media_policy_version': 0,
  'private_media_mode': 'ordinary',
  'private_media_duration_seconds': null,
  'private_media_state': 'none',
  'private_media_received_at_ms': null,
  'private_media_expires_at_ms': null,
  'private_media_revealed_at_ms': null,
  'private_media_terminal_at_ms': null,
  'private_media_clock_high_water_ms': null,
};

Map<String, Object?> _v107TerminalRow() => const <String, Object?>{
  'peer_id': 'peer-v107',
  'message_id': 'message-v107',
  'actor_peer_id': 'actor-v107',
  'reaction_id': 'reaction-v107',
  'terminal_event_id': 'terminal-v107',
  'notification_acknowledged_at': null,
  'updated_at': _at,
};

Future<Map<String, List<Map<String, Object?>>>> _authoritySnapshot(
  sqlcipher.Database db,
) async => <String, List<Map<String, Object?>>>{
  'terminal': await db.query('direct_notification_reaction_terminal_events'),
  'messages': await db.query(
    'messages',
    where: 'id = ?',
    whereArgs: const <Object?>[_messageId],
  ),
  'custody': await db.query('direct_inbox_custody_outbox'),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TC-342-11 Android SQLCipher v107-to-v108 direct-text custody survives delivery and crash replay',
    (_) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'TC-342-11 is an Android SQLCipher plugin boundary proof',
      );
      expect(currentIdentityDatabaseVersion, 109);

      final temp = await Directory.systemTemp.createTemp(
        'direct_inbox_custody_sqlcipher_',
      );
      final path = '${temp.path}/identity.db';
      const password = 'tc342-sqlcipher-password';
      sqlcipher.Database? db;
      var proofStage = 'create-v107';

      try {
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 107,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 107);
        expect(await _cipherVersion(db), isNotEmpty);
        await db.insert(
          'direct_notification_reaction_terminal_events',
          _v107TerminalRow(),
        );
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'direct_inbox_custody_outbox'",
          ),
          isEmpty,
        );
        await db.close();
        db = null;

        proofStage = 'upgrade-v107-to-v109';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 109);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(await db.query('direct_inbox_custody_outbox'), isEmpty);
        expect(
          await db.query('direct_notification_reaction_terminal_events'),
          <Map<String, Object?>>[_v107TerminalRow()],
        );

        proofStage = 'idempotent-v108-migration';
        await runDirectInboxCustodyOutboxMigration(db);
        await runDirectInboxCustodyOutboxMigration(db);
        expect(await db.query('direct_inbox_custody_outbox'), isEmpty);

        proofStage = 'atomic-stage';
        expect(
          await dbStageOutgoingDirectTextInboxCustody(
            db,
            expectedRow: null,
            stagedRow: _stagedMessage(),
            kind: OutgoingOrdinaryAttemptKind.fresh,
            recipientPeerId: _recipientPeerId,
            messageId: _messageId,
            incarnationId: _incarnationId,
            wireEnvelope: _wireEnvelope,
          ),
          OutgoingOrdinaryMutationOutcome.applied,
        );
        var custody = DirectInboxCustodyOutboxEntry.fromMap(
          (await dbLoadDirectInboxCustodyOutbox(db)).single,
        );
        expect(custody.recipientPeerId, _recipientPeerId);
        expect(custody.messageId, _messageId);
        expect(custody.incarnationId, _incarnationId);
        expect(custody.wireEnvelope, _wireEnvelope);
        expect(custody.retryCount, 0);

        proofStage = 'delivery-does-not-retire-custody';
        expect(
          await db.update(
            'messages',
            const <String, Object?>{
              'status': 'delivered',
              'transport': 'wifi',
              'wire_envelope': null,
            },
            where: 'id = ?',
            whereArgs: const <Object?>[_messageId],
          ),
          1,
        );
        expect(
          await dbLoadDirectInboxCustodyOutboxForMessage(
            db,
            recipientPeerId: _recipientPeerId,
            messageId: _messageId,
          ),
          isNotNull,
        );
        await db.close();
        db = null;

        proofStage = 'wrong-key-refusal';
        sqlcipher.Database? wrong;
        await expectLater(() async {
          wrong = await sqlcipher.openDatabase(
            path,
            password: 'wrong-tc342-password',
            singleInstance: false,
          );
          await wrong!.rawQuery('SELECT COUNT(*) FROM messages');
        }(), throwsA(anything));
        if (wrong != null && wrong!.isOpen) await wrong!.close();

        proofStage = 'restart-retains-delivered-custody';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        custody = DirectInboxCustodyOutboxEntry.fromMap(
          (await dbLoadDirectInboxCustodyOutbox(db)).single,
        );
        expect(custody.wireEnvelope, _wireEnvelope);
        expect(
          (await db.query(
            'messages',
            columns: const <String>['status', 'wire_envelope'],
            where: 'id = ?',
            whereArgs: const <Object?>[_messageId],
          )).single,
          const <String, Object?>{'status': 'delivered', 'wire_envelope': null},
        );

        proofStage = 'accepted-then-local-completion-failure';
        await db.execute('''
CREATE TRIGGER tc342_abort_custody_completion
BEFORE DELETE ON direct_inbox_custody_outbox
BEGIN
  SELECT RAISE(ABORT, 'simulated local completion failure');
END
''');
        await expectLater(
          dbCompleteAcceptedDirectInboxCustodyIfExact(
            db,
            recipientPeerId: _recipientPeerId,
            messageId: _messageId,
            expectedIncarnationId: _incarnationId,
            expectedWireEnvelope: _wireEnvelope,
            relayExpiresAt: 1999999999000,
          ),
          throwsA(anything),
        );
        expect(
          await dbRecordDirectInboxCustodyFailureIfExact(
            db,
            recipientPeerId: _recipientPeerId,
            messageId: _messageId,
            expectedIncarnationId: _incarnationId,
            expectedWireEnvelope: _wireEnvelope,
            errorCode: DirectInboxCustodyErrorCode.localCompletionFailed,
            attemptedAt: _attemptedAt,
          ),
          isTrue,
        );
        await db.close();
        db = null;

        proofStage = 'duplicate-replay-completes-after-reopen';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        custody = DirectInboxCustodyOutboxEntry.fromMap(
          (await dbLoadDirectInboxCustodyOutbox(db)).single,
        );
        expect(custody.retryCount, 1);
        expect(
          custody.lastErrorCode,
          DirectInboxCustodyErrorCode.localCompletionFailed,
        );
        await db.execute('DROP TRIGGER tc342_abort_custody_completion');
        final duplicateOutcome =
            InboxStoreOutcome.fromBridgeResponse(<String, dynamic>{
              'ok': true,
              'storeStatus': 'duplicate',
              'expiresAtMs': 0,
              'occupancy': 1,
              'capacity': 100,
            });
        expect(duplicateOutcome.status, InboxStoreStatus.duplicate);
        expect(duplicateOutcome.accepted, isTrue);
        expect(duplicateOutcome.expiresAtMs, isNull);
        expect(
          await dbCompleteAcceptedDirectInboxCustodyIfExact(
            db,
            recipientPeerId: _recipientPeerId,
            messageId: _messageId,
            expectedIncarnationId: _incarnationId,
            expectedWireEnvelope: _wireEnvelope,
            relayExpiresAt: duplicateOutcome.expiresAtMs,
          ),
          DirectInboxCustodyCompletionOutcome.messagePreserved,
        );
        expect(await db.query('direct_inbox_custody_outbox'), isEmpty);
        expect(
          (await db.query(
            'messages',
            columns: const <String>['status', 'wire_envelope'],
            where: 'id = ?',
            whereArgs: const <Object?>[_messageId],
          )).single,
          const <String, Object?>{'status': 'delivered', 'wire_envelope': null},
        );
        expect(
          await db.query('direct_notification_reaction_terminal_events'),
          <Map<String, Object?>>[_v107TerminalRow()],
        );
        final beforeDowngradeRefusal = await _authoritySnapshot(db);
        await db.close();
        db = null;

        proofStage = 'v108-to-v107-downgrade-refusal';
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 107,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        proofStage = 'reopen-v109-unchanged-after-refusal';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 109);
        expect(await _authoritySnapshot(db), beforeDowngradeRefusal);
      } catch (error, stackTrace) {
        fail('TC-342-11 failed at $proofStage: $error\n$stackTrace');
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );
}
