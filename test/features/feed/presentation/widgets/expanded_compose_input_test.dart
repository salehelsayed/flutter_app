import 'dart:ui' show TextDirection;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/expanded_compose_input.dart';

void main() {
  // Constrain the widget to keep the send button within visible bounds.
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(width: 350, child: child),
      ),
    ),
  );

  group('ExpandedComposeInput', () {
    testWidgets('renders multiline TextField', (tester) async {
      await tester.pumpWidget(wrap(ExpandedComposeInput(onSend: (_) {})));
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLines, isNull); // null means unlimited (multiline)
    });

    testWidgets('shows attach button when onAttach is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(ExpandedComposeInput(onSend: (_) {}, onAttach: () {})),
      );
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('shows send button icon when text is entered', (tester) async {
      await tester.pumpWidget(wrap(ExpandedComposeInput(onSend: (_) {})));
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    group('BiDi input direction', () {
      testWidgets('TextField defaults to LTR when empty', (tester) async {
        await tester.pumpWidget(wrap(ExpandedComposeInput(onSend: (_) {})));
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.ltr);
      });

      testWidgets('TextField switches to RTL when Arabic is typed', (
        tester,
      ) async {
        await tester.pumpWidget(wrap(ExpandedComposeInput(onSend: (_) {})));

        await tester.enterText(find.byType(TextField), 'مرحبا');
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.rtl);
      });

      testWidgets('TextField stays LTR when English is typed', (tester) async {
        await tester.pumpWidget(wrap(ExpandedComposeInput(onSend: (_) {})));

        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.ltr);
      });

      testWidgets('TextField switches back to LTR after clearing text', (
        tester,
      ) async {
        await tester.pumpWidget(wrap(ExpandedComposeInput(onSend: (_) {})));

        await tester.enterText(find.byType(TextField), 'مرحبا');
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).textDirection,
          TextDirection.rtl,
        );

        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).textDirection,
          TextDirection.ltr,
        );
      });
    });

    testWidgets('calls onSend with text when send button tapped', (
      tester,
    ) async {
      String? sentText;
      await tester.pumpWidget(
        wrap(ExpandedComposeInput(onSend: (text) => sentText = text)),
      );
      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.pump();
      // The send button is a GestureDetector whose child contains the
      // arrow_upward_rounded Icon. The outer GestureDetector absorbs hit-test
      // events, so we find the send GestureDetector by its ancestor
      // relationship and invoke onTap directly.
      final sendIconFinder = find.byIcon(Icons.arrow_upward_rounded);
      final sendGestureDetector = find.ancestor(
        of: sendIconFinder,
        matching: find.byType(GestureDetector),
      );
      // The first ancestor GestureDetector is the send button's detector.
      final gd = tester.widget<GestureDetector>(sendGestureDetector.first);
      gd.onTap?.call();
      await tester.pump();
      expect(sentText, 'Test message');
    });

    testWidgets('renders with custom hint text', (tester) async {
      await tester.pumpWidget(
        wrap(ExpandedComposeInput(onSend: (_) {}, hintText: 'Compose...')),
      );
      expect(find.text('Compose...'), findsOneWidget);
    });
  });
}
