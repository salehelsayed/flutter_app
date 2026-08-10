import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:path/path.dart' as p;

import 'private_media_action_eligibility.dart';
import 'strict_direct_media_blob_download_ack_owner.dart';

/// Downloads a media blob from the relay and saves it locally.
///
/// Called lazily when the UI needs to display a media item.
final Map<_MediaDownloadInFlightKey, Future<MediaAttachment?>>
_inFlightMediaDownloads =
    <_MediaDownloadInFlightKey, Future<MediaAttachment?>>{};

enum MediaDownloadIntent { automatic, explicitUser }

typedef GroupMediaPostClaimPreCommit =
    Future<void> Function(MediaAttachment attachment);
typedef GroupMediaAutomaticDownloadAttemptStarted =
    Future<void> Function(MediaAttachment attachment);

class _GroupPrivateDownloadStateAdapter
    implements DirectPrivateMediaDownloadStateRepository {
  _GroupPrivateDownloadStateAdapter({
    required this.delegate,
    required this.runtime,
    required this.groupId,
  });

  final GroupPrivateMediaDownloadStateRepository delegate;
  final GroupPrivateMediaCleanupRuntime runtime;
  final String groupId;

  @override
  Future<bool> beginDirectPrivateMediaDownload(
    String id, {
    required String messageId,
    required int nowMs,
  }) => runtime.groupPrivateMediaLifecycleLock.synchronized(
    id,
    () => beginDirectPrivateMediaDownloadWithinLock(
      id,
      messageId: messageId,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> beginDirectPrivateMediaDownloadWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) => delegate.beginGroupPrivateMediaDownloadWithinLock(
    id,
    groupId: groupId,
    messageId: messageId,
    nowMs: nowMs,
  );

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReady(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) => runtime.groupPrivateMediaLifecycleLock.synchronized(
    id,
    () => qualifyDirectPrivateMediaLocalReadyWithinLock(
      id,
      messageId: messageId,
      expectedLocalPath: expectedLocalPath,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReadyWithinLock(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) => delegate.qualifyGroupPrivateMediaLocalReadyWithinLock(
    id,
    groupId: groupId,
    messageId: messageId,
    expectedLocalPath: expectedLocalPath,
    nowMs: nowMs,
  );

  @override
  Future<bool> qualifyDirectPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) => delegate.qualifyGroupPrivateMediaDownloadClaimWithinLock(
    id,
    groupId: groupId,
    messageId: messageId,
    nowMs: nowMs,
  );

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
  }) => delegate.recordGroupPrivateMediaDownloadFailure(
    id,
    groupId: groupId,
    messageId: messageId,
    nowMs: nowMs,
    incrementRetryCount: incrementRetryCount,
    failureStatus: failureStatus,
    expectedDownloadStatus: expectedDownloadStatus,
    expectedLocalPath: expectedLocalPath,
    clearLocalPath: clearLocalPath,
  );

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
  }) => delegate.recordGroupPrivateMediaDownloadFailureWithinLock(
    id,
    groupId: groupId,
    messageId: messageId,
    nowMs: nowMs,
    incrementRetryCount: incrementRetryCount,
    failureStatus: failureStatus,
    expectedDownloadStatus: expectedDownloadStatus,
    expectedLocalPath: expectedLocalPath,
    clearLocalPath: clearLocalPath,
  );

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPath(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) => runtime.groupPrivateMediaLifecycleLock.synchronized(
    id,
    () => commitDirectPrivateMediaDownloadLocalPathWithinLock(
      id,
      messageId: messageId,
      localPath: localPath,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) => delegate.commitGroupPrivateMediaDownloadLocalPathWithinLock(
    id,
    groupId: groupId,
    messageId: messageId,
    localPath: localPath,
    nowMs: nowMs,
  );
}

class _GroupPrivateCleanupRuntimeAdapter
    implements DirectPrivateMediaCleanupRuntime {
  const _GroupPrivateCleanupRuntimeAdapter(this.delegate);

  final GroupPrivateMediaCleanupRuntime delegate;

  @override
  MediaAttachmentLifecycleLock get directPrivateMediaLifecycleLock =>
      delegate.groupPrivateMediaLifecycleLock;
}

class _MediaDownloadInFlightKey {
  const _MediaDownloadInFlightKey({
    required this.bridge,
    required this.mediaAttachmentRepo,
    required this.mediaFileManager,
    required this.contactPeerId,
    required this.attachmentId,
    required this.mime,
    required this.enforceGroupMediaPolicy,
    required this.requiresDirectPrivateCommit,
    required this.encryptionDiscriminator,
  });

  final Bridge bridge;
  final MediaAttachmentRepository mediaAttachmentRepo;
  final MediaFileManager mediaFileManager;
  final String contactPeerId;
  final String attachmentId;
  final String mime;
  final bool enforceGroupMediaPolicy;
  final bool requiresDirectPrivateCommit;

  /// Key/nonce/scheme fingerprint: concurrent calls for the same blob with
  /// different encryption metadata (or policy) must not share a future —
  /// they stage to different suffixes and take different promote paths.
  final String encryptionDiscriminator;

  @override
  bool operator ==(Object other) {
    return other is _MediaDownloadInFlightKey &&
        identical(bridge, other.bridge) &&
        identical(mediaAttachmentRepo, other.mediaAttachmentRepo) &&
        identical(mediaFileManager, other.mediaFileManager) &&
        contactPeerId == other.contactPeerId &&
        attachmentId == other.attachmentId &&
        mime == other.mime &&
        enforceGroupMediaPolicy == other.enforceGroupMediaPolicy &&
        requiresDirectPrivateCommit == other.requiresDirectPrivateCommit &&
        encryptionDiscriminator == other.encryptionDiscriminator;
  }

  @override
  int get hashCode => Object.hash(
    identityHashCode(bridge),
    identityHashCode(mediaAttachmentRepo),
    identityHashCode(mediaFileManager),
    contactPeerId,
    attachmentId,
    mime,
    enforceGroupMediaPolicy,
    requiresDirectPrivateCommit,
    encryptionDiscriminator,
  );

  bool conflictsWith(_MediaDownloadInFlightKey other) {
    return identical(bridge, other.bridge) &&
        identical(mediaAttachmentRepo, other.mediaAttachmentRepo) &&
        identical(mediaFileManager, other.mediaFileManager) &&
        contactPeerId == other.contactPeerId &&
        attachmentId == other.attachmentId &&
        mime == other.mime &&
        enforceGroupMediaPolicy == other.enforceGroupMediaPolicy &&
        encryptionDiscriminator == other.encryptionDiscriminator &&
        requiresDirectPrivateCommit != other.requiresDirectPrivateCommit;
  }
}

/// Outcome of a direct (1:1) staged-ciphertext decrypt+promote attempt.
enum _DirectStagedDecryptOutcome {
  /// Plaintext committed to the canonical path; caller finishes the commit.
  promoted,

  /// Stale/unusable staged artifact during adoption — no terminal status
  /// set; caller falls through to a fresh relay download.
  softMiss,

  /// Fail-closed or transient failure; status already persisted, staged
  /// artifact preserved, NO relay ack. The whole download returns null.
  terminal,
}

String _mediaDownloadPathKind(String? path) {
  if (path == null || path.isEmpty) {
    return 'empty';
  }
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
    return 'absolute';
  }
  return 'relative';
}

String _mediaDownloadShortPeerId(String peerId) {
  if (peerId.length <= 12) {
    return peerId;
  }
  return peerId.substring(peerId.length - 8);
}

@visibleForTesting
List<Duration> debugGroupMediaDownloadPostCommitProbeDelays = const [
  Duration(milliseconds: 250),
  Duration(seconds: 1),
];

void _scheduleGroupMediaDownloadPostCommitProbes({
  required String absolutePath,
  required String relativePath,
  required String source,
  required String blobId,
  required String attachmentId,
  required String messageId,
  required String mime,
  required String mediaType,
  required int expectedBytes,
}) {
  for (final delay in debugGroupMediaDownloadPostCommitProbeDelays) {
    unawaited(
      Future<void>.delayed(delay, () async {
        try {
          final file = File(absolutePath);
          final exists = await file.exists();
          final bytes = exists ? await file.length() : 0;
          final details = <String, dynamic>{
            'blobId': blobId,
            'attachmentId': attachmentId,
            'messageId': messageId,
            'mime': mime,
            'mediaType': mediaType,
            'source': source,
            'relativePath': relativePath,
            'relativePathKind': _mediaDownloadPathKind(relativePath),
            'absolutePathKind': _mediaDownloadPathKind(absolutePath),
            'probeDelayMs': delay.inMilliseconds,
            'fileExists': exists,
            'fileBytes': bytes,
            'expectedBytes': expectedBytes,
          };
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_GROUP_DURABLE_LOCAL_PATH_DELAYED_PROBE',
            details: details,
          );
          if (!exists || bytes <= 0) {
            emitFlowEvent(
              layer: 'FL',
              event: 'MEDIA_GROUP_DURABLE_LOCAL_PATH_DELAYED_PROBE_MISSING',
              details: details,
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_GROUP_DURABLE_LOCAL_PATH_DELAYED_PROBE_ERROR',
            details: {
              'blobId': blobId,
              'attachmentId': attachmentId,
              'messageId': messageId,
              'mime': mime,
              'source': source,
              'relativePath': relativePath,
              'probeDelayMs': delay.inMilliseconds,
              'error': e.toString(),
            },
          );
        }
      }),
    );
  }
}

Future<List<MediaAttachment>> _localMediaAttachmentCandidates({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaAttachment attachment,
  required MediaOwnerLane owner,
  bool includeInputCandidate = true,
}) async {
  final candidates = <MediaAttachment>[if (includeInputCandidate) attachment];
  try {
    final storedAttachments = await mediaAttachmentRepo
        .getAttachmentsForMessage(attachment.messageId, owner: owner);
    candidates.insertAll(
      0,
      storedAttachments.where((stored) => stored.id == attachment.id),
    );
  } catch (_) {}
  return candidates;
}

Future<Map<String, Object?>> _localMediaCandidateDiagnostic({
  required MediaFileManager mediaFileManager,
  required MediaAttachment candidate,
  required int index,
  required bool allowStatusRepair,
}) async {
  final storedPath = candidate.localPath;
  var reason = 'local_ready';
  String? resolvedPath;
  String? resolveError;
  bool? fileExists;
  int? fileBytes;

  if (storedPath == null || storedPath.isEmpty) {
    reason = 'no_local_path';
  } else {
    try {
      resolvedPath = await mediaFileManager.resolveStoredPath(storedPath);
    } catch (e) {
      resolvedPath = storedPath;
      resolveError = e.toString();
    }

    try {
      final file = File(resolvedPath);
      fileExists = await file.exists();
      if (fileExists) {
        fileBytes = await file.length();
      }
    } catch (e) {
      reason = 'file_stat_failed';
      resolveError ??= e.toString();
    }

    if (reason == 'local_ready' && fileExists != true) {
      reason = 'local_file_missing';
    }
    if (reason == 'local_ready' &&
        candidate.downloadStatus != kMediaDownloadStatusDone &&
        !allowStatusRepair) {
      reason = 'status_not_done';
    }
  }

  final details = <String, Object?>{
    'candidateIndex': index,
    'attachmentId': candidate.id,
    'messageId': candidate.messageId,
    'downloadStatus': candidate.downloadStatus,
    'hasLocalPath': storedPath != null && storedPath.isNotEmpty,
    'localPathKind': _mediaDownloadPathKind(storedPath),
    'localPath': storedPath,
    'resolvedPath': resolvedPath,
    'resolvedPathKind': _mediaDownloadPathKind(resolvedPath),
    'resolvedFileExists': fileExists,
    'resolvedFileBytes': fileBytes,
    'reason': reason,
  };
  if (resolveError != null) {
    details['resolveError'] = resolveError;
  }
  return details;
}

Future<List<Map<String, Object?>>> _collectLocalMediaCandidateDiagnostics({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required MediaAttachment attachment,
  required bool allowStatusRepair,
  required MediaOwnerLane owner,
  bool includeInputCandidate = true,
}) async {
  final candidates = await _localMediaAttachmentCandidates(
    mediaAttachmentRepo: mediaAttachmentRepo,
    attachment: attachment,
    owner: owner,
    includeInputCandidate: includeInputCandidate,
  );
  final diagnostics = <Map<String, Object?>>[];
  for (var i = 0; i < candidates.length; i += 1) {
    diagnostics.add(
      await _localMediaCandidateDiagnostic(
        mediaFileManager: mediaFileManager,
        candidate: candidates[i],
        index: i,
        allowStatusRepair: allowStatusRepair,
      ),
    );
  }
  return diagnostics;
}

String _mediaDownloadLocalMissReason(
  List<Map<String, Object?>> diagnostics, {
  required bool encryptedCompanionFoundBeforeRestore,
}) {
  if (encryptedCompanionFoundBeforeRestore) {
    return 'encrypted_companion_unusable';
  }
  if (diagnostics.isEmpty) {
    return 'no_attachment_candidate';
  }
  final reasons = diagnostics
      .map((diagnostic) => diagnostic['reason'])
      .whereType<String>()
      .toList(growable: false);
  if (reasons.every((reason) => reason == 'no_local_path')) {
    return 'no_local_path';
  }
  for (final reason in const [
    'local_file_missing',
    'status_not_done',
    'file_stat_failed',
  ]) {
    if (reasons.contains(reason)) {
      return reason;
    }
  }
  return 'no_completed_local_candidate';
}

/// Read-only authorization of every path one strict-private explicit download
/// may touch: the canonical target, the legacy LAN ciphertext sibling, and the
/// deterministic staging pair. Nothing is created, so a refusal is free.
Future<bool> _authorizesStrictPrivateDownloadPaths({
  required MediaFileManager mediaFileManager,
  required String contactPeerId,
  required MediaAttachment attachment,
}) async {
  final authorityRoot = await mediaFileManager.trustedMediaRootPath();
  final canonical = await mediaFileManager.resolveStoredPath(
    mediaFileManager.relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: attachment.id,
      mime: attachment.mime,
    ),
  );
  for (final target in <String>[
    canonical,
    '$canonical.enc',
    StrictDirectMediaBlobDownloadAckOwner.privateCiphertextStagingPath(
      canonical,
    ),
    StrictDirectMediaBlobDownloadAckOwner.privateDecryptStagingPath(canonical),
  ]) {
    if (!await DirectPrivateMediaPathGuard.authorizeTarget(
      targetPath: target,
      authorityRoot: authorityRoot,
    )) {
      return false;
    }
  }
  return true;
}

/// The exact durable direct attachment whose canonical plaintext already
/// exists on disk, or null.
Future<MediaAttachment?> _durableLocalDirectAttachment({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required MediaAttachment attachment,
}) async {
  final persisted = await mediaAttachmentRepo.getAttachmentsForMessage(
    attachment.messageId,
    owner: MediaOwnerLane.direct,
  );
  for (final candidate in persisted) {
    if (candidate.id != attachment.id ||
        candidate.downloadStatus != kMediaDownloadStatusDone ||
        candidate.localPath == null ||
        candidate.localPath!.isEmpty) {
      continue;
    }
    final absolute = await mediaFileManager.resolveStoredPath(
      candidate.localPath!,
    );
    if (await File(absolute).exists()) {
      return candidate.copyWith(ownerLane: MediaOwnerLane.direct);
    }
  }
  return null;
}

/// Reloads the row the private claim just changed and proves it is still the
/// same durable transfer subject in the exact `downloading` state.
///
/// The caller's snapshot came from the UI and may be arbitrarily stale; only
/// this reloaded row may be handed to the strict owner.
Future<MediaAttachment?> _requalifyClaimedPrivateAttachment({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaAttachment attachment,
}) async {
  final persisted = await mediaAttachmentRepo.getAttachmentsForMessage(
    attachment.messageId,
    owner: MediaOwnerLane.direct,
  );
  final exact = persisted.where((item) => item.id == attachment.id);
  if (exact.length != 1) return null;
  final current = exact.single;
  if (current.messageId != attachment.messageId ||
      current.ownerLane != MediaOwnerLane.direct ||
      current.mime != attachment.mime ||
      current.mediaType != attachment.mediaType ||
      current.size != attachment.size ||
      current.width != attachment.width ||
      current.height != attachment.height ||
      current.durationMs != attachment.durationMs ||
      current.contentHash != attachment.contentHash ||
      current.encryptionKeyBase64 != attachment.encryptionKeyBase64 ||
      current.encryptionNonce != attachment.encryptionNonce ||
      current.encryptionScheme != attachment.encryptionScheme ||
      current.downloadStatus != kMediaDownloadStatusDownloading) {
    return null;
  }
  return current;
}

Future<MediaAttachment?> downloadMedia({
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required MediaAttachment attachment,
  required String contactPeerId,
  required MediaOwnerLane owner,
  MessageRepository? messageRepo,
  GroupMessageRepository? groupMessageRepo,
  MediaDownloadIntent? intent,
  bool enforceGroupMediaPolicy = false,
  Duration? transferStallTimeout,
  Duration? transferMaxTimeout,
  // Test-only scheduling seam. Production callers leave this null so the
  // scrub retains the transfer watchdog's existing maximum-delay authority.
  Duration? latePrivateTransferScrubDelay,
  int Function()? nowMs,
  // Compile-gated attempt observer used only by the main-app Android proof.
  // It counts an eligible ordinary automatic-group invocation before local
  // encrypted-companion recovery, so a fresh-process recovery is still an
  // honest second attempt even when it avoids a redundant relay transfer.
  GroupMediaAutomaticDownloadAttemptStarted?
  groupMediaAutomaticDownloadAttemptStarted,
  // Compile-gated main-app E2E seam. Production leaves this null. It is
  // reached only by an ordinary automatic group download after the exact
  // durable claim and one successful relay attempt, before validation,
  // promotion, or commit.
  GroupMediaPostClaimPreCommit? groupMediaPostClaimPreCommit,
}) async {
  int currentNowMs() =>
      nowMs?.call() ?? DateTime.now().toUtc().millisecondsSinceEpoch;

  final effectiveIntent = intent ?? MediaDownloadIntent.automatic;
  var requiresDirectPrivateCommit = false;
  DirectPrivateMediaDownloadStateRepository? directPrivateDownloadRepo;
  DirectPrivateMediaCleanupRuntime? directPrivateRuntime;
  OrdinaryGroupMediaDownloadFailureRepository? ordinaryGroupDownloadFailureRepo;
  OrdinaryGroupAutomaticMediaDownloadStateRepository?
  ordinaryGroupAutomaticDownloadStateRepo;
  OrdinaryGroupExplicitMediaDownloadStateRepository?
  ordinaryGroupExplicitDownloadStateRepo;
  var ordinaryGroupDownloadClaimed = false;
  var ordinaryGroupExpectedDownloadStatus = attachment.downloadStatus;
  String? ordinaryGroupExpectedLocalPath = attachment.localPath;
  if (owner == MediaOwnerLane.direct && !enforceGroupMediaPolicy) {
    if (!DirectPrivateMediaPathGuard.identifiersAreSafe(
      contactPeerId: contactPeerId,
      messageId: attachment.messageId,
      attachmentId: attachment.id,
    )) {
      return null;
    }
    if (messageRepo == null) return null;
    final currentParent = await messageRepo.getMessage(attachment.messageId);
    if (currentParent == null) return null;
    final policy = currentParent.privateMediaPolicy;
    final parentDecision = DirectPrivateMediaActionEligibility.evaluate(
      parent: currentParent,
      attachment: null,
      expectedMessageId: attachment.messageId,
      attachmentRequired: false,
    );
    if (!parentDecision.allows(DirectPrivateMediaAction.explicitDownload)) {
      return null;
    }
    requiresDirectPrivateCommit = policy.requiresRedaction;
    if (requiresDirectPrivateCommit) {
      if (contactPeerId != currentParent.contactPeerId) return null;
      final persisted = await mediaAttachmentRepo.getAttachmentsForMessage(
        currentParent.id,
        owner: MediaOwnerLane.direct,
      );
      final exactRows = persisted.where((item) => item.id == attachment.id);
      if (exactRows.length != 1) return null;
      final exact = exactRows.single;
      final exactDecision = DirectPrivateMediaActionEligibility.evaluate(
        parent: currentParent,
        attachment: exact,
        expectedMessageId: attachment.messageId,
        expectedAttachmentId: attachment.id,
      );
      if (!exactDecision.allows(DirectPrivateMediaAction.explicitDownload)) {
        return null;
      }
      // Private byte-routing authority comes only from the exact current row.
      if (exact.messageId != attachment.messageId ||
          exact.mime != attachment.mime ||
          exact.mediaType != attachment.mediaType ||
          exact.size != attachment.size ||
          exact.localPath != attachment.localPath ||
          exact.downloadStatus != attachment.downloadStatus ||
          exact.encryptionKeyBase64 != attachment.encryptionKeyBase64 ||
          exact.encryptionNonce != attachment.encryptionNonce ||
          exact.encryptionScheme != attachment.encryptionScheme) {
        return null;
      }
      if (!DirectPrivateMediaPathGuard.identifiersAreSafe(
            contactPeerId: currentParent.contactPeerId,
            messageId: currentParent.id,
            attachmentId: attachment.id,
          ) ||
          mediaAttachmentRepo is! DirectPrivateMediaDownloadStateRepository ||
          mediaAttachmentRepo is! DirectPrivateMediaCleanupRuntime) {
        return null;
      }
      directPrivateDownloadRepo =
          mediaAttachmentRepo as DirectPrivateMediaDownloadStateRepository;
      directPrivateRuntime =
          mediaAttachmentRepo as DirectPrivateMediaCleanupRuntime;
    }
    if (policy.requiresRedaction &&
        (effectiveIntent != MediaDownloadIntent.explicitUser ||
            !policy.allowsExplicitDownload(currentParent.privateMediaState))) {
      return null;
    }
  } else if (owner == MediaOwnerLane.group && enforceGroupMediaPolicy) {
    if (groupMessageRepo == null) return null;
    var currentParent = await groupMessageRepo.getMessage(attachment.messageId);
    if (currentParent == null || currentParent.groupId != contactPeerId) {
      return null;
    }
    final policy = currentParent.privateMediaPolicy;
    if (policy.requiresRedaction) {
      if (groupMessageRepo is! GroupPrivateMediaLifecycleRepository ||
          mediaAttachmentRepo is! GroupPrivateMediaDownloadStateRepository ||
          mediaAttachmentRepo is! GroupPrivateMediaCleanupRuntime ||
          !currentParent.isIncoming ||
          !policy.isPrivate ||
          effectiveIntent != MediaDownloadIntent.explicitUser ||
          currentParent.mediaConsumedAt != null ||
          currentParent.mediaExpiredAt != null ||
          currentParent.mediaCleanupPending ||
          !DirectPrivateMediaPathGuard.identifiersAreSafe(
            contactPeerId: contactPeerId,
            messageId: attachment.messageId,
            attachmentId: attachment.id,
          )) {
        return null;
      }
      final lifecycleRepository =
          groupMessageRepo as GroupPrivateMediaLifecycleRepository;
      if (policy.lifecycle == GroupMediaLifecycle.disappearing) {
        await lifecycleRepository.advanceGroupPrivateMediaClock(
          currentParent.id,
          nowMs: currentNowMs(),
        );
        currentParent = await lifecycleRepository.loadGroupPrivateMediaMessage(
          currentParent.id,
        );
        if (currentParent == null ||
            currentParent.mediaExpiredAt != null ||
            currentParent.mediaCleanupPending) {
          return null;
        }
      }
      final persisted = await mediaAttachmentRepo.getAttachmentsForMessage(
        currentParent.id,
        owner: MediaOwnerLane.group,
      );
      final exactRows = persisted.where((item) => item.id == attachment.id);
      if (exactRows.length != 1) return null;
      final exact = exactRows.single;
      if (exact.messageId != attachment.messageId ||
          exact.ownerLane != MediaOwnerLane.group ||
          exact.mime != attachment.mime ||
          exact.mediaType != attachment.mediaType ||
          exact.size != attachment.size ||
          exact.localPath != attachment.localPath ||
          exact.downloadStatus != attachment.downloadStatus ||
          exact.encryptionKeyBase64 != attachment.encryptionKeyBase64 ||
          exact.encryptionNonce != attachment.encryptionNonce ||
          exact.encryptionScheme != attachment.encryptionScheme) {
        return null;
      }
      requiresDirectPrivateCommit = true;
      final groupRuntime =
          mediaAttachmentRepo as GroupPrivateMediaCleanupRuntime;
      directPrivateDownloadRepo = _GroupPrivateDownloadStateAdapter(
        delegate:
            mediaAttachmentRepo as GroupPrivateMediaDownloadStateRepository,
        runtime: groupRuntime,
        groupId: contactPeerId,
      );
      directPrivateRuntime = _GroupPrivateCleanupRuntimeAdapter(groupRuntime);
    } else {
      if (!currentParent.isIncoming ||
          mediaAttachmentRepo is! OrdinaryGroupMediaDownloadFailureRepository) {
        return null;
      }
      ordinaryGroupDownloadFailureRepo =
          mediaAttachmentRepo as OrdinaryGroupMediaDownloadFailureRepository;
      if (effectiveIntent == MediaDownloadIntent.automatic) {
        if (mediaAttachmentRepo
            is! OrdinaryGroupAutomaticMediaDownloadStateRepository) {
          return null;
        }
        ordinaryGroupAutomaticDownloadStateRepo =
            mediaAttachmentRepo
                as OrdinaryGroupAutomaticMediaDownloadStateRepository;
      } else {
        if (mediaAttachmentRepo
            is! OrdinaryGroupExplicitMediaDownloadStateRepository) {
          return null;
        }
        ordinaryGroupExplicitDownloadStateRepo =
            mediaAttachmentRepo
                as OrdinaryGroupExplicitMediaDownloadStateRepository;
      }
    }
  }
  // 354: an explicit-user private strict download enters the SAME sole strict
  // owner. The exact attachment-scoped private transfer token and the DB
  // `downloading` claim are acquired BEFORE its first network callback, and it
  // uses deterministic convention-owned staging siblings so private cleanup
  // and restart recovery can enumerate them. Automatic private download stays
  // refused: this branch requires explicit user intent.
  if (owner == MediaOwnerLane.direct &&
      !enforceGroupMediaPolicy &&
      requiresDirectPrivateCommit &&
      effectiveIntent == MediaDownloadIntent.explicitUser &&
      directPrivateDownloadRepo != null &&
      directPrivateRuntime != null &&
      mediaAttachmentRepo is DirectMediaBlobCustodyRepository &&
      mediaAttachmentRepo is IncomingDirectMediaBlobCustodyRepository) {
    final custodyRepository =
        mediaAttachmentRepo as DirectMediaBlobCustodyRepository;
    final custody = custodyRepository.supportsDirectMediaBlobCustody
        ? await custodyRepository.loadDirectMediaBlobCustodyForAttachment(
            attachment.id,
          )
        : null;
    if (custody != null &&
        custody.direction == DirectMediaBlobCustodyDirection.incoming &&
        (custody.state == DirectMediaBlobCustodyState.incomingCommitted ||
            custody.state == DirectMediaBlobCustodyState.incomingAckPending)) {
      StrictDirectMediaBlobDownloadAckOwner strictOwner() =>
          StrictDirectMediaBlobDownloadAckOwner(
            bridge: bridge,
            mediaAttachmentRepository: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            privateDeterministicStaging: true,
            now: () => DateTime.fromMillisecondsSinceEpoch(
              currentNowMs(),
              isUtc: true,
            ),
          );
      // Read-only path preflight BEFORE the durable claim. Nothing is created
      // here, so an unsafe canonical/LAN/staging target refuses with zero
      // network and zero durable mutation.
      if (!await _authorizesStrictPrivateDownloadPaths(
        mediaFileManager: mediaFileManager,
        contactPeerId: contactPeerId,
        attachment: attachment,
      )) {
        return null;
      }
      final durableLocal = await _durableLocalDirectAttachment(
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        attachment: attachment,
      );
      // Pinned strict state table. No row in these states may fall through to
      // the proof-less legacy transport, and no branch may ACK away custody
      // the receiver cannot prove it already holds locally.
      if (custody.state == DirectMediaBlobCustodyState.incomingAckPending) {
        if (durableLocal == null) {
          // ACK-pending without exact durable local bytes: never claim,
          // download, ACK, or delete v111. Expiry remains its only converger.
          return null;
        }
        // Retry only the source-pinned ACK against the persisted relay.
        return strictOwner().downloadAndAcknowledge(
          attachment: durableLocal,
          contactPeerId: contactPeerId,
        );
      }
      final expiresAtMs = custody.expiresAtMs;
      if (durableLocal != null ||
          (expiresAtMs != null && expiresAtMs <= currentNowMs())) {
        // Committed + already durable adopts without ACK; an exact expiry
        // converges through the existing expiry transition. Neither claims the
        // row, and neither performs network work.
        return strictOwner().downloadAndAcknowledge(
          attachment: durableLocal ?? attachment.copyWith(
            ownerLane: MediaOwnerLane.direct,
          ),
          contactPeerId: contactPeerId,
        );
      }
      final lock = directPrivateRuntime.directPrivateMediaLifecycleLock;
      final claim = await lock.synchronized(attachment.id, () async {
        final claimed = directPrivateMediaTransferRegistry.tryBegin(
          attachment.id,
          messageId: attachment.messageId,
        );
        if (claimed == null) return null;
        final began = await directPrivateDownloadRepo!
            .beginDirectPrivateMediaDownloadWithinLock(
              attachment.id,
              messageId: attachment.messageId,
              nowMs: currentNowMs(),
            );
        if (!began) {
          directPrivateMediaTransferRegistry.end(attachment.id, claimed);
          return null;
        }
        // The claim, not the caller's UI snapshot, is the transfer's
        // authority. Reload the row it just changed and requalify every
        // immutable dimension plus the exact `downloading` state before any
        // network work can consume it.
        final reloaded = await _requalifyClaimedPrivateAttachment(
          mediaAttachmentRepo: mediaAttachmentRepo,
          attachment: attachment,
        );
        if (reloaded == null) {
          await directPrivateDownloadRepo
              .recordDirectPrivateMediaDownloadFailureWithinLock(
                attachment.id,
                messageId: attachment.messageId,
                nowMs: currentNowMs(),
                incrementRetryCount: false,
                failureStatus: kMediaDownloadStatusDownloadFailed,
                expectedDownloadStatus: kMediaDownloadStatusDownloading,
              );
          directPrivateMediaTransferRegistry.end(attachment.id, claimed);
          return null;
        }
        return (token: claimed, row: reloaded);
      });
      if (claim == null) return null;
      var committed = false;
      try {
        final downloaded = await strictOwner().downloadAndAcknowledge(
          attachment: claim.row,
          contactPeerId: contactPeerId,
        );
        committed = downloaded != null;
        return downloaded;
      } finally {
        await lock.synchronized(attachment.id, () async {
          if (!committed) {
            // Every non-committed outcome after a successful claim — pre-
            // network path drift, transport/proof/decrypt/output refusal, or
            // a lost final CAS — releases `downloading` back to a retryable
            // status. v111 is deliberately untouched.
            await directPrivateDownloadRepo!
                .recordDirectPrivateMediaDownloadFailureWithinLock(
                  attachment.id,
                  messageId: attachment.messageId,
                  nowMs: currentNowMs(),
                  incrementRetryCount: false,
                  failureStatus: kMediaDownloadStatusDownloadFailed,
                  expectedDownloadStatus: kMediaDownloadStatusDownloading,
                );
          }
          directPrivateMediaTransferRegistry.end(attachment.id, claim.token);
        });
      }
    }
    // A fingerprinted strict-private row with missing, crossed, expired or
    // unsupported v111 state fails closed here. Only a pre-354 private parent
    // with no strict fingerprint and no v111 keeps the legacy explicit path.
    if (custody != null ||
        attachment.blobCustody != null ||
        attachment.directMediaBlobCustodyFingerprint != null ||
        (await mediaAttachmentRepo.getAttachmentsForMessage(
          attachment.messageId,
          owner: MediaOwnerLane.direct,
        )).any(
          (candidate) =>
              candidate.id == attachment.id &&
              candidate.directMediaBlobCustodyFingerprint != null,
        )) {
      return null;
    }
  }
  if (owner == MediaOwnerLane.direct &&
      !enforceGroupMediaPolicy &&
      !requiresDirectPrivateCommit &&
      mediaAttachmentRepo is DirectMediaBlobCustodyRepository &&
      mediaAttachmentRepo is IncomingDirectMediaBlobCustodyRepository) {
    final custody =
        await (mediaAttachmentRepo as DirectMediaBlobCustodyRepository)
            .loadDirectMediaBlobCustodyForAttachment(attachment.id);
    if (custody != null &&
        custody.direction == DirectMediaBlobCustodyDirection.incoming) {
      return StrictDirectMediaBlobDownloadAckOwner(
        bridge: bridge,
        mediaAttachmentRepository: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        now: () =>
            DateTime.fromMillisecondsSinceEpoch(currentNowMs(), isUtc: true),
      ).downloadAndAcknowledge(
        attachment: attachment.copyWith(ownerLane: MediaOwnerLane.direct),
        contactPeerId: contactPeerId,
      );
    }
    // Public strict authority and its local one-way adoption fingerprint must
    // never cross into the proof-less legacy download/delete path, even after
    // exact ACK or expiry convergence has removed v111.
    if (attachment.blobCustody != null ||
        attachment.directMediaBlobCustodyFingerprint != null) {
      return null;
    }
    final currentAttachments = await mediaAttachmentRepo
        .getAttachmentsForMessage(
          attachment.messageId,
          owner: MediaOwnerLane.direct,
        );
    if (currentAttachments.any(
      (candidate) =>
          candidate.id == attachment.id &&
          candidate.directMediaBlobCustodyFingerprint != null,
    )) {
      return null;
    }
  }
  final inFlightKey = _MediaDownloadInFlightKey(
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
    contactPeerId: contactPeerId,
    attachmentId: attachment.id,
    mime: attachment.mime,
    enforceGroupMediaPolicy: enforceGroupMediaPolicy,
    requiresDirectPrivateCommit: requiresDirectPrivateCommit,
    encryptionDiscriminator:
        '${attachment.encryptionKeyBase64 ?? ''}|'
        '${attachment.encryptionNonce ?? ''}|'
        '${attachment.encryptionScheme ?? ''}',
  );
  // Never let a guarded private request share an ordinary future, and never
  // race the two commit protocols against the same staged/canonical paths.
  // The later request fails closed and may be retried after the current
  // transfer settles.
  if (_inFlightMediaDownloads.keys.any(
    (existing) => existing.conflictsWith(inFlightKey),
  )) {
    return null;
  }
  final inFlight = _inFlightMediaDownloads[inFlightKey];
  if (inFlight != null) {
    return inFlight;
  }

  late final Future<MediaAttachment?> downloadFuture;
  Future<MediaAttachment?> runDownload() async {
    if (ordinaryGroupAutomaticDownloadStateRepo != null &&
        groupMediaAutomaticDownloadAttemptStarted != null) {
      await groupMediaAutomaticDownloadAttemptStarted(attachment);
    }
    final downloadStopwatch = Stopwatch()..start();
    final idPrefix = attachment.id.length > 8
        ? attachment.id.substring(0, 8)
        : attachment.id;
    final ordinaryGroupDownloadAuthorityKind =
        ordinaryGroupAutomaticDownloadStateRepo != null
        ? 'automatic'
        : ordinaryGroupExplicitDownloadStateRepo != null
        ? 'explicit'
        : null;
    void emitDownloadTiming({
      required String outcome,
      Map<String, dynamic> details = const {},
    }) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DOWNLOAD_TIMING',
        details: {
          'elapsedMs': downloadStopwatch.elapsedMilliseconds,
          'outcome': outcome,
          'blobId': idPrefix,
          'mime': attachment.mime,
          'sizeBytes': attachment.size,
          ...details,
        },
      );
    }

    Future<bool> claimOrdinaryGroupDownloadIfNeeded({
      required bool companion,
    }) async {
      final authorityKind = ordinaryGroupDownloadAuthorityKind;
      if (authorityKind == null || ordinaryGroupDownloadClaimed) {
        return true;
      }
      final claimed = ordinaryGroupAutomaticDownloadStateRepo != null
          ? await ordinaryGroupAutomaticDownloadStateRepo
                .beginOrdinaryGroupAutomaticMediaDownload(
                  attachment.id,
                  groupId: contactPeerId,
                  messageId: attachment.messageId,
                  expectedDownloadStatus: ordinaryGroupExpectedDownloadStatus,
                  expectedLocalPath: ordinaryGroupExpectedLocalPath,
                )
          : await ordinaryGroupExplicitDownloadStateRepo!
                .beginOrdinaryGroupExplicitMediaDownload(
                  attachment.id,
                  groupId: contactPeerId,
                  messageId: attachment.messageId,
                  expectedDownloadStatus: ordinaryGroupExpectedDownloadStatus,
                  expectedLocalPath: ordinaryGroupExpectedLocalPath,
                );
      if (!claimed) {
        final phase = companion
            ? 'group_${authorityKind}_companion_begin'
            : 'group_${authorityKind}_begin';
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_DOWNLOAD_CLAIM_LOST',
          details: {'blobId': idPrefix, 'phase': phase},
        );
        emitDownloadTiming(
          outcome: 'failed',
          details: {
            'error': companion
                ? 'group_${authorityKind}_companion_claim_lost'
                : 'group_${authorityKind}_download_claim_lost',
          },
        );
        return false;
      }
      ordinaryGroupDownloadClaimed = true;
      return true;
    }

    Future<bool> commitOrdinaryGroupDownloadLocalPath(String localPath) {
      final automaticRepository = ordinaryGroupAutomaticDownloadStateRepo;
      if (automaticRepository != null) {
        return automaticRepository
            .commitOrdinaryGroupAutomaticMediaDownloadLocalPath(
              attachment.id,
              groupId: contactPeerId,
              messageId: attachment.messageId,
              expectedLocalPath: ordinaryGroupExpectedLocalPath,
              localPath: localPath,
            );
      }
      return ordinaryGroupExplicitDownloadStateRepo!
          .commitOrdinaryGroupExplicitMediaDownloadLocalPath(
            attachment.id,
            groupId: contactPeerId,
            messageId: attachment.messageId,
            expectedLocalPath: ordinaryGroupExpectedLocalPath,
            localPath: localPath,
          );
    }

    Future<bool> recordOrdinaryGroupDownloadFailure({
      required bool incrementRetryCount,
      required String failureStatus,
      required String expectedDownloadStatus,
      required String? expectedLocalPath,
      required bool clearLocalPath,
    }) async {
      final repository = ordinaryGroupDownloadFailureRepo;
      if (repository == null) return false;
      try {
        final changed = await repository
            .recordOrdinaryGroupMediaDownloadFailure(
              attachment.id,
              groupId: contactPeerId,
              messageId: attachment.messageId,
              incrementRetryCount: incrementRetryCount,
              failureStatus: failureStatus,
              expectedDownloadStatus: expectedDownloadStatus,
              expectedLocalPath: expectedLocalPath,
              clearLocalPath: clearLocalPath,
            );
        if (changed && clearLocalPath) {
          ordinaryGroupExpectedLocalPath = null;
        }
        return changed;
      } catch (e) {
        // Failure persistence is already the terminal consumer boundary for
        // this attempt. Swallowing here prevents the outer transport catch
        // from issuing a second, potentially different failure projection.
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_GROUP_DOWNLOAD_FAILURE_PERSISTENCE_ERROR',
          details: {
            'blobId': idPrefix,
            'attachmentId': attachment.id,
            'messageId': attachment.messageId,
            'failureStatus': failureStatus,
            'error': e.toString(),
          },
        );
        return false;
      }
    }

    // Bounded download retry budget (Finding 09 Phase 3, INV-DL-1/2/5).
    // Each transient download failure persists download_retry_count + 1:
    // the status goes through updateDownloadStatus (single-column, kept for
    // observability), and the counter through a full-row saveAttachment
    // (updateDownloadStatus cannot carry it). At/over the ceiling the row
    // flips to the terminal `download_failed` status. A successful local
    // path commit resets the counter to 0 (see dbUpdateMediaLocalPath).
    Future<String> persistTransientDownloadFailure({
      bool clearLocalPath = false,
      String expectedDownloadStatus = kMediaDownloadStatusDownloading,
      String? expectedLocalPath,
      bool privateLockHeld = false,
    }) async {
      final nextCount = (attachment.downloadRetryCount ?? 0) + 1;
      final status = nextCount >= kMaxDownloadRetries
          ? kMediaDownloadStatusDownloadFailed
          : kMediaDownloadStatusFailed;
      if (requiresDirectPrivateCommit) {
        final repository = directPrivateDownloadRepo!;
        if (privateLockHeld) {
          await repository.recordDirectPrivateMediaDownloadFailureWithinLock(
            attachment.id,
            messageId: attachment.messageId,
            nowMs: currentNowMs(),
            incrementRetryCount: true,
            failureStatus: kMediaDownloadStatusFailed,
            expectedDownloadStatus: expectedDownloadStatus,
            expectedLocalPath: expectedLocalPath,
            clearLocalPath: clearLocalPath,
          );
        } else {
          await repository.recordDirectPrivateMediaDownloadFailure(
            attachment.id,
            messageId: attachment.messageId,
            nowMs: currentNowMs(),
            incrementRetryCount: true,
            failureStatus: kMediaDownloadStatusFailed,
            expectedDownloadStatus: expectedDownloadStatus,
            expectedLocalPath: expectedLocalPath,
            clearLocalPath: clearLocalPath,
          );
        }
        return status;
      }
      if (ordinaryGroupDownloadFailureRepo != null) {
        await recordOrdinaryGroupDownloadFailure(
          incrementRetryCount: true,
          failureStatus: kMediaDownloadStatusFailed,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath:
              expectedLocalPath ?? ordinaryGroupExpectedLocalPath,
          clearLocalPath: clearLocalPath,
        );
        return status;
      }
      try {
        await mediaAttachmentRepo.updateDownloadStatus(attachment.id, status);
      } catch (_) {}
      try {
        await mediaAttachmentRepo.saveAttachment(
          attachment.copyWith(
            downloadStatus: status,
            downloadRetryCount: nextCount,
            clearLocalPath: clearLocalPath,
          ),
          owner: owner,
        );
      } catch (_) {}
      return status;
    }

    // Honest "expired / unavailable on the relay" terminal state, reached
    // immediately on a relay "not found" / "not authorized" response,
    // WITHOUT consuming the bounded retry budget (INV-DL-4).
    Future<void> markRelayUnavailableDownloadFailed() async {
      if (requiresDirectPrivateCommit) {
        await directPrivateDownloadRepo!
            .recordDirectPrivateMediaDownloadFailure(
              attachment.id,
              messageId: attachment.messageId,
              nowMs: currentNowMs(),
              incrementRetryCount: false,
              failureStatus: kMediaDownloadStatusDownloadFailed,
              expectedDownloadStatus: kMediaDownloadStatusDownloading,
            );
        return;
      }
      if (ordinaryGroupDownloadFailureRepo != null) {
        await recordOrdinaryGroupDownloadFailure(
          incrementRetryCount: false,
          failureStatus: kMediaDownloadStatusDownloadFailed,
          expectedDownloadStatus: kMediaDownloadStatusDownloading,
          expectedLocalPath: ordinaryGroupExpectedLocalPath,
          clearLocalPath: false,
        );
        return;
      }
      try {
        await mediaAttachmentRepo.updateDownloadStatus(
          attachment.id,
          kMediaDownloadStatusDownloadFailed,
        );
      } catch (_) {}
      try {
        await mediaAttachmentRepo.saveAttachment(
          attachment.copyWith(
            downloadStatus: kMediaDownloadStatusDownloadFailed,
          ),
          owner: owner,
        );
      } catch (_) {}
    }

    bool isRelayUnavailableError(Object? errorMessage) {
      final text = errorMessage?.toString().toLowerCase() ?? '';
      return text.contains('not found') || text.contains('not authorized');
    }

    Future<MediaAttachment?> completedLocalAttachment({
      required bool allowStatusRepair,
    }) async {
      final candidates = await _localMediaAttachmentCandidates(
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachment: attachment,
        owner: owner,
        includeInputCandidate: !requiresDirectPrivateCommit,
      );

      for (final candidate in candidates) {
        final storedPath = candidate.localPath;
        if (storedPath == null || storedPath.isEmpty) {
          continue;
        }

        if (requiresDirectPrivateCommit) {
          if (candidate.downloadStatus != kMediaDownloadStatusDone ||
              candidate.size <= 0 ||
              !DirectPrivateMediaPathGuard.identifiersAreSafe(
                contactPeerId: contactPeerId,
                messageId: candidate.messageId,
                attachmentId: candidate.id,
              )) {
            continue;
          }
          final expectedRelative = mediaFileManager.relativePathForAttachment(
            contactPeerId: contactPeerId,
            blobId: candidate.id,
            mime: candidate.mime,
          );
          final expectedAbsolute = await mediaFileManager.resolveStoredPath(
            expectedRelative,
          );
          final normalizedStored = p.normalize(
            storedPath.replaceAll('\\', '/'),
          );
          if (normalizedStored != p.normalize(expectedRelative) &&
              normalizedStored != p.normalize(expectedAbsolute)) {
            continue;
          }
          final root = p.dirname(p.dirname(expectedAbsolute));
          final ready = await directPrivateRuntime!
              .directPrivateMediaLifecycleLock
              .synchronized(candidate.id, () async {
                final qualified = await directPrivateDownloadRepo!
                    .qualifyDirectPrivateMediaLocalReadyWithinLock(
                      candidate.id,
                      messageId: candidate.messageId,
                      expectedLocalPath: storedPath,
                      nowMs: currentNowMs(),
                    );
                if (!qualified ||
                    !await DirectPrivateMediaPathGuard.authorizeTarget(
                      targetPath: expectedAbsolute,
                      authorityRoot: root,
                      requireExistingFile: true,
                    )) {
                  return false;
                }
                try {
                  return await File(expectedAbsolute).length() ==
                      candidate.size;
                } catch (_) {
                  return false;
                }
              });
          if (!ready) continue;
          return candidate.copyWith(
            localPath: expectedAbsolute,
            downloadStatus: kMediaDownloadStatusDone,
          );
        }

        late final String resolvedPath;
        try {
          resolvedPath = await mediaFileManager.resolveStoredPath(storedPath);
        } catch (_) {
          resolvedPath = storedPath;
        }

        if (!await File(resolvedPath).exists()) {
          continue;
        }

        if (candidate.downloadStatus != kMediaDownloadStatusDone) {
          if (!allowStatusRepair) {
            continue;
          }
          try {
            await mediaAttachmentRepo.updateDownloadStatus(
              attachment.id,
              kMediaDownloadStatusDone,
            );
          } catch (_) {}
        }

        return candidate.copyWith(
          localPath: resolvedPath,
          downloadStatus: kMediaDownloadStatusDone,
        );
      }

      return null;
    }

    Future<MediaAttachment?> useCompletedLocalAttachmentIfAvailable({
      required String event,
      required bool allowStatusRepair,
      Map<String, dynamic> details = const {},
    }) async {
      final localAttachment = await completedLocalAttachment(
        allowStatusRepair: allowStatusRepair,
      );
      if (localAttachment == null) {
        return null;
      }

      emitFlowEvent(
        layer: 'FL',
        event: event,
        details: {
          'blobId': idPrefix,
          'status': localAttachment.downloadStatus,
          ...details,
        },
      );
      emitDownloadTiming(
        outcome: 'local_ready',
        details: {'source': 'local_path', ...details},
      );
      return localAttachment;
    }

    Future<MediaAttachment?> useCompletedGroupLocalAttachmentIfAvailable({
      required String event,
      Map<String, dynamic> details = const {},
    }) async {
      return useCompletedLocalAttachmentIfAvailable(
        event: event,
        allowStatusRepair: false,
        details: details,
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_DOWNLOAD_START',
      details: {'blobId': idPrefix, 'mime': attachment.mime},
    );

    Future<void> deleteIfExists(
      File file, {
      required String caller,
      required String reason,
      Map<String, Object?> details = const {},
    }) async {
      await deleteAppOwnedMediaFileIfExists(
        file: file,
        caller: caller,
        reason: reason,
        details: {
          'blobId': idPrefix,
          'attachmentId': attachment.id,
          'messageId': attachment.messageId,
          'mime': attachment.mime,
          'mediaType': attachment.mediaType,
          'enforceGroupMediaPolicy': enforceGroupMediaPolicy,
          ...details,
        },
        swallowErrors: true,
      );
    }

    Future<bool> verifyCommittedLocalPath({
      required String absolutePath,
      required String relativePath,
      required String source,
    }) async {
      final file = File(absolutePath);
      final exists = await file.exists();
      final bytes = exists ? await file.length() : 0;
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DOWNLOAD_DURABLE_LOCAL_PATH_COMMITTED',
        details: {
          'blobId': idPrefix,
          'attachmentId': attachment.id,
          'messageId': attachment.messageId,
          'mime': attachment.mime,
          'mediaType': attachment.mediaType,
          'source': source,
          'relativePath': relativePath,
          'relativePathKind': _mediaDownloadPathKind(relativePath),
          'absolutePathKind': _mediaDownloadPathKind(absolutePath),
          'fileExists': exists,
          'fileBytes': bytes,
          'expectedBytes': attachment.size,
        },
      );
      if (exists && bytes > 0) {
        if (enforceGroupMediaPolicy) {
          _scheduleGroupMediaDownloadPostCommitProbes(
            absolutePath: absolutePath,
            relativePath: relativePath,
            source: source,
            blobId: idPrefix,
            attachmentId: attachment.id,
            messageId: attachment.messageId,
            mime: attachment.mime,
            mediaType: attachment.mediaType,
            expectedBytes: attachment.size,
          );
        }
        return true;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DOWNLOAD_DURABLE_LOCAL_PATH_MISSING_AFTER_COMMIT',
        details: {
          'blobId': idPrefix,
          'attachmentId': attachment.id,
          'messageId': attachment.messageId,
          'mime': attachment.mime,
          'source': source,
          'relativePath': relativePath,
          'fileExists': exists,
          'fileBytes': bytes,
        },
      );
      // Durable path missing after commit: bounded transient failure, and
      // clear the now-dangling local path.
      await persistTransientDownloadFailure(
        clearLocalPath: true,
        expectedDownloadStatus:
            requiresDirectPrivateCommit ||
                ordinaryGroupDownloadFailureRepo != null
            ? kMediaDownloadStatusDone
            : kMediaDownloadStatusDownloading,
        expectedLocalPath:
            requiresDirectPrivateCommit ||
                ordinaryGroupDownloadFailureRepo != null
            ? relativePath
            : null,
      );
      return false;
    }

    String? cleanupDownloadPath;
    String? privateCanonicalPath;
    String? groupPrivateDecryptedPath;
    Object? privateTransferToken;
    var retainPrivateTransferForLateScrub = false;
    var ordinaryGroupCompanionRecoveryTerminated = false;

    Future<void> quarantineUnsafeGroupMedia({
      required String event,
      required Map<String, dynamic> details,
      Iterable<File> files = const [],
    }) async {
      if (requiresDirectPrivateCommit) {
        await directPrivateDownloadRepo!
            .recordDirectPrivateMediaDownloadFailure(
              attachment.id,
              messageId: attachment.messageId,
              nowMs: currentNowMs(),
              incrementRetryCount: false,
              failureStatus: kMediaDownloadStatusIntegrityFailed,
              expectedDownloadStatus: privateTransferToken == null
                  ? attachment.downloadStatus
                  : kMediaDownloadStatusDownloading,
              clearLocalPath: true,
            );
      } else if (ordinaryGroupDownloadFailureRepo != null) {
        await recordOrdinaryGroupDownloadFailure(
          incrementRetryCount: false,
          failureStatus: kMediaDownloadStatusIntegrityFailed,
          expectedDownloadStatus: ordinaryGroupDownloadClaimed
              ? kMediaDownloadStatusDownloading
              : attachment.downloadStatus,
          expectedLocalPath: ordinaryGroupExpectedLocalPath,
          clearLocalPath: true,
        );
      } else {
        await mediaAttachmentRepo.updateDownloadStatus(
          attachment.id,
          kMediaDownloadStatusIntegrityFailed,
        );
        try {
          await mediaAttachmentRepo.saveAttachment(
            attachment.copyWith(
              downloadStatus: kMediaDownloadStatusIntegrityFailed,
              clearLocalPath: true,
            ),
            owner: owner,
          );
        } catch (_) {}
      }
      for (final file in files) {
        await deleteIfExists(
          file,
          caller: 'downloadMedia.quarantineUnsafeGroupMedia',
          reason: details['reason']?.toString() ?? event,
          details: {'quarantineEvent': event, ...details},
        );
      }

      emitFlowEvent(layer: 'FL', event: event, details: details);
      emitDownloadTiming(
        outcome: 'failed',
        details: {'error': details['reason'] ?? details['error']},
      );
    }

    // Transient failures (watchdog timeout, bridge exception, relay
    // "not found") deliberately KEEP the staged download artifact: the
    // native side may have completed the write after the Dart side gave
    // up, and that `.part` can be the only surviving copy once the relay
    // blob is gone. Only explicit corrupt/invalid outcomes delete staged
    // bytes (see the invalid-downloaded-file branch below).
    Future<void> reportPreservedDownloadArtifacts({
      required String reason,
    }) async {
      final downloadPath = cleanupDownloadPath;
      if (downloadPath == null) {
        return;
      }
      final staged = File(downloadPath);
      final stagedExists = await staged.exists();
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DOWNLOAD_PART_PRESERVED',
        details: {
          'blobId': idPrefix,
          'attachmentId': attachment.id,
          'messageId': attachment.messageId,
          'mime': attachment.mime,
          'reason': reason,
          'stagedPath': downloadPath,
          'stagedExists': stagedExists,
          if (stagedExists) 'stagedBytes': await staged.length(),
        },
      );
    }

    Future<void> purgeExactPrivateTransferArtifacts({
      required String reason,
    }) async {
      if (!requiresDirectPrivateCommit) return;
      final canonicalPath = privateCanonicalPath;
      final stagedPath = cleanupDownloadPath;
      final paths = <String>{
        ?canonicalPath,
        ?stagedPath,
        ?groupPrivateDecryptedPath,
        if (stagedPath != null) '$stagedPath.dec',
      };
      for (final path in paths) {
        await deleteIfExists(
          File(path),
          caller: 'downloadMedia.purgeExactPrivateTransferArtifacts',
          reason: reason,
        );
      }
    }

    void scheduleLatePrivateTransferScrub() {
      final token = privateTransferToken;
      if (!requiresDirectPrivateCommit || token == null) return;
      retainPrivateTransferForLateScrub = true;
      final delay =
          latePrivateTransferScrubDelay ??
          transferMaxTimeout ??
          const Duration(minutes: 5);
      unawaited(
        Future<void>.delayed(delay, () async {
          try {
            await directPrivateRuntime!.directPrivateMediaLifecycleLock
                .synchronized(
                  attachment.id,
                  () =>
                      purgeExactPrivateTransferArtifacts(
                        reason: 'late_private_transfer_completion_scrub',
                      ).then((_) async {
                        await directPrivateDownloadRepo!
                            .recordDirectPrivateMediaDownloadFailureWithinLock(
                              attachment.id,
                              messageId: attachment.messageId,
                              nowMs: currentNowMs(),
                              incrementRetryCount: true,
                              failureStatus: kMediaDownloadStatusFailed,
                              expectedDownloadStatus:
                                  kMediaDownloadStatusDownloading,
                              clearLocalPath: true,
                            );
                      }),
                );
          } finally {
            directPrivateMediaTransferRegistry.end(attachment.id, token);
          }
        }),
      );
    }

    // Acknowledgement-based relay deletion: after the local copy is
    // durably committed, tell the relay to drop its copy. Fire-and-forget
    // — a failed ack must never affect the `done` status; the relay's
    // TTL sweep bounds unacked blobs. Group blobs are never acked
    // (other members still need them).
    void ackRelayBlobDeletion({required String source}) {
      if (enforceGroupMediaPolicy) {
        return;
      }
      unawaited(() async {
        try {
          final response = await callP2PMediaDelete(bridge, id: attachment.id);
          if (response['ok'] != true) {
            emitFlowEvent(
              layer: 'FL',
              event: 'MEDIA_ACK_DELETE_FAILED',
              details: {
                'blobId': idPrefix,
                'source': source,
                'error': response['errorMessage'] ?? 'delete_not_ok',
              },
            );
            return;
          }
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_RELAY_BLOB_ACK_DELETED',
            details: {'blobId': idPrefix, 'source': source},
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_ACK_DELETE_FAILED',
            details: {
              'blobId': idPrefix,
              'source': source,
              'error': e.toString(),
            },
          );
        }
      }());
    }

    try {
      if (enforceGroupMediaPolicy) {
        final descriptor = GroupMediaMimePolicy.validateDescriptor(
          mime: attachment.mime,
          mediaType: attachment.mediaType,
        );
        if (!descriptor.isValid) {
          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_MEDIA',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': descriptor.reason,
            },
          );
          return null;
        }
        // Receive side: permissive cross-type backstop, not per-type SEND
        // caps (do not quarantine media already within the cross-type max).
        final sizeValidation = GroupMediaSizePolicy.validateAttachments([
          attachment,
        ], perMediaLimitBytes: kGroupMediaPerAttachmentLimitBytes);
        if (!sizeValidation.isValid) {
          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_MEDIA',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': sizeValidation.reason,
            },
          );
          return null;
        }
        final contentHashValidation =
            GroupMediaIntegrityPolicy.validateRequiredContentHash(
              attachment.contentHash,
            );
        if (!contentHashValidation.isValid) {
          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_INTEGRITY',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': contentHashValidation.reason,
            },
          );
          return null;
        }
        if (!attachment.hasEncryptionMetadata) {
          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_ENCRYPTION',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': 'missing_media_encryption_metadata',
            },
          );
          return null;
        }
      }

      final alreadyLocal = await useCompletedLocalAttachmentIfAvailable(
        event: 'MEDIA_DOWNLOAD_SKIP_LOCAL_READY',
        allowStatusRepair: !enforceGroupMediaPolicy,
      );
      if (alreadyLocal != null) {
        return alreadyLocal;
      }

      // 1. Resolve absolute path for file I/O
      final absolutePath = await mediaFileManager.localPathForAttachment(
        contactPeerId: contactPeerId,
        blobId: attachment.id,
        mime: attachment.mime,
      );
      if (requiresDirectPrivateCommit) {
        privateCanonicalPath = absolutePath;
      }
      final relativePath = mediaFileManager.relativePathForAttachment(
        contactPeerId: contactPeerId,
        blobId: attachment.id,
        mime: attachment.mime,
      );
      // Ciphertext custody is scheme-agnostic: ANY key material stages
      // to `.enc` — unknown-scheme ciphertext must never stage as
      // `.part` (the plaintext promote path).
      final downloadPath =
          enforceGroupMediaPolicy || attachment.hasEncryptionKeyMaterial
          ? '$absolutePath.enc'
          : '$absolutePath.part';
      if (requiresDirectPrivateCommit) {
        final authorityRoot = p.dirname(p.dirname(absolutePath));
        final canonicalSafe = await DirectPrivateMediaPathGuard.authorizeTarget(
          targetPath: absolutePath,
          authorityRoot: authorityRoot,
        );
        final stagedSafe = await DirectPrivateMediaPathGuard.authorizeTarget(
          targetPath: downloadPath,
          authorityRoot: authorityRoot,
        );
        if (!canonicalSafe || !stagedSafe) return null;
      }
      cleanupDownloadPath = downloadPath;
      final encryptedCompanionFoundBeforeRestore = enforceGroupMediaPolicy
          ? await File(downloadPath).exists()
          : false;

      // Fail-closed handling for direct (1:1) encrypted media. Unlike
      // the group quarantine, the staged ciphertext artifact is always
      // PRESERVED and the relay copy is never acked (KC-3): within the
      // relay TTL either copy can still complete a later retry.
      Future<void> failClosedDirectEncryptedMedia({
        required String status,
        required String event,
        required Map<String, dynamic> details,
      }) async {
        if (status == kMediaDownloadStatusIntegrityFailed) {
          if (requiresDirectPrivateCommit) {
            await directPrivateDownloadRepo!
                .recordDirectPrivateMediaDownloadFailureWithinLock(
                  attachment.id,
                  messageId: attachment.messageId,
                  nowMs: currentNowMs(),
                  incrementRetryCount: false,
                  failureStatus: kMediaDownloadStatusIntegrityFailed,
                  expectedDownloadStatus: kMediaDownloadStatusDownloading,
                  clearLocalPath: true,
                );
          } else {
            await mediaAttachmentRepo.updateDownloadStatus(
              attachment.id,
              status,
            );
            try {
              await mediaAttachmentRepo.saveAttachment(
                attachment.copyWith(
                  downloadStatus: kMediaDownloadStatusIntegrityFailed,
                  clearLocalPath: true,
                ),
                owner: owner,
              );
            } catch (_) {}
          }
        } else {
          // Transient direct transport failure: bounded retry budget. The
          // staged ciphertext artifact is still preserved (KC-3) below.
          await persistTransientDownloadFailure(
            privateLockHeld: requiresDirectPrivateCommit,
          );
        }
        await reportPreservedDownloadArtifacts(
          reason: details['reason']?.toString() ?? event,
        );
        emitFlowEvent(layer: 'FL', event: event, details: details);
        emitDownloadTiming(
          outcome: 'failed',
          details: {'error': details['reason'] ?? details['error']},
        );
      }

      // Decrypts a staged direct (1:1) ciphertext artifact and promotes
      // the plaintext to the canonical path. Deliberately carries NONE
      // of the group mime/size policies or the missing-metadata
      // quarantine (112 plan, Alternatives rejected #2/#3); contentHash
      // is always the encrypted-blob hash (MIG-012 lesson).
      Future<_DirectStagedDecryptOutcome> decryptAndPromoteStagedDirectBlob({
        required File stagedFile,
        required String source,
        bool failOpenOnCryptoFailure = false,
      }) async {
        // Discriminator case 3: key material whose scheme is outside
        // the v1 whitelist must never be decrypted with v1 logic.
        if (!attachment.hasEncryptionMetadata) {
          await failClosedDirectEncryptedMedia(
            status: kMediaDownloadStatusIntegrityFailed,
            event: 'MEDIA_DOWNLOAD_REJECTED_UNKNOWN_ENCRYPTION_SCHEME',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'scheme': attachment.encryptionScheme,
              'source': source,
              'reason': 'unknown_encryption_scheme',
            },
          );
          return _DirectStagedDecryptOutcome.terminal;
        }

        if (attachment.contentHash != null) {
          final integrityValidation =
              await GroupMediaIntegrityPolicy.validateFileContentHash(
                path: stagedFile.path,
                expectedHash: attachment.contentHash,
              );
          if (!integrityValidation.isValid) {
            if (failOpenOnCryptoFailure) {
              emitFlowEvent(
                layer: 'FL',
                event: 'MEDIA_DOWNLOAD_DIRECT_STALE_STAGED_ARTIFACT',
                details: {
                  'blobId': idPrefix,
                  'source': source,
                  'reason': integrityValidation.reason,
                },
              );
              return _DirectStagedDecryptOutcome.softMiss;
            }
            await failClosedDirectEncryptedMedia(
              status: kMediaDownloadStatusIntegrityFailed,
              event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_DIRECT_INTEGRITY',
              details: {
                'blobId': idPrefix,
                'mime': attachment.mime,
                'source': source,
                'reason': integrityValidation.reason,
              },
            );
            return _DirectStagedDecryptOutcome.terminal;
          }
        }

        late final String decryptedPath;
        try {
          decryptedPath = await callBlobDecrypt(
            bridge,
            filePath: stagedFile.path,
            keyBase64: attachment.encryptionKeyBase64!,
            nonce: attachment.encryptionNonce!,
          );
        } on StateError catch (e) {
          // The bridge evaluated the ciphertext and rejected it
          // (auth-tag/key mismatch) — cryptographic, not transient.
          if (failOpenOnCryptoFailure) {
            emitFlowEvent(
              layer: 'FL',
              event: 'MEDIA_DOWNLOAD_DIRECT_STALE_STAGED_ARTIFACT',
              details: {
                'blobId': idPrefix,
                'source': source,
                'reason': 'decrypt_failed',
                'error': e.toString(),
              },
            );
            return _DirectStagedDecryptOutcome.softMiss;
          }
          await failClosedDirectEncryptedMedia(
            status: kMediaDownloadStatusIntegrityFailed,
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_DIRECT_ENCRYPTION',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'source': source,
              'reason': 'decrypt_failed',
              'error': e.toString(),
            },
          );
          return _DirectStagedDecryptOutcome.terminal;
        } catch (e) {
          // Transport-level failure — the ciphertext was never
          // evaluated. Retryable `failed`, never integrity_failed.
          await failClosedDirectEncryptedMedia(
            status: kMediaDownloadStatusFailed,
            event: 'MEDIA_DOWNLOAD_DIRECT_DECRYPT_DEFERRED',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'source': source,
              'reason': 'decrypt_transient_failure',
              'error': e.toString(),
            },
          );
          return _DirectStagedDecryptOutcome.terminal;
        }

        final decryptedFile = File(decryptedPath);
        if (!await decryptedFile.exists()) {
          await failClosedDirectEncryptedMedia(
            status: kMediaDownloadStatusIntegrityFailed,
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_DIRECT_ENCRYPTION',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'source': source,
              'reason': 'missing_decrypted_file',
            },
          );
          return _DirectStagedDecryptOutcome.terminal;
        }
        if (decryptedPath != absolutePath) {
          final finalFile = File(absolutePath);
          await finalFile.parent.create(recursive: true);
          await deleteIfExists(
            finalFile,
            caller: 'downloadMedia.decryptAndPromoteStagedDirectBlob',
            reason: 'replace_existing_plaintext_before_decrypt_rename',
            details: {'source': source},
          );
          await decryptedFile.rename(absolutePath);
        }

        final plaintextFile = File(absolutePath);
        final plaintextLength = await plaintextFile.exists()
            ? await plaintextFile.length()
            : 0;
        if (plaintextLength <= 0 || plaintextLength != attachment.size) {
          await deleteIfExists(
            plaintextFile,
            caller: 'downloadMedia.decryptAndPromoteStagedDirectBlob',
            reason: 'plaintext_size_mismatch',
            details: {'source': source},
          );
          await failClosedDirectEncryptedMedia(
            status: kMediaDownloadStatusIntegrityFailed,
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_DIRECT_MEDIA',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'source': source,
              'reason': 'plaintext_size_mismatch',
              'expectedBytes': attachment.size,
              'actualBytes': plaintextLength,
            },
          );
          return _DirectStagedDecryptOutcome.terminal;
        }

        // All validations passed — the canonical plaintext is the
        // artifact of record; drop the staged ciphertext.
        await deleteIfExists(
          stagedFile,
          caller: 'downloadMedia.decryptAndPromoteStagedDirectBlob',
          reason: 'direct_staged_ciphertext_cleanup_after_decrypt',
          details: {'source': source},
        );
        return _DirectStagedDecryptOutcome.promoted;
      }

      // Set when an adoption-seam decrypt fails CLOSED (terminal):
      // the overall download must return null instead of falling
      // through to a relay re-download.
      var terminalDirectMediaFailure = false;

      Future<MediaAttachment?> adoptCanonicalFileIfAvailable({
        required String source,
      }) async {
        if (owner != MediaOwnerLane.direct ||
            enforceGroupMediaPolicy ||
            requiresDirectPrivateCommit) {
          return null;
        }
        final canonicalFile = File(absolutePath);
        if (!await canonicalFile.exists()) {
          return null;
        }
        final bytes = await canonicalFile.length();
        if (bytes <= 0 || (attachment.size > 0 && bytes != attachment.size)) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_CANONICAL_ORPHAN_REJECTED',
            details: {
              'blobId': idPrefix,
              'attachmentId': attachment.id,
              'messageId': attachment.messageId,
              'mime': attachment.mime,
              'source': source,
              'fileBytes': bytes,
              'expectedBytes': attachment.size,
              'reason': bytes <= 0
                  ? 'empty_canonical_file'
                  : 'canonical_size_mismatch',
            },
          );
          return null;
        }

        await mediaAttachmentRepo.updateLocalPath(attachment.id, relativePath);
        final committed = await verifyCommittedLocalPath(
          absolutePath: absolutePath,
          relativePath: relativePath,
          source: source,
        );
        if (!committed) {
          return null;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_DOWNLOAD_CANONICAL_ORPHAN_ADOPTED',
          details: {
            'blobId': idPrefix,
            'attachmentId': attachment.id,
            'messageId': attachment.messageId,
            'mime': attachment.mime,
            'relativePath': relativePath,
            'fileBytes': bytes,
          },
        );
        ackRelayBlobDeletion(source: source);
        emitDownloadTiming(outcome: 'local_ready', details: {'source': source});
        return attachment.copyWith(
          localPath: absolutePath,
          downloadStatus: kMediaDownloadStatusDone,
        );
      }

      final adoptedCanonicalOrphan = await adoptCanonicalFileIfAvailable(
        source: 'direct_canonical_orphan',
      );
      if (adoptedCanonicalOrphan != null) {
        return adoptedCanonicalOrphan;
      }

      // A `.part` whose size matches the expected payload is a finished
      // transfer that never got promoted (e.g. the Dart watchdog fired
      // after the native write completed). Promote it instead of
      // re-downloading; the Go side never sees it, so genuine partials
      // keep their PL-013 removal semantics.
      Future<MediaAttachment?> adoptCompletePartFileIfAvailable({
        required String source,
      }) async {
        if (owner != MediaOwnerLane.direct ||
            enforceGroupMediaPolicy ||
            requiresDirectPrivateCommit) {
          return null;
        }
        final partFile = File(downloadPath);
        if (!await partFile.exists()) {
          return null;
        }
        final bytes = await partFile.length();
        // Encrypted staged artifacts are ciphertext: plaintext size +
        // 16-byte AES-GCM tag (the nonce travels in metadata, not in
        // the blob).
        final expectedStagedBytes = attachment.hasEncryptionKeyMaterial
            ? (attachment.size > 0 ? attachment.size + 16 : 0)
            : attachment.size;
        if (bytes <= 0 ||
            expectedStagedBytes <= 0 ||
            bytes != expectedStagedBytes) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_PART_ADOPTION_SKIPPED',
            details: {
              'blobId': idPrefix,
              'attachmentId': attachment.id,
              'messageId': attachment.messageId,
              'mime': attachment.mime,
              'source': source,
              'fileBytes': bytes,
              'expectedBytes': expectedStagedBytes,
              'reason': bytes <= 0
                  ? 'empty_part_file'
                  : expectedStagedBytes <= 0
                  ? 'unknown_expected_size'
                  : 'part_size_mismatch',
            },
          );
          return null;
        }

        if (attachment.hasEncryptionKeyMaterial) {
          final outcome = await decryptAndPromoteStagedDirectBlob(
            stagedFile: partFile,
            source: source,
            failOpenOnCryptoFailure: true,
          );
          if (outcome == _DirectStagedDecryptOutcome.terminal) {
            terminalDirectMediaFailure = true;
            return null;
          }
          if (outcome == _DirectStagedDecryptOutcome.softMiss) {
            return null;
          }
        } else {
          final canonicalFile = File(absolutePath);
          await canonicalFile.parent.create(recursive: true);
          if (await canonicalFile.exists()) {
            await deleteIfExists(
              canonicalFile,
              caller: 'downloadMedia.adoptCompletePartFile',
              reason: 'replace_canonical_with_complete_part',
              details: {'source': source},
            );
          }
          await partFile.rename(absolutePath);
        }
        await mediaAttachmentRepo.updateLocalPath(attachment.id, relativePath);
        final committed = await verifyCommittedLocalPath(
          absolutePath: absolutePath,
          relativePath: relativePath,
          source: source,
        );
        if (!committed) {
          return null;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_DOWNLOAD_COMPLETE_PART_ADOPTED',
          details: {
            'blobId': idPrefix,
            'attachmentId': attachment.id,
            'messageId': attachment.messageId,
            'mime': attachment.mime,
            'relativePath': relativePath,
            'fileBytes': bytes,
          },
        );
        ackRelayBlobDeletion(source: source);
        emitDownloadTiming(outcome: 'local_ready', details: {'source': source});
        return attachment.copyWith(
          localPath: absolutePath,
          downloadStatus: kMediaDownloadStatusDone,
        );
      }

      final adoptedCompletePart = await adoptCompletePartFileIfAvailable(
        source: 'complete_part_adoption',
      );
      if (adoptedCompletePart != null) {
        return adoptedCompletePart;
      }
      if (terminalDirectMediaFailure) {
        return null;
      }

      Future<MediaAttachment?> restoreEncryptedCompanionIfAvailable() async {
        if (!enforceGroupMediaPolicy || requiresDirectPrivateCommit) {
          return null;
        }
        final encryptedCompanion = File(downloadPath);
        if (!await encryptedCompanion.exists()) {
          return null;
        }

        // A companion smaller than the complete ciphertext (plaintext +
        // 16-byte GCM tag) is a stale partial from an interrupted
        // transfer — preserved by the INV-1 transient-failure rule, not
        // a tamper candidate. Drop it and fall through to a fresh relay
        // download instead of quarantining the row as integrity_failed.
        final companionBytes = await encryptedCompanion.length();
        if (attachment.size > 0 && companionBytes < attachment.size + 16) {
          await deleteIfExists(
            encryptedCompanion,
            caller: 'downloadMedia.restoreEncryptedCompanionIfAvailable',
            reason: 'stale_partial_encrypted_companion',
            details: {
              'fileBytes': companionBytes,
              'expectedBytes': attachment.size + 16,
            },
          );
          return null;
        }

        final integrityValidation =
            await GroupMediaIntegrityPolicy.validateFileContentHash(
              path: encryptedCompanion.path,
              expectedHash: attachment.contentHash,
            );
        if (!integrityValidation.isValid) {
          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_INTEGRITY',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': integrityValidation.reason,
              'source': 'local_encrypted_companion',
            },
            files: [encryptedCompanion],
          );
          return null;
        }

        // Ordinary-group companion adoption is a real recovery attempt, not a
        // local-path repair shortcut. Acquire the exact
        // attachment + live incoming parent + active group + local-visibility
        // + deletion-journal authority before the first decrypt side effect.
        // Automatic and explicit-user retries use distinct admission status
        // sets, but both production repositories evaluate the whole authority
        // tuple in one CAS.
        if (!await claimOrdinaryGroupDownloadIfNeeded(companion: true)) {
          ordinaryGroupCompanionRecoveryTerminated = true;
          return null;
        }

        late final String decryptedPath;
        try {
          decryptedPath = await callBlobDecrypt(
            bridge,
            filePath: encryptedCompanion.path,
            keyBase64: attachment.encryptionKeyBase64!,
            nonce: attachment.encryptionNonce!,
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_LOCAL_ENCRYPTED_COMPANION_DECRYPT_FAILED',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'error': e.toString(),
            },
          );
          return null;
        }

        final decryptedFile = File(decryptedPath);
        if (!await decryptedFile.exists()) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_LOCAL_ENCRYPTED_COMPANION_DECRYPT_FAILED',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': 'missing_decrypted_file',
            },
          );
          return null;
        }
        if (decryptedPath != absolutePath) {
          final finalFile = File(absolutePath);
          await finalFile.parent.create(recursive: true);
          await deleteIfExists(
            finalFile,
            caller: 'downloadMedia.restoreEncryptedCompanionIfAvailable',
            reason: 'replace_existing_plaintext_before_decrypt_rename',
            details: {'source': 'local_encrypted_companion'},
          );
          await decryptedFile.rename(absolutePath);
        }

        final plaintextFile = File(absolutePath);
        final plaintextExists = await plaintextFile.exists();
        final plaintextLength = plaintextExists
            ? await plaintextFile.length()
            : 0;
        final plaintextSizeValidation = GroupMediaSizePolicy.validateSize(
          sizeBytes: plaintextLength,
          mime: attachment.mime,
          // Receive side: cross-type backstop, not per-type SEND caps.
          perMediaLimitBytes: kGroupMediaPerAttachmentLimitBytes,
        );
        final hasPlaintextSizeMismatch = plaintextLength != attachment.size;
        if (!plaintextExists ||
            plaintextLength <= 0 ||
            hasPlaintextSizeMismatch ||
            !plaintextSizeValidation.isValid) {
          final reason = hasPlaintextSizeMismatch
              ? 'plaintext_size_mismatch'
              : plaintextSizeValidation.reason ?? 'invalid_plaintext_file';
          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_MEDIA',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': reason,
              'source': 'local_encrypted_companion',
            },
            files: [plaintextFile],
          );
          if (ordinaryGroupDownloadAuthorityKind != null) {
            ordinaryGroupCompanionRecoveryTerminated = true;
          }
          return null;
        }

        final validation = await GroupMediaMimePolicy.validateFile(
          path: absolutePath,
          mime: attachment.mime,
          mediaType: attachment.mediaType,
        );

        if (!validation.isValid) {
          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_MEDIA',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': validation.reason,
              'source': 'local_encrypted_companion',
            },
            files: [plaintextFile],
          );
          if (ordinaryGroupDownloadAuthorityKind != null) {
            ordinaryGroupCompanionRecoveryTerminated = true;
          }
          return null;
        }

        final groupAuthorityKind = ordinaryGroupDownloadAuthorityKind;
        if (groupAuthorityKind != null) {
          final committed = await commitOrdinaryGroupDownloadLocalPath(
            relativePath,
          );
          if (!committed) {
            emitFlowEvent(
              layer: 'FL',
              event: 'MEDIA_DOWNLOAD_CLAIM_LOST',
              details: {
                'blobId': idPrefix,
                'phase': 'group_${groupAuthorityKind}_companion_commit',
              },
            );
            // The encrypted companion is pre-existing recovery input and may
            // also be journal-owned now. Discard only the plaintext output
            // promoted by this losing attempt; never delete the companion or
            // publish a completed attachment.
            await deleteIfExists(
              plaintextFile,
              caller: 'downloadMedia.groupCompanionLateCommitClaimLost',
              reason: 'discard_companion_plaintext_after_lost_group_authority',
              details: {'source': 'local_encrypted_companion'},
            );
            ordinaryGroupCompanionRecoveryTerminated = true;
            emitDownloadTiming(
              outcome: 'failed',
              details: {
                'error': 'group_${groupAuthorityKind}_companion_commit_lost',
              },
            );
            return null;
          }
          ordinaryGroupExpectedLocalPath = relativePath;
          ordinaryGroupDownloadClaimed = false;
        } else {
          // Compatibility path for direct-owner callers that opt into the
          // group integrity policy but do not participate in ordinary-group
          // recovery authority. Generic ID-only mutation is direct-only.
          if (owner != MediaOwnerLane.direct) {
            ordinaryGroupCompanionRecoveryTerminated = true;
            await deleteIfExists(
              plaintextFile,
              caller: 'downloadMedia.groupCompanionMissingExactAuthority',
              reason: 'discard_companion_plaintext_without_group_authority',
              details: {'source': 'local_encrypted_companion'},
            );
            return null;
          }
          await mediaAttachmentRepo.updateLocalPath(
            attachment.id,
            relativePath,
          );
        }
        final committed = await verifyCommittedLocalPath(
          absolutePath: absolutePath,
          relativePath: relativePath,
          source: 'local_encrypted_companion',
        );
        if (!committed) {
          return null;
        }
        await deleteIfExists(
          encryptedCompanion,
          caller: 'downloadMedia.restoreEncryptedCompanionIfAvailable',
          reason: 'local_encrypted_companion_cleanup_after_restore',
          details: {'source': 'local_encrypted_companion'},
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_DOWNLOAD_REPAIRED_FROM_LOCAL_ENCRYPTED_COMPANION',
          details: {'blobId': idPrefix, 'mime': attachment.mime},
        );
        emitDownloadTiming(
          outcome: 'local_ready',
          details: {'source': 'local_encrypted_companion'},
        );
        return attachment.copyWith(
          localPath: absolutePath,
          downloadStatus: kMediaDownloadStatusDone,
        );
      }

      final restoredEncryptedCompanion =
          await restoreEncryptedCompanionIfAvailable();
      if (restoredEncryptedCompanion != null) {
        return restoredEncryptedCompanion;
      }
      if (ordinaryGroupCompanionRecoveryTerminated) {
        return null;
      }
      final encryptedCompanionFoundAfterRestore = enforceGroupMediaPolicy
          ? await File(downloadPath).exists()
          : false;

      final localDiagnostics = await _collectLocalMediaCandidateDiagnostics(
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        attachment: attachment,
        allowStatusRepair:
            !enforceGroupMediaPolicy && !requiresDirectPrivateCommit,
        owner: owner,
        includeInputCandidate: !requiresDirectPrivateCommit,
      );
      final localMissReason = _mediaDownloadLocalMissReason(
        localDiagnostics,
        encryptedCompanionFoundBeforeRestore:
            encryptedCompanionFoundBeforeRestore,
      );
      final localMissHadLocalPath = localDiagnostics.any(
        (diagnostic) => diagnostic['hasLocalPath'] == true,
      );
      final localMissHadDoneCandidate = localDiagnostics.any(
        (diagnostic) =>
            diagnostic['downloadStatus'] == kMediaDownloadStatusDone,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DOWNLOAD_LOCAL_MISS',
        details: {
          'blobId': idPrefix,
          'attachmentId': attachment.id,
          'messageId': attachment.messageId,
          'contactPeerId': contactPeerId,
          'contactPeerShort': _mediaDownloadShortPeerId(contactPeerId),
          'mime': attachment.mime,
          'mediaType': attachment.mediaType,
          'sizeBytes': attachment.size,
          'downloadStatus': attachment.downloadStatus,
          'enforceGroupMediaPolicy': enforceGroupMediaPolicy,
          'hasLocalPath':
              attachment.localPath != null && attachment.localPath!.isNotEmpty,
          'localPathKind': _mediaDownloadPathKind(attachment.localPath),
          'hasEncryptionMetadata': attachment.hasEncryptionMetadata,
          'contentHashPresent': attachment.contentHash?.isNotEmpty == true,
          'plannedDownloadPath': downloadPath,
          'plannedDownloadPathKind': _mediaDownloadPathKind(downloadPath),
          'encryptedCompanionExpected': enforceGroupMediaPolicy,
          'encryptedCompanionFoundBeforeRestore':
              encryptedCompanionFoundBeforeRestore,
          'encryptedCompanionFoundAfterRestore':
              encryptedCompanionFoundAfterRestore,
          'reason': localMissReason,
          'candidateCount': localDiagnostics.length,
          'candidateDiagnostics': localDiagnostics.take(4).toList(),
        },
      );
      if (localMissReason == 'local_file_missing' &&
          localMissHadDoneCandidate) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_DOWNLOAD_STALE_DONE_LOCAL_PATH_CLEARED',
          details: {
            'blobId': idPrefix,
            'attachmentId': attachment.id,
            'messageId': attachment.messageId,
            'mime': attachment.mime,
            'mediaType': attachment.mediaType,
            'reason': localMissReason,
            'candidateDiagnostics': localDiagnostics.take(4).toList(),
          },
        );
        final missingDonePath = localDiagnostics
            .where(
              (diagnostic) =>
                  diagnostic['downloadStatus'] == kMediaDownloadStatusDone &&
                  diagnostic['reason'] == 'local_file_missing',
            )
            .map((diagnostic) => diagnostic['localPath'])
            .whereType<String>()
            .firstOrNull;
        if (requiresDirectPrivateCommit) {
          if (missingDonePath != null) {
            await directPrivateDownloadRepo!
                .recordDirectPrivateMediaDownloadFailure(
                  attachment.id,
                  messageId: attachment.messageId,
                  nowMs: currentNowMs(),
                  incrementRetryCount: false,
                  failureStatus: kMediaDownloadStatusFailed,
                  expectedDownloadStatus: kMediaDownloadStatusDone,
                  expectedLocalPath: missingDonePath,
                  clearLocalPath: true,
                );
          }
        } else if (ordinaryGroupDownloadFailureRepo != null) {
          if (missingDonePath != null) {
            final cleared = await recordOrdinaryGroupDownloadFailure(
              incrementRetryCount: false,
              failureStatus: kMediaDownloadStatusFailed,
              expectedDownloadStatus: kMediaDownloadStatusDone,
              expectedLocalPath: missingDonePath,
              clearLocalPath: true,
            );
            if (cleared) {
              ordinaryGroupExpectedDownloadStatus = kMediaDownloadStatusFailed;
            }
          }
        } else {
          try {
            await mediaAttachmentRepo.saveAttachment(
              attachment.copyWith(
                clearLocalPath: true,
                downloadStatus: kMediaDownloadStatusFailed,
              ),
              owner: owner,
            );
          } catch (_) {}
        }
      }

      // 2. Mark as downloading. 229: a CAS-capable repository claims the
      // row conditionally (exact owner + a claimable source state) so a
      // concurrent eviction/commit can never be silently overwritten; a
      // lost claim aborts BEFORE any transfer with zero state change.
      if (requiresDirectPrivateCommit) {
        final claimed = await directPrivateRuntime!
            .directPrivateMediaLifecycleLock
            .synchronized(attachment.id, () async {
              final token = directPrivateMediaTransferRegistry.tryBegin(
                attachment.id,
              );
              if (token == null) return false;
              final began = await directPrivateDownloadRepo!
                  .beginDirectPrivateMediaDownloadWithinLock(
                    attachment.id,
                    messageId: attachment.messageId,
                    nowMs: currentNowMs(),
                  );
              if (!began) {
                directPrivateMediaTransferRegistry.end(attachment.id, token);
                return false;
              }
              privateTransferToken = token;
              return true;
            });
        if (!claimed) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_CLAIM_LOST',
            details: {'blobId': idPrefix, 'phase': 'private_begin'},
          );
          emitDownloadTiming(
            outcome: 'failed',
            details: {'error': 'private_download_claim_lost'},
          );
          return null;
        }
      } else if (ordinaryGroupDownloadAuthorityKind != null) {
        if (!await claimOrdinaryGroupDownloadIfNeeded(companion: false)) {
          return null;
        }
      } else if (mediaAttachmentRepo is MediaDownloadStateRepository) {
        final claimed =
            await (mediaAttachmentRepo as MediaDownloadStateRepository)
                .beginMediaDownload(attachment.id, owner: owner);
        if (!claimed) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_CLAIM_LOST',
            details: {'blobId': idPrefix, 'phase': 'begin'},
          );
          emitDownloadTiming(
            outcome: 'failed',
            details: {'error': 'download_claim_lost'},
          );
          return null;
        }
      } else {
        await mediaAttachmentRepo.updateDownloadStatus(
          attachment.id,
          kMediaDownloadStatusDownloading,
        );
      }
      if (ordinaryGroupDownloadFailureRepo != null) {
        ordinaryGroupDownloadClaimed = true;
      }

      // 3. Download from relay
      final result = await callP2PMediaDownload(
        bridge,
        id: attachment.id,
        outputPath: downloadPath,
        payloadSizeBytes: attachment.size,
        stallTimeout: transferStallTimeout,
        maxTimeout: transferMaxTimeout,
      );
      final routedViaRelayStore = result['routedViaRelayStore'] == true;
      final servedByPhone = result['servedByPhone'] == true;
      final transportAuditDetails = <String, dynamic>{
        'blobId': idPrefix,
        'attachmentId': attachment.id,
        'messageId': attachment.messageId,
        'mime': attachment.mime,
        'mediaType': attachment.mediaType,
        'ok': result['ok'],
        'localMissReason': localMissReason,
        'localMissHadLocalPath': localMissHadLocalPath,
        'localMissHadDoneCandidate': localMissHadDoneCandidate,
        'servedByPhone': servedByPhone,
        'routedViaRelayStore': routedViaRelayStore,
      };
      for (final key in const [
        'sourceRole',
        'sourcePeerId',
        'sourcePeerShort',
        'streamTransport',
      ]) {
        if (result.containsKey(key)) {
          transportAuditDetails[key] = result[key];
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DOWNLOAD_TRANSPORT_AUDIT',
        details: transportAuditDetails,
      );
      if (routedViaRelayStore &&
          (localMissHadLocalPath || localMissHadDoneCandidate)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_DOWNLOAD_RELAY_DEPENDENCY_RISK',
          details: {...transportAuditDetails, 'reason': localMissReason},
        );
      }

      if (result['ok'] != true) {
        final localAttachment = await useCompletedLocalAttachmentIfAvailable(
          event: 'MEDIA_DOWNLOAD_FAILURE_SUPERSEDED_BY_LOCAL',
          allowStatusRepair: !enforceGroupMediaPolicy,
          details: {'error': result['errorMessage']},
        );
        if (localAttachment != null) {
          return localAttachment;
        }

        await reportPreservedDownloadArtifacts(reason: 'download_failed');

        // INV-DL-4: a relay "not found"/"not authorized" is an honest
        // terminal "expired on server" state — flip straight to
        // download_failed without burning the retry budget. Any other relay
        // error is a bounded transient failure.
        if (isRelayUnavailableError(result['errorMessage'])) {
          await markRelayUnavailableDownloadFailed();
        } else {
          await persistTransientDownloadFailure();
        }

        final repairedLocalAttachment =
            await useCompletedLocalAttachmentIfAvailable(
              event: 'MEDIA_DOWNLOAD_FAILURE_REPAIRED_BY_LOCAL',
              allowStatusRepair: !enforceGroupMediaPolicy,
              details: {'error': result['errorMessage']},
            );
        if (repairedLocalAttachment != null) {
          return repairedLocalAttachment;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_DOWNLOAD_FAILED',
          details: {'blobId': idPrefix, 'error': result['errorMessage']},
        );
        emitDownloadTiming(
          outcome: 'failed',
          details: {'error': result['errorMessage']},
        );
        return null;
      }

      if (ordinaryGroupAutomaticDownloadStateRepo != null &&
          groupMediaPostClaimPreCommit != null) {
        await groupMediaPostClaimPreCommit(attachment);
      }

      final downloadedFile = File(downloadPath);
      final fileExists = await downloadedFile.exists();
      final fileLength = fileExists ? await downloadedFile.length() : 0;
      final expectedSize = switch (result['size']) {
        final int size => size,
        final num size => size.toInt(),
        _ => null,
      };
      final hasInvalidDownloadedFile =
          !fileExists ||
          fileLength <= 0 ||
          (expectedSize != null &&
              expectedSize > 0 &&
              fileLength != expectedSize);
      if (hasInvalidDownloadedFile) {
        if (enforceGroupMediaPolicy) {
          final localAttachment =
              await useCompletedGroupLocalAttachmentIfAvailable(
                event: 'MEDIA_DOWNLOAD_INVALID_GROUP_FILE_SUPERSEDED_BY_LOCAL',
                details: {
                  'expectedSize': expectedSize,
                  'actualSize': fileLength,
                  'fileExists': fileExists,
                  'reason': 'invalid_downloaded_file',
                },
              );
          if (localAttachment != null) {
            if (fileExists) {
              await deleteIfExists(
                downloadedFile,
                caller: 'downloadMedia.invalidGroupFileSupersededByLocal',
                reason: 'invalid_group_file_superseded_cleanup',
                details: {
                  'expectedSize': expectedSize,
                  'actualSize': fileLength,
                },
              );
            }
            return localAttachment;
          }

          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_INVALID_FILE',
            details: {
              'blobId': idPrefix,
              'expectedSize': expectedSize,
              'actualSize': fileLength,
              'reason': 'invalid_downloaded_file',
            },
            files: fileExists ? [downloadedFile] : const [],
          );
          return null;
        }

        final localAttachment = await useCompletedLocalAttachmentIfAvailable(
          event: 'MEDIA_DOWNLOAD_INVALID_FILE_SUPERSEDED_BY_LOCAL',
          allowStatusRepair: true,
          details: {'expectedSize': expectedSize, 'actualSize': fileLength},
        );
        if (localAttachment != null) {
          return localAttachment;
        }

        await persistTransientDownloadFailure();
        if (fileExists) {
          await deleteIfExists(
            downloadedFile,
            caller: 'downloadMedia.invalidDownloadedFile',
            reason: 'invalid_downloaded_file_cleanup',
            details: {'expectedSize': expectedSize, 'actualSize': fileLength},
          );
        }

        final repairedLocalAttachment =
            await useCompletedLocalAttachmentIfAvailable(
              event: 'MEDIA_DOWNLOAD_INVALID_FILE_REPAIRED_BY_LOCAL',
              allowStatusRepair: true,
              details: {'expectedSize': expectedSize, 'actualSize': fileLength},
            );
        if (repairedLocalAttachment != null) {
          return repairedLocalAttachment;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_DOWNLOAD_INVALID_FILE',
          details: {
            'blobId': idPrefix,
            'expectedSize': expectedSize,
            'actualSize': fileLength,
          },
        );
        emitDownloadTiming(
          outcome: 'failed',
          details: {
            'error': 'invalid_downloaded_file',
            'expectedSize': expectedSize,
            'actualSize': fileLength,
          },
        );
        return null;
      }

      if (enforceGroupMediaPolicy) {
        final relayMime = result['mime'] as String?;
        final expectedMime = GroupMediaMimePolicy.normalizeMime(
          attachment.mime,
        );
        final returnedMime = GroupMediaMimePolicy.normalizeMime(relayMime);
        if (returnedMime != null && returnedMime != expectedMime) {
          final localAttachment =
              await useCompletedGroupLocalAttachmentIfAvailable(
                event:
                    'MEDIA_DOWNLOAD_GROUP_MIME_REJECTION_SUPERSEDED_BY_LOCAL',
                details: {
                  'relayMime': relayMime,
                  'expectedMime': expectedMime,
                  'reason': 'relay_mime_mismatch',
                },
              );
          if (localAttachment != null) {
            await deleteIfExists(
              downloadedFile,
              caller: 'downloadMedia.groupMimeRejectionSupersededByLocal',
              reason: 'group_mime_rejection_superseded_cleanup',
              details: {'relayMime': relayMime, 'expectedMime': expectedMime},
            );
            return localAttachment;
          }

          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_MEDIA',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'relayMime': relayMime,
              'reason': 'relay_mime_mismatch',
            },
            files: [downloadedFile],
          );
          return null;
        }

        final integrityValidation =
            await GroupMediaIntegrityPolicy.validateFileContentHash(
              path: downloadPath,
              expectedHash: attachment.contentHash,
            );
        if (!integrityValidation.isValid) {
          final localAttachment =
              await useCompletedGroupLocalAttachmentIfAvailable(
                event:
                    'MEDIA_DOWNLOAD_GROUP_INTEGRITY_REJECTION_SUPERSEDED_BY_LOCAL',
                details: {'reason': integrityValidation.reason},
              );
          if (localAttachment != null) {
            await deleteIfExists(
              downloadedFile,
              caller: 'downloadMedia.groupIntegrityRejectionSupersededByLocal',
              reason: 'group_integrity_rejection_superseded_cleanup',
              details: {'integrityReason': integrityValidation.reason},
            );
            return localAttachment;
          }

          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_INTEGRITY',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': integrityValidation.reason,
            },
            files: [downloadedFile],
          );
          return null;
        }

        late final String decryptedPath;
        try {
          decryptedPath = await callBlobDecrypt(
            bridge,
            filePath: downloadPath,
            keyBase64: attachment.encryptionKeyBase64!,
            nonce: attachment.encryptionNonce!,
          );
        } catch (e) {
          final localAttachment =
              await useCompletedGroupLocalAttachmentIfAvailable(
                event:
                    'MEDIA_DOWNLOAD_GROUP_DECRYPT_REJECTION_SUPERSEDED_BY_LOCAL',
                details: {'reason': 'decrypt_failed', 'error': e.toString()},
              );
          if (localAttachment != null) {
            await deleteIfExists(
              downloadedFile,
              caller: 'downloadMedia.groupDecryptSupersededByLocal',
              reason: 'group_decrypt_rejection_superseded_cleanup',
              details: {'decryptError': e.toString()},
            );
            return localAttachment;
          }

          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_ENCRYPTION',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': 'decrypt_failed',
              'error': e.toString(),
            },
            files: [downloadedFile],
          );
          return null;
        }
        final decryptedFile = File(decryptedPath);
        if (!await decryptedFile.exists()) {
          final localAttachment =
              await useCompletedGroupLocalAttachmentIfAvailable(
                event:
                    'MEDIA_DOWNLOAD_GROUP_DECRYPT_OUTPUT_SUPERSEDED_BY_LOCAL',
                details: {'reason': 'missing_decrypted_file'},
              );
          if (localAttachment != null) {
            await deleteIfExists(
              downloadedFile,
              caller: 'downloadMedia.groupDecryptOutputSupersededByLocal',
              reason: 'group_missing_decrypt_output_superseded_cleanup',
            );
            return localAttachment;
          }

          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_INVALID_FILE',
            details: {'blobId': idPrefix, 'reason': 'missing_decrypted_file'},
            files: [downloadedFile],
          );
          return null;
        }
        if (requiresDirectPrivateCommit) {
          final expectedDecryptedPath = '$downloadPath.dec';
          final authorityRoot = p.dirname(p.dirname(absolutePath));
          if (p.normalize(decryptedPath) !=
                  p.normalize(expectedDecryptedPath) ||
              !await DirectPrivateMediaPathGuard.authorizeTarget(
                targetPath: expectedDecryptedPath,
                authorityRoot: authorityRoot,
                requireExistingFile: true,
              )) {
            await quarantineUnsafeGroupMedia(
              event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_ENCRYPTION',
              details: {
                'blobId': idPrefix,
                'mime': attachment.mime,
                'reason': 'unsafe_private_decrypt_output',
              },
            );
            return null;
          }
          groupPrivateDecryptedPath = expectedDecryptedPath;
        } else if (decryptedPath != absolutePath) {
          final finalFile = File(absolutePath);
          await finalFile.parent.create(recursive: true);
          await deleteIfExists(
            finalFile,
            caller: 'downloadMedia.groupDownloadDecrypt',
            reason: 'replace_existing_plaintext_before_decrypt_rename',
            details: {'source': 'group_media_download'},
          );
          await decryptedFile.rename(absolutePath);
        }
        if (!requiresDirectPrivateCommit) {
          await deleteIfExists(
            downloadedFile,
            caller: 'downloadMedia.groupDownloadDecrypt',
            reason: 'group_download_encrypted_companion_cleanup_after_decrypt',
            details: {'source': 'group_media_download'},
          );
        }

        final plaintextFile = requiresDirectPrivateCommit
            ? decryptedFile
            : File(absolutePath);
        final plaintextExists = await plaintextFile.exists();
        final plaintextLength = plaintextExists
            ? await plaintextFile.length()
            : 0;
        final plaintextSizeValidation = GroupMediaSizePolicy.validateSize(
          sizeBytes: plaintextLength,
          mime: attachment.mime,
          // Receive side: cross-type backstop, not per-type SEND caps.
          perMediaLimitBytes: kGroupMediaPerAttachmentLimitBytes,
        );
        final hasPlaintextSizeMismatch = plaintextLength != attachment.size;
        if (!plaintextExists ||
            plaintextLength <= 0 ||
            hasPlaintextSizeMismatch ||
            !plaintextSizeValidation.isValid) {
          final reason = hasPlaintextSizeMismatch
              ? 'plaintext_size_mismatch'
              : plaintextSizeValidation.reason ?? 'invalid_plaintext_file';
          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_MEDIA',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': reason,
            },
            files: [plaintextFile],
          );
          return null;
        }

        final validation = await GroupMediaMimePolicy.validateFile(
          path: plaintextFile.path,
          mime: attachment.mime,
          mediaType: attachment.mediaType,
        );

        if (!validation.isValid) {
          await quarantineUnsafeGroupMedia(
            event: 'MEDIA_DOWNLOAD_REJECTED_INVALID_GROUP_MEDIA',
            details: {
              'blobId': idPrefix,
              'mime': attachment.mime,
              'reason': validation.reason,
            },
            files: [plaintextFile],
          );
          return null;
        }
      }

      Future<bool> promoteStagedDirectFile() async {
        final stagedFile = File(downloadPath);
        if (attachment.hasEncryptionKeyMaterial) {
          final outcome = await decryptAndPromoteStagedDirectBlob(
            stagedFile: stagedFile,
            source: 'direct_media_download',
          );
          return outcome == _DirectStagedDecryptOutcome.promoted;
        }
        final canonicalFile = File(absolutePath);
        await canonicalFile.parent.create(recursive: true);
        if (await canonicalFile.exists()) {
          await deleteIfExists(
            canonicalFile,
            caller: 'downloadMedia.promoteValidatedDirectDownload',
            reason: 'replace_canonical_after_staged_validation',
            details: {'source': 'direct_media_download'},
          );
        }
        await stagedFile.rename(absolutePath);
        return true;
      }

      Future<bool> promoteValidatedGroupPrivateFile() async {
        final decryptedPath = groupPrivateDecryptedPath;
        if (decryptedPath == null) return false;
        final decryptedFile = File(decryptedPath);
        if (!await decryptedFile.exists()) return false;
        final canonicalFile = File(absolutePath);
        await canonicalFile.parent.create(recursive: true);
        if (await canonicalFile.exists()) {
          await deleteIfExists(
            canonicalFile,
            caller: 'downloadMedia.promoteValidatedGroupPrivateFile',
            reason: 'replace_group_private_canonical_after_requalification',
            details: {'source': 'group_private_media_download'},
          );
        }
        await decryptedFile.rename(absolutePath);
        groupPrivateDecryptedPath = null;
        await deleteIfExists(
          File(downloadPath),
          caller: 'downloadMedia.promoteValidatedGroupPrivateFile',
          reason: 'group_private_ciphertext_cleanup_after_commit_promotion',
          details: {'source': 'group_private_media_download'},
        );
        return true;
      }

      if (requiresDirectPrivateCommit) {
        final token = privateTransferToken;
        if (token == null) return null;
        final finalized = await directPrivateRuntime!
            .directPrivateMediaLifecycleLock
            .synchronized(attachment.id, () async {
              if (!directPrivateMediaTransferRegistry.owns(
                attachment.id,
                token,
              )) {
                await purgeExactPrivateTransferArtifacts(
                  reason: 'private_transfer_token_lost_before_promote',
                );
                return false;
              }
              final qualified = await directPrivateDownloadRepo!
                  .qualifyDirectPrivateMediaDownloadClaimWithinLock(
                    attachment.id,
                    messageId: attachment.messageId,
                    nowMs: currentNowMs(),
                  );
              if (!qualified) {
                await purgeExactPrivateTransferArtifacts(
                  reason: 'private_transfer_authority_lost_before_promote',
                );
                return false;
              }
              final promoted = enforceGroupMediaPolicy
                  ? await promoteValidatedGroupPrivateFile()
                  : await promoteStagedDirectFile();
              if (!promoted) {
                await purgeExactPrivateTransferArtifacts(
                  reason: 'private_transfer_promotion_rejected',
                );
                return false;
              }
              final committed = await directPrivateDownloadRepo
                  .commitDirectPrivateMediaDownloadLocalPathWithinLock(
                    attachment.id,
                    messageId: attachment.messageId,
                    localPath: relativePath,
                    nowMs: currentNowMs(),
                  );
              if (!committed) {
                await purgeExactPrivateTransferArtifacts(
                  reason: 'private_transfer_commit_lost',
                );
              }
              return committed;
            });
        if (!finalized) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_CLAIM_LOST',
            details: {'blobId': idPrefix, 'phase': 'private_finalize'},
          );
          emitDownloadTiming(
            outcome: 'failed',
            details: {'error': 'private_download_finalize_lost'},
          );
          return null;
        }
      } else if (!enforceGroupMediaPolicy && !await promoteStagedDirectFile()) {
        return null;
      }

      // 4. Store relative path in DB (survives iOS container UUID
      // changes). 229: a CAS-capable repository commits done/path ONLY
      // from this download's own `downloading` claim — a late completion
      // whose claim was lost (e.g. the row was evicted meanwhile) writes
      // nothing and removes only the exact canonical artifact it just
      // promoted.
      if (requiresDirectPrivateCommit) {
        // Direct-private promotion + commit already completed atomically
        // with respect to lifecycle cleanup in the finalization lock.
      } else if (ordinaryGroupDownloadAuthorityKind != null) {
        final committedRow = await commitOrdinaryGroupDownloadLocalPath(
          relativePath,
        );
        if (!committedRow) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_CLAIM_LOST',
            details: {
              'blobId': idPrefix,
              'phase': 'group_${ordinaryGroupDownloadAuthorityKind}_commit',
            },
          );
          await deleteIfExists(
            File(absolutePath),
            caller: 'downloadMedia.groupLateCommitClaimLost',
            reason: 'discard_promoted_artifact_after_lost_group_authority',
            details: {'blobId': idPrefix},
          );
          emitDownloadTiming(
            outcome: 'failed',
            details: {
              'error':
                  'group_${ordinaryGroupDownloadAuthorityKind}_download_commit_lost',
            },
          );
          return null;
        }
      } else if (mediaAttachmentRepo is MediaDownloadStateRepository) {
        final committedRow =
            await (mediaAttachmentRepo as MediaDownloadStateRepository)
                .commitMediaDownloadLocalPath(
                  attachment.id,
                  owner: owner,
                  localPath: relativePath,
                );
        if (!committedRow) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_CLAIM_LOST',
            details: {'blobId': idPrefix, 'phase': 'commit'},
          );
          await deleteIfExists(
            File(absolutePath),
            caller: 'downloadMedia.lateCommitClaimLost',
            reason: 'discard_promoted_artifact_after_lost_claim',
            details: {'blobId': idPrefix},
          );
          emitDownloadTiming(
            outcome: 'failed',
            details: {'error': 'download_commit_claim_lost'},
          );
          return null;
        }
      } else if (owner == MediaOwnerLane.direct) {
        await mediaAttachmentRepo.updateLocalPath(attachment.id, relativePath);
      } else {
        await deleteIfExists(
          File(absolutePath),
          caller: 'downloadMedia.groupCommitMissingExactAuthority',
          reason: 'discard_promoted_artifact_without_group_authority',
          details: {'blobId': idPrefix},
        );
        return null;
      }
      if (ordinaryGroupDownloadFailureRepo != null) {
        ordinaryGroupExpectedLocalPath = relativePath;
        ordinaryGroupDownloadClaimed = false;
      }
      final committed = await verifyCommittedLocalPath(
        absolutePath: absolutePath,
        relativePath: relativePath,
        source: enforceGroupMediaPolicy
            ? 'group_media_download'
            : 'direct_media_download',
      );
      if (!committed) {
        emitDownloadTiming(
          outcome: 'failed',
          details: {'error': 'durable_local_path_missing_after_commit'},
        );
        return null;
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DOWNLOAD_SUCCESS',
        details: {'blobId': idPrefix},
      );
      ackRelayBlobDeletion(source: 'post_commit');
      emitDownloadTiming(outcome: 'success');

      // Return absolute path for immediate UI display
      return attachment.copyWith(
        localPath: absolutePath,
        downloadStatus: kMediaDownloadStatusDone,
      );
    } catch (e) {
      if (requiresDirectPrivateCommit && privateTransferToken != null) {
        scheduleLatePrivateTransferScrub();
      }
      // Keep the staged artifact — the watchdog may have fired while the
      // native transfer was still completing (INV-1).
      try {
        await reportPreservedDownloadArtifacts(reason: 'exception');
      } catch (_) {}

      try {
        await persistTransientDownloadFailure();
      } catch (_) {}

      final localAttachment = await useCompletedLocalAttachmentIfAvailable(
        event: 'MEDIA_DOWNLOAD_ERROR_REPAIRED_BY_LOCAL',
        allowStatusRepair: !enforceGroupMediaPolicy,
        details: {'error': e.toString()},
      );
      if (localAttachment != null) {
        return localAttachment;
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DOWNLOAD_ERROR',
        details: {'blobId': idPrefix, 'error': e.toString()},
      );
      emitDownloadTiming(outcome: 'error');
      return null;
    } finally {
      final token = privateTransferToken;
      if (token != null && !retainPrivateTransferForLateScrub) {
        directPrivateMediaTransferRegistry.end(attachment.id, token);
      }
    }
  }

  final execution = runDownload();
  downloadFuture = execution.whenComplete(() {
    if (identical(_inFlightMediaDownloads[inFlightKey], downloadFuture)) {
      _inFlightMediaDownloads.remove(inFlightKey);
    }
  });

  _inFlightMediaDownloads[inFlightKey] = downloadFuture;
  return downloadFuture;
}
