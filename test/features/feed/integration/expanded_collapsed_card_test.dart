import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  ThreadMessage _msg(
    String id, {
    bool isUnread = false,
    bool isIncoming = true,
    DateTime? timestamp,
  }) =>
      ThreadMessage(
        id: id,
        text: 'Message $id',
        time: '3:00 PM',
        timestamp: timestamp ?? DateTime(2026, 2, 9, 15, 0),
        isUnread: isUnread,
        isIncoming: isIncoming,
      );

  group('Expanded collapsed card integration', () {
    testWidgets('tap to expand read card shows messages', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg('m1'), _msg('m2'), _msg('m3')],
        conversationState: ConversationState.read,
      );

      // Start collapsed
      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: false,
      )));
      expect(find.byType(ScrollableMessagePreview), findsNothing);

      // Expand
      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: true,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    });

    testWidgets('tap again to collapse → back to single line',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg('m1'), _msg('m2'), _msg('m3')],
        conversationState: ConversationState.read,
      );

      // Start expanded
      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: true,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);

      // Collapse
      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: false,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollableMessagePreview), findsNothing);
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
    });

    testWidgets('accordion: expand A then B → A collapses', (tester) async {
      final threadA = ThreadFeedItem(
        id: 'thread_a',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peerA',
        contactUsername: 'Alice',
        messages: [_msg('a1'), _msg('a2')],
        conversationState: ConversationState.read,
      );
      final threadB = ThreadFeedItem(
        id: 'thread_b',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peerB',
        contactUsername: 'Bob',
        messages: [_msg('b1'), _msg('b2')],
        conversationState: ConversationState.read,
      );

      // A expanded, B collapsed
      await tester.pumpWidget(wrap(Column(
        children: [
          FeedCard(thread: threadA, isExpanded: true),
          FeedCard(thread: threadB, isExpanded: false),
        ],
      )));
      await tester.pumpAndSettle();

      final previews = tester.widgetList(find.byType(ScrollableMessagePreview));
      expect(previews.length, 1);

      // Now B expanded, A collapsed
      await tester.pumpWidget(wrap(Column(
        children: [
          FeedCard(thread: threadA, isExpanded: false),
          FeedCard(thread: threadB, isExpanded: true),
        ],
      )));
      await tester.pumpAndSettle();

      final previews2 = tester.widgetList(find.byType(ScrollableMessagePreview));
      expect(previews2.length, 1);
      // Bob's card should have the ScrollableMessagePreview
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('send from expanded → session reply collapses',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg('m1'), _msg('m2')],
        conversationState: ConversationState.read,
      );

      // Start expanded
      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: true,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);

      // Session reply collapses (isExpanded still true, but sessionReply overrides)
      final reply = SessionReply.justNow('My reply');
      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        sessionReply: reply,
        isExpanded: true,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollableMessagePreview), findsNothing);
      expect(find.text('My reply'), findsOneWidget);
    });

    testWidgets('View earlier messages link navigates to full conversation',
        (tester) async {
      var navigated = false;
      // Thread with earlier history (read messages before unread)
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg('m1'),
          _msg('m2'),
          _msg('m3'),
          _msg('m4'),
          _msg('m5'),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: true,
        onViewFullConversation: () => navigated = true,
      )));
      await tester.pumpAndSettle();

      // Has earlier history (5 msgs > maxPreview 3), so "View earlier" should appear
      expect(find.text('View earlier messages'), findsOneWidget);
      await tester.tap(find.text('View earlier messages'));
      expect(navigated, isTrue);
    });
  });
}
