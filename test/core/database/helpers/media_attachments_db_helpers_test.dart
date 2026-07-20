import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';

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
      final rows = await dbLoadMediaForMessage(db, 'nonexistent', ownerLane: 'direct');
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

      final rows = await dbLoadMediaForMessage(db, 'msg-A', ownerLane: 'direct');
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

      final rows = await dbLoadMediaForMessages(db, ['msg-A', 'msg-B'], ownerLane: 'direct');
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

      final rows = await dbLoadMediaForMessages(db, ['msg-A'], ownerLane: 'direct');
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

      final count = await dbDeleteMediaForMessage(db, 'msg-A', ownerLane: 'direct');
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
      final count = await dbDeleteMediaForMessage(db, 'nonexistent', ownerLane: 'direct');
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

    test(
      'owner scoped load and delete isolate equal direct and group message '
      'ids',
      () async {
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
        final directMulti = await dbLoadMediaForMessages(
          db,
          ['msg-shared'],
          ownerLane: 'direct',
        );
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
      },
    );

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

    test(
      'upload pending load filters owner in SQL before the limit',
      () async {
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
        expect(
          groupPending.every((r) => r['owner_lane'] == 'group'),
          isTrue,
        );

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
      },
    );
  });
}
