import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/startup_loading_gate.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group('StartupLoadingGate', () {
    testWidgets(
      'renders opaque bootstrap surface with centered progress affordance',
      (tester) async {
        await tester.pumpWidget(
          wrap(const StartupLoadingGate(stage: 'checking_identity')),
        );

        expect(
          find.byKey(const ValueKey('startup-loading-gate')),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.lock), findsNothing);

        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(const ValueKey('startup-loading-gate')),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, AppColors.background.withValues(alpha: 0.96));
      },
    );

    testWidgets('shows preparing copy for checking identity stage', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const StartupLoadingGate(stage: 'checking_identity')),
      );

      expect(find.text('Preparing your space...'), findsOneWidget);
      expect(find.text('Checking identity and startup state'), findsOneWidget);
    });

    testWidgets('shows opening feed copy for feed handoff stage', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const StartupLoadingGate(stage: 'opening_feed')),
      );

      expect(find.text('Opening Feed...'), findsOneWidget);
      expect(find.text('Handing off to your conversations'), findsOneWidget);
    });

    testWidgets('shows opening setup copy for first time handoff stage', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const StartupLoadingGate(stage: 'opening_setup')),
      );

      expect(find.text('Opening setup...'), findsOneWidget);
      expect(
        find.text('Getting your first-time experience ready'),
        findsOneWidget,
      );
    });

    testWidgets('shows opening onboarding copy for onboarding handoff stage', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const StartupLoadingGate(stage: 'opening_onboarding')),
      );

      expect(find.text('Opening onboarding...'), findsOneWidget);
      expect(find.text('Let\'s get your identity ready'), findsOneWidget);
    });
  });
}
