import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/more_messages_hint.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MoreMessagesHint', () {
    testWidgets('renders "N more messages" for count > 1', (tester) async {
      await tester.pumpWidget(wrap(const MoreMessagesHint(count: 5)));
      expect(find.text('5 more messages'), findsOneWidget);
    });

    testWidgets('renders singular for count 1', (tester) async {
      await tester.pumpWidget(wrap(const MoreMessagesHint(count: 1)));
      expect(find.text('1 more message'), findsOneWidget);
    });

    testWidgets('renders chevron icon', (tester) async {
      await tester.pumpWidget(wrap(const MoreMessagesHint(count: 3)));
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('not rendered when count is 0', (tester) async {
      await tester.pumpWidget(wrap(const MoreMessagesHint(count: 0)));
      expect(find.text('0 more messages'), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    });
  });
}
