import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/108_direct_inbox_custody_outbox.dart';
import 'package:flutter_app/core/database/migrations/110_direct_media_custody_intent.dart';
import 'package:flutter_app/core/database/migrations/111_direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/migrations/113_direct_linked_device_event_fanout.dart';
import 'package:flutter_app/core/database/migrations/114_direct_linked_device_media_blob_fanout.dart';
import 'package:flutter_app/core/database/migrations/115_group_media_blob_custody.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/group_media_blob_custody.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
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
const _mediaMessageId = 'tc345-media-message';
const _mediaAttachmentId = 'tc345-media-attachment';
const _rollbackMessageId = 'tc345-rollback-message';
const _rollbackAttachmentId = 'tc345-rollback-attachment';
const _v111MessageId = 'tc347-historical-message';
const _v111AttachmentId = 'tc347-durable-attachment';
const _v111IncarnationId = 'abcdef0123456789abcdef0123456789';
const _v111ContentHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _v115GroupContentHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _v115GroupId = 'tc365-group';
const _v115GroupMessageId = 'tc365-group-message';
const _v115GroupAttachmentId = 'tc365-group-attachment';
const _v115GroupCustodyBlobId = 'gmb1-tc365-group-custody-blob';
const _v115GroupCiphertextPath =
    'group_media_blob_custody_v1/identity-scope/group-scope/'
    'tc365-group.blob';
const _v114MediaBlobCustodyColumns = <String>[
  'attachment_id',
  'message_id',
  'direction',
  'state',
  'inbox_custody_incarnation_id',
  'recipient_peer_id',
  'contact_account_peer_id',
  'recipient_ml_kem_public_key',
  'ciphertext_relative_path',
  'custody_kind',
  'custody_contract',
  'content_hash',
  'ciphertext_size',
  'transport_mime',
  'expires_at_ms',
  'custody_relay_peer_id',
  'retry_count',
  'last_attempt_at',
  'next_attempt_at',
  'created_at',
  'updated_at',
];
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

Map<String, Object?> _v109ReactionCustodyRow() => const <String, Object?>{
  'recipient_peer_id': 'peer-v109-reaction',
  'event_id': 'event-v109-reaction',
  'wire_envelope': '{"type":"reaction","version":"1"}',
  'retry_count': 0,
  'last_attempt_at': null,
  'last_error_code': null,
  'created_at': _at,
  'updated_at': _at,
};

String _mediaWireEnvelope(String messageId) =>
    '{"type":"chat_message","version":"2","id":"$messageId",'
    '"senderPeerId":"self-peer",'
    '"encrypted":{"kem":"test-kem","ciphertext":"test-ciphertext",'
    '"nonce":"test-nonce"}}';

Map<String, Object?> _preparedMediaMessageRow({
  required String messageId,
  required String attachmentId,
}) => Map<String, Object?>.from(_stagedMessage())
  ..['id'] = messageId
  ..['text'] = 'opaque media payload owner'
  ..['wire_envelope'] = null
  ..['dedup_key'] = messageId
  ..['direct_media_custody_intent_id'] = computeDirectMediaCustodyIntentId(
    messageId: messageId,
    attachmentIds: <String>[attachmentId],
  );

Map<String, Object?> _pendingMediaAttachmentRow({
  required String messageId,
  required String attachmentId,
}) => <String, Object?>{
  'id': attachmentId,
  'message_id': messageId,
  'mime': 'audio/ogg',
  'size': 345,
  'media_type': 'audio',
  'width': null,
  'height': null,
  'duration_ms': 1200,
  'local_path': 'pending_uploads/$messageId/$attachmentId.ogg',
  'download_status': 'upload_pending',
  'created_at': _at,
  'waveform': null,
  'upload_retry_count': 0,
  'download_retry_count': 0,
  'content_hash': null,
  'thumbnail_hash': null,
  'encryption_key_base64': null,
  'encryption_nonce': null,
  'encryption_scheme': null,
  'owner_lane': 'direct',
  'is_bookmarked': 0,
  'last_playback_position_ms': 0,
};

Map<String, Object?> _completedMediaAttachmentRow(
  Map<String, Object?> pending,
) => Map<String, Object?>.from(pending)
  ..['download_status'] = 'done'
  ..['local_path'] = 'media/${pending['message_id']}/${pending['id']}.ogg'
  ..['content_hash'] =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  ..['encryption_key_base64'] = secureStoreReferenceForKey(
    mediaAttachmentEncryptionKeyStoreName(pending['id']! as String),
  )
  ..['encryption_nonce'] = 'tc345-media-nonce'
  ..['encryption_scheme'] = 'blob_aes_256_gcm_v1';

Map<String, Object?> _stagedMediaMessageRow(
  Map<String, Object?> prepared,
  String wireEnvelope,
) => Map<String, Object?>.from(prepared)
  ..['status'] = 'sending'
  ..['wire_envelope'] = wireEnvelope
  ..['direct_media_custody_intent_id'] = null;

Future<Map<String, Object?>> _tc345AuthoritySnapshot(
  sqlcipher.Database db,
) async => <String, Object?>{
  'user_version': await _userVersion(db),
  'messages': await db.query('messages', orderBy: 'id'),
  'media': await db.query('media_attachments', orderBy: 'id'),
  'direct_custody': await db.query(
    'direct_inbox_custody_outbox',
    orderBy: 'recipient_peer_id, message_id',
  ),
  'reaction_custody': await db.query(
    'direct_reaction_inbox_custody_outbox',
    orderBy: 'recipient_peer_id, event_id',
  ),
  'reaction_terminal': await db.query(
    'direct_notification_reaction_terminal_events',
    orderBy: 'peer_id, message_id, actor_peer_id, reaction_id',
  ),
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

DirectMediaBlobCustodyRow _v111PreparedBlobCustodyRow() =>
    DirectMediaBlobCustodyRow(
      attachmentId: _v111AttachmentId,
      messageId: _v111MessageId,
      direction: DirectMediaBlobCustodyDirection.outgoing,
      state: DirectMediaBlobCustodyState.outgoingPrepared,
      inboxCustodyIncarnationId: null,
      recipientPeerId: _recipientPeerId,
      ciphertextRelativePath:
          'direct_media_blob_custody_v1/peer-self/$_v111AttachmentId.blob',
      contentHash: _v111ContentHash,
      ciphertextSize: 512,
      expiresAtMs: null,
      custodyRelayPeerId: null,
      lastAttemptAt: null,
      nextAttemptAt: null,
      createdAt: _at,
      updatedAt: _at,
    );

List<Map<String, Object?>> _v114DirectMediaBlobCustodyRows() =>
    <Map<String, Object?>>[
      _v114DirectMediaBlobCustodyRow(
        attachmentId: 'tc365-direct-prepared',
        state: 'outgoing_prepared',
      ),
      _v114DirectMediaBlobCustodyRow(
        attachmentId: 'tc365-direct-stored',
        state: 'outgoing_stored',
        expiresAtMs: 4102444800000,
        relayPeerId: 'tc365-relay-stored',
      ),
      _v114DirectMediaBlobCustodyRow(
        attachmentId: 'tc365-direct-cleanup',
        state: 'outgoing_cleanup_pending',
        incarnationId: 'dddddddddddddddddddddddddddddddd',
        expiresAtMs: 4102444800000,
        relayPeerId: 'tc365-relay-cleanup',
      ),
      _v114DirectMediaBlobCustodyRow(
        attachmentId: 'tc365-direct-incoming-committed',
        state: 'incoming_committed',
        incoming: true,
        expiresAtMs: 4102444800000,
      ),
      _v114DirectMediaBlobCustodyRow(
        attachmentId: 'tc365-direct-incoming-ack',
        state: 'incoming_ack_pending',
        incoming: true,
        expiresAtMs: 4102444800000,
        relayPeerId: 'tc365-relay-incoming',
      ),
    ];

Map<String, Object?> _v114DirectMediaBlobCustodyRow({
  required String attachmentId,
  required String state,
  bool incoming = false,
  String? incarnationId,
  int? expiresAtMs,
  String? relayPeerId,
}) => <String, Object?>{
  'attachment_id': attachmentId,
  'message_id': 'message-$attachmentId',
  'direction': incoming ? 'incoming' : 'outgoing',
  'state': state,
  'inbox_custody_incarnation_id': incarnationId,
  'recipient_peer_id': incoming ? null : 'recipient-$attachmentId',
  'contact_account_peer_id': null,
  'recipient_ml_kem_public_key': null,
  'ciphertext_relative_path': incoming
      ? null
      : 'direct_media_blob_custody_v1/identity-scope/$attachmentId.blob',
  'custody_kind': 'direct_media_blob_v1',
  'custody_contract': 'ack_or_expiry_v1',
  'content_hash': _v111ContentHash,
  'ciphertext_size': 512,
  'transport_mime': 'application/octet-stream',
  'expires_at_ms': expiresAtMs,
  'custody_relay_peer_id': relayPeerId,
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': _at,
  'updated_at': _at,
};

Map<String, Object?> _v115GroupMessageRow() => const <String, Object?>{
  'id': _v115GroupMessageId,
  'group_id': _v115GroupId,
  'sender_peer_id': 'tc365-sender',
  'sender_username': 'TC365 Sender',
  'text': '',
  'timestamp': _at,
  'key_generation': 1,
  'status': 'pending',
  'is_incoming': 0,
  'created_at': _at,
};

Map<String, Object?> _v115GroupAttachmentRow(String fingerprint) =>
    <String, Object?>{
      'id': _v115GroupAttachmentId,
      'message_id': _v115GroupMessageId,
      'mime': 'image/jpeg',
      'size': 32,
      'media_type': 'image',
      'width': null,
      'height': null,
      'duration_ms': null,
      'local_path': _v115GroupCiphertextPath,
      'download_status': 'upload_pending',
      'created_at': _at,
      'waveform': null,
      'upload_retry_count': 0,
      'download_retry_count': 0,
      'content_hash': _v115GroupContentHash,
      'thumbnail_hash': null,
      'encryption_key_base64': secureStoreReferenceForKey(
        mediaAttachmentEncryptionKeyStoreName(_v115GroupAttachmentId),
      ),
      'encryption_nonce': 'dGMzNjUtbm9uY2U=',
      'encryption_scheme': 'blob_aes_256_gcm_v1',
      'owner_lane': 'group',
      'is_bookmarked': 0,
      'last_playback_position_ms': 0,
      'group_media_blob_custody_fingerprint': fingerprint,
    };

List<DirectMediaBlobCustodyRow> _v115GroupCustodyRows() =>
    const <String>['tc365-device-a', 'tc365-device-b']
        .map(
          (recipient) => DirectMediaBlobCustodyRow(
            attachmentId: _v115GroupAttachmentId,
            messageId: _v115GroupMessageId,
            ownerLane: MediaBlobCustodyOwnerLane.group,
            groupId: _v115GroupId,
            custodyBlobId: _v115GroupCustodyBlobId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingPrepared,
            inboxCustodyIncarnationId: null,
            recipientPeerId: recipient,
            ciphertextRelativePath: _v115GroupCiphertextPath,
            custodyKind: kGroupMediaBlobCustodyKind,
            contentHash: _v115GroupContentHash,
            ciphertextSize: 48,
            expiresAtMs: null,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: _at,
            updatedAt: _at,
          ),
        )
        .toList(growable: false);

Map<String, Object?> _v114Projection(Map<String, Object?> row) =>
    <String, Object?>{
      for (final column in _v114MediaBlobCustodyColumns) column: row[column],
    };

Future<Map<String, Object?>> _v115AuthoritySnapshot(
  sqlcipher.Database db,
) async => <String, Object?>{
  'custody': await db.query(
    kDirectMediaBlobCustodyTable,
    orderBy: 'owner_lane, attachment_id, recipient_peer_id',
  ),
  'group_message': await db.query(
    'group_messages',
    where: 'id = ?',
    whereArgs: const <Object?>[_v115GroupMessageId],
  ),
  'group_attachment': await db.query(
    'media_attachments',
    where: 'id = ? AND message_id = ? AND owner_lane = ?',
    whereArgs: const <Object?>[
      _v115GroupAttachmentId,
      _v115GroupMessageId,
      'group',
    ],
  ),
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
      expect(currentIdentityDatabaseVersion, 116);

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

        proofStage = 'upgrade-v107-to-current-v116';
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

        proofStage = 'reopen-current-v116-unchanged-after-refusal';
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
        expect(await _authoritySnapshot(db), beforeDowngradeRefusal);
      } catch (error, stackTrace) {
        fail('TC-342-11 failed at $proofStage: $error\n$stackTrace');
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'TC-345-11 Android SQLCipher v109-to-v110 media custody and downgrade floor survive reopen',
    (_) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'TC-345-11 is an Android SQLCipher plugin boundary proof',
      );
      expect(currentIdentityDatabaseVersion, 116);

      final temp = await Directory.systemTemp.createTemp(
        'direct_media_custody_sqlcipher_',
      );
      final path = '${temp.path}/identity.db';
      const password = 'tc345-sqlcipher-password';
      sqlcipher.Database? db;
      var proofStage = 'create-v109';

      try {
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 109,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 109);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(
          (await db.rawQuery('PRAGMA table_info(messages)')).where(
            (column) => column['name'] == 'direct_media_custody_intent_id',
          ),
          isEmpty,
        );

        proofStage = 'seed-v108-text-and-v109-reaction-authority';
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
        await db.insert(
          'direct_notification_reaction_terminal_events',
          _v107TerminalRow(),
        );
        await db.insert(
          'direct_reaction_inbox_custody_outbox',
          _v109ReactionCustodyRow(),
        );
        await db.close();
        db = null;

        proofStage = 'upgrade-v109-through-v110-to-current-v116';
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
        expect(
          (await db.query(
            'messages',
            columns: const <String>['direct_media_custody_intent_id'],
            where: 'id = ?',
            whereArgs: const <Object?>[_messageId],
          )).single['direct_media_custody_intent_id'],
          isNull,
          reason: 'v109 rows must not be backfilled with invented freshness',
        );
        expect(await db.query('direct_inbox_custody_outbox'), hasLength(1));
        expect(
          await db.query('direct_reaction_inbox_custody_outbox'),
          <Map<String, Object?>>[
            // 361: the v113 additive columns exist but stay NULL for the
            // historical pre-fanout row — no invented backfill.
            <String, Object?>{
              ..._v109ReactionCustodyRow(),
              'contact_account_peer_id': null,
              'parent_message_id': null,
            },
          ],
        );

        proofStage = 'idempotent-v110-migration';
        await runDirectMediaCustodyIntentMigration(db);
        await runDirectMediaCustodyIntentMigration(db);
        final intentColumns = (await db.rawQuery('PRAGMA table_info(messages)'))
            .where(
              (column) => column['name'] == 'direct_media_custody_intent_id',
            );
        expect(intentColumns, hasLength(1));

        proofStage = 'persist-prepared-media-intent';
        await db.insert(
          'messages',
          _preparedMediaMessageRow(
            messageId: _mediaMessageId,
            attachmentId: _mediaAttachmentId,
          ),
        );
        await db.insert(
          'media_attachments',
          _pendingMediaAttachmentRow(
            messageId: _mediaMessageId,
            attachmentId: _mediaAttachmentId,
          ),
        );
        final pendingIntent = computeDirectMediaCustodyIntentId(
          messageId: _mediaMessageId,
          attachmentIds: const <String>[_mediaAttachmentId],
        );
        await db.close();
        db = null;

        proofStage = 'wrong-key-refusal';
        sqlcipher.Database? wrong;
        await expectLater(() async {
          wrong = await sqlcipher.openDatabase(
            path,
            password: 'wrong-tc345-password',
            singleInstance: false,
          );
          await wrong!.rawQuery('SELECT COUNT(*) FROM messages');
        }(), throwsA(anything));
        if (wrong != null && wrong!.isOpen) await wrong!.close();

        proofStage = 'prepared-intent-reopen';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        var prepared = (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[_mediaMessageId],
        )).single;
        var pendingAttachment = (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: const <Object?>[_mediaAttachmentId],
        )).single;
        expect(prepared['direct_media_custody_intent_id'], pendingIntent);
        expect(pendingAttachment['download_status'], 'upload_pending');

        proofStage = 'atomic-media-custody-stage';
        final mediaEnvelope = _mediaWireEnvelope(_mediaMessageId);
        final mediaStage = await dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: prepared,
          stagedRow: _stagedMediaMessageRow(prepared, mediaEnvelope),
          attachmentRows: <Map<String, Object?>>[
            _completedMediaAttachmentRow(pendingAttachment),
          ],
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: _recipientPeerId,
          wireEnvelope: mediaEnvelope,
        );
        expect(mediaStage.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(
          mediaStage.messageRow?['direct_media_custody_intent_id'],
          isNull,
        );
        expect(mediaStage.messageRow?['wire_envelope'], mediaEnvelope);
        expect(mediaStage.attachmentRows.single['download_status'], 'done');
        expect(mediaStage.custodyRow?['incarnation_id'], pendingIntent);
        expect(mediaStage.custodyRow?['wire_envelope'], mediaEnvelope);

        final committedSnapshot = await _tc345AuthoritySnapshot(db);
        await db.close();
        db = null;

        proofStage = 'atomic-media-custody-reopen';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _tc345AuthoritySnapshot(db), committedSnapshot);

        proofStage = 'prepare-rollback-fixture';
        await db.insert(
          'messages',
          _preparedMediaMessageRow(
            messageId: _rollbackMessageId,
            attachmentId: _rollbackAttachmentId,
          ),
        );
        await db.insert(
          'media_attachments',
          _pendingMediaAttachmentRow(
            messageId: _rollbackMessageId,
            attachmentId: _rollbackAttachmentId,
          ),
        );
        prepared = (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[_rollbackMessageId],
        )).single;
        pendingAttachment = (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: const <Object?>[_rollbackAttachmentId],
        )).single;
        final beforeRollback = await _tc345AuthoritySnapshot(db);
        await db.execute('''
CREATE TRIGGER tc345_abort_media_custody_insert
BEFORE INSERT ON direct_inbox_custody_outbox
WHEN NEW.message_id = '$_rollbackMessageId'
BEGIN
  SELECT RAISE(ABORT, 'simulated media custody commit failure');
END
''');

        proofStage = 'combined-stage-rollback';
        final rollbackEnvelope = _mediaWireEnvelope(_rollbackMessageId);
        await expectLater(
          dbStageOutgoingDirectMediaInboxCustody(
            db,
            expectedRow: prepared,
            stagedRow: _stagedMediaMessageRow(prepared, rollbackEnvelope),
            attachmentRows: <Map<String, Object?>>[
              _completedMediaAttachmentRow(pendingAttachment),
            ],
            kind: OutgoingOrdinaryAttemptKind.existing,
            recipientPeerId: _recipientPeerId,
            wireEnvelope: rollbackEnvelope,
          ),
          throwsA(anything),
        );
        await db.execute('DROP TRIGGER tc345_abort_media_custody_insert');
        expect(await _tc345AuthoritySnapshot(db), beforeRollback);

        proofStage = 'current-v116-to-v109-downgrade-refusal';
        final beforeDowngradeRefusal = await _tc345AuthoritySnapshot(db);
        await db.close();
        db = null;
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 109,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        proofStage = 'reopen-current-v116-unchanged-after-downgrade-refusal';
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
        expect(await _tc345AuthoritySnapshot(db), beforeDowngradeRefusal);
      } catch (error, stackTrace) {
        fail('TC-345-11 failed at $proofStage: $error\n$stackTrace');
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'TC-347-01 Android SQLCipher v110-to-v111 blob custody survives reopen',
    (_) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'TC-347-01 is an Android SQLCipher plugin boundary proof',
      );
      expect(currentIdentityDatabaseVersion, 116);

      final temp = await Directory.systemTemp.createTemp(
        'direct_media_blob_custody_sqlcipher_',
      );
      final path = '${temp.path}/identity.db';
      const password = 'tc347-sqlcipher-password';
      sqlcipher.Database? db;
      var proofStage = 'create-v110';

      try {
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 110,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 110);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'direct_media_blob_custody'",
          ),
          isEmpty,
        );
        await db.insert('direct_inbox_custody_outbox', <String, Object?>{
          'recipient_peer_id': _recipientPeerId,
          'message_id': _v111MessageId,
          'incarnation_id': _v111IncarnationId,
          'wire_envelope': _mediaWireEnvelope(_v111MessageId),
          'retry_count': 0,
          'last_attempt_at': null,
          'last_error_code': null,
          'created_at': _at,
          'updated_at': _at,
        });
        await db.close();
        db = null;

        proofStage = 'upgrade-v110-to-v111-without-backfill';
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
        final historical = (await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: const <Object?>[_v111MessageId],
        )).single;
        expect(historical['media_blob_manifest_hash'], isNull);
        expect(historical['media_blob_expires_at_ms'], isNull);
        expect(await db.query('direct_media_blob_custody'), isEmpty);

        proofStage = 'stage-and-store-independent-v111-authority';
        final prepared = _v111PreparedBlobCustodyRow();
        expect(
          await dbStageInitialDirectMediaBlobCustodyBatch(
            db,
            rows: <DirectMediaBlobCustodyRow>[prepared],
          ),
          DirectMediaBlobCustodyBatchStageOutcome.applied,
        );
        final stored = prepared.copyWith(
          state: DirectMediaBlobCustodyState.outgoingStored,
          expiresAtMs: 1999999999000,
          custodyRelayPeerId: 'relay-plan347',
          updatedAt: _attemptedAt,
        );
        expect(
          await dbTransitionDirectMediaBlobCustodyIfExact(
            db,
            expected: prepared,
            next: stored,
          ),
          isTrue,
        );
        final expectedSnapshot = <String, Object?>{
          'v108': await db.query('direct_inbox_custody_outbox'),
          'v111': await db.query('direct_media_blob_custody'),
        };

        proofStage = 'run-v111-migration-twice';
        await runDirectMediaBlobCustodyMigration(db);
        await runDirectMediaBlobCustodyMigration(db);
        expect(<String, Object?>{
          'v108': await db.query('direct_inbox_custody_outbox'),
          'v111': await db.query('direct_media_blob_custody'),
        }, expectedSnapshot);
        await db.close();
        db = null;

        proofStage = 'wrong-key-refusal';
        sqlcipher.Database? wrong;
        await expectLater(() async {
          wrong = await sqlcipher.openDatabase(
            path,
            password: 'wrong-tc347-password',
            singleInstance: false,
          );
          await wrong!.rawQuery(
            'SELECT COUNT(*) FROM direct_media_blob_custody',
          );
        }(), throwsA(anything));
        if (wrong != null && wrong!.isOpen) await wrong!.close();

        proofStage = 'v111-reopen-retains-exact-authority';
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
        expect(
          DirectMediaBlobCustodyRow.fromMap(
            (await db.query('direct_media_blob_custody')).single,
          ).exactDatabaseProjectionMatches(stored),
          isTrue,
        );
        expect(<String, Object?>{
          'v108': await db.query('direct_inbox_custody_outbox'),
          'v111': await db.query('direct_media_blob_custody'),
        }, expectedSnapshot);
        await db.close();
        db = null;

        proofStage = 'v111-to-v110-downgrade-refusal';
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 110,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        proofStage = 'reopen-v111-unchanged-after-downgrade-refusal';
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(<String, Object?>{
          'v108': await db.query('direct_inbox_custody_outbox'),
          'v111': await db.query('direct_media_blob_custody'),
        }, expectedSnapshot);
      } catch (error, stackTrace) {
        fail('TC-347-01 failed at $proofStage: $error\n$stackTrace');
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'TC-361-04a Android SQLCipher v112-to-v113 linked event fanout custody survives reopen',
    (_) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'TC-361-04a is an Android SQLCipher plugin boundary proof',
      );
      expect(currentIdentityDatabaseVersion, 116);

      final temp = await Directory.systemTemp.createTemp(
        'direct_event_fanout_sqlcipher_',
      );
      final path = '${temp.path}/identity.db';
      const password = 'tc361-sqlcipher-password';
      const fanoutContact = 'peer-fanout-contact';
      const fanoutGeneration = 'tc361-generation-1';
      sqlcipher.Database? db;
      var proofStage = 'create-v112';

      try {
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 112,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 112);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(
          (await db.rawQuery('PRAGMA table_info(messages)')).where(
            (column) => column['name'] == 'direct_event_fanout_generation_id',
          ),
          isEmpty,
        );
        expect(
          (await db.rawQuery(
            'PRAGMA table_info(direct_inbox_custody_outbox)',
          )).where((column) => column['name'] == 'contact_account_peer_id'),
          isEmpty,
        );

        proofStage = 'seed-historical-v108-and-v109-authority';
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
        await db.insert(
          'direct_reaction_inbox_custody_outbox',
          _v109ReactionCustodyRow(),
        );
        await db.close();
        db = null;

        proofStage = 'upgrade-v112-to-v113-without-backfill';
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
        final historicalText = (await db.query(
          'direct_inbox_custody_outbox',
        )).single;
        expect(historicalText['contact_account_peer_id'], isNull);
        final historicalEvent = (await db.query(
          'direct_reaction_inbox_custody_outbox',
        )).single;
        expect(historicalEvent['contact_account_peer_id'], isNull);
        expect(historicalEvent['parent_message_id'], isNull);
        expect(
          (await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: const <Object?>[_messageId],
          )).single['direct_event_fanout_generation_id'],
          isNull,
          reason: 'historical rows must not gain an invented fanout marker',
        );

        proofStage = 'idempotent-v113-migration';
        await runDirectLinkedDeviceEventFanoutMigration(db);
        await runDirectLinkedDeviceEventFanoutMigration(db);
        expect(
          (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN "
            "('idx_direct_inbox_custody_outbox_generation', "
            "'idx_direct_reaction_inbox_custody_outbox_generation')",
          )).length,
          2,
        );

        proofStage = 'persist-fanout-generation-authority';
        final fanoutMessage = Map<String, Object?>.from(_stagedMessage())
          ..['id'] = 'tc361-fanout-message'
          ..['dedup_key'] = 'tc361-fanout-message'
          ..['contact_peer_id'] = fanoutContact
          ..['wire_envelope'] = null
          ..['direct_event_fanout_generation_id'] = fanoutGeneration;
        await db.insert('messages', fanoutMessage);
        for (final sibling in const <(String, String)>[
          ('peer-device-a', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          ('peer-device-b', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        ]) {
          await db.insert('direct_inbox_custody_outbox', <String, Object?>{
            'recipient_peer_id': sibling.$1,
            'message_id': 'tc361-fanout-message',
            'incarnation_id': sibling.$2,
            'wire_envelope': _mediaWireEnvelope('tc361-fanout-message'),
            'retry_count': 0,
            'last_attempt_at': null,
            'last_error_code': null,
            'contact_account_peer_id': fanoutContact,
            'created_at': _at,
            'updated_at': _at,
          });
        }
        await db
            .insert('direct_reaction_inbox_custody_outbox', <String, Object?>{
              'recipient_peer_id': 'peer-device-a',
              'event_id': 'tc361-fanout-event',
              'wire_envelope': '{"type":"message_reaction","version":"2"}',
              'retry_count': 0,
              'last_attempt_at': null,
              'last_error_code': null,
              'contact_account_peer_id': fanoutContact,
              'parent_message_id': 'tc361-fanout-message',
              'created_at': _at,
              'updated_at': _at,
            });
        final committedSnapshot = await _tc345AuthoritySnapshot(db);
        await db.close();
        db = null;

        proofStage = 'wrong-key-refusal';
        sqlcipher.Database? wrong;
        await expectLater(() async {
          wrong = await sqlcipher.openDatabase(
            path,
            password: 'wrong-tc361-password',
            singleInstance: false,
          );
          await wrong!.rawQuery(
            'SELECT COUNT(*) FROM direct_inbox_custody_outbox',
          );
        }(), throwsA(anything));
        if (wrong != null && wrong!.isOpen) await wrong!.close();

        proofStage = 'v113-reopen-retains-exact-fanout-authority';
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
        expect(await _tc345AuthoritySnapshot(db), committedSnapshot);
        await db.close();
        db = null;

        proofStage = 'v113-to-v112-downgrade-refusal';
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 112,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        proofStage = 'reopen-v113-unchanged-after-downgrade-refusal';
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
        expect(await _tc345AuthoritySnapshot(db), committedSnapshot);
      } catch (error, stackTrace) {
        fail('TC-361-04a failed at $proofStage: $error\n$stackTrace');
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'TC-362-05a Android SQLCipher v113-to-v114 linked media fanout survives reopen',
    (_) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'TC-362-05a is an Android SQLCipher plugin boundary proof',
      );
      expect(currentIdentityDatabaseVersion, 116);

      final temp = await Directory.systemTemp.createTemp(
        'direct_media_fanout_sqlcipher_',
      );
      final path = '${temp.path}/identity.db';
      const password = 'tc362-sqlcipher-password';
      const fanoutContact = 'peer-media-fanout-contact';
      const linkedTransport = 'peer-media-fanout-linked-device';
      const legacyAttachment = 'tc362-legacy-attachment';
      const fanoutAttachment = 'tc362-fanout-attachment';
      const contentHash =
          '2222222222222222222222222222222222222222222222222222222222222222';
      sqlcipher.Database? db;
      var proofStage = 'create-v113';

      Map<String, Object?> legacyV111Row() => const <String, Object?>{
        'attachment_id': legacyAttachment,
        'message_id': 'tc362-legacy-message',
        'direction': 'outgoing',
        'state': 'outgoing_stored',
        'inbox_custody_incarnation_id': 'cccccccccccccccccccccccccccccccc',
        'recipient_peer_id': fanoutContact,
        'ciphertext_relative_path':
            'direct_media_blob_custody_v1/scope/tc362-legacy-attachment.blob',
        'custody_kind': 'direct_media_blob_v1',
        'custody_contract': 'ack_or_expiry_v1',
        'content_hash': contentHash,
        'ciphertext_size': 1024,
        'transport_mime': 'application/octet-stream',
        'expires_at_ms': 4102444800000,
        'custody_relay_peer_id': 'peer-relay',
        'retry_count': 0,
        'last_attempt_at': null,
        'next_attempt_at': null,
        'created_at': _at,
        'updated_at': _at,
      };
      Map<String, Object?> fanoutTargetRow(
        String recipient,
      ) => <String, Object?>{
        'attachment_id': fanoutAttachment,
        'message_id': 'tc362-fanout-message',
        'direction': 'outgoing',
        'state': 'outgoing_prepared',
        'inbox_custody_incarnation_id': null,
        'recipient_peer_id': recipient,
        'contact_account_peer_id': fanoutContact,
        'recipient_ml_kem_public_key': 'mlkem-$recipient',
        'ciphertext_relative_path':
            'direct_media_blob_custody_v1/scope/tc362-fanout-attachment.blob',
        'custody_kind': 'direct_media_blob_v1',
        'custody_contract': 'ack_or_expiry_v1',
        'content_hash': contentHash,
        'ciphertext_size': 2048,
        'transport_mime': 'application/octet-stream',
        'expires_at_ms': null,
        'custody_relay_peer_id': null,
        'retry_count': 0,
        'last_attempt_at': null,
        'next_attempt_at': null,
        'created_at': _at,
        'updated_at': _at,
        'owner_lane': 'direct',
        'group_id': null,
        'custody_blob_id': fanoutAttachment,
      };
      Future<List<Map<String, Object?>>> custodySnapshot(
        sqlcipher.Database database,
      ) => database.query(
        'direct_media_blob_custody',
        orderBy: 'attachment_id, direction, recipient_peer_id',
      );

      try {
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 113,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 113);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(
          (await db.rawQuery(
            'PRAGMA table_info(direct_media_blob_custody)',
          )).where((column) => column['name'] == 'contact_account_peer_id'),
          isEmpty,
        );

        proofStage = 'seed-legal-legacy-v111-authority';
        await db.insert('direct_media_blob_custody', legacyV111Row());
        final v113Legacy = await custodySnapshot(db);
        await db.close();
        db = null;

        proofStage =
            'upgrade-v113-through-v114-to-current-preserves-legacy-untouched';
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
        final upgraded = await custodySnapshot(db);
        expect(upgraded, hasLength(v113Legacy.length));
        for (var index = 0; index < upgraded.length; index++) {
          expect(upgraded[index]['contact_account_peer_id'], isNull);
          expect(upgraded[index]['recipient_ml_kem_public_key'], isNull);
          expect(upgraded[index]['owner_lane'], 'direct');
          expect(upgraded[index]['group_id'], isNull);
          expect(
            upgraded[index]['custody_blob_id'],
            upgraded[index]['attachment_id'],
          );
          final projected = Map<String, Object?>.from(upgraded[index])
            ..remove('contact_account_peer_id')
            ..remove('recipient_ml_kem_public_key')
            ..remove('owner_lane')
            ..remove('group_id')
            ..remove('custody_blob_id');
          expect(projected, v113Legacy[index]);
        }

        proofStage = 'idempotent-v114-migration';
        await runDirectLinkedDeviceMediaBlobFanoutMigration(db);
        await runDirectLinkedDeviceMediaBlobFanoutMigration(db);
        expect(await _userVersion(db), 116);

        proofStage = 'persist-two-same-attachment-target-rows';
        await db.insert('messages', <String, Object?>{
          ..._stagedMessage(),
          'id': 'tc362-fanout-message',
          'dedup_key': 'tc362-fanout-message',
          'contact_peer_id': fanoutContact,
          'wire_envelope': null,
          'direct_event_fanout_generation_id': 'tc362-fanout-message',
        });
        await db.insert(
          'direct_media_blob_custody',
          fanoutTargetRow(fanoutContact),
        );
        await db.insert(
          'direct_media_blob_custody',
          fanoutTargetRow(linkedTransport),
        );
        await expectLater(
          db.insert(
            'direct_media_blob_custody',
            fanoutTargetRow(fanoutContact),
          ),
          throwsA(anything),
          reason: 'one outgoing row per exact (attachment, recipient)',
        );
        final committedSnapshot = await custodySnapshot(db);
        expect(committedSnapshot, hasLength(3));
        await db.close();
        db = null;

        proofStage = 'wrong-key-refusal';
        sqlcipher.Database? wrong;
        await expectLater(() async {
          wrong = await sqlcipher.openDatabase(
            path,
            password: 'wrong-tc362-password',
            singleInstance: false,
          );
          await wrong!.rawQuery(
            'SELECT COUNT(*) FROM direct_media_blob_custody',
          );
        }(), throwsA(anything));
        if (wrong != null && wrong!.isOpen) await wrong!.close();

        proofStage = 'current-reopen-retains-exact-fanout-authority';
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
        expect(await custodySnapshot(db), committedSnapshot);

        proofStage = 'rerun-v114-migration-preserves-fanout-rows';
        await runDirectLinkedDeviceMediaBlobFanoutMigration(db);
        expect(await custodySnapshot(db), committedSnapshot);
        await db.close();
        db = null;

        proofStage = 'current-to-v113-downgrade-refusal';
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 113,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        proofStage = 'reopen-current-unchanged-after-downgrade-refusal';
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
        expect(await custodySnapshot(db), committedSnapshot);
      } catch (error, stackTrace) {
        fail('TC-362-05a failed at $proofStage: $error\n$stackTrace');
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'TC-365-01a Android SQLCipher v114-to-v115 group media custody survives reopen',
    (_) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'TC-365-01a is an Android SQLCipher plugin boundary proof',
      );
      expect(currentIdentityDatabaseVersion, 116);

      final temp = await Directory.systemTemp.createTemp(
        'group_media_blob_custody_sqlcipher_',
      );
      final path = '${temp.path}/identity.db';
      const password = 'tc365-sqlcipher-password';
      sqlcipher.Database? db;
      var proofStage = 'create-v114';

      try {
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 114,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _userVersion(db), 114);
        expect(await _cipherVersion(db), isNotEmpty);
        expect(
          (await db.rawQuery(
            'PRAGMA table_info($kDirectMediaBlobCustodyTable)',
          )).where((column) => column['name'] == 'owner_lane'),
          isEmpty,
        );
        expect(
          (await db.rawQuery('PRAGMA table_info(media_attachments)')).where(
            (column) =>
                column['name'] == 'group_media_blob_custody_fingerprint',
          ),
          isEmpty,
        );

        proofStage = 'seed-every-legal-v114-direct-state-family';
        for (final row in _v114DirectMediaBlobCustodyRows()) {
          await db.insert(kDirectMediaBlobCustodyTable, row);
        }
        final v114Projection = await db.query(
          kDirectMediaBlobCustodyTable,
          orderBy: 'attachment_id',
        );
        expect(v114Projection, hasLength(5));
        await db.close();
        db = null;

        proofStage = 'upgrade-v114-to-v115-preserves-direct-projection';
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
        final upgradedDirect = await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'owner_lane = ?',
          whereArgs: const <Object?>['direct'],
          orderBy: 'attachment_id',
        );
        expect(upgradedDirect, hasLength(v114Projection.length));
        for (var index = 0; index < v114Projection.length; index++) {
          expect(_v114Projection(upgradedDirect[index]), v114Projection[index]);
          expect(upgradedDirect[index]['owner_lane'], 'direct');
          expect(upgradedDirect[index]['group_id'], isNull);
          expect(
            upgradedDirect[index]['custody_blob_id'],
            upgradedDirect[index]['attachment_id'],
          );
        }

        proofStage = 'atomically-stage-group-parent-attachment-and-targets';
        final groupRows = _v115GroupCustodyRows();
        final fingerprint = computeGroupMediaBlobCustodyFingerprint(
          groupId: _v115GroupId,
          messageId: _v115GroupMessageId,
          attachmentId: _v115GroupAttachmentId,
          custodyBlobId: _v115GroupCustodyBlobId,
          contentHash: _v115GroupContentHash,
          ciphertextSize: 48,
          recipientPeerIds: groupRows.map((row) => row.recipientPeerId!),
        );
        expect(
          await dbStageFreshOutgoingGroupMediaBlobGeneration(
            db,
            parentRow: _v115GroupMessageRow(),
            attachmentRows: <Map<String, Object?>>[
              _v115GroupAttachmentRow(fingerprint),
            ],
            custodyRows: groupRows,
            custodyBlobIdsByAttachmentId: const <String, String>{
              _v115GroupAttachmentId: _v115GroupCustodyBlobId,
            },
          ),
          DirectMediaBlobCustodyBatchStageOutcome.applied,
        );
        expect(
          (await db.query(
            'media_attachments',
            columns: const <String>['group_media_blob_custody_fingerprint'],
            where: 'id = ? AND message_id = ? AND owner_lane = ?',
            whereArgs: const <Object?>[
              _v115GroupAttachmentId,
              _v115GroupMessageId,
              'group',
            ],
          )).single['group_media_blob_custody_fingerprint'],
          fingerprint,
        );
        final persistedGroup = await dbLoadGroupMediaBlobCustodyForMessage(
          db,
          groupId: _v115GroupId,
          messageId: _v115GroupMessageId,
        );
        expect(persistedGroup, hasLength(2));
        expect(
          persistedGroup,
          everyElement(
            isA<DirectMediaBlobCustodyRow>()
                .having(
                  (row) => row.ownerLane,
                  'owner lane',
                  MediaBlobCustodyOwnerLane.group,
                )
                .having(
                  (row) => row.custodyBlobId,
                  'custody blob ID',
                  _v115GroupCustodyBlobId,
                ),
          ),
        );
        expect(
          await dbLoadDirectMediaBlobCustodyRowsForAttachment(
            db,
            attachmentId: _v115GroupAttachmentId,
          ),
          isEmpty,
          reason: 'the incumbent direct loader remains lane-isolated',
        );
        final committedSnapshot = await _v115AuthoritySnapshot(db);
        await db.close();
        db = null;

        proofStage = 'wrong-key-refusal';
        sqlcipher.Database? wrong;
        await expectLater(() async {
          wrong = await sqlcipher.openDatabase(
            path,
            password: 'wrong-tc365-password',
            singleInstance: false,
          );
          await wrong!.rawQuery(
            'SELECT COUNT(*) FROM $kDirectMediaBlobCustodyTable',
          );
        }(), throwsA(anything));
        if (wrong != null && wrong!.isOpen) await wrong!.close();

        proofStage = 'reopen-v115-and-rerun-migration-idempotently';
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
        expect(await _v115AuthoritySnapshot(db), committedSnapshot);
        await runGroupMediaBlobCustodyMigration(db);
        await runGroupMediaBlobCustodyMigration(db);
        expect(await _v115AuthoritySnapshot(db), committedSnapshot);
        await db.close();
        db = null;

        proofStage = 'v115-to-v114-downgrade-refusal';
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 114,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        proofStage = 'reopen-v115-unchanged-after-downgrade-refusal';
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
        expect(await _v115AuthoritySnapshot(db), committedSnapshot);
      } catch (error, stackTrace) {
        fail('TC-365-01a failed at $proofStage: $error\n$stackTrace');
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );
}
