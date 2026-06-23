import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_swipe_card.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 134-P7 (TC-31) reduced-motion: when `MediaQuery.disableAnimations` (OR
/// `accessibleNavigation`) is true, every feed-local animation collapses to
/// `Duration.zero` — the focus-collapse (AnimatedOpacity + AnimatedSize), the
/// nav-bar fade, and the swipe-card movement — and the AmbientBackground feed
/// entrance does NOT start an infinite repeat() (so a bounded pump settles).
///
/// Mounts FeedScreen directly (buildFeedWired / pumpFeedFrames are local
/// closures in feed_wired_test.dart, not importable). AmbientBackground.repeat()
/// hangs pumpAndSettle, so use bounded pumps only.
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
          text: 'Latest message for $username',
          time: '12:05',
          timestamp: timestamp,
          isIncoming: true,
          isUnread: false,
          status: 'read',
        ),
      ],
    );
  }

  Widget buildFeedScreen({
    required List<FeedItem> feedItems,
    String? focusedId,
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: FeedScreen(
              username: 'Alice',
              feedItems: feedItems,
              feedLoaded: true,
              activeTab: 'feed',
              onSwitchView: (_) {},
              focusedId: focusedId,
              userPeerId: 'alice-peer',
              backgroundPreference: BackgroundPreference.defaultBackground,
            ),
          ),
        ),
      ),
    );
  }

  // FEED-LOCAL AnimatedOpacity durations only. The focused composer mounts a
  // Material TextField whose InputDecorator carries a framework-internal 20ms
  // AnimatedOpacity — that is NOT a feed animation (composer is P5, out of the
  // P7 motion scope), so exclude any AnimatedOpacity that descends from an
  // InputDecorator.
  bool underInputDecorator(Element element) {
    var found = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is InputDecorator) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  List<Duration> animatedOpacityDurations(WidgetTester tester) => find
      .byType(AnimatedOpacity)
      .evaluate()
      .where((e) => !underInputDecorator(e))
      .map((e) => (e.widget as AnimatedOpacity).duration)
      .toList();

  // No framework AnimatedSize appears in this tree — both are the feed
  // focus-collapse sizes — but apply the same guard for safety.
  List<Duration> animatedSizeDurations(WidgetTester tester) => find
      .byType(AnimatedSize)
      .evaluate()
      .where((e) => !underInputDecorator(e))
      .map((e) => (e.widget as AnimatedSize).duration)
      .toList();

  final items = [
    buildThreadItem(
      id: 't1',
      username: 'Ann',
      timestamp: DateTime.utc(2026, 6, 20, 12, 0),
    ),
    buildThreadItem(
      id: 't2',
      username: 'Ben',
      timestamp: DateTime.utc(2026, 6, 20, 11, 0),
    ),
  ];

  testWidgets(
    'TC-31: with disableAnimations=true and a card focused, every feed-local '
    'AnimatedOpacity/AnimatedSize (focus-collapse + nav-fade) and the swipe '
    'movement collapse to Duration.zero',
    (tester) async {
      setPhoneViewport(tester);

      // Focus t1 so t2 collapses (producing the sibling AnimatedSize/Opacity).
      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: items,
          focusedId: 't1_peer',
          disableAnimations: true,
        ),
      );
      // Bounded pumps — if AmbientBackground starts an infinite repeat() this
      // never settles; reduced motion must NOT start it.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Nav bar is mounted (its fade is one of the AnimatedOpacity widgets).
      expect(find.byType(FeedNavigationBar), findsOneWidget);

      // EVERY feed-local AnimatedOpacity (sibling fade + nav fade) is zero.
      final opacityDurations = animatedOpacityDurations(tester);
      expect(opacityDurations, isNotEmpty);
      for (final d in opacityDurations) {
        expect(d, Duration.zero);
      }

      // EVERY feed-local AnimatedSize (sibling collapse) is zero.
      final sizeDurations = animatedSizeDurations(tester);
      expect(sizeDurations, isNotEmpty);
      for (final d in sizeDurations) {
        expect(d, Duration.zero);
      }

      // Each rendered swipe card was told to reduce motion (its Dismissible
      // movementDuration collapses to zero).
      final swipeCards = tester.widgetList<FeedSwipeCard>(
        find.byType(FeedSwipeCard),
      );
      expect(swipeCards, isNotEmpty);
      for (final c in swipeCards) {
        expect(c.reduceMotion, isTrue);
      }
    },
  );

  testWidgets(
    'TC-31b: with animations ENABLED, the same focus-collapse + nav-fade '
    'durations are the non-zero design values (220ms / 200ms) — guards the '
    'reduced-motion mutation',
    (tester) async {
      setPhoneViewport(tester);

      await tester.pumpWidget(
        buildFeedScreen(
          feedItems: items,
          focusedId: 't1_peer',
          disableAnimations: false,
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final opacityDurations = animatedOpacityDurations(tester);
      expect(opacityDurations, isNotEmpty);
      // No feed-local AnimatedOpacity collapses to zero when motion is on.
      expect(
        opacityDurations.every((d) => d > Duration.zero),
        isTrue,
        reason: 'all feed AnimatedOpacity durations should be > 0 with motion on',
      );

      final sizeDurations = animatedSizeDurations(tester);
      expect(sizeDurations, isNotEmpty);
      expect(sizeDurations.every((d) => d > Duration.zero), isTrue);
    },
  );

  testWidgets(
    'TC-31c: accessibleNavigation alone (disableAnimations false) also '
    'collapses the feed-local durations to zero',
    (tester) async {
      setPhoneViewport(tester);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  accessibleNavigation: true,
                ),
                child: FeedScreen(
                  username: 'Alice',
                  feedItems: items,
                  feedLoaded: true,
                  activeTab: 'feed',
                  onSwitchView: (_) {},
                  focusedId: 't1_peer',
                  userPeerId: 'alice-peer',
                  backgroundPreference: BackgroundPreference.defaultBackground,
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      for (final d in animatedOpacityDurations(tester)) {
        expect(d, Duration.zero);
      }
      for (final d in animatedSizeDurations(tester)) {
        expect(d, Duration.zero);
      }
    },
  );
}
