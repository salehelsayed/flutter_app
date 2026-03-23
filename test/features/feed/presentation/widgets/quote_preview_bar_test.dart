import 'dart:ui' show TextDirection;

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

    testWidgets('Arabic quoted text drives RTL', (tester) async {
      await tester.pumpWidget(
        wrap(const QuotePreviewBar(text: 'مرحبا بالعالم')),
      );

      final textWidget = tester.widget<Text>(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'مرحبا بالعالم',
        ),
      );
      expect(textWidget.textDirection, TextDirection.rtl);
    });

    testWidgets('Arabic-first mixed quoted text drives RTL', (tester) async {
      await tester.pumpWidget(
        wrap(const QuotePreviewBar(text: 'مرحبا Hello كيف')),
      );

      final textWidget = tester.widget<Text>(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'مرحبا Hello كيف',
        ),
      );
      expect(textWidget.textDirection, TextDirection.rtl);
    });

    testWidgets('English quoted text drives LTR', (tester) async {
      await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'Hello world')));

      final textWidget = tester.widget<Text>(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Hello world',
        ),
      );
      expect(textWidget.textDirection, TextDirection.ltr);
    });

    testWidgets('text has maxLines 2 with ellipsis overflow', (tester) async {
      await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'Some text')));
      final textWidget = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.data == 'Some text')
          .first;
      expect(textWidget.maxLines, 2);
      expect(textWidget.overflow, TextOverflow.ellipsis);
    });

    testWidgets('shows dismiss icon when onDismiss is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(QuotePreviewBar(text: 'Hello', onDismiss: () {})),
      );
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('hides dismiss icon when onDismiss is null', (tester) async {
      await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'Hello')));
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });
  });
}
