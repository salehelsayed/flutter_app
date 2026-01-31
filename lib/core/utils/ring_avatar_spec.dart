/// Ring Avatar Specification v1.0
///
/// This file documents the deterministic algorithm for generating
/// unique ring avatars from a peerId. The same peerId will always
/// produce the same avatar on any device/platform.
///
/// ## Algorithm Overview
///
/// ```
/// Input: peerId (UTF-8 string)
///
/// 1. HASH
///    hash = djb2(peerId)
///
/// 2. RING COUNT
///    ringCount = 4 (always exactly 4 rings)
///
/// 3. BRAND PALETTE (fixed)
///    colors[0] = #FF3B3B (red)
///    colors[1] = #FFFFFF (white)
///    colors[2] = #1A1A1A (black)
///    colors[3] = #1DB954 (green)
///
/// 4. COLOR ORDER (shuffled permutation based on hash)
///    All 4 colors are always used, order determined by hash.
///    shuffledColors = fisherYatesShuffle(colors, seed: hash)
///
/// 5. PER-RING PARAMETERS (for i = 0 to 3)
///    ringHash    = (hash * (i + 1)) % 1000
///    color       = shuffledColors[i]  // Each ring gets unique color
///    strokeWidth = 2 + (ringHash % 4)           // 2-5
///    gapFromPrev = 7 + ((ringHash >> 4) % 4)    // 7-10
///    rotation    = (ringHash * 137) % 360       // degrees
///    opacity     = 0.75 + ((ringHash >> 8) % 26) / 100.0
///    isDashed    = (i % 2) == 1
///    dashLength  = 5 + ((ringHash >> 2) % 10)   // if dashed
///    dashGap     = 2 + ((ringHash >> 6) % 5)    // if dashed
///
/// 6. RING RADII (outer to inner)
///    maxRadius = size * 0.475 (e.g., 38 for 80px avatar)
///    Start from outer ring, subtract strokeWidth + gap for each inner ring
///
/// 7. CENTER GLOW
///    glowHue = (hash >> 16) % 360
///    glowSat = 70%
///    glowLum = 50%
///    glowColor = HSL(glowHue, glowSat, glowLum)
///
///    Layer 1: radius = size * 0.15, opacity = 0.25
///    Layer 2: radius = size * 0.10, opacity = 0.50
///    Layer 3: radius = size * 0.0625, opacity = 1.00
/// ```
library;

import 'dart:ui';

/// Brand colors for ring avatar (fixed, do not change).
class RingAvatarColors {
  RingAvatarColors._();

  static const Color red = Color(0xFFFF3B3B);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF1A1A1A);
  static const Color green = Color(0xFF1DB954);

  static const List<Color> palette = [red, white, black, green];
}

/// Constants for ring avatar generation.
class RingAvatarConstants {
  RingAvatarConstants._();

  /// Number of rings (always 4, one for each brand color).
  static const int ringCount = 4;

  /// Minimum stroke width in logical pixels.
  static const double minStrokeWidth = 2.0;

  /// Maximum stroke width in logical pixels.
  static const double maxStrokeWidth = 5.0;

  /// Minimum gap between rings in logical pixels.
  static const double minGap = 7.0;

  /// Maximum gap between rings in logical pixels.
  static const double maxGap = 10.0;

  /// Minimum opacity for rings.
  static const double minOpacity = 0.75;

  /// Maximum opacity for rings.
  static const double maxOpacity = 1.0;

  /// Center glow saturation (0-100).
  static const double glowSaturation = 70.0;

  /// Center glow luminance (0-100).
  static const double glowLuminance = 50.0;

  /// Outer glow layer radius ratio (relative to avatar size).
  static const double glowOuterRadiusRatio = 0.15;

  /// Middle glow layer radius ratio.
  static const double glowMiddleRadiusRatio = 0.10;

  /// Inner glow layer radius ratio.
  static const double glowInnerRadiusRatio = 0.0625;

  /// Outer glow layer opacity.
  static const double glowOuterOpacity = 0.25;

  /// Middle glow layer opacity.
  static const double glowMiddleOpacity = 0.50;

  /// Inner glow layer opacity.
  static const double glowInnerOpacity = 1.0;

  /// Maximum ring radius ratio (relative to avatar size).
  static const double maxRadiusRatio = 0.475;
}
