import 'dart:convert' show base64Encode;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

class PreparedRepostAvatarSnapshot {
  final String avatarBase64;
  final int avatarByteLength;

  const PreparedRepostAvatarSnapshot({
    required this.avatarBase64,
    required this.avatarByteLength,
  });
}

Future<PreparedRepostAvatarSnapshot?> prepareRepostAvatarSnapshot({
  required String postId,
  required String authorPeerId,
  required Uint8List avatarBytes,
  AvatarNormalizationHelper? avatarNormalizer,
  int maxBytes = 65536,
}) async {
  final normalizer = avatarNormalizer ?? AvatarNormalizationHelper();
  final tempDir = await Directory.systemTemp.createTemp(
    'post-pass-avatar-${postId}_$authorPeerId-',
  );
  final sourceFile = File('${tempDir.path}/source.jpg');

  emitFlowEvent(
    layer: 'FL',
    event: 'POST_PASS_AVATAR_PROCESS_START',
    details: {
      'postId': postId,
      'authorPeerId': authorPeerId,
      'rawAvatarByteLength': avatarBytes.length,
      'maxBytes': maxBytes,
    },
  );

  try {
    await sourceFile.writeAsBytes(avatarBytes, flush: true);
    final processedPath = await normalizer.prepareAvatar(
      inputPath: sourceFile.path,
    );
    final processedBytes = await File(processedPath).readAsBytes();
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_PASS_AVATAR_PROCESS_SUCCESS',
      details: {
        'postId': postId,
        'authorPeerId': authorPeerId,
        'processedAvatarByteLength': processedBytes.length,
      },
    );
    if (processedBytes.length > maxBytes) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_PASS_AVATAR_OMITTED_TOO_LARGE',
        details: {
          'postId': postId,
          'authorPeerId': authorPeerId,
          'processedAvatarByteLength': processedBytes.length,
          'maxBytes': maxBytes,
        },
      );
      return null;
    }
    return PreparedRepostAvatarSnapshot(
      avatarBase64: base64Encode(processedBytes),
      avatarByteLength: processedBytes.length,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_PASS_AVATAR_PROCESS_FAILED',
      details: {
        'postId': postId,
        'authorPeerId': authorPeerId,
        'error': e.toString(),
      },
    );
    return null;
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}
