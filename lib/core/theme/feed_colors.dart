import 'package:flutter/material.dart';

/// Color palette for the Feed Live 2 card redesign.
///
/// Purple + teal accent scheme. Does NOT modify [AppColors] —
/// other screens still use the old palette.
class FeedColors {
  FeedColors._();

  // Background gradient
  static const Color backgroundTop = Color(0xFF0f0f18);
  static const Color backgroundBottom = Color(0xFF0a0a0f);

  // Accent colors
  static const Color accentPurple = Color(0xFFa78bfa);
  static const Color accentTeal = Color(0xFF81e6d9);

  // Card surface
  static const Color cardBg = Color.fromRGBO(255, 255, 255, 0.03);
  static const Color cardBorder = Color.fromRGBO(255, 255, 255, 0.08);

  // Message bubble backgrounds
  static const Color messageReceivedBg = Color.fromRGBO(255, 255, 255, 0.06);
  static const Color messageSentBg = Color.fromRGBO(255, 255, 255, 0.04);
  static const Color messageUnreadBg = Color.fromRGBO(255, 255, 255, 0.06);

  // UI hints
  static const Color moreMessagesHint = Color.fromRGBO(167, 139, 250, 0.7);
  static const Color chevronColor = Color.fromRGBO(167, 139, 250, 0.5);
  static const Color viewEarlierText = Color.fromRGBO(255, 255, 255, 0.35);
  static const Color textMuted = Color.fromRGBO(255, 255, 255, 0.50);

  // Border tints per state
  static Color get purpleBorderTint =>
      accentPurple.withValues(alpha: 0.12);
  static Color get tealBorderTint =>
      accentTeal.withValues(alpha: 0.12);

  // Glow shadows per state
  static Color get purpleGlow =>
      accentPurple.withValues(alpha: 0.08);
}
