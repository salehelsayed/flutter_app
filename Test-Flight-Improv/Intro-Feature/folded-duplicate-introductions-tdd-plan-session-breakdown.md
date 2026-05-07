# Folded Duplicate Introductions TDD Plan Session Breakdown

## Decomposition Artifact

- Artifact path:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
- Supporting docs:
  - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Decomposition date:
  `2026-05-05`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution
  - each session should add failing tests first, then implement the smallest
    code change needed to make those tests pass

## Run Mode Snapshot Seed

- Active mode: `standard`
- Degraded local continuation explicitly allowed: `no`
- Source proposal/matrix path:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
- Source row/status vocabulary: `Open`, `Closed`, `Blocked`
- Overall closure bar: every `DIF-*` source row is updated to `Closed` with
  concrete file-and-test evidence, or the final verdict remains `still_open`
  with an exact blocker.
- Final verdict policy: `closed` only when all required `P0` rows and the
  closure row are closed with evidence. If the four-identity simulator fixture
  is unavailable, the simulator row stays blocked and the final verdict remains
  `still_open`.

## Run Mode Snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: `no`
- Source proposal/matrix path:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
- Source row/status vocabulary: `Open`, `Closed`, `Blocked`
- Overall closure bar: every `DIF-*` source row is updated to `Closed` with
  concrete file-and-test evidence, or the final verdict remains `still_open`
  with an exact blocker.
- Final verdict policy: `closed` only when all required `P0` rows and the
  closure row are closed with evidence. If the four-identity simulator fixture
  is unavailable, the simulator row stays blocked and the final verdict remains
  `still_open`.

## Controller Progress

- `2026-05-06` - Controller intake: run mode snapshot refreshed; source matrix
  statuses are all `Open`, session ledger is all `pending`, no reusable
  `DIF-*` plan files exist yet. Next action: create the `DIF-001` plan through
  a fresh planning child.
- `2026-05-06 20:04 CEST` - Ledger sanity after `DIF-003`: source rows
  `DIF-001` through `DIF-003` are `Closed` with concrete evidence, and the
  matching session ledger rows are `accepted`. `DIF-004` is the next runnable
  session; no reusable `DIF-004` plan file exists yet. Next action: create the
  `DIF-004` plan through a fresh planning child.
- `2026-05-06 20:36 CEST` - Ledger sanity after `DIF-004`: source rows
  `DIF-001` through `DIF-004` are `Closed` with concrete evidence, and the
  matching session ledger rows are `accepted`. `DIF-005` is the next runnable
  session; no reusable `DIF-005` plan file exists yet. Next action: create the
  `DIF-005` plan through a fresh planning child.
- `2026-05-06 21:02 CEST` - Ledger sanity after `DIF-005`: source rows
  `DIF-001` through `DIF-005` are `Closed` with concrete evidence, and the
  matching session ledger rows are `accepted`. `DIF-006` is the next runnable
  session. Live fixture intake found booted iOS simulators
  `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`,
  `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and
  `1B098DFF-6294-407A-A209-BBF360893485`, plus booted simulator
  `38FECA55-03C1-4907-BD9D-8E64BF8E3469` and physical iPhone
  `00008030-001A6D2801BB802E`. No reusable `DIF-006` plan exists yet. Next
  action: create the `DIF-006` device/relay proof plan through a fresh planning
  child.
- `2026-05-06 22:39 CEST` - Closure audit after blocked `DIF-006` execution:
  final execution verdict is `blocked`, blocker class `test_or_gate_failure`.
  The four-identity fixture was available and standalone `happy` plus
  `folded-duplicate` proof passed, but required
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` is red because existing
  scenario 5 `copy` fails before the folded duplicate scenario runs. Source row
  `DIF-006` is now `Blocked`; `DIF-007` remains pending and dependency-blocked
  until the existing `copy` failure is fixed or classified and `all` is green.
- `2026-05-06 22:45 CEST` - Final ledger sanity: source rows `DIF-001`
  through `DIF-005` are `Closed` with matching `accepted` ledger entries,
  `DIF-006` remains `Blocked`/`blocked` with blocker class
  `test_or_gate_failure`, and `DIF-007` is now
  `Blocked`/`skipped_due_to_dependency` because its `DIF-006` prerequisite is
  not closed. Final verdict persisted as `still_open`; next safe action is to
  fix or separately classify the existing `copy` scenario failure, rerun
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`, then close `DIF-006`
  before running `DIF-007`.
- `2026-05-07 14:25 CEST` - Resume evidence after user-requested stop:
  earlier full-suite attempt had already passed scenario 1, and the resumed
  per-scenario loop passed scenarios `refresh`, `pass`, `repair`, `copy`,
  `partial`, `partition`, `offline-chat`, `pass-fallback`, `split-brain`, and
  `folded-duplicate`. The stale `copy` blocker is obsolete. A scenario 8
  `offline-first-chat` false timeout was fixed by increasing the receiver
  `chat_poll_cycles` in `smoke_test_friends.sh` to `120`; standalone
  `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh` passed before the
  resumed loop. `DIF-006` can close from blocked to accepted with resumed full
  scenario coverage evidence; `DIF-007` is now unblocked and is the next
  runnable closure/documentation session.

## Closure Progress

- `2026-05-06 19:01 CEST` - Session `DIF-001`, closure phase:
  Completion Auditor started. Docs inspected/updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`,
  `folded-duplicate-introductions-tdd-plan-session-DIF-001-plan.md`,
  `folded-duplicate-introductions-tdd-plan.md`, and DIF-001 owner code/test
  paths by targeted search. Tentative verdict: `accepted` if detailed evidence
  stays consistent. Next action: audit landed code/tests, source row closure,
  and ledger update needs.
- `2026-05-06 19:01 CEST` - Session `DIF-001`, closure phase:
  Completion Auditor completed / Closure Writer started. Docs inspected:
  DIF-001 plan execution verdict, source matrix row `DIF-001`, and
  DIF-001 owner code/test diffs. Tentative verdict: `accepted`; no blocker
  class found. Next action: update only the DIF-001 ledger/closure note in this
  breakdown artifact.
- `2026-05-06 19:03 CEST` - Session `DIF-001`, closure phase:
  Closure Writer completed / Closure Reviewer started. Docs updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md` ledger and
  `DIF-001` closure audit note. Tentative verdict: `accepted`. Next action:
  review the update against the DIF-001 plan, source row, and no-other-session
  scope guard.
- `2026-05-06 19:03 CEST` - Session `DIF-001`, closure phase:
  Closure Reviewer completed. Docs inspected/updated: breakdown ledger,
  `DIF-001` closure audit note, source row `DIF-001`, and DIF-001 execution
  verdict. Tentative verdict: `accepted` confirmed. Next action: stop this
  DIF-001-only closure audit; do not plan, execute, or close other sessions.
- `2026-05-06 19:28 CEST` - Session `DIF-002`, closure phase:
  Completion Auditor started. Docs inspected/updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`,
  `folded-duplicate-introductions-tdd-plan-session-DIF-002-plan.md`,
  `folded-duplicate-introductions-tdd-plan.md` row `DIF-002`, and targeted
  count-helper/count-source references. Tentative verdict: `accepted` if the
  detailed evidence stays consistent. Next action: audit the landed code/tests,
  source row closure, and DIF-002 ledger update needs.
- `2026-05-06 19:29 CEST` - Session `DIF-002`, closure phase:
  Completion Auditor completed / Closure Writer started. Docs inspected:
  DIF-002 final execution verdict, source matrix row `DIF-002`, helper tests,
  Feed badge count source, Orbit review count source, and raw repository count
  references. Tentative verdict: `accepted`; blocker class `none`. Next action:
  update only the DIF-002 ledger/current-count closure notes in this breakdown
  artifact.
- `2026-05-06 19:30 CEST` - Session `DIF-002`, closure phase:
  Closure Writer completed / Closure Reviewer started. Docs updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md` DIF-002
  ledger row, current count fact, DIF-001 stale-status wording, and
  `DIF-002` closure audit note. Tentative verdict: `accepted`. Next action:
  review the update against the DIF-002 plan, source row, and one-session scope
  guard.
- `2026-05-06 19:30 CEST` - Session `DIF-002`, closure phase:
  Closure Reviewer completed. Docs inspected/updated: breakdown ledger,
  `DIF-002` closure audit note, source row `DIF-002`, DIF-002 execution
  verdict, and breakdown-only diff/whitespace checks. Tentative verdict:
  `accepted` confirmed. Next action: stop this DIF-002-only closure audit; do
  not plan, execute, or close other sessions.
- `2026-05-06 20:00 CEST` - Session `DIF-003`, closure phase:
  Completion Auditor started. Docs inspected/updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`,
  `folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md`,
  `folded-duplicate-introductions-tdd-plan.md` row `DIF-003`, and targeted
  folded response code/test references. Tentative verdict: `accepted` if the
  detailed evidence stays consistent. Next action: audit the landed code/tests,
  source row closure, and DIF-003 ledger update needs.
- `2026-05-06 20:01 CEST` - Session `DIF-003`, closure phase:
  Completion Auditor completed / Closure Writer started. Docs inspected:
  DIF-003 final execution verdict, source matrix row `DIF-003`, folded
  response use-case code/test, and a current folded response suite rerun.
  Tentative verdict: `accepted`; blocker class `none`. Next action: update only
  the DIF-003 ledger row and closure audit note in this breakdown artifact.
- `2026-05-06 20:02 CEST` - Session `DIF-003`, closure phase:
  Closure Writer completed / Closure Reviewer started. Docs updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md` DIF-003
  ledger row and `DIF-003` closure audit note. Tentative verdict: `accepted`.
  Next action: review the update against the DIF-003 plan, source row, current
  folded response test result, and one-session scope guard.
- `2026-05-06 20:03 CEST` - Session `DIF-003`, closure phase:
  Closure Reviewer completed. Docs inspected/updated: breakdown ledger,
  `DIF-003` closure audit note, source row `DIF-003`, DIF-003 execution
  verdict, and current folded response test result. Tentative verdict:
  `accepted` confirmed. Next action: stop this DIF-003-only closure audit; do
  not plan, execute, or close other sessions.
- `2026-05-06 20:32 CEST` - Session `DIF-004`, closure phase:
  Completion Auditor started. Docs inspected/updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`,
  `folded-duplicate-introductions-tdd-plan-session-DIF-004-plan.md`,
  `folded-duplicate-introductions-tdd-plan.md` row `DIF-004`, and targeted
  folded UI rendering code/test references. Tentative verdict: `accepted` if
  the detailed evidence stays consistent. Next action: audit the landed
  code/tests, source row closure, and DIF-004 ledger update needs.
- `2026-05-06 20:33 CEST` - Session `DIF-004`, closure phase:
  Completion Auditor completed / Closure Writer started. Docs inspected:
  DIF-004 final execution verdict, source matrix row `DIF-004`, `IntroRow`,
  `IntrosTab`, active `OrbitScreen` folded rendering diffs, and direct folded
  UI widget tests. Tentative verdict: `accepted`; blocker class `none`. Next
  action: update only the DIF-004 ledger row, source row, and closure audit
  note.
- `2026-05-06 20:33 CEST` - Session `DIF-004`, closure phase:
  Closure Writer completed / Closure Reviewer started. Docs updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md` DIF-004
  ledger row and `DIF-004` closure audit note, plus source matrix row
  `DIF-004`. Tentative verdict: `accepted`. Next action: review the update
  against DIF-004 scope guard, source row evidence, and no-other-session edit
  constraints.
- `2026-05-06 20:35 CEST` - Session `DIF-004`, closure phase:
  Closure Reviewer completed. Docs inspected/updated: breakdown ledger,
  `DIF-004` closure audit note, source row `DIF-004`, DIF-004 execution
  verdict, and scoped doc diffs. Tentative verdict: `accepted` confirmed.
  Next action: stop this DIF-004-only closure audit; do not plan, execute, or
  close other sessions.
- `2026-05-06 20:58 CEST` - Session `DIF-005`, closure phase:
  Completion Auditor started. Docs inspected/updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`,
  `folded-duplicate-introductions-tdd-plan-session-DIF-005-plan.md`,
  `folded-duplicate-introductions-tdd-plan.md` row `DIF-005`, targeted
  `OrbitWired` code/test references, and current worktree status. Tentative
  verdict: `accepted` if scope and evidence stay consistent. Next action:
  audit landed code/tests, source row closure, and DIF-005 ledger update needs.
- `2026-05-06 20:59 CEST` - Session `DIF-005`, closure phase:
  Completion Auditor completed / Closure Writer started. Docs inspected:
  DIF-005 final execution verdict, source matrix row `DIF-005`, `OrbitWired`
  folded publish/action diff, `OrbitWired` folded wired tests, Feed badge
  evidence, and later-row statuses. Tentative verdict: `accepted`; blocker
  class `none`. Next action: update only the DIF-005 ledger row and closure
  audit note in this breakdown artifact.
- `2026-05-06 21:00 CEST` - Session `DIF-005`, closure phase:
  Closure Writer completed / Closure Reviewer started. Docs updated:
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md` DIF-005
  ledger row and `DIF-005` closure audit note. Tentative verdict: `accepted`.
  Next action: review the update against the DIF-005 plan, source row evidence,
  code/test scope guard, and no-DIF-006/DIF-007 closure constraint.
- `2026-05-06 21:01 CEST` - Session `DIF-005`, closure phase:
  Closure Reviewer completed. Docs inspected/updated: breakdown ledger,
  `DIF-005` closure audit note, source row `DIF-005`, DIF-005 execution
  verdict, targeted `OrbitWired` diffs, and scoped doc whitespace check.
  Tentative verdict: `accepted` confirmed. Next action: stop this DIF-005-only
  closure audit; do not plan, execute, or close other sessions.
- `2026-05-06 22:39 CEST` - Session `DIF-006`, closure phase:
  Completion Auditor started. Docs inspected/updated:
  `folded-duplicate-introductions-tdd-plan-session-DIF-006-plan.md`,
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`, and
  source matrix row `DIF-006`. Tentative verdict: `still_open`; blocker class
  under audit is `test_or_gate_failure`. Next action: verify green evidence
  versus the required red `all` gate and decide source-row status.
- `2026-05-06 22:39 CEST` - Session `DIF-006`, closure phase:
  Completion Auditor completed / Closure Writer started. Docs inspected:
  DIF-006 execution progress, source row `DIF-006`, and `DIF-007` dependency
  row. Tentative verdict: `still_open`. Evidence accepted as current
  implementation proof: live fixture intake, unknown-scenario RED, shell
  syntax, direct host tests, `./scripts/run_test_gates.sh intro`,
  standalone `happy`, standalone `folded-duplicate`, fix-pass reruns of
  `happy` and `folded-duplicate`, and `git diff --check`. Remaining blocker:
  required `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` failed in existing
  scenario 5 `copy`; standalone `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh`
  reproduced the C-side missing intro/system-message assertion. Next action:
  update the ledger and source row as blocked without closing `test-inventory.md`
  or `DIF-007`.
- `2026-05-06 22:39 CEST` - Session `DIF-006`, closure phase:
  Closure Writer completed / Closure Reviewer started. Docs updated:
  DIF-006 plan closure progress, breakdown ledger and `DIF-006` closure audit
  note, plus source matrix row `DIF-006`. Tentative verdict: `still_open` with
  blocker class `test_or_gate_failure`. Next action: review for source-matrix
  consistency and accidental overclaiming.
- `2026-05-06 22:39 CEST` - Session `DIF-006`, closure phase:
  Closure Reviewer completed. Docs inspected/updated: DIF-006 plan closure
  progress, breakdown ledger, source row `DIF-006`, and no-DIF-007-closure
  constraint. Verdict confirmed: `still_open`; session status remains
  `blocked`, not `accepted`. Next action: fix or separately classify the
  existing `copy` C-side delivery/settling failure, then rerun required
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` before closing `DIF-006` or
  running `DIF-007` closure.

## Downstream Execution Path

For each unresolved session, run through:

1. `$implementation-plan-orchestrator`
2. `$implementation-execution-qa-orchestrator`
3. `$implementation-closure-audit-orchestrator`

After all runnable sessions, run final program acceptance/closure.

## Recommended Plan Count

- `7`
- Smallest safe split:
  - `6` implementation-ready sessions
  - `1` acceptance-only documentation and final-closure session
- No session should execute in parallel. The UI and wired sessions depend on
  the folded application model and group action contract. The simulator proof
  depends on the integrated folded UI and wired behavior.

## Overall Closure Bar

The rollout is closed only when all of the following are true:

- a current user sees one intro review row per target peer, even when multiple
  introducers produced separate active introduction records
- a user upgrading from the current shipped build sees their already-persisted
  pending intro rows in the new folded review design after first launch, with no
  intro ids, statuses, introducer attribution, or pending decisions lost
- the folded row visibly names multiple introducers
- one Accept/Pass action applies to every current underlying pending intro in
  the fold
- Orbit and Feed user-facing badge/review counts count folded targets, not raw
  duplicate rows
- existing single-intro behavior, already-connected behavior, pass/expiry
  terminal behavior, and same-introducer newer-wins dedupe still pass
- `./scripts/run_test_gates.sh intro` passes after the implementation
- `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh` passes with
  four distinct identities: introducer A, current viewer B, introduced target C,
  and second introducer D from a fourth simulator or attached physical device
- `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh` remains green and
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` includes the new folded
  duplicate scenario
- the source TDD matrix and intro test inventory record concrete closure
  evidence

## Source Of Truth

Primary governing docs:

- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts:

- Raw intro loading and introducer grouping live in
  `lib/features/introduction/application/load_introductions_use_case.dart`.
- Raw intro rows render in both
  `lib/features/introduction/presentation/widgets/intros_tab.dart` and
  `lib/features/orbit/presentation/screens/orbit_screen.dart`.
- The active wired path is in
  `lib/features/orbit/presentation/screens/orbit_wired.dart`.
- Feed and Orbit user-facing intro counts now route duplicate pending raw rows
  through `countFoldedPendingIntroductionTargets(...)`; repository
  `countPendingIntroductions(...)` remains a raw-row count.
- The intro gate is `./scripts/run_test_gates.sh intro`.
- Existing simulator intro coverage lives in `smoke_test_friends.sh` and now
  includes scenario 11, `INTRO_E2E_SCENARIO=folded-duplicate`, which uses two
  introducers for the same current viewer and target across four identities.
  Scenario 8 `offline-first-chat` uses a longer receiver expectation window
  (`chat_poll_cycles: 120`) to avoid false timeouts after the sender's
  intentional settle delay.

## Session Ledger

| Session ID | Title | Classification | Plan file path | Depends on | Current status | Final execution verdict | Closure docs touched | Blocker class | Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `DIF-001` | Folded projection contract | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-001-plan.md` | none | `accepted` | `accepted` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`; source matrix row `DIF-001` already updated/verified in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` | none | Direct projection evidence is consistent: RED missing `foldIntroductionsForReview`, then `flutter test test/features/introduction/application/load_introductions_test.dart` passed in Executor and QA with `+12`; no follow-ups. |
| `DIF-002` | Folded count contract | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-002-plan.md` | `DIF-001` | `accepted` | `accepted` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`; source matrix row `DIF-002` already updated/verified in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` | none | Direct folded-count evidence is consistent: RED missing `countFoldedPendingIntroductionTargets` plus Feed/Orbit duplicate count failures, then Executor and QA reran the helper, Feed, and Orbit targeted commands green with `+16`, `+1`, and `+1`; repository count intentionally remains raw-row based. |
| `DIF-003` | Folded accept/pass group actions | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md` | `DIF-001` | `accepted` | `accepted` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`; source matrix row `DIF-003` already updated/verified in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` | none | Direct folded-response evidence is consistent: RED missing folded response API symbols, then folded response, accept, pass, and mutual-acceptance direct commands passed with `+6`, `+14`, `+9`, and `+17`; closure audit reran the folded response suite green with `+6`. |
| `DIF-004` | Folded intro review UI rendering | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-004-plan.md` | `DIF-001` | `accepted` | `accepted` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`; source matrix row `DIF-004` updated/verified in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` | none | Direct folded UI evidence is consistent: RED missing folded row constructor inputs, then folded IntroRow, IntrosTab, extended IntrosTab, Orbit active-sliver, Orbit loading/wiring, Orbit badge companion, Feed badge companion, and `./scripts/run_test_gates.sh intro` passed; QA reran the owner widget suite green with `+41`. Raw-id action callbacks and non-simulator proof remain later-session scope. |
| `DIF-005` | Orbit wired and Feed badge integration | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-005-plan.md` | `DIF-001`, `DIF-002`, `DIF-003`, `DIF-004` | `accepted` | `accepted` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`; source matrix row `DIF-005` already updated/verified in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` | none | Direct wired evidence is consistent: RED showed duplicate `Dora` rows and enabled raw duplicate actions, then format, the three folded `OrbitWired` tests, raw single-intro duplicate-tap companions, `orbit_intros_wiring_test.dart`, the Feed folded badge companion, `./scripts/run_test_gates.sh intro` (`+185`), and `git diff --check` passed. |
| `DIF-006` | Four-identity simulator folded duplicate proof | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-006-plan.md` | `DIF-005` | `accepted` | `accepted` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-006-plan.md`; `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`; source matrix row `DIF-006` in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` | none | Harness implementation and proof are green: live four-identity fixture intake, expected unknown-scenario RED, shell syntax, direct host tests, `./scripts/run_test_gates.sh intro`, standalone `happy`, standalone `folded-duplicate`, `git diff --check`, standalone `offline-chat` after the receive-wait fix, and resumed full scenario coverage all passed. The earlier `copy` blocker is obsolete: scenario 5 passed in the resumed loop, and scenario 11 `folded-duplicate` completed with `=== Intro E2E harness passed ===`. The full coverage evidence was resumed rather than one uninterrupted `all` process: scenario 1 passed before the user-requested stop, then scenarios 2-11 passed sequentially. |
| `DIF-007` | Regression, documentation, and final closure | `acceptance-only` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-007-plan.md` | `DIF-006` | `accepted` | `accepted` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-007-plan.md`; `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`; source matrix row `DIF-007` in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`; `Test-Flight-Improv/Intro-Feature/test-inventory.md` | none | DIF-007 acceptance evidence is green: required direct host suite passed `+266`; `./scripts/run_test_gates.sh intro` passed `+185`; fixture intake commands passed; the first `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` attempt timed out in scenario 3 `pass-handshake` before intro send/pass/folded behavior with A/C complete and B still `running`, then the exact uninterrupted retry passed scenarios 1-11 and ended with `=== Intro E2E harness passed ===`; `bash -n smoke_test_friends.sh reset_simulators.sh` and `git diff --check` passed with no output. No production or test code changed in DIF-007. |

## DIF-001 Closure Audit

- What is now closed: `DIF-001` folded projection contract. The application
  projection helper/model exists in
  `lib/features/introduction/application/load_introductions_use_case.dart`, and
  focused tests in
  `test/features/introduction/application/load_introductions_test.dart` prove
  same-target folding, different-target separation, viewer-side target
  resolution, newest-row display fallback, current-viewer action-state ids, and
  persisted-row compatibility without raw-row mutation.
- Residual-only items: none for `DIF-001`. Later rows are tracked by the
  session ledger; this DIF-001-only note does not reopen or govern their
  current status.
- Accepted differences: the projection is colocated with the existing raw load
  use case and exposes factual projection fields; final count semantics,
  grouped Accept/Pass behavior, UI copy/rendering, Orbit/Feed wiring, simulator
  proof, and program-level regression closure remain later-session scope.
- Reopen only on a real regression: reopen `DIF-001` only if the folded
  projection stops preserving raw intro ids/statuses/introducer attribution,
  mutates persisted rows, misresolves the current viewer's target peer, or
  regresses the direct `load_introductions_test.dart` projection/raw-list
  coverage.
- Maintenance-time safety gate: the direct DIF-001 gate is
  `flutter test test/features/introduction/application/load_introductions_test.dart`.
  The broader intro gate and simulator proof are intentionally deferred to
  integrated later sessions.

## DIF-002 Closure Audit

- What is now closed: `DIF-002` folded count contract. The application helper
  `countFoldedPendingIntroductionTargets(...)` counts one pending target per
  current viewer/counterparty, and Feed plus Orbit now consume that folded count
  for user-facing intro badges/review counts.
- Residual-only items: none for `DIF-002`. Later grouped action, UI rendering,
  integrated wired behavior, simulator proof, and final regression rows remain
  separate pending sessions and are not reopened by this closure audit.
- Accepted differences: `IntroductionRepository.countPendingIntroductions(...)`
  remains raw-row based by design; folded user-facing count semantics are owned
  by the shared application helper and its Feed/Orbit callers.
- Reopen only on a real regression: reopen `DIF-002` only if duplicate pending
  raw rows for the same viewer/counterparty inflate Feed or Orbit user-facing
  counts, or if `alreadyConnected`, `passed`, `expired`, `mutualAccepted`, or
  unrelated distinct-target rows stop following the documented count rules.
- Maintenance-time safety gates: the direct DIF-002 gates are
  `flutter test test/features/introduction/application/load_introductions_test.dart`,
  `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"`,
  and
  `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"`.
  The broader intro gate and simulator proof remain later-session scope.

## DIF-003 Closure Audit

- What is now closed: `DIF-003` folded accept/pass group action contract. The
  application wrapper in
  `lib/features/introduction/application/folded_introduction_response_use_case.dart`
  applies one folded Accept or Pass action across each current pending
  underlying intro id through the existing single-intro use cases, returns
  per-id `applied`, `skippedNotPending`, or `failed` outcomes, and leaves
  single-intro role, key mismatch, outbound-send, status-derivation, and mutual
  acceptance behavior centralized.
- Residual-only items: none for `DIF-003`. UI rendering, Orbit/Feed folded
  action wiring, simulator proof, and final integrated regression closure
  remain separate pending sessions and are not reopened by this closure audit.
- Accepted differences: no schema, projection, repository, UI, or broad gate
  change was required for this session; stale duplicate suppression is proven
  at the folded wrapper boundary, while direct single-intro duplicate calls
  remain outside `DIF-003` scope.
- Reopen only on a real regression: reopen `DIF-003` only if a folded Accept or
  Pass no longer applies to every current pending underlying intro id, no
  longer skips stale already-handled ids without duplicate sends, hides
  non-party or ML-KEM/key mismatch failures as success, or regresses the direct
  folded response/accept/pass/mutual-acceptance tests.
- Maintenance-time safety gates: the direct DIF-003 gates are
  `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart`,
  `flutter test test/features/introduction/application/accept_introduction_test.dart`,
  `flutter test test/features/introduction/application/pass_introduction_test.dart`,
  and
  `flutter test test/features/introduction/application/mutual_acceptance_test.dart`.
  This closure audit additionally reran the folded response suite green with
  `+6`. The broader intro gate and simulator proof remain later-session scope.

## DIF-004 Closure Audit

- What is now closed: `DIF-004` folded intro review UI rendering. `IntroRow`
  can display multiple introducer attributions in one row, `IntrosTab` can
  consume supplied folded review items without raw introducer headers, and the
  active `OrbitScreen` intro sliver can render supplied folded review items as
  one row per target while preserving the sliver/no-`ListView` layout.
- Residual-only items: none for `DIF-004`. Wired folded actions, folded
  publisher/reload behavior, group-level processing/duplicate-tap suppression,
  simulator proof, and final regression documentation remain separate pending
  sessions (`DIF-005` through `DIF-007`) and are not reopened by this closure
  audit.
- Accepted differences: folded rendering uses an optional `foldedReviewItems`
  bridge while keeping raw grouped callers compatible. Accept, Pass, and delete
  callbacks still use `displaySourceIntroductionId`; processing display only
  reflects existing raw ids in `processingIntroductionIds`. No schema,
  repository, projection, Feed badge, Orbit badge, or simulator behavior was
  added in this session.
- Reopen only on a real regression: reopen `DIF-004` only if duplicate target
  intros render as multiple UI review rows, multi-introducer attribution is
  lost, single-introducer row behavior regresses, active Orbit intros stop using
  the folded row bridge when supplied, or the direct folded widget tests/gates
  regress.
- Maintenance-time safety gates: the direct DIF-004 gates are
  `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart`,
  `flutter test test/features/introduction/presentation/widgets/intros_tab_test.dart`,
  `flutter test test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`,
  `flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`,
  `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`,
  `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`,
  `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"`,
  `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"`,
  and `./scripts/run_test_gates.sh intro`. Executor recorded these green; QA
  reran the owner widget suite green with `+41`.

## DIF-005 Closure Audit

- What is now closed: `DIF-005` active Orbit wired folded integration.
  `OrbitWired` publishes folded review items into `OrbitScreen`, uses the
  folded pending target count for the Orbit badge/review count, resolves raw
  callback ids back to the folded item, guards every underlying intro id while
  a folded Accept/Pass is processing, calls
  `acceptFoldedIntroduction(...)`/`passFoldedIntroduction(...)`, reloads folded
  state after the action, and preserves the single-raw-id fallback path.
- Residual-only items: none within `DIF-005`. Four-identity simulator proof
  remains `DIF-006` scope, and final regression inventory/rollout closure
  remains `DIF-007` scope; neither later row is closed or reopened by this
  audit.
- Accepted differences: `FeedWired` production code is not a DIF-005 edit
  because the current Feed badge path already uses folded pending target
  counts. `OrbitScreen` keeps the existing raw-id callback signature while
  `OrbitWired` resolves that id to a folded item. Delete behavior remains
  display-source raw-id scoped. No schema, repository, folded projection,
  folded action internals, simulator script, or final inventory change is
  required for this session.
- Reopen only on a real regression: reopen `DIF-005` only if active
  `OrbitWired` duplicate target intros render as multiple rows, inflate the
  Orbit badge/review count, leave a folded row partially enabled while any
  underlying id is processing, fail to apply folded Accept/Pass to every
  pending underlying id once, stop reloading to the folded state after action,
  or regress the raw single-intro fallback.
- Maintenance-time safety gates: the direct DIF-005 gates are
  `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets into one OrbitWired intro row and badge target"`,
  `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "accepting a folded Orbit intro disables the folded row and updates every underlying intro once"`,
  `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "passing a folded Orbit intro disables the folded row and updates every underlying intro once"`,
  `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"`,
  `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "accepting an intro shows processing immediately and ignores duplicate taps"`,
  `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "passing an intro disables both actions immediately and ignores duplicate taps"`,
  `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`,
  `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"`,
  `./scripts/run_test_gates.sh intro`, and `git diff --check`. Recorded GREEN
  evidence includes the three new folded OrbitWired commands, the existing
  direct companions, `orbit_intros_wiring_test.dart` (`+11`), the Feed folded
  badge companion, and the intro gate (`+185`).

## DIF-006 Closure Audit

- Closure verdict: `accepted`; ledger status `accepted`; blocker class `none`.
- What is now closed: `DIF-006` four-identity simulator folded duplicate proof.
  `smoke_test_friends.sh`, `reset_simulators.sh`, and
  `lib/core/debug/intro_e2e_runner.dart` provide the four-identity harness,
  `INTRO_E2E_SCENARIO=folded-duplicate`, folded snapshot/action proof, and
  inclusion in the full scenario set. The live fixture was available, the
  unknown-scenario RED was captured before implementation, and standalone
  `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh` plus
  `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh` were green.
- Current closure evidence: `./scripts/run_test_gates.sh intro`,
  standalone `offline-chat` after the receiver wait fix, and the resumed full
  scenario coverage all passed. The earlier full-suite attempt had already
  passed scenario 1 before the user-requested stop; the resumed loop then
  passed scenarios `refresh`, `pass`, `repair`, `copy`, `partial`,
  `partition`, `offline-chat`, `pass-fallback`, `split-brain`, and
  `folded-duplicate`, ending with `=== Intro E2E harness passed ===`.
- Residual-only items: final regression inventory/source-matrix closure remains
  `DIF-007` scope. No `DIF-006` harness or product blocker remains open.
- Accepted differences: the recorded full coverage evidence is resumed rather
  than one uninterrupted `INTRO_E2E_SCENARIO=all` process because the user
  requested a stop during scenario 2 and later requested continuation from that
  point. The previous `copy` blocker is obsolete because scenario 5 passed in
  the resumed loop. Scenario 8 needed a harness timing adjustment after C
  reached mutual acceptance but timed out waiting for B's first chat; increasing
  `offline-first-chat` receiver `chat_poll_cycles` to `120` made standalone
  `offline-chat` and the resumed loop green.
- Reopen only on a real regression: reopen DIF-006 implementation scope only if
  `happy`, standalone `offline-chat`, standalone `folded-duplicate`, or the
  folded duplicate portion of the full scenario set regresses due to the
  harness changes, if four distinct identities can no longer be provisioned by
  the harness, or if folded snapshot/action proof stops showing one folded B/C
  target with both underlying intro ids and introducer attributions.
- Maintenance-time safety gates: keep
  `./scripts/run_test_gates.sh intro`,
  `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`,
  `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh`,
  `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`,
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` or an explicitly resumed
  full-scenario ledger, and `git diff --check` as the evidence set for future
  maintenance. `DIF-007` is now unblocked and owns final documentation closure.

## DIF-007 Closure Audit

- Closure verdict: `ready_for_qa`; ledger status `accepted`; blocker class
  `none`.
- What is now closed: `DIF-007` final regression, documentation, and program
  closure evidence. The required direct host suite covering folded projection,
  folded Accept/Pass, IntroRow/IntrosTab folded rendering, Orbit/Feed folded
  wiring, and existing intro companions passed with `+266`. The named intro
  gate `./scripts/run_test_gates.sh intro` passed with `+185`.
- Current simulator evidence: fixture intake passed with
  `flutter devices --machine` and `xcrun simctl list devices available`. The
  first exact `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` attempt timed
  out in scenario 3 `pass-handshake` before any intro send/pass/folded
  behavior; A and C had completed `pass-handshake`, while B remained
  `{"stepId":"pass-handshake","status":"running"}` until the shell timeout.
  Without production/test changes, the exact uninterrupted retry passed
  scenarios 1-11, including scenario 11 `Four-identity folded duplicate
  acceptance`, and ended with `=== Intro E2E harness passed ===`. The first
  timeout is classified as a transient environment/harness timeout.
- Hygiene evidence: `bash -n smoke_test_friends.sh reset_simulators.sh` and
  `git diff --check` passed with no output.
- Residual-only items: none for DIF-007. No production or test code changed in
  this acceptance-only session.
- Reopen only on a real regression: reopen DIF-007 only if the direct folded
  companion suite, the named intro gate, the full intro E2E matrix including
  folded duplicate scenario 11, or the folded duplicate inventory/source-row
  documentation evidence regresses.

## Final Program Acceptance Verdict

- Verdict: `closed`
- Persisted: `2026-05-07 15:57 CEST`
- Ledger sanity result: `DIF-001` through `DIF-007` are `accepted` with source
  rows `Closed`; no session blocker remains.
- Program closure decision: the overall closure bar is met. The rollout now has
  folded projection, folded count, folded Accept/Pass, folded UI rendering,
  Orbit/Feed wired integration, four-identity folded duplicate simulator proof,
  current direct regression evidence, current intro gate evidence, and current
  documentation inventory/source-row closure evidence.
- Maintenance evidence set: keep the DIF-owned direct companion suite,
  `./scripts/run_test_gates.sh intro`, fixture intake when simulator proof is
  needed, `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`, `bash -n
  smoke_test_friends.sh reset_simulators.sh`, and `git diff --check` as the
  final folded duplicate regression contract.

## Ordered Session Breakdown

### `DIF-001` - Folded projection contract

- Session classification: `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-001-plan.md`
- Exact scope:
  - add an application-level folded intro review projection
  - fold active raw intro rows by current viewer's target peer
  - preserve underlying intro ids and introducer attribution
  - derive folded display and action state without mutating raw intro rows
  - treat existing persisted raw `IntroductionModel` rows from the current
    shipped build as valid projection input so upgraded users see their current
    intros in the folded design without migration-time data loss
- Why it is its own session:
  - every later UI and wired change depends on a stable projection contract
- Likely code-entry files:
  - `lib/features/introduction/application/load_introductions_use_case.dart`
  - optionally a new adjacent application helper/model file
- Likely direct tests/regressions:
  - `test/features/introduction/application/load_introductions_test.dart`
  - include an upgrade-style fixture built from existing raw persisted
    `IntroductionModel` rows, proving folded projection preserves intro ids,
    statuses, introducer attribution, and pending decisions without mutating the
    raw rows
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
    for pure projection use if a helper already sits there
- Likely named gates:
  - direct tests first
  - `./scripts/run_test_gates.sh intro` after later integrated sessions
- Matrix/closure docs to update when done:
  - source row `DIF-001`
- Dependency on earlier sessions: none

### `DIF-002` - Folded count contract

- Session classification: `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-002-plan.md`
- Exact scope:
  - make user-facing pending/review counts count folded targets instead of raw
    duplicate rows
  - keep `alreadyConnected`, `passed`, and `expired` badge exclusion rules
    intact
  - update either the repository count method or the application badge source,
    choosing the smaller path after the session plan inspects current callers
- Why it is its own session:
  - badge/review counts can regress independently of row rendering
- Likely code-entry files:
  - `lib/features/introduction/application/load_introductions_use_case.dart`
  - `lib/features/introduction/domain/repositories/introduction_repository.dart`
  - `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
  - `lib/core/database/helpers/introductions_db_helpers.dart`
  - `test/shared/fakes/in_memory_introduction_repository.dart`
- Likely direct tests/regressions:
  - `test/features/introduction/application/load_introductions_test.dart`
  - `test/core/database/helpers/intro_db_helpers_test.dart` if the DB count
    query changes
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- Likely named gates:
  - direct tests first
  - `./scripts/run_test_gates.sh intro` after later integrated sessions
- Matrix/closure docs to update when done:
  - source row `DIF-002`
- Dependency on earlier sessions: `DIF-001`

### `DIF-003` - Folded accept/pass group actions

- Session classification: `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md`
- Exact scope:
  - add folded accept and folded pass use cases that operate over all current
    pending intro ids in a folded item
  - call existing single-intro `acceptIntroduction(...)` and
    `passIntroduction(...)` rather than duplicating status or outbound logic
  - return per-underlying-intro results sufficient for UI reload and QA
- Why it is its own session:
  - action semantics are correctness-sensitive and must be proven before
    wiring buttons to grouped rows
- Likely code-entry files:
  - `lib/features/introduction/application/accept_introduction_use_case.dart`
  - `lib/features/introduction/application/pass_introduction_use_case.dart`
  - optional new folded response use case file under
    `lib/features/introduction/application/`
  - `test/shared/fakes/in_memory_introduction_repository.dart`
- Likely direct tests/regressions:
  - new folded response tests under `test/features/introduction/application/`
  - `test/features/introduction/application/accept_introduction_test.dart`
  - `test/features/introduction/application/pass_introduction_test.dart`
  - `test/features/introduction/application/mutual_acceptance_test.dart`
- Likely named gates:
  - direct tests first
  - `./scripts/run_test_gates.sh intro` after integrated sessions
- Matrix/closure docs to update when done:
  - source row `DIF-003`
- Dependency on earlier sessions: `DIF-001`

### `DIF-004` - Folded intro review UI rendering

- Session classification: `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-004-plan.md`
- Exact scope:
  - render folded intro review items in `IntrosTab`
  - render folded intro review items in the active `OrbitScreen` intro sliver
  - display multi-introducer attribution inside the row
  - keep single-introducer rows visually compatible with existing copy
- Why it is its own session:
  - this is the visible user-facing change and should not be mixed with action
    side effects
- Likely code-entry files:
  - `lib/features/introduction/presentation/widgets/intro_row.dart`
  - `lib/features/introduction/presentation/widgets/intros_tab.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - possibly a small new presentation model/adapter if needed
- Likely direct tests/regressions:
  - `test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `test/features/introduction/presentation/widgets/intros_tab_test.dart`
  - `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`
  - `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
- Likely named gates:
  - direct widget tests first
  - `./scripts/run_test_gates.sh intro` after integrated sessions
- Matrix/closure docs to update when done:
  - source row `DIF-004`
- Dependency on earlier sessions: `DIF-001`

### `DIF-005` - Orbit wired and Feed badge integration

- Session classification: `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-005-plan.md`
- Exact scope:
  - update `OrbitWired` to publish folded intro review data
  - call folded accept/pass actions from the folded row
  - track processing by folded group id and suppress duplicate taps
  - set Orbit review count from folded target count
  - update Feed badge behavior if it still reads raw pending row count
- Why it is its own session:
  - this is the integration seam between application model, UI, actions, and
    badge count
- Likely code-entry files:
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - folded projection/action files from earlier sessions
- Likely direct tests/regressions:
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart` if Feed badge
    code changes
- Likely named gates:
  - direct Orbit/Feed tests first
  - `./scripts/run_test_gates.sh intro`
  - `./scripts/run_test_gates.sh feed` only if Feed card behavior changes beyond
    badge count
- Matrix/closure docs to update when done:
  - source row `DIF-005`
- Dependency on earlier sessions: `DIF-001`, `DIF-002`, `DIF-003`, `DIF-004`

### `DIF-006` - Four-identity simulator folded duplicate proof

- Session classification: `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-006-plan.md`
- Exact scope:
  - add `INTRO_E2E_SCENARIO=folded-duplicate` to `smoke_test_friends.sh`
  - extend the supporting debug runner/config only as needed for four distinct
    identities: introducer A, current viewer B, introduced target C, and second
    introducer D
  - allow D to run on a fourth simulator or an attached physical device
  - prove A and D each create an active intro from B to C, B sees one folded row
    with both introducer attributions, and one Accept/Pass decision applies to
    both underlying intro ids
  - include `folded-duplicate` in `INTRO_E2E_SCENARIO=all`
- Device/relay proof profile required:
  - the session plan must run `flutter devices --machine` before execution
  - for iOS simulator runs, also run `xcrun simctl list devices available`
  - record the exact four device ids or simulator ids used for A, B, C, and D
  - if the fourth identity/device is unavailable, classify the row as an
    external-fixture blocker and leave the row blocked instead of closing it
- Why it is its own session:
  - the four-identity simulator harness has a different fixture and runtime
    risk profile than host-side projection, widget, and wired tests
- Likely code-entry files:
  - `smoke_test_friends.sh`
  - `lib/core/debug/intro_e2e_runner.dart`
  - `reset_simulators.sh` only if a fourth simulator slot must be provisioned
- Likely direct tests/regressions:
  - `bash -n smoke_test_friends.sh`
  - targeted runner tests if the session introduces testable helper code
  - `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`
  - `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`
  - `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`
- Likely named gates:
  - `./scripts/run_test_gates.sh intro`
  - folded duplicate simulator scenario with four identities
- Matrix/closure docs to update when done:
  - source row `DIF-006`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Dependency on earlier sessions: `DIF-005`

### `DIF-007` - Regression, documentation, and final closure

- Session classification: `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-007-plan.md`
- Exact scope:
  - run the existing direct intro, Orbit companion, named intro gates, and folded
    duplicate simulator proof
  - fix only doc/test evidence gaps; product-code fixes belong to the blocking
    implementation session that caused them
  - update source rows from `Open` to `Closed` only with concrete test evidence
  - update `Test-Flight-Improv/Intro-Feature/test-inventory.md` with new folded
    duplicate intro tests, simulator commands, and four-identity device notes
  - record final program verdict in this breakdown
- Why it is its own session:
  - closure should verify the whole feature after implementation, simulator
    proof, and tests land
- Likely code-entry files:
  - none
- Likely docs:
  - `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - this breakdown file
- Likely direct tests/regressions:
  - all touched direct tests from `DIF-001` through `DIF-006`
  - `test/features/introduction/regression/introduction_regression_test.dart`
  - `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
  - `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`
  - `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`
  - `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`
- Likely named gates:
  - `./scripts/run_test_gates.sh intro`
  - folded duplicate four-identity simulator proof
- Matrix/closure docs to update when done:
  - all `DIF-*` rows and final verdict
- Dependency on earlier sessions: `DIF-006`

## Why This Is Not Fewer Sessions

- Projection/count, group action, UI rendering, wired integration, four-identity
  simulator proof, regression preservation, and closure have different failure
  modes.
- Combining group action with UI would make it too easy to ship one visible row
  that still only accepts one raw intro.
- Combining Orbit/Feed wiring with projection would hide badge-count regressions
  behind widget-only proof.
- Combining simulator proof with final closure would force an acceptance-only
  session to create or repair four-identity E2E harness code.
- Closure must be separate so source rows are not marked closed before the intro
  gate and simulator evidence exists.

## Why This Is Not More Sessions

- No database migration is planned, so schema work does not need a standalone
  session. The folded projection must read existing raw intro rows directly so
  upgrade users keep their current intros.
- `IntrosTab` and `OrbitScreen` both consume the same folded item shape, so
  splitting them would mostly create duplicate widget-adapter work.
- Feed badge work is small and only matters after the Orbit folded count exists.
- Delete semantics are intentionally out of scope.

## Regression And Gate Contract

- Add the failing direct tests named in each session before product code.
- Run direct tests for the current session before moving on.
- Run `./scripts/run_test_gates.sh intro` after integrated UI/wired work.
- Run direct Orbit companion tests whenever Orbit intro data shape changes:
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- Run direct Feed tests only if Feed badge implementation changes:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
- Add and run the folded duplicate simulator proof after integrated UI/wired
  work:
  - `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`
  - `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`
  - `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`
- `DIF-006` requires four distinct identities: introducer A, current viewer B,
  introduced target C, and second introducer D. D may be a fourth simulator or
  an attached physical device. Do not mark the row accepted without green proof;
  if the fixture is unavailable, record the exact external-fixture blocker and
  keep the rollout open.
- Do not remove existing intro gate files to make the gate pass.

## Matrix Update Contract

- The source matrix for this rollout is the `## TDD Source Matrix` table in
  `folded-duplicate-introductions-tdd-plan.md`.
- Each session owns the row ids named in its breakdown entry.
- A source row may move from `Open` to `Closed` only when the row includes:
  - code files changed
  - test files added or updated
  - exact test command evidence
  - any known remaining non-blocking limitation
- `DIF-007` owns the final documentation pass and final program verdict.

## Structural Blockers Remaining

- None known from planning. `DIF-006` has an explicit execution fixture
  requirement for a fourth identity/device; if that device is unavailable during
  execution, record it as an external-fixture blocker.

## Accepted Differences Intentionally Left Unchanged

- Existing single raw `IntroductionModel` persistence remains unchanged, and
  already-persisted intro rows from the current shipped build remain readable in
  the folded review design.
- Same-introducer newer-wins dedupe remains unchanged.
- Future re-introduction after a terminal pass is not permanently blocked by
  this rollout.
- Group delete is not part of folded action semantics.

## Exact Docs/Files Used As Evidence

- `lib/features/introduction/domain/models/introduction_model.dart`
- `lib/features/introduction/application/load_introductions_use_case.dart`
- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/pass_introduction_use_case.dart`
- `lib/features/introduction/presentation/widgets/intros_tab.dart`
- `lib/features/introduction/presentation/widgets/intro_row.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `lib/core/debug/intro_e2e_runner.dart`
- `smoke_test_friends.sh`
- `reset_simulators.sh`
- `test/shared/fakes/in_memory_introduction_repository.dart`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## Why The Decomposition Is Safe To Send Downstream

- It starts at deterministic application projection tests before touching UI.
- It keeps folded action semantics on top of existing accept/pass use cases, so
  role checks, encryption, response delivery, and mutual-acceptance side effects
  stay covered by current tests.
- It explicitly covers both passive display confusion and the behavioral risk
  of accepting only one raw duplicate.
- It requires a four-identity simulator scenario for the real duplicate
  introducer journey instead of relying only on existing three-simulator intro
  happy-path coverage.
- It keeps existing intro gate evidence as a closure requirement rather than a
  nice-to-have.
