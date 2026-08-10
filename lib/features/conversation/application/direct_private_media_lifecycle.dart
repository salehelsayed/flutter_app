import 'dart:io';

import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:path/path.dart' as p;

enum DirectPrivateMediaOpenQualificationFailure {
  localAuthorityMissing,
  senderLocalBytesMissing,
}

class DirectPrivateMediaOpenQualificationResult {
  const DirectPrivateMediaOpenQualificationResult({
    required this.target,
    required this.failure,
  });

  final PrivateMediaLifecycleTarget? target;
  final DirectPrivateMediaOpenQualificationFailure? failure;
}

/// Reconciles process-local completion ownership after a real outgoing
/// protected/view-once upload lane releases its transfer claim.
///
/// Opening/viewing keeps a deferred completion so a later pre-frame rollback
/// can atomically promote the canonical result. Terminal/deleted authority with
/// no durable envelope abandons only the process-local authorization, leaving
/// the exact pending row/source available for a fresh same-process upload.
Future<void> reconcileReleasedOutgoingDirectPrivateUploadAttempt({
  required String messageId,
  required Map<String, String> expectedPendingPaths,
  required OutgoingDirectPrivateMutationCoordinator coordinator,
  required OutgoingDirectPrivateEnvelopeCustodyRepository envelopeRepository,
  required DirectPrivateMediaLifecycleRepository lifecycleRepository,
}) async {
  if (expectedPendingPaths.isEmpty) return;
  for (final pending in expectedPendingPaths.entries) {
    try {
      await envelopeRepository.markOutgoingDirectPrivateUploadHandoffFailed(
        messageId: messageId,
        attachmentId: pending.key,
        expectedPendingLocalPath: pending.value,
      );
    } catch (_) {
      // The durable row remains eligible for normal stuck-sending recovery.
    }
  }

  ConversationMessage? parent;
  try {
    parent = await lifecycleRepository.loadPrivateMediaLifecycleMessage(
      messageId,
    );
  } catch (_) {
    return;
  }
  final envelope = parent?.wireEnvelope?.trim();
  final terminalWithoutHandoff =
      parent == null ||
      ((parent.privateMediaState.isTerminal ||
              parent.hiddenAt != null ||
              parent.deletedAt != null) &&
          (envelope == null || envelope.isEmpty));
  if (!terminalWithoutHandoff) return;

  for (final attachmentId in expectedPendingPaths.keys) {
    try {
      await coordinator.discardCompletion(
        messageId: messageId,
        attachmentId: attachmentId,
      );
    } catch (_) {
      // Restart also clears this process-local authorization. Never obscure
      // the durable retry result with a best-effort memory cleanup failure.
    }
  }
}

/// Direct-lane qualification seam used only by the viewer controller.
///
/// Generic lifecycle loads remain read-only. The deployed dangling-path
/// repair is an explicit qualification step, after which the controller
/// reloads both its current rows and the lifecycle target.
abstract interface class DirectPrivateMediaOpenQualificationAdapter {
  Future<void> repairLegacyOpenQualificationIfEligible({
    required String messageId,
    required String attachmentId,
  });

  Future<DirectPrivateMediaOpenQualificationResult>
  loadOpenQualificationTarget({
    required String messageId,
    required String attachmentId,
  });
}

enum _DirectPrivateMediaPathProbeOutcome {
  authorized,
  senderLocalBytesMissing,
  refused,
}

class _DirectPrivateMediaPathProbe {
  const _DirectPrivateMediaPathProbe(this.outcome, [this.path]);

  final _DirectPrivateMediaPathProbeOutcome outcome;
  final String? path;
}

/// Direct lane adapter for the shared lifecycle engine.
class DirectPrivateMediaLifecycle
    implements
        PrivateMediaLifecycleLaneAdapter,
        PrivateMediaIndeterminateQuarantineAdapter,
        PrivateMediaInterruptedDownloadRecoveryAdapter,
        DirectPrivateMediaOpenQualificationAdapter {
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

  DirectPrivateMediaExactOpeningLeaseRepository get _exactLeaseRepository {
    final repository = messageRepository;
    if (repository is! DirectPrivateMediaExactOpeningLeaseRepository) {
      throw StateError(
        'Direct private-media reveal requires exact durable lease CAS',
      );
    }
    return repository as DirectPrivateMediaExactOpeningLeaseRepository;
  }

  @override
  Future<PrivateMediaLifecycleTarget?> loadTarget(String messageId) async {
    final message = await messageRepository.loadPrivateMediaLifecycleMessage(
      messageId,
    );
    if (message == null || !message.privateMediaPolicy.requiresRedaction) {
      return null;
    }
    return (await _buildTarget(message)).target;
  }

  @override
  Future<DirectPrivateMediaOpenQualificationResult>
  loadOpenQualificationTarget({
    required String messageId,
    required String attachmentId,
  }) async {
    final message = await messageRepository.loadPrivateMediaLifecycleMessage(
      messageId,
    );
    if (message == null || !message.privateMediaPolicy.requiresRedaction) {
      return const DirectPrivateMediaOpenQualificationResult(
        target: null,
        failure:
            DirectPrivateMediaOpenQualificationFailure.localAuthorityMissing,
      );
    }
    final built = await _buildTarget(message);
    final probe = built.probes[attachmentId];
    return DirectPrivateMediaOpenQualificationResult(
      target: built.target,
      failure:
          probe == _DirectPrivateMediaPathProbeOutcome.senderLocalBytesMissing
          ? DirectPrivateMediaOpenQualificationFailure.senderLocalBytesMissing
          : probe == _DirectPrivateMediaPathProbeOutcome.authorized
          ? null
          : DirectPrivateMediaOpenQualificationFailure.localAuthorityMissing,
    );
  }

  @override
  Future<void> repairLegacyOpenQualificationIfEligible({
    required String messageId,
    required String attachmentId,
  }) async {
    final repository = mediaAttachmentRepository;
    if (repository is! DirectPrivateMediaLegacyPathRepairRepository ||
        repository is! DirectPrivateMediaCleanupRuntime) {
      return;
    }
    final repairRepository =
        repository as DirectPrivateMediaLegacyPathRepairRepository;
    final runtime = repository as DirectPrivateMediaCleanupRuntime;
    await runtime.directPrivateMediaLifecycleLock.synchronized(
      attachmentId,
      () async {
        final message = await messageRepository
            .loadPrivateMediaLifecycleMessage(messageId);
        if (message == null ||
            message.id != messageId ||
            message.isIncoming ||
            message.hiddenAt != null ||
            message.deletedAt != null ||
            message.privateMediaPolicy.version != 1 ||
            !_isOutgoingOneMoreLookMode(message.privateMediaMode) ||
            message.privateMediaState != PrivateMediaLifecycleState.available ||
            message.privateMediaRevealedAtMs != null ||
            message.privateMediaTerminalAtMs != null ||
            !DirectPrivateMediaPathGuard.identifiersAreSafe(
              contactPeerId: message.contactPeerId,
              messageId: message.id,
              attachmentId: attachmentId,
            )) {
          return;
        }
        final metadata = await _cleanupRepository
            .loadDirectPrivateMediaLifecycleAttachmentMetadata(message.id);
        final matches = metadata.where(
          (attachment) =>
              attachment.id == attachmentId &&
              attachment.messageId == message.id,
        );
        if (matches.length != 1) return;
        final attachment = matches.single;
        final storedPath = attachment.localPath;
        if (attachment.downloadStatus != kMediaDownloadStatusDone ||
            storedPath == null ||
            storedPath.isEmpty ||
            !p.isAbsolute(storedPath) ||
            attachment.size <= 0) {
          return;
        }

        final pendingRelative =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: message.id,
              attachmentId: attachment.id,
              mime: attachment.mime,
            );
        final pendingRoot = p.normalize(
          await mediaFileManager.trustedPendingUploadRootPath(),
        );
        final expectedPendingAbsolute = p.normalize(
          p.join(pendingRoot, message.id, p.posix.basename(pendingRelative)),
        );
        if (p.normalize(storedPath) != expectedPendingAbsolute ||
            await FileSystemEntity.type(
                  expectedPendingAbsolute,
                  followLinks: false,
                ) !=
                FileSystemEntityType.notFound) {
          return;
        }

        final canonicalRelative =
            MediaFilePathConvention.relativePathForAttachment(
              contactPeerId: message.contactPeerId,
              blobId: attachment.id,
              mime: attachment.mime,
            );
        final canonicalRoot = p.normalize(
          await mediaFileManager.trustedMediaRootPath(),
        );
        final canonicalAbsolute = p.normalize(
          p.join(
            canonicalRoot,
            message.contactPeerId,
            p.posix.basename(canonicalRelative),
          ),
        );
        final canonicalProbe = await _probeExpectedFile(
          targetPath: canonicalAbsolute,
          authorityRoot: canonicalRoot,
          expectedSize: attachment.size,
        );
        if (canonicalProbe.outcome !=
            _DirectPrivateMediaPathProbeOutcome.authorized) {
          return;
        }
        await repairRepository
            .repairOutgoingDirectPrivateMediaDoneLocalPathWithinLock(
              messageId: message.id,
              attachmentId: attachment.id,
              expectedStoredLocalPath: storedPath,
              canonicalLocalPath: canonicalRelative,
              expectedContactPeerId: message.contactPeerId,
              expectedMime: attachment.mime,
              expectedSize: attachment.size,
            );
      },
    );
  }

  /// Removes only the exact pending source made redundant by a committed
  /// outgoing-private promotion.
  ///
  /// Callers invoke this after releasing their transfer token. The method
  /// reacquires the repository-owned attachment lock, requalifies the durable
  /// parent and canonical completion, and authorizes both filesystem roots
  /// independently before unlinking anything. A live viewer/transfer or a
  /// stale/conflicting row leaves the source untouched.
  Future<bool> cleanupCommittedPendingSource({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  }) async {
    final repository = mediaAttachmentRepository;
    if (repository is! DirectPrivateMediaCleanupRuntime ||
        repository is! DirectPrivateMediaCleanupRepository) {
      return false;
    }
    final runtime = repository as DirectPrivateMediaCleanupRuntime;
    return runtime.directPrivateMediaLifecycleLock.synchronized(
      attachmentId,
      () async {
        if (directPrivateMediaTransferRegistry.isActive(attachmentId)) {
          return false;
        }
        final parent = await messageRepository.loadPrivateMediaLifecycleMessage(
          messageId,
        );
        if (parent == null ||
            parent.id != messageId ||
            parent.isIncoming ||
            parent.hiddenAt != null ||
            parent.deletedAt != null ||
            parent.privateMediaPolicy.version != 1 ||
            !_isOutgoingOneMoreLookMode(parent.privateMediaMode) ||
            parent.privateMediaState != PrivateMediaLifecycleState.available ||
            parent.privateMediaRevealedAtMs != null ||
            parent.privateMediaTerminalAtMs != null ||
            !DirectPrivateMediaPathGuard.identifiersAreSafe(
              contactPeerId: parent.contactPeerId,
              messageId: parent.id,
              attachmentId: attachmentId,
            )) {
          return false;
        }

        final metadata = await _cleanupRepository
            .loadDirectPrivateMediaLifecycleAttachmentMetadata(parent.id);
        final matches = metadata.where(
          (attachment) =>
              attachment.id == attachmentId &&
              attachment.messageId == parent.id,
        );
        if (matches.length != 1) return false;
        final attachment = matches.single;
        if (attachment.downloadStatus != kMediaDownloadStatusDone ||
            attachment.size <= 0) {
          return false;
        }

        // The pending plaintext is redundant only when the canonical done row
        // still hydrates its actual secure-store key. A DB secure-reference is
        // not enough: after key loss the pending source may be the only bytes
        // that can be re-uploaded, so it must remain untouched.
        final hydrated = await mediaAttachmentRepository
            .getAttachmentsForMessage(parent.id, owner: MediaOwnerLane.direct);
        final committedMatches = hydrated.where(
          (candidate) =>
              candidate.id == attachment.id &&
              candidate.messageId == parent.id &&
              candidate.ownerLane == MediaOwnerLane.direct,
        );
        if (committedMatches.length != 1) return false;
        final committed = committedMatches.single;
        if (committed.downloadStatus != kMediaDownloadStatusDone ||
            committed.mime != attachment.mime ||
            committed.size != attachment.size ||
            committed.contentHash == null ||
            committed.contentHash!.isEmpty ||
            !committed.hasEncryptionKeyMaterial ||
            committed.encryptionScheme !=
                kMediaAttachmentEncryptionSchemeBlobAesGcmV1) {
          return false;
        }

        final expectedPending =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: parent.id,
              attachmentId: attachment.id,
              mime: attachment.mime,
            );
        final expectedCanonical =
            MediaFilePathConvention.relativePathForAttachment(
              contactPeerId: parent.contactPeerId,
              blobId: attachment.id,
              mime: attachment.mime,
            );
        if (expectedPendingLocalPath != expectedPending ||
            attachment.localPath != expectedCanonical ||
            committed.localPath != expectedCanonical) {
          return false;
        }

        final canonicalRoot = p.normalize(
          await mediaFileManager.trustedMediaRootPath(),
        );
        final canonicalAbsolute = p.normalize(
          p.join(
            canonicalRoot,
            parent.contactPeerId,
            p.posix.basename(expectedCanonical),
          ),
        );
        final canonicalProbe = await _probeExpectedFile(
          targetPath: canonicalAbsolute,
          authorityRoot: canonicalRoot,
          expectedSize: attachment.size,
        );
        if (canonicalProbe.outcome !=
            _DirectPrivateMediaPathProbeOutcome.authorized) {
          return false;
        }

        final pendingRoot = p.normalize(
          await mediaFileManager.trustedPendingUploadRootPath(),
        );
        final pendingAbsolute = p.normalize(
          p.join(pendingRoot, parent.id, p.posix.basename(expectedPending)),
        );
        if (!await DirectPrivateMediaPathGuard.authorizeTarget(
          targetPath: pendingAbsolute,
          authorityRoot: pendingRoot,
        )) {
          return false;
        }
        final pendingType = await FileSystemEntity.type(
          pendingAbsolute,
          followLinks: false,
        );
        if (pendingType == FileSystemEntityType.notFound) return true;
        if (pendingType != FileSystemEntityType.file ||
            await File(pendingAbsolute).length() != attachment.size) {
          return false;
        }
        await mediaFileManager.deleteFile(
          pendingAbsolute,
          caller: 'DirectPrivateMediaLifecycle.cleanupCommittedPendingSource',
          reason: 'direct_private_media_committed_pending_cleanup',
          redactTelemetry: true,
        );
        return await FileSystemEntity.type(
              pendingAbsolute,
              followLinks: false,
            ) ==
            FileSystemEntityType.notFound;
      },
    );
  }

  Future<
    ({
      PrivateMediaLifecycleTarget target,
      Map<String, _DirectPrivateMediaPathProbeOutcome> probes,
    })
  >
  _buildTarget(ConversationMessage message) async {
    final metadata = await _cleanupRepository
        .loadDirectPrivateMediaLifecycleAttachmentMetadata(message.id);
    final attachments = <PrivateMediaLifecycleAttachment>[];
    final probes = <String, _DirectPrivateMediaPathProbeOutcome>{};
    for (final attachment in metadata) {
      final probe = await _probeOpenableLocalPath(message, attachment);
      probes[attachment.id] = probe.outcome;
      final pendingOneMoreLook =
          !message.isIncoming &&
          _isOutgoingOneMoreLookMode(message.privateMediaMode) &&
          attachment.downloadStatus == kMediaDownloadStatusUploadPending;
      attachments.add(
        PrivateMediaLifecycleAttachment(
          id: attachment.id,
          messageId: attachment.messageId,
          storedLocalPath: attachment.localPath,
          localPath: probe.path,
          mime: attachment.mime,
          size: attachment.size,
          isDownloadComplete:
              attachment.downloadStatus == kMediaDownloadStatusDone ||
              pendingOneMoreLook,
          isIntegrityEligible:
              probe.outcome == _DirectPrivateMediaPathProbeOutcome.authorized,
          isDownloadInProgress:
              attachment.downloadStatus == kMediaDownloadStatusDownloading,
        ),
      );
    }
    return (
      target: PrivateMediaLifecycleTarget(
        messageId: message.id,
        scopeId: message.contactPeerId,
        direction: message.isIncoming
            ? PrivateMediaDirection.incoming
            : PrivateMediaDirection.outgoing,
        mode: message.privateMediaMode,
        state: message.privateMediaState,
        receivedAtMs: message.privateMediaReceivedAtMs,
        expiresAtMs: message.privateMediaExpiresAtMs,
        revealedAtMs: message.privateMediaRevealedAtMs,
        terminalAtMs: message.privateMediaTerminalAtMs,
        clockHighWaterMs: message.privateMediaClockHighWaterMs,
        hidden: message.hiddenAt != null || message.deletedAt != null,
        attachments: attachments,
      ),
      probes: probes,
    );
  }

  Future<_DirectPrivateMediaPathProbe> _probeOpenableLocalPath(
    ConversationMessage parent,
    DirectPrivateMediaLifecycleAttachmentMetadata attachment,
  ) async {
    final storedPath = attachment.localPath;
    if (storedPath == null ||
        storedPath.isEmpty ||
        attachment.messageId != parent.id ||
        !DirectPrivateMediaPathGuard.identifiersAreSafe(
          contactPeerId: parent.contactPeerId,
          messageId: parent.id,
          attachmentId: attachment.id,
        ) ||
        attachment.size <= 0) {
      return const _DirectPrivateMediaPathProbe(
        _DirectPrivateMediaPathProbeOutcome.refused,
      );
    }

    if (attachment.downloadStatus == kMediaDownloadStatusDone) {
      final expectedRelative =
          MediaFilePathConvention.relativePathForAttachment(
            contactPeerId: parent.contactPeerId,
            blobId: attachment.id,
            mime: attachment.mime,
          );
      final root = p.normalize(await mediaFileManager.trustedMediaRootPath());
      final expectedAbsolute = p.normalize(
        p.join(root, parent.contactPeerId, p.posix.basename(expectedRelative)),
      );
      final normalizedStored = p.normalize(storedPath.replaceAll('\\', '/'));
      if (normalizedStored != p.normalize(expectedRelative) &&
          normalizedStored != expectedAbsolute) {
        return const _DirectPrivateMediaPathProbe(
          _DirectPrivateMediaPathProbeOutcome.refused,
        );
      }
      return _probeExpectedFile(
        targetPath: expectedAbsolute,
        authorityRoot: root,
        expectedSize: attachment.size,
      );
    }

    if (attachment.downloadStatus == kMediaDownloadStatusUploadPending &&
        !parent.isIncoming &&
        _isOutgoingOneMoreLookMode(parent.privateMediaMode)) {
      final expectedRelative =
          MediaFilePathConvention.relativePathForPendingUpload(
            messageId: parent.id,
            attachmentId: attachment.id,
            mime: attachment.mime,
          );
      if (storedPath != expectedRelative) {
        return const _DirectPrivateMediaPathProbe(
          _DirectPrivateMediaPathProbeOutcome.refused,
        );
      }
      final root = p.normalize(
        await mediaFileManager.trustedPendingUploadRootPath(),
      );
      final expectedAbsolute = p.normalize(
        p.join(root, parent.id, p.posix.basename(expectedRelative)),
      );
      return _probeExpectedFile(
        targetPath: expectedAbsolute,
        authorityRoot: root,
        expectedSize: attachment.size,
        missingLeafIsSenderLocalBytesMissing: true,
      );
    }

    return const _DirectPrivateMediaPathProbe(
      _DirectPrivateMediaPathProbeOutcome.refused,
    );
  }

  Future<_DirectPrivateMediaPathProbe> _probeExpectedFile({
    required String targetPath,
    required String authorityRoot,
    required int expectedSize,
    bool missingLeafIsSenderLocalBytesMissing = false,
  }) async {
    try {
      final target = p.normalize(targetPath);
      final root = p.normalize(authorityRoot);
      if (!p.isAbsolute(target) ||
          !p.isAbsolute(root) ||
          !p.isWithin(root, target)) {
        return const _DirectPrivateMediaPathProbe(
          _DirectPrivateMediaPathProbeOutcome.refused,
        );
      }
      if (await FileSystemEntity.type(root, followLinks: false) !=
          FileSystemEntityType.directory) {
        return const _DirectPrivateMediaPathProbe(
          _DirectPrivateMediaPathProbeOutcome.refused,
        );
      }
      final parts = p.split(p.relative(target, from: root));
      if (parts.isEmpty) {
        return const _DirectPrivateMediaPathProbe(
          _DirectPrivateMediaPathProbeOutcome.refused,
        );
      }
      var current = root;
      for (var index = 0; index < parts.length - 1; index += 1) {
        current = p.join(current, parts[index]);
        if (await FileSystemEntity.type(current, followLinks: false) !=
            FileSystemEntityType.directory) {
          return const _DirectPrivateMediaPathProbe(
            _DirectPrivateMediaPathProbeOutcome.refused,
          );
        }
      }
      final leafType = await FileSystemEntity.type(target, followLinks: false);
      if (leafType == FileSystemEntityType.notFound) {
        return _DirectPrivateMediaPathProbe(
          missingLeafIsSenderLocalBytesMissing
              ? _DirectPrivateMediaPathProbeOutcome.senderLocalBytesMissing
              : _DirectPrivateMediaPathProbeOutcome.refused,
        );
      }
      if (leafType != FileSystemEntityType.file ||
          !await DirectPrivateMediaPathGuard.authorizeTarget(
            targetPath: target,
            authorityRoot: root,
            requireExistingFile: true,
          ) ||
          await File(target).length() != expectedSize) {
        return const _DirectPrivateMediaPathProbe(
          _DirectPrivateMediaPathProbeOutcome.refused,
        );
      }
      return _DirectPrivateMediaPathProbe(
        _DirectPrivateMediaPathProbeOutcome.authorized,
        target,
      );
    } catch (_) {
      return const _DirectPrivateMediaPathProbe(
        _DirectPrivateMediaPathProbeOutcome.refused,
      );
    }
  }

  bool _isOutgoingOneMoreLookMode(PrivateMediaMode mode) =>
      mode == PrivateMediaMode.protected || mode == PrivateMediaMode.viewOnce;

  @override
  Future<bool> claimOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) => _exactLeaseRepository.claimExactPrivateMediaOpening(
    identity.messageId,
    isIncoming: identity.direction == PrivateMediaDirection.incoming,
    mode: identity.mode,
    attachmentId: identity.attachmentId,
    storedLocalPath: identity.storedLocalPath,
    nowMs: nowMs,
  );

  @override
  Future<bool> markViewing(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) => _exactLeaseRepository.markExactPrivateMediaViewing(
    identity.messageId,
    isIncoming: identity.direction == PrivateMediaDirection.incoming,
    mode: identity.mode,
    attachmentId: identity.attachmentId,
    storedLocalPath: identity.storedLocalPath,
    nowMs: nowMs,
  );

  @override
  Future<bool> rollbackOpening(
    PrivateMediaOpeningLeaseIdentity identity,
  ) async {
    if (identity.direction == PrivateMediaDirection.outgoing) {
      final repository = mediaAttachmentRepository;
      if (repository is! OutgoingDirectPrivateMutationRepository) {
        return false;
      }
      final mutationRepository =
          repository as OutgoingDirectPrivateMutationRepository;
      final combined = await mutationRepository
          .outgoingDirectPrivateMutationCoordinator
          .rollbackOpeningWithDeferredCompletion(
            messageId: identity.messageId,
            attachmentId: identity.attachmentId,
            expectedPendingLocalPath: identity.storedLocalPath,
            mode: identity.mode.wireValue,
            authorizeCanonicalFile: (fingerprint) async {
              final parent = await messageRepository
                  .loadPrivateMediaLifecycleMessage(identity.messageId);
              if (parent == null ||
                  parent.id != identity.messageId ||
                  parent.isIncoming ||
                  parent.contactPeerId.isEmpty ||
                  fingerprint.messageId != identity.messageId ||
                  fingerprint.attachmentId != identity.attachmentId ||
                  fingerprint.expectedPendingLocalPath !=
                      identity.storedLocalPath) {
                return false;
              }
              final expectedRelative =
                  MediaFilePathConvention.relativePathForAttachment(
                    contactPeerId: parent.contactPeerId,
                    blobId: identity.attachmentId,
                    mime: fingerprint.mime,
                  );
              if (fingerprint.canonicalLocalPath != expectedRelative) {
                return false;
              }
              final root = p.normalize(
                await mediaFileManager.trustedMediaRootPath(),
              );
              final target = p.normalize(
                p.join(
                  root,
                  parent.contactPeerId,
                  p.posix.basename(expectedRelative),
                ),
              );
              final probe = await _probeExpectedFile(
                targetPath: target,
                authorityRoot: root,
                expectedSize: fingerprint.size,
              );
              return probe.outcome ==
                  _DirectPrivateMediaPathProbeOutcome.authorized;
            },
          );
      if (combined != null) {
        if (combined) {
          try {
            // If transfer custody already released, settlement is the last
            // owner capable of removing the now-redundant pending source. If
            // a transfer is still active this exact cleanup refuses, and the
            // transfer's finally path performs the symmetric recheck.
            await cleanupCommittedPendingSource(
              messageId: identity.messageId,
              attachmentId: identity.attachmentId,
              expectedPendingLocalPath: identity.storedLocalPath,
            );
          } catch (_) {
            // The canonical row remains safe and a later exact lifecycle
            // cleanup can reclaim this redundant source.
          }
        }
        return combined;
      }
    }
    return _exactLeaseRepository.rollbackExactPrivateMediaOpening(
      identity.messageId,
      isIncoming: identity.direction == PrivateMediaDirection.incoming,
      mode: identity.mode,
      attachmentId: identity.attachmentId,
      storedLocalPath: identity.storedLocalPath,
    );
  }

  @override
  Future<bool> quarantineIndeterminateAvailable(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) {
    final repository = messageRepository;
    if (repository is! DirectPrivateMediaIndeterminateQuarantineRepository) {
      return Future<bool>.value(false);
    }
    final quarantineRepository =
        repository as DirectPrivateMediaIndeterminateQuarantineRepository;
    return quarantineRepository.quarantineIndeterminatePrivateMediaAvailable(
      identity.messageId,
      isIncoming: identity.direction == PrivateMediaDirection.incoming,
      mode: identity.mode,
      attachmentId: identity.attachmentId,
      storedLocalPath: identity.storedLocalPath,
      nowMs: nowMs,
    );
  }

  @override
  Future<bool> consume(String messageId, {required int nowMs}) =>
      messageRepository.consumePrivateMedia(messageId, nowMs: nowMs);

  @override
  Future<bool> consumeOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) => _exactLeaseRepository.consumeExactPrivateMedia(
    identity.messageId,
    isIncoming: identity.direction == PrivateMediaDirection.incoming,
    mode: identity.mode,
    attachmentId: identity.attachmentId,
    storedLocalPath: identity.storedLocalPath,
    nowMs: nowMs,
  );

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
      targets.add((await _buildTarget(message)).target);
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
      targets.add((await _buildTarget(message)).target);
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
    // 354: a strict protected/View-Once generation whose ciphertext is still
    // live under v111 keeps its complete projection — attachment row, secure
    // key, plaintext and ciphertext artifact — even when hide/delete/consume
    // won. The existing global blob drain terminalizes that independent
    // authority, and a later private cleanup pass then removes these assets.
    // This is deliberately retention-only: it never invokes the message-wide
    // transition from inside this per-attachment lock.
    if (await _mustRetainLivePrivateBlobCustody(parent, attachments)) {
      return;
    }
    if (await _mustRetainUnhandedOffOutgoingCustody(parent, attachments)) {
      final mutationRepository = mediaAttachmentRepository;
      if (mutationRepository is OutgoingDirectPrivateMutationRepository) {
        final coordinator =
            (mutationRepository as OutgoingDirectPrivateMutationRepository)
                .outgoingDirectPrivateMutationCoordinator;
        for (final attachment in attachments) {
          await coordinator.terminalizeDeferredCompletionForCustody(
            messageId: parent.id,
            attachmentId: attachment.id,
          );
        }
      }
      return;
    }
    final mutationRepository = mediaAttachmentRepository;
    if (mutationRepository is OutgoingDirectPrivateMutationRepository) {
      final coordinator =
          (mutationRepository as OutgoingDirectPrivateMutationRepository)
              .outgoingDirectPrivateMutationCoordinator;
      for (final attachment in current.attachments) {
        await coordinator.discardCompletion(
          messageId: parent.id,
          attachmentId: attachment.id,
        );
      }
    }
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

  /// Whether one outgoing protected/View-Once parent still owns a live
  /// `outgoing_prepared`/`outgoing_stored` v111 generation.
  ///
  /// v111 rows have no foreign key and are policy-neutral, so this obligation
  /// legitimately outlives a terminal private parent. Removing the attachment,
  /// its secure key, or its plaintext first would leave an unreopenable live
  /// generation.
  Future<bool> _mustRetainLivePrivateBlobCustody(
    ConversationMessage parent,
    List<DirectPrivateMediaCleanupAttachment> attachments,
  ) async {
    if (parent.isIncoming ||
        parent.privateMediaPolicy.version != 1 ||
        !_isOutgoingOneMoreLookMode(parent.privateMediaMode) ||
        attachments.isEmpty) {
      return false;
    }
    final repository = mediaAttachmentRepository;
    if (repository is! DirectMediaBlobCustodyRepository ||
        !(repository as DirectMediaBlobCustodyRepository)
            .supportsDirectMediaBlobCustody) {
      return false;
    }
    List<DirectMediaBlobCustodyRow> rows;
    try {
      rows = await (repository as DirectMediaBlobCustodyRepository)
          .loadDirectMediaBlobCustodyForMessage(parent.id);
    } on Object {
      // Authority is unresolved. Retaining a bounded projection is always
      // safer than destroying the only resumable bytes for a live generation.
      return true;
    }
    final attachmentIds = attachments
        .map((attachment) => attachment.id)
        .toSet();
    return rows.any(
      (row) =>
          row.direction == DirectMediaBlobCustodyDirection.outgoing &&
          (row.state == DirectMediaBlobCustodyState.outgoingPrepared ||
              row.state == DirectMediaBlobCustodyState.outgoingStored) &&
          row.messageId == parent.id &&
          attachmentIds.contains(row.attachmentId),
    );
  }

  Future<bool> _mustRetainUnhandedOffOutgoingCustody(
    ConversationMessage parent,
    List<DirectPrivateMediaCleanupAttachment> attachments,
  ) async {
    if (parent.isIncoming ||
        parent.hiddenAt != null ||
        parent.deletedAt != null ||
        parent.privateMediaPolicy.version != 1 ||
        !_isOutgoingOneMoreLookMode(parent.privateMediaMode) ||
        parent.privateMediaState != PrivateMediaLifecycleState.consumed ||
        parent.privateMediaTerminalAtMs == null ||
        (parent.status != 'sending' && parent.status != 'failed') ||
        (parent.wireEnvelope != null && parent.wireEnvelope!.isNotEmpty) ||
        attachments.length != 1) {
      return false;
    }

    final pendingRoot = p.normalize(
      await mediaFileManager.trustedPendingUploadRootPath(),
    );
    if (!p.isAbsolute(pendingRoot) ||
        await FileSystemEntity.type(pendingRoot, followLinks: false) !=
            FileSystemEntityType.directory) {
      return false;
    }
    final attachment = attachments.single;
    if (attachment.messageId != parent.id ||
        attachment.size <= 0 ||
        !DirectPrivateMediaPathGuard.identifiersAreSafe(
          contactPeerId: parent.contactPeerId,
          messageId: parent.id,
          attachmentId: attachment.id,
        )) {
      return false;
    }

    final expectedPending =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: parent.id,
          attachmentId: attachment.id,
          mime: attachment.mime,
        );
    final pendingAbsolute = p.normalize(
      p.join(pendingRoot, parent.id, p.posix.basename(expectedPending)),
    );
    final pendingProbe = await _probeExpectedFile(
      targetPath: pendingAbsolute,
      authorityRoot: pendingRoot,
      expectedSize: attachment.size,
    );
    if (pendingProbe.outcome !=
        _DirectPrivateMediaPathProbeOutcome.authorized) {
      return false;
    }

    // A completion deferred by an opening/viewing lease remains the exact
    // pending outbox row. Restart retries that source and receives the
    // coordinator's transport-only terminal authority.
    if (attachment.downloadStatus == kMediaDownloadStatusUploadPending) {
      return attachment.localPath == expectedPending;
    }

    // The opposite serialization order can durably commit the full
    // canonical completion while the parent is still available, then the
    // sender consumes it before the envelope handoff. That committed row is
    // trustworthy transport custody, not canonical-file inference. Retain it
    // (and the still-owned pending source) so the failed-message lane can
    // rebuild the envelope without rotating media keys after a crash.
    if (attachment.downloadStatus != kMediaDownloadStatusDone) return false;
    final hydrated = await mediaAttachmentRepository.getAttachmentsForMessage(
      parent.id,
      owner: MediaOwnerLane.direct,
    );
    final exact = hydrated.where(
      (candidate) =>
          candidate.id == attachment.id &&
          candidate.messageId == parent.id &&
          candidate.ownerLane == MediaOwnerLane.direct,
    );
    if (exact.length != 1) return false;
    final committed = exact.single;
    if (committed.downloadStatus != kMediaDownloadStatusDone ||
        committed.mime != attachment.mime ||
        committed.size != attachment.size ||
        committed.contentHash == null ||
        committed.contentHash!.isEmpty ||
        !committed.hasEncryptionKeyMaterial ||
        committed.encryptionScheme !=
            kMediaAttachmentEncryptionSchemeBlobAesGcmV1) {
      return false;
    }
    final expectedCanonical = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: parent.contactPeerId,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    if (attachment.localPath != expectedCanonical ||
        committed.localPath != expectedCanonical) {
      return false;
    }
    final canonicalRoot = p.normalize(
      await mediaFileManager.trustedMediaRootPath(),
    );
    final canonicalAbsolute = p.normalize(
      p.join(
        canonicalRoot,
        parent.contactPeerId,
        p.posix.basename(expectedCanonical),
      ),
    );
    final canonicalProbe = await _probeExpectedFile(
      targetPath: canonicalAbsolute,
      authorityRoot: canonicalRoot,
      expectedSize: attachment.size,
    );
    return canonicalProbe.outcome ==
        _DirectPrivateMediaPathProbeOutcome.authorized;
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
    // 301: the receiver-side inline-thumbnail sibling is an app-owned derived
    // artifact of this exact attachment — it dies with the media bytes on
    // every caller of this wipe (terminal cleanup, delete-for-me, interrupted
    // -download recovery). The sender never writes one.
    final thumbnailPath = await mediaFileManager.resolveStoredPath(
      MediaFilePathConvention.relativeThumbnailPathForAttachment(
        contactPeerId: contactPeerId,
        blobId: attachment.id,
      ),
    );
    final canonicalRoot = p.dirname(p.dirname(canonicalPath));
    final pendingRoot = p.dirname(p.dirname(pendingPath));

    final expanded = <({String path, String root})>[
      (path: thumbnailPath, root: canonicalRoot),
    ];
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
