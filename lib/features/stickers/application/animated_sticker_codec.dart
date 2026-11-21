import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const stickerAnimationSide = 512;
const stickerAnimationFrameBytes =
    stickerAnimationSide * stickerAnimationSide * 4;
const _maxDurationMs = 2000;
const _animatedBytes = 512 * 1024;
const _posterBytes = 256 * 1024;
const _targetFps = 12;

enum AnimatedStickerCodecFailure { invalidInput, budgetExceeded }

final class AnimatedStickerCodecException implements Exception {
  const AnimatedStickerCodecException(this.failure);

  final AnimatedStickerCodecFailure failure;
}

typedef EncodedStickerAnimation = ({
  Uint8List webp,
  Uint8List poster,
  int side,
  int frameCount,
  int durationMs,
});

List<int> stickerAnimationSampleTimes(int durationMs) {
  if (durationMs < 2 || durationMs > _maxDurationMs) {
    throw const AnimatedStickerCodecException(
      AnimatedStickerCodecFailure.invalidInput,
    );
  }
  final count = _frameCount(durationMs, _targetFps);
  return List.generate(count, (i) => _boundary(i, count, durationMs));
}

typedef _Profile = ({int fps, int quality, int rgbBits, int side});

const _opaqueProfiles = <_Profile>[
  (fps: 12, quality: 70, rgbBits: 8, side: stickerAnimationSide),
  (fps: 12, quality: 45, rgbBits: 8, side: stickerAnimationSide),
  (fps: 8, quality: 55, rgbBits: 8, side: stickerAnimationSide),
  (fps: 6, quality: 45, rgbBits: 8, side: stickerAnimationSide),
];

// Lossy color can reconstruct RGB under zero alpha even if the input
// had been cleared. Preserve alpha and the cleared pixels with VP8L.
const _circleProfiles = <_Profile>[
  (fps: 12, quality: 100, rgbBits: 8, side: stickerAnimationSide),
  (fps: 12, quality: 100, rgbBits: 5, side: stickerAnimationSide),
  (fps: 8, quality: 100, rgbBits: 5, side: stickerAnimationSide),
  (fps: 6, quality: 100, rgbBits: 4, side: stickerAnimationSide),
  (fps: 8, quality: 100, rgbBits: 8, side: 192),
];

/// Encodes already cropped, orientation-corrected camera frames. The caller
/// invokes this CPU-bound function on a worker and owns all supplied buffers.
EncodedStickerAnimation encodeStickerAnimation({
  required List<Uint8List> croppedFrames,
  required int durationMs,
  required bool circle,
  Uint8List? textOverlay,
}) {
  final sampleCount = stickerAnimationSampleTimes(durationMs).length;
  if (croppedFrames.length != sampleCount ||
      croppedFrames.any(
        (frame) => frame.length != stickerAnimationFrameBytes,
      ) ||
      (textOverlay != null &&
          textOverlay.length != stickerAnimationFrameBytes)) {
    throw const AnimatedStickerCodecException(
      AnimatedStickerCodecFailure.invalidInput,
    );
  }

  final profiles = circle ? _circleProfiles : _opaqueProfiles;
  for (final profile in profiles) {
    final side = profile.side;
    final overlay = textOverlay == null
        ? null
        : _resizeRgba(textOverlay, side, alphaAware: true);
    final firstSource = _resizeRgba(croppedFrames.first, side);
    final frameCount = _frameCount(durationMs, profile.fps);
    img.Image composeFrame(int i) {
      // Reuse the captured sampling grid for every attempt.
      final sourceIndex = i * sampleCount ~/ frameCount;
      return _compose(
          i == 0 ? firstSource : _resizeRgba(croppedFrames[sourceIndex], side),
          overlay: overlay,
          side: side,
          circle: circle,
          rgbBits: profile.rgbBits,
        )
        ..frameDuration =
            _boundary(i + 1, frameCount, durationMs) -
            _boundary(i, frameCount, durationMs);
    }

    final firstFrame = composeFrame(0);
    final encoded = _encodeBoundedWebP(
      frames: Iterable.generate(
        frameCount,
        (i) => i == 0 ? firstFrame : composeFrame(i),
      ),
      side: side,
      hasAlpha: circle,
      encoder: img.WebPEncoder(
        lossless: circle,
        exact: false,
        quality: profile.quality,
        method: 0,
      ),
    );
    if (encoded == null) continue;

    return (
      webp: encoded.animation,
      poster: _encodePoster(
        firstFrame,
        encodedFirstFrame: circle ? encoded.firstFrame : null,
        source: firstSource,
        overlay: overlay,
        side: side,
        circle: circle,
        rgbBits: profile.rgbBits,
      ),
      side: side,
      frameCount: frameCount,
      durationMs: durationMs,
    );
  }
  throw const AnimatedStickerCodecException(
    AnimatedStickerCodecFailure.budgetExceeded,
  );
}

({Uint8List animation, Uint8List firstFrame})? _encodeBoundedWebP({
  required Iterable<img.Image> frames,
  required int side,
  required bool hasAlpha,
  required img.WebPEncoder encoder,
}) {
  const riffHeaderBytes = 12;
  const animationHeaderBytes = 44; // RIFF header, VP8X and ANIM.
  const frameHeaderBytes = 24; // ANMF chunk header and frame fields.
  final header = img.OutputBuffer(size: animationHeaderBytes)
    ..writeBytes('RIFF'.codeUnits)
    ..writeUint32(0) // Filled with the exact file size after the final frame.
    ..writeBytes('WEBPVP8X'.codeUnits)
    ..writeUint32(10)
    ..writeUint32(hasAlpha ? 0x12 : 0x02); // Animation and optional alpha.
  _writeUint24(header, side - 1);
  _writeUint24(header, side - 1);
  header
    ..writeBytes('ANIM'.codeUnits)
    ..writeUint32(6)
    ..writeUint32(0) // Transparent background.
    ..writeUint16(0); // Loop forever.
  final animation = BytesBuilder(copy: false)..add(header.getBytes());

  Uint8List? firstFrame;
  for (final frame in frames) {
    // These composed frames have no metadata. The standalone encoder writes
    // one padded VP8 or VP8L chunk after the RIFF header.
    final still = encoder.encode(frame, singleFrame: true);
    final bitstream = Uint8List.sublistView(still, riffHeaderBytes);
    final fileBytes = animation.length + frameHeaderBytes + bitstream.length;
    if (fileBytes > _animatedBytes) return null;

    firstFrame ??= still;
    final frameHeader = img.OutputBuffer(size: frameHeaderBytes)
      ..writeBytes('ANMF'.codeUnits)
      ..writeUint32(frameHeaderBytes - 8 + bitstream.length)
      ..writeUint32(0) // Top-left frame offset (two uint24 fields).
      ..writeUint16(0);
    _writeUint24(frameHeader, side - 1);
    _writeUint24(frameHeader, side - 1);
    _writeUint24(frameHeader, frame.frameDuration);
    frameHeader.writeByte(3); // Replace the canvas, then clear to background.
    animation
      ..add(frameHeader.getBytes())
      ..add(bitstream);
  }

  final bytes = animation.takeBytes();
  ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);
  return (animation: bytes, firstFrame: firstFrame!);
}

void _writeUint24(img.OutputBuffer out, int value) {
  out
    ..writeUint16(value & 0xffff)
    ..writeByte(value >> 16);
}

int _frameCount(int durationMs, int fps) =>
    math.max(2, (durationMs * fps + 999) ~/ 1000);

int _boundary(int i, int count, int durationMs) =>
    (i * durationMs + count ~/ 2) ~/ count;

// Resize the source and text before applying the circle mask.
Uint8List _resizeRgba(Uint8List pixels, int side, {bool alphaAware = false}) {
  if (side == stickerAnimationSide) return pixels;
  final source = img.Image.fromBytes(
    width: stickerAnimationSide,
    height: stickerAnimationSide,
    bytes: pixels.buffer,
    bytesOffset: pixels.offsetInBytes,
    order: img.ChannelOrder.rgba,
  );
  if (alphaAware) {
    for (final pixel in source) {
      final alpha = pixel.a.toInt();
      pixel.setRgba(
        (pixel.r.toInt() * alpha + 127) ~/ 255,
        (pixel.g.toInt() * alpha + 127) ~/ 255,
        (pixel.b.toInt() * alpha + 127) ~/ 255,
        alpha,
      );
    }
  }
  final resized = img.copyResize(
    source,
    width: side,
    height: side,
    interpolation: img.Interpolation.average,
  );
  if (alphaAware) {
    for (final pixel in resized) {
      final alpha = pixel.a.toInt();
      if (alpha == 0) continue;
      int unpremultiply(num channel) =>
          math.min(255, (channel.toInt() * 255 + alpha ~/ 2) ~/ alpha);
      pixel.setRgba(
        unpremultiply(pixel.r),
        unpremultiply(pixel.g),
        unpremultiply(pixel.b),
        alpha,
      );
    }
  }
  return resized.getBytes(order: img.ChannelOrder.rgba);
}

img.Image _compose(
  Uint8List source, {
  required Uint8List? overlay,
  required int side,
  required bool circle,
  required int rgbBits,
}) {
  final pixels = Uint8List.fromList(source);
  final levels = (1 << rgbBits) - 1;
  final radius = side / 2;
  final innerRadius2 = (radius - 0.5) * (radius - 0.5);
  final outerRadius2 = (radius + 0.5) * (radius + 0.5);
  for (var y = 0; y < side; y++) {
    final dy = y + 0.5 - radius;
    for (var x = 0; x < side; x++) {
      final p = 4 * (y * side + x);
      final overlayAlpha = overlay?[p + 3] ?? 0;
      if (overlayAlpha != 0) {
        for (var channel = 0; channel < 3; channel++) {
          pixels[p + channel] =
              (overlay![p + channel] * overlayAlpha +
                  pixels[p + channel] * (255 - overlayAlpha) +
                  127) ~/
              255;
        }
      }
      var alpha = 255; // Camera pixels are opaque before the crop mask.
      if (circle) {
        final dx = x + 0.5 - radius;
        final distance2 = dx * dx + dy * dy;
        if (distance2 >= outerRadius2) {
          alpha = 0;
        } else if (distance2 > innerRadius2) {
          alpha = ((radius + 0.5 - math.sqrt(distance2)) * 255).round();
        }
      }
      pixels[p + 3] = alpha;
      if (alpha == 0) {
        pixels[p] = 0;
        pixels[p + 1] = 0;
        pixels[p + 2] = 0;
      } else if (rgbBits < 8) {
        for (var channel = 0; channel < 3; channel++) {
          pixels[p + channel] =
              (((pixels[p + channel] * levels + 127) ~/ 255) * 255) ~/ levels;
        }
      }
    }
  }
  return img.Image.fromBytes(
    width: side,
    height: side,
    bytes: pixels.buffer,
    order: img.ChannelOrder.rgba,
    loopCount: 0,
  );
}

Uint8List _encodePoster(
  img.Image firstFrame, {
  required Uint8List? encodedFirstFrame,
  required Uint8List source,
  required Uint8List? overlay,
  required int side,
  required bool circle,
  required int rgbBits,
}) {
  final lossless = img.WebPEncoder(exact: false);
  final preferred = encodedFirstFrame ?? lossless.encode(firstFrame);
  if (preferred.length <= _posterBytes) return preferred;
  if (circle) {
    for (final bits in [5, 4]) {
      if (bits >= rgbBits) continue;
      final poster = lossless.encode(
        _compose(
          source,
          overlay: overlay,
          side: side,
          circle: true,
          rgbBits: bits,
        ),
      );
      if (poster.length <= _posterBytes) return poster;
    }
  } else {
    for (final quality in [70, 45]) {
      final poster = img.WebPEncoder(
        lossless: false,
        exact: false,
        quality: quality,
        method: 0,
      ).encode(firstFrame);
      if (poster.length <= _posterBytes) return poster;
    }
  }
  throw const AnimatedStickerCodecException(
    AnimatedStickerCodecFailure.budgetExceeded,
  );
}
