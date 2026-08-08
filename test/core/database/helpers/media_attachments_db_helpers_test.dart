import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

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
}
