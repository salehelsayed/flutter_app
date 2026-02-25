import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';

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
    testWidgets('collapsed card shows "Tap to expand" hint', (tester) async {
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
        isExpanded: false,
      )));
      expect(find.text('Tap to expand'), findsOneWidget);
    });

    testWidgets('expanded card hides "Tap to expand" hint', (tester) async {
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
        isExpanded: true,
      )));
      expect(find.text('Tap to expand'), findsNothing);
    });

    testWidgets('session reply still shows "Tap to expand" hint', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
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

      final reply = SessionReply(text: 'Quick reply', time: DateTime.now());

      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        sessionReply: reply,
        isExpanded: false,
      )));
      expect(find.text('Tap to expand'), findsOneWidget);
    });
  });

  group('CollapsedModeCardBody expanded state', () {
    ThreadFeedItem _readThread({int messageCount = 3}) {
      return ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: List.generate(
          messageCount,
          (i) => ThreadMessage(
            id: 'm${i + 1}',
            text: 'Message ${i + 1}',
            time: '3:0$i PM',
            timestamp: DateTime(2026, 2, 9, 15, i),
            isIncoming: true,
          ),
        ),
        conversationState: ConversationState.read,
      );
    }

    testWidgets('isExpanded false does not show ScrollableMessagePreview',
        (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: false,
      )));
      expect(find.byType(ScrollableMessagePreview), findsNothing);
    });

    testWidgets('isExpanded true shows ScrollableMessagePreview',
        (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
      )));
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    });

    testWidgets('header still shows username when expanded', (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
      )));
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('InlineReplyInput still present when expanded',
        (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
      )));
      expect(find.text('Continue...'), findsOneWidget);
    });

    testWidgets('single-line preview hidden when expanded', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Preview line text',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      // Not expanded: preview text visible as "Alice: Preview line text"
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        isExpanded: false,
      )));
      // The preview shows "Alice: " label and "Preview line text"
      expect(find.text('Preview line text'), findsOneWidget);

      // Expanded: preview text replaced by ScrollableMessagePreview
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        isExpanded: true,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    });

    testWidgets('tap header fires onTapExpand in expanded state',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
        onTapExpand: () => tapped = true,
      )));

      await tester.tap(find.text('Alice'));
      expect(tapped, isTrue);
    });

    testWidgets('Collapse link present in expanded state', (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
        onCollapse: () {},
      )));
      expect(find.text('Collapse'), findsOneWidget);
    });

    testWidgets('session reply with isExpanded does not show ScrollableMessagePreview',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hi',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.unread,
      );

      final reply = SessionReply.justNow('My reply');
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        sessionReply: reply,
        isExpanded: true,
      )));
      // Session reply overrides expanded — shows single-line preview, not ScrollableMessagePreview
      expect(find.byType(ScrollableMessagePreview), findsNothing);
      expect(find.text('My reply'), findsOneWidget);
    });
  });
}
