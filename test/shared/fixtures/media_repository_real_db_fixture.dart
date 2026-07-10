import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

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
/// wired over a sqflite FFI database built through the SHARED production
/// registry at the CURRENT schema version — in-memory by default, or
/// file-backed when a test must prove a real close/reopen. It is never a
/// hand-rolled schema that can drift from main.dart.
class MediaRepositoryRealDbFixture {
  MediaRepositoryRealDbFixture._(
    this.db,
    this.repo,
    this.messageRepo,
    this.secureKeyStore,
    this.databasePath,
  );

  final Database db;
  final MediaAttachmentRepositoryImpl repo;
  final MessageRepositoryImpl messageRepo;
  final RecordingSecureKeyStore secureKeyStore;
  final String databasePath;

  static Future<MediaRepositoryRealDbFixture> create({
    String databasePath = inMemoryDatabasePath,
    RecordingSecureKeyStore? secureKeyStore,
  }) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    final effectiveSecureKeyStore = secureKeyStore ?? RecordingSecureKeyStore();
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
      dbLoadUploadPendingAttachments:
          ({int limit = 50, required String ownerLane}) =>
              dbLoadUploadPendingAttachments(
                db,
                limit: limit,
                ownerLane: ownerLane,
              ),
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
            required bool incomingOnly,
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
            incomingOnly: incomingOnly,
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
      secureKeyStore: effectiveSecureKeyStore,
    );
    return MediaRepositoryRealDbFixture._(
      db,
      repo,
      _buildMessageRepository(db),
      effectiveSecureKeyStore,
      databasePath,
    );
  }

  /// Closes and reopens a file-backed fixture with fresh repository objects.
  ///
  /// The secure store is intentionally retained: production secure storage
  /// outlives a SQLite handle, while the repository and database handle do not.
  Future<MediaRepositoryRealDbFixture> reopen() async {
    if (databasePath == inMemoryDatabasePath) {
      throw StateError('A file-backed database path is required for reopen');
    }
    await dispose();
    return create(databasePath: databasePath, secureKeyStore: secureKeyStore);
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

MessageRepositoryImpl _buildMessageRepository(Database db) {
  return MessageRepositoryImpl(
    dbInsertMessage: (row) => dbInsertMessage(db, row),
    dbLoadMessagesForContact: (contactPeerId) =>
        dbLoadMessagesForContact(db, contactPeerId),
    dbLoadLatestMessageForContact: (contactPeerId) =>
        dbLoadLatestMessageForContact(db, contactPeerId),
    dbUpdateMessageStatus: (id, status) =>
        dbUpdateMessageStatus(db, id, status),
    dbLoadMessage: (id) => dbLoadMessage(db, id),
    dbCountMessagesForContact: (contactPeerId) =>
        dbCountMessagesForContact(db, contactPeerId),
    dbMarkConversationAsRead: (contactPeerId) =>
        dbMarkConversationAsRead(db, contactPeerId),
    dbCountUnreadForContact: (contactPeerId) =>
        dbCountUnreadForContact(db, contactPeerId),
    dbCountTotalUnread: () => dbCountTotalUnread(db),
    dbCountTotalUnreadExcludingArchived: () =>
        dbCountTotalUnreadExcludingArchived(db),
    dbDeleteMessagesForContact: (contactPeerId) =>
        dbDeleteMessagesForContact(db, contactPeerId),
    dbDeleteMessage: (id) => dbDeleteMessage(db, id),
    dbExistsMessageByContent: (contactPeerId, senderPeerId, text, timestamp) =>
        dbExistsMessageByContent(
          db,
          contactPeerId,
          senderPeerId,
          text,
          timestamp,
        ),
    dbExistsMessageByDedupKey: (contactPeerId, senderPeerId, dedupKey) =>
        dbExistsMessageByDedupKey(db, contactPeerId, senderPeerId, dedupKey),
    dbLoadMessagesPage: (contactPeerId, {limit = 50, beforeTimestamp}) =>
        dbLoadMessagesPage(
          db,
          contactPeerId,
          limit: limit,
          beforeTimestamp: beforeTimestamp,
        ),
    dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
    dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
        dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
    dbLoadConversationThreadSummaries: (contactPeerIds) =>
        dbLoadConversationThreadSummaries(db, contactPeerIds),
    dbRecoverStuckSendingMessages: ({required olderThan, limit = 50}) =>
        dbRecoverStuckSendingMessages(db, olderThan: olderThan, limit: limit),
    dbUpdateWireEnvelope: (id, wireEnvelope) =>
        dbUpdateWireEnvelope(db, id, wireEnvelope),
    dbLoadStuckSendingOutgoingMessages: ({required olderThan, limit = 50}) =>
        dbLoadStuckSendingOutgoingMessages(
          db,
          olderThan: olderThan,
          limit: limit,
        ),
    dbLoadSendingOutgoingMessages: () => dbLoadSendingOutgoingMessages(db),
    dbConditionalTransitionStatus:
        (id, {required fromStatus, required toStatus}) =>
            dbConditionalTransitionStatus(
              db,
              id,
              fromStatus: fromStatus,
              toStatus: toStatus,
            ),
    dbLoadInboxCustodyOutgoingMessages:
        ({required recheckOlderThan, limit = 50}) =>
            dbLoadInboxCustodyOutgoingMessages(
              db,
              recheckOlderThan: recheckOlderThan,
              limit: limit,
            ),
    dbMarkInboxCustodyChecked: (id, {relayExpiresAtMs}) =>
        dbMarkInboxCustodyChecked(db, id, relayExpiresAtMs: relayExpiresAtMs),
  );
}
