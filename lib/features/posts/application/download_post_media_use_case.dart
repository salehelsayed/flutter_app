import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/transient_transport_error.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

final _activePostDownloads =
    Expando<Map<String, Future<PostMediaAttachmentModel>>>();

/// Downloads (and when keyed, decrypts) a posts media blob to its final path.
///
/// Custody discriminator (doc 113 Section 4) routes on KEY-MATERIAL PRESENCE,
/// never the `isEncrypted` bool alone:
/// 1. no key/nonce + `isEncrypted=false` → legacy plaintext path (permanent
///    compat surface for old senders);
/// 2. no key/nonce + `isEncrypted=true` → fail closed (`failed`) — never the
///    old ciphertext-as-`done` silent corruption;
/// 3. key+nonce + scheme ∈ {null, blob_aes_256_gcm_v1} → download `.enc`,
///    verify contentHash against the CIPHERTEXT when present (MIG-012),
///    decrypt, rename to final;
/// 4. key+nonce + unknown scheme → fail closed without decrypting.
///
/// KC-P4/G8: never issues `media:delete` — posts blobs are shared by all
/// recipients and stay TTL-bound on the relay.
Future<PostMediaAttachmentModel> downloadPostMedia({
  required Bridge bridge,
  required PostRepository postRepo,
  required MediaFileManager mediaFileManager,
  required PostMediaAttachmentModel attachment,
}) {
  final active = _activePostDownloads[postRepo] ??= {};
  return active.putIfAbsent(attachment.mediaId, () async {
    try {
      return await _downloadPostMedia(
        bridge: bridge,
        postRepo: postRepo,
        mediaFileManager: mediaFileManager,
        attachment: attachment,
      );
    } finally {
      active.remove(attachment.mediaId);
    }
  });
}

Future<PostMediaAttachmentModel> _downloadPostMedia({
  required Bridge bridge,
  required PostRepository postRepo,
  required MediaFileManager mediaFileManager,
  required PostMediaAttachmentModel attachment,
}) async {
  final absolutePath = await mediaFileManager.localPathForPostAttachment(
    postId: attachment.postId,
    blobId: attachment.blobId,
    mime: attachment.mime,
  );
  await postRepo.updatePostMediaDownloadStatus(
    attachment.mediaId,
    'downloading',
  );

  final hasKeyMaterial =
      attachment.encryptionKeyBase64 != null &&
      attachment.encryptionNonce != null;
  final downloadPath = hasKeyMaterial ? '$absolutePath.enc' : absolutePath;
  var transportInterrupted = false;

  try {
    if (attachment.isEncrypted && !hasKeyMaterial) {
      throw StateError(
        'Post media ${attachment.mediaId} is flagged encrypted but carries '
        'no key material — failing closed instead of staging ciphertext.',
      );
    }
    if (hasKeyMaterial &&
        attachment.encryptionScheme != null &&
        attachment.encryptionScheme !=
            kMediaAttachmentEncryptionSchemeBlobAesGcmV1) {
      throw StateError(
        'Post media ${attachment.mediaId} uses unknown encryption scheme '
        '${attachment.encryptionScheme} — failing closed without decrypt.',
      );
    }

    late final Map<String, dynamic> result;
    try {
      result = await callP2PMediaDownload(
        bridge,
        id: attachment.blobId,
        outputPath: downloadPath,
      );
    } catch (error) {
      transportInterrupted = TransientTransportError.matches(error);
      rethrow;
    }
    if (result['ok'] != true) {
      transportInterrupted = TransientTransportError.matches(
        result['errorMessage'],
        code: result['errorCode'],
      );
      throw StateError(
        'Post media download failed for ${attachment.mediaId}: ${result['errorMessage']}',
      );
    }

    if (hasKeyMaterial) {
      // MIG-012: the hash is ALWAYS of the encrypted blob, verified against
      // the downloaded ciphertext BEFORE decrypt — never decrypted bytes.
      final expectedHash = attachment.contentHash;
      if (expectedHash != null) {
        final actualHash = await GroupMediaIntegrityPolicy.computeFileSha256Hex(
          downloadPath,
        );
        if (actualHash != expectedHash) {
          throw StateError(
            'Post media ${attachment.mediaId} ciphertext hash mismatch '
            '(expected $expectedHash, got $actualHash).',
          );
        }
      }

      final decryptedPath = await callBlobDecrypt(
        bridge,
        filePath: downloadPath,
        keyBase64: attachment.encryptionKeyBase64!,
        nonce: attachment.encryptionNonce!,
      );
      // Move decrypted file to final path.
      final decryptedFile = File(decryptedPath);
      if (decryptedFile.existsSync()) {
        decryptedFile.renameSync(absolutePath);
      }
      // Clean up ciphertext temp file.
      try {
        final ctFile = File(downloadPath);
        if (ctFile.existsSync()) {
          ctFile.deleteSync();
        }
      } catch (_) {}
    }

    final relativePath = mediaFileManager.relativePathForPostAttachment(
      postId: attachment.postId,
      blobId: attachment.blobId,
      mime: attachment.mime,
    );
    await postRepo.updatePostMediaLocalPath(attachment.mediaId, relativePath);
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_MEDIA_DOWNLOAD_SUCCESS',
      details: {'postId': attachment.postId, 'mediaId': attachment.mediaId},
    );
    return attachment.copyWith(localPath: relativePath, downloadStatus: 'done');
  } catch (e) {
    // Remove every staged artifact; NEVER the relay blob (KC-P4 — the first
    // downloader must not starve recipients 2..N).
    for (final stagedPath in <String>{
      downloadPath,
      '$downloadPath.dec',
      absolutePath,
    }) {
      try {
        final stagedFile = File(stagedPath);
        if (stagedFile.existsSync()) {
          stagedFile.deleteSync();
        }
      } catch (_) {}
    }
    final status = transportInterrupted
        ? kMediaDownloadStatusRetryWaiting
        : kMediaDownloadStatusFailed;
    await postRepo.updatePostMediaDownloadStatus(attachment.mediaId, status);
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_MEDIA_DOWNLOAD_ERROR',
      details: {
        'postId': attachment.postId,
        'mediaId': attachment.mediaId,
        'error': e.toString(),
      },
    );
    if (transportInterrupted) {
      return attachment.copyWith(downloadStatus: status);
    }
    rethrow;
  }
}
