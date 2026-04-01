# 38 - Mutual Intro Acceptance Leaves One Side Waiting Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `2`

## Overall closure bar

Report `38` is closed only when the current repo proves the mutual-acceptance
contract for both roles, not just one side:

- once User-B and User-C have both accepted the same introduction, neither side
  still shows that same pair as a pending intro or `Waiting for ...`
- User-B and User-C are treated as connected contacts/friends on both devices
  after mutual acceptance
- the completed connection can surface consistently across the current Feed and
  Orbit surfaces for both participants under the existing product contract
- one-sided acceptance still remains pending until the second person responds
- the repo has a permanent direct regression at the real escaped seam instead of
  relying on manual status injection or prose-only expectations

## Final program acceptance

- Closure verdict:
  `closed`
- Acceptance date:
  `2026-03-31`
- What is now closed:
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
    now proves the live multi-node intro path converges without manual
    `receiveAcceptNotification(...)` helper injection when User-B accepts
    first and when User-C accepts first
  - those new direct regressions prove both participants stop treating the same
    intro as pending after the second accept and both participants get the
    mutual-acceptance contact outcome under current repo truth
  - `test/features/introduction/presentation/widgets/intro_row_test.dart` now
    proves the introduced-side `Waiting for <username>` label is a valid
    one-sided pending state rather than a post-mutual-acceptance state
  - `test/features/introduction/application/mutual_acceptance_test.dart` and
    `test/features/introduction/application/introduction_listener_test.dart`
    remained green, so the existing listener and status-derivation contracts
    stayed aligned with the new evidence
  - Report `38` therefore closes as a stale reproduction against the current
    repo rather than a missing production-fix slice
- Residual-only items:
  - none
- Still-open items:
  - none
- Reopen only on real regression:
  - if a fresh current-repo/device repro shows one participant still stuck on
    `Waiting for ...` after both accepts without helper injection
  - if the live multi-node intro regression stops converging on either
    acceptance order
  - if the waiting-state UI stops transitioning honestly between one-sided
    pending and mutual acceptance

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`
- `UI-20-Intro-friends/intro-feature-spec.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/session-35-plan.md`
- `Test-Flight-Improv/00-INDEX.md`

Current production seams that govern the split:

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

Current direct tests and adjacent closure evidence that materially shape the
split:

- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/application/mutual_acceptance_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/introduction/presentation/widgets/intro_row_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

Repo-truth findings that force this split:

- `UI-20-Intro-friends/intro-feature-spec.md` already defines the product
  contract clearly: both User-B and User-C receive the intro, and once both
  accept, both should get the connection outcome across Feed and Orbit.
- `Test-Flight-Improv/session-35-plan.md` records that one adjacent stale
  intro-reload seam in `OrbitWired` was already closed as a narrow Orbit-side
  race, not as a broad intro protocol reopen.
- current repo tests still leave a real ambiguity about the escaped seam:
  existing intro integration tests and Orbit wiring tests often use explicit
  `receiveAcceptNotification(...)` helper injection, so they do not lock the
  exact reported asymmetric User-B/User-C outcome
- current widget coverage proves `Connected`, but does not directly prove the
  introduced-side `Waiting for <user>` to completed-state transition for the
  same intro row
- current evidence therefore supports at least two plausible seams with
  different blast radius:
  remote accept propagation / persistence, or post-accept surface refresh and
  role-direction projection

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Plan file state | Local fallbacks used | Final execution verdict | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Exact mutual-acceptance asymmetry reproducer and seam pin` | `evidence-gated` | `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-1-plan.md` | none | `accepted` | `materialized 2026-03-31 via local plan fallback after the spawned planning step no-progressed` | `planning / execution / closure` | `accepted` | `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-breakdown.md` | Accepted on `2026-03-31`: Session `1` added deterministic no-helper multi-node evidence in `test/features/introduction/integration/introduction_multi_node_test.dart` for both acceptance orders and a direct waiting-label assertion in `test/features/introduction/presentation/widgets/intro_row_test.dart`; those suites plus `mutual_acceptance_test.dart` and `introduction_listener_test.dart` passed, proving the current repo already converges after both accepts and that the introduced-side waiting state is only valid before the second accept. No production fix or named gate was justified. |
| `2` | `Confirmed-seam mutual-acceptance convergence fix and closure` | `prerequisite-blocked` | `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-2-plan.md` | `1` | `stale/already-covered` | `not created; Session 1 disproved a still-open repo-local seam` | none | `not run; stale/already-covered` | `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-breakdown.md` | Downgraded on `2026-03-31`: Session `1` showed the current live intro path already processes remote accepts and clears pending intro state on both participants without manual `receiveAcceptNotification(...)` helper injection, so no confirmed production-fix session remains to execute. Reopen only if a fresh external repro or a new repo regression proves a different seam. |

## Ordered session breakdown

### Session 1

- Title:
  `Exact mutual-acceptance asymmetry reproducer and seam pin`
- Session id:
  `1`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-1-plan.md`
- Exact scope:
  - add deterministic repo-local coverage for the exact reported asymmetry:
    one participant reaches the completed-connection outcome while the other
    still shows `Waiting for ...` for the same intro
  - pin both role directions, with explicit focus on the current user as the
    introduced friend/User-C rather than only the recipient/User-B path
  - determine whether the stale state comes from missing remote accept
    propagation, local intro persistence/status derivation, or post-status
    Orbit/Feed surface refresh
  - add the smallest direct user-visible assertions needed so downstream work is
    not guessing between protocol/listener and UI refresh seams
  - refresh this breakdown artifact if the exact report is disproved or narrowed
    materially by the new evidence
- Why it is its own session:
  - the proposal is narrow, but the current repo still leaves two materially
    different seams in play
  - `session-35-plan.md` already claims one adjacent Orbit stale-reload seam is
    closed, so a new implementation session cannot safely assume the same
    root cause without fresh proof
  - the current direct suites prove pieces of the contract, but not the escaped
    User-C stale-waiting outcome itself
- Likely code-entry files:
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart` only if the
    evidence needs Feed-side confirmation to separate transport from surface
    failure
  - observed production seams while pinning the repro:
    `accept_introduction_use_case.dart`,
    `handle_incoming_introduction_use_case.dart`,
    `introduction_listener.dart`,
    `orbit_wired.dart`,
    `intros_tab.dart`,
    `intro_row.dart`
- Likely direct tests/regressions:
  - a new or extended exact repro in
    `test/features/introduction/integration/introduction_multi_node_test.dart`
    or
    `test/features/introduction/integration/introduction_smoke_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `flutter test test/features/introduction/application/mutual_acceptance_test.dart`
  - `flutter test test/features/introduction/application/introduction_listener_test.dart`
- Likely named gates:
  - no frozen named gate owns this seam directly today
  - direct intro/orbit/feed suites first
  - run `./scripts/run_test_gates.sh baseline` only if Session `1` must touch
    shared top-level production wiring rather than staying evidence-only in
    direct tests
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-breakdown.md`
  - `Test-Flight-Improv/test-gate-definitions.md` only if Session `1` adds a
    brand-new test file that needs classification rather than extending
    existing direct suites
- Dependency on earlier sessions:
  - none

### Session 2

- Title:
  `Confirmed-seam mutual-acceptance convergence fix and closure`
- Session id:
  `2`
- Session classification:
  `prerequisite-blocked`
- Intended plan file:
  `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-2-plan.md`
- Exact scope:
  - implement only the production fix that Session `1` proves
  - if the real seam is remote accept delivery, listener processing, or local
    intro status persistence, keep the patch inside that intro message/status
    lane
  - if the real seam is post-status Orbit/Feed refresh or introduced-side role
    projection, keep the patch inside that narrower surface lane
  - land the permanent escaped-bug regression at the proven seam
  - preserve the existing one-sided-pending, passed, expired, and
    `alreadyConnected` contracts unless Session `1` proves the report depends on
    one of those rules being wrong
  - close the doc-scoped rollout honestly without widening named gates unless
    test inventory actually changes
- Why it is its own session:
  - the production seam is not safe to pre-choose from the current evidence
  - the likely fix paths have different blast radius:
    intro accept propagation/persistence vs Orbit/Feed surface convergence
  - once the real seam is pinned, the fix, direct regressions, and closure docs
    can land together in one meaningful verified state
- Likely code-entry files:
  - confirmed by Session `1`, likely one or more of:
    `lib/features/introduction/application/accept_introduction_use_case.dart`,
    `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`,
    `lib/features/introduction/application/introduction_listener.dart`,
    `lib/features/introduction/application/load_introductions_use_case.dart`,
    `lib/features/introduction/presentation/widgets/intros_tab.dart`,
    `lib/features/introduction/presentation/widgets/intro_row.dart`,
    `lib/features/orbit/presentation/screens/orbit_wired.dart`,
    `lib/features/feed/presentation/screens/feed_wired.dart`
  - matching direct tests under:
    `test/features/introduction/`,
    `test/features/orbit/presentation/screens/`,
    `test/features/feed/presentation/screens/`
- Likely direct tests/regressions:
  - the exact Session `1` reproducer
  - `flutter test test/features/introduction/application/introduction_listener_test.dart`
  - `flutter test test/features/introduction/application/mutual_acceptance_test.dart`
  - `flutter test test/features/introduction/regression/introduction_regression_test.dart`
  - `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
  - `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
    if Feed follow-up behavior or connection-card surfacing changes
- Likely named gates:
  - no frozen named gate directly owns intro mutual-acceptance convergence
  - run the direct intro/orbit/feed maintenance suite above
  - run `./scripts/run_test_gates.sh baseline` as the companion gate because
    this report touches shared user-visible app surfaces
  - run `./scripts/run_test_gates.sh feed` only if the landed fix changes Feed
    card or Feed-owned follow-up behavior materially rather than staying inside
    intro/orbit seams
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md` only if Session `2` actually closes
    Report `38`
  - `Test-Flight-Improv/test-gate-definitions.md` only if Session `2` adds a
    new classified test file or changes maintained direct-suite inventory
  - `Test-Flight-Improv/session-35-plan.md` only if the landed fix proves the
    prior Session `35` closure statement needs an explicit reopen/reference
    refresh for maintenance-time honesty
- Dependency on earlier sessions:
  - must wait for Session `1` evidence
  - if Session `1` disproves the repo-local bug or narrows it to already-landed
    behavior, downgrade Session `2` to `stale/already-covered` instead of
    forcing speculative production work

## Why this is not fewer sessions

One session would be unsafe because the current repo still supports two
different explanations for the escaped symptom:

- User-C may never be processing User-B's accept at all
- User-C may process the accept, but the local Orbit/Feed surface may still
  publish or retain stale pending state for the introduced-side role

Those explanations touch different production seams and different direct proof.
The existing Session `35` closure record already says one adjacent Orbit stale
reload seam is closed, so a single implementation session would invite
speculation-driven edits across listener, persistence, and surface code at the
same time. The minimum safe set is therefore:

- one evidence-gated session that leaves the repo with a deterministic repro or
  disproval
- one dependent fix/closure session that uses that landed evidence rather than
  the bug narrative alone

## Why this is not more sessions

More sessions would be bookkeeping overhead because:

- there is still only one user-visible slice: after both accepts, the same
  introduction must converge to a completed connection on both participants
- once Session `1` proves the real seam, the production patch, permanent direct
  regressions, and closure refresh all ride the same mutual-acceptance outcome
- splitting protocol, Orbit, Feed, and closure into separate sessions before
  Session `1` would be hallucination bait and would not provide independent
  verification value
- a separate closure-only session is unnecessary unless Session `2` broadens
  into multiple independently verifiable seams, which this decomposition
  explicitly rejects

## Regression and gate contract

- Follow `Test-Flight-Improv/14-regression-test-strategy.md` by adding one
  permanent regression for the escaped bug at the real seam rather than adding a
  broad new smoke layer.
- `Test-Flight-Improv/test-gate-definitions.md` remains the source of truth for
  named gates and currently says intro-to-Orbit and intro-to-Feed follow-up
  behavior stays in direct suites, not in a frozen named intro gate.
- Minimum direct proof across the session set:
  - the exact asymmetric User-B/User-C repro is captured or disproved
  - introduced-side/User-C waiting state is asserted directly, not inferred only
    from recipient-side tests
  - once both accepts are complete, the same intro no longer appears as pending
    on either participant
  - if Feed follow-up changes, the connection card still surfaces truthfully for
    the new contact
  - existing listener, mutual-acceptance, and introduction regression suites
    remain green
- Gate expectations by session:
  - Session `1`: direct intro/orbit/feed suites first; `baseline` only if the
    evidence session must touch shared production wiring
  - Session `2`: direct intro/orbit/feed suites plus `./scripts/run_test_gates.sh baseline`
  - Session `2`: `./scripts/run_test_gates.sh feed` only if Feed card/follow-up
    code changes materially
- Completeness-check rule:
  - run `./scripts/run_test_gates.sh completeness-check` only if a new test file
    is added and `test-gate-definitions.md` is edited

## Matrix update contract

- Do not create a new matrix doc for Report `38`.
- Existing stable matrix/closure docs for this area are:
  - `Test-Flight-Improv/test-gate-definitions.md` for direct-suite and named-gate ownership
  - `Test-Flight-Improv/session-35-plan.md` as the adjacent closed intro-to-Orbit
    closure record that this report may narrowly reopen
- This new breakdown artifact is the doc-scoped closure-owner ledger for
  Report `38`.
- Session `1` owns refreshing this breakdown if it disproves or narrows the bug.
- Session `2` owns the maintenance-time closure refresh if a real fix lands.
- Update `Test-Flight-Improv/00-INDEX.md` only if Session `2` actually closes
  the report into stable maintenance-time meaning.
- Update `Test-Flight-Improv/session-35-plan.md` only if the landed fix proves
  that the prior closed seam needs an explicit cross-reference or reopen note.
- Update `Test-Flight-Improv/test-gate-definitions.md` only if new classified
  direct-suite files are introduced.

## Downstream execution path

- Session `1` should next go through, in order:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Session `2` should next go through, in order, after Session `1` is closed and
  only if it remains a real runnable session:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none
- final closure state:
  - Session `1` is accepted as the evidence session that disproved the
    currently decomposed repo-local bug narrative
  - Session `2` remains `stale/already-covered` and should not execute unless
    fresh evidence proves a new seam

## Accepted differences intentionally left unchanged

- do not redesign intro UI, copy, or the connection-card visual treatment
- do not change one-sided pending behavior, pass behavior, 30-day expiry, or
  `alreadyConnected` rules; Session `1` evidence showed the current repo still
  satisfies those contracts for this report
- do not create a new frozen named intro gate for this report
- do not reopen transport, bridge, or server work from this report; no
  production fix landed because the current repo already passes the narrower
  direct evidence bar
- accept that Session `2` ended `stale/already-covered` because Session `1`
  disproved the current repo-local bug narrative

## Exact docs/files used as evidence

- `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting.md`
- `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-1-plan.md`
- `UI-20-Intro-friends/intro-feature-spec.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/session-35-plan.md`
- `Test-Flight-Improv/00-INDEX.md`
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

## Why the decomposition is safe to send into downstream planning/execution

- it isolates the only real ambiguity first instead of letting the planner guess
  between two different production seams
- it preserves the existing product contract from `intro-feature-spec.md`
  rather than widening scope from the bug narrative
- it reuses the current gate/maintenance policy in
  `test-gate-definitions.md` instead of inventing a new intro gate
- it gives the downstream planner doc-scoped plan paths and a clear stop rule:
  prove the seam in Session `1`, then either fix the confirmed seam in
  Session `2` or close Session `2` as `stale/already-covered`

## Program rollout ledger

- Breakdown artifact used:
  `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-breakdown.md`
- Spawned-agent isolation used:
  `yes` for the attempted planning, execution, closure, and final-acceptance
  passes; all four no-progressed and were replaced by the single bounded local
  fallbacks allowed by the pipeline contract
- Sessions processed:
  `2/2`
- Sessions accepted:
  `1`
- Sessions accepted_with_explicit_follow_up:
  `0`
- Sessions blocked:
  `0`
- Sessions stale/already-covered:
  `1`
- Sessions skipped_due_to_dependency:
  `0`
- Plan fallbacks used:
  `1`
- Execution fallbacks used:
  `1`
- Closure fallbacks used:
  `1`
- Final acceptance fallbacks used:
  `1`
- Final program acceptance verdict:
  `closed`
- Stable docs updated:
  `Test-Flight-Improv/38-mutual-intro-acceptance-leaves-one-side-waiting-session-breakdown.md`
- Final blocker note:
  none
