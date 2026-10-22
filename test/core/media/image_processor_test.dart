import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('photo resolution through the default encoder', () {
    for (final extension in ['jpg', 'png']) {
      for (final portrait in [false, true]) {
        for (final quality in ImageQualityPreference.values) {
          test(
            '${quality.name} ${portrait ? 'portrait' : 'landscape'} $extension photo',
            () async {
              final directory = await Directory.systemTemp.createTemp(
                'photo-resolution-',
              );
              addTearDown(() => directory.delete(recursive: true));
              final source = img.Image(
                width: portrait ? 2400 : 3200,
                height: portrait ? 3200 : 2400,
              );
              // Camera JPEG and large PNG use the same metadata-stripping pipeline.
              final input = File('${directory.path}/source.$extension');
              await input.writeAsBytes(
                extension == 'png'
                    ? img.encodePng(source)
                    : img.encodeJpg(source),
              );
              final previous = FlutterImageCompressPlatform.instance;
              final encoder = _DimensionImageCompressor();
              FlutterImageCompressPlatform.instance = encoder;
              addTearDown(
                () => FlutterImageCompressPlatform.instance = previous,
              );

              final output = await ImageProcessor().processImage(
                inputPath: input.path,
                quality: quality,
              );
              final decoded = img.decodeJpg(await File(output).readAsBytes())!;
              if (quality == ImageQualityPreference.original) {
                expect(
                  (decoded.width, decoded.height),
                  (source.width, source.height),
                );
                expect(encoder.quality, 100);
              } else {
                expect((
                  decoded.width,
                  decoded.height,
                ), portrait ? (1920, 2560) : (1920, 1440));
                expect(encoder.quality, 85);
              }
              expect(encoder.keepExif, isFalse);
              expect(encoder.autoCorrectionAngle, isTrue);
            },
          );
        }
      }
    }
  });

  group('inline photo thumbnail', () {
    for (final portrait in [false, true]) {
      test(
        'bounds a large ${portrait ? 'portrait' : 'landscape'} photo to 320px',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'inline-thumbnail-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final source = img.Image(
            width: portrait ? 2400 : 3200,
            height: portrait ? 3200 : 2400,
          );
          final input = File('${directory.path}/source.png');
          final sourceBytes = img.encodePng(source);
          await input.writeAsBytes(sourceBytes);
          final bytes = await ImageProcessor.generateInlineThumbnailBytes(
            inputPath: input.path,
          );
          expect(bytes, isNotNull);
          expect(
            bytes!.length,
            lessThanOrEqualTo(kProtectedPhotoInlineThumbnailMaxRawBytes),
          );
          final thumbnail = img.decodeJpg(bytes)!;
          expect((
            thumbnail.width,
            thumbnail.height,
          ), portrait ? (240, 320) : (320, 240));
          expect(await input.readAsBytes(), sourceBytes);
        },
      );
    }
    test('missing and invalid image bytes omit the thumbnail', () async {
      final directory = await Directory.systemTemp.createTemp(
        'invalid-thumbnail-',
      );
      addTearDown(() => directory.delete(recursive: true));
      expect(
        await ImageProcessor.generateInlineThumbnailBytes(
          inputPath: '${directory.path}/absent.jpg',
        ),
        isNull,
      );
      final input = File('${directory.path}/invalid.jpg');
      await input.writeAsString('not an image');
      expect(
        await ImageProcessor.generateInlineThumbnailBytes(
          inputPath: input.path,
        ),
        isNull,
      );
    });
  });

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

    test(
      'calls compress with quality 85 when preference is compressed',
      () async {
        int? capturedQuality;
        final processor = ImageProcessor(
          compressFile:
              ({
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
      },
    );

    test(
      'calls compress with quality 100 when preference is original',
      () async {
        int? capturedQuality;
        final processor = ImageProcessor(
          compressFile:
              ({
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
      },
    );

    test('always passes keepExif: false (compressed)', () async {
      bool? capturedKeepExif;
      final processor = ImageProcessor(
        compressFile:
            ({
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
        compressFile:
            ({
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

    test(
      'returns original path when compress returns null (graceful fallback)',
      () async {
        final processor = ImageProcessor(
          compressFile:
              ({
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
      },
    );

    test('returns original path unchanged for .gif files', () async {
      var compressCalled = false;
      final processor = ImageProcessor(
        compressFile:
            ({
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
    test(
      'calls compress with quality 80, minWidth 512, minHeight 512',
      () async {
        int? capturedQuality;
        int? capturedMinWidth;
        int? capturedMinHeight;
        final processor = ImageProcessor(
          compressFile:
              ({
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
      },
    );

    test('always passes keepExif: false', () async {
      bool? capturedKeepExif;
      final processor = ImageProcessor(
        compressFile:
            ({
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
        compressFile:
            ({
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

    test('TC-200-11: crops a decodable non-square compress output to 512x512 '
        '(NEW file) while leaving the 512-min args unchanged', () async {
      final tempDir = Directory.systemTemp.createTempSync('img_proc_crop');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final input = File('${tempDir.path}/in.jpg')..writeAsBytesSync(<int>[0]);
      final nonSquare = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 1024, height: 512), quality: 90),
      );
      int? capturedMinWidth;
      int? capturedMinHeight;
      final processor = ImageProcessor(
        compressFile:
            ({
              required String path,
              required int quality,
              required bool keepExif,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async {
              capturedMinWidth = minWidth;
              capturedMinHeight = minHeight;
              final out = '${path}_compressed.jpg';
              File(out).writeAsBytesSync(nonSquare, flush: true);
              return XFile(out);
            },
      );

      final outPath = await processor.processAvatar(inputPath: input.path);

      // Crop is a strictly post-compress step: the 512-min contract is intact.
      expect(capturedMinWidth, 512);
      expect(capturedMinHeight, 512);
      final decoded = img.decodeImage(File(outPath).readAsBytesSync())!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
      expect(outPath, isNot('${input.path}_compressed.jpg'));
    });

    test(
      'TC-200-15: unwritten (missing) compress output passes through unchanged',
      () async {
        final processor = ImageProcessor(
          compressFile:
              ({
                required String path,
                required int quality,
                required bool keepExif,
                int minWidth = 1920,
                int minHeight = 1080,
              }) async => XFile('${path}_compressed.jpg'),
        );

        final result = await processor.processAvatar(
          inputPath: '/tmp/missing-avatar.jpg',
        );

        // No throw, no crop — the reported compress path is returned verbatim.
        expect(result, '/tmp/missing-avatar.jpg_compressed.jpg');
      },
    );

    test(
      'TC-200-15: undecodable compress output returns compress path byte-identical',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('img_proc_junk');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final input = File('${tempDir.path}/in.jpg')
          ..writeAsBytesSync(<int>[0]);
        final junk = Uint8List.fromList(<int>[0xCA, 0xFE, 0xBA, 0xBE]);
        final processor = ImageProcessor(
          compressFile:
              ({
                required String path,
                required int quality,
                required bool keepExif,
                int minWidth = 1920,
                int minHeight = 1080,
              }) async {
                final out = '${path}_compressed.jpg';
                File(out).writeAsBytesSync(junk, flush: true);
                return XFile(out);
              },
        );

        final result = await processor.processAvatar(inputPath: input.path);

        expect(result, '${input.path}_compressed.jpg');
        expect(File(result).readAsBytesSync(), junk);
      },
    );
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
    test(
      'stalled compression cancels and late progress cannot revive it',
      () async {
        final pending = Completer<VideoProcessResult?>();
        final cancelled = Completer<void>();
        void Function(double)? progress;
        final processor = ImageProcessor(
          compressVideo: ({required path, required compress, onProgress}) {
            progress = onProgress;
            return pending.future;
          },
          cancelVideoCompression: () async => cancelled.complete(),
          videoStallTimeout: const Duration(milliseconds: 30),
        );

        final result = processor.processVideo(
          inputPath: '/tmp/stalled.mp4',
          quality: ImageQualityPreference.compressed,
        );
        progress?.call(45);
        await expectLater(
          result,
          throwsA(isA<VideoProcessingTimeoutException>()),
        );
        expect(cancelled.isCompleted, isTrue);
        pending.complete(VideoProcessResult(path: '/tmp/late.mp4'));
      },
    );

    test('advancing progress resets the stall deadline', () async {
      final pending = Completer<VideoProcessResult?>();
      void Function(double)? progress;
      var cancelCount = 0;
      final processor = ImageProcessor(
        compressVideo: ({required path, required compress, onProgress}) {
          progress = onProgress;
          return pending.future;
        },
        cancelVideoCompression: () async => cancelCount++,
        videoStallTimeout: const Duration(milliseconds: 300),
      );

      final result = processor.processVideo(
        inputPath: '/tmp/progress.mp4',
        quality: ImageQualityPreference.compressed,
      );
      await Future<void>.delayed(const Duration(milliseconds: 180));
      progress?.call(25);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      pending.complete(VideoProcessResult(path: '/tmp/done.mp4'));
      expect((await result).path, '/tmp/done.mp4');
      expect(cancelCount, 0);
    });

    test(
      'repeated unchanged progress does not keep a stuck job alive',
      () async {
        final pending = Completer<VideoProcessResult?>();
        void Function(double)? progress;
        final processor = ImageProcessor(
          compressVideo: ({required path, required compress, onProgress}) {
            progress = onProgress;
            return pending.future;
          },
          cancelVideoCompression: () async {},
          videoStallTimeout: const Duration(milliseconds: 60),
        );
        final result = processor.processVideo(
          inputPath: '/tmp/stuck.mp4',
          quality: ImageQualityPreference.compressed,
        );
        progress?.call(45);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        progress?.call(45);
        await expectLater(
          result,
          throwsA(isA<VideoProcessingTimeoutException>()),
        );
        pending.complete(null);
      },
    );

    test('a hung cancel call cannot keep the caller blocked', () async {
      final pending = Completer<VideoProcessResult?>();
      final processor = ImageProcessor(
        compressVideo: ({required path, required compress, onProgress}) =>
            pending.future,
        cancelVideoCompression: () => Completer<void>().future,
        videoStallTimeout: const Duration(milliseconds: 20),
        videoCancelTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        processor.processVideo(
          inputPath: '/tmp/stuck.mp4',
          quality: ImageQualityPreference.compressed,
        ),
        throwsA(isA<VideoProcessingTimeoutException>()),
      );
      pending.complete(null);
    });

    test('overall deadline ends a job even while progress advances', () async {
      final pending = Completer<VideoProcessResult?>();
      void Function(double)? progress;
      var cancels = 0;
      final processor = ImageProcessor(
        compressVideo: ({required path, required compress, onProgress}) {
          progress = onProgress;
          return pending.future;
        },
        cancelVideoCompression: () async => cancels++,
        videoStallTimeout: const Duration(milliseconds: 100),
        videoMaxDuration: const Duration(milliseconds: 60),
      );
      final result = processor.processVideo(
        inputPath: '/tmp/endless.mp4',
        quality: ImageQualityPreference.compressed,
      );
      for (var i = 1; i <= 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 15));
        progress?.call(i.toDouble());
      }
      await expectLater(
        result,
        throwsA(isA<VideoProcessingTimeoutException>()),
      );
      expect(cancels, 1);
      pending.complete(null);
    });

    test(
      'default compressor requests native cancellation on a stall',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        const channel = MethodChannel('video_compress');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final nativeResult = Completer<String?>();
        var cancelCalls = 0;
        messenger.setMockMethodCallHandler(channel, (call) {
          if (call.method == 'compressVideo') return nativeResult.future;
          if (call.method == 'cancelCompression') {
            cancelCalls++;
            return Future<void>.value();
          }
          throw StateError('Unexpected native method: ${call.method}');
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        final processor = ImageProcessor(
          videoStallTimeout: const Duration(milliseconds: 20),
        );
        await expectLater(
          processor.processVideo(
            inputPath: '/tmp/native-stall.mp4',
            quality: ImageQualityPreference.compressed,
          ),
          throwsA(isA<VideoProcessingTimeoutException>()),
        );
        expect(cancelCalls, 1);
        nativeResult.complete(null);
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'an unsettled native stall refuses another video until it settles',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        const channel = MethodChannel('video_compress');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final firstNativeResult = Completer<String?>();
        var compressCalls = 0;
        messenger.setMockMethodCallHandler(channel, (call) {
          if (call.method == 'compressVideo') {
            compressCalls++;
            return compressCalls == 1
                ? firstNativeResult.future
                : Future.value('{"path":"/tmp/processed.mp4"}');
          }
          if (call.method == 'cancelCompression') return Future.value(false);
          throw StateError('Unexpected native method: ${call.method}');
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        final processor = ImageProcessor(
          videoStallTimeout: const Duration(milliseconds: 20),
        );
        await expectLater(
          processor.processVideo(
            inputPath: '/tmp/first.mp4',
            quality: ImageQualityPreference.compressed,
          ),
          throwsA(isA<VideoProcessingTimeoutException>()),
        );
        await expectLater(
          processor.processVideo(
            inputPath: '/tmp/next.mp4',
            quality: ImageQualityPreference.compressed,
          ),
          throwsA(isA<VideoProcessingUnavailableException>()),
        );
        expect(compressCalls, 1);

        firstNativeResult.complete(null);
        await Future<void>.delayed(Duration.zero);
        await processor.processVideo(
          inputPath: '/tmp/after-settlement.mp4',
          quality: ImageQualityPreference.compressed,
        );
        expect(compressCalls, 2);
      },
    );

    test(
      'a missing native channel releases the compressor for a later video',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        const channel = MethodChannel('video_compress');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        var compressCalls = 0;
        messenger.setMockMethodCallHandler(channel, null);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        final processor = ImageProcessor();
        await expectLater(
          processor.processVideo(
            inputPath: '/tmp/failed.mp4',
            quality: ImageQualityPreference.compressed,
          ),
          throwsA(isA<MissingPluginException>()),
        );
        messenger.setMockMethodCallHandler(channel, (call) {
          if (call.method != 'compressVideo') {
            throw StateError('Unexpected native method: ${call.method}');
          }
          compressCalls++;
          return Future.value('{"path":"/tmp/processed.mp4"}');
        });
        await processor.processVideo(
          inputPath: '/tmp/later.mp4',
          quality: ImageQualityPreference.compressed,
        );
        expect(compressCalls, 1);
      },
    );
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

    test(
      'calls compressVideo with compress: true when preference is compressed',
      () async {
        bool? capturedCompress;
        final processor = ImageProcessor(
          compressFile: _noOpCompress,
          compressVideo:
              ({
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
      },
    );

    test(
      'calls compressVideo with compress: false when preference is original',
      () async {
        bool? capturedCompress;
        final processor = ImageProcessor(
          compressFile: _noOpCompress,
          compressVideo:
              ({
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
      },
    );

    test('returns processed path from CompressVideoFn result', () async {
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo:
            ({
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

    test(
      'returns width, height, durationMs from CompressVideoFn result',
      () async {
        final processor = ImageProcessor(
          compressFile: _noOpCompress,
          compressVideo:
              ({
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
      },
    );

    test(
      'returns null metadata when CompressVideoFn provides null metadata',
      () async {
        final processor = ImageProcessor(
          compressFile: _noOpCompress,
          compressVideo:
              ({
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
      },
    );

    test('does not attach the source when video compression fails', () async {
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo:
            ({
              required String path,
              required bool compress,
              void Function(double)? onProgress,
            }) async {
              return null;
            },
      );

      await expectLater(
        processor.processVideo(
          inputPath: '/tmp/video.mp4',
          quality: ImageQualityPreference.compressed,
        ),
        throwsA(isA<VideoProcessingFailedException>()),
      );
    });

    test('passes onProgress to CompressVideoFn', () async {
      final receivedProgress = <double>[];
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo:
            ({
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

    test('processVideo watches progress without a caller callback', () async {
      final processor = ImageProcessor(
        compressFile: _noOpCompress,
        compressVideo:
            ({
              required String path,
              required bool compress,
              void Function(double)? onProgress,
            }) async {
              // The watchdog still observes progress when the caller does not.
              expect(onProgress, isNotNull);
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

// Host replacement for the native raster encoder. Match the plugin's no-upscale
// sizing contract, then inspect real encoded output dimensions. Native codecs,
// orientation and metadata removal still need device proof.
class _DimensionImageCompressor extends FlutterImageCompressPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  int? quality;
  bool? keepExif;
  bool? autoCorrectionAngle;

  @override
  Future<XFile?> compressAndGetFile(
    String path,
    String targetPath, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
    int numberOfRetries = 5,
  }) async {
    this.quality = quality;
    this.keepExif = keepExif;
    this.autoCorrectionAngle = autoCorrectionAngle;
    final source = img.decodeImage(await File(path).readAsBytes())!;
    final scale = math.max(
      1.0,
      math.min(source.width / minWidth, source.height / minHeight),
    );
    final resized = img.copyResize(
      source,
      width: (source.width / scale).toInt(),
      height: (source.height / scale).toInt(),
    );
    await File(
      targetPath,
    ).writeAsBytes(img.encodeJpg(resized, quality: quality));
    return XFile(targetPath);
  }
}
