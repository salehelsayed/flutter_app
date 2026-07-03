import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_edit_handle.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';

/// 198 fidelity — the extracted geometry-handle widget (M1–M4, M2 pulse,
/// TC-198-59, INV-F7). Visual contract locked at the widget tier so the wired
/// suite can stay positional.
void main() {
  final en = AppLocalizationsEn();
  final labels = <OrbitKnob, String>{
    OrbitKnob.avatarScale: en.orbit_handle_avatar_size,
    OrbitKnob.spacingScale: en.orbit_handle_ring_spacing,
    OrbitKnob.arcWrap: en.orbit_handle_arc_wrap,
    OrbitKnob.maxPerArc: en.orbit_handle_max_per_arc,
    OrbitKnob.orbitGap: en.orbit_handle_orbit_gap,
  };

  Widget wrap(
    Widget child, {
    bool disableAnimations = false,
    bool accessibleNavigation = false,
  }) =>
      MaterialApp(
        theme: ThemeData(extensions: [BackgroundReadableColors.dark]),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: disableAnimations,
              accessibleNavigation: accessibleNavigation,
            ),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      );

  Widget handle(OrbitKnob knob, {bool armed = false}) => OrbitEditHandle(
        knob: knob,
        label: labels[knob]!,
        armed: armed,
        onArm: () {},
        onPanStart: (_) {},
        onPanUpdate: (_) {},
        onPanEnd: (_) {},
      );

  Finder discF(OrbitKnob knob) =>
      find.byKey(ValueKey('orbit-handle-disc-${knob.name}'));

  BoxDecoration discDeco(WidgetTester tester, OrbitKnob knob) =>
      tester.widget<Container>(discF(knob)).decoration! as BoxDecoration;

  testWidgets(
      'handle visual contract: circular disc in ≥44pt target, per-knob icon, tip-pill below',
      (tester) async {
    for (final knob in OrbitKnob.values) {
      await tester.pumpWidget(wrap(handle(knob)));
      await tester.pump();

      // ≥44pt hit target on the keyed gesture surface (INV-F7, spec decision #9).
      final target = find.byKey(ValueKey('orbit-handle-${knob.name}'));
      expect(target, findsOneWidget, reason: '${knob.name} gesture target');
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44), reason: knob.name);
      expect(size.height, greaterThanOrEqualTo(44), reason: knob.name);

      // ~30px circular disc.
      final discSize = tester.getSize(discF(knob));
      expect(discSize.width, closeTo(30, 0.5), reason: knob.name);
      expect(discSize.height, closeTo(30, 0.5), reason: knob.name);
      final deco = discDeco(tester, knob);
      expect(deco.shape, BoxShape.circle, reason: knob.name);

      // Per-knob icon, keyed and carrying its own knob (a swap re-reds this).
      final iconF = find.byKey(ValueKey('orbit-handle-icon-${knob.name}'));
      expect(iconF, findsOneWidget, reason: '${knob.name} icon');
      final painter = tester.widget<CustomPaint>(iconF).painter;
      expect((painter! as OrbitHandleIconPainter).knob, knob);

      // Tip-pill below the disc: the l10n name plus a SEPARATE letter-free
      // glyph Text (↕/⟷ never enters the l10n value or the Semantics label).
      final nameF = find.text(labels[knob]!);
      expect(nameF, findsOneWidget, reason: '${knob.name} tip name');
      final glyph = knob == OrbitKnob.maxPerArc ? '⟷' : '↕';
      final glyphF = find.text(glyph);
      expect(glyphF, findsOneWidget, reason: '${knob.name} glyph');
      final discCenter = tester.getCenter(discF(knob));
      expect(tester.getCenter(nameF).dy, greaterThan(discCenter.dy),
          reason: '${knob.name} tip sits below the disc');
      expect(tester.getCenter(glyphF).dy, greaterThan(discCenter.dy),
          reason: '${knob.name} glyph sits below the disc');
    }
  });

  testWidgets('TC-198F-11 armed treatment: teal halo; unarmed: green border',
      (tester) async {
    await tester.pumpWidget(wrap(handle(OrbitKnob.avatarScale)));
    await tester.pump();
    var deco = discDeco(tester, OrbitKnob.avatarScale);
    expect((deco.border! as Border).top.color, const Color(0xFF1ED760));
    expect(deco.boxShadow, isNotEmpty);
    expect(deco.boxShadow!.first.color, const Color(0xCC1DB954));

    await tester.pumpWidget(wrap(handle(OrbitKnob.avatarScale, armed: true)));
    await tester.pump();
    deco = discDeco(tester, OrbitKnob.avatarScale);
    expect((deco.border! as Border).top.color, const Color(0xFF4ECDC4));
    expect(deco.boxShadow, isNotEmpty);
    expect(deco.boxShadow!.first.color, const Color(0xCC4ECDC4));
    expect(deco.color, const Color(0x4D4ECDC4),
        reason: 'armed disc gets the translucent teal fill');
  });

  testWidgets('TC-198-59 unarmed pulse animates the halo', (tester) async {
    await tester.pumpWidget(wrap(handle(OrbitKnob.spacingScale)));
    await tester.pump();
    final b0 =
        discDeco(tester, OrbitKnob.spacingScale).boxShadow!.first.blurRadius;
    await tester.pump(const Duration(milliseconds: 800)); // half the period
    final b1 =
        discDeco(tester, OrbitKnob.spacingScale).boxShadow!.first.blurRadius;
    expect(b1, isNot(closeTo(b0, 0.01)), reason: 'pulse breathes the halo');
  });

  testWidgets(
      'TC-198-59 pulse frozen under disableAnimations AND accessibleNavigation; handle stays visible',
      (tester) async {
    for (final mode in ['disableAnimations', 'accessibleNavigation']) {
      await tester.pumpWidget(wrap(
        handle(OrbitKnob.spacingScale),
        disableAnimations: mode == 'disableAnimations',
        accessibleNavigation: mode == 'accessibleNavigation',
      ));
      await tester.pump();
      final b0 =
          discDeco(tester, OrbitKnob.spacingScale).boxShadow!.first.blurRadius;
      await tester.pump(const Duration(milliseconds: 800));
      final b1 =
          discDeco(tester, OrbitKnob.spacingScale).boxShadow!.first.blurRadius;
      expect(b1, closeTo(b0, 1e-9), reason: '$mode freezes the pulse');
      expect(discF(OrbitKnob.spacingScale), findsOneWidget,
          reason: 'handle stays statically visible under $mode');
    }
  });
}
