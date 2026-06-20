# TDD Plan — Enable iOS edge-swipe-back on the 1:1 conversation screen

**Status:** PLAN ONLY (no code changes yet)
**Date:** 2026-06-19
**Decision:** Option A — match group chat (push 1:1 via `MaterialPageRoute`).

---

## 1. Problem & root cause (verified)

On iOS, swiping left→right from the screen edge pops back to the previous screen
(Orbit / Feed) when you are inside a **group** chat, but the same gesture does
**nothing** inside a **1:1** chat.

Root cause is purely the **route type at the push sites**:

| | Group chat (`GroupConversationWired`) | 1:1 chat (`ConversationWired`) |
|---|---|---|
| Route | stock `MaterialPageRoute` | `buildConversationSlideUpRoute` → `PageRouteBuilder` |
| iOS edge-swipe-back | **YES** (Flutter supplies the Cupertino back gesture for `MaterialPageRoute` on iOS) | **NO** (`PageRouteBuilder` with a custom slide-up+fade transition does not register the back gesture) |

- The 1:1 route helper is `lib/features/conversation/presentation/navigation/conversation_route_transition.dart:7-34` — a `PageRouteBuilder<T>` with a 420 ms slide-up + fade.
- Confirmed **not** a `PopScope` difference: the two upload-guard `PopScope` blocks are byte-equivalent (`conversation_wired.dart:3949-3954` ≡ `group_conversation_wired.dart:4768-4773`).
- Confirmed **no** global override re-adds it: `app_theme.dart` sets no `pageTransitionsTheme`/`platform`, so Flutter's per-platform default applies.
- The app has **no** swipe-back package in `pubspec.yaml`.

Full root-cause report is the prior investigation in this session.

### Why "match group chat" (Option A)

You cannot keep Flutter's free iOS edge-swipe-back **and** the bespoke slide-up at
the same time using SDK-only public API — the back gesture lives inside the same
`buildTransitions` that owns the transition. Of the three options (A: MaterialPageRoute,
B: hand-rolled edge gesture, C: add a package), **A** was chosen: lowest risk, exact
behavioral parity with groups, and UX-coherent (an iOS slide-in-from-right pairs
naturally with a left-edge-swipe-back). The trade-off accepted: the 1:1 enter
animation changes from slide-up to slide-from-right (i.e. it now animates like the
group chat).

---

## 2. The fix (single chokepoint)

One file, one route-type swap. This fixes **all 10 call sites** at once.

`lib/features/conversation/presentation/navigation/conversation_route_transition.dart`:

```dart
import 'package:flutter/material.dart';

/// Builds the route used when entering a 1:1 conversation.
///
/// Uses [MaterialPageRoute] so that on iOS the conversation gets the platform
/// edge-swipe-back gesture for free — identical to the group conversation screen.
/// (Previously a PageRouteBuilder slide-up, which silently dropped swipe-back.)
Route<T> buildConversationRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return MaterialPageRoute<T>(
    settings: settings,
    builder: builder,
  );
}
```

### Rename (recommended, mechanical)

`buildConversationSlideUpRoute` becomes a misnomer (no longer slides up). Rename to
`buildConversationRoute` and update the **10 call sites** + import-free references:

- `lib/features/orbit/presentation/screens/orbit_wired.dart:1690, 1761, 1813, 1862`
- `lib/features/posts/presentation/screens/posts_wired.dart:990`
- `lib/features/feed/presentation/screens/feed_wired.dart:1431, 1468, 1880`
- `lib/main.dart:3199, 3963`

(If you prefer a zero-blast-radius diff, keep the old name; the behavior fix is
identical. The rename is hygiene only.)

> **Out of scope:** the sibling slide-up helpers (`feed_route_transition.dart`,
> `orbit_route_transition.dart`, `settings_route_transition.dart`,
> `startup_route_transition.dart`) share the same `PageRouteBuilder` pattern and the
> same no-swipe-back trait. They are **not** touched — those screens are tab roots /
> replacement routes where edge-swipe-back is not the expected gesture. This plan is
> 1:1-conversation only.

---

## 3. Invariants (must hold after the fix)

- **INV-1** — On iOS, a left-edge swipe on the 1:1 conversation route pops back to the
  previous route.
- **INV-2** — Parity: the 1:1 swipe-back behaves identically to the group swipe-back
  (same route class, same gesture).
- **INV-3** — The active-upload guard still wins: while a `PopScope(canPop: false)`
  is registered (relay upload in flight), the edge-swipe is **suppressed** — the
  gesture must not bypass the guard. (Flutter disables the pop gesture when
  `route.popDisposition == doNotPop`; this test locks that we inherit it.)
- **INV-4** — `RouteSettings` (name/arguments) is still forwarded (analytics / named
  routes unaffected).
- **INV-5** — RTL parity: under an RTL locale (`ar`), the back gesture lives on the
  **right** edge (Flutter flips it via `Directionality`) and still pops. No code work
  — assertion only.
- **INV-6** — Android unchanged: neither chat has an edge-swipe on Android by default;
  both rely on the system back. The fix is iOS-specific and must not regress Android.

---

## 4. TDD sequence

Strict RED → GREEN. Author every test **before** the one-line fix and watch it fail
for the documented reason, then apply the fix and watch it pass.

### Phase 0 — Baseline RED (prove the bug at the route layer)

New host test file:
`test/features/conversation/presentation/navigation/conversation_route_transition_test.dart`

**T0.1 — route-type lock (deterministic RED→GREEN anchor, no gesture sim):**
```dart
test('1:1 conversation route is a MaterialPageRoute (iOS edge-swipe-back capable)', () {
  final route = buildConversationRoute<void>(builder: (_) => const SizedBox());
  expect(route, isA<MaterialPageRoute>());   // RED today (PageRouteBuilder)
});
```

**T0.2 — settings forwarded (INV-4):**
```dart
test('forwards RouteSettings', () {
  final route = buildConversationRoute<void>(
    builder: (_) => const SizedBox(),
    settings: const RouteSettings(name: 'conversation'),
  );
  expect(route.settings.name, 'conversation');
});
```

### Phase 1 — Behavioral host test (RED→GREEN, gesture-driven)

Same file (uses `flutter_test`'s gesture arena with an iOS platform override).

**T1.1 — left-edge swipe pops the 1:1 route (INV-1):**
```dart
testWidgets('iOS left-edge swipe pops the 1:1 conversation back to the previous screen', (tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);

  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: nav,
    home: const Scaffold(body: Center(child: Text('PREVIOUS'))),
  ));

  nav.currentState!.push(buildConversationRoute<void>(
    builder: (_) => const Scaffold(body: Center(child: Text('CHAT'))),
  ));
  await tester.pumpAndSettle();
  expect(find.text('CHAT'), findsOneWidget);
  expect(find.text('PREVIOUS'), findsNothing);

  // iOS back gesture: drag from within the left edge zone, across the screen.
  final gesture = await tester.startGesture(const Offset(5, 300));
  await gesture.moveBy(const Offset(600, 0));   // well past mid-width
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();

  expect(find.text('PREVIOUS'), findsOneWidget);  // popped (RED today: stays CHAT)
  expect(find.text('CHAT'), findsNothing);
});
```

**T1.2 — upload guard suppresses the swipe (INV-3):**
```dart
testWidgets('edge-swipe is suppressed while a PopScope blocks pop (active-upload guard)', (tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);

  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: nav,
    home: const Scaffold(body: Center(child: Text('PREVIOUS'))),
  ));
  nav.currentState!.push(buildConversationRoute<void>(
    builder: (_) => const PopScope(canPop: false, child: Scaffold(body: Center(child: Text('CHAT')))),
  ));
  await tester.pumpAndSettle();

  final gesture = await tester.startGesture(const Offset(5, 300));
  await gesture.moveBy(const Offset(600, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();

  expect(find.text('CHAT'), findsOneWidget);       // guard held — no pop
  expect(find.text('PREVIOUS'), findsNothing);
});
```

> **Known risk (T1.x):** driving the Cupertino `_CupertinoBackGestureDetector` from a
> headless `flutter test` binding can be sensitive to drag distance/velocity. Flutter's
> own `cupertino/route_test.dart` does exactly this pattern, so it is viable, but if
> T1.1 proves flaky, add fling velocity (`tester.flingFrom(const Offset(5,300), const
> Offset(600,0), 1000)`) and/or intermediate `pump`s. **The deterministic guarantee is
> T0.1 (route type); the authoritative behavioral guarantee is the Phase 3 device/sim
> proof.** Do not let T1.x flakiness block the fix — fall back to T0.1 + the sim proof.

### Phase 2 — Apply the fix + host gate

1. Apply the §2 change (and the rename).
2. Confirm T0.1/T0.2/T1.1/T1.2 flip RED→GREEN.
3. Regression sweep — the conversation/orbit/feed/posts wired suites that own the
   push sites must stay green:
   ```bash
   flutter test \
     test/features/conversation \
     test/features/orbit/presentation/screens/orbit_wired_test.dart \
     test/features/feed/presentation/screens/feed_wired_test.dart \
     test/features/posts
   flutter analyze   # 0 new issues
   ```
4. Register the new host file in `scripts/run_test_gates.sh` (host array for the
   conversation/1to1 pool) so it runs in CI.

### Phase 3 — Sim proof (the "sim skill" deliverable)

This is where the real device gap is closed. The iOS edge-swipe is platform-native;
the host test runs against a *platform override* on the host gesture arena, whereas the
simulator exercises the **real iOS binding, real viewport/DPR, real gesture timing** —
the exact host↔device gap the proof-test convention exists for (see the header of
`integration_test/group_conversation_polish_proof_test.dart`, the template here).

New device proof file:
`integration_test/conversation_swipe_back_proof_test.dart`

```dart
/// Real-device proof: the 1:1 conversation screen supports the iOS edge-swipe-back,
/// at parity with the group conversation screen. Renders the REAL ConversationScreen
/// pushed via the production `buildConversationRoute` onto a real navigation stack on
/// a booted simulator, then performs a real left-edge drag and asserts the pop.
@Tags(['device'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
// + the real ConversationScreen (lib/.../screens/conversation_screen.dart) and the
//   minimal models it needs, mirroring how group_conversation_polish_proof builds
//   GroupConversationScreen with in-memory fixtures.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1:1 conversation: real iOS left-edge swipe pops to the previous screen', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Center(child: Text('ORBIT'))),   // stand-in "previous" screen
    ));
    nav.currentState!.push(buildConversationRoute<void>(
      builder: (_) => /* real ConversationScreen with in-memory fixture messages */,
    ));
    await tester.pumpAndSettle();
    expect(find.text('ORBIT'), findsNothing);

    final gesture = await tester.startGesture(const Offset(6, 320));
    for (var dx = 0; dx < 12; dx++) { await gesture.moveBy(const Offset(40, 0)); await tester.pump(); }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('ORBIT'), findsOneWidget);   // back on the previous screen
  });

  testWidgets('parity: group conversation route pops the same way (control)', (tester) async {
    // Same flow but push via MaterialPageRoute (what groups use) → identical pop.
    // Locks INV-2 so a future regression to the 1:1 helper is caught as a divergence.
  });

  testWidgets('RTL (ar): the back gesture lives on the right edge and still pops', (tester) async {
    // Wrap in Directionality.rtl / Locale('ar'); start the drag from the RIGHT edge. (INV-5)
  });
}
```

**Harness integration (do all three):**

1. **Register for discovery** in `scripts/check_reliability_simulation_discovery.sh`:
   add a `record "1to1" "integration_test/conversation_swipe_back_proof_test.dart"
   "test" "1:1 edge-swipe-back navigation proof"` line alongside the other `1to1`
   `record` entries (cluster near lines 255-271), and add the path to the
   classification `case` list near line 315 (where `group_conversation_polish_proof_test.dart`
   is listed) so it classifies as a device proof, not an unclassified file.
2. **Confirm it lists** under the sim skill's 1:1 category:
   ```bash
   ./scripts/run_test_gates.sh reliability-sim 1to1 --list   # new proof appears
   "${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
   ```
3. **Run it on a booted simulator** via the sim skill (single device is enough — this
   is a local-navigation proof, not a two-party network scenario):
   ```bash
   "${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1
   ```
   Capture the green run as the device evidence (the `group_conversation_polish_proof`
   was validated the same way: iPhone 16e sim).

### Phase 4 — Acceptance

- [ ] T0.1/T0.2 GREEN (route is `MaterialPageRoute`, settings forwarded).
- [ ] T1.1/T1.2 GREEN on host (or documented fallback to sim proof if gesture-arena flaky).
- [ ] `flutter analyze` — 0 new issues.
- [ ] Conversation/orbit/feed/posts wired suites green (no push-site regression).
- [ ] New host file added to `scripts/run_test_gates.sh`.
- [ ] New `integration_test/conversation_swipe_back_proof_test.dart` created, registered
      in `check_reliability_simulation_discovery.sh` under `1to1`, and appears in
      `run_test_gates.sh reliability-sim 1to1 --list`.
- [ ] Sim proof GREEN on a booted iOS simulator (1:1 pop, group-parity control, RTL).
- [ ] Manual sanity on device: deep-link-opened 1:1 (`main.dart:3199`, after
      `popUntil(isFirst)`) swipes back to home as expected; PopScope upload guard still
      blocks both the back button and the swipe.
- [ ] `graphify update .` after code changes (keep the arch graph current).

---

## 5. Edge cases & notes

- **Deep-link path** (`main.dart:3196-3201`) does `popUntil((r) => r.isFirst)` before
  pushing the 1:1 route; after the fix, swiping back from a deep-link-opened 1:1 pops to
  the first route (home). Expected — call it out in manual sanity.
- **`_openConversationForContact`** (`main.dart:~3963`) is the same helper — covered by
  the single change.
- **RTL** (Arabic): Flutter flips the back-gesture edge to the right automatically via
  `Directionality`. No code; INV-5 asserts it. Groups already behave this way (same route
  type), so this is parity, not new behavior.
- **No new dependency, no migration, no l10n, no Go/bridge change.** Dart-presentation-only.
- **Animation change is intentional and accepted** (slide-up → slide-from-right). If a
  reviewer flags the lost slide-up, that is the documented Option-A trade-off, not a bug.
```
