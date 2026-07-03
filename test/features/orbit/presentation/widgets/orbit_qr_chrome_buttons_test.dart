import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_qr_chrome_buttons.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 196 — twin "My QR" / "Scan" chrome circle buttons (widget tier).
///
/// Locks the toggle-species chrome contract: two 40×40 circles with
/// `surfaceSubtle` fill / 0.5 hairline / 20px `textPrimary` glyph, icon-only
/// with l10n-sourced button Semantics, physical (non-mirroring) centered
/// placement at `safeTop+8`. Donor wrap idiom: `orbit_close_button_test.dart`.
void main() {
  const myQrKey = ValueKey('orbit-my-qr-button');
  const scanKey = ValueKey('orbit-scan-button');

  Widget wrap(
    Widget child, {
    BackgroundReadableColors? colors,
    Locale locale = const Locale('en'),
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [colors ?? BackgroundReadableColors.dark]),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: padding),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(children: [child]),
          ),
        ),
      ),
    );
  }

  Container circleContainer(WidgetTester tester, Key key) {
    return tester.widget<Container>(
      find.descendant(of: find.byKey(key), matching: find.byType(Container)),
    );
  }

  Icon glyph(WidgetTester tester, Key key) {
    return tester.widget<Icon>(
      find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
    );
  }

  group('OrbitQrChromeButtons', () {
    testWidgets('renders two 40px chrome circles with toggle-species tokens', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(OrbitQrChromeButtons(onMyQR: () {}, onScanQR: () {})),
      );

      expect(find.byKey(myQrKey), findsOneWidget);
      expect(find.byKey(scanKey), findsOneWidget);

      const dark = BackgroundReadableColors.dark;
      for (final key in const [myQrKey, scanKey]) {
        expect(tester.getSize(find.byKey(key)), const Size(40, 40));
        final decoration = circleContainer(tester, key).decoration as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        expect(decoration.color, dark.surfaceSubtle);
        expect((decoration.border as Border).top.width, 0.5);
        expect((decoration.border as Border).top.color, dark.border);
      }
    });

    testWidgets('shows qr_code and camera_alt_outlined at 20px textPrimary', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(OrbitQrChromeButtons(onMyQR: () {}, onScanQR: () {})),
      );

      const dark = BackgroundReadableColors.dark;
      final myGlyph = glyph(tester, myQrKey);
      expect(myGlyph.icon, Icons.qr_code);
      expect(myGlyph.size, 20);
      expect(myGlyph.color, dark.textPrimary);

      final scanGlyph = glyph(tester, scanKey);
      expect(scanGlyph.icon, Icons.camera_alt_outlined);
      expect(scanGlyph.size, 20);
      expect(scanGlyph.color, dark.textPrimary);
    });

    testWidgets('exposes button semantics labeled from l10n (en)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(OrbitQrChromeButtons(onMyQR: () {}, onScanQR: () {})),
      );

      expect(find.bySemanticsLabel('My QR'), findsOneWidget);
      expect(find.bySemanticsLabel('Scan'), findsOneWidget);

      final myData = tester
          .getSemantics(find.bySemanticsLabel('My QR'))
          .getSemanticsData();
      expect(myData.flagsCollection.isButton, isTrue);
      final scanData = tester
          .getSemantics(find.bySemanticsLabel('Scan'))
          .getSemanticsData();
      expect(scanData.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('semantics labels localize (ar)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          OrbitQrChromeButtons(onMyQR: () {}, onScanQR: () {}),
          locale: const Locale('ar'),
        ),
      );

      expect(find.bySemanticsLabel('رمزي'), findsOneWidget);
      expect(find.bySemanticsLabel('مسح'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('tap My QR fires onMyQR only', (tester) async {
      var myQrTaps = 0;
      var scanTaps = 0;
      await tester.pumpWidget(
        wrap(
          OrbitQrChromeButtons(
            onMyQR: () => myQrTaps++,
            onScanQR: () => scanTaps++,
          ),
        ),
      );

      await tester.tap(find.byKey(myQrKey));
      expect(myQrTaps, 1);
      expect(scanTaps, 0);
    });

    testWidgets('tap Scan fires onScanQR only', (tester) async {
      var myQrTaps = 0;
      var scanTaps = 0;
      await tester.pumpWidget(
        wrap(
          OrbitQrChromeButtons(
            onMyQR: () => myQrTaps++,
            onScanQR: () => scanTaps++,
          ),
        ),
      );

      await tester.tap(find.byKey(scanKey));
      expect(scanTaps, 1);
      expect(myQrTaps, 0);
    });

    testWidgets('keeps physical order under RTL', (tester) async {
      await tester.pumpWidget(
        wrap(
          OrbitQrChromeButtons(onMyQR: () {}, onScanQR: () {}),
          locale: const Locale('ar'),
        ),
      );

      final myCenter = tester.getCenter(find.byKey(myQrKey));
      final scanCenter = tester.getCenter(find.byKey(scanKey));
      // Fixed LTR Row: My QR stays physically left of Scan even under RTL.
      expect(myCenter.dx, lessThan(scanCenter.dx));
    });

    testWidgets('resolves the light readable tone on daylight preference', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;
      await tester.pumpWidget(
        wrap(OrbitQrChromeButtons(onMyQR: () {}, onScanQR: () {}), colors: colors),
      );

      final decoration =
          circleContainer(tester, myQrKey).decoration as BoxDecoration;
      expect(decoration.color, colors.surfaceSubtle); // light fill
      expect(glyph(tester, myQrKey).color, colors.textPrimary); // dark glyph
    });

    testWidgets('pair is centered with an 8px gap at top safeTop+8', (
      tester,
    ) async {
      const topPad = 40.0;
      await tester.pumpWidget(
        wrap(
          OrbitQrChromeButtons(onMyQR: () {}, onScanQR: () {}),
          padding: const EdgeInsets.only(top: topPad),
        ),
      );

      final myRect = tester.getRect(find.byKey(myQrKey));
      final scanRect = tester.getRect(find.byKey(scanKey));

      // Top edge sits at padding.top + 8 on both buttons.
      expect(myRect.top, moreOrLessEquals(topPad + 8, epsilon: 0.5));
      expect(scanRect.top, moreOrLessEquals(topPad + 8, epsilon: 0.5));
      // 8px gap between the pair.
      expect(scanRect.left - myRect.right, moreOrLessEquals(8, epsilon: 0.5));
      // Symmetric about the screen center (±1).
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        (myRect.left + scanRect.right) / 2,
        moreOrLessEquals(width / 2, epsilon: 1),
      );
    });
  });
}
