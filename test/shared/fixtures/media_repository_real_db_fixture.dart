import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';

import '../../core/secure_storage/fake_secure_key_store.dart';

/// [FakeSecureKeyStore] that records every write, so tests can prove a
/// rejected save produced NO secure-store mutation (TC-228-04K).
class RecordingSecureKeyStore extends FakeSecureKeyStore {
  final List<String> writtenKeys = [];

  @override
  Future<void> write(String key, String value) async {
    writtenKeys.add(key);
    await super.write(key, value);
  }
}

/// Real-database repository fixture (228): a [MediaAttachmentRepositoryImpl]
/// wired over an in-memory sqflite FFI database built through the SHARED
/// production registry at the CURRENT schema version — never a hand-rolled
/// schema that can drift from main.dart.
class MediaRepositoryRealDbFixture {
  MediaRepositoryRealDbFixture._(this.db, this.repo, this.secureKeyStore);

  final Database db;
  final MediaAttachmentRepositoryImpl repo;
  final RecordingSecureKeyStore secureKeyStore;

  static Future<MediaRepositoryRealDbFixture> create() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    final secureKeyStore = RecordingSecureKeyStore();
    final repo = MediaAttachmentRepositoryImpl(
      dbSaveMediaAttachmentPreservingLocalState: (row) =>
          dbSaveMediaAttachmentPreservingLocalState(db, row),
      dbLoadMediaForMessage: (messageId, ownerLane) =>
          dbLoadMediaForMessage(db, messageId, ownerLane: ownerLane),
      dbLoadMediaById: (id) => dbLoadMediaById(db, id),
      dbLoadMediaForMessages: (messageIds, ownerLane) =>
          dbLoadMediaForMessages(db, messageIds, ownerLane: ownerLane),
      dbUpdateMediaLocalPath: (id, localPath, downloadStatus) =>
          dbUpdateMediaLocalPath(db, id, localPath, downloadStatus),
      dbUpdateMediaDownloadStatus: (id, downloadStatus) =>
          dbUpdateMediaDownloadStatus(db, id, downloadStatus),
      dbDeleteMediaForMessage: (messageId, ownerLane) =>
          dbDeleteMediaForMessage(db, messageId, ownerLane: ownerLane),
      dbDeleteMediaForContact: (contactPeerId) =>
          dbDeleteMediaForContact(db, contactPeerId),
      dbMarkUploadPendingAttachmentsFailedForMessage: (messageId, ownerLane) =>
          dbMarkUploadPendingAttachmentsFailedForMessage(
            db,
            messageId,
            ownerLane: ownerLane,
          ),
      dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
      dbLoadUploadPendingAttachments: ({int limit = 50, required String ownerLane}) =>
          dbLoadUploadPendingAttachments(db, limit: limit, ownerLane: ownerLane),
      dbSetMediaBookmarked: (id, bookmarked) =>
          dbSetMediaBookmarked(db, id, bookmarked: bookmarked),
      dbUpdateMediaPlaybackPosition: (id, positionMs) =>
          dbUpdateMediaPlaybackPosition(db, id, positionMs),
      dbLoadMediaLibraryPage:
          ({
            required String scopeKind,
            required String scopeId,
            required List<String> mediaTypes,
            required bool bookmarkedOnly,
            required int limit,
            String? afterTimestamp,
            String? afterMessageId,
            String? afterAttachmentId,
          }) => dbLoadMediaLibraryPage(
            db,
            scopeKind: scopeKind,
            scopeId: scopeId,
            mediaTypes: mediaTypes,
            bookmarkedOnly: bookmarkedOnly,
            limit: limit,
            afterTimestamp: afterTimestamp,
            afterMessageId: afterMessageId,
            afterAttachmentId: afterAttachmentId,
          ),
      dbLoadMediaStoragePage:
          ({
            required String scopeKind,
            required String scopeId,
            required List<String> mediaTypes,
            required int limit,
            String? afterTimestamp,
            String? afterMessageId,
            String? afterAttachmentId,
          }) => dbLoadMediaStoragePage(
            db,
            scopeKind: scopeKind,
            scopeId: scopeId,
            mediaTypes: mediaTypes,
            limit: limit,
            afterTimestamp: afterTimestamp,
            afterMessageId: afterMessageId,
            afterAttachmentId: afterAttachmentId,
          ),
      dbBeginMediaDownload: (id, {required String ownerLane}) =>
          dbBeginMediaDownload(db, id, ownerLane: ownerLane),
      dbCommitMediaDownloadLocalPath:
          (id, {required String ownerLane, required String localPath}) =>
              dbCommitMediaDownloadLocalPath(
                db,
                id,
                ownerLane: ownerLane,
                localPath: localPath,
              ),
      dbClaimMediaEvicted:
          (
            id, {
            required String ownerLane,
            required String expectedLocalPath,
          }) => dbClaimMediaEvicted(
            db,
            id,
            ownerLane: ownerLane,
            expectedLocalPath: expectedLocalPath,
          ),
      dbFinalizeMediaEvictedPathCleared: (id, {required String ownerLane}) =>
          dbFinalizeMediaEvictedPathCleared(db, id, ownerLane: ownerLane),
      secureKeyStore: secureKeyStore,
    );
    return MediaRepositoryRealDbFixture._(db, repo, secureKeyStore);
  }

  /// Inserts a live direct parent row into `messages`.
  Future<void> seedDirectParent(
    String id, {
    String contactPeerId = 'contact-1',
    String timestamp = '2026-07-01T00:00:00.000Z',
    String? hiddenAt,
    String? deletedAt,
  }) async {
    await db.insert('messages', {
      'id': id,
      'contact_peer_id': contactPeerId,
      'sender_peer_id': contactPeerId,
      'text': 'direct parent $id',
      'timestamp': timestamp,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': timestamp,
      if (hiddenAt != null) 'hidden_at': hiddenAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    });
  }

  /// Inserts a live group parent row into `group_messages`.
  Future<void> seedGroupParent(
    String id, {
    String groupId = 'group-1',
    String timestamp = '2026-07-01T00:00:00.000Z',
  }) async {
    await db.insert('group_messages', {
      'id': id,
      'group_id': groupId,
      'sender_peer_id': 'peer-g',
      'sender_username': 'GroupSender',
      'text': 'group parent $id',
      'timestamp': timestamp,
      'key_generation': 0,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': timestamp,
    });
  }

  /// Raw row lookup bypassing the repository (no hydration).
  Future<Map<String, Object?>?> rawAttachmentRow(String id) async {
    final rows = await db.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> dispose() => db.close();
}
