import 'dart:io';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

const int kGeneralMediaAttachmentBudgetBytes = 5 * 1024 * 1024 * 1024;

class PendingComposerMedia {
  final File file;
  final int budgetBytes;
  final int? width;
  final int? height;
  final int? durationMs;

  const PendingComposerMedia({
    required this.file,
    required this.budgetBytes,
    this.width,
    this.height,
    this.durationMs,
  });
}

int _resolvedBudgetBytesForFile(File file, {required int fallbackBytes}) {
  try {
    return file.lengthSync();
  } catch (_) {
    return fallbackBytes;
  }
}

Future<PendingComposerMedia> preparePendingComposerMedia({
  required String inputPath,
  required ImageProcessor? imageProcessor,
  required ImageQualityPreference imageQualityPreference,
  required ImageQualityPreference videoQualityPreference,
  void Function(double progress)? onVideoProgress,
}) async {
  final sourceFile = File(inputPath);
  final rawBudgetBytes = sourceFile.lengthSync();
  if (imageProcessor == null) {
    return PendingComposerMedia(file: sourceFile, budgetBytes: rawBudgetBytes);
  }

  if (imageProcessor.isProcessableVideo(inputPath)) {
    final result = await imageProcessor.processVideo(
      inputPath: inputPath,
      quality: videoQualityPreference,
      onProgress: onVideoProgress,
    );
    final processedFile = File(result.path);
    final budgetBytes =
        videoQualityPreference == ImageQualityPreference.original
        ? rawBudgetBytes
        : _resolvedBudgetBytesForFile(
            processedFile,
            fallbackBytes: rawBudgetBytes,
          );
    return PendingComposerMedia(
      file: processedFile,
      budgetBytes: budgetBytes,
      width: result.width,
      height: result.height,
      durationMs: result.durationMs,
    );
  }

  if (imageProcessor.isProcessableImage(inputPath)) {
    final processedPath = await imageProcessor.processImage(
      inputPath: inputPath,
      quality: imageQualityPreference,
    );
    final processedFile = File(processedPath);
    final budgetBytes =
        imageQualityPreference == ImageQualityPreference.original
        ? rawBudgetBytes
        : _resolvedBudgetBytesForFile(
            processedFile,
            fallbackBytes: rawBudgetBytes,
          );
    return PendingComposerMedia(file: processedFile, budgetBytes: budgetBytes);
  }

  return PendingComposerMedia(file: sourceFile, budgetBytes: rawBudgetBytes);
}

int totalPendingComposerBudgetBytes(Iterable<PendingComposerMedia> media) {
  return media.fold<int>(0, (sum, item) => sum + item.budgetBytes);
}

String formatPendingComposerBudgetBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;

  if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(1)} GB';
  }
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }
  if (bytes >= kb) {
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
