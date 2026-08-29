/// Production-visible rendering seams for the opt-in Orbit visual treatment.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// Opt-in visual treatment for the isolated Orbit experiment.
///
/// [current] is deliberately the default everywhere. The experiment changes
/// rendering only; Orbit state, geometry, gestures, and navigation stay owned
/// by the existing production widgets.
enum OrbitVisualTreatment { current, orbitalQuiet, orbitalQuietV2 }

/// Tiny, runtime-selectable alternatives used to settle the V2 state grammar.
/// They do not alter unread, selection, or relationship state itself.
enum OrbitalQuietStateGrammar { ring, arc, halo }

/// Runtime alternatives for the center/self node. All three retain the same
/// 48px box, center point, semantics, and interaction.
enum OrbitalQuietSelfTreatment { neutralCore, layeredCore, chartAnchor }

@immutable
class OrbitalQuietV2Options {
  final OrbitalQuietStateGrammar stateGrammar;
  final OrbitalQuietSelfTreatment selfTreatment;
  final bool localAtmosphere;
  final bool densityScale;
  final bool refinedNeutralControls;

  const OrbitalQuietV2Options({
    this.stateGrammar = OrbitalQuietStateGrammar.ring,
    this.selfTreatment = OrbitalQuietSelfTreatment.neutralCore,
    this.localAtmosphere = true,
    this.densityScale = true,
    this.refinedNeutralControls = true,
  });

  OrbitalQuietV2Options copyWith({
    OrbitalQuietStateGrammar? stateGrammar,
    OrbitalQuietSelfTreatment? selfTreatment,
    bool? localAtmosphere,
    bool? densityScale,
    bool? refinedNeutralControls,
  }) => OrbitalQuietV2Options(
    stateGrammar: stateGrammar ?? this.stateGrammar,
    selfTreatment: selfTreatment ?? this.selfTreatment,
    localAtmosphere: localAtmosphere ?? this.localAtmosphere,
    densityScale: densityScale ?? this.densityScale,
    refinedNeutralControls:
        refinedNeutralControls ?? this.refinedNeutralControls,
  );

  @override
  bool operator ==(Object other) =>
      other is OrbitalQuietV2Options &&
      other.stateGrammar == stateGrammar &&
      other.selfTreatment == selfTreatment &&
      other.localAtmosphere == localAtmosphere &&
      other.densityScale == densityScale &&
      other.refinedNeutralControls == refinedNeutralControls;

  @override
  int get hashCode => Object.hash(
    stateGrammar,
    selfTreatment,
    localAtmosphere,
    densityScale,
    refinedNeutralControls,
  );
}

/// Deterministic presentation-only scale experiment. It does not alter ring
/// assignment, angular ordering, or the placement engine's source geometry.
double orbitalQuietV2ScaleForCount(int count) {
  if (count <= 1) return 1.16;
  if (count <= 5) return 1.12;
  if (count <= 12) return 1.04;
  return 1;
}

class OrbitVisualScope extends InheritedWidget {
  final OrbitVisualTreatment treatment;

  /// Prototype-only focus evidence. The production Orbit does not keep a
  /// persistent selected node because tapping a node opens its conversation.
  final Set<int> focusedIndices;
  final OrbitalQuietV2Options v2Options;

  const OrbitVisualScope({
    super.key,
    required this.treatment,
    this.focusedIndices = const <int>{},
    this.v2Options = const OrbitalQuietV2Options(),
    required super.child,
  });

  static OrbitVisualScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrbitVisualScope>();

  static OrbitVisualTreatment treatmentOf(BuildContext context) =>
      maybeOf(context)?.treatment ?? OrbitVisualTreatment.current;

  static Set<int> focusedIndicesOf(BuildContext context) =>
      maybeOf(context)?.focusedIndices ?? const <int>{};

  static OrbitalQuietV2Options v2OptionsOf(BuildContext context) =>
      maybeOf(context)?.v2Options ?? const OrbitalQuietV2Options();

  static bool isQuietOf(BuildContext context) =>
      treatmentOf(context) != OrbitVisualTreatment.current;

  @override
  bool updateShouldNotify(covariant OrbitVisualScope oldWidget) =>
      oldWidget.treatment != treatment ||
      oldWidget.focusedIndices != focusedIndices ||
      oldWidget.v2Options != v2Options;
}

/// Local background/theme scope used only by the Orbital Quiet prototype.
/// It intentionally does not add app-wide tokens or a new background setting.
class OrbitalQuietBackground extends StatelessWidget {
  final bool light;
  final bool neutralGlobalActions;
  final bool version2;
  final bool localAtmosphere;
  final Widget child;

  const OrbitalQuietBackground({
    super.key,
    required this.light,
    this.neutralGlobalActions = false,
    this.version2 = false,
    this.localAtmosphere = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = switch ((light, version2, neutralGlobalActions)) {
      (true, true, _) => OrbitalQuietPalette.lightV2,
      (false, true, _) => OrbitalQuietPalette.darkV2,
      (true, false, true) => OrbitalQuietPalette.lightNeutralActions,
      (true, false, false) => OrbitalQuietPalette.light,
      (false, false, true) => OrbitalQuietPalette.darkNeutralActions,
      (false, false, false) => OrbitalQuietPalette.dark,
    };
    final theme = Theme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: colors.systemUiOverlayStyle,
      child: Theme(
        data: theme.copyWith(
          brightness: light ? Brightness.light : Brightness.dark,
          extensions: [
            ...theme.extensions.values.where(
              (extension) => extension is! BackgroundReadableColors,
            ),
            colors,
          ],
        ),
        child: ColoredBox(
          color: light
              ? (version2
                    ? OrbitalQuietPalette.lightCanvasV2
                    : OrbitalQuietPalette.lightCanvas)
              : (version2
                    ? OrbitalQuietPalette.darkCanvasV2
                    : OrbitalQuietPalette.darkCanvas),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: _OrbitalQuietCanvasPainter(
                    light: light,
                    version2: version2,
                    localAtmosphere: localAtmosphere,
                  ),
                ),
              ),
              RepaintBoundary(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class OrbitalQuietPalette {
  static const darkCanvas = Color(0xFF060A11);
  static const lightCanvas = Color(0xFFF1F6F8);
  static const darkCanvasV2 = Color(0xFF070B12);
  static const lightCanvasV2 = Color(0xFFF3F7F8);
  static const darkAction = Color(0xFF7CC8F5);
  static const lightAction = Color(0xFF176B93);
  static const connectedDark = Color(0xFF54D68A);
  static const connectedLight = Color(0xFF1D7447);
  static const darkNeutralAction = Color(0xFFA5B2BA);
  static const lightNeutralAction = Color(0xFF52636D);

  static final BackgroundReadableColors dark = BackgroundReadableColors.dark
      .copyWith(
        textPrimary: const Color(0xFFF4F7F9),
        textSecondary: const Color(0xFFC1CBD2),
        textMuted: const Color(0xFF96A4AF),
        iconPrimary: const Color(0xFFE8EFF3),
        iconSecondary: const Color(0xFFC1CBD2),
        iconMuted: const Color(0xFF96A4AF),
        surfaceBase: const Color(0xF20B111A),
        surfaceRaised: const Color(0xF2151D27),
        surfaceSubtle: const Color(0xD90B111A),
        glassSurface: const Color(0xE60B111A),
        glassBorder: const Color(0x99546576),
        border: const Color(0x99546576),
        surfaceBorder: const Color(0x4D546576),
        divider: const Color(0x33546576),
        inputFill: const Color(0xF2151D27),
        inputBorder: const Color(0x99546576),
        placeholderText: const Color(0xFF96A4AF),
        accent: connectedDark,
        accentIcon: const Color(0xFF06110C),
        ring1: const Color(0x59597286),
        ring2: const Color(0x525D7D83),
        ringGlow: Colors.transparent,
        ctaBg: const Color(0xF20B111A),
        ctaIcon: darkAction,
        ctaMenuFill: const Color(0xF2151D27),
        ctaMenuBorder: const Color(0x66546576),
        ctaMenuText: const Color(0xFFF4F7F9),
        navActive: darkAction,
        navInactive: const Color(0xFF96A4AF),
        navActiveFill: const Color(0x1F7CC8F5),
        nodeSelfGlow: connectedDark,
        nodeContactGlow: Colors.transparent,
        connectedHeading: connectedDark,
        statusBarIconBrightness: Brightness.light,
        navigationBarIconBrightness: Brightness.light,
      );

  static final BackgroundReadableColors light = BackgroundReadableColors
      .representativeLight
      .copyWith(
        textPrimary: const Color(0xFF18252E),
        textSecondary: const Color(0xFF465761),
        textMuted: const Color(0xFF61717B),
        iconPrimary: const Color(0xFF263842),
        iconSecondary: const Color(0xFF465761),
        iconMuted: const Color(0xFF61717B),
        surfaceBase: const Color(0xFFF8FBFC),
        surfaceRaised: const Color(0xFFFFFFFF),
        surfaceSubtle: const Color(0xF2FFFFFF),
        glassSurface: const Color(0xF2FFFFFF),
        glassBorder: const Color(0xFF9AADB8),
        border: const Color(0xFF8FA3AE),
        surfaceBorder: const Color(0xFFCDD9DF),
        divider: const Color(0xFFCFDCE2),
        inputFill: const Color(0xFFFFFFFF),
        inputBorder: const Color(0xFF8FA3AE),
        placeholderText: const Color(0xFF61717B),
        disabledSurface: const Color(0xFFE3EBEF),
        accent: connectedLight,
        accentIcon: const Color(0xFFFFFFFF),
        ring1: const Color(0x667894A6),
        ring2: const Color(0x66789C9C),
        ringGlow: Colors.transparent,
        ctaBg: const Color(0xFFFFFFFF),
        ctaIcon: lightAction,
        ctaMenuFill: const Color(0xFFFFFFFF),
        ctaMenuBorder: const Color(0xFF9AADB8),
        ctaMenuText: const Color(0xFF18252E),
        navActive: lightAction,
        navInactive: const Color(0xFF61717B),
        navActiveFill: const Color(0x1F176B93),
        nodeSelfGlow: connectedLight,
        nodeContactGlow: Colors.transparent,
        connectedHeading: connectedLight,
        statusBarIconBrightness: Brightness.dark,
        navigationBarIconBrightness: Brightness.dark,
      );

  static final BackgroundReadableColors darkNeutralActions = dark.copyWith(
    ctaIcon: darkNeutralAction,
    navActive: darkNeutralAction,
    navActiveFill: const Color(0x1FA5B2BA),
  );

  static final BackgroundReadableColors lightNeutralActions = light.copyWith(
    ctaIcon: lightNeutralAction,
    navActive: lightNeutralAction,
    navActiveFill: const Color(0x1F52636D),
  );

  static final BackgroundReadableColors darkV2 = darkNeutralActions.copyWith(
    surfaceBase: const Color(0xF20C121A),
    surfaceRaised: const Color(0xF2141C25),
    surfaceSubtle: const Color(0xE60C121A),
    glassSurface: const Color(0xE60C121A),
    glassBorder: const Color(0x805C6B77),
    border: const Color(0x8A5C6B77),
    surfaceBorder: const Color(0x425C6B77),
    ring1: const Color(0x526C8490),
    ring2: const Color(0x4A6D8787),
    ctaBg: const Color(0xE60C121A),
    ctaIcon: const Color(0xFFB5C0C7),
    navActive: const Color(0xFFB5C0C7),
    navActiveFill: const Color(0x14B5C0C7),
    nodeSelfGlow: Colors.transparent,
  );

  static final BackgroundReadableColors lightV2 = lightNeutralActions.copyWith(
    surfaceBase: const Color(0xF7FAFCFD),
    surfaceRaised: const Color(0xFFFFFFFF),
    surfaceSubtle: const Color(0xF2FAFCFD),
    glassSurface: const Color(0xF7FAFCFD),
    glassBorder: const Color(0xFFADBBC2),
    border: const Color(0xFF9EAFB7),
    surfaceBorder: const Color(0xFFCFDADF),
    ring1: const Color(0x707A949F),
    ring2: const Color(0x687A9998),
    ctaBg: const Color(0xFFFAFCFD),
    ctaIcon: const Color(0xFF50616A),
    navActive: const Color(0xFF50616A),
    navActiveFill: const Color(0x1250616A),
    nodeSelfGlow: Colors.transparent,
  );
}

class _OrbitalQuietCanvasPainter extends CustomPainter {
  final bool light;
  final bool version2;
  final bool localAtmosphere;

  const _OrbitalQuietCanvasPainter({
    required this.light,
    required this.version2,
    required this.localAtmosphere,
  });

  static const _darkStars = <Offset>[
    Offset(.06, .12),
    Offset(.18, .31),
    Offset(.31, .16),
    Offset(.43, .37),
    Offset(.57, .11),
    Offset(.71, .29),
    Offset(.86, .17),
    Offset(.94, .42),
    Offset(.09, .57),
    Offset(.26, .74),
    Offset(.48, .63),
    Offset(.64, .82),
    Offset(.81, .69),
    Offset(.92, .88),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (!version2) {
      final wash = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.15, .18),
          radius: 1.05,
          colors: light
              ? const [Color(0x24A9D6E8), Color(0x00F1F6F8)]
              : const [Color(0x33163447), Color(0x00060A11)],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, wash);
    } else if (localAtmosphere) {
      final diameter = size.width * 1.18;
      final fieldRect = Rect.fromCenter(
        center: Offset(size.width * .5, size.height * .53),
        width: diameter,
        height: diameter,
      );
      final field = Paint()
        ..shader = RadialGradient(
          colors: light
              ? const [Color(0x1E8CB5C2), Color(0x0C9EC4CE), Color(0x00F3F7F8)]
              : const [Color(0x2A1C3340), Color(0x14142531), Color(0x00070B12)],
          stops: const [0, .48, 1],
        ).createShader(fieldRect);
      canvas.drawOval(fieldRect, field);
    }

    final starPaint = Paint()
      ..color = light
          ? (version2 ? const Color(0x1C4B7891) : const Color(0x244B7891))
          : (version2 ? const Color(0x2CE7F2FF) : const Color(0x36E7F2FF));
    for (var i = 0; i < _darkStars.length; i++) {
      final star = _darkStars[i];
      final radius = i.isEven ? .75 : .5;
      canvas.drawCircle(
        Offset(star.dx * size.width, star.dy * size.height),
        radius,
        starPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitalQuietCanvasPainter oldDelegate) =>
      oldDelegate.light != light ||
      oldDelegate.version2 != version2 ||
      oldDelegate.localAtmosphere != localAtmosphere;
}
