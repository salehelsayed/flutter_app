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
Future<MediaAttachment?> downloadMedia({
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required MediaAttachment attachment,
  required String contactPeerId,
}) async {
  final idPrefix =
      attachment.id.length > 8 ? attachment.id.substring(0, 8) : attachment.id;

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
        attachment.id, 'downloading');

    // 3. Download from relay
    final result = await callP2PMediaDownload(
      bridge,
      id: attachment.id,
      outputPath: absolutePath,
    );

    if (result['ok'] != true) {
      await mediaAttachmentRepo.updateDownloadStatus(
          attachment.id, 'failed');

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_DOWNLOAD_FAILED',
        details: {'blobId': idPrefix, 'error': result['errorMessage']},
      );
      return null;
    }

    // 4. Store relative path in DB (survives iOS container UUID changes)
    final relativePath = mediaFileManager.relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    await mediaAttachmentRepo.updateLocalPath(attachment.id, relativePath);

    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_DOWNLOAD_SUCCESS',
      details: {'blobId': idPrefix},
    );

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
          attachment.id, 'failed');
    } catch (_) {}

    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_DOWNLOAD_ERROR',
      details: {'blobId': idPrefix, 'error': e.toString()},
    );
    return null;
  }
}
