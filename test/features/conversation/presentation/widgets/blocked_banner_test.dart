import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/blocked_banner.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('GERMAN-OVERFLOW blocked banner scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var unblocked = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: BlockedBanner(onUnblock: () => unblocked = true),
          ),
        ),
      );
      await tester.pump();
      final label = find.text('Du hast diesen Kontakt blockiert.');
      expect(label, findsOneWidget);
      expect(tester.takeException(), isNull);
      final labelBounds = tester.getRect(label);
      final bannerBounds = tester.getRect(find.byType(BlockedBanner));
      expect(labelBounds.width, greaterThan(0));
      expect(labelBounds.left, greaterThanOrEqualTo(bannerBounds.left));
      expect(labelBounds.right, lessThanOrEqualTo(bannerBounds.right));
      final paragraph = tester.renderObject<RenderParagraph>(label);
      if (paragraph.didExceedMaxLines) {
        expect(paragraph.overflow, TextOverflow.ellipsis);
      }
      await tester.tap(find.text('Entsperren'));
      expect(unblocked, isTrue);
    });
  }

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
