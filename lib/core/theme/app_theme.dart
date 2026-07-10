import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'background_readable_colors.dart';
import 'feed_tokens.dart';

/// Application theme configuration for Custom1 dark theme.
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.background,
        primary: AppColors.primaryAccent,
        secondary: AppColors.secondaryAccent,
        onSurface: AppColors.textPrimary,
        onPrimary: AppColors.textPrimary,
        onSecondary: AppColors.textPrimary,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 32,
        ),
        bodyLarge: TextStyle(color: AppColors.textMuted, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.textMuted, fontSize: 14),
        labelSmall: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        BackgroundReadableColors.dark,
        FeedTokens.dark,
      ],
    );
  }

  /// 248 — the warm Signal light theme. One coherent, dimensional light
  /// appearance so a Signal root (and every pushed route / modal that falls back
  /// to it) renders warm mineral surfaces instead of dark Material islands. The
  /// locked light roles live on [BackgroundReadableColors.representativeLight]
  /// and [FeedTokens.light]; this is the Material ColorScheme + component
  /// defaults that back pushed chrome with no ambient wrapper.
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      // Warm mineral/linen ground; pure white is forbidden as the Signal canvas.
      scaffoldBackgroundColor: const Color(0xFFECE8E1),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF6045B6),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF2F7755),
        onSecondary: Color(0xFFFFFFFF),
        surface: Color(0xFFFAF8F3),
        onSurface: Color(0xFF25222B),
        error: Color(0xFFB4232F),
        onError: Color(0xFFFFFFFF),
        outline: Color(0xFF8D83A8),
        outlineVariant: Color(0xFFB3ACBD),
        surfaceContainerHighest: Color(0xFFE1DCE5),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: Color(0xFF25222B),
          fontWeight: FontWeight.bold,
          fontSize: 32,
        ),
        bodyLarge: TextStyle(color: Color(0xFF56515E), fontSize: 16),
        bodyMedium: TextStyle(color: Color(0xFF56515E), fontSize: 14),
        labelSmall: TextStyle(color: Color(0xFF65606C), fontSize: 12),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFFE1DCE5),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFFFAF8F3)),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFFFAF8F3),
      ),
      popupMenuTheme: const PopupMenuThemeData(color: Color(0xFFFAF8F3)),
      extensions: const <ThemeExtension<dynamic>>[
        BackgroundReadableColors.representativeLight,
        FeedTokens.light,
      ],
    );
  }
}
