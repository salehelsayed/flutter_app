import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

enum BackgroundReadableTone { dark, representativeLight }

@immutable
class BackgroundReadableColors
    extends ThemeExtension<BackgroundReadableColors> {
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconMuted;
  final Color surfaceBase;
  final Color surfaceRaised;
  final Color surfaceSubtle;
  final Color glassSurface;
  final Color glassBorder;
  final Color border;
  final Color divider;
  final Color overlayScrim;
  final Color inputFill;
  final Color inputBorder;
  final Color placeholderText;
  final Color disabledForeground;
  final Color disabledSurface;
  final Brightness statusBarIconBrightness;
  final Brightness navigationBarIconBrightness;

  const BackgroundReadableColors({
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.iconMuted,
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceSubtle,
    required this.glassSurface,
    required this.glassBorder,
    required this.border,
    required this.divider,
    required this.overlayScrim,
    required this.inputFill,
    required this.inputBorder,
    required this.placeholderText,
    required this.disabledForeground,
    required this.disabledSurface,
    required this.statusBarIconBrightness,
    required this.navigationBarIconBrightness,
  });

  static const dark = BackgroundReadableColors(
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xDDE5E7EB),
    textMuted: Color(0xB8C9CED6),
    iconPrimary: Color(0xFFF8FAFC),
    iconSecondary: Color(0xDDE5E7EB),
    iconMuted: Color(0xAFC9CED6),
    surfaceBase: Color(0xE60A0A0F),
    surfaceRaised: Color(0xDB181A20),
    surfaceSubtle: Color(0xBF101218),
    glassSurface: Color(0xCC0A0A0F),
    glassBorder: Color(0x66FFFFFF),
    border: Color(0x80FFFFFF),
    divider: Color(0x24FFFFFF),
    overlayScrim: Color(0xB3000000),
    inputFill: Color(0xCC101218),
    inputBorder: Color(0x80FFFFFF),
    placeholderText: Color(0xAFC9CED6),
    disabledForeground: Color(0xB8C9CED6),
    disabledSurface: Color(0x80181A20),
    statusBarIconBrightness: Brightness.light,
    navigationBarIconBrightness: Brightness.light,
  );

  static const representativeLight = BackgroundReadableColors(
    textPrimary: Color(0xFF101318),
    textSecondary: Color(0xFF293241),
    textMuted: Color(0xFF4B5563),
    iconPrimary: Color(0xFF101318),
    iconSecondary: Color(0xFF293241),
    iconMuted: Color(0xFF5B6472),
    surfaceBase: Color(0xF7FFFFFF),
    surfaceRaised: Color(0xF2F7F9FC),
    surfaceSubtle: Color(0xE8EEF2F7),
    glassSurface: Color(0xEAF8FAFC),
    glassBorder: Color(0x66101318),
    border: Color(0x8A101318),
    divider: Color(0x29101318),
    overlayScrim: Color(0x66000000),
    inputFill: Color(0xF2FFFFFF),
    inputBorder: Color(0x8A101318),
    placeholderText: Color(0xFF566173),
    disabledForeground: Color(0xFF5B6472),
    disabledSurface: Color(0xFFD9DEE6),
    statusBarIconBrightness: Brightness.dark,
    navigationBarIconBrightness: Brightness.dark,
  );

  static BackgroundReadableColors resolve(
    BackgroundPreference preference, {
    BackgroundReadableTone? representativeToneOverride,
  }) {
    final tone = representativeToneOverride ?? toneForPreference(preference);
    return switch (tone) {
      BackgroundReadableTone.dark => dark,
      BackgroundReadableTone.representativeLight => representativeLight,
    };
  }

  static BackgroundReadableTone toneForPreference(
    BackgroundPreference preference,
  ) {
    switch (preference) {
      case BackgroundPreference.defaultBackground:
      case BackgroundPreference.cosmic:
      case BackgroundPreference.cosmicMirrored:
        return BackgroundReadableTone.dark;
      case BackgroundPreference.daylightLagoon:
        return BackgroundReadableTone.representativeLight;
    }
  }

  SystemUiOverlayStyle get systemUiOverlayStyle {
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: statusBarIconBrightness,
      statusBarBrightness: statusBarIconBrightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarColor: surfaceBase,
      systemNavigationBarDividerColor: divider,
      systemNavigationBarIconBrightness: navigationBarIconBrightness,
    );
  }

  bool get isLightSurface => statusBarIconBrightness == Brightness.dark;

  @override
  BackgroundReadableColors copyWith({
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? iconPrimary,
    Color? iconSecondary,
    Color? iconMuted,
    Color? surfaceBase,
    Color? surfaceRaised,
    Color? surfaceSubtle,
    Color? glassSurface,
    Color? glassBorder,
    Color? border,
    Color? divider,
    Color? overlayScrim,
    Color? inputFill,
    Color? inputBorder,
    Color? placeholderText,
    Color? disabledForeground,
    Color? disabledSurface,
    Brightness? statusBarIconBrightness,
    Brightness? navigationBarIconBrightness,
  }) {
    return BackgroundReadableColors(
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconSecondary: iconSecondary ?? this.iconSecondary,
      iconMuted: iconMuted ?? this.iconMuted,
      surfaceBase: surfaceBase ?? this.surfaceBase,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      glassSurface: glassSurface ?? this.glassSurface,
      glassBorder: glassBorder ?? this.glassBorder,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      overlayScrim: overlayScrim ?? this.overlayScrim,
      inputFill: inputFill ?? this.inputFill,
      inputBorder: inputBorder ?? this.inputBorder,
      placeholderText: placeholderText ?? this.placeholderText,
      disabledForeground: disabledForeground ?? this.disabledForeground,
      disabledSurface: disabledSurface ?? this.disabledSurface,
      statusBarIconBrightness:
          statusBarIconBrightness ?? this.statusBarIconBrightness,
      navigationBarIconBrightness:
          navigationBarIconBrightness ?? this.navigationBarIconBrightness,
    );
  }

  @override
  BackgroundReadableColors lerp(
    ThemeExtension<BackgroundReadableColors>? other,
    double t,
  ) {
    if (other is! BackgroundReadableColors) {
      return this;
    }
    return BackgroundReadableColors(
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconSecondary: Color.lerp(iconSecondary, other.iconSecondary, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      overlayScrim: Color.lerp(overlayScrim, other.overlayScrim, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      inputBorder: Color.lerp(inputBorder, other.inputBorder, t)!,
      placeholderText: Color.lerp(placeholderText, other.placeholderText, t)!,
      disabledForeground: Color.lerp(
        disabledForeground,
        other.disabledForeground,
        t,
      )!,
      disabledSurface: Color.lerp(disabledSurface, other.disabledSurface, t)!,
      statusBarIconBrightness: t < 0.5
          ? statusBarIconBrightness
          : other.statusBarIconBrightness,
      navigationBarIconBrightness: t < 0.5
          ? navigationBarIconBrightness
          : other.navigationBarIconBrightness,
    );
  }
}

extension BackgroundReadableColorsContext on BuildContext {
  BackgroundReadableColors get backgroundReadableColors {
    return Theme.of(this).extension<BackgroundReadableColors>() ??
        BackgroundReadableColors.dark;
  }
}
