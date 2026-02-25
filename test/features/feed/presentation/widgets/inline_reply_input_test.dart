import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('InlineReplyInput', () {
    testWidgets('renders TextField with hint text', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Reply...'), findsOneWidget);
    });

    testWidgets('shows attach button when onAttach is provided', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(
        onSend: (_) {},
        onAttach: () {},
      )));
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('hides attach button when onAttach is null', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));
      expect(find.byIcon(Icons.add_rounded), findsNothing);
    });

    testWidgets('shows send button when text is entered', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('calls onSend with text when send button tapped', (tester) async {
      String? sentText;
      await tester.pumpWidget(wrap(InlineReplyInput(
        onSend: (text) => sentText = text,
      )));
      await tester.enterText(find.byType(TextField), 'Hello world');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      expect(sentText, 'Hello world');
    });

    testWidgets('renders with custom hint text', (tester) async {
      await tester.pumpWidget(wrap(InlineReplyInput(
        onSend: (_) {},
        hintText: 'Type here...',
      )));
      expect(find.text('Type here...'), findsOneWidget);
    });
  });
}
