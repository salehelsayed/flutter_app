import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/presentation/screens/sent_confirmation_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject({
    required int introductionCount,
    required List<String> introducedUsernames,
    VoidCallback? onBackToConversation,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SentConfirmationScreen(
          introductionCount: introductionCount,
          introducedUsernames: introducedUsernames,
          onBackToConversation: onBackToConversation ?? () {},
        ),
      ),
    );
  }

  testWidgets('correct count displayed in title', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        introductionCount: 3,
        introducedUsernames: ['Alice', 'Bob', 'Charlie'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 introductions sent'), findsOneWidget);
  });

  testWidgets('singular form for count of 1', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        introductionCount: 1,
        introducedUsernames: ['Alice'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 introduction sent'), findsOneWidget);
  });

  testWidgets('avatar row renders friend names with overflow',
      (tester) async {
    await tester.pumpWidget(
      buildSubject(
        introductionCount: 5,
        introducedUsernames: ['Alice', 'Bob', 'Charlie', 'Dave', 'Eve'],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Alice, Bob, Charlie and 2 more'),
      findsOneWidget,
    );
  });

  testWidgets('"Back to conversation" button triggers callback',
      (tester) async {
    var callbackCalled = false;
    await tester.pumpWidget(
      buildSubject(
        introductionCount: 1,
        introducedUsernames: ['Alice'],
        onBackToConversation: () => callbackCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to conversation'));
    await tester.pump();

    expect(callbackCalled, isTrue);
  });
}
