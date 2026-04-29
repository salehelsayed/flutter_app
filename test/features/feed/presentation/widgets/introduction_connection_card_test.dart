import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/feed/presentation/widgets/introduction_connection_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(
    Widget child, {
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
  }) => MaterialApp(
    locale: const Locale('en'),
    theme: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(child: SizedBox(width: 400, child: child)),
      ),
    ),
  );

  // Suppress overflow errors from button Row (same as connection_card_test)
  void suppressOverflow() {
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);
  }

  group('IntroductionConnectionCard', () {
    testWidgets('renders both usernames', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(
        wrap(
          const IntroductionConnectionCard(
            ownPeerId: 'own-peer-123',
            ownUsername: 'me',
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            introducedBy: 'bob',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('me'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
    });

    testWidgets('renders "Introduced by X" text', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(
        wrap(
          const IntroductionConnectionCard(
            ownPeerId: 'own-peer-123',
            ownUsername: 'me',
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            introducedBy: 'bob',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Introduced by bob'), findsOneWidget);
    });

    testWidgets('renders "Send Message" button', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(
        wrap(
          const IntroductionConnectionCard(
            ownPeerId: 'own-peer-123',
            ownUsername: 'me',
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            introducedBy: 'bob',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Send Message'), findsOneWidget);
    });

    testWidgets('uses readable colors on representative light backgrounds', (
      tester,
    ) async {
      suppressOverflow();
      await tester.pumpWidget(
        wrap(
          const IntroductionConnectionCard(
            ownPeerId: 'own-peer-123',
            ownUsername: 'me',
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            introducedBy: 'bob',
          ),
          readableColors: BackgroundReadableColors.representativeLight,
        ),
      );
      await tester.pumpAndSettle();

      final ownName = tester.widget<Text>(find.text('me'));
      final contactName = tester.widget<Text>(find.text('alice'));
      expect(
        ownName.style?.color,
        BackgroundReadableColors.representativeLight.textPrimary,
      );
      expect(
        contactName.style?.color,
        BackgroundReadableColors.representativeLight.textPrimary,
      );

      final introducedBy = tester.widget<Text>(find.text('Introduced by bob'));
      expect(
        introducedBy.style?.color,
        BackgroundReadableColors.representativeLight.textSecondary,
      );
    });

    testWidgets('calls onSendMessage on button tap', (tester) async {
      suppressOverflow();
      var sendPressed = false;
      await tester.pumpWidget(
        wrap(
          IntroductionConnectionCard(
            ownPeerId: 'own-peer-123',
            ownUsername: 'me',
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            introducedBy: 'bob',
            onSendMessage: () => sendPressed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Message'));
      expect(sendPressed, isTrue);
    });

    testWidgets('shows blocked overlay when isBlocked is true', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(
        wrap(
          const IntroductionConnectionCard(
            ownPeerId: 'own-peer-123',
            ownUsername: 'me',
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            introducedBy: 'bob',
            isBlocked: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets('disables Send Message button when blocked', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(
        wrap(
          IntroductionConnectionCard(
            ownPeerId: 'own-peer-123',
            ownUsername: 'me',
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            introducedBy: 'bob',
            isBlocked: true,
            onSendMessage: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('does not render Connected text or green check icon', (
      tester,
    ) async {
      suppressOverflow();
      await tester.pumpWidget(
        wrap(
          const IntroductionConnectionCard(
            ownPeerId: 'own-peer-123',
            ownUsername: 'me',
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            introducedBy: 'bob',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connected!'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });
  });
}
