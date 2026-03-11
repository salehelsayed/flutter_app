import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

void main() {
  void setPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  ThreadFeedItem buildThreadItem({
    required String id,
    required String username,
    required DateTime timestamp,
  }) {
    return ThreadFeedItem(
      id: id,
      timestamp: timestamp,
      contactPeerId: '${id}_peer',
      contactUsername: username,
      conversationState: ConversationState.read,
      messages: [
        ThreadMessage(
          id: '${id}_message_0',
          text: 'First message for $username',
          time: '12:00',
          timestamp: timestamp.subtract(const Duration(minutes: 5)),
          isIncoming: true,
          isUnread: false,
          status: 'read',
        ),
        ThreadMessage(
          id: '${id}_message_1',
          text: 'Latest message for $username',
          time: '12:05',
          timestamp: timestamp,
          isIncoming: false,
          isUnread: false,
          status: 'read',
        ),
      ],
    );
  }

  Widget buildFeedScreen({
    required List<FeedItem> feedItems,
    ValueNotifier<List<FeedItem>>? feedItemsListenable,
    bool feedLoaded = true,
    String? expandedCardId,
    SessionReplyTracker? sessionReplies,
    Map<String, String>? activeQuoteMessageIds,
    void Function(String contactPeerId)? onClearQuote,
    void Function(String groupId, String text)? onGroupInlineSend,
    void Function(String contactPeerId, String messageId)? onQuoteReply,
    void Function(GroupThreadFeedItem)? onGroupAttach,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: FeedScreen(
          username: 'Alice',
          feedItems: feedItems,
          feedItemsListenable: feedItemsListenable,
          feedLoaded: feedLoaded,
          activeTab: 'feed',
          onSwitchView: (_) {},
          expandedCardId: expandedCardId,
          onToggleExpand: (_) {},
          sessionReplies: sessionReplies,
          activeQuoteMessageIds: activeQuoteMessageIds,
          onClearQuote: onClearQuote,
          onGroupInlineSend: onGroupInlineSend,
          onQuoteReply: onQuoteReply,
          onGroupAttach: onGroupAttach,
        ),
      ),
    );
  }

  testWidgets('renders loading placeholders while feed is still loading', (
    tester,
  ) async {
    setPhoneViewport(tester);

    await tester.pumpWidget(
      buildFeedScreen(feedItems: const [], feedLoaded: false),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('feed-loading-card-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-loading-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-loading-card-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-loading-status')), findsOneWidget);
    expect(find.text('Loading Feed...'), findsOneWidget);
    expect(find.text('Your recent threads are still syncing.'), findsOneWidget);
    expect(find.textContaining('Your feed is ready'), findsNothing);
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Orbit'), findsOneWidget);
    expect(find.text('Remember'), findsOneWidget);
  });

  testWidgets('renders empty state once feed load completes with no items', (
    tester,
  ) async {
    setPhoneViewport(tester);

    await tester.pumpWidget(
      buildFeedScreen(feedItems: const [], feedLoaded: true),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('feed-loading-card-0')), findsNothing);
    expect(find.textContaining('Your feed is ready'), findsOneWidget);
  });

  testWidgets(
    'swaps loading placeholders for real feed items when data arrives',
    (tester) async {
      setPhoneViewport(tester);

      final itemsNotifier = ValueNotifier<List<FeedItem>>(const <FeedItem>[]);
      addTearDown(itemsNotifier.dispose);

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: const [],
          feedItemsListenable: itemsNotifier,
          feedLoaded: false,
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('feed-loading-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-loading-status')), findsOneWidget);

      itemsNotifier.value = [
        buildThreadItem(
          id: 'thread_bob',
          username: 'Bob',
          timestamp: DateTime.utc(2026, 3, 1, 10),
        ),
      ];
      await tester.pump();

      expect(find.byKey(const ValueKey('feed-loading-card-0')), findsNothing);
      expect(find.byKey(const ValueKey('feed-loading-status')), findsNothing);
      expect(find.byKey(const ValueKey<String>('thread_bob')), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    },
  );

  testWidgets(
    'renders feed through CustomScrollView instead of eager scroll view',
    (tester) async {
      setPhoneViewport(tester);

      final items = List<FeedItem>.generate(
        30,
        (index) => buildThreadItem(
          id: 'thread_$index',
          username: 'User $index',
          timestamp: DateTime.utc(
            2026,
            3,
            1,
          ).subtract(Duration(minutes: index)),
        ),
      );

      await tester.pumpWidget(buildFeedScreen(feedItems: items));
      await tester.pump();

      final tailCardFinder = find.byKey(const ValueKey<String>('thread_29'));
      final feedScrollViewFinder = find.byType(CustomScrollView);

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(FeedCard).evaluate().length, lessThan(items.length));
      expect(tailCardFinder, findsNothing);

      for (var attempt = 0; attempt < 20; attempt++) {
        if (tailCardFinder.evaluate().isNotEmpty) {
          break;
        }

        await tester.drag(feedScrollViewFinder, const Offset(0, -400));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 700));

      expect(tailCardFinder, findsOneWidget);
      expect(find.text('User 29'), findsOneWidget);
    },
  );

  testWidgets(
    'preserves the expanded card element when thread ordering changes',
    (tester) async {
      setPhoneViewport(tester);

      final bob = buildThreadItem(
        id: 'thread_bob',
        username: 'Bob',
        timestamp: DateTime.utc(2026, 3, 1, 10),
      );
      final cara = buildThreadItem(
        id: 'thread_cara',
        username: 'Cara',
        timestamp: DateTime.utc(2026, 3, 1, 11),
      );

      await tester.pumpWidget(
        buildFeedScreen(feedItems: [bob, cara], expandedCardId: 'thread_bob'),
      );
      await tester.pump();

      final bobFinder = find.byKey(const ValueKey<String>('thread_bob'));
      final beforeElement = tester.element(bobFinder);

      expect(find.byType(ScrollableMessagePreview), findsOneWidget);

      final bobReordered = buildThreadItem(
        id: 'thread_bob',
        username: 'Bob',
        timestamp: DateTime.utc(2026, 3, 1, 12),
      );

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [bobReordered, cara],
          expandedCardId: 'thread_bob',
        ),
      );
      await tester.pump();

      final afterElement = tester.element(bobFinder);
      expect(identical(beforeElement, afterElement), isTrue);
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    },
  );

  testWidgets('maps active quote id to visible preview text and dismisses it', (
    tester,
  ) async {
    setPhoneViewport(tester);

    final item = ThreadFeedItem(
      id: 'thread_bob',
      timestamp: DateTime.utc(2026, 3, 1, 10),
      contactPeerId: 'bob-peer',
      contactUsername: 'Bob',
      conversationState: ConversationState.read,
      messages: [
        ThreadMessage(
          id: 'bob-msg-1',
          text: 'First quote target',
          time: '12:00',
          timestamp: DateTime.utc(2026, 3, 1, 9, 55),
          isIncoming: true,
        ),
      ],
    );
    String? clearedPeerId;

    await tester.pumpWidget(
      buildFeedScreen(
        feedItems: [item],
        activeQuoteMessageIds: const {'bob-peer': 'bob-msg-1'},
        onClearQuote: (contactPeerId) => clearedPeerId = contactPeerId,
      ),
    );
    await tester.pump();

    expect(find.text('Replying to'), findsOneWidget);
    expect(find.text('First quote target'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(clearedPeerId, 'bob-peer');
  });

  testWidgets(
    'maps active group quote id to visible preview text and dismisses it',
    (tester) async {
      setPhoneViewport(tester);

      final item = GroupThreadFeedItem(
        id: 'group_thread_g1',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        groupId: 'g1',
        groupName: 'Group One',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm-1',
            text: 'Quote this group message',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
            isUnread: true,
            senderUsername: 'Alice',
            senderPeerId: 'peer-alice',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );
      String? clearedKey;

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [item],
          activeQuoteMessageIds: const {'group:g1': 'gm-1'},
          onClearQuote: (contactPeerId) => clearedKey = contactPeerId,
        ),
      );
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Quote this group message'), findsWidgets);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(clearedKey, 'group:g1');
    },
  );

  testWidgets(
    'group card with session reply shows collapsed mode instead of open mode',
    (tester) async {
      // Suppress RenderFlex overflow errors from card layouts in test surface
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      setPhoneViewport(tester);

      // Group card in unread state (open mode)
      final groupItem = GroupThreadFeedItem(
        id: 'group_thread_g1',
        timestamp: DateTime.now(),
        groupId: 'g1',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm-1',
            text: 'Hello group',
            time: '3:33 AM',
            timestamp: DateTime.now(),
            isIncoming: true,
            isUnread: true,
            senderUsername: 'Hisam',
            senderPeerId: 'peer-hisam',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      // Without session reply — should be in open mode
      await tester.pumpWidget(buildFeedScreen(feedItems: [groupItem]));
      await tester.pump();
      expect(find.byType(OpenModeCardBody), findsOneWidget);

      // With session reply — should collapse to show sent message
      final tracker = SessionReplyTracker();
      tracker.track('group:g1', SessionReply.justNow('My reply'));

      await tester.pumpWidget(
        buildFeedScreen(feedItems: [groupItem], sessionReplies: tracker),
      );
      await tester.pump();
      expect(find.byType(CollapsedModeCardBody), findsOneWidget);
      expect(find.byType(OpenModeCardBody), findsNothing);
    },
  );

  testWidgets(
    'announcement member group card stays read-only even when callbacks are provided',
    (tester) async {
      setPhoneViewport(tester);

      final groupItem = GroupThreadFeedItem(
        id: 'group_thread_announce',
        timestamp: DateTime.utc(2026, 3, 1, 10),
        groupId: 'announce',
        groupName: 'Announcements',
        groupType: GroupType.announcement,
        myRole: GroupRole.member,
        messages: [
          ThreadMessage(
            id: 'gm-announce-1',
            text: 'Admin update',
            time: '12:00',
            timestamp: DateTime.utc(2026, 3, 1, 9, 55),
            isIncoming: true,
            isUnread: true,
            senderUsername: 'Admin',
            senderPeerId: 'peer-admin',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: [groupItem],
          onGroupInlineSend: (_, __) {},
          onQuoteReply: (_, __) {},
          onGroupAttach: (_) {},
        ),
      );
      await tester.pump();

      expect(
        find.text('Only admins can send messages in this group'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byType(SwipeToQuoteBubble), findsNothing);
    },
  );
}
