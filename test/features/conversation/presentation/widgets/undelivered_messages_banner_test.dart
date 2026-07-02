import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/undelivered_messages_banner.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

// 172 TC-08 (INV-2): the "couldn't display N messages" affordance — a
// kept-but-undisplayed staged entry (quarantined / recoverable-class rejected)
// must be user-visibly surfaced, never silently invisible.
void main() {
  testWidgets(
    '172 TC-08: shows "couldn\'t display N messages" when quarantined/'
    'recoverable-exhausted entries exist',
    (tester) async {
      await tester.pumpWidget(
        _host(UndeliveredMessagesBanner(count: 3, onRetry: () {})),
      );

      expect(find.byKey(UndeliveredMessagesBanner.bannerKey), findsOneWidget);
      expect(find.text("Couldn't display 3 messages"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets('singular count renders singular copy', (tester) async {
    await tester.pumpWidget(_host(const UndeliveredMessagesBanner(count: 1)));

    expect(find.text("Couldn't display 1 message"), findsOneWidget);
    // No retry affordance without a handler.
    expect(find.byKey(UndeliveredMessagesBanner.retryKey), findsNothing);
  });

  testWidgets('renders nothing when the count is zero', (tester) async {
    await tester.pumpWidget(
      _host(UndeliveredMessagesBanner(count: 0, onRetry: () {})),
    );

    expect(find.byKey(UndeliveredMessagesBanner.bannerKey), findsNothing);
    expect(find.textContaining("Couldn't display"), findsNothing);
  });

  testWidgets('tapping retry fires the callback (re-drives the drain)', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(UndeliveredMessagesBanner(count: 2, onRetry: () => retries++)),
    );

    await tester.tap(find.byKey(UndeliveredMessagesBanner.retryKey));
    await tester.pump();

    expect(retries, 1);
  });
}
