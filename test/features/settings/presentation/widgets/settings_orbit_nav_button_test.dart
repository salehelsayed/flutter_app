import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_orbit_nav_button.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void suppressAssetErrors(WidgetTester tester) {
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('Unable to load asset') ||
          message.contains('SvgPicture')) {
        return;
      }
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);
  }

  Widget wrap(BackgroundReadableColors colors, {VoidCallback? onTap}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [colors]),
      home: Scaffold(
        body: Center(child: SettingsOrbitNavButton(onTap: onTap ?? () {})),
      ),
    );
  }

  group('SettingsOrbitNavButton', () {
    testWidgets(
      'TC-226-04 renders 52px glass circle with border, blur, shadow, '
      'and nav_orbit icon 24',
      (tester) async {
        suppressAssetErrors(tester);

        await tester.pumpWidget(wrap(BackgroundReadableColors.dark));
        await tester.pump();

        expect(
          tester.getSize(find.byType(SettingsOrbitNavButton)),
          const Size(52, 52),
        );

        final outer = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(SettingsOrbitNavButton),
                matching: find.byType(Container),
              )
              .first,
        );
        final outerDecoration = outer.decoration as BoxDecoration;
        expect(outerDecoration.boxShadow, isNotNull);
        expect(outerDecoration.boxShadow, isNotEmpty);
        expect(
          outerDecoration.boxShadow!.single.color,
          const Color(0x59000000),
        );
        expect(outerDecoration.boxShadow!.single.blurRadius, 18);
        expect(outerDecoration.boxShadow!.single.offset, const Offset(0, 6));

        expect(
          find.descendant(
            of: find.byType(SettingsOrbitNavButton),
            matching: find.byType(ClipOval),
          ),
          findsOneWidget,
        );
        final backdrop = tester.widget<BackdropFilter>(
          find.descendant(
            of: find.byType(SettingsOrbitNavButton),
            matching: find.byType(BackdropFilter),
          ),
        );
        expect(backdrop.filter.toString(), contains('12'));

        final inner = tester.widget<Container>(
          find.descendant(
            of: find.byType(BackdropFilter),
            matching: find.byType(Container),
          ),
        );
        final innerDecoration = inner.decoration as BoxDecoration;
        expect(
          innerDecoration.color,
          BackgroundReadableColors.dark.glassSurface,
        );
        expect(
          (innerDecoration.border as Border).top.color,
          BackgroundReadableColors.dark.glassBorder,
        );

        final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(svg.width, 24);
        expect(svg.height, 24);
        expect(
          svg.colorFilter,
          ColorFilter.mode(
            BackgroundReadableColors.dark.iconPrimary,
            BlendMode.srcIn,
          ),
        );
        expect(svg.bytesLoader.toString(), contains('nav_orbit.svg'));
      },
    );

    testWidgets('TC-226-05 daylight tone uses light glass tokens', (
      tester,
    ) async {
      suppressAssetErrors(tester);
      const colors = BackgroundReadableColors.representativeLight;

      await tester.pumpWidget(wrap(colors));
      await tester.pump();

      final inner = tester.widget<Container>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(Container),
        ),
      );
      final decoration = inner.decoration as BoxDecoration;
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));

      expect(decoration.color, colors.glassSurface);
      expect((decoration.border as Border).top.color, colors.glassBorder);
      expect(
        svg.colorFilter,
        ColorFilter.mode(colors.iconPrimary, BlendMode.srcIn),
      );
    });

    testWidgets('TC-226-06 exposes Semantics button label and fires onTap', (
      tester,
    ) async {
      suppressAssetErrors(tester);
      final handle = tester.ensureSemantics();
      var taps = 0;

      await tester.pumpWidget(
        wrap(BackgroundReadableColors.dark, onTap: () => taps++),
      );
      await tester.pump();

      final orbit = find.bySemanticsLabel('Orbit');
      expect(orbit, findsOneWidget);
      expect(tester.getSemantics(orbit), isSemantics(isButton: true));

      await tester.tap(find.byType(SettingsOrbitNavButton));
      expect(taps, 1);
      handle.dispose();
    });
  });
}
