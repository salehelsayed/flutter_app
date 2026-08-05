@Tags(['device'])
library;

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

const _peerId = 'r1-peer';
const _selfPeerId = 'r1-self';
const _mediaMessageId = 'r1-media-message';
const _mediaAttachmentId = 'r1-media-attachment';
const _mediaEnvelope = 'r1-media-envelope';
const _tombstoneMessageId = 'r1-tombstone-message';
const _tombstoneEnvelope = 'r1-tombstone-envelope';
const _createdAt = '2026-08-05T12:00:00.000Z';
const _deletedAt = '2026-08-05T12:01:00.000Z';

Future<String> _cipherVersion(sqlcipher.Database db) async =>
    (await db.rawQuery(
      'PRAGMA cipher_version',
    )).single.values.single.toString();

Future<Map<String, Object?>> _loadMessage(
  sqlcipher.Database db,
  String messageId,
) async => Map<String, Object?>.from(
  (await db.query(
    'messages',
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
  )).single,
);

Future<List<Map<String, Object?>>> _loadProofMessages(
  sqlcipher.Database db,
) async => (await db.query(
  'messages',
  where: 'id IN (?, ?)',
  whereArgs: const <Object?>[_mediaMessageId, _tombstoneMessageId],
  orderBy: 'id',
)).map(Map<String, Object?>.from).toList(growable: false);

Future<List<Map<String, Object?>>> _loadProofAttachments(
  sqlcipher.Database db,
) async => (await db.query(
  'media_attachments',
  where: 'id = ?',
  whereArgs: const <Object?>[_mediaAttachmentId],
  orderBy: 'id',
)).map(Map<String, Object?>.from).toList(growable: false);

Map<String, Object?> _mediaParentRow({
  String messageId = _mediaMessageId,
  String envelope = _mediaEnvelope,
}) => ConversationMessage(
  id: messageId,
  contactPeerId: _peerId,
  senderPeerId: _selfPeerId,
  text: 'encrypted media payload',
  timestamp: _createdAt,
  status: 'sending',
  isIncoming: false,
  createdAt: _createdAt,
  wireEnvelope: envelope,
  dedupKey: messageId,
).toMap();

Map<String, Object?> _mediaAttachmentRow({
  String messageId = _mediaMessageId,
  String attachmentId = _mediaAttachmentId,
}) => MediaAttachment(
  id: attachmentId,
  messageId: messageId,
  mime: 'image/jpeg',
  size: 4096,
  mediaType: 'image',
  width: 32,
  height: 32,
  localPath: 'pending_uploads/$messageId/$attachmentId.enc',
  downloadStatus: 'upload_pending',
  createdAt: _createdAt,
  uploadRetryCount: 0,
  downloadRetryCount: 0,
  contentHash:
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  encryptionKeyBase64: secureStoreReferenceForKey(
    mediaAttachmentEncryptionKeyStoreName(attachmentId),
  ),
  encryptionNonce: 'r1-nonce',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  ownerLane: MediaOwnerLane.direct,
).toMap();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'R1 keyed SQLCipher preserves atomic outgoing settlement across reopen',
    (_) async {
      final tempDir = await Directory.systemTemp.createTemp(
        'outgoing_transport_settlement_sqlcipher_',
      );
      final databasePath = p.join(tempDir.path, 'settlement.db');
      const password = 'plan-336-r1-correct-sqlcipher-key';
      sqlcipher.Database? db;
      final previousFlowEventLogging = flowEventLoggingEnabled;
      flowEventLoggingEnabled = false;
      var proofStage = 'create-keyed-production-schema';
      try {
        db = await sqlcipher.openDatabase(
          databasePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _cipherVersion(db), isNotEmpty);
        await db.close();
        db = null;

        proofStage = 'reject-wrong-key-read';
        await expectLater(() async {
          sqlcipher.Database? wrongKeyDb;
          try {
            wrongKeyDb = await sqlcipher.openDatabase(
              databasePath,
              password: 'plan-336-r1-deliberately-wrong-key',
              singleInstance: false,
            );
            await wrongKeyDb.query('messages');
          } finally {
            if (wrongKeyDb != null && wrongKeyDb.isOpen) {
              await wrongKeyDb.close();
            }
          }
        }(), throwsA(anything));

        proofStage = 'reopen-with-correct-key';
        db = await sqlcipher.openDatabase(
          databasePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _cipherVersion(db), isNotEmpty);

        proofStage = 'prove-parent-media-rollback';
        const rollbackMessageId = 'r1-rollback-parent';
        const rollbackAttachmentId = 'r1-rollback-attachment';
        final invalidAttachment = _mediaAttachmentRow(
          messageId: rollbackMessageId,
          attachmentId: rollbackAttachmentId,
        )..['mime'] = null;
        await expectLater(
          dbStageOutgoingOrdinaryAttemptWithMedia(
            db,
            expectedRow: null,
            stagedRow: _mediaParentRow(
              messageId: rollbackMessageId,
              envelope: 'r1-rollback-envelope',
            ),
            attachmentRows: <Map<String, Object?>>[invalidAttachment],
            kind: OutgoingOrdinaryAttemptKind.fresh,
          ),
          throwsA(anything),
        );
        expect(
          await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: const <Object?>[rollbackMessageId],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: const <Object?>[rollbackAttachmentId],
          ),
          isEmpty,
        );

        proofStage = 'stage-media-parent-and-projection';
        expect(
          await dbStageOutgoingOrdinaryAttemptWithMedia(
            db,
            expectedRow: null,
            stagedRow: _mediaParentRow(),
            attachmentRows: <Map<String, Object?>>[_mediaAttachmentRow()],
            kind: OutgoingOrdinaryAttemptKind.fresh,
          ),
          OutgoingOrdinaryMutationOutcome.applied,
        );
        expect(
          await _loadMessage(db, _mediaMessageId),
          allOf(
            containsPair('status', 'sending'),
            containsPair('wire_envelope', _mediaEnvelope),
            containsPair('transport', null),
          ),
        );
        expect(await _loadProofAttachments(db), hasLength(1));
        expect(
          (await _loadProofAttachments(db)).single,
          allOf(
            containsPair('message_id', _mediaMessageId),
            containsPair('owner_lane', MediaOwnerLane.direct.dbValue),
            containsPair('encryption_key_base64', startsWith('secure:')),
          ),
        );

        proofStage = 'commit-first-delivery-and-preserve-it';
        expect(
          await dbSettleOutgoingOrdinaryTransport(
            db,
            messageId: _mediaMessageId,
            expectedContactPeerId: _peerId,
            expectedEnvelope: _mediaEnvelope,
            status: 'delivered',
            transport: 'direct',
            relayExpiresAt: null,
            mode: OutgoingOrdinarySettlementMode.live,
          ),
          OutgoingOrdinaryMutationOutcome.applied,
        );
        final deliveredMediaParent = await _loadMessage(db, _mediaMessageId);
        expect(
          deliveredMediaParent,
          allOf(
            containsPair('status', 'delivered'),
            containsPair('transport', 'direct'),
            containsPair('wire_envelope', null),
            containsPair('relay_expires_at', null),
            containsPair('custody_checked_at', null),
          ),
        );
        expect(
          await dbSettleOutgoingOrdinaryTransport(
            db,
            messageId: _mediaMessageId,
            expectedContactPeerId: _peerId,
            expectedEnvelope: _mediaEnvelope,
            status: 'sent',
            transport: 'relay',
            relayExpiresAt: null,
            mode: OutgoingOrdinarySettlementMode.live,
          ),
          OutgoingOrdinaryMutationOutcome.preserved,
        );
        expect(await _loadMessage(db, _mediaMessageId), deliveredMediaParent);

        proofStage = 'stage-and-deliver-visible-tombstone';
        await db.insert(
          'messages',
          ConversationMessage(
            id: _tombstoneMessageId,
            contactPeerId: _peerId,
            senderPeerId: _selfPeerId,
            text: 'delete this payload',
            timestamp: _createdAt,
            status: 'delivered',
            isIncoming: false,
            createdAt: _createdAt,
            transport: 'direct',
            dedupKey: _tombstoneMessageId,
          ).toMap(),
        );
        final tombstoneExpected = await _loadMessage(db, _tombstoneMessageId);
        final tombstoneStage = Map<String, Object?>.from(tombstoneExpected)
          ..['text'] = ''
          ..['status'] = 'sending'
          ..['deleted_at'] = _deletedAt
          ..['deleted_by_peer_id'] = _selfPeerId
          ..['hidden_at'] = null
          ..['transport'] = null
          ..['wire_envelope'] = _tombstoneEnvelope
          ..['relay_expires_at'] = null
          ..['custody_checked_at'] = null;
        expect(
          await dbStageOutgoingOrdinaryAttempt(
            db,
            expectedRow: tombstoneExpected,
            stagedRow: tombstoneStage,
            kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
          ),
          OutgoingOrdinaryMutationOutcome.applied,
        );
        expect(
          await dbSettleOutgoingOrdinaryDeleteTombstone(
            db,
            messageId: _tombstoneMessageId,
            expectedContactPeerId: _peerId,
            expectedEnvelope: _tombstoneEnvelope,
            status: 'delivered',
            transport: 'direct',
            relayExpiresAt: null,
            mode: OutgoingOrdinarySettlementMode.live,
          ),
          OutgoingOrdinaryMutationOutcome.applied,
        );
        expect(
          await _loadMessage(db, _tombstoneMessageId),
          allOf(
            containsPair('text', ''),
            containsPair('status', 'delivered'),
            containsPair('deleted_at', _deletedAt),
            containsPair('deleted_by_peer_id', _selfPeerId),
            containsPair('hidden_at', _deletedAt),
            containsPair('wire_envelope', null),
          ),
        );

        final messagesBeforeReopen = await _loadProofMessages(db);
        final attachmentsBeforeReopen = await _loadProofAttachments(db);
        expect(messagesBeforeReopen, hasLength(2));
        expect(attachmentsBeforeReopen, hasLength(1));
        await db.close();
        db = null;

        proofStage = 'reopen-and-verify-exact-rows';
        db = await sqlcipher.openDatabase(
          databasePath,
          password: password,
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect(await _cipherVersion(db), isNotEmpty);
        expect(await _loadProofMessages(db), messagesBeforeReopen);
        expect(await _loadProofAttachments(db), attachmentsBeforeReopen);
        expect(
          await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: const <Object?>[rollbackMessageId],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: const <Object?>[rollbackAttachmentId],
          ),
          isEmpty,
        );
      } catch (error, stackTrace) {
        fail(
          'Plan 336 SQLCipher proof failed at $proofStage: $error\n$stackTrace',
        );
      } finally {
        flowEventLoggingEnabled = previousFlowEventLogging;
        if (db != null && db.isOpen) await db.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    },
  );
}
