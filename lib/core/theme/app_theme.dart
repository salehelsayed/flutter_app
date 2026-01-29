import 'package:flutter/material.dart';
import 'app_colors.dart';

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
        bodyLarge: TextStyle(
          color: AppColors.textMuted,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
        labelSmall: TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
        ),
      ),
    );
  }
}
