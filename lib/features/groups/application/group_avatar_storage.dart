import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

typedef DownloadGroupAvatarFn =
    Future<String?> Function({
      required Bridge bridge,
      required String groupId,
      required String blobId,
    });

String groupAvatarRelativePath(String groupId) {
  return p.join('media', 'group_avatars', '$groupId.jpg');
}

Future<String> groupAvatarCanonicalPath(String groupId) async {
  final appDir = await getApplicationDocumentsDirectory();
  return p.join(appDir.path, groupAvatarRelativePath(groupId));
}

Future<String> normalizeAndCommitGroupAvatar({
  required String groupId,
  required String inputPath,
  AvatarNormalizationHelper? avatarNormalizer,
}) async {
  final canonicalPath = await groupAvatarCanonicalPath(groupId);
  final normalizer = avatarNormalizer ?? AvatarNormalizationHelper();
  final committedPath = await normalizer.normalizeAvatar(
    inputPath: inputPath,
    canonicalPath: canonicalPath,
  );
  unawaited(FileImage(File(committedPath)).evict());
  return committedPath;
}

Future<String> commitPreparedGroupAvatar({
  required String groupId,
  required String sourcePath,
  AvatarNormalizationHelper? avatarNormalizer,
}) async {
  final canonicalPath = await groupAvatarCanonicalPath(groupId);
  final normalizer = avatarNormalizer ?? AvatarNormalizationHelper();
  final committedPath = await normalizer.commitAvatar(
    sourcePath: sourcePath,
    canonicalPath: canonicalPath,
  );
  unawaited(FileImage(File(committedPath)).evict());
  return committedPath;
}

Future<String?> downloadGroupAvatar({
  required Bridge bridge,
  required String groupId,
  required String blobId,
  AvatarNormalizationHelper? avatarNormalizer,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_AVATAR_DOWNLOAD_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'blobId': blobId.length > 8 ? blobId.substring(0, 8) : blobId,
    },
  );

  try {
    final canonicalPath = await groupAvatarCanonicalPath(groupId);
    final tempPath = '$canonicalPath.download.jpg';
    final tempFile = File(tempPath);
    await tempFile.parent.create(recursive: true);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final result = await callP2PMediaDownload(
      bridge,
      id: blobId,
      outputPath: tempPath,
    );
    if (result['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_AVATAR_DOWNLOAD_FAILED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'blobId': blobId.length > 8 ? blobId.substring(0, 8) : blobId,
          'error': result['errorMessage'],
        },
      );
      return null;
    }

    await normalizeAndCommitGroupAvatar(
      groupId: groupId,
      inputPath: tempPath,
      avatarNormalizer: avatarNormalizer,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_AVATAR_DOWNLOAD_SUCCESS',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'blobId': blobId.length > 8 ? blobId.substring(0, 8) : blobId,
      },
    );
    return groupAvatarRelativePath(groupId);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_AVATAR_DOWNLOAD_ERROR',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'blobId': blobId.length > 8 ? blobId.substring(0, 8) : blobId,
        'error': e.toString(),
      },
    );
    return null;
  }
}

Future<void> deleteGroupAvatar({String? storedPath, String? groupId}) async {
  final effectivePath =
      storedPath ?? (groupId == null ? null : groupAvatarRelativePath(groupId));
  if (effectivePath == null || effectivePath.isEmpty) {
    return;
  }

  try {
    final resolvedPath = await _resolveGroupAvatarPath(effectivePath);
    final file = File(resolvedPath);
    unawaited(FileImage(file).evict());
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}

Future<String> _resolveGroupAvatarPath(String storedPath) async {
  if (p.isAbsolute(storedPath)) {
    return storedPath;
  }

  final appDir = await getApplicationDocumentsDirectory();
  return p.join(appDir.path, storedPath);
}
