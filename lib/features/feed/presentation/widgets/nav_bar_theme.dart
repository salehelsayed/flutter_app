import 'dart:ui';

import 'package:flutter/material.dart';

/// Single source of truth for the Signal-inspired navigation bar design tokens.
abstract final class NavBarTheme {
  // ── Bar ──────────────────────────────────────────────────────────────

  static const double barMaxWidth = 340;
  static const double barBorderRadius = 30;
  static const EdgeInsets barPadding =
      EdgeInsets.symmetric(horizontal: 6, vertical: 5);
  static const double blurSigma = 28;

  static const List<Color> barGradientColors = [
    Color.fromRGBO(255, 255, 255, 0.18),
    Color.fromRGBO(255, 255, 255, 0.10),
  ];

  static const Color barBorderColor = Color.fromRGBO(255, 255, 255, 0.30);
  static const Color barShadowColor = Color.fromRGBO(0, 0, 0, 0.12);
  static const double barShadowBlur = 16;
  static const Offset barShadowOffset = Offset(0, 4);

  // ── Button ───────────────────────────────────────────────────────────

  static const double buttonSpacing = 5;
  static const double buttonWidth = 70;
  static const double buttonBorderRadius = 19;
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(vertical: 5);

  static const double iconSize = 18;
  static const double textSize = 11;
  static const double iconTextGap = 2;

  static const Duration animationDuration = Duration(milliseconds: 220);
  static const Curve animationCurve = Curves.easeOut;

  // Active state
  static const List<Color> activePillGradient = [
    Color.fromRGBO(255, 255, 255, 0.25),
    Color.fromRGBO(255, 255, 255, 0.12),
  ];
  static const Color activeTextColor = Colors.white;
  static const Color activeIconColor = Colors.white;
  static const FontWeight activeWeight = FontWeight.w600;

  // Inactive state
  static const double inactiveIconOpacity = 0.60;
  static const double inactiveTextOpacity = 0.55;
  static const FontWeight inactiveWeight = FontWeight.w500;

  static Color get inactiveIconColor =>
      Colors.white.withValues(alpha: inactiveIconOpacity);
  static Color get inactiveTextColor =>
      Colors.white.withValues(alpha: inactiveTextOpacity);

  // ── Badge ────────────────────────────────────────────────────────────

  static const List<Color> badgeGradientColors = [
    Color(0xFFFF3B30),
    Color(0xFFE0342A),
  ];
  static const Color badgeShadowColor = Color(0x66FF3B30);
}
