import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

import '../models/media_attachment.dart';
import '../models/media_library.dart';
import '../models/media_preview_descriptor.dart';
import '../models/media_storage.dart';
import 'media_attachment_repository.dart';

/// Implementation of MediaAttachmentRepository using database helper functions.
///
/// 228 ownership contract: every message-scoped closure takes the owner-lane
/// string as its final argument, and [saveAttachment] validates the immutable
/// `(attachmentId, ownerLane, messageId)` identity BEFORE `_toStorageRow` or
/// any secure-store side effect. The save closure
/// ([dbSaveMediaAttachmentPreservingLocalState]) must merge atomically,
/// preserving local-only owner/bookmark/playback state and a completed local
/// path, and re-validate identity inside the write transaction as the final
/// race guard.
///
/// Every public attachment-row mutator enters [lifecycleLock]. Methods whose
/// names end in `WithinLock` also enter it defensively; acquisition is
/// reentrant only for the same async-zone attachment lease, so these public
/// capabilities cannot be used to bypass the row mutation authority. Bulk
/// message/contact writers use the lock's exclusive mode because their full
/// affected attachment set cannot be frozen before the database statement.
class MediaAttachmentRepositoryImpl
    implements
        MediaAttachmentRepository,
        MediaAttachmentAuthorizationChangeSource,
        MediaAttachmentByIdLookup,
        MediaPreviewDescriptorLookup,
        MediaLibraryStateRepository,
        DirectMediaLibraryStateRepository,
        GroupMediaLibraryStateRepository,
        MediaLibraryRepository,
        MediaDownloadStateRepository,
        DirectPrivateMediaDownloadStateRepository,
        DirectPrivateMediaAttachmentSaveRepository,
        DirectPrivateMediaCleanupRepository,
        DirectPrivateMediaCleanupRuntime,
        GroupPrivateMediaDownloadStateRepository,
        GroupPrivateMediaCleanupRepository,
        GroupPrivateMediaCleanupRuntime,
        MediaStorageInventoryRepository,
        GroupGuardedMediaAttachmentSave,
        NewMessageMediaPersistenceRollback {
  final Future<void> Function(Map<String, Object?> row)
  dbSaveMediaAttachmentPreservingLocalState;
  final Future<List<Map<String, Object?>>> Function(
    String messageId,
    String ownerLane,
  )
  dbLoadMediaForMessage;
  final Future<Map<String, Object?>?> Function(String id) dbLoadMediaById;
  final Future<List<Map<String, Object?>>> Function(
    List<String> messageIds,
    String ownerLane,
  )
  dbLoadMediaForMessages;
  final Future<void> Function(
    String id,
    String localPath,
    String downloadStatus,
  )
  dbUpdateMediaLocalPath;
  final Future<void> Function(String id, String downloadStatus)
  dbUpdateMediaDownloadStatus;
  final Future<int> Function(String messageId, String ownerLane)
  dbDeleteMediaForMessage;
  final Future<int> Function(String contactPeerId) dbDeleteMediaForContact;
  final Future<int> Function(String messageId, String ownerLane)
  dbMarkUploadPendingAttachmentsFailedForMessage;
  final Future<List<Map<String, Object?>>> Function()
  dbLoadPendingMediaDownloads;
  final Future<List<Map<String, Object?>>> Function({
    int limit,
    required String ownerLane,
  })
  dbLoadUploadPendingAttachments;
  final Future<void> Function(String id, bool bookmarked) dbSetMediaBookmarked;
  final Future<bool> Function({
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  })?
  dbSetDirectMediaBookmarkedIfOrdinary;
  final Future<bool> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  })?
  dbSetGroupMediaBookmarkedIfOrdinary;
  final Future<void> Function(String id, int positionMs)
  dbUpdateMediaPlaybackPosition;
  final Future<List<Map<String, Object?>>> Function({
    required String scopeKind,
    required String scopeId,
    required List<String> mediaTypes,
    required bool bookmarkedOnly,
    required bool incomingOnly,
    required int limit,
    String? afterTimestamp,
    String? afterMessageId,
    String? afterAttachmentId,
  })
  dbLoadMediaLibraryPage;

  // 229: the owner-scoped all-media storage page closure. Optional like the
  // CAS closures below; the capability fails closed when missing.
  final Future<List<Map<String, Object?>>> Function({
    required String scopeKind,
    required String scopeId,
    required List<String> mediaTypes,
    required int limit,
    String? afterTimestamp,
    String? afterMessageId,
    String? afterAttachmentId,
  })?
  dbLoadMediaStoragePage;

  // 229: owner-aware CAS closures. Optional so schema-only constructions
  // keep compiling, but the capability methods fail closed (StateError)
  // rather than silently degrading when a closure is missing.
  final Future<int> Function(String id, {required String ownerLane})?
  dbBeginMediaDownload;
  final Future<int> Function(
    String id, {
    required String ownerLane,
    required String localPath,
  })?
  dbCommitMediaDownloadLocalPath;
  final Future<int> Function(
    String id, {
    required String ownerLane,
    required String expectedLocalPath,
  })?
  dbClaimMediaEvicted;
  final Future<int> Function(String id, {required String ownerLane})?
  dbFinalizeMediaEvictedPathCleared;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required String localPath,
    required int nowMs,
  })?
  dbCommitDirectPrivateMediaDownloadIfEligible;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required int nowMs,
  })?
  dbBeginDirectPrivateMediaDownloadIfEligible;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required String expectedLocalPath,
    required int nowMs,
  })?
  dbQualifyDirectPrivateMediaLocalReadyIfEligible;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required int nowMs,
  })?
  dbQualifyDirectPrivateMediaDownloadClaimIfEligible;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath,
  })?
  dbRecordDirectPrivateMediaDownloadFailureIfEligible;
  final Future<bool> Function(
    Map<String, Object?> row, {
    required String messageId,
    required int nowMs,
  })?
  dbSaveDirectPrivateMediaAttachmentGuarded;
  final Future<bool> Function({
    required String messageId,
    required String attachmentId,
  })?
  dbCanCleanupDirectPrivateMediaAttachmentExact;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
  })?
  dbDeleteDirectPrivateMediaAttachmentExact;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required int nowMs,
  })?
  dbBeginGroupPrivateMediaDownloadIfEligible;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required String expectedLocalPath,
    required int nowMs,
  })?
  dbQualifyGroupPrivateMediaLocalReadyIfEligible;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required int nowMs,
  })?
  dbQualifyGroupPrivateMediaDownloadClaimIfEligible;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    required bool clearLocalPath,
  })?
  dbRecordGroupPrivateMediaDownloadFailureIfEligible;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required String localPath,
    required int nowMs,
  })?
  dbCommitGroupPrivateMediaDownloadIfEligible;
  final Future<bool> Function({
    required String messageId,
    required String attachmentId,
  })?
  dbCanCleanupGroupPrivateMediaAttachmentExact;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
  })?
  dbDeleteGroupPrivateMediaAttachmentExact;

  // 235: guarded final write for incoming GROUP media (parent + deletion-
  // journal check in the SAME transaction as the row write). Optional like
  // the CAS closures; the capability fails closed when missing.
  final Future<bool> Function(
    Map<String, Object?> row, {
    required String groupId,
  })?
  dbSaveGroupMediaAttachmentGuarded;

  final SecureKeyStore? secureKeyStore;
  final Future<void> Function(String messageId)?
  refreshDirectPrivateMediaParent;

  /// 235: serializes row/key/file work per attachment across the guarded
  /// save, the download commit, and the deletion-journal cleanup saga.
  final MediaAttachmentLifecycleLock lifecycleLock;
  final StreamController<MediaAttachmentAuthorizationChange>
  _authorizationChangesController =
      StreamController<MediaAttachmentAuthorizationChange>.broadcast(
        sync: true,
      );

  MediaAttachmentRepositoryImpl({
    required this.dbSaveMediaAttachmentPreservingLocalState,
    required this.dbLoadMediaForMessage,
    required this.dbLoadMediaById,
    required this.dbLoadMediaForMessages,
    required this.dbUpdateMediaLocalPath,
    required this.dbUpdateMediaDownloadStatus,
    required this.dbDeleteMediaForMessage,
    required this.dbDeleteMediaForContact,
    required this.dbMarkUploadPendingAttachmentsFailedForMessage,
    required this.dbLoadPendingMediaDownloads,
    required this.dbLoadUploadPendingAttachments,
    required this.dbSetMediaBookmarked,
    this.dbSetDirectMediaBookmarkedIfOrdinary,
    this.dbSetGroupMediaBookmarkedIfOrdinary,
    required this.dbUpdateMediaPlaybackPosition,
    required this.dbLoadMediaLibraryPage,
    this.dbLoadMediaStoragePage,
    this.dbBeginMediaDownload,
    this.dbCommitMediaDownloadLocalPath,
    this.dbClaimMediaEvicted,
    this.dbFinalizeMediaEvictedPathCleared,
    this.dbCommitDirectPrivateMediaDownloadIfEligible,
    this.dbBeginDirectPrivateMediaDownloadIfEligible,
    this.dbQualifyDirectPrivateMediaLocalReadyIfEligible,
    this.dbQualifyDirectPrivateMediaDownloadClaimIfEligible,
    this.dbRecordDirectPrivateMediaDownloadFailureIfEligible,
    this.dbSaveDirectPrivateMediaAttachmentGuarded,
    this.dbCanCleanupDirectPrivateMediaAttachmentExact,
    this.dbDeleteDirectPrivateMediaAttachmentExact,
    this.dbBeginGroupPrivateMediaDownloadIfEligible,
    this.dbQualifyGroupPrivateMediaLocalReadyIfEligible,
    this.dbQualifyGroupPrivateMediaDownloadClaimIfEligible,
    this.dbRecordGroupPrivateMediaDownloadFailureIfEligible,
    this.dbCommitGroupPrivateMediaDownloadIfEligible,
    this.dbCanCleanupGroupPrivateMediaAttachmentExact,
    this.dbDeleteGroupPrivateMediaAttachmentExact,
    this.dbSaveGroupMediaAttachmentGuarded,
    this.secureKeyStore,
    this.refreshDirectPrivateMediaParent,
    MediaAttachmentLifecycleLock? lifecycleLock,
  }) : lifecycleLock = lifecycleLock ?? mediaAttachmentLifecycleLock;

  @override
  Stream<MediaAttachmentAuthorizationChange> get authorizationChanges =>
      _authorizationChangesController.stream;

  void _emitAuthorizationChange({
    required MediaOwnerLane owner,
    String? scopeId,
    String? messageId,
    String? attachmentId,
    required MediaAttachmentAuthorizationMutation kind,
  }) {
    _authorizationChangesController.add(
      MediaAttachmentAuthorizationChange(
        owner: owner,
        scopeId: scopeId,
        messageId: messageId,
        attachmentId: attachmentId,
        kind: kind,
      ),
    );
  }

  void _emitAuthorizationChangeForRow(
    Map<String, Object?> row,
    MediaAttachmentAuthorizationMutation kind,
  ) {
    final owner = mediaOwnerLaneFromDbValue(row['owner_lane'] as String?);
    final messageId = row['message_id'] as String?;
    final attachmentId = row['id'] as String?;
    if (owner == null || messageId == null || attachmentId == null) return;
    _emitAuthorizationChange(
      owner: owner,
      messageId: messageId,
      attachmentId: attachmentId,
      kind: kind,
    );
  }

  @override
  MediaAttachmentLifecycleLock get directPrivateMediaLifecycleLock =>
      lifecycleLock;

  @override
  MediaAttachmentLifecycleLock get groupPrivateMediaLifecycleLock =>
      lifecycleLock;

  @override
  Future<bool> deleteDirectPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  }) => lifecycleLock.synchronized(attachmentId, () async {
    final canCleanup = _requireCasClosure(
      dbCanCleanupDirectPrivateMediaAttachmentExact,
      'deleteDirectPrivateMediaEncryptionKeyWithinLock',
    );
    if (!await canCleanup(messageId: messageId, attachmentId: attachmentId)) {
      return false;
    }
    final store = secureKeyStore;
    if (store == null) {
      throw StateError(
        'direct private-media cleanup requires secure key storage',
      );
    }
    await store.delete(mediaAttachmentEncryptionKeyStoreName(attachmentId));
    return true;
  });

  T _requireCasClosure<T>(T? closure, String name) {
    if (closure == null) {
      throw StateError(
        '229 CAS closure $name is not wired on this '
        'MediaAttachmentRepositoryImpl — conditional download/eviction '
        'transitions fail closed instead of degrading to unconditional '
        'writes',
      );
    }
    return closure;
  }

  Future<T> _withCompensatedEncryptionKeyWrite<T>(
    MediaAttachment attachment,
    Future<T> Function(Map<String, Object?> row) persist, {
    required bool Function(T result) committed,
  }) async {
    final snapshot = await _captureEncryptionKeyWriteSnapshot(attachment);
    try {
      final row = await _toStorageRow(attachment);
      final result = await persist(row);
      if (!committed(result)) await snapshot.restore();
      return result;
    } catch (_) {
      await snapshot.restore();
      rethrow;
    }
  }

  Future<_MediaEncryptionKeyWriteSnapshot> _captureEncryptionKeyWriteSnapshot(
    MediaAttachment attachment,
  ) async {
    final store = secureKeyStore;
    final rawKey = attachment.encryptionKeyBase64;
    if (store == null ||
        rawKey == null ||
        rawKey.isEmpty ||
        isSecureStoreReference(rawKey)) {
      return _MediaEncryptionKeyWriteSnapshot.inactive();
    }
    final keyName = mediaAttachmentEncryptionKeyStoreName(attachment.id);
    final existed = await store.containsKey(keyName);
    final previousValue = existed ? await store.read(keyName) : null;
    if (existed && previousValue == null) {
      throw StateError(
        'existing secure media key is unreadable; refusing overwrite',
      );
    }
    return _MediaEncryptionKeyWriteSnapshot(
      store: store,
      keyName: keyName,
      existed: existed,
      previousValue: previousValue,
    );
  }

  @override
  Future<bool> saveDirectPrivateAttachmentGuarded(
    MediaAttachment attachment, {
    required String messageId,
    required int nowMs,
  }) async {
    if (attachment.messageId != messageId ||
        (attachment.ownerLane != null &&
            attachment.ownerLane != MediaOwnerLane.direct)) {
      throw MediaAttachmentOwnerViolation(
        'guarded direct private save received mismatched identity',
      );
    }
    final guarded = _requireCasClosure(
      dbSaveDirectPrivateMediaAttachmentGuarded,
      'saveDirectPrivateAttachmentGuarded',
    );
    final stamped = attachment.copyWith(ownerLane: MediaOwnerLane.direct);
    return lifecycleLock.synchronized(stamped.id, () async {
      final existingRow = await dbLoadMediaById(stamped.id);
      if (existingRow != null &&
          (existingRow['owner_lane'] != MediaOwnerLane.direct.dbValue ||
              existingRow['message_id'] != messageId)) {
        throw MediaAttachmentOwnerViolation(
          'guarded direct private save would re-parent attachment '
          '${stamped.id}',
        );
      }
      final saved = await _withCompensatedEncryptionKeyWrite<bool>(stamped, (
        row,
      ) async {
        try {
          return await guarded(row, messageId: messageId, nowMs: nowMs);
        } finally {
          await _refreshDirectPrivateParent(messageId);
        }
      }, committed: (saved) => saved);
      if (saved) {
        _emitAuthorizationChange(
          owner: MediaOwnerLane.direct,
          messageId: messageId,
          attachmentId: stamped.id,
          kind: MediaAttachmentAuthorizationMutation.saved,
        );
      }
      return saved;
    });
  }

  @override
  Future<bool> beginDirectPrivateMediaDownload(
    String id, {
    required String messageId,
    required int nowMs,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => beginDirectPrivateMediaDownloadWithinLock(
        id,
        messageId: messageId,
        nowMs: nowMs,
      ),
    );
  }

  @override
  Future<bool> beginDirectPrivateMediaDownloadWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final begin = _requireCasClosure(
      dbBeginDirectPrivateMediaDownloadIfEligible,
      'beginDirectPrivateMediaDownload',
    );
    try {
      return await begin(messageId: messageId, attachmentId: id, nowMs: nowMs) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReady(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => qualifyDirectPrivateMediaLocalReadyWithinLock(
        id,
        messageId: messageId,
        expectedLocalPath: expectedLocalPath,
        nowMs: nowMs,
      ),
    );
  }

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReadyWithinLock(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final qualify = _requireCasClosure(
      dbQualifyDirectPrivateMediaLocalReadyIfEligible,
      'qualifyDirectPrivateMediaLocalReady',
    );
    try {
      return await qualify(
            messageId: messageId,
            attachmentId: id,
            expectedLocalPath: expectedLocalPath,
            nowMs: nowMs,
          ) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  @override
  Future<bool> qualifyDirectPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final qualify = _requireCasClosure(
      dbQualifyDirectPrivateMediaDownloadClaimIfEligible,
      'qualifyDirectPrivateMediaDownloadClaim',
    );
    try {
      return await qualify(
            messageId: messageId,
            attachmentId: id,
            nowMs: nowMs,
          ) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailure(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => recordDirectPrivateMediaDownloadFailureWithinLock(
        id,
        messageId: messageId,
        nowMs: nowMs,
        incrementRetryCount: incrementRetryCount,
        failureStatus: failureStatus,
        expectedDownloadStatus: expectedDownloadStatus,
        expectedLocalPath: expectedLocalPath,
        clearLocalPath: clearLocalPath,
      ),
    );
  }

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailureWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) => lifecycleLock.synchronized(id, () async {
    final record = _requireCasClosure(
      dbRecordDirectPrivateMediaDownloadFailureIfEligible,
      'recordDirectPrivateMediaDownloadFailure',
    );
    try {
      return await record(
            messageId: messageId,
            attachmentId: id,
            nowMs: nowMs,
            incrementRetryCount: incrementRetryCount,
            failureStatus: failureStatus,
            expectedDownloadStatus: expectedDownloadStatus,
            expectedLocalPath: expectedLocalPath,
            clearLocalPath: clearLocalPath,
          ) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  @override
  Future<bool> beginMediaDownload(String id, {required MediaOwnerLane owner}) =>
      lifecycleLock.synchronized(id, () async {
        final claim = _requireCasClosure(
          dbBeginMediaDownload,
          'beginMediaDownload',
        );
        final previous = await dbLoadMediaById(id);
        final changed = await claim(id, ownerLane: owner.dbValue) > 0;
        if (changed && previous != null) {
          _emitAuthorizationChangeForRow(
            previous,
            MediaAttachmentAuthorizationMutation.downloadStarted,
          );
        }
        return changed;
      });

  @override
  Future<bool> commitMediaDownloadLocalPath(
    String id, {
    required MediaOwnerLane owner,
    required String localPath,
  }) => lifecycleLock.synchronized(id, () async {
    final commit = _requireCasClosure(
      dbCommitMediaDownloadLocalPath,
      'commitMediaDownloadLocalPath',
    );
    // 235: the commit shares the attachment lifecycle lock with the guarded
    // group save and the deletion-journal cleanup saga so a cleanup never
    // interleaves with a promotion on the same attachment. The SQL CAS (plus
    // the group journal anti-join) remains the correctness authority.
    final previous = await dbLoadMediaById(id);
    final changed =
        await commit(id, ownerLane: owner.dbValue, localPath: localPath) > 0;
    if (changed && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.downloadCommitted,
      );
    }
    return changed;
  });

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPath(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => commitDirectPrivateMediaDownloadLocalPathWithinLock(
        id,
        messageId: messageId,
        localPath: localPath,
        nowMs: nowMs,
      ),
    );
  }

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final commit = _requireCasClosure(
      dbCommitDirectPrivateMediaDownloadIfEligible,
      'commitDirectPrivateMediaDownloadLocalPath',
    );
    try {
      return await commit(
            messageId: messageId,
            attachmentId: id,
            localPath: localPath,
            nowMs: nowMs,
          ) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  Future<void> _refreshDirectPrivateParent(String messageId) async {
    final refresh = refreshDirectPrivateMediaParent;
    if (refresh == null) return;
    try {
      await refresh(messageId);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PRIVATE_MEDIA_PARENT_REFRESH_ERROR',
        details: {'error': error.runtimeType.toString()},
      );
    }
  }

  @override
  Future<List<DirectPrivateMediaLifecycleAttachmentMetadata>>
  loadDirectPrivateMediaLifecycleAttachmentMetadata(String messageId) async {
    final rows = await dbLoadMediaForMessage(
      messageId,
      MediaOwnerLane.direct.dbValue,
    );
    return rows
        .where(
          (row) =>
              row['message_id'] == messageId &&
              row['owner_lane'] == MediaOwnerLane.direct.dbValue,
        )
        .map(
          (row) => DirectPrivateMediaLifecycleAttachmentMetadata(
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
  Future<List<DirectPrivateMediaCleanupAttachment>>
  loadDirectPrivateMediaCleanupAttachments(String messageId) async {
    final rows = await dbLoadMediaForMessage(
      messageId,
      MediaOwnerLane.direct.dbValue,
    );
    return rows
        .where(
          (row) =>
              row['message_id'] == messageId &&
              row['owner_lane'] == MediaOwnerLane.direct.dbValue,
        )
        .map(
          (row) => DirectPrivateMediaCleanupAttachment(
            id: row['id'] as String,
            messageId: row['message_id'] as String,
            mime: row['mime'] as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<int> deleteDirectPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  }) => lifecycleLock.synchronized(attachmentId, () {
    final delete = _requireCasClosure(
      dbDeleteDirectPrivateMediaAttachmentExact,
      'deleteDirectPrivateMediaAttachmentWithinLock',
    );
    return delete(messageId: messageId, attachmentId: attachmentId);
  });

  @override
  Future<bool> beginGroupPrivateMediaDownloadWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final begin = _requireCasClosure(
      dbBeginGroupPrivateMediaDownloadIfEligible,
      'beginGroupPrivateMediaDownloadWithinLock',
    );
    return await begin(
          groupId: groupId,
          messageId: messageId,
          attachmentId: id,
          nowMs: nowMs,
        ) ==
        1;
  });

  @override
  Future<bool> qualifyGroupPrivateMediaLocalReadyWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final qualify = _requireCasClosure(
      dbQualifyGroupPrivateMediaLocalReadyIfEligible,
      'qualifyGroupPrivateMediaLocalReadyWithinLock',
    );
    return await qualify(
          groupId: groupId,
          messageId: messageId,
          attachmentId: id,
          expectedLocalPath: expectedLocalPath,
          nowMs: nowMs,
        ) ==
        1;
  });

  @override
  Future<bool> qualifyGroupPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final qualify = _requireCasClosure(
      dbQualifyGroupPrivateMediaDownloadClaimIfEligible,
      'qualifyGroupPrivateMediaDownloadClaimWithinLock',
    );
    return await qualify(
          groupId: groupId,
          messageId: messageId,
          attachmentId: id,
          nowMs: nowMs,
        ) ==
        1;
  });

  @override
  Future<bool> recordGroupPrivateMediaDownloadFailure(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    required bool clearLocalPath,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => recordGroupPrivateMediaDownloadFailureWithinLock(
        id,
        groupId: groupId,
        messageId: messageId,
        nowMs: nowMs,
        incrementRetryCount: incrementRetryCount,
        failureStatus: failureStatus,
        expectedDownloadStatus: expectedDownloadStatus,
        expectedLocalPath: expectedLocalPath,
        clearLocalPath: clearLocalPath,
      ),
    );
  }

  @override
  Future<bool> recordGroupPrivateMediaDownloadFailureWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    required bool clearLocalPath,
  }) => lifecycleLock.synchronized(id, () async {
    final record = _requireCasClosure(
      dbRecordGroupPrivateMediaDownloadFailureIfEligible,
      'recordGroupPrivateMediaDownloadFailureWithinLock',
    );
    return await record(
          groupId: groupId,
          messageId: messageId,
          attachmentId: id,
          nowMs: nowMs,
          incrementRetryCount: incrementRetryCount,
          failureStatus: failureStatus,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath: expectedLocalPath,
          clearLocalPath: clearLocalPath,
        ) ==
        1;
  });

  @override
  Future<bool> commitGroupPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required String localPath,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final commit = _requireCasClosure(
      dbCommitGroupPrivateMediaDownloadIfEligible,
      'commitGroupPrivateMediaDownloadLocalPathWithinLock',
    );
    final committed = await commit(
      groupId: groupId,
      messageId: messageId,
      attachmentId: id,
      localPath: localPath,
      nowMs: nowMs,
    );
    return committed == 1;
  });

  @override
  Future<List<GroupPrivateMediaLifecycleAttachmentMetadata>>
  loadGroupPrivateMediaLifecycleAttachmentMetadata(String messageId) async {
    final rows = await dbLoadMediaForMessage(
      messageId,
      MediaOwnerLane.group.dbValue,
    );
    return rows
        .where(
          (row) =>
              row['message_id'] == messageId &&
              row['owner_lane'] == MediaOwnerLane.group.dbValue,
        )
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
  }) => lifecycleLock.synchronized(attachmentId, () async {
    final canCleanup = _requireCasClosure(
      dbCanCleanupGroupPrivateMediaAttachmentExact,
      'deleteGroupPrivateMediaEncryptionKeyWithinLock',
    );
    if (!await canCleanup(messageId: messageId, attachmentId: attachmentId)) {
      return false;
    }
    final store = secureKeyStore;
    if (store == null) {
      throw StateError(
        'group private-media cleanup requires secure key storage',
      );
    }
    await store.delete(mediaAttachmentEncryptionKeyStoreName(attachmentId));
    return true;
  });

  @override
  Future<int> deleteGroupPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  }) => lifecycleLock.synchronized(attachmentId, () {
    final delete = _requireCasClosure(
      dbDeleteGroupPrivateMediaAttachmentExact,
      'deleteGroupPrivateMediaAttachmentWithinLock',
    );
    return delete(messageId: messageId, attachmentId: attachmentId);
  });

  @override
  Future<bool> saveGroupAttachmentGuarded(
    MediaAttachment attachment, {
    required String groupId,
  }) async {
    final guarded = _requireCasClosure(
      dbSaveGroupMediaAttachmentGuarded,
      'saveGroupAttachmentGuarded',
    );
    if (attachment.ownerLane != null &&
        attachment.ownerLane != MediaOwnerLane.group) {
      throw MediaAttachmentOwnerViolation(
        'guarded group save received a row stamped '
        '${attachment.ownerLane!.dbValue}',
      );
    }
    final stamped = attachment.copyWith(ownerLane: MediaOwnerLane.group);
    return lifecycleLock.synchronized(stamped.id, () async {
      // Secure-key write + guarded row persistence form one compensated saga.
      // A refused or throwing guard restores the exact prior key value (or
      // removes a newly introduced key) while this attachment lock is held.
      final saved = await _withCompensatedEncryptionKeyWrite<bool>(
        stamped,
        (row) => guarded(row, groupId: groupId),
        committed: (saved) => saved,
      );
      if (saved) {
        _emitAuthorizationChange(
          owner: MediaOwnerLane.group,
          scopeId: groupId,
          messageId: stamped.messageId,
          attachmentId: stamped.id,
          kind: MediaAttachmentAuthorizationMutation.saved,
        );
      }
      return saved;
    });
  }

  @override
  Future<int> claimMediaEvicted(
    String id, {
    required MediaOwnerLane owner,
    required String expectedLocalPath,
  }) => lifecycleLock.synchronized(id, () async {
    final claim = _requireCasClosure(dbClaimMediaEvicted, 'claimMediaEvicted');
    final previous = await dbLoadMediaById(id);
    final count = await claim(
      id,
      ownerLane: owner.dbValue,
      expectedLocalPath: expectedLocalPath,
    );
    if (count > 0 && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.evicted,
      );
    }
    return count;
  });

  @override
  Future<int> finalizeMediaEvictedPathCleared(
    String id, {
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronized(id, () async {
    final finalize = _requireCasClosure(
      dbFinalizeMediaEvictedPathCleared,
      'finalizeMediaEvictedPathCleared',
    );
    final previous = await dbLoadMediaById(id);
    final count = await finalize(id, ownerLane: owner.dbValue);
    if (count > 0 && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.evictionFinalized,
      );
    }
    return count;
  });

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronized(attachment.id, () async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_SAVE_START',
      details: {
        'id': attachment.id.length > 8
            ? attachment.id.substring(0, 8)
            : attachment.id,
        'ownerLane': owner.dbValue,
      },
    );

    String? keyNameForCompensation;
    var keyExistedBefore = false;
    String? previousKeyValue;
    var keyWriteMayHaveMutated = false;
    var rowPersisted = false;
    try {
      // A model stamped with a DIFFERENT lane than the caller's typed owner
      // is a caller bug — fail closed before any side effect.
      if (attachment.ownerLane != null && attachment.ownerLane != owner) {
        throw MediaAttachmentOwnerViolation(
          'attachment ${attachment.id} is stamped ${attachment.ownerLane!.dbValue} '
          'but the caller passed ${owner.dbValue}',
        );
      }
      final stamped = attachment.copyWith(ownerLane: owner);

      // Immutable-identity validation BEFORE _toStorageRow or any
      // secure-store side effect (TC-228-04K): a rejected cross-owner or
      // cross-parent save must leave the existing row, secure-store
      // reference/value and decryptability unchanged.
      final existingRow = await dbLoadMediaById(stamped.id);
      if (existingRow != null) {
        final existingOwner = existingRow['owner_lane'] as String?;
        final existingMessageId = existingRow['message_id'] as String?;
        if (existingOwner != owner.dbValue ||
            existingMessageId != stamped.messageId) {
          throw MediaAttachmentOwnerViolation(
            'save would re-parent attachment ${stamped.id} from '
            '($existingOwner, $existingMessageId) to '
            '(${owner.dbValue}, ${stamped.messageId})',
          );
        }
      }

      final rawKey = stamped.encryptionKeyBase64;
      final store = secureKeyStore;
      if (store != null &&
          rawKey != null &&
          rawKey.isNotEmpty &&
          !isSecureStoreReference(rawKey)) {
        keyNameForCompensation = mediaAttachmentEncryptionKeyStoreName(
          stamped.id,
        );
        keyExistedBefore = await store.containsKey(keyNameForCompensation);
        if (keyExistedBefore) {
          previousKeyValue = await store.read(keyNameForCompensation);
          if (previousKeyValue == null) {
            throw StateError(
              'secure media key disappeared before attachment save',
            );
          }
        }
      }

      keyWriteMayHaveMutated = keyNameForCompensation != null;
      final storageRow = await _toStorageRow(stamped);
      await dbSaveMediaAttachmentPreservingLocalState(storageRow);
      rowPersisted = true;
      _emitAuthorizationChange(
        owner: owner,
        messageId: stamped.messageId,
        attachmentId: stamped.id,
        kind: MediaAttachmentAuthorizationMutation.saved,
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_SAVE_SUCCESS',
        details: {
          'id': attachment.id.length > 8
              ? attachment.id.substring(0, 8)
              : attachment.id,
        },
      );
    } catch (e) {
      final keyName = keyNameForCompensation;
      final store = secureKeyStore;
      if (!rowPersisted &&
          keyWriteMayHaveMutated &&
          keyName != null &&
          store != null) {
        try {
          if (keyExistedBefore) {
            await store.write(keyName, previousKeyValue!);
          } else if (!keyExistedBefore) {
            await store.delete(keyName);
          }
        } catch (compensationError) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_REPO_SAVE_COMPENSATION_FAILED',
            details: {'error': compensationError.toString()},
          );
          throw StateError(
            'attachment save failed and secure-key compensation failed: '
            '$e; compensation: $compensationError',
          );
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  });

  @override
  Future<int> rollbackNewMessageAttachments({
    required String messageId,
    required Set<String> attachmentIds,
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronizedAll(() async {
    final rows = await dbLoadMediaForMessage(messageId, owner.dbValue);
    final persistedIds = rows
        .map((row) => row['id'])
        .whereType<String>()
        .toSet();
    if (!attachmentIds.containsAll(persistedIds)) {
      throw StateError(
        'refusing new-message media rollback with unexpected attachment ids',
      );
    }

    final deleted = await dbDeleteMediaForMessage(messageId, owner.dbValue);
    final store = secureKeyStore;
    if (store != null) {
      final failures = <String>[];
      for (final attachmentId in persistedIds) {
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        try {
          await store.delete(keyName);
        } catch (_) {
          try {
            await store.delete(keyName);
          } catch (error) {
            failures.add('$attachmentId: $error');
          }
        }
      }
      if (failures.isNotEmpty) {
        throw StateError(
          'new-message media rollback left secure-key residue: '
          '${failures.join('; ')}',
        );
      }
    }
    return deleted;
  });

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final rows = await dbLoadMediaForMessage(messageId, owner.dbValue);
    return _attachmentsFromRows(rows);
  }

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    final row = await dbLoadMediaById(id);
    if (row == null) return null;
    return MediaAttachment.fromMap(await _hydrateRow(row));
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadMediaForMessages(messageIds, owner.dbValue);
    final Map<String, List<MediaAttachment>> result = {};
    for (final attachment in await _attachmentsFromRows(rows)) {
      result.putIfAbsent(attachment.messageId, () => []).add(attachment);
    }
    return result;
  }

  @override
  Future<Map<String, MediaPreviewDescriptor>> getMediaPreviewDescriptors(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadMediaForMessages(messageIds, owner.dbValue);
    // Parse rows WITHOUT _hydrateRow: a preview label is derived purely from
    // media_type/mime/count and never needs the decryption key, so we skip the
    // per-attachment SecureKeyStore.read this path would otherwise pay once per
    // contact/group on every orbit load.
    final Map<String, List<MediaAttachment>> byMessage = {};
    for (final row in rows) {
      final attachment = MediaAttachment.fromMap(row);
      byMessage.putIfAbsent(attachment.messageId, () => []).add(attachment);
    }
    final Map<String, MediaPreviewDescriptor> result = {};
    byMessage.forEach((messageId, attachments) {
      final descriptor = MediaPreviewDescriptor.fromAttachments(attachments);
      if (descriptor != null) result[messageId] = descriptor;
    });
    return result;
  }

  @override
  Future<void> updateLocalPath(String id, String localPath) =>
      lifecycleLock.synchronized(id, () async {
        final previous = await dbLoadMediaById(id);
        await dbUpdateMediaLocalPath(id, localPath, 'done');
        final updated = await dbLoadMediaById(id);
        if (updated != null &&
            (previous == null ||
                previous['local_path'] != updated['local_path'] ||
                previous['download_status'] != updated['download_status'])) {
          _emitAuthorizationChangeForRow(
            updated,
            MediaAttachmentAuthorizationMutation.localPathChanged,
          );
        }
      });

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) =>
      lifecycleLock.synchronized(id, () async {
        final previous = await dbLoadMediaById(id);
        await dbUpdateMediaDownloadStatus(id, downloadStatus);
        final updated = await dbLoadMediaById(id);
        if (updated != null &&
            previous?['download_status'] != updated['download_status']) {
          _emitAuthorizationChangeForRow(
            updated,
            MediaAttachmentAuthorizationMutation.downloadStatusChanged,
          );
        }
      });

  @override
  Future<void> setBookmarked(String id, {required bool bookmarked}) =>
      lifecycleLock.synchronized(id, () async {
        await dbSetMediaBookmarked(id, bookmarked);
      });

  @override
  Future<bool> setDirectBookmarkedIfOrdinary({
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  }) => lifecycleLock.synchronized(attachmentId, () async {
    final guarded = dbSetDirectMediaBookmarkedIfOrdinary;
    if (guarded == null) return false;
    return guarded(
      messageId: messageId,
      attachmentId: attachmentId,
      bookmarked: bookmarked,
    );
  });

  @override
  Future<bool> setGroupBookmarkedIfOrdinary({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  }) => lifecycleLock.synchronized(attachmentId, () async {
    final guarded = dbSetGroupMediaBookmarkedIfOrdinary;
    if (guarded == null) return false;
    return guarded(
      groupId: groupId,
      messageId: messageId,
      attachmentId: attachmentId,
      bookmarked: bookmarked,
    );
  });

  @override
  Future<MediaLibraryPage> getMediaLibraryPage({
    required MediaLibraryScope scope,
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    int limit = 50,
    String? cursor,
  }) async {
    // Every argument-contract failure happens HERE, before any SQL.
    if (limit < 1 || limit > kMediaLibraryMaxPageSize) {
      throw ArgumentError.value(
        limit,
        'limit',
        'must be within 1..$kMediaLibraryMaxPageSize',
      );
    }
    _MediaLibraryCursor? after;
    if (cursor != null) {
      after = _MediaLibraryCursor.decode(cursor);
      if (after.scopeKind != scope.lane.dbValue ||
          after.scopeId != scope.id ||
          after.kind != filter.kind.name ||
          after.bookmarkedOnly != filter.bookmarkedOnly ||
          after.incomingOnly != filter.incomingOnly) {
        throw ArgumentError.value(
          cursor,
          'cursor',
          'cursor was minted for a different scope/filter signature',
        );
      }
    }

    final rows = await dbLoadMediaLibraryPage(
      scopeKind: scope.lane.dbValue,
      scopeId: scope.id,
      mediaTypes: filter.kind.mediaTypes,
      bookmarkedOnly: filter.bookmarkedOnly,
      incomingOnly: filter.incomingOnly,
      limit: limit,
      afterTimestamp: after?.timestamp,
      afterMessageId: after?.messageId,
      afterAttachmentId: after?.attachmentId,
    );

    final entries = <MediaLibraryEntry>[];
    for (final row in rows) {
      final attachmentMap = await _hydrateRow(
        mediaLibraryRowToAttachmentMap(row),
      );
      entries.add(
        MediaLibraryEntry(
          attachment: MediaAttachment.fromMap(attachmentMap),
          parentTimestamp: row['parent_timestamp'] as String,
          parentSenderPeerId: row['parent_sender_peer_id'] as String?,
        ),
      );
    }

    String? nextCursor;
    if (entries.length == limit) {
      final last = entries.last;
      nextCursor = _MediaLibraryCursor(
        scopeKind: scope.lane.dbValue,
        scopeId: scope.id,
        kind: filter.kind.name,
        bookmarkedOnly: filter.bookmarkedOnly,
        incomingOnly: filter.incomingOnly,
        timestamp: last.parentTimestamp,
        messageId: last.attachment.messageId,
        attachmentId: last.attachment.id,
      ).encode();
    }
    return MediaLibraryPage(entries: entries, nextCursor: nextCursor);
  }

  @override
  Future<MediaStoragePage> getMediaStoragePage({
    required MediaLibraryScope scope,
    MediaStorageKind kind = MediaStorageKind.all,
    int limit = kMediaLibraryMaxPageSize,
    String? cursor,
  }) async {
    final loadPage = _requireCasClosure(
      dbLoadMediaStoragePage,
      'getMediaStoragePage',
    );
    // Every argument-contract failure happens HERE, before any SQL.
    if (limit < 1 || limit > kMediaLibraryMaxPageSize) {
      throw ArgumentError.value(
        limit,
        'limit',
        'must be within 1..$kMediaLibraryMaxPageSize',
      );
    }
    _MediaStorageCursor? after;
    if (cursor != null) {
      after = _MediaStorageCursor.decode(cursor);
      if (after.scopeKind != scope.lane.dbValue ||
          after.scopeId != scope.id ||
          after.kind != kind.name) {
        throw ArgumentError.value(
          cursor,
          'cursor',
          'cursor was minted for a different scope/kind signature',
        );
      }
    }

    final rows = await loadPage(
      scopeKind: scope.lane.dbValue,
      scopeId: scope.id,
      mediaTypes: kind.mediaTypes,
      limit: limit,
      afterTimestamp: after?.timestamp,
      afterMessageId: after?.messageId,
      afterAttachmentId: after?.attachmentId,
    );

    final entries = <MediaStorageEntry>[];
    for (final row in rows) {
      final attachmentMap = await _hydrateRow(
        mediaLibraryRowToAttachmentMap(row),
      );
      entries.add(
        MediaStorageEntry(
          attachment: MediaAttachment.fromMap(attachmentMap),
          parentTimestamp: row['parent_timestamp'] as String,
        ),
      );
    }

    String? nextCursor;
    if (entries.length == limit) {
      final last = entries.last;
      nextCursor = _MediaStorageCursor(
        scopeKind: scope.lane.dbValue,
        scopeId: scope.id,
        kind: kind.name,
        timestamp: last.parentTimestamp,
        messageId: last.attachment.messageId,
        attachmentId: last.attachment.id,
      ).encode();
    }
    return MediaStoragePage(entries: entries, nextCursor: nextCursor);
  }

  @override
  Future<void> updatePlaybackPosition(String id, int positionMs) =>
      lifecycleLock.synchronized(id, () async {
        await dbUpdateMediaPlaybackPosition(id, positionMs);
      });

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronizedAll(() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_START',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'ownerLane': owner.dbValue,
      },
    );

    try {
      final previousRows = await dbLoadMediaForMessage(
        messageId,
        owner.dbValue,
      );
      final count = await dbDeleteMediaForMessage(messageId, owner.dbValue);
      if (count > 0) {
        if (previousRows.isEmpty) {
          _emitAuthorizationChange(
            owner: owner,
            messageId: messageId,
            kind: MediaAttachmentAuthorizationMutation.removed,
          );
        } else {
          for (final row in previousRows) {
            _emitAuthorizationChangeForRow(
              row,
              MediaAttachmentAuthorizationMutation.removed,
            );
          }
        }
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_SUCCESS',
        details: {'count': count},
      );

      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  });

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) =>
      lifecycleLock.synchronizedAll(() async {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_REPO_DELETE_FOR_CONTACT_START',
          details: {
            'contactPeerId': contactPeerId.length > 10
                ? contactPeerId.substring(0, 10)
                : contactPeerId,
          },
        );

        try {
          final count = await dbDeleteMediaForContact(contactPeerId);
          if (count > 0) {
            _emitAuthorizationChange(
              owner: MediaOwnerLane.direct,
              scopeId: contactPeerId,
              kind: MediaAttachmentAuthorizationMutation.removed,
            );
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_REPO_DELETE_FOR_CONTACT_SUCCESS',
            details: {'count': count},
          );

          return count;
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_REPO_DELETE_FOR_CONTACT_ERROR',
            details: {'error': e.toString()},
          );
          rethrow;
        }
      });

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronizedAll(() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_START',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'ownerLane': owner.dbValue,
      },
    );

    try {
      final count = await dbMarkUploadPendingAttachmentsFailedForMessage(
        messageId,
        owner.dbValue,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_SUCCESS',
        details: {'count': count},
      );
      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  });

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async {
    final rows = await dbLoadPendingMediaDownloads();
    return _attachmentsFromRows(rows);
  }

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async {
    final rows = await dbLoadUploadPendingAttachments(ownerLane: owner.dbValue);
    return _attachmentsFromRows(rows);
  }

  Future<Map<String, Object?>> _toStorageRow(MediaAttachment attachment) async {
    final row = Map<String, Object?>.from(attachment.toMap());
    final key = attachment.encryptionKeyBase64;
    final store = secureKeyStore;
    if (store == null ||
        key == null ||
        key.isEmpty ||
        isSecureStoreReference(key)) {
      return row;
    }

    final secureStoreKey = mediaAttachmentEncryptionKeyStoreName(attachment.id);
    await store.write(secureStoreKey, key);
    row['encryption_key_base64'] = secureStoreReferenceForKey(secureStoreKey);
    return row;
  }

  Future<List<MediaAttachment>> _attachmentsFromRows(
    List<Map<String, Object?>> rows,
  ) async {
    final attachments = <MediaAttachment>[];
    for (final row in rows) {
      attachments.add(MediaAttachment.fromMap(await _hydrateRow(row)));
    }
    return attachments;
  }

  Future<Map<String, Object?>> _hydrateRow(Map<String, Object?> row) async {
    final keyValue = row['encryption_key_base64'] as String?;
    final store = secureKeyStore;
    if (keyValue == null || !isSecureStoreReference(keyValue)) {
      return row;
    }

    final missingKeyRow = Map<String, Object?>.from(row)
      ..['encryption_key_base64'] = null;
    if (store == null) {
      return missingKeyRow;
    }

    final hydrated = await store.read(secureStoreKeyFromReference(keyValue));
    if (hydrated == null) {
      return missingKeyRow;
    }

    return Map<String, Object?>.from(row)..['encryption_key_base64'] = hydrated;
  }
}

class _MediaEncryptionKeyWriteSnapshot {
  _MediaEncryptionKeyWriteSnapshot({
    required this.store,
    required this.keyName,
    required this.existed,
    required this.previousValue,
  });

  _MediaEncryptionKeyWriteSnapshot.inactive()
    : store = null,
      keyName = null,
      existed = false,
      previousValue = null;

  final SecureKeyStore? store;
  final String? keyName;
  final bool existed;
  final String? previousValue;
  var _restored = false;

  Future<void> restore() async {
    final effectiveStore = store;
    final effectiveKeyName = keyName;
    if (_restored || effectiveStore == null || effectiveKeyName == null) return;
    if (existed) {
      await effectiveStore.write(effectiveKeyName, previousValue!);
    } else {
      await effectiveStore.delete(effectiveKeyName);
    }
    _restored = true;
  }
}

/// Opaque keyset cursor for [MediaAttachmentRepositoryImpl.getMediaStoragePage]
/// (229). Embeds the complete scope/kind signature alongside the keyset
/// position; a `v`/`q` mismatch or replay under another signature fails
/// before SQL. Deliberately a distinct codec from [_MediaLibraryCursor] so a
/// visual-library cursor can never address the storage query (and vice
/// versa).
class _MediaStorageCursor {
  const _MediaStorageCursor({
    required this.scopeKind,
    required this.scopeId,
    required this.kind,
    required this.timestamp,
    required this.messageId,
    required this.attachmentId,
  });

  final String scopeKind;
  final String scopeId;
  final String kind;
  final String timestamp;
  final String messageId;
  final String attachmentId;

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'q': 'storage',
        'scopeKind': scopeKind,
        'scopeId': scopeId,
        'kind': kind,
        'ts': timestamp,
        'mid': messageId,
        'aid': attachmentId,
      }),
    ),
  );

  static _MediaStorageCursor decode(String cursor) {
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(cursor)))
              as Map<String, dynamic>;
      if (decoded['v'] != 1 || decoded['q'] != 'storage') {
        throw const FormatException('unknown storage cursor signature');
      }
      return _MediaStorageCursor(
        scopeKind: decoded['scopeKind'] as String,
        scopeId: decoded['scopeId'] as String,
        kind: decoded['kind'] as String,
        timestamp: decoded['ts'] as String,
        messageId: decoded['mid'] as String,
        attachmentId: decoded['aid'] as String,
      );
    } catch (e) {
      throw ArgumentError.value(cursor, 'cursor', 'malformed cursor: $e');
    }
  }
}

/// Opaque keyset cursor for [MediaAttachmentRepositoryImpl.getMediaLibraryPage].
/// Embeds the complete scope/filter signature alongside the keyset position so
/// a cursor can never be replayed under another query signature.
class _MediaLibraryCursor {
  const _MediaLibraryCursor({
    required this.scopeKind,
    required this.scopeId,
    required this.kind,
    required this.bookmarkedOnly,
    required this.incomingOnly,
    required this.timestamp,
    required this.messageId,
    required this.attachmentId,
  });

  final String scopeKind;
  final String scopeId;
  final String kind;
  final bool bookmarkedOnly;
  final bool incomingOnly;
  final String timestamp;
  final String messageId;
  final String attachmentId;

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'v': 2,
        'scopeKind': scopeKind,
        'scopeId': scopeId,
        'kind': kind,
        'bookmarkedOnly': bookmarkedOnly,
        'incomingOnly': incomingOnly,
        'ts': timestamp,
        'mid': messageId,
        'aid': attachmentId,
      }),
    ),
  );

  static _MediaLibraryCursor decode(String cursor) {
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(cursor)))
              as Map<String, dynamic>;
      final version = decoded['v'];
      if (version != 1 && version != 2) {
        throw const FormatException('unknown cursor version');
      }
      return _MediaLibraryCursor(
        scopeKind: decoded['scopeKind'] as String,
        scopeId: decoded['scopeId'] as String,
        kind: decoded['kind'] as String,
        bookmarkedOnly: decoded['bookmarkedOnly'] as bool,
        incomingOnly: version == 1 ? false : decoded['incomingOnly'] as bool,
        timestamp: decoded['ts'] as String,
        messageId: decoded['mid'] as String,
        attachmentId: decoded['aid'] as String,
      );
    } catch (e) {
      throw ArgumentError.value(cursor, 'cursor', 'malformed cursor: $e');
    }
  }
}
