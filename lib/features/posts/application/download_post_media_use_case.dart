import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

Future<PostMediaAttachmentModel> downloadPostMedia({
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

  try {
    final result = await callP2PMediaDownload(
      bridge,
      id: attachment.blobId,
      outputPath: absolutePath,
    );
    if (result['ok'] != true) {
      await postRepo.updatePostMediaDownloadStatus(attachment.mediaId, 'failed');
      throw StateError(
        'Post media download failed for ${attachment.mediaId}: ${result['errorMessage']}',
      );
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
    return attachment.copyWith(
      localPath: relativePath,
      downloadStatus: 'done',
    );
  } catch (e) {
    try {
      final file = File(absolutePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    await postRepo.updatePostMediaDownloadStatus(attachment.mediaId, 'failed');
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_MEDIA_DOWNLOAD_ERROR',
      details: {
        'postId': attachment.postId,
        'mediaId': attachment.mediaId,
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
