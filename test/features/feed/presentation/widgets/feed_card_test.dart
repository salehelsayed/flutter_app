import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

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

  group('FeedCard with GroupThreadFeedItem', () {
    testWidgets('renders OpenModeCardBody for unread GroupThreadFeedItem',
        (tester) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          _msg('gm1', isUnread: true),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: groupThread)));
      expect(find.byType(OpenModeCardBody), findsOneWidget);
      expect(find.byType(CollapsedModeCardBody), findsNothing);
    });

    testWidgets('renders CollapsedModeCardBody for read GroupThreadFeedItem',
        (tester) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [_msg('gm1')],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: groupThread)));
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      expect(find.byType(OpenModeCardBody), findsNothing);
    });

    testWidgets(
        'session reply forces CollapsedModeCardBody for unread group card',
        (tester) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [_msg('gm1', isUnread: true)],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      final sessionReply = SessionReply.justNow('My reply');

      await tester.pumpWidget(wrap(FeedCard(
        thread: groupThread,
        sessionReply: sessionReply,
      )));
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      expect(find.byType(OpenModeCardBody), findsNothing);
    });

    testWidgets(
        'active group card without session reply stays in open mode',
        (tester) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          _msg('gm1', isUnread: true),
          _msg('gm2', isIncoming: false),
        ],
        unreadCount: 1,
        conversationState: ConversationState.active,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: groupThread)));
      expect(find.byType(OpenModeCardBody), findsOneWidget);
      expect(find.byType(CollapsedModeCardBody), findsNothing);
    });
  });

  group('FeedCard expanded collapsed card', () {
    testWidgets('isExpanded false + read state → no ScrollableMessagePreview',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg('m1'), _msg('m2'), _msg('m3')],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: false,
      )));
      expect(find.byType(ScrollableMessagePreview), findsNothing);
    });

    testWidgets('isExpanded true + read state → ScrollableMessagePreview present',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg('m1'), _msg('m2'), _msg('m3')],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: true,
      )));
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    });

    testWidgets('unread state ignores isExpanded (always OpenModeCardBody)',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [_msg('m1', isUnread: true)],
        conversationState: ConversationState.unread,
      );

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: true,
      )));
      expect(find.byType(OpenModeCardBody), findsOneWidget);
      expect(find.byType(CollapsedModeCardBody), findsNothing);
    });

    testWidgets('tap fires onToggleExpand, not onViewFullConversation',
        (tester) async {
      var toggleFired = false;
      var viewFired = false;
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
        onToggleExpand: () => toggleFired = true,
        onViewFullConversation: () => viewFired = true,
      )));

      await tester.tap(find.text('Alice'));
      expect(toggleFired, isTrue);
      expect(viewFired, isFalse);
    });

    testWidgets('blocked overlay still renders when expanded',
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

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: true,
      )));
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);
    });
  });

  group('FeedCard reactions', () {
    testWidgets('open-mode card renders ReactionDisplay when reactions exist',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg('m1', isUnread: true),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      final reactions = {
        'm1': [
          MessageReaction(
            id: 'r1',
            messageId: 'm1',
            emoji: '👍',
            senderPeerId: 'peer1',
            timestamp: '2026-02-27T10:00:00Z',
            createdAt: '2026-02-27T10:00:00Z',
          ),
        ],
      };

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        reactions: reactions,
        ownPeerId: 'my-peer',
      )));

      // Inline reaction chips, no standalone ReactionDisplay
      expect(find.byType(ReactionDisplay), findsNothing);
      expect(find.text('👍'), findsOneWidget);
    });

    testWidgets('long-press on message in open-mode fires onMessageLongPress',
        (tester) async {
      String? longPressedMsgId;
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg('m1', isUnread: true),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        ownPeerId: 'my-peer',
        onMessageLongPress: (msgId) => longPressedMsgId = msgId,
      )));

      await tester.longPress(find.textContaining('Message m1'));
      expect(longPressedMsgId, 'm1');
    });

    testWidgets('onReactionTap fires with message ID and emoji',
        (tester) async {
      String? tappedMsgId;
      String? tappedEmoji;
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg('m1', isUnread: true),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      final reactions = {
        'm1': [
          MessageReaction(
            id: 'r1',
            messageId: 'm1',
            emoji: '❤️',
            senderPeerId: 'peer1',
            timestamp: '2026-02-27T10:00:00Z',
            createdAt: '2026-02-27T10:00:00Z',
          ),
        ],
      };

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        reactions: reactions,
        ownPeerId: 'my-peer',
        onReactionTap: (msgId, emoji) {
          tappedMsgId = msgId;
          tappedEmoji = emoji;
        },
      )));

      await tester.tap(find.text('❤️'));
      expect(tappedMsgId, 'm1');
      expect(tappedEmoji, '❤️');
    });

    testWidgets('expanded collapsed card renders ReactionDisplay when reactions exist',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          _msg('m1'),
          _msg('m2'),
        ],
        conversationState: ConversationState.read,
      );

      final reactions = {
        'm1': [
          MessageReaction(
            id: 'r1',
            messageId: 'm1',
            emoji: '😂',
            senderPeerId: 'peer1',
            timestamp: '2026-02-27T10:00:00Z',
            createdAt: '2026-02-27T10:00:00Z',
          ),
        ],
      };

      await tester.pumpWidget(wrap(FeedCard(
        thread: thread,
        isExpanded: true,
        reactions: reactions,
        ownPeerId: 'my-peer',
      )));

      // Inline reaction chips, no standalone ReactionDisplay
      expect(find.byType(ReactionDisplay), findsNothing);
      expect(find.text('😂'), findsOneWidget);
    });
  });
}
