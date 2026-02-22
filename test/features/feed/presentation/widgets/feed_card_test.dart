import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  ThreadMessage _msg(String id, {bool isUnread = false, bool isIncoming = true}) =>
      ThreadMessage(
        id: id,
        text: 'Message $id',
        time: '3:00 PM',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        isUnread: isUnread,
        isIncoming: isIncoming,
      );

  group('FeedCard', () {
    testWidgets('unread state renders OpenModeCardBody', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg('m1', isUnread: true),
          _msg('m2', isUnread: true),
        ],
        unreadCount: 2,
        conversationState: ConversationState.unread,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: thread)));
      expect(find.byType(OpenModeCardBody), findsOneWidget);
      expect(find.byType(CollapsedModeCardBody), findsNothing);
    });

    testWidgets('active state renders OpenModeCardBody', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg('m1', isUnread: true),
          _msg('m2', isIncoming: false),
        ],
        conversationState: ConversationState.active,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: thread)));
      expect(find.byType(OpenModeCardBody), findsOneWidget);
    });

    testWidgets('read state renders CollapsedModeCardBody', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg('m1')],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: thread)));
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      expect(find.byType(OpenModeCardBody), findsNothing);
    });

    testWidgets('replied state renders CollapsedModeCardBody', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg('m1'),
          _msg('m2', isIncoming: false),
        ],
        conversationState: ConversationState.replied,
        lastRepliedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(FeedCard(thread: thread)));
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
    });

    testWidgets('session reply forces CollapsedModeCardBody', (tester) async {
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

      final sessionReply = SessionReply.justNow('Quick reply');

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        sessionReply: sessionReply,
      )));
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      expect(find.byType(OpenModeCardBody), findsNothing);
    });

    testWidgets('blocked overlay rendered when isBlocked', (tester) async {
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
    });

    testWidgets('no stacked layers (flat card)', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg('m1'),
          _msg('m2'),
          _msg('m3'),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: thread)));
      // Only one ClipRRect for the main card — no extra stack layers
      final clips = tester.widgetList<ClipRRect>(find.byType(ClipRRect));
      // Should be exactly 1 ClipRRect for the card container
      expect(clips.length, 1);
    });

    testWidgets('entry animation starts', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg('m1')],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: thread)));
      // Pump a few frames to advance animation
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      // Card should be fully visible after animation
      expect(find.byType(FeedCard), findsOneWidget);
    });
  });
}
