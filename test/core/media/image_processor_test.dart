import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

void main() {
  group('isProcessableImage', () {
    late ImageProcessor processor;

    setUp(() {
      processor = ImageProcessor(compressFile: _noOpCompress);
    });

    test('returns true for .jpg, .jpeg, .png, .webp, .heic', () {
      expect(processor.isProcessableImage('photo.jpg'), true);
      expect(processor.isProcessableImage('photo.jpeg'), true);
      expect(processor.isProcessableImage('photo.png'), true);
      expect(processor.isProcessableImage('photo.webp'), true);
      expect(processor.isProcessableImage('photo.heic'), true);
      expect(processor.isProcessableImage('photo.JPG'), true);
    });

    test('returns false for .mp4, .mov, .pdf, .aac', () {
      expect(processor.isProcessableImage('video.mp4'), false);
      expect(processor.isProcessableImage('video.mov'), false);
      expect(processor.isProcessableImage('doc.pdf'), false);
      expect(processor.isProcessableImage('audio.aac'), false);
    });

    test('returns false for .gif to preserve animation', () {
      expect(processor.isProcessableImage('funny.gif'), false);
      expect(processor.isProcessableImage('funny.GIF'), false);
    });
  });

  group('processImage', () {
    test('returns original path unchanged for non-image file (.mp4)', () async {
      final processor = ImageProcessor(compressFile: _noOpCompress);

      final result = await processor.processImage(
        inputPath: '/tmp/video.mp4',
        quality: ImageQualityPreference.compressed,
      );

      expect(result, '/tmp/video.mp4');
    });

    test('calls compress with quality 85 when preference is compressed',
        () async {
      int? capturedQuality;
      final processor = ImageProcessor(
        compressFile: ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          capturedQuality = quality;
          return XFile('${path}_compressed.jpg');
        },
      );

      await processor.processImage(
        inputPath: '/tmp/photo.jpg',
        quality: ImageQualityPreference.compressed,
      );

      expect(capturedQuality, 85);
    });

    test('calls compress with quality 100 when preference is original',
        () async {
      int? capturedQuality;
      final processor = ImageProcessor(
        compressFile: ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          capturedQuality = quality;
          return XFile('${path}_compressed.jpg');
        },
      );

      await processor.processImage(
        inputPath: '/tmp/photo.jpg',
        quality: ImageQualityPreference.original,
      );

      expect(capturedQuality, 100);
    });

    test('always passes keepExif: false (compressed)', () async {
      bool? capturedKeepExif;
      final processor = ImageProcessor(
        compressFile: ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          capturedKeepExif = keepExif;
          return XFile('${path}_compressed.jpg');
        },
      );

      await processor.processImage(
        inputPath: '/tmp/photo.jpg',
        quality: ImageQualityPreference.compressed,
      );

      expect(capturedKeepExif, false);
    });

    test('always passes keepExif: false (original)', () async {
      bool? capturedKeepExif;
      final processor = ImageProcessor(
        compressFile: ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          capturedKeepExif = keepExif;
          return XFile('${path}_compressed.jpg');
        },
      );

      await processor.processImage(
        inputPath: '/tmp/photo.png',
        quality: ImageQualityPreference.original,
      );

      expect(capturedKeepExif, false);
    });

    test('returns original path when compress returns null (graceful fallback)',
        () async {
      final processor = ImageProcessor(
        compressFile: ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          return null;
        },
      );

      final result = await processor.processImage(
        inputPath: '/tmp/photo.jpg',
        quality: ImageQualityPreference.compressed,
      );

      expect(result, '/tmp/photo.jpg');
    });

    test('returns original path unchanged for .gif files', () async {
      var compressCalled = false;
      final processor = ImageProcessor(
        compressFile: ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          compressCalled = true;
          return XFile('${path}_compressed.jpg');
        },
      );

      final result = await processor.processImage(
        inputPath: '/tmp/funny.gif',
        quality: ImageQualityPreference.compressed,
      );

      expect(result, '/tmp/funny.gif');
      expect(compressCalled, isFalse);
    });
  });

  group('processAvatar', () {
    test('calls compress with quality 80, minWidth 512, minHeight 512',
        () async {
      int? capturedQuality;
      int? capturedMinWidth;
      int? capturedMinHeight;
      final processor = ImageProcessor(
        compressFile: ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          capturedQuality = quality;
          capturedMinWidth = minWidth;
          capturedMinHeight = minHeight;
          return XFile('${path}_compressed.jpg');
        },
      );

      await processor.processAvatar(inputPath: '/tmp/photo.jpg');

      expect(capturedQuality, 80);
      expect(capturedMinWidth, 512);
      expect(capturedMinHeight, 512);
    });

    test('always passes keepExif: false', () async {
      bool? capturedKeepExif;
      final processor = ImageProcessor(
        compressFile: ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          capturedKeepExif = keepExif;
          return XFile('${path}_compressed.jpg');
        },
      );

      await processor.processAvatar(inputPath: '/tmp/photo.jpg');

      expect(capturedKeepExif, false);
    });

    test('returns original path when compress returns null', () async {
      final processor = ImageProcessor(
        compressFile: ({
          required String path,
          required int quality,
          required bool keepExif,
          int minWidth = 1920,
          int minHeight = 1080,
        }) async {
          return null;
        },
      );

      final result = await processor.processAvatar(inputPath: '/tmp/photo.jpg');

      expect(result, '/tmp/photo.jpg');
    });
  });

  group('isProcessableVideo', () {
    late ImageProcessor processor;

    setUp(() {
      processor = ImageProcessor(compressFile: _noOpCompress);
    });

    test('returns true for .mp4, .mov, .avi, .mkv, .m4v', () {
      expect(processor.isProcessableVideo('video.mp4'), true);
      expect(processor.isProcessableVideo('video.mov'), true);
      expect(processor.isProcessableVideo('video.avi'), true);
      expect(processor.isProcessableVideo('video.mkv'), true);
      expect(processor.isProcessableVideo('video.m4v'), true);
    });

    test('returns true for uppercase .MP4', () {
      expect(processor.isProcessableVideo('video.MP4'), true);
    });

    test('returns false for .jpg, .png, .pdf, .aac', () {
      expect(processor.isProcessableVideo('photo.jpg'), false);
      expect(processor.isProcessableVideo('photo.png'), false);
      expect(processor.isProcessableVideo('doc.pdf'), false);
      expect(processor.isProcessableVideo('audio.aac'), false);
    });

    test('returns false for .mp3 (audio, not video)', () {
      expect(processor.isProcessableVideo('audio.mp3'), false);
    });
  });

  group('processVideo', () {
    test('returns original path unchanged for non-video file (.jpg)', () async {
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo: _noOpVideoCompress,
      );

      final result = await processor.processVideo(
        inputPath: '/tmp/photo.jpg',
        quality: ImageQualityPreference.compressed,
      );

      expect(result.path, '/tmp/photo.jpg');
      expect(result.width, isNull);
      expect(result.height, isNull);
      expect(result.durationMs, isNull);
    });

    test('calls compressVideo with compress: true when preference is compressed',
        () async {
      bool? capturedCompress;
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo: ({
          required String path,
          required bool compress,
          void Function(double)? onProgress,
        }) async {
          capturedCompress = compress;
          return VideoProcessResult(path: '${path}_out.mp4');
        },
      );

      await processor.processVideo(
        inputPath: '/tmp/video.mp4',
        quality: ImageQualityPreference.compressed,
      );

      expect(capturedCompress, true);
    });

    test('calls compressVideo with compress: false when preference is original',
        () async {
      bool? capturedCompress;
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo: ({
          required String path,
          required bool compress,
          void Function(double)? onProgress,
        }) async {
          capturedCompress = compress;
          return VideoProcessResult(path: '${path}_out.mp4');
        },
      );

      await processor.processVideo(
        inputPath: '/tmp/video.mp4',
        quality: ImageQualityPreference.original,
      );

      expect(capturedCompress, false);
    });

    test('returns processed path from CompressVideoFn result', () async {
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo: ({
          required String path,
          required bool compress,
          void Function(double)? onProgress,
        }) async {
          return VideoProcessResult(path: '/tmp/processed_video.mp4');
        },
      );

      final result = await processor.processVideo(
        inputPath: '/tmp/video.mp4',
        quality: ImageQualityPreference.compressed,
      );

      expect(result.path, '/tmp/processed_video.mp4');
    });

    test('returns width, height, durationMs from CompressVideoFn result',
        () async {
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo: ({
          required String path,
          required bool compress,
          void Function(double)? onProgress,
        }) async {
          return VideoProcessResult(
            path: '/tmp/processed.mp4',
            width: 1920,
            height: 1080,
            durationMs: 30000,
          );
        },
      );

      final result = await processor.processVideo(
        inputPath: '/tmp/video.mp4',
        quality: ImageQualityPreference.compressed,
      );

      expect(result.width, 1920);
      expect(result.height, 1080);
      expect(result.durationMs, 30000);
    });

    test('returns null metadata when CompressVideoFn provides null metadata',
        () async {
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo: ({
          required String path,
          required bool compress,
          void Function(double)? onProgress,
        }) async {
          return VideoProcessResult(path: '/tmp/processed.mp4');
        },
      );

      final result = await processor.processVideo(
        inputPath: '/tmp/video.mp4',
        quality: ImageQualityPreference.compressed,
      );

      expect(result.width, isNull);
      expect(result.height, isNull);
      expect(result.durationMs, isNull);
    });

    test('returns original path when CompressVideoFn returns null (graceful fallback)',
        () async {
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo: ({
          required String path,
          required bool compress,
          void Function(double)? onProgress,
        }) async {
          return null;
        },
      );

      final result = await processor.processVideo(
        inputPath: '/tmp/video.mp4',
        quality: ImageQualityPreference.compressed,
      );

      expect(result.path, '/tmp/video.mp4');
      expect(result.width, isNull);
      expect(result.height, isNull);
      expect(result.durationMs, isNull);
    });

    test('passes onProgress to CompressVideoFn', () async {
      final receivedProgress = <double>[];
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo: ({
          required String path,
          required bool compress,
          void Function(double)? onProgress,
        }) async {
          onProgress?.call(25.0);
          onProgress?.call(50.0);
          onProgress?.call(100.0);
          return VideoProcessResult(path: '${path}_out.mp4');
        },
      );

      await processor.processVideo(
        inputPath: '/tmp/video.mp4',
        quality: ImageQualityPreference.compressed,
        onProgress: (p) => receivedProgress.add(p),
      );

      expect(receivedProgress, [25.0, 50.0, 100.0]);
    });

    test('processVideo works without onProgress (null)', () async {
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo: ({
          required String path,
          required bool compress,
          void Function(double)? onProgress,
        }) async {
          // onProgress should be null — just verify no crash
          expect(onProgress, isNull);
          return VideoProcessResult(path: '${path}_out.mp4');
        },
      );

      final result = await processor.processVideo(
        inputPath: '/tmp/video.mp4',
        quality: ImageQualityPreference.compressed,
      );

      expect(result.path, '/tmp/video.mp4_out.mp4');
    });
  });
}

/// A no-op compress function for tests that don't care about compression.
Future<XFile?> _noOpCompress({
  required String path,
  required int quality,
  required bool keepExif,
  int minWidth = 1920,
  int minHeight = 1080,
}) async {
  return XFile('${path}_compressed.jpg');
}

/// A no-op video compress function for tests that don't care about video compression.
Future<VideoProcessResult?> _noOpVideoCompress({
  required String path,
  required bool compress,
  void Function(double progress)? onProgress,
}) async {
  return VideoProcessResult(path: '${path}_out.mp4');
}
