import 'package:flutter/material.dart';

/// Design tokens for the redesigned Feed ("Letters" pending-reply inbox, 134
/// §9). A `ThemeExtension` so the whole surface reads tokens off the active
/// theme (mirrors `BackgroundReadableColors`). `AppText`/`AppSpace` do not
/// exist in this codebase, so the message typography + spacing tokens are
/// folded directly in here.
///
/// NOTE: the literal hexes/sigmas below are derived from the spec token names
/// (`--teal-400`, `--green-500`, `--teal-fill-08`, `--green-fill-15`,
/// `--blur-letter`, …) + the existing dark palette. A design-system handoff
/// can refine the literal values without changing this structure.
@immutable
class FeedTokens extends ThemeExtension<FeedTokens> {
  /// Focused-letter accent (border + glow) — `--teal-400`.
  final Color teal400;

  /// Focused-letter surface tint — `--teal-fill-08` (teal @ ~8%).
  final Color tealFill08;

  /// Outgoing / system bubble accent — `--green-500`.
  final Color green500;

  /// Outgoing / system bubble fill — `--green-fill-15` (green @ ~15%).
  final Color greenFill15;

  /// Resting incoming bubble surface.
  final Color surfaceSubtle;

  /// Focused incoming bubble surface (raised).
  final Color surfaceRaised;

  /// Soft hairline border on resting bubbles.
  final Color borderSoft;

  /// Feed canvas background.
  final Color canvas;

  /// `BackdropFilter` sigma for letters — `--blur-letter`.
  final double blurLetter;

  /// `BackdropFilter` sigma for the floating nav/composer — `--blur-nav`.
  final double blurNav;

  /// Bubble corner radius — `--radius-full` (16).
  final double radiusFull;

  /// Base inter-element spacing unit — `--space-3`.
  final double space3;

  /// Message body text style (folded `AppText.textMessage`).
  final TextStyle textMessage;

  /// Message body line-height multiplier (folded `AppText.leadingMessage`).
  final double leadingMessage;

  /// Meta / label text style (folded `AppText.textMeta`).
  final TextStyle textMeta;

  const FeedTokens({
    required this.teal400,
    required this.tealFill08,
    required this.green500,
    required this.greenFill15,
    required this.surfaceSubtle,
    required this.surfaceRaised,
    required this.borderSoft,
    required this.canvas,
    required this.blurLetter,
    required this.blurNav,
    required this.radiusFull,
    required this.space3,
    required this.textMessage,
    required this.leadingMessage,
    required this.textMeta,
  });

  /// Dark-surface token set (the only theme the app ships today).
  static const FeedTokens dark = FeedTokens(
    teal400: Color(0xFF2DD4BF),
    tealFill08: Color(0x142DD4BF),
    green500: Color(0xFF22C55E),
    greenFill15: Color(0x2622C55E),
    surfaceSubtle: Color(0xBF101218),
    surfaceRaised: Color(0xDB181A20),
    borderSoft: Color(0x1FFFFFFF),
    canvas: Color(0xE60A0A0F),
    blurLetter: 14.0,
    blurNav: 24.0,
    radiusFull: 16.0,
    space3: 12.0,
    textMessage: TextStyle(
      fontSize: 15.5,
      fontWeight: FontWeight.w400,
      color: Color(0xFFF8FAFC),
      height: 1.4,
    ),
    leadingMessage: 1.4,
    textMeta: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      color: Color(0xB8C9CED6),
    ),
  );

  /// Light Signal token set used only when AmbientBackground resolves the
  /// daylight-lagoon storage key to the representative light tone.
  // 248 — the warm Signal Feed hierarchy. Accent is the calmer violet #6045B6;
  // small success text/border is full-opacity #236143 with the #DCE9E1 success
  // fill; canvas/surfaces mirror the mineral ground. Numeric blur/radius/spacing
  // /leading values are unchanged, so geometry/density is identical.
  static const FeedTokens light = FeedTokens(
    teal400: Color(0xFF6045B6),
    tealFill08: Color(0x146045B6),
    green500: Color(0xFF236143),
    greenFill15: Color(0xFFDCE9E1),
    surfaceSubtle: Color(0xFFE1DCE5),
    surfaceRaised: Color(0xFFFAF8F3),
    borderSoft: Color(0xFFB3ACBD),
    canvas: Color(0xFFECE8E1),
    blurLetter: 14.0,
    blurNav: 24.0,
    radiusFull: 16.0,
    space3: 12.0,
    textMessage: TextStyle(
      fontSize: 15.5,
      fontWeight: FontWeight.w400,
      color: Color(0xFF25222B),
      height: 1.4,
    ),
    leadingMessage: 1.4,
    textMeta: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      color: Color(0xFF56515E),
    ),
  );

  @override
  FeedTokens copyWith({
    Color? teal400,
    Color? tealFill08,
    Color? green500,
    Color? greenFill15,
    Color? surfaceSubtle,
    Color? surfaceRaised,
    Color? borderSoft,
    Color? canvas,
    double? blurLetter,
    double? blurNav,
    double? radiusFull,
    double? space3,
    TextStyle? textMessage,
    double? leadingMessage,
    TextStyle? textMeta,
  }) {
    return FeedTokens(
      teal400: teal400 ?? this.teal400,
      tealFill08: tealFill08 ?? this.tealFill08,
      green500: green500 ?? this.green500,
      greenFill15: greenFill15 ?? this.greenFill15,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      borderSoft: borderSoft ?? this.borderSoft,
      canvas: canvas ?? this.canvas,
      blurLetter: blurLetter ?? this.blurLetter,
      blurNav: blurNav ?? this.blurNav,
      radiusFull: radiusFull ?? this.radiusFull,
      space3: space3 ?? this.space3,
      textMessage: textMessage ?? this.textMessage,
      leadingMessage: leadingMessage ?? this.leadingMessage,
      textMeta: textMeta ?? this.textMeta,
    );
  }

  @override
  FeedTokens lerp(ThemeExtension<FeedTokens>? other, double t) {
    if (other is! FeedTokens) {
      return this;
    }
    return FeedTokens(
      teal400: Color.lerp(teal400, other.teal400, t)!,
      tealFill08: Color.lerp(tealFill08, other.tealFill08, t)!,
      green500: Color.lerp(green500, other.green500, t)!,
      greenFill15: Color.lerp(greenFill15, other.greenFill15, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      blurLetter: _lerpDouble(blurLetter, other.blurLetter, t),
      blurNav: _lerpDouble(blurNav, other.blurNav, t),
      radiusFull: _lerpDouble(radiusFull, other.radiusFull, t),
      space3: _lerpDouble(space3, other.space3, t),
      textMessage: TextStyle.lerp(textMessage, other.textMessage, t)!,
      leadingMessage: _lerpDouble(leadingMessage, other.leadingMessage, t),
      textMeta: TextStyle.lerp(textMeta, other.textMeta, t)!,
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// `context.feedTokens` with a const `FeedTokens.dark` fallback (mirrors
/// `BackgroundReadableColorsContext`), so callers never null-check.
extension FeedTokensContext on BuildContext {
  FeedTokens get feedTokens =>
      Theme.of(this).extension<FeedTokens>() ?? FeedTokens.dark;
}
