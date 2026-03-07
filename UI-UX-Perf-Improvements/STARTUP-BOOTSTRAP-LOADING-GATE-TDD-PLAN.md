# Startup Bootstrap Loading Gate TDD Plan

## Goal

Implement a startup-only loading gate that hides partially built app surfaces
during cold launch and hot restart.

The target outcome is:
- the app shows one intentional full-screen bootstrap surface while startup
  routing is unresolved
- Feed / Orbit / bottom nav do not peek through during startup replacement
- once the destination route is known, the app hands off cleanly into
  Feed, first-time experience, or onboarding
- screen-level skeletons still handle post-route data hydration

This plan is for the startup/bootstrap UX proposal only. It is adjacent to
`PERF-02`, but it is not a reopen of Feed or Orbit loading behavior.

---

## Current Repo State

Confirmed current behavior:
- [startup_router.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/startup_router.dart)
  renders a basic lock icon, spinner, and `Loading...` text while startup
  routing runs.
- The same file uses `MaterialPageRoute` plus `pushReplacement` for startup
  handoff into Feed, first-time experience, and onboarding.
- [identity_loading_card.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/widgets/identity_loading_card.dart)
  already provides a cheap opaque loading surface and is visually closer to the
  desired bootstrap experience than the current lock screen.
- [startup_router_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/screens/startup_router_test.dart)
  currently locks the legacy startup UI contract by asserting the plain spinner
  plus `Loading...`.

Likely cause of the odd launch screenshot:
- the old startup route remains visible while the replacement route animates in
- Feed shell chrome can appear before the startup surface is fully gone
- the resulting composition looks like multiple unrelated states are on screen
  at once

---

## Product Decision

Use a dedicated startup loading gate, not a global spinner.

Why:
- skeletons are still the right choice once the user is already inside a screen
- startup is different because the app has not committed to a destination yet
- showing half of Feed plus half of the startup shell reads as broken

Recommended experience:
- full-screen opaque bootstrap surface
- centered loading card or branded panel
- short, stage-based copy such as:
  - `Preparing your space...`
  - `Opening Feed...`
  - `Opening setup...`
  - `Opening onboarding...`
- no slide-up route transition during startup replacement
- optional short fade only

Non-goals:
- do not wait for Feed data, Orbit data, or P2P startup to complete before
  routing
- do not introduce shimmer
- do not redesign the main app screens

---

## Architecture Recommendation

Prefer this implementation shape:

1. Add a dedicated startup widget, for example:
   - `lib/features/identity/presentation/widgets/startup_loading_gate.dart`

2. Keep `StartupRouter` as the startup decision owner:
   - track a startup stage enum or string
   - render the new startup gate while unresolved
   - keep error and retry handling inside `StartupRouter`

3. Replace startup `MaterialPageRoute` replacements with a startup-specific
   route helper, for example:
   - `lib/features/identity/presentation/navigation/startup_route_transition.dart`

4. Use an opaque no-slide handoff:
   - best default: short fade replacement
   - acceptable fallback: zero-duration replacement

5. Keep existing performance behavior:
   - `decideStartupRoute(...)` still decides early
   - P2P startup remains deferred until after route push
   - Feed and Orbit still own their own loading placeholders after handoff

Why this shape:
- smallest change to existing startup orchestration
- avoids reopening Feed / Orbit navigation stacks
- makes the transition contract testable in isolation

---

## Scope

In scope:
- startup-only loading gate UI
- startup stage copy
- startup replacement transition cleanup
- startup widget and router regression tests
- QA for cold launch and hot restart

Out of scope:
- waiting for target data hydration before route push
- changing Feed skeleton UI
- changing Orbit skeleton UI
- changing identity generation / restore loading flows beyond optional visual
  reuse

---

## Agent Topology

Use up to 3 agents.

Parallel start:
- Agent 1: startup loading gate widget and visual contract
- Agent 2: startup router staging and replacement transition

Sequenced after both:
- Agent 3: integration, regression alignment, and QA coverage

Why this split:
- Agent 1 can work entirely in widget/UI territory
- Agent 2 can work in routing/state territory without blocking on final visual
  polish
- Agent 3 resolves test overlap and proves the full launch contract end-to-end

---

## Shared Rules

All agents must follow these rules:

1. Start with RED tests only. No production edits before a failing test exists.
2. Do not hide startup failures behind an infinite spinner. Error and retry
   must remain reachable.
3. Do not wait for Feed content, Orbit content, or P2P completion before the
   route handoff.
4. Do not expose bottom nav, Feed cards, Orbit rows, or onboarding chrome while
   startup is still unresolved.
5. Do not add blur, shimmer, or heavy animated backgrounds to the startup gate.
6. Keep the dark mknoon visual language and existing theme tokens.

---

## Proposed File Inventory

Primary implementation files:
- [startup_router.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/startup_router.dart)
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/widgets/startup_loading_gate.dart`
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/navigation/startup_route_transition.dart`

Primary test files:
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/widgets/startup_loading_gate_test.dart`
- [startup_router_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/screens/startup_router_test.dart)
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/navigation/startup_route_transition_test.dart`

Reference files:
- [identity_loading_card.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/widgets/identity_loading_card.dart)
- [feed_screen_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_screen_test.dart)
- [orbit_screen_loading_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_screen_loading_test.dart)

---

## Agent 1

### Lane

`startup/a-loading-gate`

### Goal

Create the startup loading surface and lock its visual contract with isolated
widget tests.

### Ownership

Primary files:
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/widgets/startup_loading_gate.dart`
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/widgets/startup_loading_gate_test.dart`

Secondary references:
- [identity_loading_card.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/widgets/identity_loading_card.dart)
- [app_colors.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/theme/app_colors.dart)

### RED Tests To Add First

Create `test/features/identity/presentation/widgets/startup_loading_gate_test.dart`
with these exact test names:

- `renders opaque bootstrap surface with centered progress affordance`
- `shows preparing copy for checking identity stage`
- `shows opening feed copy for feed handoff stage`
- `shows opening setup copy for first time handoff stage`
- `shows opening onboarding copy for onboarding handoff stage`

Expected assertions:
- one `CircularProgressIndicator`
- stage title text exists
- stage subtitle text exists
- the widget fills the screen with an opaque dark surface
- no legacy lock icon

### GREEN Implementation Target

Implement the smallest production change set necessary:

- create `StartupLoadingGate`
- use existing `AppColors` tokens
- render a centered card or panel with:
  - progress indicator
  - title
  - subtitle
- keep visuals static and cheap
- make stage text deterministic via a small private mapping helper

Recommended stage IDs:
- `checking_identity`
- `opening_feed`
- `opening_setup`
- `opening_onboarding`

### REFACTOR Constraints

- if useful, share styling ideas with `IdentityLoadingCard`, but do not couple
  bootstrap text or state to identity-generation flows
- do not introduce repository dependencies into the widget
- keep copy centralized so Agent 2 can drive it cleanly from `StartupRouter`

### Lane Verification

Run:

```bash
flutter test test/features/identity/presentation/widgets/startup_loading_gate_test.dart
```

### Handoff Contract

Agent 1 must provide:
- final widget name
- final supported stage IDs
- any stable keys added for test lookup

---

## Agent 2

### Lane

`startup/b-router-handoff`

### Goal

Replace the legacy startup lock screen and slide-prone replacement flow with a
stage-aware bootstrap gate plus a startup-specific handoff transition.

### Ownership

Primary files:
- [startup_router.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/startup_router.dart)
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/navigation/startup_route_transition.dart`
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/navigation/startup_route_transition_test.dart`
- [startup_router_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/screens/startup_router_test.dart)

### RED Tests To Add First

Add or update tests in `startup_router_test.dart` with these exact test names:

- `shows bootstrap loading gate while startup decision is pending`
- `keeps bootstrap gate visible until startup route is committed`
- `routes to feed after showing opening feed stage`
- `routes to first time experience after showing opening setup stage`
- `routes to onboarding after showing opening onboarding stage`
- `does not wait for p2p startup before route replacement`
- `preserves retry flow after startup failure`

Create `startup_route_transition_test.dart` with these exact test names:

- `builds an opaque startup replacement route`
- `uses fade only without slide translation`
- `uses a short forward transition suitable for startup handoff`

Expected assertions:
- before route resolution completes, only the startup gate is visible
- no `Loading...` legacy text remains
- no lock icon remains
- the target screen appears after routing
- P2P start is still fire-and-forget after navigation
- error screen still appears when repositories throw

Test harness additions likely needed:
- delayed identity repository or delayed contact repository
- `NavigatorObserver` to capture replacement timing
- bounded pumps instead of `pumpAndSettle` for pending-startup assertions

### GREEN Implementation Target

Implement the smallest production change set necessary:

- replace legacy startup loading body with `StartupLoadingGate`
- add `_startupStage` state to `StartupRouter`
- set stage transitions deliberately:
  - startup begins -> `checking_identity`
  - route decided to Feed -> `opening_feed`
  - route decided to FTE -> `opening_setup`
  - route decided to onboarding -> `opening_onboarding`
- replace `MaterialPageRoute` startup replacements with a startup-specific route
  helper
- use fade-only or zero-motion replacement

Important contract:
- route handoff should happen as soon as destination shell is known
- no additional awaits for Feed data, Orbit data, or P2P startup

### REFACTOR Constraints

- preserve existing ML-KEM migration behavior
- preserve deferred P2P startup behavior
- keep retry/error path in `StartupRouter`
- do not leak startup-specific transition logic into Feed/Orbit/conversation
  route helpers

### Lane Verification

Run:

```bash
flutter test test/features/identity/presentation/navigation/startup_route_transition_test.dart
flutter test test/features/identity/presentation/screens/startup_router_test.dart
```

### Handoff Contract

Agent 2 must provide:
- final transition helper API
- whether startup handoff uses short fade or zero-duration replacement
- final router stage names

---

## Agent 3

### Lane

`startup/c-integration-and-qa`

### Goal

Integrate the new gate and transition contract cleanly with the existing app
startup flow, then prove the user-visible launch behavior with focused
regression coverage and QA steps.

### Ownership

Primary files:
- [startup_router_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/screens/startup_router_test.dart)
- `/Users/I560101/Project-Sat/mknoon-2/flutter_app/UI-UX-Perf-Improvements/execution-log.md` if the team wants the change logged
- this plan document if final notes are captured

Secondary references:
- [feed_screen_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/screens/feed_screen_test.dart)
- [orbit_screen_loading_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_screen_loading_test.dart)
- [identity_loading_card_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/widgets/identity_loading_card_test.dart)

### RED Tests To Add First

Add integration-oriented startup router cases with these exact test names:

- `cold launch shows only bootstrap gate before feed route appears`
- `hot restart style delayed startup does not expose feed chrome before handoff`
- `bootstrap gate disappears once feed route is visible`
- `bootstrap gate does not block existing feed loading placeholders after handoff`

Expected assertions:
- before commit: no Feed bottom nav, no Feed shell text, no onboarding shell
- after commit: `FeedWired`, `FirstTimeExperienceWired`, or
  `IdentityChoiceWired` appears and bootstrap gate is gone
- Feed can still show its own loading placeholders once startup handoff is
  complete

If the last test is too integration-heavy for widget scope, Agent 3 may replace
it with:
- a targeted regression run of Feed loading placeholder tests
- a manual QA checklist item that explicitly verifies startup gate -> Feed
  skeleton handoff

### GREEN Integration Target

Finalize the merged behavior:

- align route tests with the final stage copy
- remove or update any tests that still assert `Loading...`
- ensure startup error + retry still work
- verify that launch-only loading stays distinct from screen-level loading

### REFACTOR Constraints

- do not expand scope into Feed redesign
- do not change Orbit code for this task
- keep the startup gate limited to bootstrap and restart entry paths

### Lane Verification

Run:

```bash
flutter test test/features/identity/presentation/widgets/startup_loading_gate_test.dart
flutter test test/features/identity/presentation/navigation/startup_route_transition_test.dart
flutter test test/features/identity/presentation/screens/startup_router_test.dart
flutter test test/features/feed/presentation/screens/feed_screen_test.dart
flutter analyze lib/features/identity/presentation/startup_router.dart lib/features/identity/presentation/widgets/startup_loading_gate.dart lib/features/identity/presentation/navigation/startup_route_transition.dart test/features/identity/presentation/widgets/startup_loading_gate_test.dart test/features/identity/presentation/navigation/startup_route_transition_test.dart test/features/identity/presentation/screens/startup_router_test.dart
```

### Manual QA Script

1. Launch the app from a terminated state into a seeded Feed account.
2. Verify the first visible surface is the bootstrap gate only.
3. Confirm Feed chrome does not peek in from the side or underneath.
4. Confirm the handoff is fade-only or visually still, not a noticeable slide.
5. Confirm Feed can still show its own placeholders after handoff if data is
   delayed.
6. Hot restart in debug on the same seeded account.
7. Confirm the bootstrap gate appears again and no partial old/new screen mix is
   visible.
8. Repeat with a no-identity account and an identity-without-contacts account.
9. Force a startup repository failure and confirm retry remains usable.

---

## Merge Order

Recommended merge order:

1. Agent 1 merges first or in parallel with Agent 2.
2. Agent 2 rebases on Agent 1 if stage IDs or widget API changed.
3. Agent 3 rebases on both, resolves test expectations, and runs the final
   acceptance suite.

Conflict hotspots:
- `startup_router_test.dart`
- any shared stage string constants if both Agent 1 and Agent 2 define them

Low-conflict rule:
- Agent 1 should avoid editing `StartupRouter`
- Agent 2 should avoid visual churn inside the gate widget after Agent 1 lands

---

## Definition Of Done

The work is done when all of the following are true:

- startup no longer renders the legacy lock icon plus `Loading...` shell
- startup shows one branded opaque gate while route decision is unresolved
- startup handoff no longer exposes a mixed old/new screen composition
- Feed, first-time experience, and onboarding still route correctly
- startup error and retry still work
- P2P startup still begins after navigation rather than blocking it
- existing Feed loading placeholders still appear only after startup handoff
- targeted tests and analyze pass

---

## Risks And Watchouts

- If the gate is removed only after full Feed hydration, startup will feel
  slower and the app will regress on perceived responsiveness.
- If startup uses a slide transition again, the same mixed-state visual problem
  can reappear.
- If the new gate shares too much code with identity-generation loading, future
  copy changes can couple unrelated flows.
- If tests only assert final navigation and never assert the pending state, the
  half-built-screen bug can return unnoticed.

---

## Recommended First RED Sequence

If one engineer executes this plan alone instead of parallel agents, use this
exact order:

1. Add `startup_loading_gate_test.dart` and make all 5 gate widget tests fail.
2. Add `startup_route_transition_test.dart` and make the transition tests fail.
3. Update `startup_router_test.dart` to fail on the new bootstrap expectations.
4. Implement `StartupLoadingGate`.
5. Implement the startup replacement route helper.
6. Update `StartupRouter` to drive stage-based gate UI and new route handoff.
7. Re-run targeted tests.
8. Re-run Feed loading tests as a regression check.

---

## Acceptance Commands

```bash
flutter test test/features/identity/presentation/widgets/startup_loading_gate_test.dart
flutter test test/features/identity/presentation/navigation/startup_route_transition_test.dart
flutter test test/features/identity/presentation/screens/startup_router_test.dart
flutter test test/features/feed/presentation/screens/feed_screen_test.dart
flutter analyze lib/features/identity/presentation/startup_router.dart lib/features/identity/presentation/widgets/startup_loading_gate.dart lib/features/identity/presentation/navigation/startup_route_transition.dart test/features/identity/presentation/widgets/startup_loading_gate_test.dart test/features/identity/presentation/navigation/startup_route_transition_test.dart test/features/identity/presentation/screens/startup_router_test.dart
```

Optional broader regression:

```bash
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart
```
