import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

const _uuid = Uuid();

String _uploadMediaShortId(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;

String _uploadMediaPathKind(String? path) {
  if (path == null || path.isEmpty) {
    return 'empty';
  }
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
    return 'absolute';
  }
  return 'relative';
}

@visibleForTesting
List<Duration> debugGroupMediaUploadPostCommitProbeDelays = const [
  Duration(milliseconds: 250),
  Duration(seconds: 1),
];

void _scheduleGroupMediaUploadPostCommitProbes({
  required String absolutePath,
  required String storedPath,
  required String blobId,
  required String mime,
  required int expectedBytes,
}) {
  for (final delay in debugGroupMediaUploadPostCommitProbeDelays) {
    unawaited(
      Future<void>.delayed(delay, () async {
        try {
          final file = File(absolutePath);
          final exists = await file.exists();
          final bytes = exists ? await file.length() : 0;
          final details = <String, dynamic>{
            'blobId': _uploadMediaShortId(blobId),
            'mime': mime,
            'recipientClass': 'group',
            'storedPath': storedPath,
            'storedPathKind': _uploadMediaPathKind(storedPath),
            'absolutePathKind': _uploadMediaPathKind(absolutePath),
            'probeDelayMs': delay.inMilliseconds,
            'fileExists': exists,
            'fileBytes': bytes,
            'expectedBytes': expectedBytes,
          };
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_GROUP_UPLOAD_DURABLE_COPY_DELAYED_PROBE',
            details: details,
          );
          if (!exists || bytes <= 0 || bytes != expectedBytes) {
            emitFlowEvent(
              layer: 'FL',
              event: 'MEDIA_GROUP_UPLOAD_DURABLE_COPY_DELAYED_PROBE_MISSING',
              details: details,
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_GROUP_UPLOAD_DURABLE_COPY_DELAYED_PROBE_ERROR',
            details: {
              'blobId': _uploadMediaShortId(blobId),
              'mime': mime,
              'storedPath': storedPath,
              'probeDelayMs': delay.inMilliseconds,
              'error': e.toString(),
            },
          );
        }
      }),
    );
  }
}

class _DurableMediaCopyResult {
  const _DurableMediaCopyResult({
    required this.exists,
    required this.bytes,
    required this.tempPath,
  });

  final bool exists;
  final int bytes;
  final String tempPath;
}

Future<_DurableMediaCopyResult> _copyToOwnedMediaPath({
  required String sourcePath,
  required String targetPath,
  required String blobId,
  required String mime,
  required String recipientClass,
}) async {
  final targetFile = File(targetPath);
  await targetFile.parent.create(recursive: true);
  final tempPath = '$targetPath.tmp-${DateTime.now().microsecondsSinceEpoch}';
  final tempFile = await File(sourcePath).copy(tempPath);
  await deleteAppOwnedMediaFileIfExists(
    file: targetFile,
    caller: 'uploadMedia.copyToOwnedMediaPath',
    reason: 'replace_existing_durable_media_copy',
    details: {
      'blobId': _uploadMediaShortId(blobId),
      'mime': mime,
      'recipientClass': recipientClass,
      'sourcePathKind': _uploadMediaPathKind(sourcePath),
      'targetPathKind': _uploadMediaPathKind(targetPath),
      'tempPathKind': _uploadMediaPathKind(tempPath),
    },
  );
  await tempFile.rename(targetPath);
  final committedFile = File(targetPath);
  final exists = await committedFile.exists();
  return _DurableMediaCopyResult(
    exists: exists,
    bytes: exists ? await committedFile.length() : 0,
    tempPath: tempPath,
  );
}

/// A blob encrypted once and shared by BOTH transports (112 Phase 4:
/// "encrypt once, send the same ciphertext artifact on relay and LAN").
class EncryptedMediaArtifact {
  const EncryptedMediaArtifact({
    required this.encryptedPath,
    required this.keyBase64,
    required this.nonce,
    required this.scheme,
    required this.contentHash,
    required this.plaintextSize,
  });

  /// Path of the ciphertext temp file (plaintext + 16-byte GCM tag).
  final String encryptedPath;
  final String keyBase64;
  final String nonce;
  final String scheme;

  /// SHA-256 of the ENCRYPTED bytes (relay_blob scope).
  final String contentHash;
  final int plaintextSize;
}

/// Injectable form of [prepareEncryptedMediaArtifact] for widget tests —
/// the real implementation does file I/O that cannot complete inside the
/// testWidgets fake-async zone.
typedef PrepareEncryptedMediaArtifactFn =
    Future<EncryptedMediaArtifact> Function({
      required Bridge bridge,
      required String localFilePath,
    });

/// Runs blob keygen + encrypt + hash for [localFilePath]. The caller hands
/// the artifact to the LAN sender and/or [uploadMedia] (via
/// `preparedArtifact`); ownership of the ciphertext temp transfers to
/// [uploadMedia], which deletes it after the relay upload settles.
Future<EncryptedMediaArtifact> prepareEncryptedMediaArtifact({
  required Bridge bridge,
  required String localFilePath,
}) async {
  final plaintextSize = await File(localFilePath).length();
  final keyBase64 = await callBlobKeygen(bridge);
  final encrypted = await callBlobEncrypt(
    bridge,
    filePath: localFilePath,
    keyBase64: keyBase64,
  );
  final contentHash = await GroupMediaIntegrityPolicy.computeFileSha256Hex(
    encrypted.encryptedPath,
  );
  return EncryptedMediaArtifact(
    encryptedPath: encrypted.encryptedPath,
    keyBase64: keyBase64,
    nonce: encrypted.nonce,
    scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    contentHash: contentHash,
    plaintextSize: plaintextSize,
  );
}

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
      bool deleteSourceWhenDone,
      EncryptedMediaArtifact? preparedArtifact,
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
  // Best-effort unlink of [localFilePath] after the durable copy is
  // committed and the upload succeeded — for picker/recorder temps whose
  // plaintext would otherwise linger. Only honored when a durable copy
  // exists (otherwise the source IS the sender's render copy). NOTE:
  // secure-delete/overwrite is NOT meaningfully achievable on flash/APFS —
  // this is a plain unlink.
  bool deleteSourceWhenDone = false,
  // Phase 4 "encrypt once": when the caller already built the ciphertext
  // artifact (for the LAN leg), reuse it instead of re-encrypting — a
  // second encryption here would mint a key the LAN copy doesn't have.
  EncryptedMediaArtifact? preparedArtifact,
  // Null => derive the per-type SEND cap from the mime (the new default). An
  // explicit value (tests) overrides with a flat cap.
  int? groupMediaPerAttachmentLimitBytes,
  Duration? transferStallTimeout,
  Duration? transferMaxTimeout,
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
    }

    // 112 G1: encryption is UNCONDITIONAL — every blob (1:1 AND group)
    // leaves the device as AES-256-GCM ciphertext under a fresh random
    // per-blob key. contentHash is ALWAYS the hash of the ENCRYPTED bytes
    // (relay_blob scope — the MIG-012 lesson). A keygen/encrypt failure
    // throws into the catch below: fail closed, no plaintext fallback.
    final artifact =
        preparedArtifact ??
        await prepareEncryptedMediaArtifact(
          bridge: bridge,
          localFilePath: localFilePath,
        );
    encryptedUploadPath = artifact.encryptedPath;
    final encryptionKeyBase64 = artifact.keyBase64;
    final encryptionNonce = artifact.nonce;
    final encryptionScheme = artifact.scheme;
    final contentHash = artifact.contentHash;

    final result = await callP2PMediaUpload(
      bridge,
      id: effectiveBlobId,
      toPeerId: recipientPeerId,
      // G7a: 1:1 uploads advertise an opaque mime — the real mime travels
      // only inside the ML-KEM v2 envelope. Groups keep the real mime: the
      // group download path cross-checks the relay-returned mime
      // (relay_mime_mismatch) and would quarantine opaque uploads.
      mime: isGroupUpload ? effectiveMime : kOpaqueMediaTransportMime,
      // Structurally ciphertext-only: there is deliberately NO
      // `?? localFilePath` fallback — the upload call must be incapable of
      // receiving a plaintext path.
      filePath: artifact.encryptedPath,
      allowedPeers: allowedPeers,
      // Plaintext size by convention (ciphertext = size + 16-byte GCM tag);
      // Go stats the actual file for the relay's exact-size enforcement.
      payloadSizeBytes: fileSize,
      stallTimeout: transferStallTimeout,
      maxTimeout: transferMaxTimeout,
    );

    if (encryptedUploadPath != null) {
      await deleteAppOwnedMediaFileIfExists(
        file: File(encryptedUploadPath),
        caller: 'uploadMedia.cleanupEncryptedUpload',
        reason: 'upload_encrypted_temp_cleanup_after_upload',
        details: {
          'blobId': _uploadMediaShortId(effectiveBlobId),
          'mime': effectiveMime,
          'recipientClass': isGroupUpload ? 'group' : 'direct',
        },
        swallowErrors: true,
      );
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
    int? durableCopyBytes;
    String? durableCopyAbsolutePath;
    if (mediaFileManager != null) {
      final absolutePath = await mediaFileManager.localPathForAttachment(
        contactPeerId: recipientPeerId,
        blobId: effectiveBlobId,
        mime: effectiveMime,
      );
      final copyResult = await _copyToOwnedMediaPath(
        sourcePath: localFilePath,
        targetPath: absolutePath,
        blobId: effectiveBlobId,
        mime: effectiveMime,
        recipientClass: allowedPeers == null ? 'direct' : 'group',
      );
      durableCopyBytes = copyResult.bytes;
      storedPath = mediaFileManager.relativePathForAttachment(
        contactPeerId: recipientPeerId,
        blobId: effectiveBlobId,
        mime: effectiveMime,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_UPLOAD_DURABLE_COPY_COMMITTED',
        details: {
          'blobId': _uploadMediaShortId(effectiveBlobId),
          'mime': effectiveMime,
          'recipientClass': allowedPeers == null ? 'direct' : 'group',
          'sourcePathKind': _uploadMediaPathKind(localFilePath),
          'storedPath': storedPath,
          'storedPathKind': _uploadMediaPathKind(storedPath),
          'absolutePathKind': _uploadMediaPathKind(absolutePath),
          'tempPathKind': _uploadMediaPathKind(copyResult.tempPath),
          'fileExists': copyResult.exists,
          'fileBytes': copyResult.bytes,
          'expectedBytes': fileSize,
        },
      );
      if (isGroupUpload && copyResult.exists && copyResult.bytes > 0) {
        _scheduleGroupMediaUploadPostCommitProbes(
          absolutePath: absolutePath,
          storedPath: storedPath,
          blobId: effectiveBlobId,
          mime: effectiveMime,
          expectedBytes: fileSize!,
        );
      }
      if (!copyResult.exists ||
          copyResult.bytes <= 0 ||
          copyResult.bytes != fileSize) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_UPLOAD_DURABLE_COPY_INVALID',
          details: {
            'blobId': _uploadMediaShortId(effectiveBlobId),
            'mime': effectiveMime,
            'fileExists': copyResult.exists,
            'fileBytes': copyResult.bytes,
            'expectedBytes': fileSize,
          },
        );
        throw FileSystemException(
          'durable media copy verification failed',
          absolutePath,
        );
      }
      durableCopyAbsolutePath = absolutePath;
    }

    if (deleteSourceWhenDone &&
        durableCopyAbsolutePath != null &&
        durableCopyAbsolutePath != localFilePath) {
      await deleteAppOwnedMediaFileIfExists(
        file: File(localFilePath),
        caller: 'uploadMedia.deleteSourceWhenDone',
        reason: 'transient_source_cleanup_after_durable_copy',
        details: {
          'blobId': _uploadMediaShortId(effectiveBlobId),
          'mime': effectiveMime,
          'recipientClass': isGroupUpload ? 'group' : 'direct',
        },
        swallowErrors: true,
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
        if (durableCopyBytes != null) 'durableFileBytes': durableCopyBytes,
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
      await deleteAppOwnedMediaFileIfExists(
        file: File(encryptedUploadPath),
        caller: 'uploadMedia.cleanupEncryptedUpload',
        reason: 'upload_encrypted_temp_cleanup_after_error',
        details: {
          'blobId': _uploadMediaShortId(effectiveBlobId),
          'mime': effectiveMime,
          'recipientClass': isGroupUpload ? 'group' : 'direct',
          'error': e.toString(),
        },
        swallowErrors: true,
      );
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
