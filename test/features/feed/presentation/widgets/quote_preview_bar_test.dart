import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('QuotePreviewBar', () {
    testWidgets('renders "Replying to" label', (tester) async {
      await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'Hello')));
      expect(find.text('Replying to'), findsOneWidget);
    });

    testWidgets('renders quoted text', (tester) async {
      await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'Hello world')));
      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('text has maxLines 2 with ellipsis overflow', (tester) async {
      await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'Some text')));
      final textWidget = tester.widgetList<Text>(find.byType(Text)).where(
        (t) => t.data == 'Some text',
      ).first;
      expect(textWidget.maxLines, 2);
      expect(textWidget.overflow, TextOverflow.ellipsis);
    });

    testWidgets('shows dismiss icon when onDismiss is provided', (tester) async {
      await tester.pumpWidget(wrap(QuotePreviewBar(
        text: 'Hello',
        onDismiss: () {},
      )));
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('hides dismiss icon when onDismiss is null', (tester) async {
      await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'Hello')));
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });
  });
}
