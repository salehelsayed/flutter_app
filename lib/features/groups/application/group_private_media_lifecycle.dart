import 'dart:async';

import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:path/path.dart' as p;

/// Process-local wake-up signal for a newly anchored disappearing group row.
/// The durable DB clock remains the authority; this stream only asks the shared
/// foreground scheduler to recompute its next deadline.
final StreamController<void> _groupPrivateMediaExpirySignals =
    StreamController<void>.broadcast(sync: true);

Stream<void> get groupPrivateMediaExpirySignals =>
    _groupPrivateMediaExpirySignals.stream;

void signalGroupPrivateMediaExpiryChanged() {
  if (!_groupPrivateMediaExpirySignals.isClosed) {
    _groupPrivateMediaExpirySignals.add(null);
  }
}

class GroupPrivateMediaOpenGrantData {
  GroupPrivateMediaOpenGrantData({
    required this.groupId,
    required this.messageId,
    required this.attachmentId,
    required this.policy,
    required this.kind,
    required this.localPath,
    required this.expiresAtMs,
  });

  final String groupId;
  final String messageId;
  final String attachmentId;
  final GroupPrivateMediaPolicy policy;
  final MediaViewerKind kind;
  final String localPath;
  final int? expiresAtMs;
  bool consumedAtFirstFrame = false;

  @override
  String toString() => 'GroupPrivateMediaOpenGrantData(redacted)';
}

class GroupPrivateMediaReconcileResult {
  int terminalClaims = 0;
  int cleanupCompleted = 0;
  int retainedAfterError = 0;
}

/// Device-local group private-media lifecycle authority.
///
/// Policy and timestamps live on the exact group parent. File/key/attachment
/// cleanup is ordered by the process-wide attachment lock and is authorized a
/// second time by SQL immediately before key/row deletion.
class GroupPrivateMediaLifecycleEngine {
  GroupPrivateMediaLifecycleEngine({
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.cleanupRepository,
    required this.mediaFileManager,
    required this.lifecycleLock,
    required this.nowMs,
  });

  final GroupPrivateMediaLifecycleRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final GroupPrivateMediaCleanupRepository cleanupRepository;
  final MediaFileManager mediaFileManager;
  final MediaAttachmentLifecycleLock lifecycleLock;
  final int Function() nowMs;

  Future<GroupPrivateMediaOpenGrantData?> qualifyOpen({
    required String groupId,
    required String messageId,
    required String attachmentId,
  }) {
    if (!DirectPrivateMediaPathGuard.identifiersAreSafe(
      contactPeerId: groupId,
      messageId: messageId,
      attachmentId: attachmentId,
    )) {
      return Future.value(null);
    }
    return lifecycleLock.synchronized(
      attachmentId,
      () => _qualifyOpenWithinLock(
        groupId: groupId,
        messageId: messageId,
        attachmentId: attachmentId,
      ),
    );
  }

  Future<GroupPrivateMediaOpenGrantData?> _qualifyOpenWithinLock({
    required String groupId,
    required String messageId,
    required String attachmentId,
  }) async {
    var parent = await messageRepository.loadGroupPrivateMediaMessage(
      messageId,
    );
    if (parent == null ||
        parent.groupId != groupId ||
        !parent.isIncoming ||
        !parent.privateMediaPolicy.isPrivate ||
        parent.mediaConsumedAt != null ||
        parent.mediaExpiredAt != null ||
        parent.mediaCleanupPending) {
      return null;
    }
    if (parent.privateMediaPolicy.lifecycle ==
        GroupMediaLifecycle.disappearing) {
      await messageRepository.advanceGroupPrivateMediaClock(
        messageId,
        nowMs: nowMs(),
      );
      parent = await messageRepository.loadGroupPrivateMediaMessage(messageId);
      if (parent == null ||
          parent.groupId != groupId ||
          parent.mediaExpiredAt != null ||
          parent.mediaCleanupPending) {
        return null;
      }
    }

    final rows = await mediaAttachmentRepository.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    if (rows.length != 1) return null;
    final attachment = rows.single;
    if (attachment.id != attachmentId ||
        attachment.messageId != messageId ||
        attachment.ownerLane != MediaOwnerLane.group ||
        attachment.mime == 'image/gif') {
      return null;
    }
    // Group `contentHash` authenticates the relay ciphertext and is checked
    // before decrypt/commit. The canonical local file is plaintext, so hashing
    // it against that ciphertext digest would reject every valid download.
    // Re-open instead revalidates the exact app-owned path, byte length and
    // decoded MIME signature; the guarded download commit proves the prior
    // authenticated-decrypt step.
    final integrity =
        await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
          attachment: attachment,
          ownerScopeId: groupId,
          mediaFileManager: mediaFileManager,
        );
    final expectedAbsolute = integrity.resolvedPath;
    if (!integrity.isValid || expectedAbsolute == null) return null;

    return GroupPrivateMediaOpenGrantData(
      groupId: groupId,
      messageId: messageId,
      attachmentId: attachmentId,
      policy: parent.privateMediaPolicy,
      kind: attachment.mediaType == 'video'
          ? MediaViewerKind.video
          : MediaViewerKind.image,
      localPath: expectedAbsolute,
      expiresAtMs: parent.mediaExpiresAt,
    );
  }

  Future<bool> consumeAtFirstFrame(GroupPrivateMediaOpenGrantData grant) {
    if (grant.policy.lifecycle != GroupMediaLifecycle.viewOnce ||
        grant.consumedAtFirstFrame) {
      return Future.value(
        grant.policy.lifecycle != GroupMediaLifecycle.viewOnce,
      );
    }
    return lifecycleLock.synchronized(grant.attachmentId, () async {
      final current = await _qualifyOpenWithinLock(
        groupId: grant.groupId,
        messageId: grant.messageId,
        attachmentId: grant.attachmentId,
      );
      if (current == null || current.localPath != grant.localPath) return false;
      final consumed = await messageRepository.consumeGroupPrivateMedia(
        grant.messageId,
        nowMs: nowMs(),
      );
      if (consumed) grant.consumedAtFirstFrame = true;
      return consumed;
    });
  }

  Future<bool> revalidateOpen(GroupPrivateMediaOpenGrantData grant) async {
    if (grant.consumedAtFirstFrame &&
        grant.policy.lifecycle == GroupMediaLifecycle.viewOnce) {
      return true;
    }
    final current = await qualifyOpen(
      groupId: grant.groupId,
      messageId: grant.messageId,
      attachmentId: grant.attachmentId,
    );
    return current != null &&
        current.policy == grant.policy &&
        current.localPath == grant.localPath;
  }

  Future<void> settle(GroupPrivateMediaOpenGrantData grant) async {
    if (grant.policy.lifecycle == GroupMediaLifecycle.viewOnce) {
      if (grant.consumedAtFirstFrame) {
        await cleanupTerminalMessage(grant.messageId);
      }
      return;
    }
    if (grant.policy.lifecycle == GroupMediaLifecycle.disappearing) {
      await messageRepository.advanceGroupPrivateMediaClock(
        grant.messageId,
        nowMs: nowMs(),
      );
      final current = await messageRepository.loadGroupPrivateMediaMessage(
        grant.messageId,
      );
      if (current?.mediaExpiredAt != null) {
        await cleanupTerminalMessage(grant.messageId);
      }
    }
  }

  Future<GroupPrivateMediaReconcileResult> sweepExpiries({
    int limit = 100,
    int? evaluationFloorMs,
  }) async {
    final result = GroupPrivateMediaReconcileResult();
    final sample = nowMs();
    final evaluationNow =
        evaluationFloorMs != null && evaluationFloorMs > sample
        ? evaluationFloorMs
        : sample;
    final active = await messageRepository
        .loadActiveGroupPrivateMediaDisappearing(limit: limit);
    for (final parent in active) {
      try {
        final metadata = await cleanupRepository
            .loadGroupPrivateMediaLifecycleAttachmentMetadata(parent.id);
        await _withAttachmentLocks(metadata.map((item) => item.id), () async {
          await messageRepository.advanceGroupPrivateMediaClock(
            parent.id,
            nowMs: evaluationNow,
          );
        });
        final after = await messageRepository.loadGroupPrivateMediaMessage(
          parent.id,
        );
        if (after?.mediaExpiredAt != null) {
          result.terminalClaims++;
          if (await cleanupTerminalMessage(parent.id)) {
            result.cleanupCompleted++;
          }
        }
      } catch (_) {
        result.retainedAfterError++;
      }
    }
    return result;
  }

  Future<GroupPrivateMediaReconcileResult> reconcileLocalLifecycle({
    int limit = 100,
  }) async {
    final result = await sweepExpiries(limit: limit);
    final candidates = await messageRepository
        .loadGroupPrivateMediaRecoveryCandidates(limit: limit);
    for (final candidate in candidates) {
      try {
        if (await cleanupTerminalMessage(candidate.id)) {
          result.cleanupCompleted++;
        }
      } catch (_) {
        result.retainedAfterError++;
        try {
          await messageRepository.rotateGroupPrivateMediaRecoveryCandidate(
            candidate.id,
            nowMs: nowMs(),
          );
        } catch (_) {}
      }
    }
    return result;
  }

  Future<int?> loadNextExpiryAtMs() =>
      messageRepository.loadNextGroupPrivateMediaExpiryAtMs();

  Future<bool> cleanupTerminalMessage(String messageId) async {
    final metadata = await cleanupRepository
        .loadGroupPrivateMediaLifecycleAttachmentMetadata(messageId);
    return _withAttachmentLocks(metadata.map((item) => item.id), () async {
      final parent = await messageRepository.loadGroupPrivateMediaMessage(
        messageId,
      );
      if (!_hasCleanupAuthority(parent)) return false;
      final current = await cleanupRepository
          .loadGroupPrivateMediaLifecycleAttachmentMetadata(messageId);
      for (final attachment in current) {
        if (attachment.messageId != messageId ||
            directPrivateMediaTransferRegistry.isActive(attachment.id)) {
          throw StateError('group private cleanup retained unsafe ownership');
        }
        await _deleteExactAppOwnedArtifacts(parent!, attachment);
        if (!await cleanupRepository
            .deleteGroupPrivateMediaEncryptionKeyWithinLock(
              messageId: messageId,
              attachmentId: attachment.id,
            )) {
          throw StateError('group private cleanup key authority lost');
        }
        final deleted = await cleanupRepository
            .deleteGroupPrivateMediaAttachmentWithinLock(
              messageId: messageId,
              attachmentId: attachment.id,
            );
        if (deleted == 0) {
          final remaining = await cleanupRepository
              .loadGroupPrivateMediaLifecycleAttachmentMetadata(messageId);
          if (remaining.any((item) => item.id == attachment.id)) {
            throw StateError('group private cleanup row authority lost');
          }
        }
      }
      await messageRepository.completeGroupPrivateMediaCleanup(messageId);
      return true;
    });
  }

  bool _hasCleanupAuthority(GroupMessage? parent) =>
      parent != null &&
      parent.privateMediaPolicy.requiresRedaction &&
      parent.mediaCleanupPending &&
      (parent.mediaConsumedAt != null ||
          parent.mediaExpiredAt != null ||
          parent.privateMediaPolicy.isUnsupported);

  Future<void> _deleteExactAppOwnedArtifacts(
    GroupMessage parent,
    GroupPrivateMediaLifecycleAttachmentMetadata attachment,
  ) async {
    if (!DirectPrivateMediaPathGuard.identifiersAreSafe(
      contactPeerId: parent.groupId,
      messageId: parent.id,
      attachmentId: attachment.id,
    )) {
      throw StateError('group private cleanup rejected unsafe identity');
    }
    final canonicalRelative = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: parent.groupId,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    final pendingRelative =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: parent.id,
          attachmentId: attachment.id,
          mime: attachment.mime,
        );
    final canonicalPath = await mediaFileManager.resolveStoredPath(
      canonicalRelative,
    );
    final pendingPath = await mediaFileManager.resolveStoredPath(
      pendingRelative,
    );
    final targets = <({String path, String root})>[];
    for (final base in [canonicalPath, pendingPath]) {
      final root = p.dirname(p.dirname(base));
      targets.addAll([
        (path: base, root: root),
        (path: '$base.part', root: root),
        (path: '$base.part.dec', root: root),
        (path: '$base.enc', root: root),
        (path: '$base.enc.part', root: root),
        (path: '$base.enc.dec', root: root),
      ]);
    }
    for (final target in targets) {
      if (!await DirectPrivateMediaPathGuard.authorizeTarget(
        targetPath: target.path,
        authorityRoot: target.root,
      )) {
        throw StateError('group private cleanup rejected resolved target');
      }
    }
    for (final target in targets) {
      await mediaFileManager.deleteFile(
        target.path,
        caller: 'GroupPrivateMediaLifecycleEngine.cleanupTerminalMessage',
        reason: 'group_private_media_terminal_cleanup',
        redactTelemetry: true,
      );
    }
  }

  Future<T> _withAttachmentLocks<T>(
    Iterable<String> attachmentIds,
    Future<T> Function() action,
  ) {
    final ids = attachmentIds.toSet().toList()..sort();
    Future<T> acquire(int index) {
      if (index >= ids.length) return action();
      return lifecycleLock.synchronized(ids[index], () => acquire(index + 1));
    }

    return acquire(0);
  }
}
