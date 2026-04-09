import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/presentation/screens/sent_confirmation_wired.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'passes the sent result set through and forwards the back callback',
    (tester) async {
      var backCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SentConfirmationWired(
            introductionCount: 2,
            introducedUsernames: const ['Alice', 'Bob'],
            onBackToConversation: () => backCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 introductions sent'), findsOneWidget);
      expect(find.text('Alice, Bob'), findsOneWidget);

      await tester.tap(find.text('Back to conversation'));
      await tester.pump();

      expect(backCalled, isTrue);
    },
  );
}
