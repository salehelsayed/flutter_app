import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit3/presentation/screens/orbit3_screen.dart';
import 'package:flutter_app/features/orbit3/presentation/widgets/orbit3_fisheye_prototype.dart';
import 'package:flutter_app/features/orbit3/presentation/widgets/orbit3_inner_sky_prototype.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Lightweight render smoke checks for the two scalability prototypes (Inner+Sky,
/// Fisheye). They are visuals-only throwaway directions, so this just guards that
/// the wiring mounts, switches, and survives the dense population + the headline
/// interactions WITHOUT throwing a layout/runtime exception.
void main() {
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(440, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget wrap() => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Orbit3Screen(userPeerId: 'me-peer'),
      );

  Future<void> drain(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2400));
  }

  // Tap the lab cycler [n] times (classic -> innerSky -> fisheye -> classic).
  Future<void> cycleLab(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.tap(find.byKey(const ValueKey('orbit3-lab-cycler')));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await drain(tester);
  }

  Future<void> goToPop50(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      if (find.text('50').evaluate().isNotEmpty) break;
      await tester.tap(find.byKey(const ValueKey('orbit3-population-cycler')));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await drain(tester);
  }

  testWidgets('lab cycler switches into Inner+Sky and back without error',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await drain(tester);

    await cycleLab(tester, 1);
    expect(find.byType(Orbit3InnerSkyPrototype), findsOneWidget);
    expect(find.byKey(const ValueKey('proto-a-drawer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inner+Sky at population 50: launch to Sky and return, no error',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await drain(tester);

    await cycleLab(tester, 1); // innerSky
    await goToPop50(tester);

    // "+N" node launches to the Sky (constellation) instead of growing rings.
    await tester.tap(find.byKey(const ValueKey('orbit3-expand-toggle')));
    await tester.pump(const Duration(milliseconds: 350));
    await drain(tester);
    expect(find.byKey(const ValueKey('proto-a-return-inner')), findsOneWidget);

    // Back to the Inner Orbit.
    await tester.tap(find.byKey(const ValueKey('proto-a-return-inner')));
    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fisheye at population 50 renders and travels without error',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await drain(tester);

    await cycleLab(tester, 2); // fisheye
    expect(find.byType(Orbit3FisheyePrototype), findsOneWidget);
    await goToPop50(tester);

    // Drag up to "climb" outward through the tiers.
    await tester.drag(
        find.byType(Orbit3FisheyePrototype), const Offset(0, -180));
    await drain(tester);
    expect(tester.takeException(), isNull);
  });
}
