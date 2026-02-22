import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  ThreadFeedItem _thread({
    List<ThreadMessage>? messages,
    int unreadCount = 2,
  }) {
    final msgs = messages ??
        [
          ThreadMessage(
            id: 'm1',
            text: 'Read msg',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'm2',
            text: 'Unread 1',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isUnread: true,
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'm3',
            text: 'Unread 2',
            time: '3:05 PM',
            timestamp: DateTime(2026, 2, 9, 15, 5),
            isUnread: true,
            isIncoming: true,
          ),
        ];
    return ThreadFeedItem(
      id: 'thread_1',
      timestamp: DateTime(2026, 2, 9, 15, 5),
      contactPeerId: 'peer1',
      contactUsername: 'Alice',
      messages: msgs,
      unreadCount: unreadCount,
      conversationState: ConversationState.unread,
    );
  }

  group('OpenModeCardBody', () {
    testWidgets('renders ScrollableMessagePreview with unread messages',
        (tester) async {
      await tester.pumpWidget(wrap(OpenModeCardBody(thread: _thread())));
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
      expect(find.text('Unread 1'), findsOneWidget);
      expect(find.text('Unread 2'), findsOneWidget);
    });

    testWidgets('shows ViewEarlierLink when hasEarlierHistory',
        (tester) async {
      await tester.pumpWidget(wrap(OpenModeCardBody(thread: _thread())));
      // Thread has a read message before unread, so hasEarlierHistory = true
      expect(find.text('View earlier messages'), findsOneWidget);
    });

    testWidgets('renders InlineReplyInput with Reply... hint', (tester) async {
      await tester.pumpWidget(wrap(OpenModeCardBody(thread: _thread())));
      expect(find.text('Reply...'), findsOneWidget);
    });

    testWidgets('renders friend indicator with name and time', (tester) async {
      await tester.pumpWidget(wrap(OpenModeCardBody(thread: _thread())));
      expect(find.text('Alice'), findsAtLeast(1));
    });

    testWidgets('shows UnreadCountBadge when count > 0', (tester) async {
      await tester.pumpWidget(wrap(OpenModeCardBody(
        thread: _thread(unreadCount: 3),
      )));
      expect(find.text('3'), findsOneWidget);
    });
  });
}
