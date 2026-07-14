import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

enum GroupPrivateCleanupFailurePoint { none, keyDelete, rowDelete }

class FailOnceGroupPrivateMediaFileManager extends FakeMediaFileManager {
  bool failNextDelete = true;

  @override
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {
    if (failNextDelete) {
      failNextDelete = false;
      throw FileSystemException('injected group cleanup failure', localPath);
    }
    return super.deleteFile(
      localPath,
      caller: caller,
      reason: reason,
      storedPath: storedPath,
      details: details,
      redactTelemetry: redactTelemetry,
    );
  }
}

class GroupPrivateMediaSeededAttachment {
  const GroupPrivateMediaSeededAttachment({
    required this.attachment,
    required this.relativePath,
    required this.absolutePath,
  });

  final MediaAttachment attachment;
  final String relativePath;
  final String absolutePath;
}

/// Current-schema, production-repository fixture for Plan 238 lifecycle tests.
///
/// The broad attachment repository is the production implementation from
/// [MediaRepositoryRealDbFixture]. The narrow cleanup seam below delegates to
/// the same production SQL helpers while allowing one injected crash boundary.
class GroupPrivateMediaLifecycleTestFixture {
  GroupPrivateMediaLifecycleTestFixture._({
    required this.mediaFixture,
    required this.messageRepository,
    required this.cleanupRepository,
    required this.mediaFileManager,
    required this.nowMs,
  }) {
    engine = GroupPrivateMediaLifecycleEngine(
      messageRepository: messageRepository,
      mediaAttachmentRepository: mediaFixture.repo,
      cleanupRepository: cleanupRepository,
      mediaFileManager: mediaFileManager,
      lifecycleLock: mediaFixture.repo.lifecycleLock,
      nowMs: () => nowMs,
    );
  }

  final MediaRepositoryRealDbFixture mediaFixture;
  final GroupMessageRepositoryImpl messageRepository;
  final TestGroupPrivateMediaCleanupRepository cleanupRepository;
  final FakeMediaFileManager mediaFileManager;
  int nowMs;
  late final GroupPrivateMediaLifecycleEngine engine;
  final Set<String> _ownedPaths = <String>{};

  Database get db => mediaFixture.db;

  static Future<GroupPrivateMediaLifecycleTestFixture> create({
    String databasePath = inMemoryDatabasePath,
    int nowMs = 1000,
    FakeMediaFileManager? mediaFileManager,
    GroupPrivateCleanupFailurePoint cleanupFailure =
        GroupPrivateCleanupFailurePoint.none,
  }) async {
    final mediaFixture = await MediaRepositoryRealDbFixture.create(
      databasePath: databasePath,
    );
    return _fromMediaFixture(
      mediaFixture,
      nowMs: nowMs,
      mediaFileManager: mediaFileManager ?? FakeMediaFileManager(),
      cleanupFailure: cleanupFailure,
    );
  }

  static GroupPrivateMediaLifecycleTestFixture _fromMediaFixture(
    MediaRepositoryRealDbFixture mediaFixture, {
    required int nowMs,
    required FakeMediaFileManager mediaFileManager,
    required GroupPrivateCleanupFailurePoint cleanupFailure,
  }) {
    final messageRepository = _buildGroupMessageRepository(mediaFixture.db);
    return GroupPrivateMediaLifecycleTestFixture._(
      mediaFixture: mediaFixture,
      messageRepository: messageRepository,
      cleanupRepository: TestGroupPrivateMediaCleanupRepository(
        mediaFixture.db,
        mediaFixture.secureKeyStore,
        failurePoint: cleanupFailure,
      ),
      mediaFileManager: mediaFileManager,
      nowMs: nowMs,
    );
  }

  Future<GroupPrivateMediaLifecycleTestFixture> reopen({
    FakeMediaFileManager? mediaFileManager,
    GroupPrivateCleanupFailurePoint cleanupFailure =
        GroupPrivateCleanupFailurePoint.none,
  }) async {
    final reopened = await mediaFixture.reopen();
    final fresh = _fromMediaFixture(
      reopened,
      nowMs: nowMs,
      mediaFileManager: mediaFileManager ?? FakeMediaFileManager(),
      cleanupFailure: cleanupFailure,
    );
    fresh._ownedPaths.addAll(_ownedPaths);
    return fresh;
  }

  Future<void> seedParent({
    required String messageId,
    required GroupPrivateMediaPolicy policy,
    String groupId = 'group-1',
    bool isIncoming = true,
    int? receivedAt,
    int? expiresAt,
    int? lastCheckedAt,
    int? consumedAt,
    int? expiredAt,
    bool cleanupPending = false,
    String timestamp = '2026-01-01T00:00:00.000Z',
  }) async {
    await mediaFixture.seedGroupParent(
      messageId,
      groupId: groupId,
      timestamp: timestamp,
    );
    await db.update(
      'group_messages',
      <String, Object?>{
        ...policy.toDatabaseMap(),
        'is_incoming': isIncoming ? 1 : 0,
        'media_received_at': receivedAt,
        'media_expires_at': expiresAt,
        'media_last_checked_at': lastCheckedAt,
        'media_consumed_at': consumedAt,
        'media_expired_at': expiredAt,
        'media_cleanup_pending': cleanupPending ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
    );
  }

  Future<GroupPrivateMediaSeededAttachment> seedAttachment({
    required String messageId,
    required String attachmentId,
    String groupId = 'group-1',
    String mime = 'image/jpeg',
    List<int> bytes = const <int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10],
    String downloadStatus = kMediaDownloadStatusDone,
    String? localPath,
    bool includeLocalPath = true,
    String? contentHash,
    bool createCanonicalFile = true,
    bool isBookmarked = false,
    int lastPlaybackPositionMs = 0,
  }) async {
    final relativePath = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: groupId,
      blobId: attachmentId,
      mime: mime,
    );
    final absolutePath = p.join(
      FakeMediaFileManager.testRootPath,
      relativePath,
    );
    if (createCanonicalFile) {
      final file = File(absolutePath);
      file.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      _ownedPaths.add(absolutePath);
    }
    final attachment = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: mime,
      size: bytes.length,
      mediaType: mime.startsWith('video/') ? 'video' : 'image',
      localPath: includeLocalPath ? (localPath ?? relativePath) : null,
      downloadStatus: downloadStatus,
      createdAt: '2026-07-12T00:00:00.000Z',
      // Relay contentHash authenticates ciphertext, never this canonical
      // plaintext fixture. Keep the domains deliberately distinct.
      contentHash:
          contentHash ?? sha256.convert(<int>[...bytes, 0xa5]).toString(),
      encryptionKeyBase64: 'cGxhbi0yMzgtc2VlZC1rZXk=',
      encryptionNonce: 'cGxhbi0yMzgtbm9uY2U=',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      isBookmarked: isBookmarked,
      lastPlaybackPositionMs: lastPlaybackPositionMs,
    );
    await mediaFixture.repo.saveAttachment(
      attachment,
      owner: MediaOwnerLane.group,
    );
    return GroupPrivateMediaSeededAttachment(
      attachment: attachment,
      relativePath: relativePath,
      absolutePath: absolutePath,
    );
  }

  Future<Map<String, Object?>?> rawParent(String messageId) async {
    final rows = await db.query(
      'group_messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> dispose() async {
    try {
      await mediaFixture.dispose();
    } catch (_) {}
    for (final path in _ownedPaths) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }
}

class TestGroupPrivateMediaCleanupRepository
    implements GroupPrivateMediaCleanupRepository {
  TestGroupPrivateMediaCleanupRepository(
    this.db,
    this.secureKeyStore, {
    this.failurePoint = GroupPrivateCleanupFailurePoint.none,
  });

  final Database db;
  final RecordingSecureKeyStore secureKeyStore;
  final GroupPrivateCleanupFailurePoint failurePoint;
  bool _failed = false;
  int keyDeleteCalls = 0;
  int rowDeleteCalls = 0;

  bool _shouldFail(GroupPrivateCleanupFailurePoint point) {
    if (!_failed && failurePoint == point) {
      _failed = true;
      return true;
    }
    return false;
  }

  @override
  Future<List<GroupPrivateMediaLifecycleAttachmentMetadata>>
  loadGroupPrivateMediaLifecycleAttachmentMetadata(String messageId) async {
    final rows = await dbLoadMediaForMessage(
      db,
      messageId,
      ownerLane: MediaOwnerLane.group.dbValue,
    );
    return rows
        .map(
          (row) => GroupPrivateMediaLifecycleAttachmentMetadata(
            id: row['id'] as String,
            messageId: row['message_id'] as String,
            mime: row['mime'] as String,
            size: (row['size'] as num).toInt(),
            downloadStatus: row['download_status'] as String,
            localPath: row['local_path'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> deleteGroupPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  }) async {
    keyDeleteCalls++;
    if (_shouldFail(GroupPrivateCleanupFailurePoint.keyDelete)) {
      throw StateError('injected key-delete crash');
    }
    if (!await dbCanCleanupGroupPrivateMediaAttachmentExact(
      db,
      messageId: messageId,
      attachmentId: attachmentId,
    )) {
      return false;
    }
    await secureKeyStore.delete(
      mediaAttachmentEncryptionKeyStoreName(attachmentId),
    );
    return true;
  }

  @override
  Future<int> deleteGroupPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  }) {
    rowDeleteCalls++;
    if (_shouldFail(GroupPrivateCleanupFailurePoint.rowDelete)) {
      throw StateError('injected row-delete crash');
    }
    return dbDeleteGroupPrivateMediaAttachmentExact(
      db,
      messageId: messageId,
      attachmentId: attachmentId,
    );
  }
}

GroupMessageRepositoryImpl _buildGroupMessageRepository(Database db) {
  return GroupMessageRepositoryImpl(
    dbInsertGroupMessage: (row) => dbInsertGroupMessage(db, row),
    dbLoadGroupMessagesPage: (groupId, {int limit = 50, int offset = 0}) =>
        dbLoadGroupMessagesPage(db, groupId, limit: limit, offset: offset),
    dbLoadGroupMessage: (id) => dbLoadGroupMessage(db, id),
    dbLoadLatestGroupMessage: (groupId) =>
        dbLoadLatestGroupMessage(db, groupId),
    dbUpdateGroupMessageStatus: (id, status) =>
        dbUpdateGroupMessageStatus(db, id, status),
    dbCountGroupMessages: (groupId) => dbCountGroupMessages(db, groupId),
    dbCountUnreadGroupMessages: (groupId) =>
        dbCountUnreadGroupMessages(db, groupId),
    dbCountTotalUnreadGroupMessages: () => dbCountTotalUnreadGroupMessages(db),
    dbMarkGroupMessagesAsRead: (groupId) =>
        dbMarkGroupMessagesAsRead(db, groupId),
    dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(db, id),
    dbExistsGroupMessageByContent: (groupId, senderPeerId, text, timestamp) =>
        dbExistsGroupMessageByContent(
          db,
          groupId,
          senderPeerId,
          text,
          timestamp,
        ),
    dbDeleteGroupMessagesForGroup: (groupId) =>
        dbDeleteGroupMessagesForGroup(db, groupId),
    dbLoadGroupThreadSummaries: (groupIds) =>
        dbLoadGroupThreadSummaries(db, groupIds),
    dbAnchorOutgoingGroupPrivateMediaCustodyFn: (id, {required int nowMs}) =>
        dbAnchorOutgoingGroupPrivateMediaCustody(db, id, nowMs: nowMs),
    dbConsumeGroupPrivateMediaFn: (id, {required int nowMs}) =>
        dbConsumeGroupPrivateMedia(db, id, nowMs: nowMs),
    dbAdvanceGroupPrivateMediaClockFn: (id, {required int nowMs}) =>
        dbAdvanceGroupPrivateMediaClock(db, id, nowMs: nowMs),
    dbLoadNextGroupPrivateMediaExpiryAtMsFn: () =>
        dbLoadNextGroupPrivateMediaExpiryAtMs(db),
    dbLoadActiveGroupPrivateMediaDisappearingFn: ({int limit = 100}) =>
        dbLoadActiveGroupPrivateMediaDisappearing(db, limit: limit),
    dbLoadGroupPrivateMediaRecoveryCandidatesFn: ({int limit = 100}) =>
        dbLoadGroupPrivateMediaRecoveryCandidates(db, limit: limit),
    dbRotateGroupPrivateMediaRecoveryCandidateFn: (id, {required int nowMs}) =>
        dbRotateGroupPrivateMediaRecoveryCandidate(db, id, nowMs: nowMs),
    dbCompleteGroupPrivateMediaCleanupFn: (id) =>
        dbCompleteGroupPrivateMediaCleanup(db, id),
  );
}
