import 'dart:io';

import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:path/path.dart' as p;

/// Direct lane adapter for the shared lifecycle engine.
class DirectPrivateMediaLifecycle
    implements
        PrivateMediaLifecycleLaneAdapter,
        PrivateMediaInterruptedDownloadRecoveryAdapter {
  DirectPrivateMediaLifecycle({
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.mediaFileManager,
  });

  final DirectPrivateMediaLifecycleRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final MediaFileManager mediaFileManager;

  DirectPrivateMediaCleanupRepository get _cleanupRepository {
    final repository = mediaAttachmentRepository;
    if (repository is! DirectPrivateMediaCleanupRepository) {
      throw StateError(
        'Direct private-media cleanup requires an exact raw cleanup repository',
      );
    }
    return repository as DirectPrivateMediaCleanupRepository;
  }

  DirectPrivateMediaDownloadStateRepository get _downloadStateRepository {
    final repository = mediaAttachmentRepository;
    if (repository is! DirectPrivateMediaDownloadStateRepository) {
      throw StateError(
        'Direct private-media recovery requires guarded download state',
      );
    }
    return repository as DirectPrivateMediaDownloadStateRepository;
  }

  @override
  Future<PrivateMediaLifecycleTarget?> loadTarget(String messageId) async {
    final message = await messageRepository.loadPrivateMediaLifecycleMessage(
      messageId,
    );
    if (message == null || !message.privateMediaPolicy.requiresRedaction) {
      return null;
    }
    return _toTarget(message);
  }

  Future<PrivateMediaLifecycleTarget> _toTarget(
    ConversationMessage message,
  ) async {
    final metadata = await _cleanupRepository
        .loadDirectPrivateMediaLifecycleAttachmentMetadata(message.id);
    final attachments = <PrivateMediaLifecycleAttachment>[];
    for (final attachment in metadata) {
      final verifiedPath = await _verifiedOpenableLocalPath(
        message,
        attachment,
      );
      attachments.add(
        PrivateMediaLifecycleAttachment(
          id: attachment.id,
          messageId: attachment.messageId,
          storedLocalPath: attachment.localPath,
          localPath: verifiedPath,
          mime: attachment.mime,
          size: attachment.size,
          isDownloadComplete:
              attachment.downloadStatus == kMediaDownloadStatusDone,
          isIntegrityEligible: verifiedPath != null,
          isDownloadInProgress:
              attachment.downloadStatus == kMediaDownloadStatusDownloading,
        ),
      );
    }
    return PrivateMediaLifecycleTarget(
      messageId: message.id,
      scopeId: message.contactPeerId,
      mode: message.privateMediaMode,
      state: message.privateMediaState,
      receivedAtMs: message.privateMediaReceivedAtMs,
      expiresAtMs: message.privateMediaExpiresAtMs,
      revealedAtMs: message.privateMediaRevealedAtMs,
      terminalAtMs: message.privateMediaTerminalAtMs,
      clockHighWaterMs: message.privateMediaClockHighWaterMs,
      hidden: message.hiddenAt != null || message.deletedAt != null,
      attachments: attachments,
    );
  }

  Future<String?> _verifiedOpenableLocalPath(
    ConversationMessage parent,
    DirectPrivateMediaLifecycleAttachmentMetadata attachment,
  ) async {
    final storedPath = attachment.localPath;
    if (attachment.downloadStatus != kMediaDownloadStatusDone ||
        storedPath == null ||
        storedPath.isEmpty ||
        !DirectPrivateMediaPathGuard.identifiersAreSafe(
          contactPeerId: parent.contactPeerId,
          messageId: parent.id,
          attachmentId: attachment.id,
        ) ||
        attachment.size <= 0) {
      return null;
    }
    final expectedRelative = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: parent.contactPeerId,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    final expectedAbsolute = await mediaFileManager.resolveStoredPath(
      expectedRelative,
    );
    final normalizedStored = p.normalize(storedPath.replaceAll('\\', '/'));
    if (normalizedStored != p.normalize(expectedRelative) &&
        normalizedStored != p.normalize(expectedAbsolute)) {
      return null;
    }
    final root = p.dirname(p.dirname(expectedAbsolute));
    if (!await DirectPrivateMediaPathGuard.authorizeTarget(
      targetPath: expectedAbsolute,
      authorityRoot: root,
      requireExistingFile: true,
    )) {
      return null;
    }
    try {
      return await File(expectedAbsolute).length() == attachment.size
          ? expectedAbsolute
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> claimOpening(String messageId, {required int nowMs}) =>
      messageRepository.claimPrivateMediaOpening(messageId, nowMs: nowMs);

  @override
  Future<bool> markViewing(String messageId, {required int nowMs}) =>
      messageRepository.markPrivateMediaViewing(messageId, nowMs: nowMs);

  @override
  Future<bool> rollbackOpening(String messageId) =>
      messageRepository.rollbackPrivateMediaOpening(messageId);

  @override
  Future<bool> consume(String messageId, {required int nowMs}) =>
      messageRepository.consumePrivateMedia(messageId, nowMs: nowMs);

  @override
  Future<bool> advanceClock(String messageId, {required int nowMs}) =>
      messageRepository.advancePrivateMediaClock(messageId, nowMs: nowMs);

  @override
  Future<bool> failClosedCorruptState(String messageId, {required int nowMs}) =>
      messageRepository.failClosedCorruptPrivateMediaState(
        messageId,
        nowMs: nowMs,
      );

  @override
  Future<List<PrivateMediaLifecycleTarget>> loadActiveDisappearing({
    int limit = 100,
  }) async {
    final messages = await messageRepository.loadActiveDisappearingPrivateMedia(
      limit: limit,
    );
    final targets = <PrivateMediaLifecycleTarget>[];
    for (final message in messages) {
      targets.add(await _toTarget(message));
    }
    return targets;
  }

  @override
  Future<List<PrivateMediaLifecycleTarget>> loadRecoveryCandidates({
    int limit = 100,
  }) async {
    final messages = await messageRepository.loadPrivateMediaRecoveryCandidates(
      limit: limit,
    );
    final targets = <PrivateMediaLifecycleTarget>[];
    for (final message in messages) {
      targets.add(await _toTarget(message));
    }
    return targets;
  }

  @override
  Future<bool> rotateRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) => messageRepository.rotatePrivateMediaRecoveryCandidate(
    messageId,
    nowMs: nowMs,
  );

  @override
  Future<int?> loadNextExpiryAtMs() =>
      messageRepository.loadNextPrivateMediaExpiryAtMs();

  @override
  Future<int> recoverInterruptedDownloadsWithinLock(
    PrivateMediaLifecycleTarget current, {
    required int nowMs,
  }) async {
    var recovered = 0;
    for (final attachment in current.attachments) {
      if (!attachment.isDownloadInProgress) continue;
      if (directPrivateMediaTransferRegistry.isActive(attachment.id)) {
        throw StateError('private recovery retained an active transfer claim');
      }
      await _deleteExactAppOwnedArtifacts(
        messageId: current.messageId,
        contactPeerId: current.scopeId,
        attachment: DirectPrivateMediaCleanupAttachment(
          id: attachment.id,
          messageId: current.messageId,
          mime: attachment.mime,
        ),
      );
      final released = await _downloadStateRepository
          .recordDirectPrivateMediaDownloadFailureWithinLock(
            attachment.id,
            messageId: current.messageId,
            nowMs: nowMs,
            incrementRetryCount: true,
            failureStatus: kMediaDownloadStatusFailed,
            expectedDownloadStatus: kMediaDownloadStatusDownloading,
            clearLocalPath: true,
          );
      if (released) recovered++;
    }
    return recovered;
  }

  @override
  Future<void> cleanupTerminalWithinLock(
    PrivateMediaLifecycleTarget current,
  ) async {
    final parent = await messageRepository.loadPrivateMediaLifecycleMessage(
      current.messageId,
    );
    if (parent == null ||
        (!parent.privateMediaState.isTerminal &&
            parent.hiddenAt == null &&
            parent.deletedAt == null)) {
      throw StateError('private cleanup requires durable terminal authority');
    }

    final attachments = await _cleanupRepository
        .loadDirectPrivateMediaCleanupAttachments(parent.id);
    if (attachments.any(
      (attachment) =>
          directPrivateMediaTransferRegistry.isActive(attachment.id),
    )) {
      throw StateError('private cleanup retained an active transfer claim');
    }
    for (final attachment in attachments) {
      if (attachment.messageId != parent.id) {
        throw StateError('private cleanup attachment parent mismatch');
      }
      await _deleteExactAppOwnedArtifacts(
        messageId: parent.id,
        contactPeerId: parent.contactPeerId,
        attachment: attachment,
      );
      final keyDeleted = await _cleanupRepository
          .deleteDirectPrivateMediaEncryptionKeyWithinLock(
            messageId: parent.id,
            attachmentId: attachment.id,
          );
      if (!keyDeleted) {
        throw StateError('private cleanup exact key authority lost');
      }
      final deleted = await _cleanupRepository
          .deleteDirectPrivateMediaAttachmentWithinLock(
            messageId: parent.id,
            attachmentId: attachment.id,
          );
      if (deleted == 0) {
        final remaining = await _cleanupRepository
            .loadDirectPrivateMediaCleanupAttachments(parent.id);
        if (remaining.any((item) => item.id == attachment.id)) {
          throw StateError('private cleanup exact row finalize lost');
        }
      }
    }
  }

  Future<void> _deleteExactAppOwnedArtifacts({
    required String messageId,
    required String contactPeerId,
    required DirectPrivateMediaCleanupAttachment attachment,
  }) async {
    if (!DirectPrivateMediaPathGuard.identifiersAreSafe(
      contactPeerId: contactPeerId,
      messageId: messageId,
      attachmentId: attachment.id,
    )) {
      throw StateError('private cleanup rejected unsafe path identifier');
    }
    final canonicalRelative = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    final pendingRelative =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: messageId,
          attachmentId: attachment.id,
          mime: attachment.mime,
        );
    final canonicalPath = await mediaFileManager.resolveStoredPath(
      canonicalRelative,
    );
    final pendingPath = await mediaFileManager.resolveStoredPath(
      pendingRelative,
    );
    final canonicalRoot = p.dirname(p.dirname(canonicalPath));
    final pendingRoot = p.dirname(p.dirname(pendingPath));

    final expanded = <({String path, String root})>[];
    for (final target in [
      (path: canonicalPath, root: canonicalRoot),
      (path: pendingPath, root: pendingRoot),
    ]) {
      expanded.addAll([
        target,
        (path: '${target.path}.part', root: target.root),
        (path: '${target.path}.enc', root: target.root),
        (path: '${target.path}.enc.part', root: target.root),
      ]);
    }
    // Preflight every target before the first unlink so a later unsafe symlink
    // cannot leave a half-cleaned row/key saga.
    for (final target in expanded) {
      if (!await DirectPrivateMediaPathGuard.authorizeTarget(
        targetPath: target.path,
        authorityRoot: target.root,
      )) {
        throw StateError('private cleanup rejected unsafe resolved target');
      }
    }
    for (final target in expanded) {
      await mediaFileManager.deleteFile(
        target.path,
        caller: 'DirectPrivateMediaLifecycle.cleanupTerminalWithinLock',
        reason: 'direct_private_media_terminal_cleanup',
        redactTelemetry: true,
      );
    }
  }
}
