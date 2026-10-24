import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

void main() {
  group('preparePendingComposerMedia', () {
    test(
      'failed preference reads retain fallback and complete image/video preparation',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'quality-read-fallback-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final image = File('${root.path}/source.jpg')
          ..writeAsStringSync('image bytes');
        final video = File('${root.path}/source.mp4')
          ..writeAsStringSync('video bytes');
        final imageRequests = <int>[];
        final videoRequests = <bool>[];
        final processor = ImageProcessor(
          loadImageQualityPreference: () async =>
              throw StateError('private-keychain-error'),
          loadVideoQualityPreference: () async =>
              throw StateError('private-keychain-error'),
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                imageRequests.add(quality);
                return XFile(path);
              },
          compressVideo:
              ({required path, required compress, onProgress}) async {
                videoRequests.add(compress);
                return VideoProcessResult(path: path);
              },
        );
        for (final fallback in ImageQualityPreference.values) {
          for (final source in [image, video]) {
            final prepared = await preparePendingComposerMedia(
              inputPath: source.path,
              imageProcessor: processor,
              imageQualityPreference: fallback,
              videoQualityPreference: fallback,
            );
            expect(prepared.file.path, source.path);
            expect(prepared.budgetBytes, source.lengthSync());
            expect(await prepared.file.readAsBytes(), source.readAsBytesSync());
          }
        }
        expect(imageRequests, [85, 100]);
        expect(videoRequests, [true, false]);
        final failures = events
            .where(
              (event) =>
                  event['event'] == 'MEDIA_QUALITY_PREFERENCE_READ_FAILED',
            )
            .toList();
        expect(
          failures,
          hasLength(4),
          reason: 'one diagnostic per failed load',
        );
        expect(failures.map((event) => event['details']), [
          {'mediaType': 'image'},
          {'mediaType': 'video'},
          {'mediaType': 'image'},
          {'mediaType': 'video'},
        ]);
        expect(failures.toString(), isNot(contains('private-keychain-error')));
        expect(failures.toString(), isNot(contains(root.path)));
      },
    );

    test(
      'saved Original applies to default entry values; explicit compression still wins',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'live-quality-pending-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final input = File('${root.path}/source.jpg')
          ..writeAsStringSync('photo');
        final requested = <int>[];
        final processor = ImageProcessor(
          loadImageQualityPreference: () async =>
              ImageQualityPreference.original,
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                requested.add(quality);
                return XFile(input.path);
              },
        );
        for (final stored in [true, false]) {
          await preparePendingComposerMedia(
            inputPath: input.path,
            imageProcessor: processor,
            imageQualityPreference: ImageQualityPreference.compressed,
            videoQualityPreference: ImageQualityPreference.compressed,
            useStoredPreferences: stored,
          );
        }
        expect(requested, [100, 85]);
      },
    );

    test('uses processed bytes for original-quality images', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'pending_composer_media_original_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final sourceFile = File('${tempDir.path}/source.jpg')
        ..writeAsStringSync('1234567890');
      final processedFile = File('${tempDir.path}/processed.jpg')
        ..writeAsStringSync('12');

      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => XFile(processedFile.path),
        compressVideo: ({required path, required compress, onProgress}) async =>
            null,
      );

      final prepared = await preparePendingComposerMedia(
        inputPath: sourceFile.path,
        imageProcessor: processor,
        imageQualityPreference: ImageQualityPreference.original,
        videoQualityPreference: ImageQualityPreference.compressed,
      );

      expect(prepared.file.path, processedFile.path);
      expect(prepared.budgetBytes, 2);
    });

    test('uses processed bytes for compressed-quality images', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'pending_composer_media_compressed_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final sourceFile = File('${tempDir.path}/source.jpg')
        ..writeAsStringSync('1234567890');
      final processedFile = File('${tempDir.path}/processed.jpg')
        ..writeAsStringSync('1234');

      final processor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => XFile(processedFile.path),
        compressVideo: ({required path, required compress, onProgress}) async =>
            null,
      );

      final prepared = await preparePendingComposerMedia(
        inputPath: sourceFile.path,
        imageProcessor: processor,
        imageQualityPreference: ImageQualityPreference.compressed,
        videoQualityPreference: ImageQualityPreference.compressed,
      );

      expect(prepared.file.path, processedFile.path);
      expect(prepared.budgetBytes, 4);
    });

    for (final quality in ImageQualityPreference.values) {
      test('uses processed bytes for ${quality.name}-quality videos', () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'pending_composer_media_video_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final sourceFile = File('${tempDir.path}/source.mov')
          ..writeAsStringSync('1234567890');
        final processedFile = File('${tempDir.path}/processed.mp4')
          ..writeAsStringSync('1234');
        final processor = ImageProcessor(
          compressVideo:
              ({required path, required compress, onProgress}) async {
                expect(path, sourceFile.path);
                expect(compress, quality == ImageQualityPreference.compressed);
                return VideoProcessResult(
                  path: processedFile.path,
                  width: 320,
                  height: 240,
                  durationMs: 1000,
                );
              },
        );
        final prepared = await preparePendingComposerMedia(
          inputPath: sourceFile.path,
          imageProcessor: processor,
          imageQualityPreference: ImageQualityPreference.compressed,
          videoQualityPreference: quality,
        );
        expect(prepared.file.path, processedFile.path);
        expect(prepared.budgetBytes, 4);
        expect(prepared.width, 320);
        expect(prepared.height, 240);
        expect(prepared.durationMs, 1000);
      });
    }
  });
}
