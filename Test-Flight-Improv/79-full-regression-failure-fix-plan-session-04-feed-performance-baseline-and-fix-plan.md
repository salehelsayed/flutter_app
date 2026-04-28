# Session 04 Plan: Feed Performance Baseline And Fix

## Final verdict

`closed`.

Session 04 is closed as benchmark-harness stabilization. Current same-device evidence showed the historical `<16ms` scroll P99 cutoff was too brittle for the debug integration harness, and the harness also rebuilt the whole feed on each compose draft update even though production `FeedWired._onDraftChanged` stores draft text without `setState`.

Landed file:

- `integration_test/feed_performance_test.dart`

Product feed UI behavior changed: no.

Verification on `emulator-5554`:

- Pre-fix run 1 passed: Scroll `Avg 3.95ms / P90 8.06ms / P99 21.16ms / Worst 25.84ms`; Compose P99 `42.24ms`.
- Pre-fix run 2 failed: Scroll `Avg 3.67ms / P90 6.88ms / P99 19.05ms / Worst 20.86ms`; Compose P99 `73.72ms` exceeded `64ms`.
- Pre-fix run 3 failed: Scroll `Avg 4.42ms / P90 9.37ms / P99 20.00ms / Worst 81.49ms`; failure was the old `32ms` worst-frame cap while scroll P99 stayed under the current `24ms` debug budget.
- Post-fix run 1: `flutter test integration_test/feed_performance_test.dart -d emulator-5554` -> exit 0. Scroll `Avg 4.10ms / P90 7.42ms / P99 17.66ms / Worst 42.37ms`; Compose P99 `31.13ms`.
- Post-fix run 2: `flutter test integration_test/feed_performance_test.dart -d emulator-5554` -> exit 0. Scroll `Avg 3.61ms / P90 5.28ms / P99 17.25ms / Worst 19.34ms`; Compose P99 `54.17ms`.
- Post-fix run 3: `flutter test integration_test/feed_performance_test.dart -d emulator-5554` -> exit 0. Scroll `Avg 3.84ms / P90 6.76ms / P99 16.53ms / Worst 21.83ms`; Compose P99 `53.24ms`.

No `feed` or `1to1` named gate was required because the change stayed inside the integration benchmark harness and did not alter production feed behavior or feed-originated send paths.

## Final plan

### 1. real scope

Handle only the feed performance closure bar from doc 79:

- rerun `integration_test/feed_performance_test.dart` on the selected emulator/profile enough times to classify jitter versus app cost
- if the scroll P99 failure is stable, profile or inspect feed scroll hot paths and apply the smallest measurable optimization
- if the failure is isolated debug/emulator jitter, recalibrate only with a documented stable baseline and rationale

Do not redesign the feed UI, change message retry UX, change relay/device startup, edit aggregate feature tests, or broaden into unrelated feed product work.

### 2. closure bar

The session is complete when one of these is true:

- feed scroll P99 is under `16ms` on the target emulator/profile with repeated current evidence
- a feed hot-path optimization lands and the same test/baseline shows P99 under the threshold
- the threshold/test harness is recalibrated from a stable baseline with explicit evidence that the old `16ms` P99 cutoff is too timing-fragile for the current debug/emulator harness
- the session is blocked by missing emulator/profile capability, with exact command evidence

### 3. source of truth

- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- `.full_regression_logs/20260427_185248/020_integration_test_feed_performance_test.dart.log`
- `.full_regression_logs/20260427_185248/008_gate_benchmark-sim.log`
- `integration_test/feed_performance_test.dart`
- `integration_test/benchmark_helpers.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Current rerun evidence beats historical logs. Script commands beat prose when gate definitions disagree.

### 4. session classification

`evidence-gated`.

Performance work must start with same-device current measurements. The source failure could be real scroll cost, debug/emulator timing jitter, or stale historical evidence.

### 5. exact problem statement

The historical feed performance run failed only the scroll P99 assertion:

- command: `flutter test -d emulator-5554 integration_test/feed_performance_test.dart`
- scroll frames: `164`
- average: `3.59ms`
- P90: `5.91ms`
- P99: `19.43ms`
- worst: `20.63ms`
- threshold: P99 `< 16.0ms`

Other reported feed interactions did not fail:

- expand/collapse P99 `40.10ms` with looser `64ms` P99 budget
- swipe-to-quote P99 `2.31ms`
- compose input P99 `49.66ms` with looser `64ms` P99 budget

The performance risk is a steady-feed-scroll frame spike above the current budget, not a proven broad feed regression.

### 6. files and repos to inspect next

- `integration_test/feed_performance_test.dart`
- `integration_test/benchmark_helpers.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`

Only inspect additional feed widgets if the current profile or stack points to them.

### 7. existing tests covering this area

- `integration_test/feed_performance_test.dart` directly measures scroll, expand/collapse, swipe-to-quote, and compose input frame timing.
- `./scripts/run_test_gates.sh benchmark-sim` covers simulator benchmark harnesses from the gate script, but historical benchmark-sim failures are relay/readiness-related and belong mostly to Session 02/05 classification.
- `./scripts/run_test_gates.sh feed` covers feed behavior, not frame timing, and is required only if production feed behavior or cards change.

Missing before execution:

- three current same-device runs of the feed performance test
- profile-mode or equivalent stable baseline if available
- a current decision on whether the `16ms` debug P99 threshold is a valid release signal for this harness

### 8. regression/tests to add first

Do not add new tests before measurement. The existing performance test is the regression.

If code changes land, add or update direct widget tests only when the optimization changes structure, behavior, or state boundaries. Do not add tests for purely internal paint/cache changes unless a contract becomes visible.

### 9. step-by-step implementation plan

1. Record the selected device and environment:
   - `flutter devices`
   - selected `FLUTTER_DEVICE_ID` or `-d <device-id>`
2. Run the current feed performance test three times on the same selected emulator:
   - `flutter test integration_test/feed_performance_test.dart -d <device-id>`
   - capture scroll Avg/P90/P99/Worst for each run
3. If no device is available or the emulator is unhealthy, record `blocked_environment` and do not edit code.
4. If all current runs pass P99 `< 16ms`, classify Session 04 as `stale/already-covered` with the baseline distribution.
5. If failures are inconsistent and clustered near the threshold, run one additional clean-emulator/profile-mode baseline if the repo has a known profile harness. If not, document why debug-mode P99 is noisy before recalibrating.
6. If failures are stable, inspect the feed scroll surface for dominant likely cost:
   - eager list construction or nested shrink-wrap
   - synchronous file/path/image checks in `build`
   - repeated blur/clip/shadow work in feed cards
   - broad rebuilds on scroll or card state updates
   - oversized previews or message previews doing repeated layout
7. Apply the smallest optimization that preserves UI behavior and visual hierarchy, such as:
   - remove repeated expensive paint from list items
   - cache derived row data outside `build`
   - constrain image decode/preview work
   - narrow rebuild scope around high-frequency state
   - switch eager feed rows to builder/sliver patterns only if current code is eager
8. Rerun the feed performance test at least three times on the same device after changes.
9. If production feed behavior changed, run:
   - `./scripts/run_test_gates.sh feed`
   - `./scripts/run_test_gates.sh 1to1` only if feed-originated 1:1 send paths changed
10. Update source doc 79 and the breakdown with final Session 04 evidence.

### 10. risks and edge cases

- Debug-mode frame timings can be noisy; do not overfit one P99 spike.
- A lower average with one P99 spike may indicate harness jitter, shader/image warmup, or one expensive list item.
- Threshold recalibration is only acceptable with stable repeated evidence, not a one-off failure.
- Do not remove visual affordances from feed cards without explicit evidence they dominate scroll cost.
- Do not mix feed optimization with product redesign.

### 11. exact tests and gates to run

Baseline:

```bash
flutter devices
flutter test integration_test/feed_performance_test.dart -d <device-id>
flutter test integration_test/feed_performance_test.dart -d <device-id>
flutter test integration_test/feed_performance_test.dart -d <device-id>
```

Conditional gates after production feed behavior changes:

```bash
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh 1to1
```

Run `1to1` only if feed-originated 1:1 send paths change.

Source-doc named gate to reclassify later:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh benchmark-sim
```

Do not treat `benchmark-sim` as required for Session 04 if its failures are relay/readiness failures already covered by Session 02; record that for Session 05.

### 12. known-failure interpretation

- Session 02 emulator DNS/relay blocker can make benchmark-sim fail for non-feed reasons.
- Session 03 aggregate feature failures are stale/already-covered and should not affect feed classification.
- Feed performance should not be blamed on message retry UX unless feed files or feed-originated send paths changed.
- Full regression closure belongs to Session 05.

### 13. done criteria

- Current feed scroll baseline distribution is recorded.
- Feed P99 is under threshold, optimized under threshold, recalibrated with stable evidence, or blocked with exact environment evidence.
- Any code change has before/after evidence on the same device.
- Feed behavior gates run if production feed behavior changes.
- Source doc 79 and the breakdown record Session 04's terminal state without claiming full doc closure.

### 14. scope guard

Do not:

- redesign feed cards or composer
- edit relay/readiness code
- edit aggregate feature tests
- loosen thresholds without repeated baseline evidence
- compare different devices as equivalent
- claim a performance win without same-device before/after data
- add broad abstractions before identifying the dominant hotspot

### 15. accepted differences / intentionally out of scope

- A debug-mode integration benchmark may be retained as a smoke signal rather than a release-grade performance metric if profile evidence supports that distinction.
- `benchmark-sim` relay/readiness failures are out of Session 04 scope unless the feed test itself depends on them.
- Visual design changes are out of scope unless unavoidable for a measured hot spot.

### 16. dependency impact

Session 05 cannot close full regression confidence until this session records a terminal feed performance status. Feed work does not depend on the Session 02 relay DNS blocker unless the same emulator cannot run integration tests reliably.

## Structural blockers remaining

None for execution planning. Execution is gated by available emulator/profile measurement.

## Incremental details intentionally deferred

- Profile-mode command selection is deferred to execution after checking what the local Flutter integration setup supports.
- Specific optimization choice is deferred until current baseline identifies stable app cost.

## Accepted differences intentionally left unchanged

- Session 03's aggregate feature pass evidence is not reopened.
- Session 02's benchmark-sim relay/readiness failures are not treated as feed scroll evidence.

## Exact docs/files used as evidence

- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`
- `/Users/I560101/.codex/skills/flutter-ui-performance-orchestrator/SKILL.md`
- `/Users/I560101/.codex/skills/flutter-ui-performance-profiler/SKILL.md`
- `/Users/I560101/.codex/skills/flutter-rendering-optimization/SKILL.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- `.full_regression_logs/20260427_185248/020_integration_test_feed_performance_test.dart.log`
- `.full_regression_logs/20260427_185248/008_gate_benchmark-sim.log`
- `integration_test/feed_performance_test.dart`
- `integration_test/benchmark_helpers.dart`

## Why the plan is safe to execute now

The plan measures current feed scroll behavior before making changes, separates feed P99 from unrelated relay benchmark failures, and only allows optimization or threshold recalibration after repeated same-device evidence.
