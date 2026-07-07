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

  static const representativeLight = BackgroundReadableColors(
    textPrimary: Color(0xFF16181F),
    textSecondary: Color(0xFF4A4E5C),
    textMuted: Color(0xFF656A79),
    iconPrimary: Color(0xFF16181F),
    iconSecondary: Color(0xFF4A4E5C),
    iconMuted: Color(0xFF656A79),
    surfaceBase: Color(0xFFF4F6FA),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFE9ECF4),
    glassSurface: Color(0xEEF7F8FB),
    glassBorder: Color(0x33463A96),
    border: Color(0x99463A96),
    divider: Color(0x24463A96),
    overlayScrim: Color(0x66000000),
    inputFill: Color(0xFFF7F8FB),
    inputBorder: Color(0x99463A96),
    placeholderText: Color(0xFF6A6F7E),
    disabledForeground: Color(0xFF656A79),
    disabledSurface: Color(0xFFD8DBE4),
    accent: Color(0xFF5A24E0),
    accentIcon: Color(0xFFFFFFFF),
    // Paper White orbit rings: bolder neutral-ink dashes so the structure reads
    // on white (the old ink-violet 0x47/0x61 463A96 dashes went pale). ringGlow
    // is a near-nil violet so the painter's blur sublayer never hazes.
    ring1: Color(0x52262A3A),
    ring2: Color(0x70262A3A),
    ringGlow: Color(0x0A6D28D9),
    ctaBg: Color(0xFF5A24E0),
    ctaIcon: Color(0xFF5A24E0),
    ctaMenuFill: Color(0xFFF7F8FB),
    ctaMenuBorder: Color(0x335A24E0),
    ctaMenuText: Color(0xFF16181F),
    navActive: Color(0xFF5A24E0),
    navInactive: Color(0xFF656A79),
    navActiveFill: Color(0x1A5A24E0),
    // Paper White node treatment: these are now OPAQUE crisp-ring colors (not
    // translucent blooms). _OrbitNodeHalo paints a 2px solid ring in this color
    // hugging each node instead of the pale soft halo that washed out on white.
    nodeSelfGlow: Color(0xFF5A24E0),
    nodeContactGlow: Color(0xFFE5484D),
    composerBarColor: Color(0xF2EDEEF3),
    composerInputFill: Color(0xFFF7F8FB),
    composerHint: Color(0xFF656A79),
    sendBg: Color(0x1F5A24E0),
    sendIcon: Color(0xFF5A24E0),
    connectedHeading: Color(0xFF0A5D34),
    emptyHint: Color(0xFF656A79),
    emptyDate: Color(0xFF656A79),
    emptyDivider: Color(0x66463A96),
    emptyAvatarGlow: Color(0xFF5A24E0),
    micBg: Color(0x1F5A24E0),
    micBorder: Color(0x525A24E0),
    micShadow: Color(0x3D5A24E0),
    micIcon: Color(0xFF5A24E0),
    avatarFrameBorder: Color(0x33463A96),
    avatarFrameFill: Color(0xFFF7F8FB),
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
