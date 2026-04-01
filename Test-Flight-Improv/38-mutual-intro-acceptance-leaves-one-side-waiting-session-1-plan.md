# 38 - Mutual Introduction Acceptance Leaves One Side Waiting - Session 1 Plan

## Final Verdict

`implementation-ready`

Current repo evidence still leaves the escaped mutual-acceptance seam ambiguous:

- the product contract is clear that once User-B and User-C both accept the
  same introduction, both sides should converge on a completed connection
  outcome rather than a split `Connected` / `Waiting for ...` result
- current direct tests prove pieces of the handshake, but several of them still
  rely on explicit `receiveAcceptNotification(...)` injection and therefore do
  not lock the exact reported User-B/User-C asymmetry through the live path
- Session `35` already closed one narrow Orbit stale-reload race, so Session
  `1` must prove whether Report `38` is a still-open repo-local seam, a
  narrower already-covered case, or a different seam than the prior closure

## Final Plan

### Real Scope

- Add deterministic repo-local evidence for the exact reported asymmetry: after
  both participants accept the same intro, one participant reaches the
  completed connection outcome while the other still shows `Waiting for ...`
  for that same intro.
- Pin both role directions, with explicit introduced-friend/User-C coverage
  rather than only the recipient/User-B path.
- Determine whether the escaped symptom comes from missing remote-accept
  propagation, local intro persistence/status derivation, or post-status
  Orbit/Feed surface refresh.
- Add the smallest direct user-visible assertions needed so Session `2` does
  not guess between protocol/listener and surface-refresh seams.
- Refresh the report breakdown artifact if execution disproves the current
  bug narrative or narrows it materially.

### Closure Bar

Session `1` is good enough when the repo ends with one of these evidence-safe
outcomes:

- a deterministic automated repro proves the exact asymmetric User-B/User-C
  outcome and narrows it to a specific current repo-local seam
- or a deterministic automated proof shows the reported asymmetry is already
  covered or disproved under current repo truth, with the breakdown ledger
  updated honestly

In either acceptable outcome:

- introduced-side/User-C waiting behavior is asserted directly rather than
  inferred only from recipient-side tests
- both acceptance orders are addressed explicitly, or the plan records why one
  direction is sufficient to isolate the real seam
- the result distinguishes transport/listener/persistence failure from pure
  Orbit/Feed refresh failure closely enough that Session `2` can stay narrow
- existing one-sided-pending behavior remains valid and explicitly preserved

### Source Of Truth

Primary docs:

- `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-breakdown.md`
- `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`
- `UI-20-Intro-friends/intro-feature-spec.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/session-35-plan.md`
- `Test-Flight-Improv/00-INDEX.md`

Current code and direct tests beat stale prose when they disagree. Current repo
evidence already shaping this session:

- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/application/load_introductions_use_case.dart`
- `lib/features/introduction/presentation/widgets/intros_tab.dart`
- `lib/features/introduction/presentation/widgets/intro_row.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/introduction_connection_card.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/application/mutual_acceptance_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/introduction/presentation/widgets/intro_row_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

### Session Classification

- `evidence-gated`

### Exact Problem Statement

The repo currently proves that mutual acceptance can reach `mutualAccepted`,
but it does not yet pin the escaped user-visible asymmetry where one side
surfaces the completed connection while the other side still renders `Waiting
for <username>` for the same intro. Existing evidence leaves at least two
materially different explanations in play:

- one side may never process the remote accept into local intro truth
- or both accepts may be processed while Orbit and/or Feed still publish stale
  pending-state UI for one role direction

Session `1` must prove which class of seam is actually open, or prove that the
reported seam is already covered by current repo behavior. It must not
speculate across listener, persistence, and surface code at the same time.

### Files And Repos To Inspect Next

Repo scope stays inside
`/Users/I560101/Project-Sat/mknoon-2/flutter_app`.

Production seams to inspect only as needed while pinning the repro:

- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/application/load_introductions_use_case.dart`
- `lib/features/introduction/presentation/widgets/intros_tab.dart`
- `lib/features/introduction/presentation/widgets/intro_row.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`

Direct test seams:

- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/application/mutual_acceptance_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/introduction/presentation/widgets/intro_row_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart` only if
  evidence needs Feed confirmation to separate protocol truth from surface
  refresh truth

### Existing Tests Covering This Area

- `mutual_acceptance_test.dart` already proves local accept plus explicit
  incoming accept can reach `mutualAccepted`.
- `introduction_multi_node_test.dart` and `introduction_smoke_test.dart`
  already prove both nodes can reach `mutualAccepted`, but current coverage
  still relies on explicit remote-accept helper injection for the cross-node
  effect.
- `orbit_intros_wiring_test.dart` already proves Orbit-side status update with
  manually injected remote accept.
- `feed_wired_test.dart` already proves Feed can surface the connection card
  when a `mutualAccepted` intro status change arrives.
- `intro_row_test.dart` already covers `Connected`, but not the exact waiting
  copy or waiting-to-connected transition for the same intro row on both peers.
- Missing today:
  - no deterministic automated proof of the exact reported split outcome
  - no direct introduced-side/User-C assertion for the live `Waiting for ...`
    to completed-state convergence
  - no direct proof separating remote accept truth from post-status surface
    refresh truth at the escaped seam

### Regression / Tests To Add First

- Extend or add the smallest deterministic repro in
  `test/features/introduction/integration/introduction_multi_node_test.dart`
  or `test/features/introduction/integration/introduction_smoke_test.dart` to
  pin the exact asymmetric outcome or disprove it under current repo truth.
- Add only the minimum direct Orbit/UI assertions needed to prove introduced-side
  waiting behavior and its transition to completed truth:
  - `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart`
- Touch Feed-side direct proof only if Session `1` needs it to distinguish
  intro-protocol truth from surface-refresh truth:
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`

### Step-By-Step Implementation Plan

1. Re-read the current mutual-acceptance integration, listener, Orbit wiring,
   and intro-row tests before editing so the new proof lands at the real seam
   rather than duplicating helper-driven assumptions.
2. Add the smallest deterministic automated coverage that exercises both sides
   of the same introduction and records exactly what each participant sees
   after the second accept.
3. If the new evidence still leaves the seam ambiguous, add one more narrow
   direct assertion at the closest user-visible boundary needed to separate
   remote-accept truth from UI refresh truth.
4. Keep production edits out of Session `1` unless a minimal instrumentation or
   direct assertion seam absolutely requires them to prove the current truth.
   If production code must change materially to expose the bug, stop and return
   `blocked` rather than guessing the fix early.
5. Update the breakdown artifact with the proven seam classification and the
   Session `2` activation decision:
   - runnable fix session if a real open seam is proven
   - `stale/already-covered` if current repo truth disproves the report or
     shows the seam is already closed
6. Run the direct suites listed below. Run `./scripts/run_test_gates.sh baseline`
   only if Session `1` had to touch shared top-level production wiring instead
   of remaining evidence-only in direct tests.
7. Stop after the seam is pinned. Do not implement the production fix in this
   session.

### Risks And Edge Cases

- Existing integration helpers may accidentally mask the real live-path seam if
  the new repro reuses too much manual status injection.
- The introduced-friend/User-C path is the likeliest blind spot, so execution
  must not stop after only re-proving the recipient/User-B direction.
- Session `35` already closed one Orbit stale-reload seam; execution must not
  reopen that closure without fresh evidence that current repo truth still
  fails.
- If current repo truth disproves the exact report, the breakdown and later
  session status must be refreshed honestly instead of forcing speculative fix
  work.
- The working tree may already contain unrelated changes; execution must merge
  carefully and must not revert user work.

### Exact Tests And Gates To Run

Direct tests:

- `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
  or `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
  depending on where the deterministic repro lands
- `flutter test test/features/introduction/application/mutual_acceptance_test.dart`
- `flutter test test/features/introduction/application/introduction_listener_test.dart`
- `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  only if Feed-side evidence is required by the final seam verdict

Named gate:

- `./scripts/run_test_gates.sh baseline` only if Session `1` changes shared
  top-level production wiring rather than staying evidence-only in direct tests

### Known-Failure Interpretation

- Treat failures in the new exact repro or introduced-side waiting assertions as
  the primary Session `1` signal until they are either fixed or proven to
  reflect stale assumptions in the report.
- Treat failures in untouched adjacent areas as Session `1` regressions only if
  they reproduce after accounting for the repo's existing dirty tree and are
  plausibly tied to the changed evidence seam.
- If the only way to produce deterministic proof would require widening into
  transport, bridge, or server infrastructure, return `blocked` instead of
  expanding this session.

### Done Criteria

- The repo has deterministic automated evidence for the reported mutual
  acceptance asymmetry or deterministic automated proof that the report is
  already covered/disproved.
- The evidence directly addresses introduced-side/User-C behavior rather than
  only recipient/User-B behavior.
- The execution result distinguishes the real seam closely enough for Session
  `2` to remain narrow.
- The breakdown artifact truthfully records whether Session `2` should run as a
  real fix session or downgrade to `stale/already-covered`.
- The direct suites required by the landed evidence pass, and any skipped
  optional suite or gate is justified by the bounded scope.

### Scope Guard

- Do not implement the production fix in Session `1`.
- Do not redesign intro UI, copy, or Feed/Orbit presentation.
- Do not change one-sided pending, pass, expiry, or `alreadyConnected`
  product rules unless the new evidence proves the report depends on one of
  those rules being wrong.
- Do not create a new frozen named intro gate for this report.
- Do not widen into transport, bridge, or server changes unless the evidence
  step proves the current seam is there, in which case this session should stop
  `blocked` rather than fix it.

### Accepted Differences / Intentionally Out Of Scope

- Final production-fix work belongs to Session `2` only after Session `1`
  proves a real runnable seam.
- Closure/index refresh beyond the report breakdown ledger stays out of this
  session unless execution proves the report is already closed.
- Feed-specific follow-up verification remains optional unless required to
  distinguish the proven seam.

### Dependency Impact

- Session `2` depends entirely on Session `1` leaving a trustworthy seam verdict.
- If Session `1` ends `blocked`, Session `2` remains dependency-blocked.
- If Session `1` ends by disproving or narrowing the report to already-landed
  behavior, Session `2` should be marked `stale/already-covered` instead of
  forcing speculative production work.
