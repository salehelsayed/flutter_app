import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit3/application/orbit3_mock_data.dart';
import 'package:flutter_app/features/orbit3/presentation/widgets/orbit3_arch_panel.dart';
import 'package:flutter_app/features/orbit3/presentation/widgets/orbit3_one_circle.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Widget coverage for the two additive [Orbit3OneCircle] knobs introduced for
/// the Arch redesign: [Orbit3OneCircle.showOverflowNode] (so the classic One
/// Circle can hide the in-ring "+N" node while InnerSky keeps it) and
/// [Orbit3OneCircle.avatarScale] (the +/- avatar-size stepper).
void main() {
  void tall(WidgetTester t) {
    t.view.physicalSize = const Size(440, 950);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
  }

  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      );

  // Drain the staggered OrbitalAvatar entrance timers (globalIndex * 40ms).
  Future<void> drain(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 2400));
  }

  Set<double> avatarSizes(WidgetTester t) => t
      .widgetList<OrbitalAvatar>(find.byType(OrbitalAvatar))
      .map((a) => a.size)
      .toSet();

  testWidgets('showOverflowNode:false suppresses the in-ring expand node '
      '(classic One Circle, capped at 2 rings)', (t) async {
    tall(t);
    await t.pumpWidget(wrap(Orbit3OneCircle(
      userPeerId: 'me',
      items: Orbit3MockData.build(count: 24),
      cappedRings: 2,
      showOverflowNode: false,
    )));
    await drain(t);

    expect(find.byKey(const ValueKey('orbit3-expand-toggle')), findsNothing);
    expect(find.byType(OrbitalAvatar), findsNWidgets(13)); // 2 rings, no node
  });

  testWidgets('default showOverflowNode keeps the in-ring node (InnerSky '
      'contract: cappedRings:3 + onToggleExpand)', (t) async {
    tall(t);
    await t.pumpWidget(wrap(Orbit3OneCircle(
      userPeerId: 'me',
      items: Orbit3MockData.build(count: 50),
      cappedRings: 3,
      onToggleExpand: () {},
    )));
    await drain(t);

    expect(find.byKey(const ValueKey('orbit3-expand-toggle')), findsOneWidget);
  });

  testWidgets('avatarScale multiplies member avatar diameters', (t) async {
    tall(t);
    await t.pumpWidget(wrap(Orbit3OneCircle(
      userPeerId: 'me',
      items: Orbit3MockData.build(count: 13), // two full rings: base {38, 30}
      avatarScale: 1.4,
    )));
    await drain(t);

    final sizes = avatarSizes(t);
    expect(sizes.reduce(max), closeTo(38 * 1.4, 1e-6)); // ring 0 grown
    expect(sizes.reduce(min), closeTo(30 * 1.4, 1e-6)); // ring 1 grown
  });

  testWidgets('avatarScale default 1.0 leaves Orbit-parity sizes {38, 30}',
      (t) async {
    tall(t);
    await t.pumpWidget(wrap(Orbit3OneCircle(
      userPeerId: 'me',
      items: Orbit3MockData.build(count: 13),
    )));
    await drain(t);

    expect(avatarSizes(t), {38.0, 30.0});
  });

  testWidgets('Orbit3ArchBar renders compact (height <= 38) to match the chips',
      (t) async {
    tall(t);
    await t.pumpWidget(wrap(Orbit3ArchBar(count: 37, onTap: () {})));
    await drain(t);

    final size = t.getSize(find.byType(Orbit3ArchBar));
    expect(size.height, lessThanOrEqualTo(38.0));
    expect(find.text('+37'), findsOneWidget);
    expect(find.byIcon(Icons.people_alt_rounded), findsOneWidget);
  });
}
