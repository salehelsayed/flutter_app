import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

/// Plan 200 — the canonical avatar contract must center-square non-square picks
/// after compress, while leaving every failure/undecodable/already-square path
/// byte-identical (so the many fake-compressor locks stay green).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avatar_norm_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Uint8List solidJpeg(int width, int height) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(60, 120, 200));
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  /// A fake compressor that writes [bytes] to `${path}_compressed.jpg`.
  ImageProcessor processorWriting(Uint8List bytes) {
    return ImageProcessor(
      compressFile:
          ({
            required String path,
            required int quality,
            required bool keepExif,
            int minWidth = 1920,
            int minHeight = 1080,
          }) async {
            final out = '${path}_compressed.jpg';
            File(out).writeAsBytesSync(bytes, flush: true);
            return XFile(out);
          },
    );
  }

  ImageProcessor processorReturningNull() {
    return ImageProcessor(
      compressFile:
          ({
            required String path,
            required int quality,
            required bool keepExif,
            int minWidth = 1920,
            int minHeight = 1080,
          }) async => null,
    );
  }

  /// Returns a compress path but never writes the file (missing-output shape).
  ImageProcessor processorUnwritten() {
    return ImageProcessor(
      compressFile:
          ({
            required String path,
            required int quality,
            required bool keepExif,
            int minWidth = 1920,
            int minHeight = 1080,
          }) async => XFile('${path}_compressed.jpg'),
    );
  }

  test(
    'TC-200-08: non-square input commits a 512x512 square jpeg in a NEW file',
    () async {
      final input = File('${tempDir.path}/in.jpg')..writeAsBytesSync(<int>[0]);
      final helper = AvatarNormalizationHelper(
        imageProcessor: processorWriting(solidJpeg(1024, 512)),
      );

      final outPath = await helper.prepareAvatar(inputPath: input.path);

      expect(outPath, isNot(input.path));
      // NEW file: not the compress output, so the crop wrote its own artifact.
      expect(outPath, isNot('${input.path}_compressed.jpg'));
      final decoded = img.decodeImage(File(outPath).readAsBytesSync())!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
    },
  );

  test(
    'TC-200-09: square input is passed through untouched (width==height skip)',
    () async {
      final input = File('${tempDir.path}/in.jpg')..writeAsBytesSync(<int>[0]);
      final squareBytes = solidJpeg(512, 512);
      final helper = AvatarNormalizationHelper(
        imageProcessor: processorWriting(squareBytes),
      );

      final outPath = await helper.prepareAvatar(inputPath: input.path);

      // The square-skip guard must NOT re-encode an already-square image: the
      // compress output is returned verbatim (no new file, byte-identical). This
      // locks the guard that keeps decodable-square fixtures byte-identical
      // downstream (pass_post_along oversized-omit, post_pass smoke). Dropping
      // the width==height skip -> a `.square.jpg` re-encode -> both asserts red.
      expect(outPath, '${input.path}_compressed.jpg');
      expect(File(outPath).readAsBytesSync(), squareBytes);
      final decoded = img.decodeImage(File(outPath).readAsBytesSync())!;
      expect(decoded.width, decoded.height);
      expect(decoded.width, 512);
    },
  );

  test(
    'TC-200-10: compress-null path returns StateError and skips crop',
    () async {
      final helper = AvatarNormalizationHelper(
        imageProcessor: processorReturningNull(),
      );

      expect(
        () => helper.prepareAvatar(inputPath: '${tempDir.path}/in.jpg'),
        throwsStateError,
      );
    },
  );

  test(
    'TC-200-15: undecodable compress output passes through byte-identical (crop skipped)',
    () async {
      final input = File('${tempDir.path}/in.jpg')..writeAsBytesSync(<int>[0]);
      final junk = Uint8List.fromList(<int>[0xCA, 0xFE, 0xBA, 0xBE]);
      final helper = AvatarNormalizationHelper(
        imageProcessor: processorWriting(junk),
      );

      final outPath = await helper.prepareAvatar(inputPath: input.path);

      // Undecodable -> crop skipped -> the compress output is returned intact.
      expect(outPath, '${input.path}_compressed.jpg');
      expect(File(outPath).readAsBytesSync(), junk);
    },
  );

  test(
    'TC-200-15: missing compress output still throws StateError (contract unchanged)',
    () async {
      final helper = AvatarNormalizationHelper(
        imageProcessor: processorUnwritten(),
      );

      expect(
        () => helper.prepareAvatar(inputPath: '${tempDir.path}/in.jpg'),
        throwsStateError,
      );
    },
  );
}
