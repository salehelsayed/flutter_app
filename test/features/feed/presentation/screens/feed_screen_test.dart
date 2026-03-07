import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';

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

      itemsNotifier.value = [
        buildThreadItem(
          id: 'thread_bob',
          username: 'Bob',
          timestamp: DateTime.utc(2026, 3, 1, 10),
        ),
      ];
      await tester.pump();

      expect(find.byKey(const ValueKey('feed-loading-card-0')), findsNothing);
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
}
