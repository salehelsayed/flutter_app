import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('CollapsedModeCardBody', () {
    testWidgets('replied state shows reply indicator', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hey',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'm2',
            text: 'My reply',
            time: '2:05 PM',
            timestamp: DateTime(2026, 2, 9, 14, 5),
            isIncoming: false,
          ),
        ],
        conversationState: ConversationState.replied,
        lastRepliedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: thread)));
      expect(find.textContaining('You replied'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('read state shows last received message, no check',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hello there',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: thread)));
      expect(find.textContaining('You replied'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('session reply shows reply text with Just now',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hello',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.unread,
      );

      final reply = SessionReply(text: 'My quick reply', time: DateTime.now());

      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        sessionReply: reply,
      )));

      // Session reply text should be in the preview
      expect(find.text('My quick reply'), findsOneWidget);
      // Check icon should show (replied via session)
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('InlineReplyInput has Continue... hint', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hi',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: thread)));
      expect(find.text('Continue...'), findsOneWidget);
    });

    testWidgets('fires onTapExpand on tap', (tester) async {
      var tapped = false;
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hi',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        onTapExpand: () => tapped = true,
      )));

      // Tap on the name (part of the GestureDetector area)
      await tester.tap(find.text('Alice'));
      expect(tapped, isTrue);
    });
  });
}
