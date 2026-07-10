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

  /// 248 — decorative card/bubble/divider outline. Deliberately softer than
  /// [border]/[inputBorder] (which stay ≥3:1 control boundaries). Only named
  /// decorative consumers (rows, bubbles) use it; the dark value equals the
  /// prior dark [border] so dark rendering is byte-identical.
  final Color surfaceBorder;

  final Color divider;
  final Color overlayScrim;
  final Color inputFill;
  final Color inputBorder;
  final Color placeholderText;
  final Color disabledForeground;
  final Color disabledSurface;
  final Color accent;
  final Color accentIcon;
  final Color ring1;
  final Color ring2;
  final Color ringGlow;
  final Color ctaBg;
  final Color ctaIcon;
  final Color ctaMenuFill;
  final Color ctaMenuBorder;
  final Color ctaMenuText;
  final Color navActive;
  final Color navInactive;
  final Color navActiveFill;
  final Color nodeSelfGlow;
  final Color nodeContactGlow;
  final Color composerBarColor;
  final Color composerInputFill;
  final Color composerHint;
  final Color sendBg;
  final Color sendIcon;
  final Color connectedHeading;
  final Color emptyHint;
  final Color emptyDate;
  final Color emptyDivider;
  final Color emptyAvatarGlow;
  final Color micBg;
  final Color micBorder;
  final Color micShadow;
  final Color micIcon;
  final Color avatarFrameBorder;
  final Color avatarFrameFill;
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
    required this.surfaceBorder,
    required this.divider,
    required this.overlayScrim,
    required this.inputFill,
    required this.inputBorder,
    required this.placeholderText,
    required this.disabledForeground,
    required this.disabledSurface,
    required this.accent,
    required this.accentIcon,
    required this.ring1,
    required this.ring2,
    required this.ringGlow,
    required this.ctaBg,
    required this.ctaIcon,
    required this.ctaMenuFill,
    required this.ctaMenuBorder,
    required this.ctaMenuText,
    required this.navActive,
    required this.navInactive,
    required this.navActiveFill,
    required this.nodeSelfGlow,
    required this.nodeContactGlow,
    required this.composerBarColor,
    required this.composerInputFill,
    required this.composerHint,
    required this.sendBg,
    required this.sendIcon,
    required this.connectedHeading,
    required this.emptyHint,
    required this.emptyDate,
    required this.emptyDivider,
    required this.emptyAvatarGlow,
    required this.micBg,
    required this.micBorder,
    required this.micShadow,
    required this.micIcon,
    required this.avatarFrameBorder,
    required this.avatarFrameFill,
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
    // Dark surfaceBorder == prior dark border so decorative-outline consumers
    // (rows/bubbles) render byte-identically on dark after switching to it.
    surfaceBorder: Color(0x80FFFFFF),
    divider: Color(0x24FFFFFF),
    overlayScrim: Color(0xB3000000),
    inputFill: Color(0xCC101218),
    inputBorder: Color(0x80FFFFFF),
    placeholderText: Color(0xAFC9CED6),
    disabledForeground: Color(0xB8C9CED6),
    disabledSurface: Color(0x80181A20),
    accent: Color(0xFF1DB954),
    accentIcon: Color(0xFFFFFFFF),
    ring1: Color(0x4081E6D9),
    ring2: Color(0x33A78BFA),
    ringGlow: Color(0x1481E6D9),
    ctaBg: Color(0xFF1A1A2E),
    ctaIcon: Color(0xFF64B5F6),
    ctaMenuFill: Color(0x1AFFFFFF),
    ctaMenuBorder: Color(0x26FFFFFF),
    ctaMenuText: Color(0xFFFFFFFF),
    navActive: Color(0xFFFFFFFF),
    navInactive: Color(0x8CFFFFFF),
    navActiveFill: Color(0x40FFFFFF),
    nodeSelfGlow: Colors.transparent,
    nodeContactGlow: Colors.transparent,
    composerBarColor: Color.fromRGBO(10, 10, 15, 0.95),
    composerInputFill: Color(0x0FFFFFFF),
    composerHint: Color(0x4DFFFFFF),
    sendBg: Color(0x261DB954),
    sendIcon: Color(0xFF1DB954),
    connectedHeading: Color(0xFF1DB954),
    emptyHint: Color(0x80FFFFFF),
    emptyDate: Color(0x59FFFFFF),
    emptyDivider: Color(0x1FFFFFFF),
    emptyAvatarGlow: Color(0x4D4ECDC4),
    micBg: Color(0x261DB954),
    micBorder: Color(0x4D1DB954),
    micShadow: Color(0x3D1DB954),
    micIcon: Color(0xFF1DB954),
    avatarFrameBorder: Color(0x59FFFFFF),
    avatarFrameFill: Color(0xB316181E),
    statusBarIconBrightness: Brightness.light,
    navigationBarIconBrightness: Brightness.light,
  );

  // 248 — the Signal "warm mineral" light palette. Every role is measured
  // against the actual surface it renders on (canvas #ECE8E1, base #F4F0EA,
  // raised #FAF8F3, subtle #E1DCE5): normal/small text ≥4.5:1, control /
  // interactive borders ≥3:1. Filled success stays #2F7755 (Material secondary
  // + white); small success text/borders use full-opacity #236143.
  static const representativeLight = BackgroundReadableColors(
    textPrimary: Color(0xFF25222B),
    textSecondary: Color(0xFF56515E),
    textMuted: Color(0xFF65606C),
    iconPrimary: Color(0xFF25222B),
    iconSecondary: Color(0xFF56515E),
    iconMuted: Color(0xFF65606C),
    surfaceBase: Color(0xFFF4F0EA),
    surfaceRaised: Color(0xFFFAF8F3),
    surfaceSubtle: Color(0xFFE1DCE5),
    glassSurface: Color(0xEEFAF8F3),
    glassBorder: Color(0xFF8D83A8),
    border: Color(0xFF8D83A8),
    // Decorative-only: softer than border/inputBorder; grouping, never the sole
    // control boundary.
    surfaceBorder: Color(0xFFB3ACBD),
    divider: Color(0xFFB3ACBD),
    overlayScrim: Color(0x66000000),
    inputFill: Color(0xFFE1DCE5),
    inputBorder: Color(0xFF7C7297),
    placeholderText: Color(0xFF645F6A),
    disabledForeground: Color(0xFF6B6672),
    disabledSurface: Color(0xFFD5D0D9),
    accent: Color(0xFF6045B6),
    accentIcon: Color(0xFFFFFFFF),
    ring1: Color(0x526045B6),
    ring2: Color(0x706045B6),
    ringGlow: Color(0x177C69C8),
    ctaBg: Color(0xFF6045B6),
    ctaIcon: Color(0xFF6045B6),
    ctaMenuFill: Color(0xFFFAF8F3),
    ctaMenuBorder: Color(0xFF8D83A8),
    ctaMenuText: Color(0xFF25222B),
    navActive: Color(0xFF6045B6),
    navInactive: Color(0xFF65606C),
    navActiveFill: Color(0x1A6045B6),
    nodeSelfGlow: Color(0xFF6045B6),
    nodeContactGlow: Color(0xFFE5484D),
    composerBarColor: Color(0xF2F4F0EA),
    composerInputFill: Color(0xFFE1DCE5),
    composerHint: Color(0xFF645F6A),
    sendBg: Color(0x1F6045B6),
    sendIcon: Color(0xFF6045B6),
    connectedHeading: Color(0xFF236143),
    emptyHint: Color(0xFF65606C),
    emptyDate: Color(0xFF65606C),
    emptyDivider: Color(0xFFB3ACBD),
    emptyAvatarGlow: Color(0xFF6045B6),
    micBg: Color(0x1F6045B6),
    micBorder: Color(0xFF7C7297),
    micShadow: Color(0x336045B6),
    micIcon: Color(0xFF6045B6),
    avatarFrameBorder: Color(0xFFB3ACBD),
    avatarFrameFill: Color(0xFFFAF8F3),
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
      case BackgroundPreference.aurora:
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
    Color? surfaceBorder,
    Color? divider,
    Color? overlayScrim,
    Color? inputFill,
    Color? inputBorder,
    Color? placeholderText,
    Color? disabledForeground,
    Color? disabledSurface,
    Color? accent,
    Color? accentIcon,
    Color? ring1,
    Color? ring2,
    Color? ringGlow,
    Color? ctaBg,
    Color? ctaIcon,
    Color? ctaMenuFill,
    Color? ctaMenuBorder,
    Color? ctaMenuText,
    Color? navActive,
    Color? navInactive,
    Color? navActiveFill,
    Color? nodeSelfGlow,
    Color? nodeContactGlow,
    Color? composerBarColor,
    Color? composerInputFill,
    Color? composerHint,
    Color? sendBg,
    Color? sendIcon,
    Color? connectedHeading,
    Color? emptyHint,
    Color? emptyDate,
    Color? emptyDivider,
    Color? emptyAvatarGlow,
    Color? micBg,
    Color? micBorder,
    Color? micShadow,
    Color? micIcon,
    Color? avatarFrameBorder,
    Color? avatarFrameFill,
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
      surfaceBorder: surfaceBorder ?? this.surfaceBorder,
      divider: divider ?? this.divider,
      overlayScrim: overlayScrim ?? this.overlayScrim,
      inputFill: inputFill ?? this.inputFill,
      inputBorder: inputBorder ?? this.inputBorder,
      placeholderText: placeholderText ?? this.placeholderText,
      disabledForeground: disabledForeground ?? this.disabledForeground,
      disabledSurface: disabledSurface ?? this.disabledSurface,
      accent: accent ?? this.accent,
      accentIcon: accentIcon ?? this.accentIcon,
      ring1: ring1 ?? this.ring1,
      ring2: ring2 ?? this.ring2,
      ringGlow: ringGlow ?? this.ringGlow,
      ctaBg: ctaBg ?? this.ctaBg,
      ctaIcon: ctaIcon ?? this.ctaIcon,
      ctaMenuFill: ctaMenuFill ?? this.ctaMenuFill,
      ctaMenuBorder: ctaMenuBorder ?? this.ctaMenuBorder,
      ctaMenuText: ctaMenuText ?? this.ctaMenuText,
      navActive: navActive ?? this.navActive,
      navInactive: navInactive ?? this.navInactive,
      navActiveFill: navActiveFill ?? this.navActiveFill,
      nodeSelfGlow: nodeSelfGlow ?? this.nodeSelfGlow,
      nodeContactGlow: nodeContactGlow ?? this.nodeContactGlow,
      composerBarColor: composerBarColor ?? this.composerBarColor,
      composerInputFill: composerInputFill ?? this.composerInputFill,
      composerHint: composerHint ?? this.composerHint,
      sendBg: sendBg ?? this.sendBg,
      sendIcon: sendIcon ?? this.sendIcon,
      connectedHeading: connectedHeading ?? this.connectedHeading,
      emptyHint: emptyHint ?? this.emptyHint,
      emptyDate: emptyDate ?? this.emptyDate,
      emptyDivider: emptyDivider ?? this.emptyDivider,
      emptyAvatarGlow: emptyAvatarGlow ?? this.emptyAvatarGlow,
      micBg: micBg ?? this.micBg,
      micBorder: micBorder ?? this.micBorder,
      micShadow: micShadow ?? this.micShadow,
      micIcon: micIcon ?? this.micIcon,
      avatarFrameBorder: avatarFrameBorder ?? this.avatarFrameBorder,
      avatarFrameFill: avatarFrameFill ?? this.avatarFrameFill,
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
      surfaceBorder: Color.lerp(surfaceBorder, other.surfaceBorder, t)!,
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
      accent: Color.lerp(accent, other.accent, t)!,
      accentIcon: Color.lerp(accentIcon, other.accentIcon, t)!,
      ring1: Color.lerp(ring1, other.ring1, t)!,
      ring2: Color.lerp(ring2, other.ring2, t)!,
      ringGlow: Color.lerp(ringGlow, other.ringGlow, t)!,
      ctaBg: Color.lerp(ctaBg, other.ctaBg, t)!,
      ctaIcon: Color.lerp(ctaIcon, other.ctaIcon, t)!,
      ctaMenuFill: Color.lerp(ctaMenuFill, other.ctaMenuFill, t)!,
      ctaMenuBorder: Color.lerp(ctaMenuBorder, other.ctaMenuBorder, t)!,
      ctaMenuText: Color.lerp(ctaMenuText, other.ctaMenuText, t)!,
      navActive: Color.lerp(navActive, other.navActive, t)!,
      navInactive: Color.lerp(navInactive, other.navInactive, t)!,
      navActiveFill: Color.lerp(navActiveFill, other.navActiveFill, t)!,
      nodeSelfGlow: Color.lerp(nodeSelfGlow, other.nodeSelfGlow, t)!,
      nodeContactGlow: Color.lerp(nodeContactGlow, other.nodeContactGlow, t)!,
      composerBarColor: Color.lerp(
        composerBarColor,
        other.composerBarColor,
        t,
      )!,
      composerInputFill: Color.lerp(
        composerInputFill,
        other.composerInputFill,
        t,
      )!,
      composerHint: Color.lerp(composerHint, other.composerHint, t)!,
      sendBg: Color.lerp(sendBg, other.sendBg, t)!,
      sendIcon: Color.lerp(sendIcon, other.sendIcon, t)!,
      connectedHeading: Color.lerp(
        connectedHeading,
        other.connectedHeading,
        t,
      )!,
      emptyHint: Color.lerp(emptyHint, other.emptyHint, t)!,
      emptyDate: Color.lerp(emptyDate, other.emptyDate, t)!,
      emptyDivider: Color.lerp(emptyDivider, other.emptyDivider, t)!,
      emptyAvatarGlow: Color.lerp(emptyAvatarGlow, other.emptyAvatarGlow, t)!,
      micBg: Color.lerp(micBg, other.micBg, t)!,
      micBorder: Color.lerp(micBorder, other.micBorder, t)!,
      micShadow: Color.lerp(micShadow, other.micShadow, t)!,
      micIcon: Color.lerp(micIcon, other.micIcon, t)!,
      avatarFrameBorder: Color.lerp(
        avatarFrameBorder,
        other.avatarFrameBorder,
        t,
      )!,
      avatarFrameFill: Color.lerp(avatarFrameFill, other.avatarFrameFill, t)!,
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
