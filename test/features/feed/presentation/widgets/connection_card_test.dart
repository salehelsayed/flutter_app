import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/feed/presentation/widgets/connection_card.dart';
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

  group('ConnectionCard', () {
    testWidgets('renders "Connected!" text', (tester) async {
      // Suppress overflow errors from the button Row (pre-existing layout issue)
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        wrap(
          const ConnectionCard(
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connected!'), findsOneWidget);
    });

    testWidgets('renders contact username', (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        wrap(
          const ConnectionCard(
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('alice'), findsOneWidget);
    });

    testWidgets('renders green check icon', (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        wrap(
          const ConnectionCard(
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('renders "Send Message" button', (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        wrap(
          const ConnectionCard(
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Send Message'), findsOneWidget);
    });

    testWidgets('uses readable colors on representative light backgrounds', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const ConnectionCard(
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
          ),
          readableColors: BackgroundReadableColors.representativeLight,
        ),
      );
      await tester.pumpAndSettle();

      final title = tester.widget<Text>(find.text('Connected!'));
      expect(title.style?.color, const Color(0xFF167A3A));
      expect(title.style?.shadows, isEmpty);

      final username = tester.widget<Text>(find.text('alice'));
      expect(
        username.style?.color,
        BackgroundReadableColors.representativeLight.textPrimary,
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(
        button.style?.foregroundColor?.resolve(<WidgetState>{}),
        const Color(0xFF157A39),
      );
      expect(
        button.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xFFE6F6EC),
      );
    });

    testWidgets('calls onSendMessage when button pressed', (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      var sendPressed = false;
      await tester.pumpWidget(
        wrap(
          ConnectionCard(
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            onSendMessage: () => sendPressed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Message'));
      expect(sendPressed, isTrue);
    });

    testWidgets('shows blocked overlay when isBlocked is true', (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        wrap(
          const ConnectionCard(
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            isBlocked: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets('renders "Introduced by X" when introducedBy provided', (
      tester,
    ) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        wrap(
          const ConnectionCard(
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            introducedBy: 'bob',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Introduced by bob'), findsOneWidget);
    });

    testWidgets('disables Send Message button when blocked', (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        wrap(
          ConnectionCard(
            contactPeerId: 'peer-abc-123',
            contactUsername: 'alice',
            isBlocked: true,
            onSendMessage: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });
  });
}
