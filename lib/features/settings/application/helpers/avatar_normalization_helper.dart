import 'dart:io';
import 'dart:math';

import 'package:flutter_app/core/media/image_processor.dart';

/// Shared helper for avatar normalization and canonical disk commits.
///
/// The helper keeps the client-side avatar contract in one place so upload
/// and download flows cannot drift apart again.
class AvatarNormalizationHelper {
  final ImageProcessor _imageProcessor;
  static final Random _random = Random();

  AvatarNormalizationHelper({ImageProcessor? imageProcessor})
    : _imageProcessor = imageProcessor ?? ImageProcessor();

  /// Runs the canonical avatar processing contract.
  ///
  /// Avatars must be normalized before they are committed to disk.
  Future<String> prepareAvatar({required String inputPath}) async {
    final processedPath = await _imageProcessor.processAvatar(
      inputPath: inputPath,
    );

    if (processedPath == inputPath) {
      throw StateError(
        'Avatar processing did not produce a normalized file for $inputPath',
      );
    }

    return processedPath;
  }

  /// Commits a processed avatar to the canonical on-disk path.
  ///
  /// The write happens through a sibling staging file first so a failed commit
  /// does not leave a half-written canonical file behind.
  Future<String> commitAvatar({
    required String sourcePath,
    required String canonicalPath,
  }) async {
    final canonicalFile = File(canonicalPath);
    await canonicalFile.parent.create(recursive: true);

    final stagingPath = '$canonicalPath.normalized_tmp.${_uniqueSuffix()}';
    final stagingFile = File(stagingPath);
    if (await stagingFile.exists()) {
      await stagingFile.delete();
    }

    await File(sourcePath).copy(stagingPath);

    if (await canonicalFile.exists()) {
      await canonicalFile.delete();
    }

    await stagingFile.rename(canonicalPath);
    return canonicalPath;
  }

  /// Normalizes an input avatar and commits it to the canonical path.
  Future<String> normalizeAvatar({
    required String inputPath,
    required String canonicalPath,
  }) async {
    final processedPath = await prepareAvatar(inputPath: inputPath);
    return commitAvatar(
      sourcePath: processedPath,
      canonicalPath: canonicalPath,
    );
  }

  static String _uniqueSuffix() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final token = _random.nextInt(1 << 32).toRadixString(16);
    return '$now-$token';
  }
}
