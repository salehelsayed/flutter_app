import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:video_compress/video_compress.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/media/jpeg_metadata.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

/// Function signature for image compression.
///
/// Matches the shape of [FlutterImageCompress.compressAndGetFile] so it can
/// be swapped with a fake in tests.
typedef CompressFileFn =
    Future<XFile?> Function({
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
typedef CompressVideoFn =
    Future<VideoProcessResult?> Function({
      required String path,
      required bool compress,
      void Function(double progress)? onProgress,
    });

typedef CancelVideoCompressionFn = Future<void> Function();

class VideoProcessingTimeoutException implements Exception {
  const VideoProcessingTimeoutException();

  @override
  String toString() => 'Video processing stopped after progress stalled';
}

class VideoProcessingUnavailableException implements Exception {
  const VideoProcessingUnavailableException();

  @override
  String toString() =>
      'Video processing is unavailable until the native job ends';
}

class VideoProcessingFailedException implements Exception {
  const VideoProcessingFailedException();

  @override
  String toString() => 'Video processing failed';
}

/// Wire key for the protected-photo inline thumbnail rides inside the
/// already-E2E-encrypted direct-lane attachment JSON (plan 301). Producers and
/// consumers live only in the send/receive use cases.
const kProtectedPhotoInlineThumbnailKey = 'thumbnailInlineBase64';

/// Hard cap on the RAW (pre-base64) inline thumbnail bytes. Bounded by the
/// 128 KB transport frame cap on both durable legs (relay inbox and the
/// go-mknoon direct stream): 49,152 raw → ~91 KB worst-case frame after the
/// double base64 + AEAD envelope. NEVER raise this without recomputing
/// against maxFrameLen — an oversized message is permanently undeliverable.
const kProtectedPhotoInlineThumbnailMaxRawBytes = 49152;

/// Longest-side bound and JPEG quality for generated inline thumbnails.
const kProtectedPhotoInlineThumbnailMaxSidePx = 320;
const kProtectedPhotoInlineThumbnailJpegQuality = 60;

/// Processes images and videos before sending: strips metadata and applies quality.
///
/// Injectable [CompressFileFn] and [CompressVideoFn] allow faking in tests.
class ImageProcessor {
  // Both native encoders clamp their resize scale to avoid upscaling. The
  // largest signed native int disables downscaling without decoding the full
  // source in Dart just to discover its dimensions (including HEIC inputs).
  static const _originalMinDimension = 0x7fffffff;

  // video_compress uses one native worker and one process-wide Dart busy flag.
  // A timed-out MethodChannel call can remain blocked in eglSwapBuffers. Do not
  // submit another job until that exact native call has actually settled.
  static Future<VideoProcessResult?>? _unsettledDefaultVideoCompression;

  bool get canProcessVideo =>
      _compressVideo != null || _unsettledDefaultVideoCompression == null;

  final Future<ImageQualityPreference> Function()? _loadImageQualityPreference;
  final Future<ImageQualityPreference> Function()? _loadVideoQualityPreference;
  final CompressFileFn _compressFile;
  final CompressVideoFn? _compressVideo;
  final CancelVideoCompressionFn _cancelVideoCompression;
  final Duration videoStallTimeout;
  final Duration videoMaxDuration;
  final Duration videoCancelTimeout;
  void Function()? _cancelActiveVideoProgress;

  ImageProcessor({
    Future<ImageQualityPreference> Function()? loadImageQualityPreference,
    Future<ImageQualityPreference> Function()? loadVideoQualityPreference,
    CompressFileFn? compressFile,
    CompressVideoFn? compressVideo,
    CancelVideoCompressionFn? cancelVideoCompression,
    this.videoStallTimeout = const Duration(minutes: 5),
    this.videoMaxDuration = const Duration(hours: 1),
    this.videoCancelTimeout = const Duration(seconds: 5),
  }) : _loadImageQualityPreference = loadImageQualityPreference,
       _loadVideoQualityPreference = loadVideoQualityPreference,
       _compressFile = compressFile ?? _defaultCompress,
       _compressVideo = compressVideo,
       _cancelVideoCompression =
           cancelVideoCompression ?? _cancelDefaultVideoCompression;

  /// Process image for sending: strip metadata; Original preserves JPEG coding.
  /// Other formats and unsupported JPEG variants use the native encoder at
  /// source resolution. Only display orientation and ICC colour data survive
  /// the JPEG metadata path. A failed encoder never exposes an unprocessed photo.
  ///
  /// A configured stored preference is read for each preparation. [quality]
  /// remains the fallback for standalone processors. Set [useStoredPreference]
  /// to false only for an explicit quality override, such as overflow compression.
  /// Non-image files (videos, PDFs) pass through unchanged.
  /// Returns the path to the processed file.
  Future<String> processImage({
    required String inputPath,
    required ImageQualityPreference quality,
    bool useStoredPreference = true,
  }) async {
    if (!isProcessableImage(inputPath)) return inputPath;

    if (useStoredPreference && _loadImageQualityPreference != null) {
      try {
        quality = await _loadImageQualityPreference();
      } catch (_) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_QUALITY_PREFERENCE_READ_FAILED',
          details: {'mediaType': 'image'},
        );
      }
    }
    if (quality == ImageQualityPreference.original) {
      final strippedPath = await _tryStripOriginalJpeg(inputPath);
      if (strippedPath != null) return strippedPath;
    }
    final compressionQuality = quality == ImageQualityPreference.original
        ? 100
        : 85;

    final result = await _compressFile(
      path: inputPath,
      quality: compressionQuality,
      keepExif: false,
      minWidth: quality == ImageQualityPreference.original
          ? _originalMinDimension
          : 1920,
      minHeight: quality == ImageQualityPreference.original
          ? _originalMinDimension
          : 1080,
    );

    if (result == null) {
      throw StateError('Photo processing failed');
    }
    return result.path;
  }

  /// Process avatar: compress to a ≥512px jpeg (quality 80, EXIF stripped), then
  /// center-square any non-square result so avatars are stored — and rendered —
  /// without aspect-ratio stretch (plan 200; `flutter_image_compress` scales
  /// proportionally and has no crop API).
  ///
  /// The square step is strictly best-effort: a missing, undecodable, or
  /// already-square compress output passes through byte-identical. A compress
  /// failure (null) returns the input path with no crop.
  Future<String> processAvatar({required String inputPath}) async {
    if (!isProcessableImage(inputPath)) return inputPath;

    final result = await _compressFile(
      path: inputPath,
      quality: 80,
      keepExif: false,
      minWidth: 512,
      minHeight: 512,
    );

    final compressedPath = result?.path;
    if (compressedPath == null) return inputPath;

    return _squareCropAvatar(compressedPath);
  }

  /// Process video: strip metadata via re-encoding, apply quality.
  ///
  /// Non-video files pass through unchanged.
  /// [onProgress] receives 0.0–100.0 during compression.
  Future<VideoProcessResult> processVideo({
    required String inputPath,
    required ImageQualityPreference quality,
    bool useStoredPreference = true,
    void Function(double progress)? onProgress,
  }) async {
    if (!isProcessableVideo(inputPath)) {
      return VideoProcessResult(path: inputPath);
    }
    if (_compressVideo == null && _unsettledDefaultVideoCompression != null) {
      throw const VideoProcessingUnavailableException();
    }
    if (useStoredPreference && _loadVideoQualityPreference != null) {
      try {
        quality = await _loadVideoQualityPreference();
      } catch (_) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_QUALITY_PREFERENCE_READ_FAILED',
          details: {'mediaType': 'video'},
        );
      }
    }

    Timer? stallTimer;
    Timer? absoluteTimer;
    final stalled = Completer<VideoProcessResult?>();
    var active = true;
    var highestProgress = -1.0;

    void armWatchdog() {
      stallTimer?.cancel();
      stallTimer = Timer(videoStallTimeout, () {
        if (active && !stalled.isCompleted) {
          stalled.completeError(const VideoProcessingTimeoutException());
        }
      });
    }

    armWatchdog();
    absoluteTimer = Timer(videoMaxDuration, () {
      if (active && !stalled.isCompleted) {
        stalled.completeError(const VideoProcessingTimeoutException());
      }
    });
    late final Future<VideoProcessResult?> operation;
    try {
      operation = (_compressVideo ?? _defaultVideoCompress)(
        path: inputPath,
        compress: quality == ImageQualityPreference.compressed,
        onProgress: (progress) {
          if (!active) return;
          if (progress.isFinite && progress > highestProgress) {
            highestProgress = progress;
            armWatchdog();
          }
          onProgress?.call(progress);
        },
      );
      final result = await Future.any([operation, stalled.future]);
      if (result == null) throw const VideoProcessingFailedException();
      return result;
    } on VideoProcessingTimeoutException {
      if (_compressVideo == null) {
        _unsettledDefaultVideoCompression = operation;
        operation.then<void>(
          (_) {
            if (identical(_unsettledDefaultVideoCompression, operation)) {
              _unsettledDefaultVideoCompression = null;
            }
          },
          onError: (Object _, StackTrace _) {
            if (identical(_unsettledDefaultVideoCompression, operation)) {
              _unsettledDefaultVideoCompression = null;
            }
          },
        );
      }
      // Stop listening before cancelling: the native call may still emit a late
      // progress event, or even fail to complete its MethodChannel future.
      _cancelActiveVideoProgress?.call();
      _cancelActiveVideoProgress = null;
      try {
        await _cancelVideoCompression().timeout(videoCancelTimeout);
      } catch (_) {
        // The composer must recover even if the platform cancellation stalls.
      }
      rethrow;
    } finally {
      active = false;
      stallTimer?.cancel();
      absoluteTimer.cancel();
    }
  }

  Future<VideoProcessResult?> _defaultVideoCompress({
    required String path,
    required bool compress,
    void Function(double progress)? onProgress,
  }) async {
    final subscription = VideoCompress.compressProgress$.subscribe((progress) {
      onProgress?.call(progress);
    });
    var progressSubscriptionClosed = false;
    void closeProgressSubscription() {
      if (progressSubscriptionClosed) return;
      progressSubscriptionClosed = true;
      subscription.unsubscribe();
    }

    _cancelActiveVideoProgress = closeProgressSubscription;
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
      closeProgressSubscription();
      if (identical(_cancelActiveVideoProgress, closeProgressSubscription)) {
        _cancelActiveVideoProgress = null;
      }
    }
  }

  /// Generates the bounded protected-photo inline thumbnail (plan 301).
  ///
  /// Decode at thumbnail size before JPEG encoding, so a full-resolution send
  /// does not also allocate a full-size Dart raster for this preview. Returns
  /// null on read/decode failure or oversized output (best-effort, never fails
  /// a send). The native codec may still use transient decode working memory.
  static Future<Uint8List?> generateInlineThumbnailBytes({
    required String inputPath,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(inputPath);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final longestSide = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = longestSide > kProtectedPhotoInlineThumbnailMaxSidePx
          ? kProtectedPhotoInlineThumbnailMaxSidePx / longestSide
          : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(
          1,
          kProtectedPhotoInlineThumbnailMaxSidePx,
        ),
        targetHeight: (descriptor.height * scale).round().clamp(
          1,
          kProtectedPhotoInlineThumbnailMaxSidePx,
        ),
      );
      image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.png);
      if (pixels == null) return null;
      final resized = img.decodePng(pixels.buffer.asUint8List());
      if (resized == null) return null;
      final encoded = Uint8List.fromList(
        img.encodeJpg(
          resized,
          quality: kProtectedPhotoInlineThumbnailJpegQuality,
        ),
      );
      if (encoded.isEmpty ||
          encoded.length > kProtectedPhotoInlineThumbnailMaxRawBytes) {
        return null;
      }
      return encoded;
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Returns true for image extensions that can be processed.
  bool isProcessableImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'}.contains(ext)) {
      return true;
    }
    // Shared/temporary files can omit an extension. Recognize only the existing
    // formats, from a bounded header; this does not add another codec or MIME.
    try {
      final handle = File(path).openSync();
      final Uint8List header;
      try {
        header = handle.readSync(32);
      } finally {
        handle.closeSync();
      }
      final bytes = String.fromCharCodes(header);
      if (bytes.startsWith('\xff\xd8') ||
          bytes.startsWith('\x89PNG\r\n\x1a\n')) {
        return true;
      }
      if (bytes.length < 12) return false;
      if (bytes.startsWith('RIFF') && bytes.substring(8, 12) == 'WEBP') {
        return true;
      }
      return bytes.substring(4, 8) == 'ftyp' &&
          const {'heic', 'heix', 'mif1'}.contains(bytes.substring(8, 12));
    } on FileSystemException {
      return false;
    }
  }

  /// Returns true for video extensions that can be processed.
  bool isProcessableVideo(String path) {
    final ext = path.split('.').last.toLowerCase();
    return const {'mp4', 'mov', 'avi', 'mkv', 'm4v'}.contains(ext);
  }
}

/// Best-effort center-square of an already-compressed avatar file.
///
/// Returns a NEW file path when a decodable, NON-square image was squared.
/// Otherwise returns [compressedPath] unchanged — a missing file, undecodable
/// bytes, or an already-square image all pass through byte-identical, so avatars
/// never stretch while the downstream fake-compressor contracts (missing/junk/
/// square bytes asserted byte-identical) stay green (plan 200). Any I/O, decode,
/// or encode error is swallowed and the compress output is returned as-is.
Future<String> _squareCropAvatar(String compressedPath) async {
  try {
    final file = File(compressedPath);
    if (!await file.exists()) return compressedPath;

    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) return compressedPath;
    if (decoded.width == decoded.height) return compressedPath;

    final side = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final squared = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );

    final squaredPath = '$compressedPath.square.jpg';
    await File(squaredPath).writeAsBytes(img.encodeJpg(squared, quality: 85));
    // Best-effort: drop the pre-square intermediate so a non-square pick leaves
    // one temp artifact, not two. Inner guard so a delete failure never falls
    // through to the outer catch (which would discard the successful crop).
    try {
      await file.delete();
    } catch (_) {}
    return squaredPath;
  } catch (_) {
    return compressedPath;
  }
}

Future<String?> _tryStripOriginalJpeg(String path) async {
  try {
    final input = File(path);
    final handle = await input.open();
    final Uint8List signature;
    try {
      signature = await handle.read(2);
    } finally {
      await handle.close();
    }
    // Avoid loading PNG/HEIC/WebP data before their existing native decode.
    if (signature.length != 2 || signature[0] != 0xff || signature[1] != 0xd8) {
      return null;
    }
    final stripped = stripJpegMetadata(await input.readAsBytes());
    if (stripped == null) return null;
    final target = File('${path}_compressed.jpg');
    await target.writeAsBytes(stripped);
    return target.path;
  } on FileSystemException {
    // The native encoder remains the fallback for inaccessible/unsupported
    // sources or an output write failure; its failure must not expose raw input.
    return null;
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

Future<void> _cancelDefaultVideoCompression() =>
    VideoCompress.cancelCompression();
