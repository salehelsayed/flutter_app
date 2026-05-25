import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

const _uuid = Uuid();

typedef DownloadGroupAvatarFn =
    Future<String?> Function({
      required Bridge bridge,
      required String groupId,
      required String blobId,
    });

typedef UploadGroupAvatarFn =
    Future<GroupAvatarUpload?> Function({
      required Bridge bridge,
      required String localFilePath,
      required String groupId,
      required List<String> allowedPeers,
      String? blobId,
      String mime,
    });

class GroupAvatarUpload {
  final String id;
  final String mime;
  final int size;

  const GroupAvatarUpload({
    required this.id,
    required this.mime,
    required this.size,
  });
}

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

Future<GroupAvatarUpload?> uploadGroupAvatar({
  required Bridge bridge,
  required String localFilePath,
  required String groupId,
  required List<String> allowedPeers,
  String? blobId,
  String mime = 'image/jpeg',
}) async {
  final effectiveBlobId = blobId ?? _uuid.v4();
  final file = File(localFilePath);
  final fileExists = await file.exists();
  final fileSize = fileExists ? await file.length() : 0;
  final hasImageSignature = fileExists
      ? await _hasSupportedAvatarImageSignature(file)
      : false;
  if (!fileExists || fileSize <= 0 || !hasImageSignature) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_AVATAR_UPLOAD_REJECTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'blobId': effectiveBlobId.length > 8
            ? effectiveBlobId.substring(0, 8)
            : effectiveBlobId,
        'reason': !fileExists || fileSize <= 0
            ? 'missing_file'
            : 'invalid_image_signature',
      },
    );
    return null;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_AVATAR_UPLOAD_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'blobId': effectiveBlobId.length > 8
          ? effectiveBlobId.substring(0, 8)
          : effectiveBlobId,
      'mime': mime,
      'allowedPeerCount': allowedPeers.length,
    },
  );

  final result = await callP2PMediaUpload(
    bridge,
    id: effectiveBlobId,
    toPeerId: groupId,
    mime: mime,
    filePath: localFilePath,
    allowedPeers: allowedPeers,
  );
  if (result['ok'] != true) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_AVATAR_UPLOAD_FAILED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'blobId': effectiveBlobId.length > 8
            ? effectiveBlobId.substring(0, 8)
            : effectiveBlobId,
        'error': result['errorMessage'],
      },
    );
    return null;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_AVATAR_UPLOAD_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'blobId': effectiveBlobId.length > 8
          ? effectiveBlobId.substring(0, 8)
          : effectiveBlobId,
      'size': fileSize,
    },
  );
  return GroupAvatarUpload(id: effectiveBlobId, mime: mime, size: fileSize);
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

  String? tempPath;
  try {
    final canonicalPath = await groupAvatarCanonicalPath(groupId);
    tempPath = '$canonicalPath.download.jpg';
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

    final downloadedExists = await tempFile.exists();
    final downloadedLength = downloadedExists ? await tempFile.length() : 0;
    final expectedSize = switch (result['size']) {
      final int size => size,
      final num size => size.toInt(),
      _ => null,
    };
    if (!downloadedExists ||
        downloadedLength <= 0 ||
        (expectedSize != null &&
            expectedSize > 0 &&
            downloadedLength != expectedSize)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_AVATAR_DOWNLOAD_MISSING_FILE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'blobId': blobId.length > 8 ? blobId.substring(0, 8) : blobId,
          'downloadedLength': downloadedLength,
          ...?expectedSize == null ? null : {'expectedSize': expectedSize},
        },
      );
      return null;
    }

    try {
      await normalizeAndCommitGroupAvatar(
        groupId: groupId,
        inputPath: tempPath,
        avatarNormalizer: avatarNormalizer,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_AVATAR_NORMALIZATION_FALLBACK',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'blobId': blobId.length > 8 ? blobId.substring(0, 8) : blobId,
          'error': e.toString(),
        },
      );
      if (!await _hasSupportedAvatarImageSignature(tempFile)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_AVATAR_NORMALIZATION_FALLBACK_REJECTED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'blobId': blobId.length > 8 ? blobId.substring(0, 8) : blobId,
            'reason': 'invalid_image_signature',
          },
        );
        return null;
      }
      await commitPreparedGroupAvatar(
        groupId: groupId,
        sourcePath: tempPath,
        avatarNormalizer: avatarNormalizer,
      );
    }

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
  } finally {
    final path = tempPath;
    if (path != null) {
      try {
        final tempFile = File(path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }
}

Future<bool> _hasSupportedAvatarImageSignature(File file) async {
  try {
    final bytes = await file
        .openRead(0, 12)
        .fold<List<int>>(<int>[], (previous, chunk) => previous..addAll(chunk));
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
  } catch (_) {}
  return false;
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
