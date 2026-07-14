import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/models/media_storage.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../shared/fixtures/media_repository_real_db_fixture.dart';

/// Delegating gateway that can fail deletes and records every delete, plus
/// an optional [onDelete] probe so a test can observe DB state at the exact
/// moment of file deletion (claim-before-delete ordering).
class _FaultInjectingGateway implements MediaStorageFileGateway {
  _FaultInjectingGateway();

  final MediaStorageFileGateway inner = const IoMediaStorageFileGateway();
  bool failDelete = false;
  final List<String> deletedPaths = [];
  Future<void> Function(String absolutePath)? onDelete;

  @override
  Future<bool> exists(String absolutePath) => inner.exists(absolutePath);

  @override
  Future<int?> lengthOrNull(String absolutePath) =>
      inner.lengthOrNull(absolutePath);

  @override
  Future<String?> resolveRealPathOrNull(String absolutePath) =>
      inner.resolveRealPathOrNull(absolutePath);

  @override
  Future<void> delete(String absolutePath, {required String reason}) async {
    if (failDelete) {
      throw FileSystemException('injected delete failure', absolutePath);
    }
    await onDelete?.call(absolutePath);
    deletedPaths.add(absolutePath);
    await inner.delete(absolutePath, reason: reason);
  }
}

/// Delegating repository that can fail the CAS claim/finalize callbacks and
/// records every storage-page request (kind/limit/cursor discipline).
class _FaultInjectingRepository
    implements
        MediaAttachmentRepository,
        MediaAttachmentByIdLookup,
        MediaDownloadStateRepository,
        MediaStorageInventoryRepository {
  _FaultInjectingRepository(this.inner);

  final dynamic inner; // MediaAttachmentRepositoryImpl
  bool failClaim = false;
  bool failFinalize = false;
  int claimCalls = 0;
  int finalizeCalls = 0;
  final List<({String kind, int limit, String? cursor})> storagePageRequests =
      [];

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) => inner.saveAttachment(attachment, owner: owner);

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => inner.getAttachmentsForMessage(messageId, owner: owner);

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) => inner.getAttachmentsForMessages(messageIds, owner: owner);

  @override
  Future<void> updateLocalPath(String id, String localPath) =>
      inner.updateLocalPath(id, localPath);

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) =>
      inner.updateDownloadStatus(id, downloadStatus);

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => inner.deleteAttachmentsForMessage(messageId, owner: owner);

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) =>
      inner.deleteAttachmentsForContact(contactPeerId);

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => inner.markUploadPendingAttachmentsFailedForMessage(
    messageId,
    owner: owner,
  );

  @override
  Future<List<MediaAttachment>> getPendingDownloads() =>
      inner.getPendingDownloads();

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) => inner.getUploadPendingAttachments(owner: owner);

  @override
  Future<MediaAttachment?> getAttachmentById(String id) =>
      inner.getAttachmentById(id);

  @override
  Future<bool> beginMediaDownload(String id, {required MediaOwnerLane owner}) =>
      inner.beginMediaDownload(id, owner: owner);

  @override
  Future<bool> commitMediaDownloadLocalPath(
    String id, {
    required MediaOwnerLane owner,
    required String localPath,
  }) => inner.commitMediaDownloadLocalPath(
    id,
    owner: owner,
    localPath: localPath,
  );

  @override
  Future<int> claimMediaEvicted(
    String id, {
    required MediaOwnerLane owner,
    required String expectedLocalPath,
  }) async {
    claimCalls++;
    if (failClaim) {
      throw StateError('injected claim failure');
    }
    return await inner.claimMediaEvicted(
          id,
          owner: owner,
          expectedLocalPath: expectedLocalPath,
        )
        as int;
  }

  @override
  Future<int> finalizeMediaEvictedPathCleared(
    String id, {
    required MediaOwnerLane owner,
  }) async {
    finalizeCalls++;
    if (failFinalize) {
      throw StateError('injected finalize failure');
    }
    return await inner.finalizeMediaEvictedPathCleared(id, owner: owner) as int;
  }

  @override
  Future<MediaStoragePage> getMediaStoragePage({
    required MediaLibraryScope scope,
    MediaStorageKind kind = MediaStorageKind.all,
    int limit = kMediaLibraryMaxPageSize,
    String? cursor,
  }) {
    storagePageRequests.add((kind: kind.name, limit: limit, cursor: cursor));
    return inner.getMediaStoragePage(
          scope: scope,
          kind: kind,
          limit: limit,
          cursor: cursor,
        )
        as Future<MediaStoragePage>;
  }
}

void main() {
  late MediaRepositoryRealDbFixture fixture;
  late Directory tempDocs;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
    tempDocs = Directory.systemTemp.createTempSync('media-storage-mgr-');
  });

  tearDown(() async {
    await fixture.dispose();
    if (tempDocs.existsSync()) {
      tempDocs.deleteSync(recursive: true);
    }
  });

  const directScopeId = 'contact-1';
  const groupScopeId = 'group-1';
  final directScope = MediaLibraryScope.direct(directScopeId);
  final groupScope = MediaLibraryScope.group(groupScopeId);

  String extFor(String mime) => switch (mime) {
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'video/mp4' => '.mp4',
    'audio/mp4' => '.m4a',
    'application/pdf' => '.pdf',
    _ => '',
  };

  String canonicalRelative(String scopeId, String id, String mime) =>
      'media/$scopeId/$id${extFor(mime)}';

  File fileAt(String relativeOrAbsolute) => File(
    p.isAbsolute(relativeOrAbsolute)
        ? relativeOrAbsolute
        : p.join(tempDocs.path, relativeOrAbsolute),
  );

  void createBytes(String relativeOrAbsolute, List<int> bytes) {
    fileAt(relativeOrAbsolute)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  Future<void> seedAttachmentRow({
    required MediaOwnerLane owner,
    required String scopeId,
    required String messageId,
    required String id,
    String mime = 'image/jpeg',
    String mediaType = 'image',
    String downloadStatus = 'done',
    String? storedPath,
    List<int>? fileBytes,
    String? encryptionKeyBase64,
  }) async {
    final path = storedPath ?? canonicalRelative(scopeId, id, mime);
    if (fileBytes != null) {
      createBytes(path, fileBytes);
    }
    await fixture.repo.saveAttachment(
      MediaAttachment(
        id: id,
        messageId: messageId,
        mime: mime,
        size: 999999, // deliberately wrong: totals must NEVER trust this
        mediaType: mediaType,
        localPath: path,
        downloadStatus: downloadStatus,
        createdAt: '2026-07-10T09:00:00.000Z',
        encryptionKeyBase64: encryptionKeyBase64,
        encryptionNonce: encryptionKeyBase64 == null ? null : 'nonce-1',
      ),
      owner: owner,
    );
  }

  MediaStorageManager makeManager({
    MediaStorageFileGateway? gateway,
    MediaAttachmentRepository? repository,
    MediaAttachmentLifecycleLock? lifecycleLock,
  }) => MediaStorageManager(
    repository: repository ?? fixture.repo,
    documentsDirectoryProvider: () async => tempDocs.path,
    fileGateway: gateway ?? const IoMediaStorageFileGateway(),
    lifecycleLock: lifecycleLock,
  );

  group('MediaStorageManager', () {
    test(
      'clear holds one lifecycle lock through claim delete and finalize',
      () async {
        await fixture.seedDirectParent('msg-lock');
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-lock',
          id: 'att-lock',
          fileBytes: const [1, 2, 3],
        );

        final lock = MediaAttachmentLifecycleLock();
        final gateway = _FaultInjectingGateway();
        late Future<void> competingCleanup;
        var competitorEntered = false;
        Map<String, Object?>? rowSeenByCompetitor;
        gateway.onDelete = (path) async {
          // This probe represents an independent lifecycle event. Escape the
          // manager's reentrant lock zone so it queues as a true contender.
          competingCleanup = Zone.root.run(
            () => lock.synchronized('att-lock', () async {
              competitorEntered = true;
              rowSeenByCompetitor = await fixture.rawAttachmentRow('att-lock');
            }),
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            competitorEntered,
            isFalse,
            reason: 'another terminal cleanup cannot enter during file I/O',
          );
        };

        final manager = makeManager(gateway: gateway, lifecycleLock: lock);
        expect(
          await manager.clearLocalCopy(
            scope: directScope,
            attachmentId: 'att-lock',
            mime: 'image/jpeg',
          ),
          MediaClearLocalCopyResult.cleared,
        );
        await competingCleanup;

        expect(competitorEntered, isTrue);
        expect(
          rowSeenByCompetitor!['download_status'],
          kMediaDownloadStatusEvicted,
        );
        expect(
          rowSeenByCompetitor!['local_path'],
          isNull,
          reason: 'the competing saga enters only after eviction finalize',
        );
      },
    );

    test('clear local copy claims exact owner path before delete and preserves '
        'sibling state', () async {
      await fixture.seedDirectParent('msg-clear');
      await fixture.seedGroupParent('msg-clear');

      // Target: direct done row with a canonical file, bookmark and a
      // secure-stored encryption key.
      await seedAttachmentRow(
        owner: MediaOwnerLane.direct,
        scopeId: directScopeId,
        messageId: 'msg-clear',
        id: 'att-clear',
        fileBytes: const [1, 2, 3, 4],
        encryptionKeyBase64: 'key-clear',
      );
      await fixture.repo.setBookmarked('att-clear', bookmarked: true);
      // Sibling attachment on the SAME direct message.
      await seedAttachmentRow(
        owner: MediaOwnerLane.direct,
        scopeId: directScopeId,
        messageId: 'msg-clear',
        id: 'att-sibling',
        fileBytes: const [5, 6, 7, 8],
      );
      // Group collision row under the SAME parent message id.
      await seedAttachmentRow(
        owner: MediaOwnerLane.group,
        scopeId: groupScopeId,
        messageId: 'msg-clear',
        id: 'att-clear-group',
        fileBytes: const [9, 9, 9],
      );
      // Fail-closed unresolved legacy row with a real file.
      const unresolvedPath = 'media/$directScopeId/att-unres.jpg';
      createBytes(unresolvedPath, const [7, 7]);
      await fixture.db.insert('media_attachments', {
        'id': 'att-unres',
        'message_id': 'msg-clear',
        'mime': 'image/jpeg',
        'size': 2,
        'media_type': 'image',
        'download_status': 'done',
        'local_path': unresolvedPath,
        'created_at': '2026-07-10T09:00:00.000Z',
        'owner_lane': 'unresolved',
      });

      // Ordering probe: at the moment the file is deleted, the durable
      // evicted claim must already be persisted.
      final gateway = _FaultInjectingGateway();
      String? statusAtDeleteTime;
      gateway.onDelete = (path) async {
        statusAtDeleteTime =
            (await fixture.rawAttachmentRow('att-clear'))!['download_status']
                as String?;
      };

      final manager = makeManager(gateway: gateway);
      final result = await manager.clearLocalCopy(
        scope: directScope,
        attachmentId: 'att-clear',
        mime: 'image/jpeg',
      );

      expect(result, MediaClearLocalCopyResult.cleared);
      expect(
        statusAtDeleteTime,
        kMediaDownloadStatusEvicted,
        reason: 'the durable claim must precede file deletion',
      );
      expect(gateway.deletedPaths, hasLength(1));

      // Exactly the target row became evicted with a cleared path and a
      // removed canonical file.
      final clearedRow = await fixture.rawAttachmentRow('att-clear');
      expect(clearedRow!['download_status'], kMediaDownloadStatusEvicted);
      expect(clearedRow['local_path'], isNull);
      expect(
        fileAt(
          canonicalRelative(directScopeId, 'att-clear', 'image/jpeg'),
        ).existsSync(),
        isFalse,
      );
      // Descriptor, key reference and viewer state survive.
      expect(clearedRow['mime'], 'image/jpeg');
      expect(clearedRow['encryption_key_base64'], isNotNull);
      expect(clearedRow['is_bookmarked'], 1);

      // Sibling, group collision, unresolved rows/files and parents survive.
      final sibling = await fixture.rawAttachmentRow('att-sibling');
      expect(sibling!['download_status'], 'done');
      expect(
        fileAt(
          canonicalRelative(directScopeId, 'att-sibling', 'image/jpeg'),
        ).existsSync(),
        isTrue,
      );
      final groupRow = await fixture.rawAttachmentRow('att-clear-group');
      expect(groupRow!['download_status'], 'done');
      expect(
        fileAt(
          canonicalRelative(groupScopeId, 'att-clear-group', 'image/jpeg'),
        ).existsSync(),
        isTrue,
      );
      final unresolvedRow = await fixture.rawAttachmentRow('att-unres');
      expect(unresolvedRow!['download_status'], 'done');
      expect(fileAt(unresolvedPath).existsSync(), isTrue);

      // Cross-scope attempts fail closed with zero mutation.
      expect(
        await manager.clearLocalCopy(
          scope: directScope,
          attachmentId: 'att-clear-group',
          mime: 'image/jpeg',
        ),
        MediaClearLocalCopyResult.rejectedWrongOwner,
      );
      expect(
        await manager.clearLocalCopy(
          scope: directScope,
          attachmentId: 'att-unres',
          mime: 'image/jpeg',
        ),
        MediaClearLocalCopyResult.rejectedWrongOwner,
      );

      // Reopen (fresh manager over a fresh repository read): still
      // evicted/null, and a repeat Clear is the idempotent no-op.
      final reopened = makeManager();
      expect(
        await reopened.clearLocalCopy(
          scope: directScope,
          attachmentId: 'att-clear',
          mime: 'image/jpeg',
        ),
        MediaClearLocalCopyResult.alreadyCleared,
      );
    });

    test(
      'eviction failures remain retryable and reconcile after restart',
      () async {
        await fixture.seedDirectParent('msg-fail');

        // --- Claim failure: no file is touched. ---
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-fail',
          id: 'att-claim-fail',
          fileBytes: const [1, 1, 1],
        );
        final gateway = _FaultInjectingGateway();
        final faultRepo = _FaultInjectingRepository(fixture.repo)
          ..failClaim = true;
        final manager = makeManager(gateway: gateway, repository: faultRepo);

        expect(
          await manager.clearLocalCopy(
            scope: directScope,
            attachmentId: 'att-claim-fail',
            mime: 'image/jpeg',
          ),
          MediaClearLocalCopyResult.conflict,
        );
        expect(
          gateway.deletedPaths,
          isEmpty,
          reason: 'a failed claim must never touch the file',
        );
        final afterClaimFail = await fixture.rawAttachmentRow('att-claim-fail');
        expect(afterClaimFail!['download_status'], 'done');
        expect(afterClaimFail['local_path'], isNotNull);
        expect(
          fileAt(
            canonicalRelative(directScopeId, 'att-claim-fail', 'image/jpeg'),
          ).existsSync(),
          isTrue,
        );

        // --- Delete failure: durable evicted claim + retained path, then a
        // second Clear retries the deletion to completion. ---
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-fail',
          id: 'att-delete-fail',
          fileBytes: const [2, 2, 2],
        );
        faultRepo.failClaim = false;
        gateway.failDelete = true;
        expect(
          await manager.clearLocalCopy(
            scope: directScope,
            attachmentId: 'att-delete-fail',
            mime: 'image/jpeg',
          ),
          MediaClearLocalCopyResult.cleanupFailed,
        );
        final pendingCleanup = await fixture.rawAttachmentRow(
          'att-delete-fail',
        );
        expect(pendingCleanup!['download_status'], kMediaDownloadStatusEvicted);
        expect(
          pendingCleanup['local_path'],
          canonicalRelative(directScopeId, 'att-delete-fail', 'image/jpeg'),
          reason: 'cleanup-pending keeps the expected path for the retry',
        );
        expect(
          fileAt(
            canonicalRelative(directScopeId, 'att-delete-fail', 'image/jpeg'),
          ).existsSync(),
          isTrue,
        );
        // The retry (fresh Clear) deletes without needing a second claim.
        gateway.failDelete = false;
        final claimsBeforeRetry = faultRepo.claimCalls;
        expect(
          await manager.clearLocalCopy(
            scope: directScope,
            attachmentId: 'att-delete-fail',
            mime: 'image/jpeg',
          ),
          MediaClearLocalCopyResult.cleared,
        );
        expect(
          faultRepo.claimCalls,
          claimsBeforeRetry,
          reason: 'a cleanup-pending row is already durably claimed',
        );
        expect(
          fileAt(
            canonicalRelative(directScopeId, 'att-delete-fail', 'image/jpeg'),
          ).existsSync(),
          isFalse,
        );
        expect(
          (await fixture.rawAttachmentRow('att-delete-fail'))!['local_path'],
          isNull,
        );

        // --- Finalize failure after successful deletion: evicted + stale
        // path; a fresh manager's inventory reconciles it to null ONLY after
        // proving the canonical file absent. ---
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-fail',
          id: 'att-finalize-fail',
          fileBytes: const [3, 3, 3],
        );
        faultRepo.failFinalize = true;
        expect(
          await manager.clearLocalCopy(
            scope: directScope,
            attachmentId: 'att-finalize-fail',
            mime: 'image/jpeg',
          ),
          MediaClearLocalCopyResult.cleanupFailed,
        );
        final stalePath = await fixture.rawAttachmentRow('att-finalize-fail');
        expect(stalePath!['download_status'], kMediaDownloadStatusEvicted);
        expect(stalePath['local_path'], isNotNull);
        expect(
          fileAt(
            canonicalRelative(directScopeId, 'att-finalize-fail', 'image/jpeg'),
          ).existsSync(),
          isFalse,
          reason: 'the bytes were reclaimed before the finalize failed',
        );

        // A cleanup-pending row whose file still EXISTS is NOT reconciled
        // (and keeps counting its bytes).
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-fail',
          id: 'att-cleanup-present',
          fileBytes: const [4, 4, 4, 4],
        );
        faultRepo.failFinalize = false;
        gateway.failDelete = true;
        expect(
          await manager.clearLocalCopy(
            scope: directScope,
            attachmentId: 'att-cleanup-present',
            mime: 'image/jpeg',
          ),
          MediaClearLocalCopyResult.cleanupFailed,
        );
        gateway.failDelete = false;

        final freshManager = makeManager();
        final inventory = await freshManager.inventory(scope: directScope);

        // Reconciled: stale-path row proven absent is now evicted/null...
        final reconciled = await fixture.rawAttachmentRow('att-finalize-fail');
        expect(reconciled!['download_status'], kMediaDownloadStatusEvicted);
        expect(reconciled['local_path'], isNull);
        // ...while the present-file cleanup-pending row keeps its path and
        // keeps counting its bytes.
        final stillPending = await fixture.rawAttachmentRow(
          'att-cleanup-present',
        );
        expect(stillPending!['download_status'], kMediaDownloadStatusEvicted);
        expect(stillPending['local_path'], isNotNull);
        // Totals: att-claim-fail (3 bytes, still done) + att-cleanup-present
        // (4 bytes, cleanup-pending) — never the deleted/missing rows, never
        // the descriptor size column.
        expect(inventory.totalFor('image').count, 2);
        expect(inventory.totalFor('image').bytes, 7);

        // No auto-download was armed anywhere in the failure protocol.
        for (final id in const [
          'att-delete-fail',
          'att-finalize-fail',
          'att-cleanup-present',
        ]) {
          final row = await fixture.rawAttachmentRow(id);
          expect(
            row!['download_status'],
            kMediaDownloadStatusEvicted,
            reason: '$id must remain evicted, never pending',
          );
        }
      },
    );

    test(
      'clear rejects noncanonical wrong scope and misleading legacy paths',
      () async {
        await fixture.seedDirectParent('msg-reject');

        final manager = makeManager();

        Future<void> expectRejectedWithZeroMutation({
          required String id,
          required String mime,
          required MediaClearLocalCopyResult expected,
          required List<String> mustSurvive,
        }) async {
          final before = await fixture.rawAttachmentRow(id);
          final result = await manager.clearLocalCopy(
            scope: directScope,
            attachmentId: id,
            mime: mime,
          );
          expect(result, expected, reason: '$id must reject as $expected');
          expect(result.isRejection, isTrue);
          final after = await fixture.rawAttachmentRow(id);
          expect(
            after!['download_status'],
            before!['download_status'],
            reason: '$id row must be untouched',
          );
          expect(after['local_path'], before['local_path']);
          for (final path in mustSurvive) {
            expect(
              fileAt(path).existsSync(),
              isTrue,
              reason: '$path must survive the rejected clear of $id',
            );
          }
        }

        // 1. Arbitrary absolute path (an export outside the app container).
        final exportsDir = Directory.systemTemp.createTempSync('msm-exports-');
        addTearDown(() => exportsDir.deleteSync(recursive: true));
        final exportedFile = p.join(exportsDir.path, 'att-export.jpg');
        createBytes(exportedFile, const [1, 2]);
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-reject',
          id: 'att-export',
          storedPath: exportedFile,
        );
        await expectRejectedWithZeroMutation(
          id: 'att-export',
          mime: 'image/jpeg',
          expected: MediaClearLocalCopyResult.rejectedNoncanonicalPath,
          mustSurvive: [exportedFile],
        );

        // 2. Misleading legacy absolute: contains a '/media/' substring a
        // resolveStoredPath-style remap would extract, but is NOT the exact
        // current-container absolute path. The CURRENT canonical file must
        // survive; the row requires an explicit path repair before Clear.
        final currentCanonical = canonicalRelative(
          directScopeId,
          'att-legacy',
          'image/jpeg',
        );
        createBytes(currentCanonical, const [3, 4, 5]);
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-reject',
          id: 'att-legacy',
          storedPath:
              '/old-container/Documents/media/$directScopeId/att-legacy.jpg',
        );
        await expectRejectedWithZeroMutation(
          id: 'att-legacy',
          mime: 'image/jpeg',
          expected: MediaClearLocalCopyResult.rejectedNoncanonicalPath,
          mustSurvive: [currentCanonical],
        );

        // 3. Another attachment's canonical path is not YOURS.
        final victimPath = canonicalRelative(
          directScopeId,
          'att-victim',
          'image/jpeg',
        );
        createBytes(victimPath, const [6, 6]);
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-reject',
          id: 'att-victim',
          fileBytes: null,
          storedPath: victimPath,
        );
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-reject',
          id: 'att-thief',
          storedPath: victimPath,
        );
        await expectRejectedWithZeroMutation(
          id: 'att-thief',
          mime: 'image/jpeg',
          expected: MediaClearLocalCopyResult.rejectedNoncanonicalPath,
          mustSurvive: [victimPath],
        );

        // 4. Wrong extension for the claimed MIME: stored .jpg can never be
        // authorized under a png expectation, and a mismatched row MIME is
        // rejected even earlier.
        final jpgPath = canonicalRelative(
          directScopeId,
          'att-wrong-ext',
          'image/jpeg',
        );
        createBytes(jpgPath, const [8, 8]);
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-reject',
          id: 'att-wrong-ext',
          mime: 'image/png',
          storedPath: jpgPath,
        );
        await expectRejectedWithZeroMutation(
          id: 'att-wrong-ext',
          mime: 'image/jpeg',
          expected: MediaClearLocalCopyResult.rejectedMimeMismatch,
          mustSurvive: [jpgPath],
        );
        await expectRejectedWithZeroMutation(
          id: 'att-wrong-ext',
          mime: 'image/png',
          expected: MediaClearLocalCopyResult.rejectedNoncanonicalPath,
          mustSurvive: [jpgPath],
        );

        // 5. Wrong scope directory (a group-scope path stored on a
        // direct-owned row).
        final foreignScopePath = canonicalRelative(
          groupScopeId,
          'att-foreign',
          'image/jpeg',
        );
        createBytes(foreignScopePath, const [9]);
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-reject',
          id: 'att-foreign',
          storedPath: foreignScopePath,
        );
        await expectRejectedWithZeroMutation(
          id: 'att-foreign',
          mime: 'image/jpeg',
          expected: MediaClearLocalCopyResult.rejectedNoncanonicalPath,
          mustSurvive: [foreignScopePath],
        );

        // 6. Symlink at the canonical path: the stored value looks exact, but
        // the resolved target escapes — fail closed BEFORE any mutation; the
        // symlink target survives.
        final symTargetFile = p.join(exportsDir.path, 'precious-original.jpg');
        createBytes(symTargetFile, const [42, 42, 42]);
        final symlinkRelative = canonicalRelative(
          directScopeId,
          'att-symlink',
          'image/jpeg',
        );
        final symlinkAbsolute = p.join(tempDocs.path, symlinkRelative);
        Directory(p.dirname(symlinkAbsolute)).createSync(recursive: true);
        Link(symlinkAbsolute).createSync(symTargetFile);
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-reject',
          id: 'att-symlink',
          storedPath: symlinkRelative,
        );
        await expectRejectedWithZeroMutation(
          id: 'att-symlink',
          mime: 'image/jpeg',
          expected: MediaClearLocalCopyResult.rejectedUnsafeTarget,
          mustSurvive: [symTargetFile],
        );
        expect(
          Link(symlinkAbsolute).existsSync(),
          isTrue,
          reason: 'even the symlink itself is never deleted on rejection',
        );

        // 7. A missing row and a row with nothing durable to clear.
        expect(
          await manager.clearLocalCopy(
            scope: directScope,
            attachmentId: 'att-absent',
            mime: 'image/jpeg',
          ),
          MediaClearLocalCopyResult.rejectedMissingRow,
        );
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-reject',
          id: 'att-pending',
          downloadStatus: 'pending',
        );
        expect(
          await manager.clearLocalCopy(
            scope: directScope,
            attachmentId: 'att-pending',
            mime: 'image/jpeg',
          ),
          MediaClearLocalCopyResult.rejectedNotClearable,
        );
      },
    );

    test(
      'all media inventory exhausts owner scoped pages for exact totals',
      () async {
        await fixture.seedDirectParent('msg-inv');
        await fixture.seedDirectParent(
          'msg-inv-deleted',
          deletedAt: '2026-07-09T00:00:00.000Z',
        );
        await fixture.seedGroupParent('msg-inv-group');

        // 200 eligible direct rows across all four types with REAL bytes:
        // 50 images x4B, 50 videos x6B, 50 audio x8B, 50 files x10B.
        const typeSpecs = [
          (type: 'image', mime: 'image/jpeg', bytes: 4),
          (type: 'video', mime: 'video/mp4', bytes: 6),
          (type: 'audio', mime: 'audio/mp4', bytes: 8),
          (type: 'file', mime: 'application/pdf', bytes: 10),
        ];
        for (final spec in typeSpecs) {
          for (var i = 0; i < 50; i++) {
            await seedAttachmentRow(
              owner: MediaOwnerLane.direct,
              scopeId: directScopeId,
              messageId: 'msg-inv',
              id: 'inv-${spec.type}-${i.toString().padLeft(3, '0')}',
              mime: spec.mime,
              mediaType: spec.type,
              fileBytes: List.filled(spec.bytes, 1),
            );
          }
        }
        // 201st..205th rows — every excluded form:
        // (a) deleted-parent direct row WITH bytes;
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-inv-deleted',
          id: 'inv-deleted-parent',
          fileBytes: const [1, 1, 1, 1],
        );
        // (b) descriptor-only row (canonical path, missing file);
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-inv',
          id: 'inv-missing-file',
        );
        // (c) noncanonical/exported stored path (file exists elsewhere);
        final exportsDir = Directory.systemTemp.createTempSync('msm-inv-');
        addTearDown(() => exportsDir.deleteSync(recursive: true));
        final exported = p.join(exportsDir.path, 'inv-exported.jpg');
        createBytes(exported, const [1, 1, 1, 1]);
        await seedAttachmentRow(
          owner: MediaOwnerLane.direct,
          scopeId: directScopeId,
          messageId: 'msg-inv',
          id: 'inv-exported',
          storedPath: exported,
        );
        // (d) unresolved legacy row with real bytes under the scope dir;
        const unresolvedPath = 'media/$directScopeId/inv-unresolved.jpg';
        createBytes(unresolvedPath, const [1, 1, 1, 1]);
        await fixture.db.insert('media_attachments', {
          'id': 'inv-unresolved',
          'message_id': 'msg-inv',
          'mime': 'image/jpeg',
          'size': 4,
          'media_type': 'image',
          'download_status': 'done',
          'local_path': unresolvedPath,
          'created_at': '2026-07-10T09:00:00.000Z',
          'owner_lane': 'unresolved',
        });
        // (e) group-owned sibling row with bytes (other scope).
        await seedAttachmentRow(
          owner: MediaOwnerLane.group,
          scopeId: groupScopeId,
          messageId: 'msg-inv-group',
          id: 'inv-group-sibling',
          fileBytes: const [2, 2],
        );

        final countingRepo = _FaultInjectingRepository(fixture.repo);
        final manager = makeManager(repository: countingRepo);
        final inventory = await manager.inventory(scope: directScope);

        // Exact per-type totals from REAL file lengths only.
        expect(inventory.totalFor('image').count, 50);
        expect(inventory.totalFor('image').bytes, 200);
        expect(inventory.totalFor('video').count, 50);
        expect(inventory.totalFor('video').bytes, 300);
        expect(inventory.totalFor('audio').count, 50);
        expect(inventory.totalFor('audio').bytes, 400);
        expect(inventory.totalFor('file').count, 50);
        expect(inventory.totalFor('file').bytes, 500);
        expect(inventory.totalCount, 200);
        expect(inventory.totalBytes, 1400);

        // The sweep paged to exhaustion through opaque limit-100 cursors:
        // 100 + 100 + 0, i.e. exactly three requests, final cursor null.
        expect(countingRepo.storagePageRequests, hasLength(3));
        expect(
          countingRepo.storagePageRequests.every(
            (request) => request.limit == kMediaLibraryMaxPageSize,
          ),
          isTrue,
        );
        expect(countingRepo.storagePageRequests.first.cursor, isNull);
        expect(countingRepo.storagePageRequests[1].cursor, isNotNull);
        expect(countingRepo.storagePageRequests[2].cursor, isNotNull);
        expect(
          countingRepo.storagePageRequests[1].cursor,
          isNot(countingRepo.storagePageRequests[2].cursor),
        );

        // The group scope sees ONLY its own sibling.
        final groupInventory = await manager.inventory(scope: groupScope);
        expect(groupInventory.totalCount, 1);
        expect(groupInventory.totalBytes, 2);

        // Cursor and limit discipline on the query itself.
        final firstPage = await fixture.repo.getMediaStoragePage(
          scope: directScope,
        );
        expect(firstPage.entries, hasLength(100));
        expect(firstPage.nextCursor, isNotNull);
        expect(
          () => fixture.repo.getMediaStoragePage(scope: directScope, limit: 0),
          throwsArgumentError,
        );
        expect(
          () =>
              fixture.repo.getMediaStoragePage(scope: directScope, limit: 101),
          throwsArgumentError,
        );
        // A cursor replayed under another scope or kind fails before SQL.
        expect(
          () => fixture.repo.getMediaStoragePage(
            scope: groupScope,
            cursor: firstPage.nextCursor,
          ),
          throwsArgumentError,
        );
        expect(
          () => fixture.repo.getMediaStoragePage(
            scope: directScope,
            kind: MediaStorageKind.image,
            cursor: firstPage.nextCursor,
          ),
          throwsArgumentError,
        );
        // A visual-library cursor can never address the storage query.
        final libraryPage = await fixture.repo.getMediaLibraryPage(
          scope: directScope,
          limit: 100,
        );
        expect(libraryPage.nextCursor, isNotNull);
        expect(
          () => fixture.repo.getMediaStoragePage(
            scope: directScope,
            cursor: libraryPage.nextCursor,
          ),
          throwsArgumentError,
        );
        // And a per-type page addresses only its own type.
        final audioPage = await fixture.repo.getMediaStoragePage(
          scope: directScope,
          kind: MediaStorageKind.audio,
        );
        expect(
          audioPage.entries.every(
            (entry) => entry.attachment.mediaType == 'audio',
          ),
          isTrue,
        );
        expect(audioPage.entries, hasLength(50));
      },
    );
  });
}
