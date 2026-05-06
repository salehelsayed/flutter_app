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
  closure row are closed with evidence.

## Downstream Execution Path

For each unresolved session, run through:

1. `$implementation-plan-orchestrator`
2. `$implementation-execution-qa-orchestrator`
3. `$implementation-closure-audit-orchestrator`

After all runnable sessions, run final program acceptance/closure.

## Recommended Plan Count

- `6`
- Smallest safe split:
  - `5` implementation-ready sessions
  - `1` acceptance-only documentation and final-closure session
- No session should execute in parallel. The UI and wired sessions depend on
  the folded application model and group action contract.

## Overall Closure Bar

The rollout is closed only when all of the following are true:

- a current user sees one intro review row per target peer, even when multiple
  introducers produced separate active introduction records
- the folded row visibly names multiple introducers
- one Accept/Pass action applies to every current underlying pending intro in
  the fold
- Orbit and Feed user-facing badge/review counts count folded targets, not raw
  duplicate rows
- existing single-intro behavior, already-connected behavior, pass/expiry
  terminal behavior, and same-introducer newer-wins dedupe still pass
- `./scripts/run_test_gates.sh intro` passes after the implementation
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
- Feed badge count currently reads
  `IntroductionRepository.countPendingIntroductions(...)` in
  `lib/features/feed/presentation/screens/feed_wired.dart`.
- The intro gate is `./scripts/run_test_gates.sh intro`.

## Session Ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Initial status |
| --- | --- | --- | --- | --- | --- |
| `DIF-001` | Folded projection contract | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-001-plan.md` | none | `pending` |
| `DIF-002` | Folded count contract | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-002-plan.md` | `DIF-001` | `pending` |
| `DIF-003` | Folded accept/pass group actions | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-003-plan.md` | `DIF-001` | `pending` |
| `DIF-004` | Folded intro review UI rendering | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-004-plan.md` | `DIF-001` | `pending` |
| `DIF-005` | Orbit wired and Feed badge integration | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-005-plan.md` | `DIF-001`, `DIF-002`, `DIF-003`, `DIF-004` | `pending` |
| `DIF-006` | Regression, documentation, and final closure | `acceptance-only` | `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-006-plan.md` | `DIF-005` | `pending` |

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
- Why it is its own session:
  - every later UI and wired change depends on a stable projection contract
- Likely code-entry files:
  - `lib/features/introduction/application/load_introductions_use_case.dart`
  - optionally a new adjacent application helper/model file
- Likely direct tests/regressions:
  - `test/features/introduction/application/load_introductions_test.dart`
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

### `DIF-006` - Regression, documentation, and final closure

- Session classification: `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-006-plan.md`
- Exact scope:
  - run the existing direct intro, Orbit companion, and named intro gates
  - fix only doc/test evidence gaps; product-code fixes belong to the blocking
    implementation session that caused them
  - update source rows from `Open` to `Closed` only with concrete test evidence
  - update `Test-Flight-Improv/Intro-Feature/test-inventory.md` with new folded
    duplicate intro tests and commands
  - record final program verdict in this breakdown
- Why it is its own session:
  - closure should verify the whole feature after implementation and tests land
- Likely code-entry files:
  - none
- Likely docs:
  - `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - this breakdown file
- Likely direct tests/regressions:
  - all touched direct tests from `DIF-001` through `DIF-005`
  - `test/features/introduction/regression/introduction_regression_test.dart`
  - `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh intro`
- Matrix/closure docs to update when done:
  - all `DIF-*` rows and final verdict
- Dependency on earlier sessions: `DIF-005`

## Why This Is Not Fewer Sessions

- Projection/count, group action, UI rendering, wired integration, regression
  preservation, and closure have different failure modes.
- Combining group action with UI would make it too easy to ship one visible row
  that still only accepts one raw intro.
- Combining Orbit/Feed wiring with projection would hide badge-count regressions
  behind widget-only proof.
- Closure must be separate so source rows are not marked closed before the intro
  gate evidence exists.

## Why This Is Not More Sessions

- No database migration is planned, so schema work does not need a standalone
  session.
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
- `DIF-006` owns the final documentation pass and final program verdict.

## Structural Blockers Remaining

- None known from planning.

## Accepted Differences Intentionally Left Unchanged

- Existing single raw `IntroductionModel` persistence remains unchanged.
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
- It keeps existing intro gate evidence as a closure requirement rather than a
  nice-to-have.
