import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/widgets/caught_up_empty_state.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 134-P7 (TC-27): the loaded-but-empty Feed shows the "caught up" state — a
/// green [Icons.done_all] + the `feed_all_caught_up` string — and NEVER the old
/// `feed_ready_for_user` / "Your feed is ready" empty card.
///
/// Mounts the FeedScreen directly (the wired harness's buildFeedWired /
/// pumpFeedFrames are local closures inside feed_wired_test.dart, not
/// importable). AmbientBackground.repeat() hangs pumpAndSettle, so use bounded
/// pumps only.
void main() {
  void setPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildFeedScreen({
    required List<FeedItem> feedItems,
    bool feedLoaded = true,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FeedScreen(
          username: 'Alice',
          feedItems: feedItems,
          feedLoaded: feedLoaded,
          activeTab: 'feed',
          onSwitchView: (_) {},
          userPeerId: 'alice-peer',
          backgroundPreference: BackgroundPreference.defaultBackground,
        ),
      ),
    );
  }

  testWidgets(
    'TC-27: a loaded, zero-item Feed shows the caught-up state (green done_all '
    '+ feed_all_caught_up) and NOT the old "Your feed is ready" copy',
    (tester) async {
      setPhoneViewport(tester);

      await tester.pumpWidget(
        buildFeedScreen(feedItems: const [], feedLoaded: true),
      );
      await tester.pump();

      // The new caught-up state renders.
      expect(find.byType(CaughtUpEmptyState), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(find.text("You're all caught up"), findsOneWidget);

      // The green done_all icon is tinted with the feed green-500 token.
      final BuildContext context = tester.element(
        find.byType(CaughtUpEmptyState),
      );
      final Icon icon = tester.widget<Icon>(find.byIcon(Icons.done_all));
      expect(icon.color, context.feedTokens.green500);

      // The legacy empty-state copy is gone.
      expect(find.textContaining('Your feed is ready'), findsNothing);
    },
  );

  testWidgets(
    'TC-27b: a still-loading Feed shows loading placeholders, not the '
    'caught-up state',
    (tester) async {
      setPhoneViewport(tester);

      await tester.pumpWidget(
        buildFeedScreen(feedItems: const [], feedLoaded: false),
      );
      await tester.pump();

      // Loading state is preserved (only the LOADED-empty state changes).
      expect(find.byKey(const ValueKey('feed-loading-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-loading-status')), findsOneWidget);
      expect(find.byType(CaughtUpEmptyState), findsNothing);
    },
  );
}
