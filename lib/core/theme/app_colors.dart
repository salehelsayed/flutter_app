import 'package:flutter/material.dart';

/// Custom1 dark theme color palette.
class AppColors {
  AppColors._();

  // Background
  static const Color background = Color(0xFF000000);

  // Primary Accent (Green)
  static const Color primaryAccent = Color(0xFF1DB954);
  static const Color secondaryAccent = Color(0xFF1ED760);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0x99FFFFFF); // rgba(255,255,255,0.6)

  // Glass effect (red-tinted)
  static const Color glassBackground = Color(0x0AFF3232); // rgba(255,50,50,0.04)
  static const Color glassBorder = Color(0x33FF3232); // rgba(255,50,50,0.2)

  // Ambient glow colors
  static const Color greenGlow = Color(0xFF1DB954);
  static const Color redGlow = Color(0xFFFF3232);
}
