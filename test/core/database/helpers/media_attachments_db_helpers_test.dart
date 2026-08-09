import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_inbox_custody_outbox_contract.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

/// One reviewed entry's ephemeral forward authorization token.
const _tc350ForwardToken = 'tc350-authorized-forward-token';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    // 228: build the CURRENT production schema through the shared registry —
    // the owner-lane tests need messages, group_messages and migration 096.
    await runProductionOnCreate(db, currentIdentityDatabaseVersion);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeAttachmentRow({
    String id = 'blob-001',
    String messageId = 'msg-001',
    String mime = 'image/jpeg',
    int size = 245000,
    String mediaType = 'image',
    int? width = 1920,
    int? height = 1080,
    int? durationMs,
    String? localPath,
    String downloadStatus = 'pending',
    String createdAt = '2026-02-20T10:00:00.000Z',
    String? contentHash,
    String? thumbnailHash,
    String? encryptionKeyBase64,
    String? encryptionNonce,
    String? encryptionScheme,
    String ownerLane = 'direct',
  }) {
    return {
      'id': id,
      'message_id': messageId,
      'owner_lane': ownerLane,
      'mime': mime,
      'size': size,
      'media_type': mediaType,
      'width': width,
      'height': height,
      'duration_ms': durationMs,
      'local_path': localPath,
      'download_status': downloadStatus,
      'created_at': createdAt,
      'content_hash': contentHash,
      'thumbnail_hash': thumbnailHash,
      'encryption_key_base64': encryptionKeyBase64,
      'encryption_nonce': encryptionNonce,
      'encryption_scheme': encryptionScheme,
    };
  }

  Map<String, Object?> makeMessageRow({
    required String id,
    String contactPeerId = 'contact-A',
    String senderPeerId = 'contact-A',
    String text = 'Hello',
    String timestamp = '2026-02-20T10:00:00.000Z',
    String status = 'delivered',
    int isIncoming = 1,
    String createdAt = '2026-02-20T10:00:01.000Z',
  }) {
    return {
      'id': id,
      'contact_peer_id': contactPeerId,
      'sender_peer_id': senderPeerId,
      'text': text,
      'timestamp': timestamp,
      'status': status,
      'is_incoming': isIncoming,
      'created_at': createdAt,
    };
  }

  group('dbInsertMediaAttachment', () {
    test('inserts a row successfully', () async {
      await dbInsertMediaAttachment(db, makeAttachmentRow());

      final rows = await db.query('media_attachments');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'blob-001');
      expect(rows[0]['mime'], 'image/jpeg');
      expect(rows[0]['size'], 245000);
    });

    test('replaces on conflict (same id)', () async {
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(downloadStatus: 'pending'),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(downloadStatus: 'done'),
      );

      final rows = await db.query('media_attachments');
      expect(rows.length, 1);
      expect(rows[0]['download_status'], 'done');
    });

    test('stores null optional fields correctly', () async {
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          width: null,
          height: null,
          durationMs: null,
          localPath: null,
        ),
      );

      final rows = await db.query('media_attachments');
      expect(rows[0]['width'], isNull);
      expect(rows[0]['height'], isNull);
      expect(rows[0]['duration_ms'], isNull);
      expect(rows[0]['local_path'], isNull);
    });
  });

  group('dbLoadMediaForMessage', () {
    test('returns empty list when no matches', () async {
      final rows = await dbLoadMediaForMessage(
        db,
        'nonexistent',
        ownerLane: 'direct',
      );
      expect(rows, isEmpty);
    });

    test('returns matching rows ordered by created_at', () async {
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-2',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-1',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(id: 'blob-3', messageId: 'msg-B'),
      );

      final rows = await dbLoadMediaForMessage(
        db,
        'msg-A',
        ownerLane: 'direct',
      );
      expect(rows.length, 2);
      expect(rows[0]['id'], 'blob-1');
      expect(rows[1]['id'], 'blob-2');
    });
  });

  group('dbLoadMediaForMessages', () {
    test('returns empty list for empty messageIds', () async {
      final rows = await dbLoadMediaForMessages(db, [], ownerLane: 'direct');
      expect(rows, isEmpty);
    });

    test('returns matching rows for multiple messages', () async {
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-1',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-2',
          messageId: 'msg-B',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-3',
          messageId: 'msg-C',
          createdAt: '2026-02-20T10:02:00.000Z',
        ),
      );

      final rows = await dbLoadMediaForMessages(db, [
        'msg-A',
        'msg-B',
      ], ownerLane: 'direct');
      expect(rows.length, 2);
      expect(rows[0]['id'], 'blob-1');
      expect(rows[1]['id'], 'blob-2');
    });

    test('returns all rows ordered by created_at', () async {
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-2',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-1',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );

      final rows = await dbLoadMediaForMessages(db, [
        'msg-A',
      ], ownerLane: 'direct');
      expect(rows.length, 2);
      expect(rows[0]['id'], 'blob-1');
      expect(rows[1]['id'], 'blob-2');
    });
  });

  group('dbUpdateMediaLocalPath', () {
    test('updates local_path and download_status', () async {
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          thumbnailHash:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          encryptionKeyBase64: 'key-1',
          encryptionNonce: 'nonce-1',
          encryptionScheme: 'blob_aes_256_gcm_v1',
        ),
      );

      await dbUpdateMediaLocalPath(db, 'blob-001', '/path/to/file.jpg', 'done');

      final rows = await db.query(
        'media_attachments',
        where: 'id = ?',
        whereArgs: ['blob-001'],
      );
      expect(rows[0]['local_path'], '/path/to/file.jpg');
      expect(rows[0]['download_status'], 'done');
      expect(
        rows[0]['content_hash'],
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(
        rows[0]['thumbnail_hash'],
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      expect(rows[0]['encryption_key_base64'], 'key-1');
      expect(rows[0]['encryption_nonce'], 'nonce-1');
      expect(rows[0]['encryption_scheme'], 'blob_aes_256_gcm_v1');
    });
  });

  group('dbUpdateMediaDownloadStatus', () {
    test('updates download_status only', () async {
      await dbInsertMediaAttachment(db, makeAttachmentRow());

      await dbUpdateMediaDownloadStatus(db, 'blob-001', 'downloading');

      final rows = await db.query(
        'media_attachments',
        where: 'id = ?',
        whereArgs: ['blob-001'],
      );
      expect(rows[0]['download_status'], 'downloading');
      expect(rows[0]['local_path'], isNull); // unchanged
    });

    test('transitions through all status values', () async {
      await dbInsertMediaAttachment(db, makeAttachmentRow());

      for (final status in ['downloading', 'done', 'failed', 'pending']) {
        await dbUpdateMediaDownloadStatus(db, 'blob-001', status);
        final rows = await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['blob-001'],
        );
        expect(rows[0]['download_status'], status);
      }
    });
  });

  group('dbDeleteMediaForMessage', () {
    test('deletes matching rows and returns count', () async {
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(id: 'blob-1', messageId: 'msg-A'),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(id: 'blob-2', messageId: 'msg-A'),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(id: 'blob-3', messageId: 'msg-B'),
      );

      final count = await dbDeleteMediaForMessage(
        db,
        'msg-A',
        ownerLane: 'direct',
      );
      expect(count, 2);

      final remaining = await db.query('media_attachments');
      expect(remaining.length, 1);
      expect(remaining[0]['id'], 'blob-3');
    });

    test('allows incoming protected direct attachment deletion', () async {
      await db.insert('messages', {
        ...makeMessageRow(id: 'msg-incoming-protected', isIncoming: 1),
        'private_media_policy_version': 1,
        'private_media_mode': 'protected',
        'private_media_state': 'available',
      });
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-incoming-protected',
          messageId: 'msg-incoming-protected',
          ownerLane: 'direct',
        ),
      );

      final count = await dbDeleteMediaForMessage(
        db,
        'msg-incoming-protected',
        ownerLane: 'direct',
      );

      expect(count, 1);
      expect(
        await dbLoadMediaForMessage(
          db,
          'msg-incoming-protected',
          ownerLane: 'direct',
        ),
        isEmpty,
      );
    });

    test('returns 0 when no matches', () async {
      final count = await dbDeleteMediaForMessage(
        db,
        'nonexistent',
        ownerLane: 'direct',
      );
      expect(count, 0);
    });
  });

  group('dbDeleteMediaForContact', () {
    test('deletes attachments for messages belonging to contact', () async {
      // Insert messages first
      await db.insert(
        'messages',
        makeMessageRow(id: 'msg-A', contactPeerId: 'contact-1'),
      );
      await db.insert(
        'messages',
        makeMessageRow(id: 'msg-B', contactPeerId: 'contact-2'),
      );

      // Insert attachments
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(id: 'blob-1', messageId: 'msg-A'),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(id: 'blob-2', messageId: 'msg-A'),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(id: 'blob-3', messageId: 'msg-B'),
      );

      final count = await dbDeleteMediaForContact(db, 'contact-1');
      expect(count, 2);

      final remaining = await db.query('media_attachments');
      expect(remaining.length, 1);
      expect(remaining[0]['id'], 'blob-3');
    });
  });

  group('dbLoadPendingMediaDownloads', () {
    test('returns only pending attachments', () async {
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-1',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-2',
          downloadStatus: 'done',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-3',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T10:02:00.000Z',
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'blob-4',
          downloadStatus: 'failed',
          createdAt: '2026-02-20T10:03:00.000Z',
        ),
      );

      final rows = await dbLoadPendingMediaDownloads(db);
      expect(rows.length, 2);
      expect(rows[0]['id'], 'blob-1');
      expect(rows[1]['id'], 'blob-3');
    });

    test('returns empty list when none pending', () async {
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(id: 'blob-1', downloadStatus: 'done'),
      );

      final rows = await dbLoadPendingMediaDownloads(db);
      expect(rows, isEmpty);
    });
  });

  // --- 228 TC-228-05: owner-lane isolation under parent-ID collision ---

  group('owner lane isolation', () {
    Future<void> seedCollisionParents(String id) async {
      await db.insert('groups', {
        'id': 'group-1',
        'name': 'Group One',
        'type': 'chat',
        'topic_name': 'group-one-topic',
        'created_at': '2026-02-20T09:00:00.000Z',
        'created_by': 'peer-g',
        'my_role': 'member',
        'self_removed_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('messages', makeMessageRow(id: id));
      await db.insert('group_messages', {
        'id': id,
        'group_id': 'group-1',
        'sender_peer_id': 'peer-g',
        'sender_username': 'GroupSender',
        'text': 'group parent $id',
        'timestamp': '2026-02-20T10:00:00.000Z',
        'key_generation': 0,
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': '2026-02-20T10:00:01.000Z',
      });
    }

    test('owner scoped load and delete isolate equal direct and group message '
        'ids', () async {
      // The SAME message id exists as a direct AND a group parent.
      await seedCollisionParents('msg-shared');
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'att-direct',
          messageId: 'msg-shared',
          ownerLane: MediaOwnerLane.direct.dbValue,
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'att-group',
          messageId: 'msg-shared',
          ownerLane: MediaOwnerLane.group.dbValue,
        ),
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'att-legacy',
          messageId: 'msg-shared',
          ownerLane: kMediaOwnerLaneUnresolved,
        ),
      );

      // Loads return only their lane — never the sibling or legacy row.
      final directRows = await dbLoadMediaForMessage(
        db,
        'msg-shared',
        ownerLane: 'direct',
      );
      expect(directRows.map((r) => r['id']), ['att-direct']);
      final groupRows = await dbLoadMediaForMessage(
        db,
        'msg-shared',
        ownerLane: 'group',
      );
      expect(groupRows.map((r) => r['id']), ['att-group']);
      final directMulti = await dbLoadMediaForMessages(db, [
        'msg-shared',
      ], ownerLane: 'direct');
      expect(directMulti.map((r) => r['id']), ['att-direct']);

      // Deleting the direct lane preserves group and unresolved rows.
      final directDeleted = await dbDeleteMediaForMessage(
        db,
        'msg-shared',
        ownerLane: 'direct',
      );
      expect(directDeleted, 1);
      var remaining = (await db.query(
        'media_attachments',
      )).map((r) => r['id']).toList();
      expect(remaining, containsAll(['att-group', 'att-legacy']));
      expect(remaining, isNot(contains('att-direct')));

      // Re-seed direct and delete the group lane: direct+legacy survive.
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'att-direct',
          messageId: 'msg-shared',
          ownerLane: 'direct',
        ),
      );
      final groupDeleted = await dbDeleteMediaForMessage(
        db,
        'msg-shared',
        ownerLane: 'group',
      );
      expect(groupDeleted, 1);
      remaining = (await db.query(
        'media_attachments',
      )).map((r) => r['id']).toList();
      expect(remaining, containsAll(['att-direct', 'att-legacy']));
      expect(remaining, isNot(contains('att-group')));
    });

    test(
      'contact cleanup removes only direct-owned rows for the contact',
      () async {
        await seedCollisionParents('msg-shared');
        await dbInsertMediaAttachment(
          db,
          makeAttachmentRow(
            id: 'att-direct',
            messageId: 'msg-shared',
            ownerLane: 'direct',
          ),
        );
        await dbInsertMediaAttachment(
          db,
          makeAttachmentRow(
            id: 'att-group',
            messageId: 'msg-shared',
            ownerLane: 'group',
          ),
        );
        await dbInsertMediaAttachment(
          db,
          makeAttachmentRow(
            id: 'att-legacy',
            messageId: 'msg-shared',
            ownerLane: kMediaOwnerLaneUnresolved,
          ),
        );

        // makeMessageRow defaults contact_peer_id to 'contact-A'.
        final count = await dbDeleteMediaForContact(db, 'contact-A');
        expect(count, 1);
        final remaining = (await db.query(
          'media_attachments',
        )).map((r) => r['id']).toList();
        expect(remaining, containsAll(['att-group', 'att-legacy']));
        expect(remaining, isNot(contains('att-direct')));
      },
    );

    test('upload pending load filters owner in SQL before the limit', () async {
      await seedCollisionParents('msg-shared');
      // Ten group upload-pending rows created BEFORE one direct row: an
      // after-limit filter of limit=5 would return zero direct rows.
      for (var i = 0; i < 10; i += 1) {
        await dbInsertMediaAttachment(
          db,
          makeAttachmentRow(
            id: 'att-g-$i',
            messageId: 'msg-shared',
            ownerLane: 'group',
            downloadStatus: 'upload_pending',
            createdAt: '2026-02-20T09:00:0$i.000Z',
          ),
        );
      }
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'att-d-late',
          messageId: 'msg-shared',
          ownerLane: 'direct',
          downloadStatus: 'upload_pending',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );

      final directPending = await dbLoadUploadPendingAttachments(
        db,
        limit: 5,
        ownerLane: 'direct',
      );
      expect(directPending.map((r) => r['id']), ['att-d-late']);

      final groupPending = await dbLoadUploadPendingAttachments(
        db,
        limit: 5,
        ownerLane: 'group',
      );
      expect(groupPending, hasLength(5));
      expect(groupPending.every((r) => r['owner_lane'] == 'group'), isTrue);

      // Owner-scoped terminalization flips only its lane.
      final flipped = await dbMarkUploadPendingAttachmentsFailedForMessage(
        db,
        'msg-shared',
        ownerLane: 'direct',
      );
      expect(flipped, 1);
      final groupStill = await dbLoadUploadPendingAttachments(
        db,
        limit: 50,
        ownerLane: 'group',
      );
      expect(groupStill, hasLength(10));
    });

    test('group upload retry excludes a self-removed parent', () async {
      await seedCollisionParents('active-message');
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'active-attachment',
          messageId: 'active-message',
          ownerLane: MediaOwnerLane.group.dbValue,
          downloadStatus: 'upload_pending',
        ),
      );

      await db.insert('groups', {
        'id': 'removed-group',
        'name': 'Removed Group',
        'type': 'chat',
        'topic_name': 'removed-group-topic',
        'created_at': '2026-02-20T09:00:00.000Z',
        'created_by': 'peer-g',
        'my_role': 'member',
        'self_removed_at': '2026-07-20T10:00:00.000Z',
      });
      await db.insert('group_messages', {
        'id': 'removed-message',
        'group_id': 'removed-group',
        'sender_peer_id': 'peer-g',
        'sender_username': 'GroupSender',
        'text': 'removed parent',
        'timestamp': '2026-02-20T10:00:00.000Z',
        'key_generation': 0,
        'status': 'failed',
        'is_incoming': 0,
        'created_at': '2026-02-20T10:00:01.000Z',
      });
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: 'removed-attachment',
          messageId: 'removed-message',
          ownerLane: MediaOwnerLane.group.dbValue,
          downloadStatus: 'upload_pending',
        ),
      );

      final pending = await dbLoadUploadPendingAttachments(
        db,
        ownerLane: MediaOwnerLane.group.dbValue,
      );
      expect(pending.map((row) => row['id']), ['active-attachment']);

      final projection = await dbProjectGroupUploadFailure(
        db,
        messageId: 'removed-message',
        attachmentId: 'removed-attachment',
        disposition: UploadMediaDisposition.boundedRetryable,
      );
      expect(projection.applied, isFalse);
      expect(
        (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['removed-attachment'],
        )).single['download_status'],
        'upload_pending',
      );
    });
  });

  group('fresh direct media blob generation authority', () {
    test(
      'TC-348-02a fresh blob owner is canonical all-or-none and exact-winner',
      () async {
        ({
          List<DirectMediaBlobCustodyRow> custody,
          List<Map<String, Object?>> expected,
          String hash,
          Map<String, Object?> parent,
          List<Map<String, Object?>> prepared,
        })
        candidate({
          required String suffix,
          required String recipientPeerId,
          String? messageIdOverride,
          String? attachmentIdOverride,
          String? dedupKeyOverride,
          String hashDigit = 'a',
        }) {
          final messageId = messageIdOverride ?? 'tc348-fresh-$suffix';
          final attachmentId =
              attachmentIdOverride ?? 'tc348-fresh-$suffix-attachment';
          const createdAt = '2026-08-08T15:00:00.000Z';
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: <String>[attachmentId],
          );
          final parent = ConversationMessage(
            id: messageId,
            contactPeerId: recipientPeerId,
            senderPeerId: 'tc348-local-peer',
            text: 'fresh external share',
            timestamp: createdAt,
            status: 'sending',
            isIncoming: false,
            createdAt: createdAt,
            directMediaCustodyIntentId: intent,
            dedupKey: dedupKeyOverride ?? messageId,
          ).toMap();
          final expected = makeAttachmentRow(
            id: attachmentId,
            messageId: messageId,
            size: 17,
            localPath: MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: 'image/jpeg',
            ),
            downloadStatus: 'upload_pending',
            createdAt: createdAt,
          );
          final hash = hashDigit * 64;
          final prepared = <String, Object?>{
            ...expected,
            'content_hash': hash,
            'encryption_key_base64': secureStoreReferenceForKey(
              mediaAttachmentEncryptionKeyStoreName(attachmentId),
            ),
            'encryption_nonce': 'nonce-$suffix-$hashDigit',
            'encryption_scheme': 'blob_aes_256_gcm_v1',
          };
          final custody = DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingPrepared,
            inboxCustodyIncarnationId: null,
            recipientPeerId: recipientPeerId,
            ciphertextRelativePath:
                'direct_media_blob_custody_v1/${'1' * 64}/$attachmentId.blob',
            contentHash: hash,
            ciphertextSize: 33,
            expiresAtMs: null,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: createdAt,
            updatedAt: createdAt,
          );
          return (
            custody: <DirectMediaBlobCustodyRow>[custody],
            expected: <Map<String, Object?>>[expected],
            hash: hash,
            parent: parent,
            prepared: <Map<String, Object?>>[prepared],
          );
        }

        Future<DirectMediaBlobGenerationDbStageResult> stage(
          ({
            List<DirectMediaBlobCustodyRow> custody,
            List<Map<String, Object?>> expected,
            String hash,
            Map<String, Object?> parent,
            List<Map<String, Object?>> prepared,
          })
          value,
        ) => dbStageFreshOutgoingDirectMediaBlobGeneration(
          db,
          parentRow: value.parent,
          expectedAttachmentRows: value.expected,
          preparedAttachmentRows: value.prepared,
          custodyRows: value.custody,
        );

        final winner = candidate(
          suffix: 'winner',
          recipientPeerId: 'tc348-recipient-winner',
        );
        final applied = await stage(winner);
        expect(
          applied.outcome,
          DirectMediaBlobGenerationDbStageOutcome.applied,
        );
        expect(applied.attachmentRows, hasLength(1));
        expect(applied.custodyRows, hasLength(1));
        expect(applied.attachmentRows.single['content_hash'], winner.hash);
        expect(
          await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[winner.parent['id']],
          ),
          hasLength(1),
        );
        expect(
          await db.query(
            'media_attachments',
            where: 'message_id = ?',
            whereArgs: <Object?>[winner.parent['id']],
          ),
          hasLength(1),
        );
        expect(
          await db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[winner.parent['id']],
          ),
          hasLength(1),
        );

        final losingCandidate = candidate(
          suffix: 'loser',
          recipientPeerId: 'tc348-recipient-winner',
          messageIdOverride: winner.parent['id']! as String,
          attachmentIdOverride: winner.expected.single['id']! as String,
          hashDigit: 'b',
        );
        final adopted = await stage(losingCandidate);
        expect(
          adopted.outcome,
          DirectMediaBlobGenerationDbStageOutcome.idempotent,
        );
        expect(adopted.attachmentRows.single['content_hash'], winner.hash);
        expect(
          adopted.custodyRows.single['content_hash'],
          winner.hash,
          reason: 'an idempotent caller receives only the exact DB winner',
        );

        final crossedRecipient = candidate(
          suffix: 'crossed-recipient',
          recipientPeerId: 'tc348-other-recipient',
          messageIdOverride: winner.parent['id']! as String,
          attachmentIdOverride: winner.expected.single['id']! as String,
          hashDigit: 'c',
        );
        expect(
          (await stage(crossedRecipient)).outcome,
          DirectMediaBlobGenerationDbStageOutcome.refused,
        );

        final partial = candidate(
          suffix: 'partial',
          recipientPeerId: 'tc348-recipient-partial',
        );
        await db.insert('messages', partial.parent);
        expect(
          (await stage(partial)).outcome,
          DirectMediaBlobGenerationDbStageOutcome.refused,
        );
        expect(
          await db.query(
            'media_attachments',
            where: 'message_id = ?',
            whereArgs: <Object?>[partial.parent['id']],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[partial.parent['id']],
          ),
          isEmpty,
        );

        final crossedLane = candidate(
          suffix: 'crossed-lane',
          recipientPeerId: 'tc348-recipient-crossed-lane',
        );
        await db.insert('media_attachments', <String, Object?>{
          ...crossedLane.expected.single,
          'owner_lane': MediaOwnerLane.group.dbValue,
        });
        expect(
          (await stage(crossedLane)).outcome,
          DirectMediaBlobGenerationDbStageOutcome.refused,
          reason:
              'a same-message attachment from another owner lane is a '
              'collision, not an absent fresh generation',
        );
        expect(
          await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[crossedLane.parent['id']],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[crossedLane.parent['id']],
          ),
          isEmpty,
        );

        final nonCanonical = candidate(
          suffix: 'non-canonical',
          recipientPeerId: 'tc348-recipient-non-canonical',
          dedupKeyOverride: 'wrong-dedup-key',
        );
        expect(
          (await stage(nonCanonical)).outcome,
          DirectMediaBlobGenerationDbStageOutcome.refused,
        );
        expect(
          await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[nonCanonical.parent['id']],
          ),
          isEmpty,
          reason: 'canonical validation must happen before the transaction',
        );
      },
    );

    test(
      'TC-350-02a fresh blob owner requires exact independent forward authorization',
      () async {
        ({
          List<DirectMediaBlobCustodyRow> custody,
          List<Map<String, Object?>> expected,
          String hash,
          Map<String, Object?> parent,
          List<Map<String, Object?>> prepared,
        })
        candidate({
          required String suffix,
          String? dedupKeyOverride,
          bool isForwarded = true,
          bool quoted = false,
          String hashDigit = 'a',
        }) {
          final messageId = 'tc350-fresh-$suffix';
          final attachmentId = 'tc350-fresh-$suffix-attachment';
          const createdAt = '2026-08-09T15:00:00.000Z';
          const recipientPeerId = 'tc350-recipient';
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: <String>[attachmentId],
          );
          final parent = ConversationMessage(
            id: messageId,
            contactPeerId: recipientPeerId,
            senderPeerId: 'tc350-local-peer',
            text: 'forwarded media',
            timestamp: createdAt,
            status: 'sending',
            isIncoming: false,
            createdAt: createdAt,
            directMediaCustodyIntentId: intent,
            dedupKey: dedupKeyOverride ?? _tc350ForwardToken,
            isForwarded: isForwarded,
            quotedMessageId: quoted ? 'tc350-quoted' : null,
          ).toMap();
          final expected = makeAttachmentRow(
            id: attachmentId,
            messageId: messageId,
            size: 17,
            localPath: MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: 'image/jpeg',
            ),
            downloadStatus: 'upload_pending',
            createdAt: createdAt,
          );
          final hash = hashDigit * 64;
          final prepared = <String, Object?>{
            ...expected,
            'content_hash': hash,
            'encryption_key_base64': secureStoreReferenceForKey(
              mediaAttachmentEncryptionKeyStoreName(attachmentId),
            ),
            'encryption_nonce': 'nonce-$suffix-$hashDigit',
            'encryption_scheme': 'blob_aes_256_gcm_v1',
          };
          final custody = DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingPrepared,
            inboxCustodyIncarnationId: null,
            recipientPeerId: recipientPeerId,
            ciphertextRelativePath:
                'direct_media_blob_custody_v1/${'1' * 64}/$attachmentId.blob',
            contentHash: hash,
            ciphertextSize: 33,
            expiresAtMs: null,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: createdAt,
            updatedAt: createdAt,
          );
          return (
            custody: <DirectMediaBlobCustodyRow>[custody],
            expected: <Map<String, Object?>>[expected],
            hash: hash,
            parent: parent,
            prepared: <Map<String, Object?>>[prepared],
          );
        }

        Future<DirectMediaBlobGenerationDbStageResult> stage(
          ({
            List<DirectMediaBlobCustodyRow> custody,
            List<Map<String, Object?>> expected,
            String hash,
            Map<String, Object?> parent,
            List<Map<String, Object?>> prepared,
          })
          value, {
          required String? authorizedForwardDedupKey,
        }) => dbStageFreshOutgoingDirectMediaBlobGeneration(
          db,
          parentRow: value.parent,
          expectedAttachmentRows: value.expected,
          preparedAttachmentRows: value.prepared,
          custodyRows: value.custody,
          authorizedForwardDedupKey: authorizedForwardDedupKey,
        );

        Future<void> expectNothingPersisted(
          Map<String, Object?> parentRow,
        ) async {
          final messageId = parentRow['id'];
          expect(
            await db.query(
              'messages',
              where: 'id = ?',
              whereArgs: <Object?>[messageId],
            ),
            isEmpty,
          );
          expect(
            await db.query(
              'media_attachments',
              where: 'message_id = ?',
              whereArgs: <Object?>[messageId],
            ),
            isEmpty,
          );
          expect(
            await db.query(
              kDirectMediaBlobCustodyTable,
              where: 'message_id = ?',
              whereArgs: <Object?>[messageId],
            ),
            isEmpty,
          );
        }

        // The exact authorized forwarded alternative applies atomically.
        final authorized = candidate(suffix: 'authorized');
        final applied = await stage(
          authorized,
          authorizedForwardDedupKey: _tc350ForwardToken,
        );
        expect(
          applied.outcome,
          DirectMediaBlobGenerationDbStageOutcome.applied,
        );
        expect(applied.attachmentRows, hasLength(1));
        expect(applied.custodyRows, hasLength(1));
        expect(
          (await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[authorized.parent['id']],
          )).single['dedup_key'],
          _tc350ForwardToken,
        );

        // …and re-adopts the exact winner idempotently.
        expect(
          (await stage(
            authorized,
            authorizedForwardDedupKey: _tc350ForwardToken,
          )).outcome,
          DirectMediaBlobGenerationDbStageOutcome.idempotent,
        );

        // Every crossed or unauthorized shape refuses atomically.
        final refusals =
            <
              String,
              ({
                Map<String, Object?> parent,
                Future<DirectMediaBlobGenerationDbStageResult> Function() run,
              })
            >{};
        final missingAuthorization = candidate(suffix: 'missing-auth');
        refusals['forwarded parent with no authorization'] = (
          parent: missingAuthorization.parent,
          run: () =>
              stage(missingAuthorization, authorizedForwardDedupKey: null),
        );
        final blankAuthorization = candidate(suffix: 'blank-auth');
        refusals['blank authorization token'] = (
          parent: blankAuthorization.parent,
          run: () => stage(blankAuthorization, authorizedForwardDedupKey: '  '),
        );
        final untrimmedAuthorization = candidate(
          suffix: 'untrimmed-auth',
          dedupKeyOverride: ' $_tc350ForwardToken ',
        );
        refusals['untrimmed authorization token'] = (
          parent: untrimmedAuthorization.parent,
          run: () => stage(
            untrimmedAuthorization,
            authorizedForwardDedupKey: ' $_tc350ForwardToken ',
          ),
        );
        final mismatched = candidate(suffix: 'mismatched');
        refusals['authorization that is not the parent dedup key'] = (
          parent: mismatched.parent,
          run: () =>
              stage(mismatched, authorizedForwardDedupKey: 'other-token-350'),
        );
        final notForwarded = candidate(
          suffix: 'not-forwarded',
          isForwarded: false,
        );
        refusals['authorized token on a non-forwarded parent'] = (
          parent: notForwarded.parent,
          run: () => stage(
            notForwarded,
            authorizedForwardDedupKey: _tc350ForwardToken,
          ),
        );
        final externalShapedForward = candidate(
          suffix: 'external-shaped',
          dedupKeyOverride: 'tc350-fresh-external-shaped',
        );
        refusals['external shape carrying a forwarded marker'] = (
          parent: externalShapedForward.parent,
          run: () =>
              stage(externalShapedForward, authorizedForwardDedupKey: null),
        );
        final quotedForward = candidate(suffix: 'quoted', quoted: true);
        refusals['authorized forward carrying quote state'] = (
          parent: quotedForward.parent,
          run: () => stage(
            quotedForward,
            authorizedForwardDedupKey: _tc350ForwardToken,
          ),
        );

        for (final entry in refusals.entries) {
          expect(
            (await entry.value.run()).outcome,
            DirectMediaBlobGenerationDbStageOutcome.refused,
            reason: entry.key,
          );
          await expectNothingPersisted(entry.value.parent);
        }

        // The exact external alternative still applies unchanged.
        final external = candidate(
          suffix: 'external-canonical',
          isForwarded: false,
          dedupKeyOverride: 'tc350-fresh-external-canonical',
        );
        expect(
          (await stage(external, authorizedForwardDedupKey: null)).outcome,
          DirectMediaBlobGenerationDbStageOutcome.applied,
        );

        // A committed exact winner is not adopted under another token.
        final crossedToken = candidate(
          suffix: 'authorized',
          dedupKeyOverride: 'tc350-other-token',
        );
        expect(
          (await stage(
            crossedToken,
            authorizedForwardDedupKey: 'tc350-other-token',
          )).outcome,
          DirectMediaBlobGenerationDbStageOutcome.refused,
          reason: 'a same-message winner under another token is not authority',
        );
        expect(
          (await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[authorized.parent['id']],
          )).single['dedup_key'],
          _tc350ForwardToken,
        );
      },
    );
  });

  group('direct media custody final authority gate', () {
    String envelope(String messageId, {String senderPeerId = 'peer-local'}) =>
        jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': messageId,
          'senderPeerId': senderPeerId,
          'encrypted': const <String, String>{
            'kem': 'kem-final-authority',
            'ciphertext': 'cipher-final-authority',
            'nonce': 'nonce-final-authority',
          },
        });

    Map<String, Object?> freshParent({
      required String messageId,
      required String recipientPeerId,
    }) {
      final wireEnvelope = envelope(messageId);
      return ConversationMessage(
        id: messageId,
        contactPeerId: recipientPeerId,
        senderPeerId: 'peer-local',
        text: 'fresh media',
        timestamp: '2026-08-07T14:30:00.000Z',
        status: 'sending',
        isIncoming: false,
        createdAt: '2026-08-07T14:30:00.000Z',
        wireEnvelope: wireEnvelope,
      ).toMap();
    }

    Map<String, Object?> completedAttachment({
      required String messageId,
      required String attachmentId,
      String mime = 'audio/mp4',
      String mediaType = 'audio',
      Object? width,
      Object? height,
      Object? durationMs = 800,
      Object? waveform = '[0.0,0.5,1.0]',
    }) => <String, Object?>{
      ...makeAttachmentRow(
        id: attachmentId,
        messageId: messageId,
        mime: mime,
        size: 800,
        mediaType: mediaType,
        width: null,
        height: null,
        durationMs: null,
        localPath: 'media/direct/$attachmentId.m4a',
        downloadStatus: 'done',
        contentHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        encryptionKeyBase64: secureStoreReferenceForKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        encryptionNonce: 'nonce-$attachmentId',
        encryptionScheme: 'blob_aes_256_gcm_v1',
      ),
      'width': width,
      'height': height,
      'duration_ms': durationMs,
      'waveform': waveform,
    };

    test(
      'TC-347-04 strict blob manifest binds and completes exact v108 atomically',
      () async {
        const nowMs = 1900000000000;

        Future<
          ({
            List<Map<String, Object?>> attachments,
            Map<String, Object?> expected,
            String intent,
            List<DirectMediaBlobManifestProjection> manifest,
            String messageId,
            String recipientPeerId,
            Map<String, Object?> staged,
            String wireEnvelope,
          })
        >
        seedStrictAttempt(String suffix) async {
          final messageId = 'tc347-manifest-$suffix';
          final recipientPeerId = 'tc347-recipient-$suffix';
          final attachmentIds = <String>['$messageId-a', '$messageId-b'];
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: attachmentIds,
          );
          final expectedParent = ConversationMessage(
            id: messageId,
            contactPeerId: recipientPeerId,
            senderPeerId: 'peer-local',
            text: 'strict manifest',
            timestamp: '2026-08-08T12:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-08-08T12:00:00.000Z',
            directMediaCustodyIntentId: intent,
          );
          final wireEnvelope = envelope(messageId);
          final stagedParent = expectedParent.copyWith(
            wireEnvelope: wireEnvelope,
            directMediaCustodyIntentId: null,
          );
          final attachments = <Map<String, Object?>>[];
          final manifest = <DirectMediaBlobManifestProjection>[];
          await db.insert('messages', expectedParent.toMap());
          for (var index = 0; index < attachmentIds.length; index++) {
            final attachmentId = attachmentIds[index];
            final contentHash = index == 0 ? '1' * 64 : '2' * 64;
            final ciphertextSize = 41 + index;
            final expiresAtMs = nowMs + 60000 + (index * 1000);
            final attachment = <String, Object?>{
              ...completedAttachment(
                messageId: messageId,
                attachmentId: attachmentId,
              ),
              'content_hash': contentHash,
            };
            attachments.add(attachment);
            await dbInsertMediaAttachment(db, attachment);
            final row = DirectMediaBlobCustodyRow(
              attachmentId: attachmentId,
              messageId: messageId,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingStored,
              inboxCustodyIncarnationId: null,
              recipientPeerId: recipientPeerId,
              ciphertextRelativePath:
                  'direct_media_blob_custody_v1/${'a' * 64}/$attachmentId.blob',
              contentHash: contentHash,
              ciphertextSize: ciphertextSize,
              expiresAtMs: expiresAtMs,
              custodyRelayPeerId: 'relay-$suffix-$index',
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: '2026-08-08T12:00:01.000Z',
              updatedAt: '2026-08-08T12:00:01.000Z',
            );
            await db.insert(kDirectMediaBlobCustodyTable, row.toMap());
            manifest.add(
              DirectMediaBlobManifestProjection(
                attachmentId: attachmentId,
                commitment: DirectMediaBlobCustodyCommitment(
                  contentHash: contentHash,
                  ciphertextSize: ciphertextSize,
                  expiresAtMs: expiresAtMs,
                ),
              ),
            );
          }
          return (
            attachments: attachments,
            expected: expectedParent.toMap(),
            intent: intent,
            manifest: manifest,
            messageId: messageId,
            recipientPeerId: recipientPeerId,
            staged: stagedParent.toMap(),
            wireEnvelope: wireEnvelope,
          );
        }

        Future<void> expectNoBinding(String messageId) async {
          expect(
            await db.query(
              'direct_inbox_custody_outbox',
              where: 'message_id = ?',
              whereArgs: <Object?>[messageId],
            ),
            isEmpty,
          );
          final rows = await db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          );
          expect(rows, hasLength(2));
          expect(
            rows.every((row) => row['inbox_custody_incarnation_id'] == null),
            isTrue,
          );
          expect(
            (await db.query(
              'messages',
              where: 'id = ?',
              whereArgs: <Object?>[messageId],
            )).single['direct_media_custody_intent_id'],
            isNotNull,
          );
        }

        final stripped = await seedStrictAttempt('stripped');
        final strippedResult = await dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: stripped.expected,
          stagedRow: stripped.staged,
          attachmentRows: stripped.attachments,
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: stripped.recipientPeerId,
          wireEnvelope: stripped.wireEnvelope,
          nowMs: nowMs,
        );
        expect(strippedResult.outcome, OutgoingOrdinaryMutationOutcome.refused);
        await expectNoBinding(stripped.messageId);

        final wrongSize = await seedStrictAttempt('wrong-size');
        final wrongSizeManifest = <DirectMediaBlobManifestProjection>[
          for (var index = 0; index < wrongSize.manifest.length; index++)
            DirectMediaBlobManifestProjection(
              attachmentId: wrongSize.manifest[index].attachmentId,
              commitment: DirectMediaBlobCustodyCommitment(
                contentHash: wrongSize.manifest[index].commitment.contentHash,
                ciphertextSize:
                    wrongSize.manifest[index].commitment.ciphertextSize +
                    (index == 0 ? 1 : 0),
                expiresAtMs: wrongSize.manifest[index].commitment.expiresAtMs,
              ),
            ),
        ];
        final wrongSizeResult = await dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: wrongSize.expected,
          stagedRow: wrongSize.staged,
          attachmentRows: wrongSize.attachments,
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: wrongSize.recipientPeerId,
          wireEnvelope: wrongSize.wireEnvelope,
          wireMediaBlobManifestHash: computeDirectMediaBlobManifestHash(
            wrongSizeManifest,
          ),
          wireMediaBlobExpiresAtMs: earliestDirectMediaBlobExpiryMs(
            wrongSizeManifest,
          ),
          nowMs: nowMs,
        );
        expect(
          wrongSizeResult.outcome,
          OutgoingOrdinaryMutationOutcome.refused,
        );
        await expectNoBinding(wrongSize.messageId);

        final wrongExpiry = await seedStrictAttempt('wrong-expiry');
        final wrongExpiryManifest = <DirectMediaBlobManifestProjection>[
          for (var index = 0; index < wrongExpiry.manifest.length; index++)
            DirectMediaBlobManifestProjection(
              attachmentId: wrongExpiry.manifest[index].attachmentId,
              commitment: DirectMediaBlobCustodyCommitment(
                contentHash: wrongExpiry.manifest[index].commitment.contentHash,
                ciphertextSize:
                    wrongExpiry.manifest[index].commitment.ciphertextSize,
                expiresAtMs:
                    wrongExpiry.manifest[index].commitment.expiresAtMs +
                    (index == 0 ? 1 : 0),
              ),
            ),
        ];
        final wrongExpiryResult = await dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: wrongExpiry.expected,
          stagedRow: wrongExpiry.staged,
          attachmentRows: wrongExpiry.attachments,
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: wrongExpiry.recipientPeerId,
          wireEnvelope: wrongExpiry.wireEnvelope,
          wireMediaBlobManifestHash: computeDirectMediaBlobManifestHash(
            wrongExpiryManifest,
          ),
          wireMediaBlobExpiresAtMs: earliestDirectMediaBlobExpiryMs(
            wrongExpiryManifest,
          ),
          nowMs: nowMs,
        );
        expect(
          wrongExpiryResult.outcome,
          OutgoingOrdinaryMutationOutcome.refused,
        );
        await expectNoBinding(wrongExpiry.messageId);

        final exact = await seedStrictAttempt('exact');
        final exactManifestHash = computeDirectMediaBlobManifestHash(
          exact.manifest,
        );
        final exactExpiry = earliestDirectMediaBlobExpiryMs(exact.manifest);
        final applied = await dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: exact.expected,
          stagedRow: exact.staged,
          attachmentRows: exact.attachments,
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: exact.recipientPeerId,
          wireEnvelope: exact.wireEnvelope,
          wireMediaBlobManifestHash: exactManifestHash,
          wireMediaBlobExpiresAtMs: exactExpiry,
          nowMs: nowMs,
        );
        expect(applied.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(applied.custodyRow, isNotNull);
        expect(
          applied.custodyRow!['media_blob_manifest_hash'],
          exactManifestHash,
        );
        expect(applied.custodyRow!['media_blob_expires_at_ms'], exactExpiry);
        expect(applied.custodyRow!['incarnation_id'], exact.intent);
        final boundRows = await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[exact.messageId],
        );
        expect(boundRows, hasLength(2));
        expect(
          boundRows.every(
            (row) => row['inbox_custody_incarnation_id'] == exact.intent,
          ),
          isTrue,
        );

        final completion = await dbCompleteAcceptedDirectInboxCustodyIfExact(
          db,
          recipientPeerId: exact.recipientPeerId,
          messageId: exact.messageId,
          expectedIncarnationId: exact.intent,
          expectedWireEnvelope: exact.wireEnvelope,
          relayExpiresAt: exactExpiry,
        );
        expect(completion, isNot(DirectInboxCustodyCompletionOutcome.stale));
        expect(
          await db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[exact.messageId],
          ),
          isEmpty,
        );
        final cleanupRows = await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[exact.messageId],
        );
        expect(
          cleanupRows.every(
            (row) =>
                row['state'] ==
                DirectMediaBlobCustodyState.outgoingCleanupPending.dbValue,
          ),
          isTrue,
        );
      },
    );

    test(
      'TC-347-09 stored v111 pending projection atomically binds v108',
      () async {
        const nowMs = 1900000000000;

        Future<
          ({
            List<String> attachmentIds,
            List<Map<String, Object?>> candidates,
            Map<String, Object?> expected,
            int expiresAtMs,
            String intent,
            String manifestHash,
            String messageId,
            String recipientPeerId,
            Map<String, Object?> staged,
            String wireEnvelope,
          })
        >
        seedStoredRestart(
          String suffix, {
          bool insertCustody = true,
          DirectMediaBlobCustodyState custodyState =
              DirectMediaBlobCustodyState.outgoingStored,
          bool persistedSiblingPath = false,
        }) async {
          final messageId = 'tc347-stored-restart-$suffix';
          final recipientPeerId = 'tc347-stored-peer-$suffix';
          final attachmentIds = <String>['$messageId-a', '$messageId-b'];
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: attachmentIds,
          );
          final expectedParent = ConversationMessage(
            id: messageId,
            contactPeerId: recipientPeerId,
            senderPeerId: 'peer-local',
            text: 'stored restart',
            timestamp: '2026-08-08T13:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-08-08T13:00:00.000Z',
            directMediaCustodyIntentId: intent,
          );
          final wireEnvelope = envelope(messageId);
          final stagedParent = expectedParent.copyWith(
            wireEnvelope: wireEnvelope,
            directMediaCustodyIntentId: null,
          );
          await db.insert('messages', expectedParent.toMap());

          final manifest = <DirectMediaBlobManifestProjection>[];
          for (var index = 0; index < attachmentIds.length; index++) {
            final attachmentId = attachmentIds[index];
            final contentHash = index == 0 ? '3' * 64 : '4' * 64;
            final expiry = nowMs + 90000 + (index * 1000);
            final canonicalPending =
                MediaFilePathConvention.relativePathForPendingUpload(
                  messageId: messageId,
                  attachmentId: attachmentId,
                  mime: 'audio/mp4',
                );
            final siblingPending =
                MediaFilePathConvention.relativePathForPendingUpload(
                  messageId: messageId,
                  attachmentId: attachmentIds[1],
                  mime: 'audio/mp4',
                );
            final persisted = <String, Object?>{
              ...completedAttachment(
                messageId: messageId,
                attachmentId: attachmentId,
              ),
              'local_path': persistedSiblingPath && index == 0
                  ? siblingPending
                  : canonicalPending,
              'download_status': 'upload_pending',
              'upload_retry_count': 2,
              'download_retry_count': 1,
              'content_hash': contentHash,
              'encryption_nonce': 'stored-nonce-$suffix-$index',
            };
            await dbInsertMediaAttachment(db, persisted);
            if (insertCustody) {
              final stored =
                  custodyState == DirectMediaBlobCustodyState.outgoingStored;
              final custody = DirectMediaBlobCustodyRow(
                attachmentId: attachmentId,
                messageId: messageId,
                direction: DirectMediaBlobCustodyDirection.outgoing,
                state: custodyState,
                inboxCustodyIncarnationId: null,
                recipientPeerId: recipientPeerId,
                ciphertextRelativePath:
                    'direct_media_blob_custody_v1/${'b' * 64}/$attachmentId.blob',
                contentHash: contentHash,
                ciphertextSize: 81 + index,
                expiresAtMs: stored ? expiry : null,
                custodyRelayPeerId: stored ? 'relay-$suffix-$index' : null,
                lastAttemptAt: null,
                nextAttemptAt: null,
                createdAt: '2026-08-08T13:00:01.000Z',
                updatedAt: '2026-08-08T13:00:01.000Z',
              );
              await db.insert(kDirectMediaBlobCustodyTable, custody.toMap());
            }
            manifest.add(
              DirectMediaBlobManifestProjection(
                attachmentId: attachmentId,
                commitment: DirectMediaBlobCustodyCommitment(
                  contentHash: contentHash,
                  ciphertextSize: 81 + index,
                  expiresAtMs: expiry,
                ),
              ),
            );
          }

          final persistedRows = await db.rawQuery(
            'SELECT * FROM media_attachments WHERE message_id = ? '
            'AND owner_lane = ? ORDER BY id',
            <Object?>[messageId, MediaOwnerLane.direct.dbValue],
          );
          final candidates = persistedRows
              .map((row) {
                final candidate = Map<String, Object?>.from(row)
                  ..['download_status'] = 'done';
                candidate['local_path'] =
                    MediaFilePathConvention.relativePathForPendingUpload(
                      messageId: messageId,
                      attachmentId: candidate['id']! as String,
                      mime: candidate['mime']! as String,
                    );
                return candidate;
              })
              .toList(growable: false);
          return (
            attachmentIds: attachmentIds,
            candidates: candidates,
            expected: expectedParent.toMap(),
            expiresAtMs: earliestDirectMediaBlobExpiryMs(manifest),
            intent: intent,
            manifestHash: computeDirectMediaBlobManifestHash(manifest),
            messageId: messageId,
            recipientPeerId: recipientPeerId,
            staged: stagedParent.toMap(),
            wireEnvelope: wireEnvelope,
          );
        }

        Future<Map<String, Object?>> snapshot(String messageId) async =>
            <String, Object?>{
              'parent': await db.query(
                'messages',
                where: 'id = ?',
                whereArgs: <Object?>[messageId],
              ),
              'attachments': await db.rawQuery(
                'SELECT * FROM media_attachments WHERE message_id = ? '
                'ORDER BY id',
                <Object?>[messageId],
              ),
              'blobCustody': await db.rawQuery(
                'SELECT * FROM $kDirectMediaBlobCustodyTable '
                'WHERE message_id = ? ORDER BY attachment_id',
                <Object?>[messageId],
              ),
              'inboxCustody': await db.rawQuery(
                'SELECT * FROM direct_inbox_custody_outbox '
                'WHERE message_id = ? ORDER BY recipient_peer_id',
                <Object?>[messageId],
              ),
            };

        Future<void> expectAtomicRefusal(
          ({
            List<String> attachmentIds,
            List<Map<String, Object?>> candidates,
            Map<String, Object?> expected,
            int expiresAtMs,
            String intent,
            String manifestHash,
            String messageId,
            String recipientPeerId,
            Map<String, Object?> staged,
            String wireEnvelope,
          })
          seeded, {
          List<Map<String, Object?>>? candidates,
          String? manifestHash,
          int? expiresAtMs,
        }) async {
          final before = await snapshot(seeded.messageId);
          final result = await dbStageOutgoingDirectMediaInboxCustody(
            db,
            expectedRow: seeded.expected,
            stagedRow: seeded.staged,
            attachmentRows: candidates ?? seeded.candidates,
            kind: OutgoingOrdinaryAttemptKind.existing,
            recipientPeerId: seeded.recipientPeerId,
            wireEnvelope: seeded.wireEnvelope,
            wireMediaBlobManifestHash: manifestHash ?? seeded.manifestHash,
            wireMediaBlobExpiresAtMs: expiresAtMs ?? seeded.expiresAtMs,
            nowMs: nowMs,
          );
          expect(result.outcome, OutgoingOrdinaryMutationOutcome.refused);
          expect(await snapshot(seeded.messageId), before);
        }

        await expectAtomicRefusal(
          await seedStoredRestart('absent-v111', insertCustody: false),
        );
        await expectAtomicRefusal(
          await seedStoredRestart(
            'outgoing-prepared',
            custodyState: DirectMediaBlobCustodyState.outgoingPrepared,
          ),
        );
        await expectAtomicRefusal(
          await seedStoredRestart(
            'persisted-sibling-path',
            persistedSiblingPath: true,
          ),
        );

        final siblingCandidate = await seedStoredRestart(
          'candidate-sibling-path',
        );
        final siblingCandidates = siblingCandidate.candidates
            .map(Map<String, Object?>.from)
            .toList(growable: false);
        siblingCandidates.first['local_path'] =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: siblingCandidate.messageId,
              attachmentId: siblingCandidate.attachmentIds.last,
              mime: siblingCandidates.first['mime']! as String,
            );
        await expectAtomicRefusal(
          siblingCandidate,
          candidates: siblingCandidates,
        );

        final crossedNonce = await seedStoredRestart('crossed-nonce');
        final crossedNonceCandidates = crossedNonce.candidates
            .map(Map<String, Object?>.from)
            .toList(growable: false);
        crossedNonceCandidates.first['encryption_nonce'] = 'crossed-nonce';
        await expectAtomicRefusal(
          crossedNonce,
          candidates: crossedNonceCandidates,
        );

        final crossedHash = await seedStoredRestart('crossed-hash');
        final crossedHashCandidates = crossedHash.candidates
            .map(Map<String, Object?>.from)
            .toList(growable: false);
        crossedHashCandidates.first['content_hash'] = '5' * 64;
        await expectAtomicRefusal(
          crossedHash,
          candidates: crossedHashCandidates,
        );

        final crossedRetry = await seedStoredRestart('crossed-retry');
        final crossedRetryCandidates = crossedRetry.candidates
            .map(Map<String, Object?>.from)
            .toList(growable: false);
        crossedRetryCandidates.first['upload_retry_count'] = 3;
        await expectAtomicRefusal(
          crossedRetry,
          candidates: crossedRetryCandidates,
        );

        final wrongManifest = await seedStoredRestart('wrong-manifest');
        final replacementPrefix = wrongManifest.manifestHash.startsWith('0')
            ? '1'
            : '0';
        await expectAtomicRefusal(
          wrongManifest,
          manifestHash:
              '$replacementPrefix${wrongManifest.manifestHash.substring(1)}',
        );

        final wrongExpiry = await seedStoredRestart('wrong-expiry');
        await expectAtomicRefusal(
          wrongExpiry,
          expiresAtMs: wrongExpiry.expiresAtMs + 1,
        );

        final exact = await seedStoredRestart('exact');
        final applied = await dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: exact.expected,
          stagedRow: exact.staged,
          attachmentRows: exact.candidates,
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: exact.recipientPeerId,
          wireEnvelope: exact.wireEnvelope,
          wireMediaBlobManifestHash: exact.manifestHash,
          wireMediaBlobExpiresAtMs: exact.expiresAtMs,
          nowMs: nowMs,
        );
        expect(applied.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(applied.custodyRow?['incarnation_id'], exact.intent);
        expect(
          applied.custodyRow?['media_blob_manifest_hash'],
          exact.manifestHash,
        );
        expect(
          applied.custodyRow?['media_blob_expires_at_ms'],
          exact.expiresAtMs,
        );

        final committedAttachments = await db.rawQuery(
          'SELECT * FROM media_attachments WHERE message_id = ? ORDER BY id',
          <Object?>[exact.messageId],
        );
        expect(committedAttachments, hasLength(exact.attachmentIds.length));
        for (final row in committedAttachments) {
          expect(row['download_status'], 'done');
          expect(
            row['local_path'],
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: exact.messageId,
              attachmentId: row['id']! as String,
              mime: row['mime']! as String,
            ),
          );
          expect(row['upload_retry_count'], 2);
          expect(row['download_retry_count'], 1);
        }
        final boundRows = await db.rawQuery(
          'SELECT * FROM $kDirectMediaBlobCustodyTable '
          'WHERE message_id = ? ORDER BY attachment_id',
          <Object?>[exact.messageId],
        );
        expect(boundRows, hasLength(exact.attachmentIds.length));
        expect(
          boundRows.every(
            (row) => row['inbox_custody_incarnation_id'] == exact.intent,
          ),
          isTrue,
        );
      },
    );

    test(
      'TC-345 final DB authority rejects MIME/type, negative dimensions, and malformed waveform metadata',
      () async {
        const messageId = 'tc345-final-metadata-gate';
        const attachmentId = 'tc345-final-metadata-attachment';
        final parent = freshParent(
          messageId: messageId,
          recipientPeerId: 'peer-metadata',
        );
        final valid = completedAttachment(
          messageId: messageId,
          attachmentId: attachmentId,
        );
        final malformed = <Map<String, Object?>>[
          <String, Object?>{...valid, 'media_type': 'video'},
          <String, Object?>{...valid, 'size': 1.5},
          <String, Object?>{...valid, 'width': -1},
          <String, Object?>{...valid, 'height': -1},
          <String, Object?>{...valid, 'duration_ms': -1},
          <String, Object?>{...valid, 'waveform': '{"sample":0.5}'},
          <String, Object?>{...valid, 'waveform': '[0.0,1.01]'},
          <String, Object?>{...valid, 'waveform': '[0.0,"bad"]'},
          <String, Object?>{
            ...valid,
            'encryption_key_base64': secureStoreReferenceForKey(
              mediaAttachmentEncryptionKeyStoreName('attacker-selected'),
            ),
          },
        ];

        for (final candidate in malformed) {
          final result = await dbStageOutgoingDirectMediaInboxCustody(
            db,
            expectedRow: null,
            stagedRow: parent,
            attachmentRows: <Map<String, Object?>>[candidate],
            kind: OutgoingOrdinaryAttemptKind.fresh,
            recipientPeerId: 'peer-metadata',
            wireEnvelope: parent['wire_envelope']! as String,
          );
          expect(result.outcome, OutgoingOrdinaryMutationOutcome.refused);
        }
        expect(
          await db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            'media_attachments',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          isEmpty,
        );

        final accepted = await dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: null,
          stagedRow: parent,
          attachmentRows: <Map<String, Object?>>[valid],
          kind: OutgoingOrdinaryAttemptKind.fresh,
          recipientPeerId: 'peer-metadata',
          wireEnvelope: parent['wire_envelope']! as String,
        );
        expect(accepted.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(accepted.hasExactMutableProjection, isTrue);
      },
    );

    test(
      'TC-345 marker-free fresh cannot reuse an outbox-only message ID under another recipient',
      () async {
        const messageId = 'tc345-fresh-cross-recipient';
        const firstAttachmentId = 'tc345-fresh-peer-a-attachment';
        final peerAParent = freshParent(
          messageId: messageId,
          recipientPeerId: 'peer-a',
        );
        final peerA = await dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: null,
          stagedRow: peerAParent,
          attachmentRows: <Map<String, Object?>>[
            completedAttachment(
              messageId: messageId,
              attachmentId: firstAttachmentId,
            ),
          ],
          kind: OutgoingOrdinaryAttemptKind.fresh,
          recipientPeerId: 'peer-a',
          wireEnvelope: peerAParent['wire_envelope']! as String,
        );
        expect(peerA.outcome, OutgoingOrdinaryMutationOutcome.applied);
        final authorityBefore = (await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
        )).single;

        await db.delete(
          'media_attachments',
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
        );
        await db.delete(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        );

        const secondAttachmentId = 'tc345-fresh-peer-b-attachment';
        final peerBParent = freshParent(
          messageId: messageId,
          recipientPeerId: 'peer-b',
        );
        final peerB = await dbStageOutgoingDirectMediaInboxCustody(
          db,
          expectedRow: null,
          stagedRow: peerBParent,
          attachmentRows: <Map<String, Object?>>[
            completedAttachment(
              messageId: messageId,
              attachmentId: secondAttachmentId,
            ),
          ],
          kind: OutgoingOrdinaryAttemptKind.fresh,
          recipientPeerId: 'peer-b',
          wireEnvelope: peerBParent['wire_envelope']! as String,
        );

        expect(peerB.outcome, OutgoingOrdinaryMutationOutcome.refused);
        expect(
          await db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          <Map<String, Object?>>[authorityBefore],
        );
        expect(await db.query('messages'), isEmpty);
        expect(await db.query('media_attachments'), isEmpty);
      },
    );

    test(
      'TC-345-07f manifest-bound failure projection is atomic and refuses crossed authority',
      () async {
        Future<
          ({
            Map<String, Object?> parent,
            List<Map<String, Object?>> attachments,
            String failedAttachmentId,
            String intent,
          })
        >
        seedPrepared(String suffix) async {
          final messageId = 'tc345-failure-$suffix';
          final failedAttachmentId = 'tc345-failure-$suffix-a';
          final siblingAttachmentId = 'tc345-failure-$suffix-b';
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: <String>[failedAttachmentId, siblingAttachmentId],
          );
          final parent = ConversationMessage(
            id: messageId,
            contactPeerId: 'peer-failure-$suffix',
            senderPeerId: 'peer-local',
            text: 'prepared media',
            timestamp: '2026-08-07T15:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-08-07T15:00:00.000Z',
            directMediaCustodyIntentId: intent,
          ).toMap();
          await db.insert('messages', parent);
          for (final attachmentId in <String>[
            failedAttachmentId,
            siblingAttachmentId,
          ]) {
            await dbInsertMediaAttachment(
              db,
              makeAttachmentRow(
                id: attachmentId,
                messageId: messageId,
                mime: 'audio/mp4',
                mediaType: 'audio',
                durationMs: 800,
                localPath: MediaFilePathConvention.relativePathForPendingUpload(
                  messageId: messageId,
                  attachmentId: attachmentId,
                  mime: 'audio/mp4',
                ),
                downloadStatus: 'upload_pending',
              ),
            );
          }
          return (
            parent: Map<String, Object?>.from(
              (await db.query(
                'messages',
                where: 'id = ?',
                whereArgs: <Object?>[messageId],
              )).single,
            ),
            attachments: (await db.rawQuery(
              'SELECT * FROM media_attachments WHERE message_id = ? '
              'AND owner_lane = ? ORDER BY id',
              <Object?>[messageId, MediaOwnerLane.direct.dbValue],
            )).map(Map<String, Object?>.from).toList(growable: false),
            failedAttachmentId: failedAttachmentId,
            intent: intent,
          );
        }

        Future<Map<String, Object?>> snapshot(String messageId) async =>
            <String, Object?>{
              'parent': await db.query(
                'messages',
                where: 'id = ?',
                whereArgs: <Object?>[messageId],
              ),
              'attachments': await db.rawQuery(
                'SELECT * FROM media_attachments WHERE message_id = ? '
                'ORDER BY id',
                <Object?>[messageId],
              ),
              'custody': await db.rawQuery(
                'SELECT * FROM direct_inbox_custody_outbox '
                'WHERE message_id = ? ORDER BY recipient_peer_id',
                <Object?>[messageId],
              ),
            };

        for (final variant in <String>[
          'parent-deleted',
          'attachment-deleted',
          'metadata-crossed',
          'contact-crossed',
          'token-crossed',
          'v108-owned',
        ]) {
          final seeded = await seedPrepared(variant);
          final messageId = seeded.parent['id']! as String;
          switch (variant) {
            case 'parent-deleted':
              await db.delete(
                'messages',
                where: 'id = ?',
                whereArgs: <Object?>[messageId],
              );
              break;
            case 'attachment-deleted':
              await db.delete(
                'media_attachments',
                where: 'id = ?',
                whereArgs: <Object?>[seeded.failedAttachmentId],
              );
              break;
            case 'metadata-crossed':
              await db.update(
                'media_attachments',
                <String, Object?>{'duration_ms': 801},
                where: 'id = ?',
                whereArgs: <Object?>[seeded.failedAttachmentId],
              );
              break;
            case 'contact-crossed':
              await db.update(
                'messages',
                <String, Object?>{'contact_peer_id': 'peer-crossed'},
                where: 'id = ?',
                whereArgs: <Object?>[messageId],
              );
              break;
            case 'token-crossed':
              await db.update(
                'messages',
                <String, Object?>{
                  'direct_media_custody_intent_id':
                      'ffffffffffffffffffffffffffffffff',
                },
                where: 'id = ?',
                whereArgs: <Object?>[messageId],
              );
              break;
            case 'v108-owned':
              await db.insert('direct_inbox_custody_outbox', <String, Object?>{
                'recipient_peer_id': 'peer-crossed-owner',
                'message_id': messageId,
                'incarnation_id': seeded.intent,
                'wire_envelope': '{"owned":true}',
                'retry_count': 0,
                'last_attempt_at': null,
                'last_error_code': null,
                'created_at': '2026-08-07T15:01:00.000Z',
                'updated_at': '2026-08-07T15:01:00.000Z',
              });
              break;
          }

          final crossed = await snapshot(messageId);
          final result = await dbProjectOutgoingDirectMediaCustodyUploadFailure(
            db,
            expectedParentRow: seeded.parent,
            expectedAttachmentRows: seeded.attachments,
            failedAttachmentId: seeded.failedAttachmentId,
            disposition: UploadMediaDisposition.terminal,
          );
          expect(result.applied, isFalse, reason: variant);
          expect(await snapshot(messageId), crossed, reason: variant);
        }

        final valid = await seedPrepared('valid');
        final validMessageId = valid.parent['id']! as String;
        await db.update(
          'media_attachments',
          <String, Object?>{'upload_retry_count': kMaxUploadRetries - 1},
          where: 'id = ?',
          whereArgs: <Object?>[valid.failedAttachmentId],
        );
        final exactParent = Map<String, Object?>.from(
          (await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[validMessageId],
          )).single,
        );
        final exactAttachments = (await db.rawQuery(
          'SELECT * FROM media_attachments WHERE message_id = ? '
          'AND owner_lane = ? ORDER BY id',
          <Object?>[validMessageId, MediaOwnerLane.direct.dbValue],
        )).map(Map<String, Object?>.from).toList(growable: false);

        final applied = await dbProjectOutgoingDirectMediaCustodyUploadFailure(
          db,
          expectedParentRow: exactParent,
          expectedAttachmentRows: exactAttachments,
          failedAttachmentId: valid.failedAttachmentId,
          disposition: UploadMediaDisposition.boundedRetryable,
        );
        expect(applied.state, UploadRetryProjectionState.terminal);
        expect(applied.uploadRetryCount, kMaxUploadRetries);
        final committedParent = (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[validMessageId],
        )).single;
        expect(committedParent['status'], 'failed');
        expect(committedParent['direct_media_custody_intent_id'], valid.intent);
        final committedAttachments = await db.rawQuery(
          'SELECT * FROM media_attachments WHERE message_id = ? ORDER BY id',
          <Object?>[validMessageId],
        );
        final committedFailed = committedAttachments.singleWhere(
          (row) => row['id'] == valid.failedAttachmentId,
        );
        final committedSibling = committedAttachments.singleWhere(
          (row) => row['id'] != valid.failedAttachmentId,
        );
        expect(committedFailed['download_status'], 'upload_failed');
        expect(committedFailed['upload_retry_count'], kMaxUploadRetries);
        expect(committedSibling, exactAttachments.last);
        expect(
          await db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[validMessageId],
          ),
          isEmpty,
        );
      },
    );
  });

  group('removed membership retry completion CAS', () {
    Future<void> seedGroup(String groupId) => db.insert('groups', {
      'id': groupId,
      'name': 'Retry CAS Group',
      'type': 'chat',
      'topic_name': 'topic-$groupId',
      'created_at': '2026-07-20T09:00:00.000Z',
      'created_by': 'peer-self',
      'my_role': 'member',
      'self_removed_at': null,
    });

    Future<void> seedOutgoingParent({
      required String messageId,
      required String groupId,
      required String status,
      String? retryPayload,
    }) => db.insert('group_messages', {
      'id': messageId,
      'group_id': groupId,
      'sender_peer_id': 'peer-self',
      'sender_username': 'Self',
      'text': 'retry authority',
      'timestamp': '2026-07-20T10:00:00.000Z',
      'last_send_attempt_at': '2026-07-20T10:00:01.000Z',
      'key_generation': 1,
      'status': status,
      'is_incoming': 0,
      'created_at': '2026-07-20T10:00:00.000Z',
      'wire_envelope': '{"wire":true}',
      'inbox_stored': 0,
      'inbox_retry_payload': retryPayload,
    });

    test(
      'guarded incoming group media refuses a retained parent under a marked shell',
      () async {
        const groupId = 'marked-media-parent-group';
        const messageId = 'marked-media-parent-message';
        const attachmentId = 'marked-media-parent-attachment';
        await seedGroup(groupId);
        await db.insert('group_messages', {
          'id': messageId,
          'group_id': groupId,
          'sender_peer_id': 'peer-member',
          'sender_username': 'Member',
          'text': 'retained history',
          'timestamp': '2026-07-20T10:00:00.000Z',
          'key_generation': 1,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-07-20T10:00:00.000Z',
        });
        await db.update(
          'groups',
          {'self_removed_at': '2026-07-20T10:01:00.000Z'},
          where: 'id = ?',
          whereArgs: [groupId],
        );

        expect(
          await dbSaveGroupMediaAttachmentGuarded(
            db,
            makeAttachmentRow(
              id: attachmentId,
              messageId: messageId,
              ownerLane: MediaOwnerLane.group.dbValue,
            ),
            groupId: groupId,
          ),
          isFalse,
        );
        expect(
          await db.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: [attachmentId],
          ),
          isEmpty,
        );
      },
    );

    test('exact live inbox and attachment completions commit once', () async {
      const groupId = 'live-cas-group';
      const inboxMessageId = 'live-inbox-cas-message';
      const uploadMessageId = 'live-upload-cas-message';
      const attachmentId = 'live-upload-cas-attachment';
      await seedGroup(groupId);
      await seedOutgoingParent(
        messageId: inboxMessageId,
        groupId: groupId,
        status: 'sent',
        retryPayload: '{"groupId":"live-cas-group"}',
      );
      final inboxExpected = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: [inboxMessageId],
      )).single;
      expect(await dbCompleteGroupInboxStoreRetry(db, inboxExpected), isTrue);
      expect(await dbCompleteGroupInboxStoreRetry(db, inboxExpected), isFalse);

      await seedOutgoingParent(
        messageId: uploadMessageId,
        groupId: groupId,
        status: 'failed',
        retryPayload: '{"groupId":"live-cas-group"}',
      );
      await dbInsertMediaAttachment(
        db,
        makeAttachmentRow(
          id: attachmentId,
          messageId: uploadMessageId,
          ownerLane: MediaOwnerLane.group.dbValue,
          localPath: 'pending_uploads/live-cas/file.jpg',
          downloadStatus: 'upload_pending',
        ),
      );
      final uploadParent = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: [uploadMessageId],
      )).single;
      final uploadExpected = (await db.query(
        'media_attachments',
        where: 'id = ?',
        whereArgs: [attachmentId],
      )).single;
      final uploadCompleted = <String, Object?>{
        ...uploadExpected,
        'download_status': 'done',
        'content_hash': List<String>.filled(64, 'b').join(),
      };
      expect(
        await dbCompleteGroupUploadRetry(
          db,
          expectedParent: uploadParent,
          expectedAttachment: uploadExpected,
          completedAttachment: uploadCompleted,
        ),
        isTrue,
      );
      expect(
        await dbCompleteGroupUploadRetry(
          db,
          expectedParent: uploadParent,
          expectedAttachment: uploadExpected,
          completedAttachment: uploadCompleted,
        ),
        isFalse,
      );
    });

    test(
      'late inbox completion cannot overwrite B3 terminal tuple after reaccept',
      () async {
        const groupId = 'inbox-cas-group';
        const messageId = 'inbox-cas-message';
        await seedGroup(groupId);
        await seedOutgoingParent(
          messageId: messageId,
          groupId: groupId,
          status: 'sent',
          retryPayload: '{"groupId":"inbox-cas-group"}',
        );
        final expected = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: [messageId],
        )).single;

        await db.update(
          'groups',
          {'self_removed_at': '2026-07-20T10:01:00.000Z'},
          where: 'id = ?',
          whereArgs: [groupId],
        );
        await db.update(
          'group_messages',
          {
            'status': 'send_failed',
            'wire_envelope': null,
            'inbox_retry_payload': null,
            'next_eligible_at': null,
          },
          where: 'id = ?',
          whereArgs: [messageId],
        );
        await db.update(
          'groups',
          {'self_removed_at': null},
          where: 'id = ?',
          whereArgs: [groupId],
        );

        expect(await dbCompleteGroupInboxStoreRetry(db, expected), isFalse);
        final after = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: [messageId],
        )).single;
        expect(after['status'], 'send_failed');
        expect(after['wire_envelope'], isNull);
        expect(after['inbox_retry_payload'], isNull);
        expect(after['inbox_stored'], 0);
      },
    );

    test(
      'late attachment completion cannot overwrite B3 upload failure after reaccept',
      () async {
        const groupId = 'upload-cas-group';
        const messageId = 'upload-cas-message';
        const attachmentId = 'upload-cas-attachment';
        await seedGroup(groupId);
        await seedOutgoingParent(
          messageId: messageId,
          groupId: groupId,
          status: 'failed',
          retryPayload: '{"groupId":"upload-cas-group"}',
        );
        await dbInsertMediaAttachment(
          db,
          makeAttachmentRow(
            id: attachmentId,
            messageId: messageId,
            ownerLane: MediaOwnerLane.group.dbValue,
            localPath: 'pending_uploads/upload-cas/file.jpg',
            downloadStatus: 'upload_pending',
          ),
        );
        final expectedParent = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: [messageId],
        )).single;
        final expectedAttachment = (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: [attachmentId],
        )).single;
        final completedAttachment = <String, Object?>{
          ...expectedAttachment,
          'download_status': 'done',
          'content_hash': List<String>.filled(64, 'a').join(),
        };

        await db.update(
          'groups',
          {'self_removed_at': '2026-07-20T10:01:00.000Z'},
          where: 'id = ?',
          whereArgs: [groupId],
        );
        await db.update(
          'group_messages',
          {
            'status': 'send_failed',
            'wire_envelope': null,
            'inbox_retry_payload': null,
            'next_eligible_at': null,
          },
          where: 'id = ?',
          whereArgs: [messageId],
        );
        await db.update(
          'media_attachments',
          {'download_status': 'upload_failed'},
          where: 'id = ?',
          whereArgs: [attachmentId],
        );
        await db.update(
          'groups',
          {'self_removed_at': null},
          where: 'id = ?',
          whereArgs: [groupId],
        );

        expect(
          await dbCompleteGroupUploadRetry(
            db,
            expectedParent: expectedParent,
            expectedAttachment: expectedAttachment,
            completedAttachment: completedAttachment,
          ),
          isFalse,
        );
        final after = (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: [attachmentId],
        )).single;
        expect(after['download_status'], 'upload_failed');
        expect(after['content_hash'], isNull);
      },
    );
  });

  group('Plan 351 ordinary direct-media deletion custody', () {
    const sender = 'peer-local';
    const recipient = 'tc351-recipient';
    const t0 = '2026-08-09T09:00:00.000Z';
    const t1 = '2026-08-09T09:00:01.000Z';
    const nowMs = 1900000000000;

    String deletionEnvelope(String eventId) => jsonEncode(<String, Object?>{
      'type': 'message_deletion',
      'version': '2',
      'eventId': eventId,
      'senderPeerId': sender,
      'encrypted': const <String, Object?>{
        'kem': 'kem-351',
        'ciphertext': 'cipher-351',
        'nonce': 'nonce-351',
      },
    });

    Map<String, Object?> strictAttachmentRow({
      required String messageId,
      required String attachmentId,
      required String contentHash,
      String? fingerprint,
    }) => <String, Object?>{
      ...makeAttachmentRow(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 800,
        mediaType: 'image',
        width: null,
        height: null,
        localPath: 'media/direct/$attachmentId.jpg',
        downloadStatus: 'done',
        createdAt: t0,
        contentHash: contentHash,
        encryptionKeyBase64: secureStoreReferenceForKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        encryptionNonce: 'nonce-$attachmentId',
        encryptionScheme: 'blob_aes_256_gcm_v1',
      ),
      'direct_media_blob_custody_fingerprint': fingerprint,
    };

    var boundIncarnationSeq = 0;

    /// Seeds one delivered strict ordinary direct-media parent whose complete
    /// v111 generation is still bound to its live v108 incarnation.
    Future<
      ({
        Map<String, Object?> current,
        String messageId,
        List<String> attachmentIds,
        String incarnationId,
      })
    >
    seedBoundStrictParent(String suffix) async {
      final messageId = 'tc351-$suffix';
      final attachmentIds = <String>['$messageId-a', '$messageId-b'];
      // v108 holds one UNIQUE lowercase 32-hex incarnation per row, so a
      // matrix that seeds several generations into one database needs a
      // distinct identity per call.
      final incarnationId =
          'c0c0c0c0c0c0c0c0c0c0c0c0'
          '${(++boundIncarnationSeq).toRadixString(16).padLeft(8, '0')}';
      await db.insert(
        'messages',
        ConversationMessage(
          id: messageId,
          contactPeerId: recipient,
          senderPeerId: sender,
          text: 'strict media',
          timestamp: t0,
          status: 'delivered',
          isIncoming: false,
          createdAt: t0,
          wireEnvelope: jsonEncode(<String, Object?>{
            'type': 'chat_message',
            'version': '2',
            'id': messageId,
            'senderPeerId': sender,
            'encrypted': const <String, Object?>{
              'kem': 'kem-initial',
              'ciphertext': 'cipher-initial',
              'nonce': 'nonce-initial',
            },
          }),
        ).toMap(),
      );
      final manifest = <DirectMediaBlobManifestProjection>[];
      for (var index = 0; index < attachmentIds.length; index++) {
        final attachmentId = attachmentIds[index];
        final contentHash = index == 0 ? '1' * 64 : '2' * 64;
        final ciphertextSize = 41 + index;
        final expiresAtMs = nowMs + 60000 + (index * 1000);
        await dbInsertMediaAttachment(
          db,
          strictAttachmentRow(
            messageId: messageId,
            attachmentId: attachmentId,
            contentHash: contentHash,
          ),
        );
        await db.insert(
          kDirectMediaBlobCustodyTable,
          DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingStored,
            inboxCustodyIncarnationId: incarnationId,
            recipientPeerId: recipient,
            ciphertextRelativePath:
                'direct_media_blob_custody_v1/${'a' * 64}/$attachmentId.blob',
            contentHash: contentHash,
            ciphertextSize: ciphertextSize,
            expiresAtMs: expiresAtMs,
            custodyRelayPeerId: 'relay-$index',
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: t0,
            updatedAt: t0,
          ).toMap(),
        );
        manifest.add(
          DirectMediaBlobManifestProjection(
            attachmentId: attachmentId,
            commitment: DirectMediaBlobCustodyCommitment(
              contentHash: contentHash,
              ciphertextSize: ciphertextSize,
              expiresAtMs: expiresAtMs,
            ),
          ),
        );
      }
      await db.insert('direct_inbox_custody_outbox', <String, Object?>{
        'recipient_peer_id': recipient,
        'message_id': messageId,
        'incarnation_id': incarnationId,
        'wire_envelope': jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': messageId,
          'senderPeerId': sender,
          'encrypted': const <String, Object?>{
            'kem': 'kem-initial',
            'ciphertext': 'cipher-initial',
            'nonce': 'nonce-initial',
          },
        }),
        'retry_count': 0,
        'created_at': t0,
        'updated_at': t0,
        'media_blob_expires_at_ms': earliestDirectMediaBlobExpiryMs(manifest),
        'media_blob_manifest_hash': computeDirectMediaBlobManifestHash(
          manifest,
        ),
      });
      final current = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      )).single;
      return (
        current: current,
        messageId: messageId,
        attachmentIds: attachmentIds,
        incarnationId: incarnationId,
      );
    }

    Map<String, Object?> tombstoneOf(
      Map<String, Object?> current, {
      required String wireEnvelope,
    }) => <String, Object?>{
      ...current,
      'text': '',
      'status': 'sending',
      'deleted_at': t1,
      'deleted_by_peer_id': sender,
      'hidden_at': null,
      'transport': null,
      'relay_expires_at': null,
      'custody_checked_at': null,
      'wire_envelope': wireEnvelope,
    };

    test('TC-351-01 direct-media deletion stages blob transition tombstone and '
        'v109 atomically', () async {
      const eventId = '35100000-0000-4000-8000-000000000001';
      final seeded = await seedBoundStrictParent('atomic');
      final envelope = deletionEnvelope(eventId);

      // Selection is DB-authoritative: physical attachments plus the exact
      // v111/v108 generation decide the lane, never the parent's media list.
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          db,
          messageId: seeded.messageId,
        ),
        OutgoingDirectDeletionLane.strictMedia,
      );

      // A failure injected immediately before the v109 insert must leave the
      // parent, v111 and v108 exactly as they were.
      await expectLater(
        dbStageOutgoingDirectMediaDeletionInboxCustody(
          db,
          expectedRow: seeded.current,
          stagedRow: tombstoneOf(seeded.current, wireEnvelope: envelope),
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
          recipientPeerId: recipient,
          eventId: eventId,
          wireEnvelope: envelope,
          updatedAt: t1,
          beforeCustodyInsertForTest: () async =>
              throw StateError('injected v109 insert fault'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[seeded.messageId],
        )).single['deleted_at'],
        isNull,
        reason: 'no tombstone may survive a lost v109 insert',
      );
      expect(await db.query('direct_reaction_inbox_custody_outbox'), isEmpty);
      expect(
        (await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[seeded.messageId],
        )).map((row) => row['state']).toSet(),
        <String>{'outgoing_stored'},
      );

      final applied = await dbStageOutgoingDirectMediaDeletionInboxCustody(
        db,
        expectedRow: seeded.current,
        stagedRow: tombstoneOf(seeded.current, wireEnvelope: envelope),
        kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
        recipientPeerId: recipient,
        eventId: eventId,
        wireEnvelope: envelope,
        updatedAt: t1,
      );
      expect(applied.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect(applied.ownsMutationEvent, isTrue);
      expect(applied.custodyRow!['wire_envelope'], envelope);
      expect(applied.messageRow!['deleted_at'], t1);
      expect(applied.messageRow!['text'], '');

      final custody = await db.query('direct_reaction_inbox_custody_outbox');
      expect(custody, hasLength(1));
      expect(custody.single['recipient_peer_id'], recipient);
      expect(custody.single['event_id'], eventId);
      expect(custody.single['wire_envelope'], envelope);

      // An exact live v108 and its bound generation survive the deletion.
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[seeded.messageId],
        ),
        hasLength(1),
      );
      expect(
        (await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[seeded.messageId],
        )).map((row) => row['state']).toSet(),
        <String>{'outgoing_stored'},
      );

      // Exact replay is idempotent and never replays the parent projection.
      final replay = await dbStageOutgoingDirectMediaDeletionInboxCustody(
        db,
        expectedRow: seeded.current,
        stagedRow: tombstoneOf(seeded.current, wireEnvelope: envelope),
        kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
        recipientPeerId: recipient,
        eventId: eventId,
        wireEnvelope: envelope,
        updatedAt: t1,
      );
      expect(replay.outcome, OutgoingOrdinaryMutationOutcome.idempotent);
      expect(replay.custodyRow!['event_id'], eventId);
      expect(
        await db.query('direct_reaction_inbox_custody_outbox'),
        hasLength(1),
      );

      // A changed envelope under the same key is a collision, not a winner.
      final collision = await dbStageOutgoingDirectMediaDeletionInboxCustody(
        db,
        expectedRow: seeded.current,
        stagedRow: tombstoneOf(
          seeded.current,
          wireEnvelope: deletionEnvelope(
            eventId,
          ).replaceAll('cipher-351', 'cipher-other'),
        ),
        kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
        recipientPeerId: recipient,
        eventId: eventId,
        wireEnvelope: deletionEnvelope(
          eventId,
        ).replaceAll('cipher-351', 'cipher-other'),
        updatedAt: t1,
      );
      expect(collision.outcome, OutgoingOrdinaryMutationOutcome.refused);
      expect(
        await db.query('direct_reaction_inbox_custody_outbox'),
        hasLength(1),
      );
    });

    test(
      'TC-351-05 an incoming author tombstone refuses generic attachment save',
      () async {
        const messageId = 'tc351-incoming-deleted';
        await db.insert('messages', <String, Object?>{
          'id': messageId,
          'contact_peer_id': 'tc351-author',
          'sender_peer_id': 'tc351-author',
          'text': '',
          'timestamp': t0,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': t0,
          'deleted_at': t1,
          'deleted_by_peer_id': 'tc351-author',
        });
        expect(
          await dbCanApplyGenericMediaAttachmentSave(
            db,
            makeAttachmentRow(
              id: '$messageId-a',
              messageId: messageId,
              createdAt: t0,
            ),
          ),
          isFalse,
          reason: 'a delayed whole-row save cannot recreate deleted media',
        );

        // A live incoming parent is untouched by the new guard.
        const liveId = 'tc351-incoming-live';
        await db.insert('messages', <String, Object?>{
          'id': liveId,
          'contact_peer_id': 'tc351-author',
          'sender_peer_id': 'tc351-author',
          'text': 'live',
          'timestamp': t0,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': t0,
        });
        expect(
          await dbCanApplyGenericMediaAttachmentSave(
            db,
            makeAttachmentRow(
              id: '$liveId-a',
              messageId: liveId,
              createdAt: t0,
            ),
          ),
          isTrue,
        );
      },
    );

    test('TC-351-02 v108 and v111 state matrix preserves the independent initial '
        'and blob owners', () async {
      var eventSeq = 0;
      String nextEventId() =>
          '35100000-0000-4000-8000-00000000${(++eventSeq + 10).toString().padLeft(4, '0')}';

      Future<DirectMediaDeletionCustodyDbStageResult> stageDeletion(
        Map<String, Object?> current, {
        required String eventId,
      }) {
        final envelope = deletionEnvelope(eventId);
        return dbStageOutgoingDirectMediaDeletionInboxCustody(
          db,
          expectedRow: current,
          stagedRow: tombstoneOf(current, wireEnvelope: envelope),
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
          recipientPeerId: recipient,
          eventId: eventId,
          wireEnvelope: envelope,
          updatedAt: t1,
        );
      }

      Future<Map<String, Object?>> seedMediaParent(
        String suffix, {
        required List<
          ({
            String attachmentId,
            String contentHash,
            String? fingerprint,
            DirectMediaBlobCustodyState? state,
            int? expiresAtMs,
            String? incarnationId,
            DirectMediaBlobCustodyDirection direction,
          })
        >
        attachments,
        ({String incarnationId, String? manifestHash, int? expiresAtMs})? v108,
      }) async {
        final messageId = 'tc351-$suffix';
        await db.insert(
          'messages',
          ConversationMessage(
            id: messageId,
            contactPeerId: recipient,
            senderPeerId: sender,
            text: 'media',
            timestamp: t0,
            status: 'delivered',
            isIncoming: false,
            createdAt: t0,
          ).toMap(),
        );
        for (final spec in attachments) {
          await dbInsertMediaAttachment(
            db,
            strictAttachmentRow(
              messageId: messageId,
              attachmentId: '$messageId-${spec.attachmentId}',
              contentHash: spec.contentHash,
              fingerprint: spec.fingerprint,
            ),
          );
          if (spec.state == null) continue;
          final outgoing =
              spec.direction == DirectMediaBlobCustodyDirection.outgoing;
          await db.insert(
            kDirectMediaBlobCustodyTable,
            DirectMediaBlobCustodyRow(
              attachmentId: '$messageId-${spec.attachmentId}',
              messageId: messageId,
              direction: spec.direction,
              state: spec.state!,
              inboxCustodyIncarnationId: spec.incarnationId,
              recipientPeerId: outgoing ? recipient : null,
              ciphertextRelativePath: outgoing
                  ? 'direct_media_blob_custody_v1/${'a' * 64}/'
                        '$messageId-${spec.attachmentId}.blob'
                  : null,
              contentHash: spec.contentHash,
              ciphertextSize: 41,
              expiresAtMs: spec.expiresAtMs,
              custodyRelayPeerId: !outgoing || spec.expiresAtMs == null
                  ? null
                  : 'relay-x',
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: t0,
              updatedAt: t0,
            ).toMap(),
          );
        }
        if (v108 != null) {
          await db.insert('direct_inbox_custody_outbox', <String, Object?>{
            'recipient_peer_id': recipient,
            'message_id': messageId,
            'incarnation_id': v108.incarnationId,
            'wire_envelope': jsonEncode(<String, Object?>{
              'type': 'chat_message',
              'version': '2',
              'id': messageId,
              'senderPeerId': sender,
              'encrypted': const <String, Object?>{
                'kem': 'kem-initial',
                'ciphertext': 'cipher-initial',
                'nonce': 'nonce-initial',
              },
            }),
            'retry_count': 0,
            'created_at': t0,
            'updated_at': t0,
            'media_blob_manifest_hash': v108.manifestHash,
            'media_blob_expires_at_ms': v108.expiresAtMs,
          });
        }
        return (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        )).single;
      }

      // Row 2: no v108 plus one complete unbound active generation moves to
      // cleanup atomically with the tombstone and the v109 event.
      final activeParent = await seedMediaParent(
        'active',
        attachments:
            <
              ({
                String attachmentId,
                String contentHash,
                String? fingerprint,
                DirectMediaBlobCustodyState? state,
                int? expiresAtMs,
                String? incarnationId,
                DirectMediaBlobCustodyDirection direction,
              })
            >[
              (
                attachmentId: 'a',
                contentHash: '1' * 64,
                fingerprint: null,
                state: DirectMediaBlobCustodyState.outgoingStored,
                expiresAtMs: nowMs + 60000,
                incarnationId: null,
                direction: DirectMediaBlobCustodyDirection.outgoing,
              ),
            ],
        v108: null,
      );
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          db,
          messageId: activeParent['id']! as String,
        ),
        OutgoingDirectDeletionLane.strictMedia,
      );
      expect(
        (await stageDeletion(activeParent, eventId: nextEventId())).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );
      expect(
        (await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[activeParent['id']],
        )).single['state'],
        'outgoing_cleanup_pending',
      );

      // Row 3: a cleanup subset left after physical cleanup still stages and
      // its remaining obligations survive untouched.
      final cleanupParent = await seedMediaParent(
        'cleanup-subset',
        attachments:
            <
              ({
                String attachmentId,
                String contentHash,
                String? fingerprint,
                DirectMediaBlobCustodyState? state,
                int? expiresAtMs,
                String? incarnationId,
                DirectMediaBlobCustodyDirection direction,
              })
            >[
              (
                attachmentId: 'a',
                contentHash: '1' * 64,
                fingerprint: null,
                state: DirectMediaBlobCustodyState.outgoingCleanupPending,
                expiresAtMs: nowMs + 60000,
                incarnationId: 'd' * 32,
                direction: DirectMediaBlobCustodyDirection.outgoing,
              ),
              (
                attachmentId: 'b',
                contentHash: '2' * 64,
                fingerprint: null,
                state: null,
                expiresAtMs: null,
                incarnationId: null,
                direction: DirectMediaBlobCustodyDirection.outgoing,
              ),
            ],
        v108: null,
      );
      expect(
        (await stageDeletion(cleanupParent, eventId: nextEventId())).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );
      expect(
        (await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[cleanupParent['id']],
        )).single['state'],
        'outgoing_cleanup_pending',
      );

      // Row 4: v111 fully absent while every attachment retains a valid
      // strict commitment fingerprint.
      final fingerprintCommitment = DirectMediaBlobCustodyCommitment(
        contentHash: '3' * 64,
        ciphertextSize: 41,
        expiresAtMs: nowMs + 60000,
      );
      final fingerprinted = await seedMediaParent(
        'fingerprinted',
        attachments:
            <
              ({
                String attachmentId,
                String contentHash,
                String? fingerprint,
                DirectMediaBlobCustodyState? state,
                int? expiresAtMs,
                String? incarnationId,
                DirectMediaBlobCustodyDirection direction,
              })
            >[
              (
                attachmentId: 'a',
                contentHash: '3' * 64,
                fingerprint: computeDirectMediaBlobCommitmentFingerprint(
                  attachmentId: 'tc351-fingerprinted-a',
                  commitment: fingerprintCommitment,
                ),
                state: null,
                expiresAtMs: null,
                incarnationId: null,
                direction: DirectMediaBlobCustodyDirection.outgoing,
              ),
            ],
        v108: null,
      );
      expect(
        (await stageDeletion(fingerprinted, eventId: nextEventId())).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );

      // Row 5: proven historical media stays on legacy transport. The strict
      // stage refuses it and its exact unbound v108 is preserved.
      final historical = await seedMediaParent(
        'historical',
        attachments:
            <
              ({
                String attachmentId,
                String contentHash,
                String? fingerprint,
                DirectMediaBlobCustodyState? state,
                int? expiresAtMs,
                String? incarnationId,
                DirectMediaBlobCustodyDirection direction,
              })
            >[
              (
                attachmentId: 'a',
                contentHash: '4' * 64,
                fingerprint: null,
                state: null,
                expiresAtMs: null,
                incarnationId: null,
                direction: DirectMediaBlobCustodyDirection.outgoing,
              ),
            ],
        v108: (incarnationId: 'e' * 32, manifestHash: null, expiresAtMs: null),
      );
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          db,
          messageId: historical['id']! as String,
        ),
        OutgoingDirectDeletionLane.legacyMedia,
      );
      expect(
        (await stageDeletion(historical, eventId: nextEventId())).outcome,
        OutgoingOrdinaryMutationOutcome.refused,
        reason: 'history is never promoted into the strict v109 owner',
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[historical['id']],
        )).single['deleted_at'],
        isNull,
      );
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[historical['id']],
        ),
        hasLength(1),
      );

      // Row 6 contradictions: every one changes nothing at all.
      final contradictions =
          <
            String,
            ({
              List<
                ({
                  String attachmentId,
                  String contentHash,
                  String? fingerprint,
                  DirectMediaBlobCustodyState? state,
                  int? expiresAtMs,
                  String? incarnationId,
                  DirectMediaBlobCustodyDirection direction,
                })
              >
              attachments,
              ({String incarnationId, String? manifestHash, int? expiresAtMs})?
              v108,
            })
          >{
            'bound-without-v108': (
              attachments: [
                (
                  attachmentId: 'a',
                  contentHash: '1' * 64,
                  fingerprint: null,
                  state: DirectMediaBlobCustodyState.outgoingStored,
                  expiresAtMs: nowMs + 60000,
                  incarnationId: 'f' * 32,
                  direction: DirectMediaBlobCustodyDirection.outgoing,
                ),
              ],
              v108: null,
            ),
            'manifest-bearing-v108-without-v111': (
              attachments: [
                (
                  attachmentId: 'a',
                  contentHash: '1' * 64,
                  fingerprint: null,
                  state: null,
                  expiresAtMs: null,
                  incarnationId: null,
                  direction: DirectMediaBlobCustodyDirection.outgoing,
                ),
              ],
              v108: (
                incarnationId: 'a' * 32,
                manifestHash: '9' * 64,
                expiresAtMs: nowMs + 60000,
              ),
            ),
            'incomplete-generation': (
              attachments: [
                (
                  attachmentId: 'a',
                  contentHash: '1' * 64,
                  fingerprint: null,
                  state: DirectMediaBlobCustodyState.outgoingStored,
                  expiresAtMs: nowMs + 60000,
                  incarnationId: null,
                  direction: DirectMediaBlobCustodyDirection.outgoing,
                ),
                (
                  attachmentId: 'b',
                  contentHash: '2' * 64,
                  fingerprint: null,
                  state: null,
                  expiresAtMs: null,
                  incarnationId: null,
                  direction: DirectMediaBlobCustodyDirection.outgoing,
                ),
              ],
              v108: null,
            ),
            'active-mixed-with-cleanup': (
              attachments: [
                (
                  attachmentId: 'a',
                  contentHash: '1' * 64,
                  fingerprint: null,
                  state: DirectMediaBlobCustodyState.outgoingStored,
                  expiresAtMs: nowMs + 60000,
                  incarnationId: null,
                  direction: DirectMediaBlobCustodyDirection.outgoing,
                ),
                (
                  attachmentId: 'b',
                  contentHash: '2' * 64,
                  fingerprint: null,
                  state: DirectMediaBlobCustodyState.outgoingCleanupPending,
                  expiresAtMs: null,
                  incarnationId: null,
                  direction: DirectMediaBlobCustodyDirection.outgoing,
                ),
              ],
              v108: null,
            ),
            'incoming-rows': (
              attachments: [
                (
                  attachmentId: 'a',
                  contentHash: '1' * 64,
                  fingerprint: null,
                  state: DirectMediaBlobCustodyState.incomingCommitted,
                  expiresAtMs: nowMs + 60000,
                  incarnationId: null,
                  direction: DirectMediaBlobCustodyDirection.incoming,
                ),
              ],
              v108: null,
            ),
            'crossed-valid-fingerprint': (
              attachments: [
                (
                  attachmentId: 'a',
                  contentHash: '1' * 64,
                  // A well-formed digest of ANOTHER commitment: shape alone
                  // is never proof of this row's extant v111 authority.
                  fingerprint: computeDirectMediaBlobCommitmentFingerprint(
                    attachmentId: 'tc351-crossed-valid-fingerprint-a',
                    commitment: DirectMediaBlobCustodyCommitment(
                      contentHash: '8' * 64,
                      ciphertextSize: 41,
                      expiresAtMs: nowMs + 60000,
                    ),
                  ),
                  state: DirectMediaBlobCustodyState.outgoingStored,
                  expiresAtMs: nowMs + 60000,
                  incarnationId: null,
                  direction: DirectMediaBlobCustodyDirection.outgoing,
                ),
              ],
              v108: null,
            ),
            'mixed-fingerprints': (
              attachments: [
                (
                  attachmentId: 'a',
                  contentHash: '1' * 64,
                  fingerprint: '7' * 64,
                  state: null,
                  expiresAtMs: null,
                  incarnationId: null,
                  direction: DirectMediaBlobCustodyDirection.outgoing,
                ),
                (
                  attachmentId: 'b',
                  contentHash: '2' * 64,
                  fingerprint: null,
                  state: null,
                  expiresAtMs: null,
                  incarnationId: null,
                  direction: DirectMediaBlobCustodyDirection.outgoing,
                ),
              ],
              v108: null,
            ),
          };
      for (final entry in contradictions.entries) {
        final parent = await seedMediaParent(
          entry.key,
          attachments: entry.value.attachments,
          v108: entry.value.v108,
        );
        final messageId = parent['id']! as String;
        expect(
          await dbClassifyOutgoingDirectDeletionLane(db, messageId: messageId),
          OutgoingDirectDeletionLane.contradiction,
          reason: entry.key,
        );
        final blobBefore = await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
        );
        expect(
          (await stageDeletion(parent, eventId: nextEventId())).outcome,
          OutgoingOrdinaryMutationOutcome.refused,
          reason: entry.key,
        );
        expect(
          (await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          )).single['deleted_at'],
          isNull,
          reason: entry.key,
        );
        expect(
          await db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          blobBefore,
          reason: entry.key,
        );
      }

      // A live v108 completes AFTER the tombstone: it retires only its own
      // incarnation, leaves the tombstone, and moves v111 to cleanup once.
      final bound = await seedBoundStrictParent('later-completion');
      expect(
        (await stageDeletion(bound.current, eventId: nextEventId())).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final v108Row = (await db.query(
        'direct_inbox_custody_outbox',
        where: 'message_id = ?',
        whereArgs: <Object?>[bound.messageId],
      )).single;
      expect(
        await dbCompleteAcceptedDirectInboxCustodyIfExact(
          db,
          recipientPeerId: recipient,
          messageId: bound.messageId,
          expectedIncarnationId: bound.incarnationId,
          expectedWireEnvelope: v108Row['wire_envelope']! as String,
          relayExpiresAt:
              (v108Row['media_blob_expires_at_ms']! as num).toInt() - 1,
        ),
        DirectInboxCustodyCompletionOutcome.messagePreserved,
      );
      final preservedTombstone = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[bound.messageId],
      )).single;
      expect(preservedTombstone['deleted_at'], t1);
      expect(preservedTombstone['status'], 'sending');
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[bound.messageId],
        ),
        isEmpty,
      );
      expect(
        (await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[bound.messageId],
        )).map((row) => row['state']).toSet(),
        <String>{'outgoing_cleanup_pending'},
      );

      // Shared v109 capacity refusal never mutates the parent or v111.
      final capacityParent = await seedBoundStrictParent('capacity');
      final capacityEnvelope = deletionEnvelope(nextEventId());
      final capacityEventId =
          (jsonDecode(capacityEnvelope) as Map<String, Object?>)['eventId']!
              as String;
      expect(
        (await dbStageOutgoingDirectMediaDeletionInboxCustody(
          db,
          expectedRow: capacityParent.current,
          stagedRow: tombstoneOf(
            capacityParent.current,
            wireEnvelope: capacityEnvelope,
          ),
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
          recipientPeerId: recipient,
          eventId: capacityEventId,
          wireEnvelope: capacityEnvelope,
          updatedAt: t1,
          capacity: 0,
        )).outcome,
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[capacityParent.messageId],
        )).single['deleted_at'],
        isNull,
      );
    });

    /// The exact per-row lineage digest the completion transaction owes each
    /// physical attachment of a proven strict generation.
    Future<Map<String, String>> expectedLineageOf(String messageId) async {
      final rows = (await db.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
        orderBy: 'attachment_id ASC',
      )).map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
      return <String, String>{
        for (final row in rows)
          row.attachmentId: computeDirectMediaBlobCommitmentFingerprint(
            attachmentId: row.attachmentId,
            commitment: DirectMediaBlobCustodyCommitment(
              kind: row.custodyKind,
              contract: row.custodyContract,
              contentHash: row.contentHash,
              ciphertextSize: row.ciphertextSize,
              transportMime: row.transportMime,
              expiresAtMs: row.expiresAtMs!,
            ),
          ),
      };
    }

    Future<Map<String, Object?>> lineageOf(String messageId) async => {
      for (final row in await db.query(
        'media_attachments',
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
        orderBy: 'id ASC',
      ))
        row['id']! as String: row['direct_media_blob_custody_fingerprint'],
    };

    Future<DirectInboxCustodyCompletionOutcome> completeBound(
      ({
        Map<String, Object?> current,
        String messageId,
        List<String> attachmentIds,
        String incarnationId,
      })
      bound,
    ) async {
      final v108 = (await db.query(
        'direct_inbox_custody_outbox',
        where: 'message_id = ?',
        whereArgs: <Object?>[bound.messageId],
      )).single;
      return dbCompleteAcceptedDirectInboxCustodyIfExact(
        db,
        recipientPeerId: recipient,
        messageId: bound.messageId,
        expectedIncarnationId: bound.incarnationId,
        expectedWireEnvelope: v108['wire_envelope']! as String,
        relayExpiresAt: (v108['media_blob_expires_at_ms']! as num).toInt() - 1,
      );
    }

    test('TC-352-01 exact accepted v108 completion pins per-attachment lineage '
        'through full v111 drain', () async {
      final bound = await seedBoundStrictParent('post-drain');
      final expectedLineage = await expectedLineageOf(bound.messageId);

      // Two independent commitments: no generation-level manifest hash, one
      // shared earliest expiry, and no relay expiry can satisfy both rows.
      expect(expectedLineage, hasLength(2));
      expect(expectedLineage.values.toSet(), hasLength(2));
      expect(await lineageOf(bound.messageId), <String, Object?>{
        for (final id in bound.attachmentIds) id: null,
      });

      expect(
        await completeBound(bound),
        DirectInboxCustodyCompletionOutcome.messagePreserved,
      );

      // The already-stronger delivered projection is preserved byte for
      // byte; only the attachments gained their exact lineage.
      expect(
        (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[bound.messageId],
        )).single,
        bound.current,
      );
      expect(await lineageOf(bound.messageId), expectedLineage);

      // The v108 owner is retired and its generation moves to cleanup.
      expect(
        await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[bound.messageId],
        ),
        isEmpty,
      );
      final cleanup = (await db.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ?',
        whereArgs: <Object?>[bound.messageId],
        orderBy: 'attachment_id ASC',
      )).map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
      expect(
        cleanup.map((row) => row.state).toSet(),
        <DirectMediaBlobCustodyState>{
          DirectMediaBlobCustodyState.outgoingCleanupPending,
        },
      );

      // Physical cleanup now drains the last reconstructable v111 proof.
      for (final row in cleanup) {
        expect(
          await dbDeleteDirectMediaBlobCleanupPendingIfExact(db, expected: row),
          isTrue,
        );
      }
      expect(
        await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[bound.messageId],
        ),
        isEmpty,
      );
      expect(await lineageOf(bound.messageId), expectedLineage);

      // The persisted lineage is the only surviving authority and still
      // selects Plan 351's durable v109 owner.
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          db,
          messageId: bound.messageId,
        ),
        OutgoingDirectDeletionLane.strictMedia,
      );

      const eventId = '35200000-0000-4000-8000-000000000001';
      final envelope = deletionEnvelope(eventId);
      final drainedParent = (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[bound.messageId],
      )).single;
      final staged = await dbStageOutgoingDirectMediaDeletionInboxCustody(
        db,
        expectedRow: drainedParent,
        stagedRow: tombstoneOf(drainedParent, wireEnvelope: envelope),
        kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
        recipientPeerId: recipient,
        eventId: eventId,
        wireEnvelope: envelope,
        updatedAt: t1,
      );
      expect(staged.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect(staged.ownsMutationEvent, isTrue);
      expect(staged.messageRow!['deleted_at'], t1);
      final v109 = await db.query('direct_reaction_inbox_custody_outbox');
      expect(v109, hasLength(1));
      expect(v109.single['event_id'], eventId);
      expect(v109.single['wire_envelope'], envelope);
    });

    test('TC-352-02 outgoing lineage fingerprint CAS and v108 completion are '
        'all-or-zero', () async {
      Future<
        ({
          Map<String, Object?> messages,
          List<Map<String, Object?>> attachments,
          List<Map<String, Object?>> v108,
          List<Map<String, Object?>> v111,
        })
      >
      snapshot(String messageId) async => (
        messages: (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        )).single,
        attachments: await db.query(
          'media_attachments',
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
          orderBy: 'id ASC',
        ),
        v108: await db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
        ),
        v111: await db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
          orderBy: 'attachment_id ASC',
        ),
      );

      Future<void> expectUnchanged(
        String messageId,
        ({
          Map<String, Object?> messages,
          List<Map<String, Object?>> attachments,
          List<Map<String, Object?>> v108,
          List<Map<String, Object?>> v111,
        })
        before, {
        required String reason,
      }) async {
        final after = await snapshot(messageId);
        expect(after.messages, before.messages, reason: reason);
        expect(after.attachments, before.attachments, reason: reason);
        expect(after.v108, before.v108, reason: reason);
        expect(after.v111, before.v111, reason: reason);
      }

      Future<void> stamp(String attachmentId, String? fingerprint) async {
        expect(
          await db.update(
            'media_attachments',
            <String, Object?>{
              'direct_media_blob_custody_fingerprint': fingerprint,
            },
            where: 'id = ?',
            whereArgs: <Object?>[attachmentId],
          ),
          1,
        );
      }

      // A crossed but well-formed digest is refused BEFORE any authorship:
      // a sibling attachment's real fingerprint is not this row's lineage.
      final crossed = await seedBoundStrictParent('crossed-valid-digest');
      final crossedExpected = await expectedLineageOf(crossed.messageId);
      await stamp(
        crossed.attachmentIds.first,
        crossedExpected[crossed.attachmentIds.last],
      );
      final crossedBefore = await snapshot(crossed.messageId);
      expect(
        await completeBound(crossed),
        DirectInboxCustodyCompletionOutcome.stale,
      );
      await expectUnchanged(
        crossed.messageId,
        crossedBefore,
        reason: 'a sibling digest is crossed proof, not lineage',
      );

      // A well-formed value that is nobody's commitment digest is refused.
      final foreign = await seedBoundStrictParent('foreign-digest');
      await stamp(foreign.attachmentIds.first, '7' * 64);
      final foreignBefore = await snapshot(foreign.messageId);
      expect(
        await completeBound(foreign),
        DirectInboxCustodyCompletionOutcome.stale,
      );
      await expectUnchanged(
        foreign.messageId,
        foreignBefore,
        reason: 'a foreign 64-hex value can never be adopted as lineage',
      );

      // One strict v111 row without its physical attachment is ambiguous.
      final missing = await seedBoundStrictParent('missing-attachment');
      await db.delete(
        'media_attachments',
        where: 'id = ?',
        whereArgs: <Object?>[missing.attachmentIds.last],
      );
      final missingBefore = await snapshot(missing.messageId);
      expect(
        await completeBound(missing),
        DirectInboxCustodyCompletionOutcome.stale,
      );
      await expectUnchanged(
        missing.messageId,
        missingBefore,
        reason: 'an unmatched v111 row cannot author partial lineage',
      );

      // An extra direct attachment with no v111 row is equally ambiguous.
      final extra = await seedBoundStrictParent('extra-attachment');
      await dbInsertMediaAttachment(
        db,
        strictAttachmentRow(
          messageId: extra.messageId,
          attachmentId: '${extra.messageId}-c',
          contentHash: '3' * 64,
        ),
      );
      final extraBefore = await snapshot(extra.messageId);
      expect(
        await completeBound(extra),
        DirectInboxCustodyCompletionOutcome.stale,
      );
      await expectUnchanged(
        extra.messageId,
        extraBefore,
        reason: 'an extra physical attachment is not part of the generation',
      );

      // A physical row whose content hash no longer matches its own v111
      // commitment is crossed identity, not a stampable projection.
      final crossedHash = await seedBoundStrictParent('crossed-hash');
      expect(
        await db.update(
          'media_attachments',
          <String, Object?>{'content_hash': '9' * 64},
          where: 'id = ?',
          whereArgs: <Object?>[crossedHash.attachmentIds.first],
        ),
        1,
      );
      final crossedHashBefore = await snapshot(crossedHash.messageId);
      expect(
        await completeBound(crossedHash),
        DirectInboxCustodyCompletionOutcome.stale,
      );
      await expectUnchanged(
        crossedHash.messageId,
        crossedHashBefore,
        reason: 'a drifted physical content hash is crossed identity',
      );

      // The same crossed identity on the SECOND row: the complete set is
      // prevalidated, so a valid leading row is never written first.
      final lateCrossedHash = await seedBoundStrictParent('late-crossed');
      expect(
        await db.update(
          'media_attachments',
          <String, Object?>{'content_hash': '9' * 64},
          where: 'id = ?',
          whereArgs: <Object?>[lateCrossedHash.attachmentIds.last],
        ),
        1,
      );
      final lateCrossedHashBefore = await snapshot(lateCrossedHash.messageId);
      expect(
        await completeBound(lateCrossedHash),
        DirectInboxCustodyCompletionOutcome.stale,
      );
      await expectUnchanged(
        lateCrossedHash.messageId,
        lateCrossedHashBefore,
        reason: 'a trailing contradiction must precede the first write',
      );

      // Null input is authored exactly once.
      final fresh = await seedBoundStrictParent('null-input');
      final freshExpected = await expectedLineageOf(fresh.messageId);
      expect(
        await completeBound(fresh),
        DirectInboxCustodyCompletionOutcome.messagePreserved,
      );
      expect(await lineageOf(fresh.messageId), freshExpected);

      // Exact pre-stamped input completes and is left byte-identical.
      final prestamped = await seedBoundStrictParent('pre-stamped-exact');
      final prestampedExpected = await expectedLineageOf(prestamped.messageId);
      for (final entry in prestampedExpected.entries) {
        await stamp(entry.key, entry.value);
      }
      final prestampedAttachments = await db.query(
        'media_attachments',
        where: 'message_id = ?',
        whereArgs: <Object?>[prestamped.messageId],
        orderBy: 'id ASC',
      );
      expect(
        await completeBound(prestamped),
        DirectInboxCustodyCompletionOutcome.messagePreserved,
      );
      expect(
        await db.query(
          'media_attachments',
          where: 'message_id = ?',
          whereArgs: <Object?>[prestamped.messageId],
          orderBy: 'id ASC',
        ),
        prestampedAttachments,
      );

      // A mixed null/exact generation is completed to full lineage.
      final partial = await seedBoundStrictParent('pre-stamped-partial');
      final partialExpected = await expectedLineageOf(partial.messageId);
      await stamp(
        partial.attachmentIds.first,
        partialExpected[partial.attachmentIds.first],
      );
      expect(
        await completeBound(partial),
        DirectInboxCustodyCompletionOutcome.messagePreserved,
      );
      expect(await lineageOf(partial.messageId), partialExpected);

      // Fault 1: the SECOND fingerprint update aborts. Nothing partial may
      // survive — not the first digest, not the v108/v111 retirement.
      final earlyFault = await seedBoundStrictParent('fault-fingerprint');
      expect(
        await db.update(
          'messages',
          <String, Object?>{'status': 'sending'},
          where: 'id = ?',
          whereArgs: <Object?>[earlyFault.messageId],
        ),
        1,
      );
      final earlyFaultBefore = await snapshot(earlyFault.messageId);
      await db.execute('''
          CREATE TRIGGER abort_second_lineage_stamp
          BEFORE UPDATE OF direct_media_blob_custody_fingerprint
          ON media_attachments
          WHEN NEW.id = '${earlyFault.attachmentIds.last}'
          BEGIN
            SELECT RAISE(ABORT, 'injected second fingerprint failure');
          END
        ''');
      await expectLater(
        completeBound(earlyFault),
        throwsA(isA<DatabaseException>()),
      );
      await db.execute('DROP TRIGGER abort_second_lineage_stamp');
      await expectUnchanged(
        earlyFault.messageId,
        earlyFaultBefore,
        reason: 'partial lineage authorship must roll back completely',
      );

      // Fault 2: the SECOND v111 cleanup transition aborts AFTER both
      // fingerprints, the message projection and the v108 delete have run.
      // One transaction is the only thing that can undo all of them.
      final lateFault = await seedBoundStrictParent('fault-late-v111');
      expect(
        await db.update(
          'messages',
          <String, Object?>{'status': 'sending'},
          where: 'id = ?',
          whereArgs: <Object?>[lateFault.messageId],
        ),
        1,
      );
      final lateFaultBefore = await snapshot(lateFault.messageId);
      await db.execute('''
          CREATE TRIGGER abort_second_v111_cleanup
          BEFORE UPDATE OF state ON $kDirectMediaBlobCustodyTable
          WHEN OLD.attachment_id = '${lateFault.attachmentIds.last}'
            AND NEW.state = 'outgoing_cleanup_pending'
          BEGIN
            SELECT RAISE(ABORT, 'injected late v111 transition failure');
          END
        ''');
      await expectLater(
        completeBound(lateFault),
        throwsA(isA<DatabaseException>()),
      );
      await db.execute('DROP TRIGGER abort_second_v111_cleanup');
      await expectUnchanged(
        lateFault.messageId,
        lateFaultBefore,
        reason:
            'lineage, message projection, v108 and v111 share one transaction',
      );
    });

    test(
      'TC-352-04 deletion-first completion retires v108 without requiring or '
      'recreating attachment lineage',
      () async {
        // Plan 351 tombstones the parent and cleanup removes its attachments
        // before the retained v108 incarnation ever completes.
        final removed = await seedBoundStrictParent('deletion-first-removed');
        const removedEventId = '35200000-0000-4000-8000-000000000004';
        final removedEnvelope = deletionEnvelope(removedEventId);
        expect(
          (await dbStageOutgoingDirectMediaDeletionInboxCustody(
            db,
            expectedRow: removed.current,
            stagedRow: tombstoneOf(
              removed.current,
              wireEnvelope: removedEnvelope,
            ),
            kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
            recipientPeerId: recipient,
            eventId: removedEventId,
            wireEnvelope: removedEnvelope,
            updatedAt: t1,
          )).outcome,
          OutgoingOrdinaryMutationOutcome.applied,
        );
        await db.delete(
          'media_attachments',
          where: 'message_id = ?',
          whereArgs: <Object?>[removed.messageId],
        );

        expect(
          await completeBound(removed),
          DirectInboxCustodyCompletionOutcome.messagePreserved,
        );
        final removedTombstone = (await db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[removed.messageId],
        )).single;
        expect(removedTombstone['deleted_at'], t1);
        expect(removedTombstone['status'], 'sending');
        expect(
          await db.query(
            'media_attachments',
            where: 'message_id = ?',
            whereArgs: <Object?>[removed.messageId],
          ),
          isEmpty,
          reason: 'completion may never recreate a cleaned-up attachment',
        );
        expect(
          await db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[removed.messageId],
          ),
          isEmpty,
        );
        expect(
          (await db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[removed.messageId],
          )).map((row) => row['state']).toSet(),
          <String>{'outgoing_cleanup_pending'},
        );

        // The same holds when cleanup has only partially drained: a terminal
        // parent never makes lineage a completion prerequisite.
        final partial = await seedBoundStrictParent('deletion-first-partial');
        const partialEventId = '35200000-0000-4000-8000-000000000005';
        final partialEnvelope = deletionEnvelope(partialEventId);
        expect(
          (await dbStageOutgoingDirectMediaDeletionInboxCustody(
            db,
            expectedRow: partial.current,
            stagedRow: tombstoneOf(
              partial.current,
              wireEnvelope: partialEnvelope,
            ),
            kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
            recipientPeerId: recipient,
            eventId: partialEventId,
            wireEnvelope: partialEnvelope,
            updatedAt: t1,
          )).outcome,
          OutgoingOrdinaryMutationOutcome.applied,
        );
        await db.delete(
          'media_attachments',
          where: 'id = ?',
          whereArgs: <Object?>[partial.attachmentIds.last],
        );

        expect(
          await completeBound(partial),
          DirectInboxCustodyCompletionOutcome.messagePreserved,
        );
        expect(await lineageOf(partial.messageId), <String, Object?>{
          partial.attachmentIds.first: null,
        });
        expect(
          await db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[partial.messageId],
          ),
          isEmpty,
        );
        expect(
          (await db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[partial.messageId],
          )).map((row) => row['state']).toSet(),
          <String>{'outgoing_cleanup_pending'},
        );
      },
    );
  });

  group('Plan 353 ordinary direct-media caption-only edit custody', () {
    const sender = 'peer-local';
    const recipient = 'tc353-recipient';
    const t0 = '2026-08-09T09:00:00.000Z';
    const t1 = '2026-08-09T09:00:01.000Z';
    const t2 = '2026-08-09T09:00:02.000Z';
    const nowMs = 1900000000000;

    var eventSeq = 0;
    String nextEventId() =>
        '35300000-0000-4000-8000-${(++eventSeq).toString().padLeft(12, '0')}';

    String editEnvelope(String messageId, String eventId) =>
        jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': messageId,
          'eventId': eventId,
          'senderPeerId': sender,
          'encrypted': <String, Object?>{
            'kem': 'kem-353',
            'ciphertext': 'cipher-$eventId',
            'nonce': 'nonce-353',
          },
        });

    String initialEnvelope(String messageId) => jsonEncode(<String, Object?>{
      'type': 'chat_message',
      'version': '2',
      'id': messageId,
      'senderPeerId': sender,
      'encrypted': const <String, Object?>{
        'kem': 'kem-initial',
        'ciphertext': 'cipher-initial',
        'nonce': 'nonce-initial',
      },
    });

    /// One physical direct attachment carrying only storage-reference key
    /// material — SQLite never sees a raw key.
    Map<String, Object?> attachmentRow({
      required String messageId,
      required String attachmentId,
      required String contentHash,
      String createdAt = t0,
      String? fingerprint,
    }) => <String, Object?>{
      ...makeAttachmentRow(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 800,
        mediaType: 'image',
        width: 640,
        height: 480,
        localPath: 'media/direct/$attachmentId.jpg',
        downloadStatus: 'done',
        createdAt: createdAt,
        contentHash: contentHash,
        encryptionKeyBase64: secureStoreReferenceForKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        encryptionNonce: 'nonce-$attachmentId',
        encryptionScheme: 'blob_aes_256_gcm_v1',
      ),
      'direct_media_blob_custody_fingerprint': fingerprint,
    };

    Map<String, Object?> parentRowFor(
      String messageId, {
      String status = 'delivered',
      String? wireEnvelope,
      String? transport = 'direct',
    }) => ConversationMessage(
      id: messageId,
      contactPeerId: recipient,
      senderPeerId: sender,
      text: 'original caption',
      timestamp: t0,
      status: status,
      isIncoming: false,
      createdAt: t0,
      transport: transport,
      wireEnvelope: wireEnvelope,
      dedupKey: messageId,
    ).toMap();

    /// A caption-only staged projection: only text, editedAt and the exact
    /// edit-attempt transport fields differ from the persisted parent.
    Map<String, Object?> captionEditOf(
      Map<String, Object?> current, {
      required String wireEnvelope,
      String caption = 'edited caption',
      String editedAt = t1,
    }) => <String, Object?>{
      ...current,
      'text': caption,
      'edited_at': editedAt,
      'status': 'sending',
      'transport': null,
      'relay_expires_at': null,
      'custody_checked_at': null,
      'wire_envelope': wireEnvelope,
    };

    var v108Seq = 0;

    /// Seeds one ordinary outgoing direct parent with [attachments] physical
    /// rows, [blobRows] v111 rows and an optional v108 owner.
    Future<Map<String, Object?>> seedMediaParent(
      String suffix, {
      required List<Map<String, Object?>> attachments,
      List<DirectMediaBlobCustodyRow> blobRows = const [],
      Map<String, Object?>? v108,
      String status = 'delivered',
      String? transport = 'direct',
      String? wireEnvelope,
    }) async {
      final messageId = 'tc353-$suffix';
      await db.insert(
        'messages',
        parentRowFor(
          messageId,
          status: status,
          transport: transport,
          wireEnvelope: wireEnvelope,
        ),
      );
      for (final attachment in attachments) {
        await dbInsertMediaAttachment(db, <String, Object?>{
          ...attachment,
          'message_id': messageId,
        });
      }
      for (final row in blobRows) {
        expect(row.messageId, messageId);
        await db.insert(kDirectMediaBlobCustodyTable, row.toMap());
      }
      if (v108 != null) {
        await db.insert('direct_inbox_custody_outbox', <String, Object?>{
          'recipient_peer_id': recipient,
          'message_id': messageId,
          'incarnation_id':
              'e0e0e0e0e0e0e0e0e0e0e0e0'
              '${(++v108Seq).toRadixString(16).padLeft(8, '0')}',
          'wire_envelope': initialEnvelope(messageId),
          'retry_count': 0,
          'last_attempt_at': null,
          'last_error_code': null,
          'created_at': t0,
          'updated_at': t0,
          ...v108,
        });
      }
      return (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      )).single;
    }

    /// A complete two-row strict generation with DISTINCT commitments.
    ({
      List<Map<String, Object?>> attachments,
      List<DirectMediaBlobCustodyRow> blobRows,
      Map<String, Object?> v108,
      Map<String, String> lineage,
      List<String> attachmentIds,
    })
    strictGeneration({
      required String messageId,
      required DirectMediaBlobCustodyState state,
      String? incarnationId,
      bool fingerprinted = false,
      int attachmentCount = 2,
      int blobCount = 2,
      // Tied created_at makes the canonical order depend on the id tiebreak.
      String createdAt = t0,
    }) {
      final attachments = <Map<String, Object?>>[];
      final blobRows = <DirectMediaBlobCustodyRow>[];
      final manifest = <DirectMediaBlobManifestProjection>[];
      final lineage = <String, String>{};
      final attachmentIds = <String>[];
      for (var index = 0; index < attachmentCount; index++) {
        final attachmentId = '$messageId-${String.fromCharCode(97 + index)}';
        final contentHash = '${index + 1}' * 64;
        final ciphertextSize = 91 + index;
        final expiresAtMs = nowMs + 60000 + (index * 1000);
        attachmentIds.add(attachmentId);
        final commitment = DirectMediaBlobCustodyCommitment(
          contentHash: contentHash,
          ciphertextSize: ciphertextSize,
          expiresAtMs: expiresAtMs,
        );
        lineage[attachmentId] = computeDirectMediaBlobCommitmentFingerprint(
          attachmentId: attachmentId,
          commitment: commitment,
        );
        attachments.add(
          attachmentRow(
            messageId: messageId,
            attachmentId: attachmentId,
            contentHash: contentHash,
            createdAt: createdAt,
            fingerprint: fingerprinted ? lineage[attachmentId] : null,
          ),
        );
        if (index < blobCount) {
          blobRows.add(
            DirectMediaBlobCustodyRow(
              attachmentId: attachmentId,
              messageId: messageId,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: state,
              inboxCustodyIncarnationId: incarnationId,
              recipientPeerId: recipient,
              ciphertextRelativePath:
                  'direct_media_blob_custody_v1/${'a' * 64}/$attachmentId.blob',
              contentHash: contentHash,
              ciphertextSize: ciphertextSize,
              expiresAtMs: expiresAtMs,
              custodyRelayPeerId: 'relay-$index',
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: t0,
              updatedAt: t0,
            ),
          );
          manifest.add(
            DirectMediaBlobManifestProjection(
              attachmentId: attachmentId,
              commitment: commitment,
            ),
          );
        }
      }
      return (
        attachments: attachments,
        blobRows: blobRows,
        v108: <String, Object?>{
          'media_blob_manifest_hash': manifest.isEmpty
              ? null
              : computeDirectMediaBlobManifestHash(manifest),
          'media_blob_expires_at_ms': manifest.isEmpty
              ? null
              : earliestDirectMediaBlobExpiryMs(manifest),
        },
        lineage: lineage,
        attachmentIds: attachmentIds,
      );
    }

    Future<
      ({
        Map<String, Object?> message,
        List<Map<String, Object?>> attachments,
        List<Map<String, Object?>> v108,
        List<Map<String, Object?>> v111,
        List<Map<String, Object?>> v109,
      })
    >
    snapshot(String messageId) async => (
      message: (await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      )).single,
      attachments: await db.query(
        'media_attachments',
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
        orderBy: 'id ASC',
      ),
      v108: await db.query(
        'direct_inbox_custody_outbox',
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
      ),
      v111: await db.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
        orderBy: 'attachment_id ASC',
      ),
      v109: await db.query(kDirectReactionInboxCustodyOutboxTable),
    );

    /// The storage-reference expectations SQLite may see: the hydrated raw key
    /// is repository proof and never crosses this boundary.
    List<Map<String, Object?>> expectationsFrom(
      List<Map<String, Object?>> attachmentRows,
    ) => attachmentRows
        .map(
          (row) => <String, Object?>{
            'id': row['id'],
            'content_hash': row['content_hash'],
            'encryption_key_base64': row['encryption_key_base64'],
            'encryption_nonce': row['encryption_nonce'],
            'encryption_scheme': row['encryption_scheme'],
          },
        )
        .toList(growable: false);

    Future<DirectMediaCaptionEditCustodyDbStageResult> stageCaptionEdit(
      Map<String, Object?> current, {
      required String eventId,
      String caption = 'edited caption',
      String editedAt = t1,
      List<Map<String, Object?>>? expectedAttachmentRows,
      int capacity = kDirectReactionInboxCustodyOutboxCapacity,
      Future<void> Function()? beforeCustodyInsertForTest,
    }) async {
      final messageId = current['id']! as String;
      final envelope = editEnvelope(messageId, eventId);
      final projection = await dbLoadOutgoingDirectMediaCaptionEditProjection(
        db,
        messageId: messageId,
      );
      return dbStageOutgoingDirectMediaCaptionEditInboxCustody(
        db,
        expectedRow: current,
        stagedRow: captionEditOf(
          current,
          wireEnvelope: envelope,
          caption: caption,
          editedAt: editedAt,
        ),
        kind: OutgoingOrdinaryAttemptKind.edit,
        recipientPeerId: recipient,
        eventId: eventId,
        wireEnvelope: envelope,
        expectedAttachmentRows:
            expectedAttachmentRows ??
            expectationsFrom(projection.attachmentRows),
        capacity: capacity,
        beforeCustodyInsertForTest: beforeCustodyInsertForTest,
      );
    }

    test('TC-353-01b strict media caption edit stages lineage parent and '
        'raw-event v109 atomically', () async {
      // ---- Row 1: a text-only parent still belongs to Plan 349. ----
      final textParent = await seedMediaParent(
        'not-media',
        attachments: const [],
      );
      final textProjection =
          await dbLoadOutgoingDirectMediaCaptionEditProjection(
            db,
            messageId: textParent['id']! as String,
          );
      expect(textProjection.lane, OutgoingDirectMediaCaptionEditLane.notMedia);
      expect(textProjection.attachmentRows, isEmpty);

      // ---- Row 2: exact live manifest v108 + complete bound stored v111. ----
      final boundGeneration = strictGeneration(
        messageId: 'tc353-bound-live',
        state: DirectMediaBlobCustodyState.outgoingStored,
        incarnationId: 'e0e0e0e0e0e0e0e0e0e0e0e000000001',
      );
      final boundParent = await seedMediaParent(
        'bound-live',
        attachments: boundGeneration.attachments,
        blobRows: boundGeneration.blobRows,
        v108: <String, Object?>{
          ...boundGeneration.v108,
          'incarnation_id': 'e0e0e0e0e0e0e0e0e0e0e0e000000001',
        },
      );
      final boundId = boundParent['id']! as String;
      final boundBeforeV111 = (await snapshot(boundId)).v111;
      expect(
        (await dbLoadOutgoingDirectMediaCaptionEditProjection(
          db,
          messageId: boundId,
        )).lane,
        OutgoingDirectMediaCaptionEditLane.strictMedia,
      );
      final boundStage = await stageCaptionEdit(
        boundParent,
        eventId: nextEventId(),
      );
      expect(boundStage.outcome, OutgoingOrdinaryMutationOutcome.applied);
      expect(boundStage.ownsMutationEvent, isTrue);
      final boundAfter = await snapshot(boundId);
      expect(boundAfter.message['text'], 'edited caption');
      expect(boundAfter.message['edited_at'], t1);
      expect(boundAfter.message['status'], 'sending');
      expect(boundAfter.message['transport'], isNull);
      expect(boundAfter.message['relay_expires_at'], isNull);
      expect(boundAfter.message['custody_checked_at'], isNull);
      // Provable null-to-exact lineage is stamped in the same transaction.
      expect(<String, Object?>{
        for (final row in boundAfter.attachments)
          row['id']! as String: row['direct_media_blob_custody_fingerprint'],
      }, boundGeneration.lineage);
      // v111 stays byte-identical: the live blob owner is untouched.
      expect(boundAfter.v111, boundBeforeV111);
      expect(boundAfter.v108, hasLength(1));
      expect(boundAfter.v109, hasLength(1));

      // ---- Row 3: no v108 + complete cleanup-pending v111, all-null. ----
      final cleanupGeneration = strictGeneration(
        messageId: 'tc353-cleanup-complete',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
      );
      final cleanupParent = await seedMediaParent(
        'cleanup-complete',
        attachments: cleanupGeneration.attachments,
        blobRows: cleanupGeneration.blobRows,
      );
      final cleanupId = cleanupParent['id']! as String;
      final cleanupBeforeV111 = (await snapshot(cleanupId)).v111;
      expect(
        (await stageCaptionEdit(cleanupParent, eventId: nextEventId())).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final cleanupAfter = await snapshot(cleanupId);
      expect(<String, Object?>{
        for (final row in cleanupAfter.attachments)
          row['id']! as String: row['direct_media_blob_custody_fingerprint'],
      }, cleanupGeneration.lineage);
      expect(cleanupAfter.v111, cleanupBeforeV111);

      // ---- Row 4: cleanup-pending SUBSET with every fingerprint exact. ----
      final subsetGeneration = strictGeneration(
        messageId: 'tc353-cleanup-subset',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        fingerprinted: true,
        blobCount: 1,
      );
      final subsetParent = await seedMediaParent(
        'cleanup-subset',
        attachments: subsetGeneration.attachments,
        blobRows: subsetGeneration.blobRows,
      );
      final subsetId = subsetParent['id']! as String;
      final subsetBefore = await snapshot(subsetId);
      expect(
        (await stageCaptionEdit(subsetParent, eventId: nextEventId())).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final subsetAfter = await snapshot(subsetId);
      expect(subsetAfter.attachments, subsetBefore.attachments);
      expect(subsetAfter.v111, subsetBefore.v111);

      // ---- Row 5: fully drained, every fingerprint exact. ----
      final drainedGeneration = strictGeneration(
        messageId: 'tc353-drained',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        fingerprinted: true,
        blobCount: 0,
      );
      final drainedParent = await seedMediaParent(
        'drained',
        attachments: drainedGeneration.attachments,
      );
      final drainedId = drainedParent['id']! as String;
      final drainedBefore = await snapshot(drainedId);
      expect(
        (await stageCaptionEdit(drainedParent, eventId: nextEventId())).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );
      expect(
        (await snapshot(drainedId)).attachments,
        drainedBefore.attachments,
      );

      // ---- Row 6: historical all-null/no-v111 stays legacy, never promoted. ----
      final historicalGeneration = strictGeneration(
        messageId: 'tc353-historical',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        blobCount: 0,
      );
      for (final historical in <({String suffix, Map<String, Object?>? v108})>[
        (suffix: 'historical-no-v108', v108: null),
        (
          suffix: 'historical-unbound-v108',
          v108: const <String, Object?>{
            'media_blob_manifest_hash': null,
            'media_blob_expires_at_ms': null,
          },
        ),
      ]) {
        final parent = await seedMediaParent(
          historical.suffix,
          attachments: historicalGeneration.attachments,
          v108: historical.v108,
        );
        final id = parent['id']! as String;
        expect(
          (await dbLoadOutgoingDirectMediaCaptionEditProjection(
            db,
            messageId: id,
          )).lane,
          OutgoingDirectMediaCaptionEditLane.legacyMedia,
          reason: historical.suffix,
        );
        final before = await snapshot(id);
        expect(
          (await stageCaptionEdit(parent, eventId: nextEventId())).outcome,
          OutgoingOrdinaryMutationOutcome.refused,
          reason: historical.suffix,
        );
        final after = await snapshot(id);
        expect(after.message, before.message, reason: historical.suffix);
        expect(
          after.attachments,
          before.attachments,
          reason: '${historical.suffix} gains no lineage backfill',
        );
        expect(after.v109, before.v109, reason: historical.suffix);
      }

      // ---- Row 7: every contradiction fails closed and changes nothing. ----
      final contradictions =
          <
            String,
            ({
              List<Map<String, Object?>> attachments,
              List<DirectMediaBlobCustodyRow> blobRows,
              Map<String, Object?>? v108,
            })
          >{
            'mixed-fingerprints': (
              attachments: <Map<String, Object?>>[
                strictGeneration(
                  messageId: 'tc353-mixed-fingerprints',
                  state: DirectMediaBlobCustodyState.outgoingCleanupPending,
                  fingerprinted: true,
                  blobCount: 0,
                ).attachments.first,
                strictGeneration(
                  messageId: 'tc353-mixed-fingerprints',
                  state: DirectMediaBlobCustodyState.outgoingCleanupPending,
                  blobCount: 0,
                ).attachments.last,
              ],
              blobRows: const [],
              v108: null,
            ),
            'manifest-v108-without-any-v111': (
              attachments: strictGeneration(
                messageId: 'tc353-manifest-v108-without-any-v111',
                state: DirectMediaBlobCustodyState.outgoingCleanupPending,
                fingerprinted: true,
                blobCount: 0,
              ).attachments,
              blobRows: const [],
              v108: strictGeneration(
                messageId: 'tc353-manifest-v108-without-any-v111',
                state: DirectMediaBlobCustodyState.outgoingStored,
              ).v108,
            ),
            'active-unbound-v111': (
              attachments: strictGeneration(
                messageId: 'tc353-active-unbound-v111',
                state: DirectMediaBlobCustodyState.outgoingStored,
              ).attachments,
              blobRows: strictGeneration(
                messageId: 'tc353-active-unbound-v111',
                state: DirectMediaBlobCustodyState.outgoingStored,
              ).blobRows,
              v108: null,
            ),
            'incoming-direction-rows': (
              attachments: strictGeneration(
                messageId: 'tc353-incoming-direction-rows',
                state: DirectMediaBlobCustodyState.outgoingStored,
              ).attachments,
              blobRows:
                  strictGeneration(
                        messageId: 'tc353-incoming-direction-rows',
                        state: DirectMediaBlobCustodyState.outgoingStored,
                      ).blobRows
                      .map(
                        (row) => DirectMediaBlobCustodyRow(
                          attachmentId: row.attachmentId,
                          messageId: row.messageId,
                          direction: DirectMediaBlobCustodyDirection.incoming,
                          state: DirectMediaBlobCustodyState.incomingCommitted,
                          inboxCustodyIncarnationId: null,
                          recipientPeerId: null,
                          ciphertextRelativePath: null,
                          contentHash: row.contentHash,
                          ciphertextSize: row.ciphertextSize,
                          expiresAtMs: row.expiresAtMs,
                          custodyRelayPeerId: null,
                          lastAttemptAt: null,
                          nextAttemptAt: null,
                          createdAt: row.createdAt,
                          updatedAt: row.updatedAt,
                        ),
                      )
                      .toList(growable: false),
              v108: null,
            ),
            'partial-v111-under-live-v108': (
              attachments: strictGeneration(
                messageId: 'tc353-partial-v111-under-live-v108',
                state: DirectMediaBlobCustodyState.outgoingStored,
                incarnationId: 'e0e0e0e0e0e0e0e0e0e0e0e0000000ff',
              ).attachments,
              blobRows: strictGeneration(
                messageId: 'tc353-partial-v111-under-live-v108',
                state: DirectMediaBlobCustodyState.outgoingStored,
                incarnationId: 'e0e0e0e0e0e0e0e0e0e0e0e0000000ff',
                blobCount: 1,
              ).blobRows,
              v108: <String, Object?>{
                ...strictGeneration(
                  messageId: 'tc353-partial-v111-under-live-v108',
                  state: DirectMediaBlobCustodyState.outgoingStored,
                ).v108,
                'incarnation_id': 'e0e0e0e0e0e0e0e0e0e0e0e0000000ff',
              },
            ),
          };
      for (final entry in contradictions.entries) {
        final parent = await seedMediaParent(
          entry.key,
          attachments: entry.value.attachments,
          blobRows: entry.value.blobRows,
          v108: entry.value.v108,
        );
        final id = parent['id']! as String;
        expect(
          (await dbLoadOutgoingDirectMediaCaptionEditProjection(
            db,
            messageId: id,
          )).lane,
          OutgoingDirectMediaCaptionEditLane.contradiction,
          reason: entry.key,
        );
        final before = await snapshot(id);
        expect(
          (await stageCaptionEdit(parent, eventId: nextEventId())).outcome,
          OutgoingOrdinaryMutationOutcome.refused,
          reason: entry.key,
        );
        final after = await snapshot(id);
        expect(after.message, before.message, reason: entry.key);
        expect(after.attachments, before.attachments, reason: entry.key);
        expect(after.v111, before.v111, reason: entry.key);
        expect(after.v109, before.v109, reason: entry.key);
      }

      // Tightened Plan 351 contract: a manifest-bearing live v108 with no v111
      // stays a contradiction even once its attachments are fingerprinted.
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          db,
          messageId: 'tc353-manifest-v108-without-any-v111',
        ),
        OutgoingDirectDeletionLane.contradiction,
      );

      // ---- Canonical projection order: created_at ASC, id ASC. ----
      final tiedGeneration = strictGeneration(
        messageId: 'tc353-tied-order',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        fingerprinted: true,
        blobCount: 0,
      );
      final tiedParent = await seedMediaParent(
        'tied-order',
        attachments: <Map<String, Object?>>[
          tiedGeneration.attachments.last,
          tiedGeneration.attachments.first,
        ],
      );
      expect(
        (await dbLoadOutgoingDirectMediaCaptionEditProjection(
          db,
          messageId: tiedParent['id']! as String,
        )).attachmentRows.map((row) => row['id']).toList(),
        tiedGeneration.attachmentIds,
        reason: 'tied created_at resolves through the id tiebreak',
      );

      // ---- Exact replay of A after B never regresses the parent. ----
      final replayGeneration = strictGeneration(
        messageId: 'tc353-replay',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        fingerprinted: true,
        blobCount: 0,
      );
      final replayParent = await seedMediaParent(
        'replay',
        attachments: replayGeneration.attachments,
      );
      final replayId = replayParent['id']! as String;
      final eventA = nextEventId();
      final eventB = nextEventId();
      expect(
        (await stageCaptionEdit(
          replayParent,
          eventId: eventA,
          caption: 'caption A',
        )).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final afterA = (await snapshot(replayId)).message;
      expect(
        (await stageCaptionEdit(
          afterA,
          eventId: eventB,
          caption: 'caption B',
          editedAt: t2,
        )).outcome,
        OutgoingOrdinaryMutationOutcome.applied,
      );
      final afterB = (await snapshot(replayId)).message;
      expect(afterB['text'], 'caption B');
      final replayA = await stageCaptionEdit(
        replayParent,
        eventId: eventA,
        caption: 'caption A',
      );
      expect(replayA.outcome, OutgoingOrdinaryMutationOutcome.idempotent);
      expect(replayA.ownsMutationEvent, isTrue);
      expect(
        (await snapshot(replayId)).message,
        afterB,
        reason: 'replaying A must not regress the current parent',
      );

      // A DIFFERENT envelope under the same raw event id refuses atomically.
      final collisionEnvelope = editEnvelope(replayId, eventA);
      expect(
        (await dbStageOutgoingDirectMediaCaptionEditInboxCustody(
          db,
          expectedRow: afterB,
          stagedRow: captionEditOf(
            afterB,
            wireEnvelope: '$collisionEnvelope ',
            caption: 'forged caption',
            editedAt: t2,
          ),
          kind: OutgoingOrdinaryAttemptKind.edit,
          recipientPeerId: recipient,
          eventId: eventA,
          wireEnvelope: '$collisionEnvelope ',
          expectedAttachmentRows: expectationsFrom(
            replayGeneration.attachments,
          ),
        )).outcome,
        OutgoingOrdinaryMutationOutcome.refused,
      );
      expect((await snapshot(replayId)).message, afterB);

      // ---- Shared v109 capacity refusal changes nothing. ----
      final capacityGeneration = strictGeneration(
        messageId: 'tc353-capacity',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        fingerprinted: true,
        blobCount: 0,
      );
      final capacityParent = await seedMediaParent(
        'capacity',
        attachments: capacityGeneration.attachments,
      );
      final capacityBefore = await snapshot(capacityParent['id']! as String);
      expect(
        (await stageCaptionEdit(
          capacityParent,
          eventId: nextEventId(),
          capacity: 0,
        )).outcome,
        OutgoingOrdinaryMutationOutcome.refused,
      );
      final capacityAfter = await snapshot(capacityParent['id']! as String);
      expect(capacityAfter.message, capacityBefore.message);
      expect(capacityAfter.attachments, capacityBefore.attachments);

      // ---- Drifted secure-storage expectations refuse before any write. ----
      final driftGeneration = strictGeneration(
        messageId: 'tc353-key-drift',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        fingerprinted: true,
        blobCount: 0,
      );
      final driftParent = await seedMediaParent(
        'key-drift',
        attachments: driftGeneration.attachments,
      );
      final driftBefore = await snapshot(driftParent['id']! as String);
      expect(
        (await stageCaptionEdit(
          driftParent,
          eventId: nextEventId(),
          expectedAttachmentRows: expectationsFrom(driftGeneration.attachments)
              .map(
                (row) => <String, Object?>{
                  ...row,
                  'encryption_nonce': 'drifted-nonce',
                },
              )
              .toList(growable: false),
        )).outcome,
        OutgoingOrdinaryMutationOutcome.refused,
      );
      final driftAfter = await snapshot(driftParent['id']! as String);
      expect(driftAfter.message, driftBefore.message);
      expect(driftAfter.v109, driftBefore.v109);

      // ---- A late v109 insert abort rolls back parent AND lineage. ----
      final abortGeneration = strictGeneration(
        messageId: 'tc353-late-abort',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
      );
      final abortParent = await seedMediaParent(
        'late-abort',
        attachments: abortGeneration.attachments,
        blobRows: abortGeneration.blobRows,
      );
      final abortId = abortParent['id']! as String;
      final abortBefore = await snapshot(abortId);
      await expectLater(
        stageCaptionEdit(
          abortParent,
          eventId: nextEventId(),
          // The barrier stands in for a lost late CAS or an aborted v109
          // insert: it fires AFTER the parent projection and the lineage
          // stamps, so only a single shared transaction can roll both back.
          beforeCustodyInsertForTest: () async =>
              throw StateError('late v109 insert failure'),
        ),
        throwsA(isA<StateError>()),
      );
      final abortAfter = await snapshot(abortId);
      expect(abortAfter.message, abortBefore.message);
      expect(
        abortAfter.attachments,
        abortBefore.attachments,
        reason: 'a late abort rolls the lineage stamps back too',
      );
      expect(abortAfter.v111, abortBefore.v111);
    });

    /// One incoming strict parent with hydrated attachments, all-exact
    /// fingerprints and an optional incoming v111 subset.
    Future<({String messageId, List<Map<String, Object?>> attachments})>
    seedIncomingStrictParent(
      String suffix, {
      DirectMediaBlobCustodyState? v111State,
      int v111Count = 2,
      bool fingerprinted = true,
      String? deletedAt,
      int isIncoming = 1,
    }) async {
      final messageId = 'tc353-in-$suffix';
      final generation = strictGeneration(
        messageId: messageId,
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        fingerprinted: fingerprinted,
        blobCount: 0,
      );
      await db.insert('messages', <String, Object?>{
        ...ConversationMessage(
          id: messageId,
          contactPeerId: sender,
          senderPeerId: sender,
          text: 'original caption',
          timestamp: t0,
          status: 'delivered',
          isIncoming: isIncoming == 1,
          createdAt: t0,
          transport: 'inbox',
          dedupKey: messageId,
        ).toMap(),
        if (deletedAt != null) ...<String, Object?>{
          'text': '',
          'deleted_at': deletedAt,
          'deleted_by_peer_id': sender,
        },
      });
      for (final attachment in generation.attachments) {
        await dbInsertMediaAttachment(db, attachment);
      }
      if (v111State != null) {
        for (var index = 0; index < v111Count; index++) {
          final attachmentId = generation.attachmentIds[index];
          await db.insert(
            kDirectMediaBlobCustodyTable,
            DirectMediaBlobCustodyRow(
              attachmentId: attachmentId,
              messageId: messageId,
              direction: DirectMediaBlobCustodyDirection.incoming,
              state: v111State,
              inboxCustodyIncarnationId: null,
              recipientPeerId: null,
              ciphertextRelativePath: null,
              contentHash: '${index + 1}' * 64,
              ciphertextSize: 91 + index,
              expiresAtMs: nowMs + 60000 + (index * 1000),
              custodyRelayPeerId:
                  v111State == DirectMediaBlobCustodyState.incomingAckPending
                  ? 'relay-ack-$index'
                  : null,
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: t0,
              updatedAt: t0,
            ).toMap(),
          );
        }
      }
      return (
        messageId: messageId,
        attachments: (await db.query(
          'media_attachments',
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
          orderBy: 'id ASC',
        )),
      );
    }

    Future<IncomingDirectMediaCaptionEditDbResult> applyIncoming(
      ({String messageId, List<Map<String, Object?>> attachments}) seeded, {
      String caption = 'edited caption',
      String editedAt = t1,
      List<Map<String, Object?>>? expectedAttachmentRows,
      Map<String, Object?> identityOverrides = const <String, Object?>{},
    }) => dbApplyIncomingDirectMediaCaptionEdit(
      db,
      expectedParentIdentity: <String, Object?>{
        'id': seeded.messageId,
        'sender_peer_id': sender,
        'contact_peer_id': sender,
        'timestamp': t0,
        'quoted_message_id': null,
        'dedup_key': seeded.messageId,
        'is_forwarded': 0,
        ...identityOverrides,
      },
      expectedAttachmentRows:
          expectedAttachmentRows ?? expectationsFrom(seeded.attachments),
      text: caption,
      editedAt: editedAt,
    );

    test('TC-353-04 incoming strict media caption edit applies atomically over '
        'the exact descriptor set', () async {
      // 1. Accepted authority: absent v111, exact incomingCommitted subset and
      //    exact incomingAckPending subset.
      for (final accepted
          in <({String suffix, DirectMediaBlobCustodyState? state, int count})>[
            (suffix: 'no-v111', state: null, count: 0),
            (
              suffix: 'committed',
              state: DirectMediaBlobCustodyState.incomingCommitted,
              count: 2,
            ),
            (
              suffix: 'ack-pending-subset',
              state: DirectMediaBlobCustodyState.incomingAckPending,
              count: 1,
            ),
          ]) {
        final seeded = await seedIncomingStrictParent(
          accepted.suffix,
          v111State: accepted.state,
          v111Count: accepted.count,
        );
        final before = await snapshot(seeded.messageId);
        final applied = await applyIncoming(seeded);
        expect(
          applied.outcome,
          IncomingDirectMediaCaptionEditOutcome.applied,
          reason: accepted.suffix,
        );
        final after = await snapshot(seeded.messageId);
        expect(after.message['text'], 'edited caption');
        expect(after.message['edited_at'], t1);
        // Only text and editedAt move; every other parent field is preserved.
        expect(
          <String, Object?>{
            ...after.message,
            'text': before.message['text'],
            'edited_at': before.message['edited_at'],
          },
          before.message,
          reason: accepted.suffix,
        );
        expect(
          after.attachments,
          before.attachments,
          reason: '${accepted.suffix} must never rewrite attachments',
        );
        expect(after.v111, before.v111, reason: accepted.suffix);

        // Exact replay is durable, not a second write.
        expect(
          (await applyIncoming(seeded)).outcome,
          IncomingDirectMediaCaptionEditOutcome.durableReplay,
          reason: accepted.suffix,
        );
      }

      // 2. A live all-null/no-v111 legacy parent resumes the generic path.
      final legacy = await seedIncomingStrictParent(
        'legacy',
        fingerprinted: false,
      );
      final legacyBefore = await snapshot(legacy.messageId);
      expect(
        (await applyIncoming(legacy)).outcome,
        IncomingDirectMediaCaptionEditOutcome.legacyParent,
      );
      expect((await snapshot(legacy.messageId)).message, legacyBefore.message);

      // 3. An author tombstone is durable supersession without attachments.
      final tombstoned = await seedIncomingStrictParent(
        'tombstone',
        deletedAt: t1,
      );
      final tombstoneBefore = await snapshot(tombstoned.messageId);
      expect(
        (await applyIncoming(tombstoned)).outcome,
        IncomingDirectMediaCaptionEditOutcome.superseded,
      );
      expect(
        (await snapshot(tombstoned.messageId)).message,
        tombstoneBefore.message,
      );

      // 4. A stale edit is validated supersession; a newer one still applies.
      final ordered = await seedIncomingStrictParent('ordering');
      expect(
        (await applyIncoming(ordered, caption: 'first', editedAt: t1)).outcome,
        IncomingDirectMediaCaptionEditOutcome.applied,
      );
      expect(
        (await applyIncoming(ordered, caption: 'stale', editedAt: t0)).outcome,
        IncomingDirectMediaCaptionEditOutcome.superseded,
      );
      expect((await snapshot(ordered.messageId)).message['text'], 'first');
      expect(
        (await applyIncoming(ordered, caption: 'newest', editedAt: t2)).outcome,
        IncomingDirectMediaCaptionEditOutcome.applied,
      );
      expect((await snapshot(ordered.messageId)).message['text'], 'newest');

      // 5. Refusals: mixed fingerprints, crossed descriptors, missing/extra
      //    descriptors, outgoing v111 direction, and wrong-direction parents.
      final refusals =
          <String, Future<IncomingDirectMediaCaptionEditDbResult> Function()>{};

      final mixed = await seedIncomingStrictParent('mixed', v111State: null);
      await db.update(
        'media_attachments',
        const <String, Object?>{'direct_media_blob_custody_fingerprint': null},
        where: 'id = ?',
        whereArgs: <Object?>[mixed.attachments.first['id']],
      );
      refusals['mixed fingerprints'] = () => applyIncoming(mixed);

      final crossed = await seedIncomingStrictParent('crossed-descriptor');
      refusals['crossed descriptor'] = () => applyIncoming(
        crossed,
        expectedAttachmentRows: expectationsFrom(crossed.attachments)
            .map((row) => <String, Object?>{...row, 'content_hash': '9' * 64})
            .toList(growable: false),
      );

      final missing = await seedIncomingStrictParent('missing-descriptor');
      refusals['missing descriptor'] = () => applyIncoming(
        missing,
        expectedAttachmentRows: expectationsFrom(
          missing.attachments,
        ).take(1).toList(growable: false),
      );

      final extra = await seedIncomingStrictParent('extra-descriptor');
      refusals['extra descriptor'] = () => applyIncoming(
        extra,
        expectedAttachmentRows: <Map<String, Object?>>[
          ...expectationsFrom(extra.attachments),
          <String, Object?>{
            'id': 'ghost',
            'content_hash': '3' * 64,
            'encryption_key_base64': 'ref',
            'encryption_nonce': 'nonce-ghost',
            'encryption_scheme': 'blob_aes_256_gcm_v1',
          },
        ],
      );

      final outgoingV111 = await seedIncomingStrictParent('outgoing-v111');
      await db.insert(
        kDirectMediaBlobCustodyTable,
        DirectMediaBlobCustodyRow(
          attachmentId: outgoingV111.attachments.first['id']! as String,
          messageId: outgoingV111.messageId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingStored,
          inboxCustodyIncarnationId: null,
          recipientPeerId: recipient,
          ciphertextRelativePath:
              'direct_media_blob_custody_v1/${'a' * 64}/x.blob',
          contentHash: '1' * 64,
          ciphertextSize: 91,
          expiresAtMs: nowMs + 60000,
          custodyRelayPeerId: 'relay-outgoing',
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: t0,
          updatedAt: t0,
        ).toMap(),
      );
      refusals['outgoing v111 direction'] = () => applyIncoming(outgoingV111);

      final wrongDirection = await seedIncomingStrictParent(
        'outgoing-parent',
        isIncoming: 0,
      );
      refusals['outgoing parent'] = () => applyIncoming(wrongDirection);

      final crossedAuthor = await seedIncomingStrictParent('crossed-author');
      refusals['crossed author'] = () => applyIncoming(
        crossedAuthor,
        identityOverrides: const <String, Object?>{
          'sender_peer_id': 'peer-impostor',
        },
      );

      for (final entry in refusals.entries) {
        final result = await entry.value();
        expect(
          result.outcome,
          IncomingDirectMediaCaptionEditOutcome.refused,
          reason: entry.key,
        );
      }
    });
  });
}
