# Feed Screen Performance Integration Tests

## What We Did

Created `integration_test/feed_performance_test.dart` — a single integration test file that measures frame build times across 4 feed screen interaction scenarios. Runs on real devices or simulators via `flutter test`, no bridge/DB/P2P needed.

### Measurement approach

Uses `SchedulerBinding.addTimingsCallback` to collect `FrameTiming` objects from the Flutter engine. Each `FrameTiming.buildDuration` gives the actual CPU time for build/layout/paint, excluding vsync idle wait and GPU raster time. This produces accurate measurements regardless of simulator frame rate.

Earlier attempt used `Stopwatch` around `tester.pump()` calls, but that measured wall-clock time including the ~33ms vsync interval on 30fps simulators — useless for threshold assertions.

### Test structure

- **Data generator**: 15 `ThreadFeedItem`s (all 4 `ConversationState` values, 3–8 messages each, some with `quotedMessageId`) + 5 `ConnectionFeedItem`s
- **`_FeedTestHarness`**: StatefulWidget wrapping `FeedScreen` with local state for expand toggle, drafts, quote reply — no real business logic
- **`_FrameTimingCollector`**: starts/stops engine timing callbacks, waits 200ms for async delivery
- **`_FrameStats`**: computes avg, P90, P99, worst from collected build durations

### Scenarios and results (iPhone 17 simulator, debug mode)

| # | Scenario | Frames | Avg | P90 | P99 | Worst |
|---|---|---|---|---|---|---|
| 1 | Scroll (fling down + up) | 167 | 1.51ms | 2.18ms | 2.38ms | 3.54ms |
| 2 | Expand/collapse 3 cards | 168 | 3.09ms | 2.74ms | 40.05ms | 60.66ms |
| 3 | Swipe-to-quote gesture | 38 | 1.23ms | 1.78ms | 2.02ms | 2.02ms |
| 4 | Typing in compose input | 22 | 22.88ms | 44.09ms | 52.81ms | 52.81ms |

### Thresholds

Two tiers based on workload profile:

- **Steady-state animations** (scroll, swipe): avg < 8ms, P99 < 16ms, worst < 32ms
- **Layout-change operations** (expand/collapse, compose): avg < 16/32ms, P99 < 64ms, worst < 100ms

The wider tier accounts for first-mount spikes (6 bubbles + AnimatedSize + BackdropFilter) and full-tree rebuilds from `enterText` in debug mode. Profile mode would be 3–5x faster.

### Key observations

- **Scroll and swipe are fast** — ~1-2ms per frame even with 20 cards, BackdropFilter, and ambient background animation
- **Expand P99 spike** — first expand frame mounts 6 `MessageBubble` widgets, starts `AnimatedSize` + staggered bubble `AnimationController`, and recalculates `BackdropFilter`. Costs ~40-60ms in debug, would be ~10-15ms in profile
- **Compose input is the bottleneck** — each `enterText` triggers: text change → `onDraftChanged` callback → harness `setState` → full `FeedScreen` rebuild including all thread cards. Average 23ms in debug mode

### How to run

```bash
# Simulator (debug mode):
flutter test integration_test/feed_performance_test.dart -d <device-id>

# Real device, profile mode (most accurate):
flutter test integration_test/feed_performance_test.dart --profile -d <device-id>
```

---

## Future Testing Opportunities

### A. Profile-mode baseline run

Run the same 4 scenarios with `--profile` on a real device to get production-representative numbers. The current debug-mode data is 3-5x slower than real-world. Profile-mode baselines would let us tighten thresholds significantly (e.g. avg < 4ms for scroll, avg < 8ms for compose).

### B. Feed with 50+ cards (stress test)

Current test uses 20 cards. A stress variant with 50-100 cards would test whether `SingleChildScrollView` + `Column` starts to degrade, or whether we need to switch to `ListView.builder` for lazy rendering. Specifically:

- Initial mount time with 100 thread cards
- Scroll jank with deep content (all 100 cards are built, not lazily)
- Memory footprint growth

### C. Thread card with 50+ messages

Current threads have 3-8 messages (only 6 shown expanded). Test with a thread containing 50+ messages to verify the "View N earlier messages" truncation keeps expanded view cheap, and that the `_expandedMessages` getter (sublist of last 6) doesn't accidentally trigger full-list iteration.

### D. Rapid expand/collapse toggling

Tap the same card 10-20 times rapidly to stress test `AnimationController` disposal and re-creation. The `_startBubbleAnimation` method disposes and recreates `_bubbleController` on each expand — verify no animation controller leaks or frame drops during rapid toggling.

### E. Quote reply chain rebuild cost

Set `activeQuoteMessageIds` for multiple cards simultaneously, then toggle quotes on/off. Each quote change triggers a rebuild of the `QuotePreviewBar` + `ExpandedComposeInput` footer. Measure whether quote state changes are O(1) or accidentally rebuild the entire card.

### F. Keyboard show/dismiss impact

Currently compose input test focuses the text field but doesn't measure the keyboard animation impact. On a real device, keyboard show/dismiss triggers a layout resize of the entire screen. Test:

- Tap compose field → keyboard appears → measure layout frames
- Tap outside → keyboard dismisses → measure layout frames
- Verify no dropped frames during the resize

### G. FeedWired integration test (with real data)

The current test pumps `FeedScreen` directly with synthetic data. A heavier variant could use `FeedWired` with real (or mocked) repositories to test the full data flow:

- `loadFeed()` use case execution time
- Stream listener setup/teardown cost
- `_refreshFeed()` rebuild cost when a new message arrives mid-scroll

### H. Memory leak detection

Run a loop of: pump feed → scroll → expand/collapse all cards → dispose → re-pump. After N iterations, check that widget count and render object count haven't grown. Catches leaks in `AnimationController` disposal, `StreamSubscription` cleanup, or `TextEditingController` lifecycle.

### I. Dark/light theme switching

The feed uses `AppColors` extensively with alpha blending and gradients. Theme switching (if added) could trigger expensive repaint of all cards. Measure frame cost of a theme change with 20 cards on screen.
