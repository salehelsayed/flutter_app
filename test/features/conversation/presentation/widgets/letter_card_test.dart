import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';

void main() {
  Widget buildTestWidget({
    bool isIncoming = true,
    String? status,
    String senderName = 'Alice',
    String text = 'Hello, this is a test message.',
    String time = '3:30 PM',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LetterCard(
            senderPeerId: '12D3KooWTestPeerId1234567890',
            senderName: senderName,
            text: text,
            time: time,
            isIncoming: isIncoming,
            status: status,
          ),
        ),
      ),
    );
  }

  group('LetterCard', () {
    group('received (incoming) card', () {
      testWidgets('shows sender name', (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));
        expect(find.text('Alice'), findsOneWidget);
      });

      testWidgets('shows message text', (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));
        expect(find.text('Hello, this is a test message.'), findsOneWidget);
      });

      testWidgets('shows time', (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));
        expect(find.text('3:30 PM'), findsOneWidget);
      });

      testWidgets('does not show delivery note', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: true, status: null),
        );
        expect(find.byIcon(Icons.done_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      });
    });

    group('sent (outgoing) card', () {
      testWidgets('shows sender name (You)', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, senderName: 'You', status: 'sent'),
        );
        expect(find.text('You'), findsOneWidget);
      });

      testWidgets('shows message body', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'sent'),
        );
        expect(find.text('Hello, this is a test message.'), findsOneWidget);
      });

      testWidgets('shows one tick when status is sending', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'sending'),
        );
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      });

      testWidgets('shows one tick when status is sent', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'sent'),
        );
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      });

      testWidgets('shows two ticks when status is delivered', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'delivered'),
        );
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      });

      testWidgets('shows failed icon when status is failed', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'failed'),
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      });

      testWidgets('no delivery note when status is null', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: null),
        );
        expect(find.byIcon(Icons.done_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      });
    });

    testWidgets('renders RingAvatar with 32px size', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final avatar32 = sizedBoxes.where(
        (sb) => sb.width == 32 && sb.height == 32,
      );
      expect(avatar32, isNotEmpty);
    });
  });
}
