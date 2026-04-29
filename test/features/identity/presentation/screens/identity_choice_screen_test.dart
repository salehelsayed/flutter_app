import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_screen.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/brand_header.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  // AmbientBackground uses a forever-repeating AnimationController,
  // so pumpAndSettle() would time out. Instead we pump past the
  // staggered entry animation duration (1200ms) with a fixed duration.
  Future<void> pumpPastAnimations(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1300));
  }

  group('IdentityChoiceScreen', () {
    testWidgets('renders BrandHeader', (tester) async {
      await tester.pumpWidget(
        wrap(IdentityChoiceScreen(onNewHere: () {}, onLoadMyKey: () {})),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(BrandHeader), findsOneWidget);
    });

    testWidgets('renders two ChoiceCards', (tester) async {
      await tester.pumpWidget(
        wrap(IdentityChoiceScreen(onNewHere: () {}, onLoadMyKey: () {})),
      );
      await pumpPastAnimations(tester);
      expect(find.text("I'm new here"), findsOneWidget);
      expect(find.text('Load my key'), findsOneWidget);
    });

    testWidgets('renders "I\'m new here" card text', (tester) async {
      await tester.pumpWidget(
        wrap(IdentityChoiceScreen(onNewHere: () {}, onLoadMyKey: () {})),
      );
      await pumpPastAnimations(tester);
      expect(find.text("I'm new here"), findsOneWidget);
      expect(find.text('Generate a fresh identity'), findsOneWidget);
    });

    testWidgets('renders "Load my key" card text', (tester) async {
      await tester.pumpWidget(
        wrap(IdentityChoiceScreen(onNewHere: () {}, onLoadMyKey: () {})),
      );
      await pumpPastAnimations(tester);
      expect(find.text('Load my key'), findsOneWidget);
      expect(find.text('Restore from recovery phrase'), findsOneWidget);
    });

    testWidgets('renders privacy footer with lock icon', (tester) async {
      await tester.pumpWidget(
        wrap(IdentityChoiceScreen(onNewHere: () {}, onLoadMyKey: () {})),
      );
      await pumpPastAnimations(tester);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Only you can read your messages'), findsOneWidget);
    });

    testWidgets('renders Scaffold with dark background', (tester) async {
      await tester.pumpWidget(
        wrap(IdentityChoiceScreen(onNewHere: () {}, onLoadMyKey: () {})),
      );
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFF000000));
    });

    testWidgets('uses the shared default ambient background before Settings', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(IdentityChoiceScreen(onNewHere: () {}, onLoadMyKey: () {})),
      );

      expect(find.byType(AmbientBackground), findsOneWidget);
    });

    testWidgets('renders the selected cosmic background before Settings', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          IdentityChoiceScreen(
            onNewHere: () {},
            onLoadMyKey: () {},
            backgroundPreference: BackgroundPreference.cosmic,
          ),
        ),
      );

      expect(find.byType(CosmicBackground), findsOneWidget);
    });

    testWidgets('dims choice cards when callbacks are null', (tester) async {
      await tester.pumpWidget(
        wrap(const IdentityChoiceScreen(onNewHere: null, onLoadMyKey: null)),
      );
      await pumpPastAnimations(tester);

      final newHereOpacity = tester.widget<Opacity>(
        find.byKey(const ValueKey("choice-card-opacity-I'm new here")),
      );
      final loadKeyOpacity = tester.widget<Opacity>(
        find.byKey(const ValueKey('choice-card-opacity-Load my key')),
      );

      expect(newHereOpacity.opacity, 0.5);
      expect(loadKeyOpacity.opacity, 0.5);
    });

    testWidgets('disabled choice cards ignore taps', (tester) async {
      await tester.pumpWidget(
        wrap(const IdentityChoiceScreen(onNewHere: null, onLoadMyKey: null)),
      );
      await pumpPastAnimations(tester);

      await tester.tap(find.text("I'm new here"));
      await tester.pump();

      expect(find.byType(BrandHeader), findsOneWidget);
    });

    testWidgets('daylight lagoon keeps identity choice copy readable', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          IdentityChoiceScreen(
            onNewHere: () {},
            onLoadMyKey: () {},
            backgroundPreference: BackgroundPreference.daylightLagoon,
          ),
        ),
      );
      await pumpPastAnimations(tester);

      const colors = BackgroundReadableColors.representativeLight;
      final brand = tester.widget<Text>(find.text('mknoon'));
      expectTextContrast(brand.style!.color!, colors.surfaceBase);

      final title = tester.widget<Text>(find.text("I'm new here"));
      expectTextContrast(title.style!.color!, colors.glassSurface);

      final description = tester.widget<Text>(
        find.text('Generate a fresh identity'),
      );
      expectTextContrast(description.style!.color!, colors.glassSurface);
    });
  });
}
