import 'dart:ui' show TextDirection;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/expanded_compose_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapApp(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Widget wrapScrollable(Widget child) =>
      wrapApp(SingleChildScrollView(child: child));

  testWidgets(
    'BiDi display widgets honor first-strong direction and safe markers survive sanitization',
    (tester) async {
      const rtlMixed = 'مرحبا Hello كيف الحال';
      const ltrMixed = 'Hello مرحبا from smoke';
      const rawWithMarkers = 'Hello\u202E\u200E مرحبا\u200F\u061C\u200D';
      const sanitizedWithMarkers = 'Hello\u200E مرحبا\u200F\u061C\u200D';

      expect(sanitizeMessageText(rawWithMarkers), sanitizedWithMarkers);

      await tester.pumpWidget(wrapApp(const QuotePreviewBar(text: rtlMixed)));
      await tester.pumpAndSettle();

      final quoteText = tester.widget<Text>(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == rtlMixed,
        ),
      );
      expect(quoteText.textDirection, TextDirection.rtl);

      await tester.pumpWidget(
        wrapScrollable(
          const MessageBubble(
            text: rtlMixed,
            time: '3:00 PM',
            isIncoming: false,
            senderLabel: 'You',
            quotedText: ltrMixed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bubbleRichText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(LinkableText),
          matching: find.byType(RichText),
        ),
      );
      expect(bubbleRichText.textDirection, TextDirection.rtl);

      final bubbleQuoteText = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(Text),
            ),
          )
          .firstWhere((textWidget) => textWidget.data == ltrMixed);
      expect(bubbleQuoteText.textDirection, TextDirection.ltr);

      await tester.pumpWidget(
        wrapScrollable(
          const LetterCard(
            senderPeerId: '12D3KooWSmokePeer',
            senderName: 'Smoke Peer',
            text: rtlMixed,
            time: '3:01 PM',
            isIncoming: true,
            quotedText: ltrMixed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cardRichText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(LinkableText),
          matching: find.byType(RichText),
        ),
      );
      expect(cardRichText.textDirection, TextDirection.rtl);

      final cardQuoteText = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(LetterCard),
              matching: find.byType(Text),
            ),
          )
          .firstWhere((textWidget) => textWidget.data == ltrMixed);
      expect(cardQuoteText.textDirection, TextDirection.ltr);
    },
  );

  testWidgets('BiDi compose inputs switch direction live while typing', (
    tester,
  ) async {
    const rtlMixed = 'مرحبا Hello';
    const ltrMixed = 'Hello مرحبا';

    await tester.pumpWidget(
      wrapApp(
        Align(
          alignment: Alignment.bottomCenter,
          child: ComposeArea(onSend: (_) {}, quotedText: 'مرحبا Hello'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Replying to'), findsOneWidget);

    await tester.enterText(find.byType(TextField), rtlMixed);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );

    await tester.enterText(find.byType(TextField), ltrMixed);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );

    await tester.pumpWidget(wrapApp(InlineReplyInput(onSend: (_) {})));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), rtlMixed);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );

    await tester.enterText(find.byType(TextField), ltrMixed);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );

    await tester.pumpWidget(
      wrapApp(
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 350,
            child: ExpandedComposeInput(onSend: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), rtlMixed);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );

    await tester.enterText(find.byType(TextField), ltrMixed);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );
  });
}
