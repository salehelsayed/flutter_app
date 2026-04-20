# Session 2 Plan: Badge Rendering, Semantics, and App-Facing Readiness Consumption

## Final verdict

Accepted locally with bounded fallback. Session `2` stayed inside the intended presentation seam: `ConnectionStatusIndicator` now renders the service-owned `NodeState.badgeReadinessState`, exposes the exact visible and semantics contract for `Online` versus `Online.`, and keeps the ready-state styling aligned without reopening the service owner from Session `1`.

## Final plan

### 1. Real scope

This session changes only the app-facing badge renderer and its immediate tests:

- replace relay-only `ConnectionHealth` inference with rendering based on the service-owned `NodeState.badgeReadinessState`
- render the exact visible copy contract:
  - `Offline`
  - `Connecting`
  - `Online`
  - `Online.`
- keep `Online` and `Online.` in the same green badge family
- expose explicit semantics labels so assistive technologies do not rely on punctuation alone
- keep `ConnectionStatusIndicator` a pure renderer of service-owned state
- rerun the widget suite and the minimum baseline gate coverage that exercises shared app chrome

This session does not:

- change the proof-window owner or service-owned readiness logic from Session `1`
- change routing policy, relay recovery behavior, or benchmark/event semantics
- redesign `FeedHeader`, `FirstTimeExperienceScreen`, or wider visual styling beyond the badge state mapping
- widen into benchmark/reporting work from Session `3`

### 2. Closure bar

Session `2` is good enough only if all of the following are true:

- `ConnectionStatusIndicator` no longer infers ready state from raw relay hints
- visible text matches the exact Phase 6 state contract
- semantics distinguish `Online` from `Online.` without depending on punctuation
- `Online` and `Online.` remain visually in the same green family
- the direct widget/semantics regressions pass
- `baseline` still passes because the badge is embedded in shared app chrome

### 3. Source of truth

- active source doc:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`
- active session contract:
  - `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
- regression / gate authority:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- current widget / embed seam:
  - `lib/features/p2p/presentation/widgets/connection_status_indicator.dart`
  - `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`
  - `lib/features/feed/presentation/widgets/feed_header.dart`
  - `lib/features/home/presentation/screens/first_time_experience_screen.dart`

On disagreement:

- current code and tests beat stale prose
- the Phase 6 spec fixes the visible and semantics contract
- `test-gate-definitions.md` defines named-gate execution

### 4. Session classification

`implementation-ready`

Reason:

- Session `1` already exposed the service-owned readiness state
- the renderer seam is localized and already has dedicated widget coverage
- the required follow-up gate is narrow and known up front

### 5. Exact problem statement

`ConnectionStatusIndicator` still derives readiness from relay-only transport truth:

- `healthFromState(...)` returns `online` when `relayState == 'online'` or `circuitAddresses.isNotEmpty`
- the widget only renders three states today:
  - `Offline`
  - `Connecting`
  - `Online`
- current widget tests lock that relay-only behavior in

What must improve:

- the badge must render the service-owned readiness truth from Session `1`
- the user must see plain `Online` when send and inbox are ready but relay-ready is still pending
- the user must see `Online.` when relay-ready later catches up
- semantics must speak the difference explicitly

What must stay unchanged:

- the badge remains a compact renderer embedded where it already appears
- `FeedHeader` and `FirstTimeExperienceScreen` continue to consume the same widget
- ready states remain green and non-ready states remain distinct

### 6. Files and repos to inspect next

Production:

- `lib/features/p2p/presentation/widgets/connection_status_indicator.dart`
- `lib/features/feed/presentation/widgets/feed_header.dart`
- `lib/features/home/presentation/screens/first_time_experience_screen.dart`

Direct tests:

- `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`

### 7. Existing tests covering this area

Already present:

- `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`
  - relay-only state mapping
  - widget timing event on upgrade to online

Current gaps:

- no direct test for `Online.` text
- no direct test for service-owned readiness mapping through `badgeReadinessState`
- no semantics assertion distinguishing `Online` from `Online.`
- no regression asserting the two ready states share the same green family

### 8. Regression/tests to add first

- update widget tests so `healthFromState(...)` maps from `NodeState.badgeReadinessState`
- add direct text assertions for all four visible states
- add semantics assertions for:
  - `Online` => online, send and inbox ready, relay reservation pending
  - `Online.` => online, send and inbox ready, relay reservation ready
- keep the widget timing-event assertion truthful for the green-state transition without treating relay-only readiness as the source of truth

### 9. Step-by-step implementation plan

1. Replace relay-only enum/state mapping in `connection_status_indicator.dart` with a renderer based on `NodeState.badgeReadinessState`.
2. Preserve the existing compact badge layout while adding the fourth visible label `Online.`.
3. Add explicit semantics labels for the two green states.
4. Tighten or rename the local widget enum/helper only as much as needed so the widget remains a pure renderer.
5. Update the widget tests to cover the four-state mapping, semantics, and green-family consistency.
6. Run the direct widget suite.
7. Run `baseline` to verify shared app chrome still behaves.

Stop rule:

- if the widget cannot render the Phase 6 contract cleanly without adding a second readiness owner or reworking broader app state, stop and refresh the breakdown instead of widening scope

### 10. Risks and edge cases

- delayed downgrade behavior must not hide a truthful transition away from a ready state after capability invalidation
- semantics must not read the two green states identically
- debug-only connection counts must not accidentally make `Online` and `Online.` diverge visually beyond the dot contract
- widget timing instrumentation must not become the source of truth for sendable or relay-ready state

### 11. Exact tests and gates to run

Direct tests:

- `flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`

Named gate:

- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`

### 12. Known-failure interpretation

- no known-failure exemption is required for the direct widget suite
- a `baseline` failure in badge-bearing app chrome is a real blocker unless clearly unrelated to the touched presentation seam

### 13. Done criteria

- visible badge text matches all four Phase 6 states
- semantics distinguish the two green states explicitly
- the widget consumes service-owned readiness instead of relay-only inference
- direct widget tests pass
- `baseline` passes

### 14. Scope guard

- do not reopen Session `1` service-owned readiness logic
- do not add benchmark/reporting changes
- do not widen into feed/home redesign outside this badge renderer
- do not change badge wording beyond the Phase 6 contract

### 15. Accepted differences / intentionally out of scope

- the internal helper/enum names inside the widget may change as long as the service-owned state remains authoritative
- debug-only connection counts may remain if they do not violate the visible Phase 6 contract
- timing-event naming stays as-is in this session unless a test proves the existing widget event is now misleading

### 16. Dependency impact

- Session `3` depends on this session so benchmark/device acceptance can validate the same visible contract users actually see

## Structural blockers remaining

- none

## Execution evidence

Landed files:

- `lib/features/p2p/presentation/widgets/connection_status_indicator.dart`
- `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`

Direct verification:

- `flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`

Named gate verification:

- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`

Accepted implementation notes:

- the widget now renders `Offline`, `Connecting`, `Online`, and `Online.` directly from `NodeState.badgeReadinessState`
- `Online` semantics: `online, send and inbox ready, relay reservation pending`
- `Online.` semantics: `online, send and inbox ready, relay reservation ready`
- the existing relay-only `ConnectionHealth` helper was intentionally kept as a legacy compatibility surface for Session `3` benchmark and smoke migration instead of widening this session beyond the renderer seam

## Exact docs/files used as evidence

- `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`
- `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/p2p/presentation/widgets/connection_status_indicator.dart`
- `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`
- `lib/features/feed/presentation/widgets/feed_header.dart`
- `lib/features/home/presentation/screens/first_time_experience_screen.dart`

## Why the plan is safe to implement now

- Session `1` already moved readiness truth into the service-owned state, so the widget no longer needs to infer anything from raw relay hints.
- The renderer seam is concentrated in one widget with immediate embed points and dedicated tests.
- The required regression surface is narrow enough to keep this session presentation-only while leaving benchmark/reporting work for Session `3`.
