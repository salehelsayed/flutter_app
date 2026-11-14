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

typedef _Profile = ({int fps, int quality, int rgbBits});

const _opaqueProfiles = <_Profile>[
  (fps: 12, quality: 70, rgbBits: 8),
  (fps: 12, quality: 45, rgbBits: 8),
  (fps: 8, quality: 55, rgbBits: 8),
  (fps: 6, quality: 45, rgbBits: 8),
];

// Lossy color can reconstruct RGB under zero alpha even if the input
// had been cleared. Preserve alpha and the cleared pixels with VP8L.
const _circleProfiles = <_Profile>[
  (fps: 12, quality: 100, rgbBits: 8),
  (fps: 12, quality: 100, rgbBits: 5),
  (fps: 8, quality: 100, rgbBits: 5),
  (fps: 6, quality: 100, rgbBits: 4),
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
    final frameCount = _frameCount(durationMs, profile.fps);
    img.Image? sequence;
    for (var i = 0; i < frameCount; i++) {
      // Reuse the captured sampling grid for every attempt.
      final sourceIndex = i * sampleCount ~/ frameCount;
      final frame =
          _compose(
              croppedFrames[sourceIndex],
              overlay: textOverlay,
              circle: circle,
              rgbBits: profile.rgbBits,
            )
            ..frameDuration =
                _boundary(i + 1, frameCount, durationMs) -
                _boundary(i, frameCount, durationMs);
      if (sequence == null) {
        sequence = frame;
      } else {
        sequence.addFrame(frame);
      }
    }
    final animation = sequence!;
    final webp = img.WebPEncoder(
      lossless: circle,
      exact: false,
      quality: profile.quality,
      method: 0,
    ).encode(animation);
    if (webp.length > _animatedBytes) continue;

    return (
      webp: webp,
      poster: _encodePoster(
        animation,
        source: croppedFrames.first,
        overlay: textOverlay,
        circle: circle,
        rgbBits: profile.rgbBits,
      ),
      frameCount: frameCount,
      durationMs: durationMs,
    );
  }
  throw const AnimatedStickerCodecException(
    AnimatedStickerCodecFailure.budgetExceeded,
  );
}

int _frameCount(int durationMs, int fps) =>
    math.max(2, (durationMs * fps + 999) ~/ 1000);

int _boundary(int i, int count, int durationMs) =>
    (i * durationMs + count ~/ 2) ~/ count;

img.Image _compose(
  Uint8List source, {
  required Uint8List? overlay,
  required bool circle,
  required int rgbBits,
}) {
  final pixels = Uint8List.fromList(source);
  final levels = (1 << rgbBits) - 1;
  const radius = stickerAnimationSide / 2;
  const innerRadius2 = (radius - 0.5) * (radius - 0.5);
  const outerRadius2 = (radius + 0.5) * (radius + 0.5);
  for (var y = 0; y < stickerAnimationSide; y++) {
    final dy = y + 0.5 - radius;
    for (var x = 0; x < stickerAnimationSide; x++) {
      final p = 4 * (y * stickerAnimationSide + x);
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
    width: stickerAnimationSide,
    height: stickerAnimationSide,
    bytes: pixels.buffer,
    order: img.ChannelOrder.rgba,
    loopCount: 0,
  );
}

Uint8List _encodePoster(
  img.Image sequence, {
  required Uint8List source,
  required Uint8List? overlay,
  required bool circle,
  required int rgbBits,
}) {
  final lossless = img.WebPEncoder(exact: false);
  final preferred = lossless.encode(sequence, singleFrame: true);
  if (preferred.length <= _posterBytes) return preferred;
  if (circle) {
    for (final bits in [5, 4]) {
      if (bits >= rgbBits) continue;
      final poster = lossless.encode(
        _compose(source, overlay: overlay, circle: true, rgbBits: bits),
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
      ).encode(sequence, singleFrame: true);
      if (poster.length <= _posterBytes) return poster;
    }
  }
  throw const AnimatedStickerCodecException(
    AnimatedStickerCodecFailure.budgetExceeded,
  );
}
