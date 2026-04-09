import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
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

        try {
          // 1. Resolve absolute path for file I/O
          final absolutePath = await mediaFileManager.localPathForAttachment(
            contactPeerId: contactPeerId,
            blobId: attachment.id,
            mime: attachment.mime,
          );

          // 2. Mark as downloading
          await mediaAttachmentRepo.updateDownloadStatus(
            attachment.id,
            'downloading',
          );

          // 3. Download from relay
          final result = await callP2PMediaDownload(
            bridge,
            id: attachment.id,
            outputPath: absolutePath,
          );

          if (result['ok'] != true) {
            await mediaAttachmentRepo.updateDownloadStatus(
              attachment.id,
              'failed',
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

          final downloadedFile = File(absolutePath);
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
            await mediaAttachmentRepo.updateDownloadStatus(
              attachment.id,
              'failed',
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
            downloadStatus: 'done',
          );
        } catch (e) {
          // Clean up partial file
          try {
            final localPath = await mediaFileManager.localPathForAttachment(
              contactPeerId: contactPeerId,
              blobId: attachment.id,
              mime: attachment.mime,
            );
            final file = File(localPath);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}

          try {
            await mediaAttachmentRepo.updateDownloadStatus(
              attachment.id,
              'failed',
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
