import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// Downloads a media blob from the relay and saves it locally.
///
/// Called lazily when the UI needs to display a media item.
final Map<String, Future<MediaAttachment?>> _inFlightMediaDownloads =
    <String, Future<MediaAttachment?>>{};

Future<MediaAttachment?> downloadMedia({
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required MediaAttachment attachment,
  required String contactPeerId,
  bool enforceGroupMediaPolicy = false,
}) async {
  final inFlightKey = '$contactPeerId|${attachment.id}|${attachment.mime}';
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

        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_DOWNLOAD_START',
          details: {'blobId': idPrefix, 'mime': attachment.mime},
        );

        Future<void> deleteIfExists(File file) async {
          try {
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
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
            );
          } catch (_) {}
          for (final file in files) {
            await deleteIfExists(file);
          }

          emitFlowEvent(layer: 'FL', event: event, details: details);
          emitDownloadTiming(
            outcome: 'failed',
            details: {'error': details['reason'] ?? details['error']},
          );
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
            final sizeValidation = GroupMediaSizePolicy.validateAttachments([
              attachment,
            ]);
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

          // 1. Resolve absolute path for file I/O
          final absolutePath = await mediaFileManager.localPathForAttachment(
            contactPeerId: contactPeerId,
            blobId: attachment.id,
            mime: attachment.mime,
          );
          final downloadPath = enforceGroupMediaPolicy
              ? '$absolutePath.enc'
              : absolutePath;

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
          );

          if (result['ok'] != true) {
            await mediaAttachmentRepo.updateDownloadStatus(
              attachment.id,
              kMediaDownloadStatusFailed,
            );

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

            await mediaAttachmentRepo.updateDownloadStatus(
              attachment.id,
              kMediaDownloadStatusFailed,
            );
            if (fileExists) {
              await downloadedFile.delete();
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
              if (await finalFile.exists()) {
                await finalFile.delete();
              }
              await decryptedFile.rename(absolutePath);
            }
            if (await downloadedFile.exists()) {
              await downloadedFile.delete();
            }

            final plaintextFile = File(absolutePath);
            final plaintextExists = await plaintextFile.exists();
            final plaintextLength = plaintextExists
                ? await plaintextFile.length()
                : 0;
            final plaintextSizeValidation = GroupMediaSizePolicy.validateSize(
              sizeBytes: plaintextLength,
              mime: attachment.mime,
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

          // 4. Store relative path in DB (survives iOS container UUID changes)
          final relativePath = mediaFileManager.relativePathForAttachment(
            contactPeerId: contactPeerId,
            blobId: attachment.id,
            mime: attachment.mime,
          );
          await mediaAttachmentRepo.updateLocalPath(
            attachment.id,
            relativePath,
          );

          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_DOWNLOAD_SUCCESS',
            details: {'blobId': idPrefix},
          );
          emitDownloadTiming(outcome: 'success');

          // Return absolute path for immediate UI display
          return attachment.copyWith(
            localPath: absolutePath,
            downloadStatus: kMediaDownloadStatusDone,
          );
        } catch (e) {
          // Clean up partial file
          try {
            final localPath = await mediaFileManager.localPathForAttachment(
              contactPeerId: contactPeerId,
              blobId: attachment.id,
              mime: attachment.mime,
            );
            for (final path in [localPath, '$localPath.enc']) {
              final file = File(path);
              if (await file.exists()) {
                await file.delete();
              }
            }
          } catch (_) {}

          try {
            await mediaAttachmentRepo.updateDownloadStatus(
              attachment.id,
              kMediaDownloadStatusFailed,
            );
          } catch (_) {}

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
