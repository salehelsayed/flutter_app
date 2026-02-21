import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

/// Function signature for image compression.
///
/// Matches the shape of [FlutterImageCompress.compressAndGetFile] so it can
/// be swapped with a fake in tests.
typedef CompressFileFn = Future<XFile?> Function({
  required String path,
  required int quality,
  required bool keepExif,
  int minWidth,
  int minHeight,
});

/// Function signature for video compression.
///
/// Injectable so it can be swapped with a fake in tests.
/// [onProgress] emits 0.0–100.0 during compression.
typedef CompressVideoFn = Future<VideoProcessResult?> Function({
  required String path,
  required bool compress,
  void Function(double progress)? onProgress,
});

/// Processes images and videos before sending: strips metadata and applies quality.
///
/// Injectable [CompressFileFn] and [CompressVideoFn] allow faking in tests.
class ImageProcessor {
  final CompressFileFn _compressFile;
  final CompressVideoFn _compressVideo;

  ImageProcessor({
    CompressFileFn? compressFile,
    CompressVideoFn? compressVideo,
  })  : _compressFile = compressFile ?? _defaultCompress,
        _compressVideo = compressVideo ?? _defaultVideoCompress;

  /// Process image for sending: strip EXIF, apply quality.
  ///
  /// Non-image files (videos, PDFs) pass through unchanged.
  /// Returns the path to the processed file.
  Future<String> processImage({
    required String inputPath,
    required ImageQualityPreference quality,
  }) async {
    if (!isProcessableImage(inputPath)) return inputPath;

    final compressionQuality =
        quality == ImageQualityPreference.original ? 100 : 85;

    final result = await _compressFile(
      path: inputPath,
      quality: compressionQuality,
      keepExif: false,
    );

    return result?.path ?? inputPath;
  }

  /// Process avatar: always 512x512, quality 80, strip EXIF.
  ///
  /// Quality setting is ignored — avatars are always compressed.
  Future<String> processAvatar({required String inputPath}) async {
    if (!isProcessableImage(inputPath)) return inputPath;

    final result = await _compressFile(
      path: inputPath,
      quality: 80,
      keepExif: false,
      minWidth: 512,
      minHeight: 512,
    );

    return result?.path ?? inputPath;
  }

  /// Process video: strip metadata via re-encoding, apply quality.
  ///
  /// Non-video files pass through unchanged.
  /// [onProgress] receives 0.0–100.0 during compression.
  Future<VideoProcessResult> processVideo({
    required String inputPath,
    required ImageQualityPreference quality,
    void Function(double progress)? onProgress,
  }) async {
    if (!isProcessableVideo(inputPath)) {
      return VideoProcessResult(path: inputPath);
    }

    final result = await _compressVideo(
      path: inputPath,
      compress: quality == ImageQualityPreference.compressed,
      onProgress: onProgress,
    );

    return result ?? VideoProcessResult(path: inputPath);
  }

  /// Returns true for image extensions that can be processed.
  bool isProcessableImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(ext);
  }

  /// Returns true for video extensions that can be processed.
  bool isProcessableVideo(String path) {
    final ext = path.split('.').last.toLowerCase();
    return const {'mp4', 'mov', 'avi', 'mkv', 'm4v'}.contains(ext);
  }
}

/// Default compression using flutter_image_compress.
Future<XFile?> _defaultCompress({
  required String path,
  required int quality,
  required bool keepExif,
  int minWidth = 1920,
  int minHeight = 1080,
}) async {
  final targetPath = '${path}_compressed.jpg';
  return FlutterImageCompress.compressAndGetFile(
    path,
    targetPath,
    quality: quality,
    keepExif: keepExif,
    minWidth: minWidth,
    minHeight: minHeight,
  );
}

/// Default video compression using video_compress.
///
/// Re-encoding inherently strips ALL metadata (GPS, camera model, timestamps).
Future<VideoProcessResult?> _defaultVideoCompress({
  required String path,
  required bool compress,
  void Function(double progress)? onProgress,
}) async {
  Subscription? subscription;
  if (onProgress != null) {
    subscription = VideoCompress.compressProgress$.subscribe((progress) {
      onProgress(progress);
    });
  }

  try {
    final info = await VideoCompress.compressVideo(
      path,
      quality: compress
          ? VideoQuality.MediumQuality
          : VideoQuality.HighestQuality,
      deleteOrigin: false,
      includeAudio: true,
    );
    if (info?.path == null) return null;
    return VideoProcessResult(
      path: info!.path!,
      width: info.width?.toInt(),
      height: info.height?.toInt(),
      durationMs: info.duration?.toInt(),
    );
  } finally {
    subscription?.unsubscribe();
  }
}
