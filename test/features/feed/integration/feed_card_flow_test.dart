import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';
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

  group('Feed card flow integration', () {
    testWidgets(
      'unread card renders open mode with scrollable unread messages and Reply... input',
      (tester) async {
        final thread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [
            _msg('m1'), // read
            _msg('m2', isUnread: true),
            _msg('m3', isUnread: true),
          ],
          unreadCount: 2,
          conversationState: ConversationState.unread,
        );

        await tester.pumpWidget(wrap(FeedCard(thread: thread)));
        expect(find.byType(OpenModeCardBody), findsOneWidget);
        expect(find.byType(ScrollableMessagePreview), findsOneWidget);
        expect(find.text('Reply...'), findsOneWidget);
      },
    );

    testWidgets(
      'replied card shows last sent message and "You replied" indicator',
      (tester) async {
        final thread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [
            _msg('m1', isIncoming: true),
            _msg('m2', isIncoming: false),
          ],
          conversationState: ConversationState.replied,
          lastRepliedAt: DateTime.now().subtract(const Duration(hours: 2)),
        );

        await tester.pumpWidget(wrap(FeedCard(thread: thread)));
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.textContaining('You replied'), findsOneWidget);
      },
    );

    testWidgets(
      'session reply collapses card with replied indicator',
      (tester) async {
        final thread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [
            _msg('m1', isUnread: true),
          ],
          conversationState: ConversationState.unread,
        );

        final reply = SessionReply.justNow('Quick reply');

        await tester.pumpWidget(wrap(FeedCard(
          thread: thread,
          sessionReply: reply,
        )));

        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.text('Quick reply'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'tapping collapsed card fires onToggleExpand (not onViewFullConversation)',
      (tester) async {
        var toggled = false;
        var navigated = false;
        final thread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [_msg('m1')],
          conversationState: ConversationState.read,
        );

        await tester.pumpWidget(wrap(FeedCard(
          thread: thread,
          onToggleExpand: () => toggled = true,
          onViewFullConversation: () => navigated = true,
        )));

        // Tap on the name area of the collapsed card
        await tester.tap(find.text('Alice'));
        expect(toggled, isTrue);
        expect(navigated, isFalse);
      },
    );

    testWidgets(
      'multiple contacts render separate feed cards with correct modes',
      (tester) async {
        final unreadThread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [_msg('m1', isUnread: true)],
          conversationState: ConversationState.unread,
        );
        final readThread = ThreadFeedItem(
          id: 'thread_2',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer2',
          contactUsername: 'Bob',
          messages: [_msg('m2')],
          conversationState: ConversationState.read,
        );

        await tester.pumpWidget(wrap(Column(
          children: [
            FeedCard(thread: unreadThread),
            FeedCard(thread: readThread),
          ],
        )));

        expect(find.byType(OpenModeCardBody), findsOneWidget);
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      },
    );

    testWidgets(
      'blocked contact shows blocked overlay',
      (tester) async {
        final thread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [_msg('m1')],
          conversationState: ConversationState.read,
          isBlocked: true,
        );

        await tester.pumpWidget(wrap(FeedCard(thread: thread)));
        expect(find.text('Blocked'), findsOneWidget);
        expect(find.byIcon(Icons.block), findsOneWidget);
      },
    );

    testWidgets(
      'ScrollablePreview shows gradient fade and hint for >3 unread',
      (tester) async {
        final thread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [
            _msg('m1', isUnread: true),
            _msg('m2', isUnread: true),
            _msg('m3', isUnread: true),
            _msg('m4', isUnread: true),
            _msg('m5', isUnread: true),
          ],
          unreadCount: 5,
          conversationState: ConversationState.unread,
        );

        await tester.pumpWidget(wrap(FeedCard(thread: thread)));
        expect(find.byType(ShaderMask), findsOneWidget);
        expect(find.text('2 more messages'), findsOneWidget);
      },
    );

    testWidgets(
      'session reply cleared on incoming allows open mode to show',
      (tester) async {
        // Thread is active (unread) with a session reply → collapsed
        final thread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [
            _msg('m1', isUnread: true),
          ],
          conversationState: ConversationState.active,
        );

        final reply = SessionReply.justNow('My reply');

        // With session reply → CollapsedModeCardBody
        await tester.pumpWidget(wrap(FeedCard(
          thread: thread,
          sessionReply: reply,
        )));
        expect(find.byType(CollapsedModeCardBody), findsOneWidget);
        expect(find.byType(OpenModeCardBody), findsNothing);

        // Session reply cleared → OpenModeCardBody
        await tester.pumpWidget(wrap(FeedCard(
          thread: thread,
          sessionReply: null,
        )));
        await tester.pumpAndSettle();
        expect(find.byType(OpenModeCardBody), findsOneWidget);
      },
    );

    testWidgets(
      'tap to expand works after session reply is cleared',
      (tester) async {
        final thread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [_msg('m1'), _msg('m2'), _msg('m3')],
          conversationState: ConversationState.read,
        );

        final reply = SessionReply.justNow('My reply');

        // With session reply + isExpanded → NO ScrollableMessagePreview
        await tester.pumpWidget(wrap(FeedCard(
          thread: thread,
          sessionReply: reply,
          isExpanded: true,
        )));
        await tester.pumpAndSettle();
        expect(find.byType(ScrollableMessagePreview), findsNothing);

        // Session reply cleared + isExpanded → ScrollableMessagePreview present
        await tester.pumpWidget(wrap(FeedCard(
          thread: thread,
          sessionReply: null,
          isExpanded: true,
        )));
        await tester.pumpAndSettle();
        expect(find.byType(ScrollableMessagePreview), findsOneWidget);
      },
    );

    testWidgets(
      'View earlier messages link fires onViewFullConversation',
      (tester) async {
        var navigated = false;
        final thread = ThreadFeedItem(
          id: 'thread_1',
          timestamp: DateTime(2026, 2, 9),
          contactPeerId: 'peer1',
          contactUsername: 'Alice',
          messages: [
            _msg('m1'), // read (creates earlier history)
            _msg('m2', isUnread: true),
          ],
          unreadCount: 1,
          conversationState: ConversationState.unread,
        );

        await tester.pumpWidget(wrap(FeedCard(
          thread: thread,
          onViewFullConversation: () => navigated = true,
        )));

        expect(find.text('View earlier messages'), findsOneWidget);
        await tester.tap(find.text('View earlier messages'));
        expect(navigated, isTrue);
      },
    );
  });
}
