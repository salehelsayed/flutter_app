import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// Downloads a media blob from the relay and saves it locally.
///
/// Called lazily when the UI needs to display a media item.
final Map<_MediaDownloadInFlightKey, Future<MediaAttachment?>>
_inFlightMediaDownloads =
    <_MediaDownloadInFlightKey, Future<MediaAttachment?>>{};

class _MediaDownloadInFlightKey {
  const _MediaDownloadInFlightKey({
    required this.bridge,
    required this.mediaAttachmentRepo,
    required this.mediaFileManager,
    required this.contactPeerId,
    required this.attachmentId,
    required this.mime,
    required this.enforceGroupMediaPolicy,
    required this.encryptionDiscriminator,
  });

  final Bridge bridge;
  final MediaAttachmentRepository mediaAttachmentRepo;
  final MediaFileManager mediaFileManager;
  final String contactPeerId;
  final String attachmentId;
  final String mime;
  final bool enforceGroupMediaPolicy;

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
    encryptionDiscriminator,
  );
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
}) async {
  final candidates = <MediaAttachment>[attachment];
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
}) async {
  final candidates = await _localMediaAttachmentCandidates(
    mediaAttachmentRepo: mediaAttachmentRepo,
    attachment: attachment,
    owner: owner,
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

Future<MediaAttachment?> downloadMedia({
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required MediaAttachment attachment,
  required String contactPeerId,
  required MediaOwnerLane owner,
  bool enforceGroupMediaPolicy = false,
  Duration? transferStallTimeout,
  Duration? transferMaxTimeout,
}) async {
  final inFlightKey = _MediaDownloadInFlightKey(
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
    contactPeerId: contactPeerId,
    attachmentId: attachment.id,
    mime: attachment.mime,
    enforceGroupMediaPolicy: enforceGroupMediaPolicy,
    encryptionDiscriminator:
        '${attachment.encryptionKeyBase64 ?? ''}|'
        '${attachment.encryptionNonce ?? ''}|'
        '${attachment.encryptionScheme ?? ''}',
  );
  final inFlight = _inFlightMediaDownloads[inFlightKey];
  if (inFlight != null) {
    return inFlight;
  }

  late final Future<MediaAttachment?> downloadFuture;
  downloadFuture =
      (() async {
        final downloadStopwatch = Stopwatch()..start();
        final idPrefix = attachment.id.length > 8
            ? attachment.id.substring(0, 8)
            : attachment.id;
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

        // Bounded download retry budget (Finding 09 Phase 3, INV-DL-1/2/5).
        // Each transient download failure persists download_retry_count + 1:
        // the status goes through updateDownloadStatus (single-column, kept for
        // observability), and the counter through a full-row saveAttachment
        // (updateDownloadStatus cannot carry it). At/over the ceiling the row
        // flips to the terminal `download_failed` status. A successful local
        // path commit resets the counter to 0 (see dbUpdateMediaLocalPath).
        Future<String> persistTransientDownloadFailure({
          bool clearLocalPath = false,
        }) async {
          final nextCount = (attachment.downloadRetryCount ?? 0) + 1;
          final status = nextCount >= kMaxDownloadRetries
              ? kMediaDownloadStatusDownloadFailed
              : kMediaDownloadStatusFailed;
          try {
            await mediaAttachmentRepo.updateDownloadStatus(
              attachment.id,
              status,
            );
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
          );

          for (final candidate in candidates) {
            final storedPath = candidate.localPath;
            if (storedPath == null || storedPath.isEmpty) {
              continue;
            }

            late final String resolvedPath;
            try {
              resolvedPath = await mediaFileManager.resolveStoredPath(
                storedPath,
              );
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
          await persistTransientDownloadFailure(clearLocalPath: true);
          return false;
        }

        Future<void> quarantineUnsafeGroupMedia({
          required String event,
          required Map<String, dynamic> details,
          Iterable<File> files = const [],
        }) async {
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

        String? cleanupAbsolutePath;
        String? cleanupDownloadPath;
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
              final response = await callP2PMediaDelete(
                bridge,
                id: attachment.id,
              );
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
            final sizeValidation = GroupMediaSizePolicy.validateAttachments(
              [attachment],
              perMediaLimitBytes: kGroupMediaPerAttachmentLimitBytes,
            );
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
          cleanupAbsolutePath = absolutePath;
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
            } else {
              // Transient direct transport failure: bounded retry budget. The
              // staged ciphertext artifact is still preserved (KC-3) below.
              await persistTransientDownloadFailure();
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
          Future<_DirectStagedDecryptOutcome>
          decryptAndPromoteStagedDirectBlob({
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
            if (enforceGroupMediaPolicy) {
              return null;
            }
            final canonicalFile = File(absolutePath);
            if (!await canonicalFile.exists()) {
              return null;
            }
            final bytes = await canonicalFile.length();
            if (bytes <= 0 ||
                (attachment.size > 0 && bytes != attachment.size)) {
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

            await mediaAttachmentRepo.updateLocalPath(
              attachment.id,
              relativePath,
            );
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
            emitDownloadTiming(
              outcome: 'local_ready',
              details: {'source': source},
            );
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
            if (enforceGroupMediaPolicy) {
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
            await mediaAttachmentRepo.updateLocalPath(
              attachment.id,
              relativePath,
            );
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
            emitDownloadTiming(
              outcome: 'local_ready',
              details: {'source': source},
            );
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

          Future<MediaAttachment?>
          restoreEncryptedCompanionIfAvailable() async {
            if (!enforceGroupMediaPolicy) {
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
                event:
                    'MEDIA_DOWNLOAD_LOCAL_ENCRYPTED_COMPANION_DECRYPT_FAILED',
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
                event:
                    'MEDIA_DOWNLOAD_LOCAL_ENCRYPTED_COMPANION_DECRYPT_FAILED',
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
              return null;
            }

            await deleteIfExists(
              encryptedCompanion,
              caller: 'downloadMedia.restoreEncryptedCompanionIfAvailable',
              reason: 'local_encrypted_companion_cleanup_after_restore',
              details: {'source': 'local_encrypted_companion'},
            );
            await mediaAttachmentRepo.updateLocalPath(
              attachment.id,
              relativePath,
            );
            final committed = await verifyCommittedLocalPath(
              absolutePath: absolutePath,
              relativePath: relativePath,
              source: 'local_encrypted_companion',
            );
            if (!committed) {
              return null;
            }
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
          final encryptedCompanionFoundAfterRestore = enforceGroupMediaPolicy
              ? await File(downloadPath).exists()
              : false;

          final localDiagnostics = await _collectLocalMediaCandidateDiagnostics(
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            attachment: attachment,
            allowStatusRepair: !enforceGroupMediaPolicy,
            owner: owner,
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
                  attachment.localPath != null &&
                  attachment.localPath!.isNotEmpty,
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

          // 2. Mark as downloading
          await mediaAttachmentRepo.updateDownloadStatus(
            attachment.id,
            kMediaDownloadStatusDownloading,
          );

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
            final localAttachment =
                await useCompletedLocalAttachmentIfAvailable(
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
                    event:
                        'MEDIA_DOWNLOAD_INVALID_GROUP_FILE_SUPERSEDED_BY_LOCAL',
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

            final localAttachment =
                await useCompletedLocalAttachmentIfAvailable(
                  event: 'MEDIA_DOWNLOAD_INVALID_FILE_SUPERSEDED_BY_LOCAL',
                  allowStatusRepair: true,
                  details: {
                    'expectedSize': expectedSize,
                    'actualSize': fileLength,
                  },
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
                details: {
                  'expectedSize': expectedSize,
                  'actualSize': fileLength,
                },
              );
            }

            final repairedLocalAttachment =
                await useCompletedLocalAttachmentIfAvailable(
                  event: 'MEDIA_DOWNLOAD_INVALID_FILE_REPAIRED_BY_LOCAL',
                  allowStatusRepair: true,
                  details: {
                    'expectedSize': expectedSize,
                    'actualSize': fileLength,
                  },
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
                  details: {
                    'relayMime': relayMime,
                    'expectedMime': expectedMime,
                  },
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
                  caller:
                      'downloadMedia.groupIntegrityRejectionSupersededByLocal',
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
                    details: {
                      'reason': 'decrypt_failed',
                      'error': e.toString(),
                    },
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
                details: {
                  'blobId': idPrefix,
                  'reason': 'missing_decrypted_file',
                },
                files: [downloadedFile],
              );
              return null;
            }
            if (decryptedPath != absolutePath) {
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
            await deleteIfExists(
              downloadedFile,
              caller: 'downloadMedia.groupDownloadDecrypt',
              reason:
                  'group_download_encrypted_companion_cleanup_after_decrypt',
              details: {'source': 'group_media_download'},
            );

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
                },
                files: [plaintextFile],
              );
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
                },
                files: [plaintextFile],
              );
              return null;
            }
          }

          if (!enforceGroupMediaPolicy) {
            final stagedFile = File(downloadPath);
            if (attachment.hasEncryptionKeyMaterial) {
              final outcome = await decryptAndPromoteStagedDirectBlob(
                stagedFile: stagedFile,
                source: 'direct_media_download',
              );
              if (outcome != _DirectStagedDecryptOutcome.promoted) {
                return null;
              }
            } else {
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
            }
          }

          // 4. Store relative path in DB (survives iOS container UUID changes)
          await mediaAttachmentRepo.updateLocalPath(
            attachment.id,
            relativePath,
          );
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
        }
      })().whenComplete(() {
        if (identical(_inFlightMediaDownloads[inFlightKey], downloadFuture)) {
          _inFlightMediaDownloads.remove(inFlightKey);
        }
      });

  _inFlightMediaDownloads[inFlightKey] = downloadFuture;
  return downloadFuture;
}
