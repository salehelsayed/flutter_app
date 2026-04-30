import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
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
  int groupMediaPerAttachmentLimitBytes = kGroupMediaPerAttachmentLimitBytes,
}) async {
  final uploadStopwatch = Stopwatch()..start();
  final effectiveBlobId = blobId ?? _uuid.v4();
  final isGroupUpload = allowedPeers != null;
  final effectiveMime = isGroupUpload
      ? (GroupMediaMimePolicy.normalizeMime(mime) ?? mime)
      : mime;
  int? fileSize;
  void emitUploadTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_UPLOAD_TIMING',
      details: {
        'elapsedMs': uploadStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'blobId': effectiveBlobId.substring(0, 8),
        'mime': effectiveMime,
        if (fileSize != null) 'sizeBytes': fileSize,
        ...details,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'MEDIA_UPLOAD_START',
    details: {
      'blobId': effectiveBlobId.substring(0, 8),
      'mime': effectiveMime,
      'recipientPeerId': recipientPeerId.length > 10
          ? recipientPeerId.substring(0, 10)
          : recipientPeerId,
    },
  );

  String? encryptedUploadPath;
  try {
    if (isGroupUpload) {
      final validation = await GroupMediaMimePolicy.validateFile(
        path: localFilePath,
        mime: mime,
        mediaType: GroupMediaMimePolicy.mediaTypeForMime(mime),
      );
      if (!validation.isValid) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_UPLOAD_REJECTED_INVALID_GROUP_MEDIA',
          details: {
            'blobId': effectiveBlobId.substring(0, 8),
            'mime': mime,
            'reason': validation.reason,
          },
        );
        emitUploadTiming(
          outcome: 'rejected',
          details: {'reason': validation.reason},
        );
        return null;
      }
    }

    final file = File(localFilePath);
    fileSize = await file.length();
    String? contentHash;
    String? encryptionKeyBase64;
    String? encryptionNonce;
    String? encryptionScheme;
    if (isGroupUpload) {
      final sizeValidation = GroupMediaSizePolicy.validateSize(
        sizeBytes: fileSize,
        mime: effectiveMime,
        perMediaLimitBytes: groupMediaPerAttachmentLimitBytes,
      );
      if (!sizeValidation.isValid) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_UPLOAD_REJECTED_INVALID_GROUP_MEDIA',
          details: {
            'blobId': effectiveBlobId.substring(0, 8),
            'mime': effectiveMime,
            'reason': sizeValidation.reason,
          },
        );
        emitUploadTiming(
          outcome: 'rejected',
          details: {'reason': sizeValidation.reason},
        );
        return null;
      }
      encryptionKeyBase64 = await callBlobKeygen(bridge);
      final encrypted = await callBlobEncrypt(
        bridge,
        filePath: localFilePath,
        keyBase64: encryptionKeyBase64,
      );
      encryptedUploadPath = encrypted.encryptedPath;
      encryptionNonce = encrypted.nonce;
      encryptionScheme = kMediaAttachmentEncryptionSchemeBlobAesGcmV1;
      contentHash = await GroupMediaIntegrityPolicy.computeFileSha256Hex(
        encryptedUploadPath,
      );
    }

    final result = await callP2PMediaUpload(
      bridge,
      id: effectiveBlobId,
      toPeerId: recipientPeerId,
      mime: effectiveMime,
      filePath: encryptedUploadPath ?? localFilePath,
      allowedPeers: allowedPeers,
    );

    if (encryptedUploadPath != null) {
      try {
        final encryptedFile = File(encryptedUploadPath);
        if (await encryptedFile.exists()) {
          await encryptedFile.delete();
        }
      } catch (_) {}
    }

    if (result['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_UPLOAD_FAILED',
        details: {
          'blobId': effectiveBlobId.substring(0, 8),
          'error': result['errorMessage'],
        },
      );
      emitUploadTiming(
        outcome: 'failed',
        details: {'error': result['errorMessage']},
      );
      return null;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final mediaType = isGroupUpload
        ? GroupMediaMimePolicy.mediaTypeForMime(effectiveMime)!
        : MediaAttachment.mediaTypeFromMime(effectiveMime);

    // Copy to persistent media directory so the file survives app restarts.
    // Store the relative path in the attachment (goes to DB) so it survives
    // iOS container UUID changes across app launches.
    String storedPath = localFilePath;
    if (mediaFileManager != null) {
      final absolutePath = await mediaFileManager.localPathForAttachment(
        contactPeerId: recipientPeerId,
        blobId: effectiveBlobId,
        mime: effectiveMime,
      );
      await File(localFilePath).copy(absolutePath);
      storedPath = mediaFileManager.relativePathForAttachment(
        contactPeerId: recipientPeerId,
        blobId: effectiveBlobId,
        mime: effectiveMime,
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_UPLOAD_SUCCESS',
      details: {'blobId': effectiveBlobId.substring(0, 8), 'size': fileSize},
    );
    emitUploadTiming(
      outcome: 'success',
      details: {
        'storedPersistently': mediaFileManager != null,
        'recipientClass': allowedPeers == null ? 'direct' : 'group',
      },
    );

    return MediaAttachment(
      id: effectiveBlobId,
      messageId: '', // set by caller after message ID is known
      mime: effectiveMime,
      size: fileSize,
      mediaType: mediaType,
      width: width,
      height: height,
      durationMs: durationMs,
      localPath: storedPath,
      downloadStatus: 'done',
      createdAt: now,
      waveform: waveform,
      contentHash: contentHash,
      encryptionKeyBase64: encryptionKeyBase64,
      encryptionNonce: encryptionNonce,
      encryptionScheme: encryptionScheme,
    );
  } catch (e) {
    if (encryptedUploadPath != null) {
      try {
        final encryptedFile = File(encryptedUploadPath);
        if (await encryptedFile.exists()) {
          await encryptedFile.delete();
        }
      } catch (_) {}
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_UPLOAD_ERROR',
      details: {
        'blobId': effectiveBlobId.substring(0, 8),
        'error': e.toString(),
      },
    );
    emitUploadTiming(outcome: 'error');
    return null;
  }
}
