import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

void main() {
  group('preparePendingComposerMedia', () {
    test('uses raw bytes for original-quality images', () async {
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
      expect(prepared.budgetBytes, 10);
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
  });
}
