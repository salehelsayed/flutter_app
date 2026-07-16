import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background_mirrored.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'support/android_critical_performance_budget.dart';

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
  // 134-P5: the per-card composer/quote/focus state was removed from the
  // FeedScreen contract; the redesigned screen drives a single focusedId.
  // (Full TC-36 perf-fixture re-author with the letter-card model is P8.)
  String? focusedId;

  @override
  void initState() {
    super.initState();
    focusedId = widget.initialExpandedCardId;
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
        focusedId: focusedId,
        onFocusCard: (id) => setState(() => focusedId = id),
        onClearFocus: () => setState(() => focusedId = null),
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

  int get frameCount => buildTimesMs.length;

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

/// Durable metrics for the device-critical feed scroll budget.
///
/// This value is also consumed by the runtime-dispatched sims campaign, so the
/// centrally prepared Android APK exercises the exact FEED 1 measurement and
/// thresholds instead of selecting a second compile-time `PERF_TARGET`.
final class FeedScrollPerformanceResult {
  const FeedScrollPerformanceResult({
    required this.frameCount,
    required this.averageBuildMs,
    required this.p99BuildMs,
    required this.worstBuildMs,
  });

  final int frameCount;
  final double averageBuildMs;
  final double p99BuildMs;
  final double worstBuildMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'frameCount': frameCount,
    'averageBuildMs': averageBuildMs,
    'p99BuildMs': p99BuildMs,
    'worstBuildMs': worstBuildMs,
  };
}

/// Runs FEED 1 as a callable runtime action and returns its measured evidence.
///
/// The assertions deliberately retain FEED 1's existing debug/device budgets.
/// A missing engine timing sample fails; it is never converted to a skip.
Future<FeedScrollPerformanceResult> runFeedScrollCriticalPerformance(
  WidgetTester tester,
) async {
  final items = _generateFeedItems();
  await _pumpFeedScreen(tester, items);

  final scrollable = find.byType(CustomScrollView);
  expect(scrollable, findsOneWidget);

  final collector = _FrameTimingCollector()..start();

  await tester.fling(scrollable, const Offset(0, -1500), 3000);
  await _pumpFrames(tester, count: 30);

  await tester.fling(scrollable, const Offset(0, 1500), 3000);
  await _pumpFrames(tester, count: 30);

  await collector.stop();
  final stats = collector.stats;
  _assertThresholds(
    stats,
    'Scroll',
    maxAvgMs: androidFeedAverageBuildBudgetMs,
    maxP99Ms: androidFeedP99BuildBudgetMs,
    maxWorstMs: androidFeedWorstBuildBudgetMs,
  );
  return FeedScrollPerformanceResult(
    frameCount: stats.frameCount,
    averageBuildMs: stats.average,
    p99BuildMs: stats.percentile(99),
    worstBuildMs: stats.worst,
  );
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
  registerFeedPerf();
}

void registerFeedPerf() {
  final items = _generateFeedItems();

  // 1. Scroll performance
  testWidgets('FEED 1', (tester) async {
    await runFeedScrollCriticalPerformance(tester);
  });

  // 2/3/4. Card expand-collapse, swipe-to-quote, and inline-compose perf.
  //
  // 134-P8: these three scenarios drove the OLD per-card FeedCard /
  // InlineReplyInput / in-card SwipeToQuoteBubble model that the feed redesign
  // removed. The redesigned FeedScreen focuses a card and raises a single
  // screen-level FeedComposer instead. Re-authoring these perf fixtures to the
  // letter-card / focus model is device-harness scope (TC-36 follow-up) and is
  // intentionally left as a documented gap — skipped, not deleted, so the
  // re-author lands here. (FEED 1/5/6/7 scroll + background perf still run.)
  testWidgets('FEED 2', (tester) async {}, skip: true);
  testWidgets('FEED 3', (tester) async {}, skip: true);
  testWidgets('FEED 4', (tester) async {}, skip: true);

  // 5. Cosmic scroll performance
  testWidgets('FEED 5', (tester) async {
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

    _assertBackgroundScrollDoesNotRegress(baselineStats, cosmicStats, 'Cosmic');
  });

  // 6. Default Mirror Cosmic scroll performance
  testWidgets('FEED 6', (tester) async {
    await _pumpFeedScreen(
      tester,
      items,
      backgroundPreference: BackgroundPreference.aurora,
    );
    expect(find.byType(CosmicBackgroundMirrored), findsNothing);

    final baselineStats = await _collectScrollStats(tester);

    await _pumpFeedScreen(
      tester,
      items,
      backgroundPreference: BackgroundPreference.defaultBackground,
    );

    expect(find.byType(CosmicBackgroundMirrored), findsOneWidget);

    final mirroredStats = await _collectScrollStats(tester);

    _assertBackgroundScrollDoesNotRegress(
      baselineStats,
      mirroredStats,
      'Default Mirror Cosmic',
    );
  });

  // 7. Daylight Lagoon scroll performance
  testWidgets('FEED 7', (tester) async {
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
}
