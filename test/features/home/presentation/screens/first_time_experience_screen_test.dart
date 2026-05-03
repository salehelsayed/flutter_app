import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_screen.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  testWidgets('uses the shared default ambient background before Settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FirstTimeExperienceScreen(
          username: 'Alice',
          peerId: '12D3KooWTestPeer',
        ),
      ),
    );

    expect(find.byType(AmbientBackground), findsOneWidget);
  });

  testWidgets('renders the selected cosmic background before Settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FirstTimeExperienceScreen(
          username: 'Alice',
          peerId: '12D3KooWTestPeer',
          backgroundPreference: BackgroundPreference.cosmic,
        ),
      ),
    );

    expect(find.byType(CosmicBackground), findsOneWidget);
  });

  testWidgets('daylight lagoon keeps first-time experience copy readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FirstTimeExperienceScreen(
          username: 'Alice',
          peerId: '12D3KooWTestPeer',
          backgroundPreference: BackgroundPreference.daylightLagoon,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byType(DaylightLagoonBackground), findsOneWidget);

    const colors = BackgroundReadableColors.representativeLight;
    final username = tester.widget<Text>(find.text('@Alice'));
    final qrDescription = tester.widget<Text>(
      find.text('Show this to someone you want in your circle...'),
    );
    final scanTitle = tester.widget<Text>(find.text("Scan a friend's code"));
    final emptyTitle = tester.widget<Text>(
      find.text('Your circle is waiting to be filled'),
    );

    expect(username.style!.color, colors.textPrimary);
    expect(qrDescription.style!.color, colors.textSecondary);
    expect(scanTitle.style!.color, colors.textPrimary);
    expect(emptyTitle.style!.color, colors.textPrimary);
    expectTextContrast(username.style!.color!, colors.surfaceBase);
    expectTextContrast(qrDescription.style!.color!, colors.surfaceBase);
    expectTextContrast(scanTitle.style!.color!, colors.glassSurface);
    expectTextContrast(emptyTitle.style!.color!, colors.surfaceBase);
  });
}
