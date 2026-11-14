import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_app/features/stickers/application/animated_sticker_codec.dart';

const _side = 512;
const _bytesPerFrame = _side * _side * 4;

Uint8List _frame(int phase, {bool cornerCanary = false}) {
  final bytes = Uint8List(_bytesPerFrame);
  for (var y = 0; y < _side; y++) {
    for (var x = 0; x < _side; x++) {
      final offset = 4 * (y * _side + x);
      final moving =
          x >= 40 + phase * 10 && x < 160 + phase * 10 && y >= 130 && y < 290;
      final canary = cornerCanary && x < 28 && y < 28;
      bytes[offset] = canary
          ? 221
          : moving
          ? 230
          : 24;
      bytes[offset + 1] = canary
          ? 173
          : moving
          ? 90
          : 64;
      bytes[offset + 2] = canary
          ? 79
          : moving
          ? 42
          : 180;
      bytes[offset + 3] = 255;
    }
  }
  return bytes;
}

List<num> _pixel(img.Image image, int x, int y) {
  final pixel = image.getPixel(x, y);
  return [pixel.r, pixel.g, pixel.b, pixel.a];
}

Matcher _failure(AnimatedStickerCodecFailure failure) =>
    isA<AnimatedStickerCodecException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );

void main() {
  test('samples the entire bounded clip without an end-of-file seek', () {
    final samples = stickerAnimationSampleTimes(2000);
    expect(samples.length, 24);
    expect(samples.first, 0);
    expect(samples.last, 1917);
    expect(stickerAnimationSampleTimes(160), [0, 80]);
    expect(
      () => stickerAnimationSampleTimes(2001),
      throwsA(_failure(AnimatedStickerCodecFailure.invalidInput)),
    );
  });

  test('rejects a wrong frame count, short RGBA frame, or wrong overlay', () {
    final frame = _frame(0);
    for (final (frames, overlay) in [
      (<Uint8List>[frame], null),
      (<Uint8List>[frame, Uint8List(12)], null),
      (<Uint8List>[frame, frame], Uint8List(12)),
    ]) {
      expect(
        () => encodeStickerAnimation(
          croppedFrames: frames,
          durationMs: 160,
          circle: false,
          textOverlay: overlay,
        ),
        throwsA(_failure(AnimatedStickerCodecFailure.invalidInput)),
      );
    }
  });

  test('produces a bounded real loop and a static first-frame poster', () {
    final frames = List.generate(24, _frame);
    final overlay = Uint8List(_bytesPerFrame);
    const p = 4 * (330 * _side + 300);
    overlay.setAll(p, [240, 40, 20, 128]);
    final encoded = encodeStickerAnimation(
      croppedFrames: frames,
      durationMs: 2000,
      circle: false,
      textOverlay: overlay,
    );
    expect(encoded.webp.length, lessThanOrEqualTo(524288));
    expect(encoded.poster.length, lessThanOrEqualTo(262144));
    final decoder = img.WebPDecoder();
    final info = decoder.startDecode(encoded.webp)!;
    expect((info.width, info.height, info.numFrames), (512, 512, 24));
    expect(info.animLoopCount, 0);
    expect(info.frames.fold<int>(0, (ms, frame) => ms + frame.duration), 2000);
    expect(info.iccp, isNull);
    expect(info.exif, isEmpty);
    expect(info.xmp, isEmpty);
    expect(
      _pixel(decoder.decodeFrame(0)!, 80, 200),
      isNot(_pixel(decoder.decodeFrame(23)!, 80, 200)),
    );
    final poster = img.decodeWebP(encoded.poster)!;
    expect(poster.hasAnimation, isFalse);
    expect(_pixel(poster, 300, 330), [132, 52, 100, 255]);
    expect(_pixel(poster, 80, 200), [230, 90, 42, 255]);
  });

  test(
    'circle output discards hidden source pixels and decodes with zero RGB',
    () {
      EncodedStickerAnimation export(bool canary) => encodeStickerAnimation(
        croppedFrames: [
          _frame(0, cornerCanary: canary),
          _frame(4, cornerCanary: canary),
        ],
        durationMs: 160,
        circle: true,
      );
      final baseline = export(false);
      final changedHiddenPixels = export(true);
      expect(changedHiddenPixels.webp, baseline.webp);
      expect(changedHiddenPixels.poster, baseline.poster);
      final decoder = img.WebPDecoder();
      final info = decoder.startDecode(baseline.webp)!;
      expect(info.hasAlpha, isTrue);
      for (var i = 0; i < info.numFrames; i++) {
        final frame = decoder.decodeFrame(i)!;
        expect(_pixel(frame, 0, 0), [0, 0, 0, 0]);
        expect(frame.getPixel(256, 256).a, 255);
        expect(
          frame.any((p) => p.a == 0 && (p.r != 0 || p.g != 0 || p.b != 0)),
          isFalse,
        );
      }
      final poster = img.decodeWebP(baseline.poster)!;
      expect(poster.hasAnimation, isFalse);
      expect(_pixel(poster, 0, 0), [0, 0, 0, 0]);
    },
  );

  test('refuses a clip that cannot fit the actual animation byte cap', () {
    final random = Random(1742);
    final noise = Uint8List(_bytesPerFrame);
    for (var i = 0; i < noise.length; i += 4) {
      noise[i] = random.nextInt(256);
      noise[i + 1] = random.nextInt(256);
      noise[i + 2] = random.nextInt(256);
      noise[i + 3] = 255;
    }
    expect(
      () => encodeStickerAnimation(
        croppedFrames: List.filled(24, noise),
        durationMs: 2000,
        circle: false,
      ),
      throwsA(_failure(AnimatedStickerCodecFailure.budgetExceeded)),
    );
  });
}
