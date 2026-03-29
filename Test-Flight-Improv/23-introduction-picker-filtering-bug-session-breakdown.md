# 23 - Introduction Picker Filtering Bug Session Breakdown

## Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/23-introduction-picker-filtering-bug-session-breakdown.md`
- Proposal path: `Test-Flight-Improv/23-introduction-picker-filtering-bug.md`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Downstream execution path

- For each executable session, run in this exact order using fresh spawned
  agents with bounded artifact handoff:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- After the final runnable session, run one fresh whole-program acceptance pass
  using `$implementation-closure-audit-orchestrator` against the completed
  breakdown artifact and stable closure docs.
- The breakdown artifact remains the live handoff ledger between spawned
  agents; do not rely on shared conversational context.

## Recommended plan count

- `2`

## Overall closure bar

All work is done only when the repo has deterministic evidence for the current
intro-picker contract and the docs record whether the proposal was fixed or
disproved:

- the picker excludes only the exact already-introduced pair for the active
  recipient under the current product rules
- the reported "B missing from C's picker after A introduced D to B" symptom is
  either reproduced and fixed at the real seam or disproved and closed as stale
- the repo has a permanent direct regression at the relevant seam: a picker
  regression if the current code is already correct, or a production-fix
  regression if a real bug is reproduced
- intro maintenance docs point future work at the right direct suites instead of
  relying on the bug writeup alone

## Source of truth

Primary governing sources for this split:

- Product intent:
  `UI-20-Intro-friends/intro-feature-spec.md`
- Proposal under review:
  `Test-Flight-Improv/23-introduction-picker-filtering-bug.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Named gate policy:
  `Test-Flight-Improv/test-gate-definitions.md`
- Stable closure state:
  `Test-Flight-Improv/00-INDEX.md`

Primary code and current-test seams:

- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/introduction/application/send_introduction_use_case.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `lib/features/introduction/domain/models/introduction_model.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/introduction/presentation/screens/friend_picker_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`

Source-of-truth conflict that forced the split:

- the proposal treats passed / expired intros as likely eligible for
  re-introduction
- the current feature spec says the picker excludes friends already introduced
  to the active recipient "regardless of status"
- the current picker implementation already filters by exact
  `(recipient, introduced)` pair, so the reported symptom is not proven by the
  current code alone

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Final execution verdict | Closure docs touched | Blocker note |
|---|---|---|---|---|---|---|---|---|
| `42` | Intro picker reproduction and contract pin | `evidence-gated` | `Test-Flight-Improv/session-42-plan.md` | none | `completed` | `accepted` | `Test-Flight-Improv/23-introduction-picker-filtering-bug-session-breakdown.md` | picker and introducer-state regressions landed; no production fix was needed |
| `43` | Confirmed-seam picker fix and closure | `prerequisite-blocked` | `Test-Flight-Improv/session-43-plan.md` | `42` | `stale/already-covered` | `stale/already-covered` | none | Session 42 disproved the proposal narrative in current repo code; no Session 43 plan was created; wait for a new external repro or real repo regression before replanning |

## Session 42 closure outcome

- Closure classification: `residual_only`
- What is now closed:
  - `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
    now pins that the current picker excludes only the exact
    `(recipient, introduced)` pair for the active recipient, so the reported
    `(A, B, D)` scenario stays green in current repo code
  - `test/features/introduction/regression/introduction_regression_test.dart`
    now pins that introducer-side send plus listener delivery keeps local intro
    state limited to the single sent pair and does not create unrelated
    introducer rows
  - Session `43` is no longer an automatic follow-on implementation session for
    this proposal; it stays `stale/already-covered` unless fresh evidence proves
    a different escaped seam
- Residual-only items:
  - a new external repro that shows unrelated contacts disappearing from the
    picker under current code
  - a real repo regression that introduces unexpected extra introducer-side
    intro rows for the same scenario
- Accepted differences:
  - no production fix landed in Session `42`; the landed evidence showed the
    current repo already satisfied the narrower duplicate-exclusion contract
  - the proposal's status-based re-introduction expectations remain rejected;
    the current intro feature spec still governs maintenance-time behavior
  - named gates remain unchanged because no frozen named gate owns this seam
- Maintenance-time safety:
  - direct suites: the new picker regression plus
    `test/features/introduction/regression/introduction_regression_test.dart`,
    `test/features/introduction/integration/intro_wiring_smoke_test.dart`,
    `test/features/introduction/integration/introduction_smoke_test.dart`, and
    `test/features/introduction/integration/introduction_multi_node_test.dart`
  - named gates: none for this session per plan contract

## Final whole-program acceptance

- Program acceptance verdict: `residual_only`
- Docs updated in this pass:
  - `Test-Flight-Improv/23-introduction-picker-filtering-bug-session-breakdown.md`
- Completion evidence accepted for final closure:
  - Session `42` was planned, executed in isolated executor/QA passes, and
    accepted as `residual_only` evidence-only work
  - the landed repo evidence is limited to:
    `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
    and
    `test/features/introduction/regression/introduction_regression_test.dart`
  - the direct intro verification set was already run twice in isolated
    execution/QA passes:
    `flutter test test/features/introduction/presentation/screens/friend_picker_wired_test.dart`,
    `flutter test test/features/introduction/regression/introduction_regression_test.dart`,
    `flutter test test/features/introduction/integration/intro_wiring_smoke_test.dart`,
    `flutter test test/features/introduction/integration/introduction_smoke_test.dart`,
    and
    `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
  - named gates run: none, per plan contract
  - Session `43` was refreshed after Session `42` and remains
    `stale/already-covered`; no Session `43` plan file was justified
- What is now considered closed:
  - this proposal no longer has an open repo-proven picker-filtering fix
    session
  - the current repo now has permanent direct evidence that the reported
    `(A, B, D)` scenario does not remove unrelated eligible contacts from the
    picker under the current contract
  - the introducer-side data path is now pinned against creating unrelated
    local introduction rows for the same scenario
- Residual-only items:
  - a fresh external repro that demonstrates the reported picker symptom under
    current repo code
  - a real repo regression that causes unrelated contacts to disappear from the
    picker for a recipient who was not part of the stored exact pair
  - a real repo regression that creates unexpected extra introducer-side intro
    rows for the same flow
- Still-open items:
  - none inside this proposal's current repo-proven scope
- Accepted differences:
  - no production fix landed because Session `42` disproved the proposal's
    assumed seam in current repo code
  - the proposal's broader status-based re-introduction expectations remain
    rejected in favor of the current feature spec
  - named gates and broader folder closure docs stay unchanged because this
    rollout did not widen maintained gate inventory or the folder-level closure
    state
- Reopen rules:
  - reopen only on a real regression in
    `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
    or
    `test/features/introduction/regression/introduction_regression_test.dart`,
    or on a fresh external repro that current repo code can now reproduce
  - do not reopen from the proposal narrative alone
  - do not create a new Session `43` plan unless new evidence proves a real
    production seam that escaped the current direct intro suites

## Ordered session breakdown

### Session 42

- Title: `Intro picker reproduction and contract pin`
- Session id: `42`
- Session classification: `evidence-gated`
- Intended plan file: `Test-Flight-Improv/session-42-plan.md`
- Exact scope:
  - add deterministic direct coverage for `FriendPickerWired` or an extracted
    helper so the exact reported symptom is reproduced or disproved in repo
    tests
  - verify whether the bug is actually in picker filtering,
    introduction-record creation, or introducer-side duplicated / unexpected
    local data
  - pin the current product contract for duplicate exact-pair exclusions so
    downstream work does not silently widen into status-policy changes
  - refresh this session breakdown if the evidence disproves the proposal's
    root-cause narrative
- Why it is its own session:
  - the proposal mixes one escaped user-visible symptom with three different
    possible seams: picker filtering, DB query scope, and duplicated intro data
  - the current code does not yet prove the reported bug
  - the proposal's status-based re-introduction expectations conflict with the
    feature spec, so implementation without a reproduction would be unsafe
- Likely code-entry files:
  - `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
  - `test/features/introduction/presentation/screens/friend_picker_test.dart`
  - `test/features/introduction/regression/introduction_regression_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `lib/features/introduction/application/send_introduction_use_case.dart`
  - `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/core/database/helpers/introductions_db_helpers.dart`
- Likely direct tests/regressions:
  - a new dedicated `FriendPickerWired` regression or equivalent extracted
    helper test
  - `flutter test test/features/introduction/regression/introduction_regression_test.dart`
  - `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
  - `flutter test test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
- Likely named gates:
  - none directly own intro-picker behavior today
  - use direct intro suites first
  - run `./scripts/run_test_gates.sh baseline` only if Session 42 has to touch
    conversation entry or other broader UI wiring
- Matrix/closure docs to update when done:
  - no stable closure doc update is required if Session 42 only lands evidence
  - if Session 42 disproves the bug or narrows it materially, refresh this
    breakdown artifact before Session 43 planning
- Dependency on earlier sessions:
  - none

### Session 43

- Title: `Confirmed-seam picker fix and closure`
- Session id: `43`
- Session classification: `prerequisite-blocked`
- Intended plan file: `Test-Flight-Improv/session-43-plan.md`
- Exact scope:
  - implement only the production fix that Session 42 proves
  - keep the fix at the confirmed seam:
    picker filtering if the current pair logic is wrong, or introduction
    create/listener/repository data flow if the picker is only reflecting bad
    local state
  - add the permanent regression at the escaped seam
  - close the maintenance contract in stable docs without widening named gates
    unless a new classified integration suite is actually added
- Why it is its own session:
  - the production seam is unknown until Session 42 lands
  - UI-only and data-path fixes have different direct regression families and
    different blast radius
  - combining proof and fix in one session would invite speculation-driven code
    changes and product-scope drift
- Likely code-entry files:
  - confirmed in Session 42, likely one of:
    `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
    `lib/features/introduction/application/send_introduction_use_case.dart`
    `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
    `lib/features/introduction/application/introduction_listener.dart`
    `lib/core/database/helpers/introductions_db_helpers.dart`
  - matching direct tests under:
    `test/features/introduction/presentation/screens/`
    `test/features/introduction/regression/`
    `test/features/introduction/integration/`
- Likely direct tests/regressions:
  - the new Session 42 reproducer
  - `flutter test test/features/introduction/regression/introduction_regression_test.dart`
  - `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
  - `flutter test test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
  - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
    only if the entry/opening flow changed
- Likely named gates:
  - none directly own the seam today
  - baseline gate is the only likely companion gate when broader conversation
    wiring changes
- Matrix/closure docs to update when done:
  - only if Session `43` is reopened by fresh evidence and a real production
    fix lands:
    `Test-Flight-Improv/00-INDEX.md`
  - only if that reopened work widens or reclassifies maintained test
    inventory:
    `Test-Flight-Improv/test-gate-definitions.md`
  - otherwise keep this breakdown artifact as the stable closure reference for
    the disproved proposal
- Dependency on earlier sessions:
  - must wait for Session 42 evidence
  - Session 42 landed direct picker and introducer-state regressions that kept
    the reported `(A, B, D)` scenario green in current repo code
  - keep Session 43 downgraded to `stale/already-covered` unless a new external
    repro proves a different production seam

## Why this is not fewer sessions

One session would be unsafe because:

- the current picker code already filters by exact recipient pair, so the
  proposal does not yet prove the seam it wants changed
- the proposal bundles an unproven escaped bug together with a product-contract
  rewrite around passed / expired intros
- a single implementation session would encourage speculative fixes in
  `FriendPickerWired`, the DB query, and the intro data path at the same time
- the direct regressions needed to prove the escaped bug are different from the
  broader suites needed after a real production fix lands

The minimum safe set is therefore:

- one evidence session that leaves the repo with a deterministic reproducer or
  a disproval
- one dependent fix/closure session that uses the landed evidence instead of
  the proposal's assumptions

## Why this is not more sessions

More sessions would be bookkeeping overhead because:

- there is still only one user-visible slice: the intro picker showing the
  wrong eligible contacts
- splitting picker UI from intro data-path implementation now would be
  hallucination bait until Session 42 proves which seam is actually broken
- a separate acceptance-only or closure-only session is unnecessary unless
  Session 43 broadens into multiple independently verifiable seams, which this
  decomposition explicitly forbids

## Regression and gate contract

- Follow `Test-Flight-Improv/14-regression-test-strategy.md` by adding one
  permanent regression for the escaped bug at the real seam rather than adding
  broad new smoke coverage.
- `Test-Flight-Improv/test-gate-definitions.md` remains the source of truth for
  named gates.
- No frozen named gate directly owns intro-picker behavior today, so both
  sessions should rely on direct intro suites.
- Minimum direct verification across the session set:
  - picker-local deterministic regression
  - `test/features/introduction/regression/introduction_regression_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
- Companion named gate rule:
  - run `./scripts/run_test_gates.sh baseline` only if the landed fix touches
    broader conversation wiring or another baseline-owned path

## Matrix update contract

- `Test-Flight-Improv/23-introduction-picker-filtering-bug-session-breakdown.md`
  is now the stable closure reference for this proposal because Session `42`
  landed only evidence and ledger state, not a broader feature closure.
- `Test-Flight-Improv/00-INDEX.md` stays unchanged because Session `42` did not
  change the broader folder closure state.
- `Test-Flight-Improv/test-gate-definitions.md` stays unchanged because Session
  `42` did not widen or alter any frozen named gate.

## Structural blockers remaining

- None after this split.

Reviewer summary:

- Recommended session count is sufficient, not too coarse.
- No sessions should merge.
- One split is required: proof first, fix second.
- Missing gate contract was resolved by explicitly keeping this work in the
  direct intro suites, not by widening named gates.
- Each session ends in a meaningful verified state.
- Matrix-update responsibility is now resolved in this breakdown artifact
  because Session `42` closed the proposal as evidence-only state.

Arbiter summary:

- The one-session version was a structural blocker because it relied on an
  unproven seam and a spec conflict.
- After the split, Session 42 is mergeable-ready as evidence work and Session
  43 is correctly prerequisite-blocked pending landed evidence.

## Accepted differences intentionally left unchanged

- Do not adopt the proposal's status-based re-introduction rules for
  `passed` / `expired` intros unless the product spec is changed separately.
- Do not change the current "already introduced to this recipient" duplicate
  prevention contract based only on this bug writeup.
- Do not reopen intro-to-Orbit / intro-to-Feed follow-up work from Session 35
  unless Session 42 proves the picker bug is actually a downstream state-sync
  regression there.
- Do not widen into new protocol, inbox, retry, or notification work unless the
  reproducer proves the picker is only reflecting corrupted local intro state.

## Exact docs/files used as evidence

- `Test-Flight-Improv/23-introduction-picker-filtering-bug.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/session-35-plan.md`
- `UI-20-Intro-friends/intro-feature-spec.md`
- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/introduction/application/send_introduction_use_case.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `lib/features/introduction/domain/models/introduction_model.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `test/shared/fakes/in_memory_introduction_repository.dart`
- `test/shared/fakes/intro_test_user.dart`
- `test/features/introduction/presentation/screens/friend_picker_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/introduction/application/load_introductions_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- It resolves the only structural blocker in the proposal: root-cause certainty.
- It keeps product intent tied to the current intro feature spec instead of the
  proposal's broader assumptions.
- It gives downstream planning a meaningful first landing state even if the
  reported bug cannot be reproduced.
- It prevents speculative changes across unrelated intro, DB, and UI seams.
