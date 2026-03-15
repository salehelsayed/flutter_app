import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';

const _uuid = Uuid();

class PostMediaDraft {
  final String localFilePath;
  final String mime;
  final int? width;
  final int? height;
  final int? durationMs;
  final List<double>? waveform;

  const PostMediaDraft({
    required this.localFilePath,
    required this.mime,
    this.width,
    this.height,
    this.durationMs,
    this.waveform,
  });

  String get kind {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'voice';
    return 'file';
  }
}

enum AttachPostMediaResult {
  success,
  postNotFound,
  noRecipients,
  invalidSelection,
  uploadFailed,
}

typedef UploadPostMediaFn =
    Future<PostMediaAttachmentModel?> Function({
      required String postId,
      required String localFilePath,
      required String mime,
      required List<String> allowedPeers,
      MediaFileManager? mediaFileManager,
      int? width,
      int? height,
      int? durationMs,
      List<double>? waveform,
    });

Future<(AttachPostMediaResult, List<PostMediaAttachmentModel>)>
attachPostMedia({
  required String postId,
  required PostRepository postRepo,
  required SecureKeyStore secureKeyStore,
  required ImageProcessor imageProcessor,
  required List<PostMediaDraft> drafts,
  MediaFileManager? mediaFileManager,
  UploadPostMediaFn? uploadPostMediaFn,
  Bridge? bridge,
}) async {
  final post = await postRepo.getPost(postId);
  if (post == null) {
    return (
      AttachPostMediaResult.postNotFound,
      const <PostMediaAttachmentModel>[],
    );
  }
  if (drafts.isEmpty) {
    return (AttachPostMediaResult.success, const <PostMediaAttachmentModel>[]);
  }

  final mediaKind = drafts.first.kind;
  final isValidSelection = switch (mediaKind) {
    'image' => drafts.every((draft) => draft.kind == 'image'),
    'video' => drafts.length == 1 && drafts.single.kind == 'video',
    'voice' => drafts.length == 1 && drafts.single.kind == 'voice',
    _ => false,
  };
  if (!isValidSelection) {
    return (
      AttachPostMediaResult.invalidSelection,
      const <PostMediaAttachmentModel>[],
    );
  }

  final recipientDeliveries = await postRepo.getRecipientDeliveries(postId);
  if (recipientDeliveries.isEmpty) {
    return (
      AttachPostMediaResult.noRecipients,
      const <PostMediaAttachmentModel>[],
    );
  }
  final allowedPeers = <String>{
    post.authorPeerId,
    for (final delivery in recipientDeliveries) delivery.recipientPeerId,
  }.toList(growable: false);

  final resolvedUpload =
      uploadPostMediaFn ??
      (bridge == null
          ? null
          : ({
              required String postId,
              required String localFilePath,
              required String mime,
              required List<String> allowedPeers,
              MediaFileManager? mediaFileManager,
              int? width,
              int? height,
              int? durationMs,
              List<double>? waveform,
            }) {
              return uploadPostMedia(
                bridge: bridge,
                postId: postId,
                ownerPeerId: post.authorPeerId,
                localFilePath: localFilePath,
                mime: mime,
                allowedPeers: allowedPeers,
                mediaFileManager: mediaFileManager,
                width: width,
                height: height,
                durationMs: durationMs,
                waveform: waveform,
              );
            });
  if (resolvedUpload == null) {
    return (
      AttachPostMediaResult.uploadFailed,
      const <PostMediaAttachmentModel>[],
    );
  }

  final attachments = <PostMediaAttachmentModel>[];
  for (var index = 0; index < drafts.length; index++) {
    final prepared = await _prepareDraft(
      draft: drafts[index],
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
    );
    final uploaded = await resolvedUpload(
      postId: postId,
      localFilePath: prepared.localFilePath,
      mime: _draftMime(prepared, drafts[index]),
      allowedPeers: allowedPeers,
      mediaFileManager: mediaFileManager,
      width: prepared.width,
      height: prepared.height,
      durationMs: prepared.durationMs,
      waveform: prepared.waveform,
    );
    if (uploaded == null) {
      return (AttachPostMediaResult.uploadFailed, attachments);
    }
    final positioned = uploaded.copyWith(position: index, postId: postId);
    await postRepo.savePostMediaAttachment(positioned);
    attachments.add(positioned);
  }

  return (AttachPostMediaResult.success, attachments);
}

Future<PostMediaAttachmentModel?> uploadPostMedia({
  required Bridge bridge,
  required String postId,
  required String ownerPeerId,
  required String localFilePath,
  required String mime,
  required List<String> allowedPeers,
  MediaFileManager? mediaFileManager,
  int? width,
  int? height,
  int? durationMs,
  List<double>? waveform,
}) async {
  final blobId = 'blob_${_uuid.v4()}';
  final mediaId = 'media_${_uuid.v4()}';

  emitFlowEvent(
    layer: 'FL',
    event: 'POST_MEDIA_UPLOAD_START',
    details: {'postId': postId, 'blobId': blobId},
  );

  try {
    final file = File(localFilePath);
    final result = await callP2PMediaUpload(
      bridge,
      id: blobId,
      toPeerId: ownerPeerId,
      mime: mime,
      filePath: localFilePath,
      allowedPeers: allowedPeers,
    );
    if (result['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_MEDIA_UPLOAD_FAILED',
        details: {
          'postId': postId,
          'blobId': blobId,
          'error': result['errorMessage'],
        },
      );
      return null;
    }

    String? storedPath;
    if (mediaFileManager != null) {
      final absolutePath = await mediaFileManager.localPathForPostAttachment(
        postId: postId,
        blobId: blobId,
        mime: mime,
      );
      await file.copy(absolutePath);
      storedPath = mediaFileManager.relativePathForPostAttachment(
        postId: postId,
        blobId: blobId,
        mime: mime,
      );
    }

    return PostMediaAttachmentModel(
      mediaId: mediaId,
      postId: postId,
      blobId: blobId,
      kind: _kindFromMime(mime),
      mime: mime,
      sizeBytes: await file.length(),
      width: width,
      height: height,
      durationMs: durationMs,
      localPath: storedPath,
      downloadStatus: storedPath == null ? 'pending' : 'done',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      waveform: waveform,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_MEDIA_UPLOAD_ERROR',
      details: {'postId': postId, 'error': e.toString()},
    );
    return null;
  }
}

String _draftMime(_PreparedPostMediaDraft prepared, PostMediaDraft original) {
  if (original.kind == 'image') {
    return original.mime == 'image/png' ? 'image/png' : 'image/jpeg';
  }
  if (original.kind == 'video') {
    return original.mime;
  }
  return original.mime;
}

class _PreparedPostMediaDraft {
  final String localFilePath;
  final int? width;
  final int? height;
  final int? durationMs;
  final List<double>? waveform;

  const _PreparedPostMediaDraft({
    required this.localFilePath,
    this.width,
    this.height,
    this.durationMs,
    this.waveform,
  });
}

Future<_PreparedPostMediaDraft> _prepareDraft({
  required PostMediaDraft draft,
  required SecureKeyStore secureKeyStore,
  required ImageProcessor imageProcessor,
}) async {
  switch (draft.kind) {
    case 'image':
      final quality = await loadImageQualityPreference(
        secureKeyStore: secureKeyStore,
      );
      final processedPath = await imageProcessor.processImage(
        inputPath: draft.localFilePath,
        quality: quality,
      );
      return _PreparedPostMediaDraft(
        localFilePath: processedPath,
        width: draft.width,
        height: draft.height,
      );
    case 'video':
      final quality = await loadVideoQualityPreference(
        secureKeyStore: secureKeyStore,
      );
      final processed = await imageProcessor.processVideo(
        inputPath: draft.localFilePath,
        quality: quality,
      );
      return _PreparedPostMediaDraft(
        localFilePath: processed.path,
        width: processed.width ?? draft.width,
        height: processed.height ?? draft.height,
        durationMs: processed.durationMs ?? draft.durationMs,
      );
    case 'voice':
      return _PreparedPostMediaDraft(
        localFilePath: draft.localFilePath,
        durationMs: draft.durationMs,
        waveform: draft.waveform,
      );
    default:
      return _PreparedPostMediaDraft(localFilePath: draft.localFilePath);
  }
}

String _kindFromMime(String mime) {
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  if (mime.startsWith('audio/')) return 'voice';
  return 'file';
}
