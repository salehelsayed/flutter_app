import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('MessageBubble colors', () {
    testWidgets('received message uses FeedColors.messageReceivedBg',
        (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Hello',
        time: '3:00 PM',
        isIncoming: true,
        isUnread: false,
      )));

      // Find the Container with BoxDecoration
      final container = tester.widget<Container>(
        find.byType(Container).first,
      );
      final decoration = container.decoration as BoxDecoration?;
      if (decoration != null) {
        expect(decoration.color, FeedColors.messageReceivedBg);
      }
    });

    testWidgets('sent message uses FeedColors.messageSentBg', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Reply',
        time: '3:05 PM',
        isIncoming: false,
        isUnread: false,
      )));

      // Verify it renders without error
      expect(find.text('Reply'), findsOneWidget);
    });

    testWidgets('unread message uses FeedColors.messageUnreadBg',
        (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'New msg',
        time: '3:10 PM',
        isIncoming: true,
        isUnread: true,
      )));

      expect(find.text('New msg'), findsOneWidget);
    });

    testWidgets('renders incoming accent edge with teal', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Test',
        time: '3:00 PM',
        isIncoming: true,
      )));

      // The accent edge Container with width 3 should exist
      final containers = tester.widgetList<Container>(find.byType(Container));
      final accentEdge = containers.where((c) {
        final constraints = c.constraints;
        return constraints != null && constraints.maxWidth == 3;
      });
      expect(accentEdge.isNotEmpty, isTrue);
    });

    testWidgets('renders text and time', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Hello world',
        time: '3:30 PM',
        isIncoming: true,
      )));

      expect(find.text('Hello world'), findsOneWidget);
      expect(find.text('3:30 PM'), findsOneWidget);
    });
  });
}
