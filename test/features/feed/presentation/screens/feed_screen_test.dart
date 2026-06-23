import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_one_to_one.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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
    EdgeInsets viewInsets = EdgeInsets.zero,
    String? focusedId,
    void Function(String threadId)? onFocusCard,
    String? userPeerId = 'alice-peer',
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
    BackgroundReadableTone? readableToneOverride,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(viewInsets: viewInsets),
            child: FeedScreen(
              username: 'Alice',
              feedItems: feedItems,
              feedItemsListenable: feedItemsListenable,
              feedLoaded: feedLoaded,
              activeTab: 'feed',
              onSwitchView: (_) {},
              focusedId: focusedId,
              onFocusCard: onFocusCard,
              userPeerId: userPeerId,
              backgroundPreference: backgroundPreference,
              readableToneOverride: readableToneOverride,
            ),
          ),
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
    expect(find.text('Remember'), findsNothing);
  });

  testWidgets(
    'loading and empty states use representative light readable roles',
    (tester) async {
      setPhoneViewport(tester);

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: const [],
          feedLoaded: false,
          readableToneOverride: BackgroundReadableTone.representativeLight,
        ),
      );
      await tester.pump();

      final loadingStatus = tester.widget<Container>(
        find.byKey(const ValueKey('feed-loading-status')),
      );
      final loadingDecoration = loadingStatus.decoration as BoxDecoration;
      expect(
        loadingDecoration.color,
        BackgroundReadableColors.representativeLight.surfaceRaised,
      );

      final loadingTitle = tester.widget<Text>(find.text('Loading Feed...'));
      expect(
        loadingTitle.style?.color,
        BackgroundReadableColors.representativeLight.textPrimary,
      );

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: const [],
          feedLoaded: true,
          readableToneOverride: BackgroundReadableTone.representativeLight,
        ),
      );
      await tester.pump();

      // 134-P7: the loaded-empty state is now the caught-up card.
      final emptyText = tester.widget<Text>(
        find.text("You're all caught up"),
      );
      expect(
        emptyText.style?.color,
        BackgroundReadableColors.representativeLight.textSecondary,
      );
    },
  );

  testWidgets('renders cosmic background when Feed preference is cosmic', (
    tester,
  ) async {
    setPhoneViewport(tester);

    await tester.pumpWidget(
      buildFeedScreen(
        feedItems: const [],
        backgroundPreference: BackgroundPreference.cosmic,
      ),
    );
    await tester.pump();

    expect(find.byType(CosmicBackground), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cosmic-background-root')),
      findsOneWidget,
    );
    expect(find.text('Feed'), findsOneWidget);
  });

  testWidgets('keeps default background when Feed preference is default', (
    tester,
  ) async {
    setPhoneViewport(tester);

    await tester.pumpWidget(buildFeedScreen(feedItems: const []));
    await tester.pump();

    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.text('Feed'), findsOneWidget);
  });

  testWidgets('renders daylight lagoon with light readable loading state', (
    tester,
  ) async {
    setPhoneViewport(tester);

    await tester.pumpWidget(
      buildFeedScreen(
        feedItems: const [],
        feedLoaded: false,
        backgroundPreference: BackgroundPreference.daylightLagoon,
      ),
    );
    await tester.pump();

    expect(find.byType(DaylightLagoonBackground), findsOneWidget);

    final loadingTitle = tester.widget<Text>(find.text('Loading Feed...'));
    expect(
      loadingTitle.style?.color,
      BackgroundReadableColors.representativeLight.textPrimary,
    );
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
    // 134-P7: the loaded-empty state now shows the caught-up copy.
    expect(find.text("You're all caught up"), findsOneWidget);
    expect(find.textContaining('Your feed is ready'), findsNothing);
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
      // 134-P5: the 1:1 letter card carries identity by avatar (no name header,
      // TC-16) — assert the card renders rather than a "Bob" header Text.
      expect(find.byType(LetterCardOneToOne), findsOneWidget);
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
      // 134-P5: cards lazily build — fewer than all 30 are realized at once.
      expect(
        find.byType(LetterCardOneToOne).evaluate().length,
        lessThan(items.length),
      );
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
    },
  );
}
