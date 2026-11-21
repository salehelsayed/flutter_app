import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

// Reproduce the center crop and bilinear resize of moving 720x480 footage.
void _writeTexturedFrame(Uint8List pixels, int index, int timeMs) {
  const cropLeft = 120;
  const cropSize = 480;
  final source = Uint8List(cropSize * cropSize * 4);
  for (var y = 0; y < cropSize; y++) {
    for (var x = 0; x < cropSize; x++) {
      final offset = 4 * (y * cropSize + x);
      final sourceX = x + cropLeft;
      final panX = sourceX + timeMs ~/ 45;
      final tile = ((panX ~/ 17) * 13 + (y ~/ 11) * 23) % 35;
      final grain = ((panX * 31) ^ (y * 73) ^ (panX * y * 17)) & 15;
      final dx = sourceX - 300 - index * 4;
      final dy = y - 240 + index * 2;
      final subject = dx * dx * 2 + dy * dy < 13456;
      source[offset] = (subject ? 130 : 32) + panX ~/ 14 + tile + grain;
      source[offset + 1] = (subject ? 68 : 65) + y ~/ 7 + tile + grain;
      source[offset + 2] =
          (subject ? 39 : 89) + (panX + y) ~/ 17 + tile + grain;
    }
  }

  num position(int pixel) =>
      ((pixel + 0.5) * cropSize / _side - 0.5).clamp(0.0, cropSize - 1.0);
  for (var y = 0; y < _side; y++) {
    final sy = position(y);
    final y0 = sy.floor();
    final y1 = min(y0 + 1, cropSize - 1);
    final wy = sy - y0;
    for (var x = 0; x < _side; x++) {
      final sx = position(x);
      final x0 = sx.floor();
      final x1 = min(x0 + 1, cropSize - 1);
      final wx = sx - x0;
      final a = 4 * (y0 * cropSize + x0);
      final b = 4 * (y0 * cropSize + x1);
      final c = 4 * (y1 * cropSize + x0);
      final d = 4 * (y1 * cropSize + x1);
      final offset = 4 * (y * _side + x);
      for (var channel = 0; channel < 3; channel++) {
        final top = source[a + channel] * (1 - wx) + source[b + channel] * wx;
        final bottom =
            source[c + channel] * (1 - wx) + source[d + channel] * wx;
        pixels[offset + channel] = (top * (1 - wy) + bottom * wy).round();
      }
      pixels[offset + 3] = 255;
    }
  }
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

  test('Flutter engine decodes distinct animated WebP frames', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final encoded = encodeStickerAnimation(
      croppedFrames: [_frame(0), _frame(5)],
      durationMs: 160,
      circle: true,
    );
    const deadline = Duration(seconds: 3);
    final codec = await ui
        .instantiateImageCodec(encoded.webp)
        .timeout(deadline);
    final frames = <ui.Image>[];
    try {
      expect(codec.frameCount, 2);
      for (var index = 0; index < 2; index++) {
        final frame = await codec.getNextFrame().timeout(deadline);
        frames.add(frame.image);
        expect(frame.duration, const Duration(milliseconds: 80));
      }

      const interiorOffset = 4 * (200 * _side + 80);
      final first = (await frames[0].toByteData().timeout(deadline))!;
      final last = (await frames[1].toByteData().timeout(deadline))!;
      expect(first.getUint32(interiorOffset), 0xe65a2aff);
      expect(last.getUint32(interiorOffset), 0x1840b4ff);
      expect(first.getUint32(0), 0);
      expect(last.getUint32(0), 0);
    } finally {
      for (final frame in frames) {
        frame.dispose();
      }
      codec.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 10)));

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

  test('fits a textured circular camera clip in the animation budget', () {
    const durationMs = 2000;
    const side = 192;
    final samples = stickerAnimationSampleTimes(durationMs);
    final frameBuffer = Uint8List(samples.length * _bytesPerFrame);
    final frames = <Uint8List>[];
    for (final (index, timeMs) in samples.indexed) {
      final frame = Uint8List.sublistView(
        frameBuffer,
        index * _bytesPerFrame,
        (index + 1) * _bytesPerFrame,
      );
      _writeTexturedFrame(frame, index, timeMs);
      frames.add(frame);
    }

    // The center output pixel averages the 2x2 source region beginning
    // at (256,256). Only one overlay pixel there has visible red.
    final overlay = Uint8List(_bytesPerFrame);
    final cameraRgbSums = [0, 0, 0];
    for (var y = 256; y < 258; y++) {
      for (var x = 256; x < 258; x++) {
        final offset = 4 * (y * _side + x);
        overlay.setAll(offset, [0, 255, 0, 0]);
        for (var channel = 0; channel < 3; channel++) {
          cameraRgbSums[channel] += frames.first[offset + channel];
        }
      }
    }
    overlay.setAll(4 * (256 * _side + 256), [255, 0, 0, 255]);

    final encoded = encodeStickerAnimation(
      croppedFrames: frames,
      durationMs: durationMs,
      circle: true,
      textOverlay: overlay,
    );

    expect(encoded.webp.length, lessThanOrEqualTo(512 * 1024));
    expect(encoded.poster.length, lessThanOrEqualTo(256 * 1024));
    final decoder = img.WebPDecoder();
    final info = decoder.startDecode(encoded.webp)!;
    expect((info.width, info.height, info.numFrames), (side, side, 16));
    expect((encoded.frameCount, encoded.durationMs), (16, durationMs));
    expect(
      info.frames.fold<int>(0, (ms, frame) => ms + frame.duration),
      durationMs,
    );
    expect(info.animLoopCount, 0);
    expect(info.hasAlpha, isTrue);
    final first = decoder.decodeFrame(0)!;
    final last = decoder.decodeFrame(info.numFrames - 1)!;
    expect(
      _pixel(first, side ~/ 4, side ~/ 2),
      isNot(_pixel(last, side ~/ 4, side ~/ 2)),
    );
    const overlayAlpha = 255 ~/ 4;
    int blendCenter(int channel) {
      final camera = cameraRgbSums[channel] ~/ 4;
      final text = channel == 0 ? 255 : 0;
      return (text * overlayAlpha + camera * (255 - overlayAlpha) + 127) ~/ 255;
    }

    final expectedCenter = [
      blendCenter(0),
      blendCenter(1),
      blendCenter(2),
      255,
    ];
    expect(_pixel(first, side ~/ 2, side ~/ 2), expectedCenter);
    for (var i = 0; i < info.numFrames; i++) {
      final frame = decoder.decodeFrame(i)!;
      expect(_pixel(frame, 0, 0), [0, 0, 0, 0]);
      expect(frame.getPixel(side ~/ 2, side ~/ 2).a, 255);
      expect(
        frame.any((p) => p.a == 0 && (p.r != 0 || p.g != 0 || p.b != 0)),
        isFalse,
      );
    }
    final poster = img.decodeWebP(encoded.poster)!;
    expect(
      (poster.width, poster.height, poster.hasAnimation),
      (side, side, false),
    );
    expect(_pixel(poster, side ~/ 2, side ~/ 2), expectedCenter);
    expect(_pixel(poster, 0, 0), [0, 0, 0, 0]);
  }, timeout: const Timeout(Duration(minutes: 2)));

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
