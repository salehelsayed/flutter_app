import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_feed_card.dart';

void main() {
  Widget buildTestWidget({
    VoidCallback? onReply,
    VoidCallback? onTap,
    String contactUsername = 'Alice',
    String messageText = 'Hello, this is a test message!',
    String messageTime = '3:30 PM',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MessageFeedCard(
            contactPeerId: '12D3KooWTestPeerId1234567890',
            contactUsername: contactUsername,
            messageText: messageText,
            messageTime: messageTime,
            onReply: onReply,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  group('MessageFeedCard', () {
    testWidgets('renders contact username', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('renders message time', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('3:30 PM'), findsOneWidget);
    });

    testWidgets('renders message text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Hello, this is a test message!'), findsOneWidget);
    });

    testWidgets('renders Reply button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    });

    testWidgets('reply button fires onReply callback', (tester) async {
      var replyPressed = false;
      await tester.pumpWidget(buildTestWidget(
        onReply: () => replyPressed = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reply'));
      expect(replyPressed, true);
    });

    testWidgets('renders RingAvatar with 42px size', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final avatar42 = sizedBoxes.where(
        (sb) => sb.width == 42 && sb.height == 42,
      );
      expect(avatar42, isNotEmpty);
    });

    testWidgets('card tapping fires onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildTestWidget(
        onTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      // Tap the card itself (the message text area)
      await tester.tap(find.text('Hello, this is a test message!'));
      expect(tapped, true);
    });
  });
}
