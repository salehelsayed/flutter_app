# UI & Rendering Performance Analysis

## Summary

6 candidates remain after correcting stale findings: **0 confirmed HIGH**, **3 MEDIUM**, **3 LOW**. Several earlier P0/P1 items were not supported by the current code and should be treated as false positives unless new profile traces say otherwise.

---

## HIGH SEVERITY

### No confirmed HIGH-severity UI issue from current code inspection

- `OrbitWired` already disposes controllers/notifiers/subscriptions
- `FeedCard` does **not** rebuild its full subtree every animation frame; it already uses `AnimatedBuilder.child`
- The earlier “nested ValueListenableBuilder” concern in `FeedScreen` was overstated
- Orbit header position math is **not** being recomputed on every collapse animation tick in the way the previous report described

---

## MEDIUM SEVERITY

### 1. Orbit painters still do repeated dash/arc math on paint
**Files:** `lib/features/orbit/presentation/widgets/orbital_ring_painter.dart`, `lib/features/orbit/presentation/widgets/overflow_badge.dart`

- Both painters recalculate dashed arcs in `paint()`
- `shouldRepaint` is `false`, so rebuild churn is low, but paint work can still matter on lower-end devices
- This is a **profile-gated** candidate, not a confirmed regression

**Fix:** Only optimize if trace data shows these painters on the hot path. Cache dash geometry by size if needed.

---

### 2. FeedWired init churn is real but small
**File:** `lib/features/feed/presentation/screens/feed_wired.dart`

- `_loadIdentity()`, `_loadQualityPreference()`, `_loadVideoQualityPreference()`, and `_loadFeedFromDatabase()` each trigger local state updates during init
- This is a valid cleanup candidate, but the impact is smaller than earlier claimed

**Fix:** Batch only if the route shows measurable startup churn in profile mode.

---

### 3. ConversationWired keeps several active subscriptions
**File:** `lib/features/conversation/presentation/screens/conversation_wired.dart`

- The screen owns multiple subscriptions
- Current code already scopes/cancels them responsibly, and recorder subscriptions only exist while recording
- Pause/resume lifecycle complexity should not be added without evidence

**Fix:** Profile first. Only refactor subscription behavior if traces show off-screen churn or route-specific jank.

---

## LOW SEVERITY

### 4. OverflowBadge uses a hardcoded `3.14159`
**File:** `lib/features/orbit/presentation/widgets/overflow_badge.dart`

- This is readability debt, not a meaningful performance issue

**Fix:** Replace with `dart:math.pi` only as cleanup.

### 5. AmplitudeBars allocates a new `Paint` during paint
**File:** `lib/features/conversation/presentation/widgets/amplitude_bars.dart`

- This is a small optimization candidate
- The earlier “voice recording stutter” conclusion was not supported strongly enough by current code inspection alone

**Fix:** Only clean up if touching the widget anyway.

### 6. FeedStore list allocations are minor
**File:** `lib/features/feed/application/feed_store.dart`

- There are small list/allocation opportunities
- This is not a current top-priority performance task

**Fix:** Ignore unless profiling points there.

---

## Findings Not Supported by Current Code

- **`OrbitWired` missing `dispose()`** — stale; current code already disposes resources
- **`FeedCard` full rebuild per frame** — inaccurate; `AnimatedBuilder.child` already isolates the subtree
- **`FeedScreen` nested listenables causing major waste** — not supported by the current tree
- **`OrbitalVisualization` positions recalculated every collapse tick** — overstated
- **`AmplitudeBars.shouldRepaint()` as a proven P0 stutter source** — not strong enough without traces

---

## Priority Action Plan

| Priority | Issue | Fix Effort | Impact |
|----------|-------|-----------|--------|
| **P1** | Profile Orbit painter cost on real route transitions | Low | Confirms whether dash caching is worth doing |
| **P1** | Profile FeedWired init churn before batching state updates | Low | Prevents speculative cleanup |
| **P2** | Profile ConversationWired subscription cost on background/foreground flows | Low | Guards against lifecycle overengineering |
| **P3** | Replace hardcoded `pi` literal / other micro-cleanups when nearby code changes | Low | Readability only |
