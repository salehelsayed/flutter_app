import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background_mirrored.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

// ─── Data Generator ───────────────────────────────────────────────────────────

List<FeedItem> _generateFeedItems() {
  final now = DateTime(2026, 2, 20, 14, 0);
  final items = <FeedItem>[];
  final states = ConversationState.values; // unread, active, replied, read
  final usernames = [
    'Alice',
    'Bob',
    'Charlie',
    'Diana',
    'Eve',
    'Frank',
    'Grace',
    'Hector',
    'Iris',
    'Jack',
    'Kate',
    'Leo',
    'Maya',
    'Nora',
    'Oscar',
  ];

  // 15 ThreadFeedItems — mix of all 4 conversation states, 3–8 messages each
  for (var i = 0; i < 15; i++) {
    final state = states[i % states.length];
    final messageCount = 3 + (i % 6); // 3, 4, 5, 6, 7, 8, 3, 4, …
    final messages = <ThreadMessage>[];

    for (var j = 0; j < messageCount; j++) {
      final isIncoming = j % 3 != 0; // 2/3 incoming, 1/3 outgoing
      final msgTime = now.subtract(Duration(hours: i * 2, minutes: j * 15));
      messages.add(
        ThreadMessage(
          id: 'msg_${i}_$j',
          text: 'Message $j in thread $i — lorem ipsum dolor sit amet.',
          time: '${msgTime.hour}:${msgTime.minute.toString().padLeft(2, '0')}',
          timestamp: msgTime,
          isUnread: state == ConversationState.unread && j >= messageCount - 2,
          isIncoming: isIncoming,
          status: isIncoming ? null : 'delivered',
          quotedMessageId: (j > 1 && j % 4 == 0) ? 'msg_${i}_${j - 1}' : null,
        ),
      );
    }

    items.add(
      ThreadFeedItem(
        id: 'thread_$i',
        timestamp: now.subtract(Duration(hours: i * 2)),
        contactPeerId: 'peer_$i',
        contactUsername: usernames[i],
        messages: messages,
        unreadCount: state == ConversationState.unread ? 3 : 0,
        isUnreadCard: state == ConversationState.unread,
        conversationState: state,
        lastRepliedAt: state == ConversationState.replied
            ? now.subtract(Duration(hours: i))
            : null,
      ),
    );
  }

  // 5 ConnectionFeedItems
  for (var i = 0; i < 5; i++) {
    items.add(
      ConnectionFeedItem(
        id: 'connection_${i + 15}',
        timestamp: now.subtract(Duration(days: i + 1)),
        contactPeerId: 'peer_${i + 15}',
        contactUsername: 'Contact${i + 15}',
      ),
    );
  }

  return items;
}

// ─── Test Harness ─────────────────────────────────────────────────────────────

class _FeedTestHarness extends StatefulWidget {
  final List<FeedItem> feedItems;
  final String? initialExpandedCardId;
  final BackgroundPreference backgroundPreference;

  const _FeedTestHarness({
    required this.feedItems,
    this.initialExpandedCardId,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  State<_FeedTestHarness> createState() => _FeedTestHarnessState();
}

class _FeedTestHarnessState extends State<_FeedTestHarness> {
  String? expandedCardId;
  final Map<String, String> draftTexts = {};
  final Map<String, String> activeQuoteMessageIds = {};
  String? activeFocusPeerId;

  @override
  void initState() {
    super.initState();
    expandedCardId = widget.initialExpandedCardId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeedScreen(
        username: 'PerfTestUser',
        feedItems: widget.feedItems,
        backgroundPreference: widget.backgroundPreference,
        onSwitchView: (_) {},
        activeTab: 'feed',
        expandedCardId: expandedCardId,
        onToggleExpand: (id) => setState(() {
          expandedCardId = expandedCardId == id ? null : id;
        }),
        onInlineSend: (_, _) {},
        draftTexts: draftTexts,
        // Match FeedWired: draft text updates are stored for later restoration
        // without rebuilding the whole feed on every keystroke.
        onDraftChanged: (peerId, text) {
          if (text.isEmpty) {
            draftTexts.remove(peerId);
          } else {
            draftTexts[peerId] = text;
          }
        },
        activeQuoteMessageIds: activeQuoteMessageIds,
        onQuoteReply: (peerId, msgId) => setState(() {
          activeQuoteMessageIds[peerId] = msgId;
        }),
        onClearQuote: (peerId) => setState(() {
          activeQuoteMessageIds.remove(peerId);
        }),
        activeFocusPeerId: activeFocusPeerId,
        onInputFocusChanged: (peerId, hasFocus) => setState(() {
          activeFocusPeerId = hasFocus ? peerId : null;
        }),
      ),
    );
  }
}

/// Pumps [FeedScreen] wrapped in a [MaterialApp] with state management.
/// Settles entry animations (~800ms worth of frames).
Future<void> _pumpFeedScreen(
  WidgetTester tester,
  List<FeedItem> items, {
  String? expandedCardId,
  BackgroundPreference backgroundPreference =
      BackgroundPreference.defaultBackground,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _FeedTestHarness(
        feedItems: items,
        initialExpandedCardId: expandedCardId,
        backgroundPreference: backgroundPreference,
      ),
    ),
  );
  // Pump through entry animations (600ms card + 540ms connection + buffer)
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

FeedCard? _nextBuiltCollapsedCard(
  WidgetTester tester,
  Set<String> exercisedThreadIds,
) {
  for (final card in tester.widgetList<FeedCard>(find.byType(FeedCard))) {
    if (!card.thread.isOpenMode &&
        !exercisedThreadIds.contains(card.thread.id)) {
      return card;
    }
  }
  return null;
}

// ─── Frame Timing Collector ───────────────────────────────────────────────────

/// Collects [FrameTiming] data from the engine via [SchedulerBinding].
///
/// Uses `buildDuration` (vsyncStart → buildFinish) which measures the actual
/// framework build/layout/paint phase, excluding vsync idle wait and GPU
/// raster time. This gives accurate measurements regardless of simulator
/// frame rate.
class _FrameTimingCollector {
  final _timings = <FrameTiming>[];
  TimingsCallback? _callback;

  void start() {
    _timings.clear();
    _callback = (List<FrameTiming> timings) => _timings.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(_callback!);
  }

  /// Stops collecting and waits briefly for pending callbacks to arrive.
  Future<void> stop() async {
    if (_callback == null) return;
    // Engine reports timings asynchronously; give callbacks time to fire.
    await Future.delayed(const Duration(milliseconds: 200));
    SchedulerBinding.instance.removeTimingsCallback(_callback!);
    _callback = null;
  }

  bool get hasData => _timings.isNotEmpty;

  _FrameStats get stats {
    final times = _timings
        .map((t) => t.buildDuration.inMicroseconds / 1000.0)
        .toList();
    return _FrameStats(times);
  }
}

// ─── Frame Stats ──────────────────────────────────────────────────────────────

class _FrameStats {
  final List<double> buildTimesMs;

  _FrameStats(this.buildTimesMs);

  bool get hasData => buildTimesMs.isNotEmpty;

  double get average =>
      buildTimesMs.reduce((a, b) => a + b) / buildTimesMs.length;

  double percentile(double p) {
    final sorted = List<double>.from(buildTimesMs)..sort();
    final idx = ((p / 100) * (sorted.length - 1)).round();
    return sorted[idx];
  }

  double get worst {
    final sorted = List<double>.from(buildTimesMs)..sort();
    return sorted.last;
  }

  void printSummary(String label) {
    if (!hasData) {
      debugPrint('[$label] No frame data');
      return;
    }
    debugPrint(
      '[$label] '
      'Frames: ${buildTimesMs.length} | '
      'Avg: ${average.toStringAsFixed(2)}ms | '
      'P90: ${percentile(90).toStringAsFixed(2)}ms | '
      'P99: ${percentile(99).toStringAsFixed(2)}ms | '
      'Worst: ${worst.toStringAsFixed(2)}ms',
    );
  }
}

/// Pumps [count] frames at 60fps intervals (no measurement, just animation).
Future<void> _pumpFrames(WidgetTester tester, {int count = 30}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Asserts frame timing thresholds. Skips assertions if no data collected.
///
/// Thresholds are per-scenario to account for different workload profiles.
/// Steady-state animations (scroll, swipe) use tight budgets.
/// Layout-change operations (expand/collapse, text input) use wider budgets
/// because first-mount and full-tree-rebuild frames are inherently costlier
/// in debug mode.
void _assertThresholds(
  _FrameStats stats,
  String label, {
  double maxAvgMs = 8,
  double maxP99Ms = 16,
  double maxWorstMs = 32,
}) {
  stats.printSummary(label);

  if (!stats.hasData) {
    fail(
      '[$label] No FrameTiming data collected — cannot validate performance',
    );
  }

  expect(
    stats.average,
    lessThan(maxAvgMs),
    reason:
        '[$label] Average build time ${stats.average.toStringAsFixed(2)}ms > ${maxAvgMs}ms',
  );
  expect(
    stats.percentile(99),
    lessThan(maxP99Ms),
    reason:
        '[$label] P99 build time ${stats.percentile(99).toStringAsFixed(2)}ms > ${maxP99Ms}ms',
  );
  expect(
    stats.worst,
    lessThan(maxWorstMs),
    reason:
        '[$label] Worst build time ${stats.worst.toStringAsFixed(2)}ms > ${maxWorstMs}ms',
  );
}

Future<_FrameStats> _collectScrollStats(WidgetTester tester) async {
  final scrollable = find.byType(CustomScrollView);
  expect(scrollable, findsOneWidget);

  final collector = _FrameTimingCollector()..start();

  await tester.fling(scrollable, const Offset(0, -1500), 3000);
  await _pumpFrames(tester, count: 30);

  await tester.fling(scrollable, const Offset(0, 1500), 3000);
  await _pumpFrames(tester, count: 30);

  await collector.stop();
  return collector.stats;
}

void _assertBackgroundScrollDoesNotRegress(
  _FrameStats baselineStats,
  _FrameStats backgroundStats,
  String label,
) {
  baselineStats.printSummary('Default baseline for $label scroll');
  backgroundStats.printSummary('$label scroll');

  if (!baselineStats.hasData || !backgroundStats.hasData) {
    fail('[$label scroll] Missing FrameTiming data for baseline comparison');
  }

  final baselineP99 = baselineStats.percentile(99);
  final backgroundP99 = backgroundStats.percentile(99);

  expect(
    backgroundStats.average,
    lessThan(max(8.0, baselineStats.average + 2.0)),
    reason:
        '[$label scroll] Average build time ${backgroundStats.average.toStringAsFixed(2)}ms regressed from default ${baselineStats.average.toStringAsFixed(2)}ms',
  );
  expect(
    backgroundP99,
    lessThan(max(24.0, baselineP99 * 1.25)),
    reason:
        '[$label scroll] P99 build time ${backgroundP99.toStringAsFixed(2)}ms regressed from default ${baselineP99.toStringAsFixed(2)}ms',
  );
  expect(
    backgroundStats.worst,
    lessThan(max(100.0, baselineStats.worst * 1.25)),
    reason:
        '[$label scroll] Worst build time ${backgroundStats.worst.toStringAsFixed(2)}ms regressed from default ${baselineStats.worst.toStringAsFixed(2)}ms',
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  final items = _generateFeedItems();

  group('Feed performance', () {
    testWidgets('1. Scroll performance', (tester) async {
      await _pumpFeedScreen(tester, items);

      final scrollable = find.byType(CustomScrollView);
      expect(scrollable, findsOneWidget);

      final collector = _FrameTimingCollector()..start();

      // Fling scroll to bottom
      await tester.fling(scrollable, const Offset(0, -1500), 3000);
      await _pumpFrames(tester, count: 30);

      // Fling scroll back to top
      await tester.fling(scrollable, const Offset(0, 1500), 3000);
      await _pumpFrames(tester, count: 30);

      await collector.stop();
      // Debug-mode flutter test scroll timing includes occasional sliver/card
      // first-build spikes. Keep average and P99 budgets tight while allowing
      // one isolated debug outlier to avoid false failures on lazy card mount.
      _assertThresholds(
        collector.stats,
        'Scroll',
        maxP99Ms: 24,
        maxWorstMs: 100,
      );
    });

    testWidgets('2. Card expand/collapse performance', (tester) async {
      await _pumpFeedScreen(tester, items);

      final collector = _FrameTimingCollector()..start();

      final scrollable = find.byType(CustomScrollView);
      final exercisedThreadIds = <String>{};

      for (var attempts = 0; exercisedThreadIds.length < 3; attempts++) {
        final nextCard = _nextBuiltCollapsedCard(tester, exercisedThreadIds);
        if (nextCard == null) {
          expect(
            attempts,
            lessThan(20),
            reason: 'Could not find three collapsed feed cards to exercise',
          );
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pump(const Duration(milliseconds: 16));
          continue;
        }

        final card = find.byKey(ValueKey(nextCard.thread.id));
        final headerLabel = find.descendant(
          of: card,
          matching: find.text(nextCard.thread.displayName),
        );

        await tester.ensureVisible(headerLabel);
        await tester.pump(const Duration(milliseconds: 16));

        // Expand via the tappable collapsed header instead of the full card body.
        await tester.tap(headerLabel);
        await _pumpFrames(tester, count: 25);

        final collapseHint = find.descendant(
          of: card,
          matching: find.text(
            AppLocalizations.of(tester.element(card))!.feed_collapse,
          ),
        );

        await tester.ensureVisible(collapseHint);
        await tester.pump(const Duration(milliseconds: 16));

        await tester.tap(collapseHint);
        await _pumpFrames(tester, count: 25);

        exercisedThreadIds.add(nextCard.thread.id);
      }

      await collector.stop();
      // Expand triggers first-mount of 6 message bubbles + AnimatedSize +
      // BackdropFilter recalc. First frame spikes are expected in debug mode;
      // wider budget catches regressions without false positives.
      _assertThresholds(
        collector.stats,
        'Expand/Collapse',
        maxAvgMs: 16,
        maxP99Ms: 64,
        maxWorstMs: 100,
      );
    });

    testWidgets('3. Swipe-to-quote gesture performance', (tester) async {
      // Pre-expand thread_0 so SwipeToQuoteBubble widgets are rendered
      await _pumpFeedScreen(tester, items, expandedCardId: 'thread_0');

      final swipeable = find.byType(SwipeToQuoteBubble);
      expect(
        swipeable,
        findsWidgets,
        reason: 'No SwipeToQuoteBubble found — is the card expanded?',
      );

      final target = swipeable.first;
      final center = tester.getCenter(target);

      final collector = _FrameTimingCollector()..start();

      // Start drag gesture
      final gesture = await tester.startGesture(center);

      // Move past touch slop (18px default) to start drag recognition
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));

      // Drag right in 8 increments (40px total, well past 36px trigger)
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(5, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Release and pump through snap-back animation
      await gesture.up();
      await _pumpFrames(tester, count: 15);

      await collector.stop();
      // Steady-state transform animation: tight budget
      _assertThresholds(collector.stats, 'Swipe-to-quote');
    });

    testWidgets('4. Compose input performance', (tester) async {
      // Pre-expand thread_0 so the inline reply input is rendered
      await _pumpFeedScreen(tester, items, expandedCardId: 'thread_0');

      final composeFinder = find.descendant(
        of: find.byKey(const ValueKey('thread_0')),
        matching: find.byType(InlineReplyInput),
      );
      expect(composeFinder, findsOneWidget);

      final textField = find.descendant(
        of: composeFinder,
        matching: find.byType(TextField),
      );
      expect(textField, findsOneWidget);

      // Tap to focus
      await tester.tap(textField);
      await tester.pump(const Duration(milliseconds: 16));

      final collector = _FrameTimingCollector()..start();

      // Enter text in 10 chunks, each triggering a rebuild
      const fullText = 'Performance test: typing fifty characters rapidly!';
      for (var i = 1; i <= 10; i++) {
        final chunk = fullText.substring(0, min(i * 5, fullText.length));
        await tester.enterText(textField, chunk);
        await tester.pump(const Duration(milliseconds: 16));
      }

      await collector.stop();
      // enterText replaces full text and exercises InlineReplyInput's local
      // text/direction/send-button state. The harness stores drafts without
      // setState to match production FeedWired behavior.
      _assertThresholds(
        collector.stats,
        'Compose input',
        maxAvgMs: 32,
        maxP99Ms: 64,
        maxWorstMs: 100,
      );
    });

    testWidgets('5. Cosmic scroll performance', (tester) async {
      await _pumpFeedScreen(tester, items);
      expect(find.byType(CosmicBackground), findsNothing);

      final baselineStats = await _collectScrollStats(tester);

      await _pumpFeedScreen(
        tester,
        items,
        backgroundPreference: BackgroundPreference.cosmic,
      );

      expect(find.byType(CosmicBackground), findsOneWidget);

      final cosmicStats = await _collectScrollStats(tester);

      _assertBackgroundScrollDoesNotRegress(
        baselineStats,
        cosmicStats,
        'Cosmic',
      );
    });

    testWidgets('6. Mirrored cosmic scroll performance', (tester) async {
      await _pumpFeedScreen(tester, items);
      expect(find.byType(CosmicBackgroundMirrored), findsNothing);

      final baselineStats = await _collectScrollStats(tester);

      await _pumpFeedScreen(
        tester,
        items,
        backgroundPreference: BackgroundPreference.cosmicMirrored,
      );

      expect(find.byType(CosmicBackgroundMirrored), findsOneWidget);

      final mirroredStats = await _collectScrollStats(tester);

      _assertBackgroundScrollDoesNotRegress(
        baselineStats,
        mirroredStats,
        'Mirrored cosmic',
      );
    });

    testWidgets('7. Daylight Lagoon scroll performance', (tester) async {
      await _pumpFeedScreen(tester, items);
      expect(find.byType(DaylightLagoonBackground), findsNothing);

      final baselineStats = await _collectScrollStats(tester);

      await _pumpFeedScreen(
        tester,
        items,
        backgroundPreference: BackgroundPreference.daylightLagoon,
      );

      expect(find.byType(DaylightLagoonBackground), findsOneWidget);

      final daylightStats = await _collectScrollStats(tester);

      _assertBackgroundScrollDoesNotRegress(
        baselineStats,
        daylightStats,
        'Daylight Lagoon',
      );
    });
  });
}
