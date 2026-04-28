import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_screen.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
