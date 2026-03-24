import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

const _uuid = Uuid();

typedef UploadMediaFn =
    Future<MediaAttachment?> Function({
      required Bridge bridge,
      required String localFilePath,
      required String mime,
      required String recipientPeerId,
      MediaFileManager? mediaFileManager,
      int? width,
      int? height,
      int? durationMs,
      List<double>? waveform,
      List<String>? allowedPeers,
      String? blobId,
    });

/// Uploads a local file to the relay and returns a MediaAttachment on success.
///
/// Called BEFORE sendChatMessage — the send use case receives
/// already-uploaded attachments.
///
/// When [mediaFileManager] is provided, copies the file to the persistent
/// media directory so it survives app restarts.
Future<MediaAttachment?> uploadMedia({
  required Bridge bridge,
  required String localFilePath,
  required String mime,
  required String recipientPeerId,
  MediaFileManager? mediaFileManager,
  int? width,
  int? height,
  int? durationMs,
  List<double>? waveform,
  List<String>? allowedPeers,
  String? blobId,
}) async {
  final effectiveBlobId = blobId ?? _uuid.v4();

  emitFlowEvent(
    layer: 'FL',
    event: 'MEDIA_UPLOAD_START',
    details: {
      'blobId': effectiveBlobId.substring(0, 8),
      'mime': mime,
      'recipientPeerId': recipientPeerId.length > 10
          ? recipientPeerId.substring(0, 10)
          : recipientPeerId,
    },
  );

  try {
    final file = File(localFilePath);
    final fileSize = await file.length();

    final result = await callP2PMediaUpload(
      bridge,
      id: effectiveBlobId,
      toPeerId: recipientPeerId,
      mime: mime,
      filePath: localFilePath,
      allowedPeers: allowedPeers,
    );

    if (result['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_UPLOAD_FAILED',
        details: {
          'blobId': effectiveBlobId.substring(0, 8),
          'error': result['errorMessage'],
        },
      );
      return null;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final mediaType = MediaAttachment.mediaTypeFromMime(mime);

    // Copy to persistent media directory so the file survives app restarts.
    // Store the relative path in the attachment (goes to DB) so it survives
    // iOS container UUID changes across app launches.
    String storedPath = localFilePath;
    if (mediaFileManager != null) {
      final absolutePath = await mediaFileManager.localPathForAttachment(
        contactPeerId: recipientPeerId,
        blobId: effectiveBlobId,
        mime: mime,
      );
      await File(localFilePath).copy(absolutePath);
      storedPath = mediaFileManager.relativePathForAttachment(
        contactPeerId: recipientPeerId,
        blobId: effectiveBlobId,
        mime: mime,
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_UPLOAD_SUCCESS',
      details: {'blobId': effectiveBlobId.substring(0, 8), 'size': fileSize},
    );

    return MediaAttachment(
      id: effectiveBlobId,
      messageId: '', // set by caller after message ID is known
      mime: mime,
      size: fileSize,
      mediaType: mediaType,
      width: width,
      height: height,
      durationMs: durationMs,
      localPath: storedPath,
      downloadStatus: 'done',
      createdAt: now,
      waveform: waveform,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_UPLOAD_ERROR',
      details: {'blobId': effectiveBlobId.substring(0, 8), 'error': e.toString()},
    );
    return null;
  }
}
