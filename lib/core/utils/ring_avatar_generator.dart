import 'package:flutter/material.dart';
import 'ring_avatar_spec.dart';

/// Data for a single ring in the avatar.
class RingData {
  final double radius;
  final double strokeWidth;
  final Color color;
  final double opacity;
  final double rotationDegrees;
  final bool isDashed;
  final double dashLength;
  final double dashGap;

  const RingData({
    required this.radius,
    required this.strokeWidth,
    required this.color,
    required this.opacity,
    required this.rotationDegrees,
    required this.isDashed,
    required this.dashLength,
    required this.dashGap,
  });
}

/// Data for the center glow effect.
class GlowData {
  final Color color;
  final double outerRadius;
  final double middleRadius;
  final double innerRadius;

  const GlowData({
    required this.color,
    required this.outerRadius,
    required this.middleRadius,
    required this.innerRadius,
  });
}

/// Complete avatar data generated from a peerId.
class RingAvatarData {
  final List<RingData> rings;
  final GlowData glow;

  const RingAvatarData({
    required this.rings,
    required this.glow,
  });
}

/// Generator for deterministic ring avatars.
///
/// The same peerId will always produce the same avatar data,
/// regardless of platform or device.
class RingAvatarGenerator {
  RingAvatarGenerator._();

  /// Generate avatar data from a peerId.
  ///
  /// [peerId] - The unique peer identifier string.
  /// [size] - The avatar size in logical pixels.
  static RingAvatarData generate(String peerId, double size) {
    final hash = djb2Hash(peerId);

    // Always exactly 4 rings, one for each brand color
    const ringCount = RingAvatarConstants.ringCount;

    // Shuffle colors based on hash (Fisher-Yates with deterministic seed)
    final shuffledColors = _shuffleColors(hash);

    // Generate per-ring data with shuffled colors
    final ringDataList = <_RingParams>[];
    for (int i = 0; i < ringCount; i++) {
      ringDataList.add(_generateRingParams(hash, i, shuffledColors[i]));
    }

    // Calculate radii from outer to inner
    final maxRadius = size * RingAvatarConstants.maxRadiusRatio;
    final rings = _calculateRingRadii(ringDataList, maxRadius);

    // Generate center glow
    final glow = _generateGlow(hash, size);

    return RingAvatarData(rings: rings, glow: glow);
  }

  /// DJB2 hash function - deterministic across all platforms.
  ///
  /// This is a well-known hash function that produces consistent
  /// results in any programming language.
  static int djb2Hash(String str) {
    int hash = 5381;
    for (int i = 0; i < str.length; i++) {
      hash = ((hash << 5) + hash) + str.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF; // Keep 32-bit
    }
    return hash;
  }

  /// Shuffle the color palette using Fisher-Yates with deterministic seed.
  static List<Color> _shuffleColors(int hash) {
    final colors = List<Color>.from(RingAvatarColors.palette);
    var seed = hash;

    // Fisher-Yates shuffle with deterministic random
    for (int i = colors.length - 1; i > 0; i--) {
      // Simple LCG for deterministic "random" index
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      final j = seed % (i + 1);

      // Swap
      final temp = colors[i];
      colors[i] = colors[j];
      colors[j] = temp;
    }

    return colors;
  }

  static _RingParams _generateRingParams(int hash, int index, Color color) {
    final ringHash = (hash * (index + 1)) % 1000;

    // Stroke width: 2-5px
    final strokeWidth = RingAvatarConstants.minStrokeWidth +
        (ringHash % (RingAvatarConstants.maxStrokeWidth -
                RingAvatarConstants.minStrokeWidth +
                1))
            .toDouble();

    // Gap from previous ring: 7-10px
    final gap = RingAvatarConstants.minGap +
        (((ringHash >> 4) %
                (RingAvatarConstants.maxGap - RingAvatarConstants.minGap + 1))
            .toDouble());

    // Rotation: 0-359 degrees
    final rotation = ((ringHash * 137) % 360).toDouble();

    // Opacity: 0.75-1.0
    final opacity =
        RingAvatarConstants.minOpacity + ((ringHash >> 8) % 26) / 100.0;

    // Dashing: alternating pattern (odd indices are dashed)
    final isDashed = (index % 2) == 1;

    // Dash parameters (only used if isDashed)
    final dashLength = 5.0 + ((ringHash >> 2) % 10).toDouble();
    final dashGap = 2.0 + ((ringHash >> 6) % 5).toDouble();

    return _RingParams(
      color: color,
      strokeWidth: strokeWidth,
      gap: gap,
      rotation: rotation,
      opacity: opacity.clamp(RingAvatarConstants.minOpacity,
          RingAvatarConstants.maxOpacity),
      isDashed: isDashed,
      dashLength: dashLength,
      dashGap: dashGap,
    );
  }

  static List<RingData> _calculateRingRadii(
      List<_RingParams> params, double maxRadius) {
    final rings = <RingData>[];

    // Start from outer ring
    double currentRadius = maxRadius;

    for (int i = params.length - 1; i >= 0; i--) {
      final p = params[i];

      rings.insert(
        0,
        RingData(
          radius: currentRadius,
          strokeWidth: p.strokeWidth,
          color: p.color,
          opacity: p.opacity,
          rotationDegrees: p.rotation,
          isDashed: p.isDashed,
          dashLength: p.dashLength,
          dashGap: p.dashGap,
        ),
      );

      // Move inward for next ring
      if (i > 0) {
        currentRadius -= p.strokeWidth + params[i - 1].gap;
      }
    }

    return rings;
  }

  static GlowData _generateGlow(int hash, double size) {
    // Hue from full spectrum (0-359)
    final hue = ((hash >> 16) % 360).toDouble();

    // Convert HSL to Color
    final color = HSLColor.fromAHSL(
      1.0,
      hue,
      RingAvatarConstants.glowSaturation / 100.0,
      RingAvatarConstants.glowLuminance / 100.0,
    ).toColor();

    return GlowData(
      color: color,
      outerRadius: size * RingAvatarConstants.glowOuterRadiusRatio,
      middleRadius: size * RingAvatarConstants.glowMiddleRadiusRatio,
      innerRadius: size * RingAvatarConstants.glowInnerRadiusRatio,
    );
  }
}

/// Internal class for intermediate ring parameters.
class _RingParams {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double rotation;
  final double opacity;
  final bool isDashed;
  final double dashLength;
  final double dashGap;

  const _RingParams({
    required this.color,
    required this.strokeWidth,
    required this.gap,
    required this.rotation,
    required this.opacity,
    required this.isDashed,
    required this.dashLength,
    required this.dashGap,
  });
}
