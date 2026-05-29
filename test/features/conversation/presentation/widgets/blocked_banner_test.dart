import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/blocked_banner.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  group('BlockedBanner', () {
    testWidgets('renders blocked text and unblock button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: BlockedBanner()),
        ),
      );

      expect(find.text('You blocked this contact.'), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets('Unblock button fires callback', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: BlockedBanner(onUnblock: () => tapped = true)),
        ),
      );

      await tester.tap(find.text('Unblock'));
      expect(tapped, isTrue);
    });
  });
}
