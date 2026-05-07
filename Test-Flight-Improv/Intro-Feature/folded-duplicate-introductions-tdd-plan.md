# Folded Duplicate Introductions TDD Plan

Status: planning-ready
Date: 2026-05-05

## Problem

When the same target user is introduced to the current user by more than one
introducer, the Intros surface currently renders one row per introduction
record. In the screenshot scenario, `aboza` appears twice because the current
user received an intro to `aboza` from two different friends. That makes the
flow look like two different decisions and can require duplicate Accept or Pass
taps.

The feature upgrade is to make duplicate active introductions reviewable as one
decision per target person. The row must still explain that multiple friends
introduced the same person.

## Current Repo Evidence

- `IntroductionModel` stores one row per introduction id with
  `introducerId`, `recipientId`, `introducedId`, per-party statuses, and an
  overall status in `lib/features/introduction/domain/models/introduction_model.dart`.
- `loadIntroductionsForUser(...)` currently returns raw pending rows and
  `groupByIntroducer(...)` groups them by `introducerId` in
  `lib/features/introduction/application/load_introductions_use_case.dart`.
- `IntrosTab` renders a sender-grouped list with one `IntroRow` for each raw
  `IntroductionModel` in
  `lib/features/introduction/presentation/widgets/intros_tab.dart`.
- The active Orbit screen has its own sliver implementation that also expands
  `groupedIntros` into one raw `IntroRow` per model in
  `lib/features/orbit/presentation/screens/orbit_screen.dart`.
- `OrbitWired` stores `_groupedIntros`, sets `_introsCount = pending.length`,
  and accepts or passes one `introductionId` at a time in
  `lib/features/orbit/presentation/screens/orbit_wired.dart`.
- `FeedWired` uses `IntroductionRepository.countPendingIntroductions(...)` for
  the Orbit badge in `lib/features/feed/presentation/screens/feed_wired.dart`.
- The canonical intro gate is `./scripts/run_test_gates.sh intro`, defined in
  `Test-Flight-Improv/test-gate-definitions.md`.
- `Test-Flight-Improv/Intro-Feature/test-inventory.md` confirms broad existing
  intro coverage. This plan must add focused regressions rather than replacing
  the existing intro suite.
- Existing three-simulator intro E2E coverage lives in `smoke_test_friends.sh`,
  including `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh` and
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`. This rollout must add a
  folded-duplicate simulator scenario instead of treating the current scenarios
  as proof of the new four-identity duplicate-introducer behavior.

## Product Contract

### Fold Key

For a current viewer `ownPeerId`, each active introduction maps to exactly one
counterparty:

```dart
otherPeerId = intro.recipientId == ownPeerId
    ? intro.introducedId
    : intro.recipientId;
```

Rows are foldable when:

- the current viewer is either `recipientId` or `introducedId`
- the resolved `otherPeerId` is the same
- the row is still part of the active review loader result:
  `pending` or `alreadyConnected`

The fold crosses introducers. It does not merge unrelated counterparties.

### Display Contract

- Show one review row per `otherPeerId`.
- Single introducer copy remains effectively unchanged:
  `Introduced by Ibra`.
- Two introducers use explicit copy:
  `Introduced by Ibra and AlMir3uD`.
- Three or more introducers use bounded copy:
  `Introduced by Ibra + 2 others`.
- The row still uses the target person's username/avatar as the primary row
  identity.
- The old sender-grouped visual model must not cause duplicates. The active
  review surface should become target-grouped or flat target-first, with
  introducer attribution inside the row.

### Action Contract

- A folded row exposes only one Accept/Pass decision.
- Accept applies the current user's accepted response to every underlying
  active pending intro in that fold where the current user's party status is
  still `pending`.
- Pass applies the current user's passed response to every underlying active
  pending intro in that fold where the current user's party status is still
  `pending`.
- Underlying single-intro accept/pass use cases remain the source of truth for
  role checks, key mismatch checks, outbound response delivery, status
  derivation, and mutual-acceptance side effects.
- If one underlying intro in the fold has already been accepted by this user,
  the folded row must not ask them to accept again. It should show the existing
  waiting/connected/already-connected state derived from the fold.
- If any underlying intro in the fold reaches `mutualAccepted`, contact
  creation remains idempotent through the existing mutual-acceptance path.
- Duplicate taps are suppressed for the whole folded row while any underlying
  intro action is processing.

### Count Contract

- User-facing intro review count and the Orbit badge count should count folded
  actionable targets, not raw duplicate rows.
- `alreadyConnected` remains visible where existing behavior requires it, but
  it must not inflate pending-action badge counts.
- Existing single-intro count behavior must remain unchanged for non-duplicate
  data.

### Upgrade Contract

- Existing persisted raw `IntroductionModel` rows from the current shipped build
  remain valid input for the folded projection.
- After app update and first launch, users with already-persisted pending intros
  must see those intros in the folded review design without losing intro ids,
  statuses, introducer attribution, or pending decisions.
- No migration may delete, merge, or rewrite raw introduction rows just to create
  the folded design; folding is a read/projection behavior over the existing
  rows unless a later explicit migration plan proves otherwise.

### Simulator E2E Contract

- Add a dedicated folded duplicate E2E scenario:
  `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`.
- The scenario requires four distinct identities: introducer A, current viewer
  B, introduced target C, and second introducer D. D may come from a fourth
  simulator or an attached physical device.
- The scenario must create two active intros for the same current viewer and
  target through different introducers, then prove the current viewer sees one
  folded row with both introducer attributions and one Accept/Pass decision.
- The same scenario must prove the folded action applies to both underlying
  intro ids and all involved identities converge without losing intro state.
- `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` must include the new
  `folded-duplicate` scenario once it lands. Keep
  `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh` green as the baseline
  simulator intro journey after the harness changes.
- If the fourth identity/device is unavailable during execution, record an
  exact simulator/device fixture blocker and keep the simulator row blocked
  rather than closing it.
- If `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` is red in an existing
  scenario before the folded duplicate scenario runs, record the exact gate
  blocker and keep the simulator row blocked rather than closing it.

## TDD Source Matrix

Status vocabulary:

- `Open`: not implemented or not proven yet
- `Closed`: implemented and backed by direct test evidence
- `Blocked`: cannot be closed without a named prerequisite

| Row ID | Status | Priority | Scenario | Required first failing tests | Closure evidence |
| --- | --- | --- | --- | --- | --- |
| `DIF-001` | `Closed` | `P0` | Application projection folds active duplicate intros by target peer across multiple introducers while preserving all underlying intro ids and introducer names, including rows already persisted by the current shipped build before update. | Added focused tests in `test/features/introduction/application/load_introductions_test.dart`. Cases: two introducers same target fold to one item; different targets remain separate; current user as recipient and introduced both resolve correctly; newest row only affects display fallback, not membership; an upgrade-style fixture built from existing raw persisted `IntroductionModel` rows folds without mutating rows or losing ids, statuses, attribution, or pending decisions. RED captured on 2026-05-06 with `Method not found: 'foldIntroductionsForReview'`. | Closed 2026-05-06: `flutter test test/features/introduction/application/load_introductions_test.dart` passed twice after implementation (`+12` Executor and `+12` QA). Raw-list tests still passed; upgrade-style persisted-row fixture proves folded display compatibility with existing data. |
| `DIF-002` | `Closed` | `P0` | User-facing pending count counts one folded target, not duplicate raw rows, and preserves already-connected/non-pending badge rules. | Added application helper tests in `test/features/introduction/application/load_introductions_test.dart` for recipient-side duplicate pending targets, introduced-side duplicate pending targets, distinct targets, and exclusion of `alreadyConnected`, `passed`, `expired`, and `mutualAccepted` rows while preserving one-sided accepted overall-pending count. Added Feed and Orbit widget regressions for duplicate raw pending rows folding to one user-facing badge/review target. RED captured 2026-05-06: helper test command failed with missing `countFoldedPendingIntroductionTargets`; Feed and Orbit targeted widget commands failed with `Expected: <1> Actual: <2>`. | Closed 2026-05-06: `flutter test test/features/introduction/application/load_introductions_test.dart` passed (`+16`); `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"` passed (`+1`); `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"` passed (`+1`). Count path uses shared application helper `countFoldedPendingIntroductionTargets(...)`; repository `countPendingIntroductions(...)` remains raw-row based. |
| `DIF-003` | `Closed` | `P0` | One Accept/Pass action applies to every underlying active pending intro in the folded group. | Added `test/features/introduction/application/folded_introduction_response_use_case_test.dart` covering folded accept/pass over two mixed-role pending intro ids, recipient/introduced status updates, four outbound sends through existing single-intro paths, stale duplicate accept/pass skip with no new sends/outbox rows, non-party failed/no-send outcomes, and ML-KEM mismatch failed/pending/no-hidden-null outcomes. RED captured 2026-05-06: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` failed with missing `folded_introduction_response_use_case.dart`, `acceptFoldedIntroduction`, `passFoldedIntroduction`, and `FoldedIntroductionActionOutcome`. | Closed 2026-05-06: `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart` passed (`+6`); `flutter test test/features/introduction/application/accept_introduction_test.dart` passed (`+14`); `flutter test test/features/introduction/application/pass_introduction_test.dart` passed (`+9`); `flutter test test/features/introduction/application/mutual_acceptance_test.dart` passed (`+17`). Implementation added application wrapper `acceptFoldedIntroduction(...)`/`passFoldedIntroduction(...)` with per-id applied/skippedNotPending/failed results and no UI/schema/projection changes. |
| `DIF-004` | `Closed` | `P0` | Orbit/Intros UI renders one row for duplicate target intros and shows multi-introducer attribution. | Added widget tests in `test/features/introduction/presentation/widgets/intro_row_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_test.dart`, `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`, and `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart` for multi-introducer row attribution, duplicate `aboza` folded rendering, blank/long introducer fallback, and the active Orbit intro sliver staying a folded one-row `CustomScrollView` path without a nested `ListView`. RED captured 2026-05-06: the four `--plain-name` commands failed for missing folded UI constructor/rendering support (`introducerAttributionNames`, `foldedReviewItems`, and `OrbitIntrosViewData.foldedReviewItems`). | Closed 2026-05-06: direct GREEN commands passed for `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart`, `flutter test test/features/introduction/presentation/widgets/intros_tab_test.dart`, `flutter test test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`, `flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`, `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`, `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`, `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"`, `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"`, and `./scripts/run_test_gates.sh intro`; QA reran the owner widget suite green with `+41`. Implementation added folded rendering support only; raw-id action wiring, group-level processing/duplicate-tap suppression, schema/repository work, and simulator proof remain later-session scope. |
| `DIF-005` | `Closed` | `P0` | Wired Orbit flow processes a folded Accept/Pass once, disables the whole folded row while processing, reloads to the folded state, and updates the Orbit badge/review count by folded target count. | Added three `OrbitWired` tests in `test/features/orbit/presentation/screens/orbit_wired_test.dart`: folded duplicate target renders as one active row plus one Orbit badge target; folded Accept disables the folded row, suppresses duplicate taps, and updates both underlying raw intro ids once; folded Pass disables the folded row, suppresses duplicate taps, updates both underlying raw intro ids once, removes the folded target row, and clears the badge. RED captured 2026-05-06: publish test failed with two `Dora` rows instead of one; folded Accept/Pass tests failed because another raw duplicate `Accept` remained enabled while the first display-source id was processing. No new Feed RED was added because the inspected Feed path and existing folded badge regression stayed current. | Closed 2026-05-06: `dart format lib/features/orbit/presentation/screens/orbit_wired.dart test/features/orbit/presentation/screens/orbit_wired_test.dart` completed; direct GREEN commands passed for the three new `OrbitWired` `--plain-name` tests, `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "folds duplicate pending introduction targets in the Orbit intro count"`, `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "accepting an intro shows processing immediately and ignores duplicate taps"`, `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "passing an intro disables both actions immediately and ignores duplicate taps"`, `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart` (`+11`), and `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads the Orbit badge from folded pending introduction targets on first load"`; `./scripts/run_test_gates.sh intro` passed (`+185`). Implementation updated only `OrbitWired` to publish folded review items, resolve raw callback ids to folded items, guard all underlying ids while processing, call `acceptFoldedIntroduction(...)`/`passFoldedIntroduction(...)`, reload folded state after actions, and preserve the single-id fallback. |
| `DIF-006` | `Closed` | `P0` | Four-identity simulator proof covers two introducers creating duplicate intros for the same current viewer and target, then verifies one folded row and one folded Accept/Pass decision over both underlying intro ids. | Command-level RED captured 2026-05-06: `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh` failed as unknown scenario before implementation. In-scope harness/debug-runner work then added `INTRO_E2E_SCENARIO=folded-duplicate` to `smoke_test_friends.sh`, supporting fourth-identity reset/config in `reset_simulators.sh`, and folded snapshot/action support in `lib/core/debug/intro_e2e_runner.dart`; `INTRO_E2E_SCENARIO=all` includes the new scenario. Four identities are required: introducer A, current viewer B, target C, and second introducer D from a fourth simulator or attached physical device. Scenario 8 `offline-first-chat` receiver polling was extended to avoid a false timeout after the sender's intentional settle delay. | Closed 2026-05-07: green evidence includes live four-identity fixture intake; shell syntax; focused direct host tests; `./scripts/run_test_gates.sh intro`; standalone `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`; standalone `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`; `git diff --check`; standalone `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh` after the receive-wait fix; and resumed full scenario coverage. The full coverage evidence was resumed rather than one uninterrupted `all` process: scenario 1 passed before the user-requested stop, then scenarios `refresh`, `pass`, `repair`, `copy`, `partial`, `partition`, `offline-chat`, `pass-fallback`, `split-brain`, and `folded-duplicate` passed sequentially with `=== Intro E2E harness passed ===`. The earlier `copy` blocker is obsolete. |
| `DIF-007` | `Closed` | `P1` | Full regression and documentation closure prove the folded behavior without weakening existing intro journeys. | No product-code test first. This is closure: run the intro gate, direct companion suites, and folded duplicate simulator proof, then update this matrix row statuses and `test-inventory.md` with concrete evidence. | Closed 2026-05-07: final closure evidence is green. The required direct companion command passed with `+266`; `./scripts/run_test_gates.sh intro` passed with `+185`; `flutter devices --machine` and `xcrun simctl list devices available` confirmed current fixture availability; `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` first timed out during scenario 3 `pass-handshake` before intro send/pass/folded behavior, with A/C complete and B still `running`, then the exact uninterrupted retry passed all scenarios 1-11 and ended with `=== Intro E2E harness passed ===`, including scenario 11 `Four-identity folded duplicate acceptance`; `bash -n smoke_test_friends.sh reset_simulators.sh` and `git diff --check` passed with no output. `test-inventory.md`, this source row, and the session breakdown final verdict were updated as DIF-007-owned closure docs; no production or test code changed in DIF-007. |

## Step-by-Step Implementation Plan

### 1. Add a Folded Intro Review Model

Create an application-level projection instead of changing the database row
shape. Candidate names:

- `FoldedIntroductionReviewItem`
- `IntroductionReviewGroup`

Required fields:

- `groupId` or `otherPeerId`
- `otherPeerId`
- `displayUsername`
- `displayIntro`
- `introductions`
- `introductionIds`
- `introducerNames`
- `introducerIds`
- `ownPartyStatus`
- `overallStatus`
- `showActions`
- `isAlreadyConnected`
- `isProcessing`

The implementation should live near
`lib/features/introduction/application/load_introductions_use_case.dart` unless
the local patterns point to a better application helper file.

### 2. Make Count Semantics Match the Projection

Prefer one shared helper for folded count so Orbit and Feed do not drift:

- either update repository/helper `countPendingIntroductions(...)` to count
  distinct counterparties for true pending rows
- or add a new application query/helper and route user-facing badges through it

If the repository method changes, update DB helper tests and in-memory fake
tests in the same session.

### 3. Add Folded Accept/Pass Use Cases

Add group-level use cases that call the existing single-intro use cases for each
underlying pending intro id. Do not bypass the current accept/pass logic.

Acceptance rules:

- skip underlying rows where the current user's party status is already
  accepted for folded accept
- skip underlying rows where the current user's party status is already passed
  for folded pass
- return a result that tells the caller which intro ids were updated, skipped,
  or failed
- keep mutual-acceptance side effects idempotent through
  `handleMutualAcceptance(...)`

### 4. Replace Raw Rows in Intro Review UI

Update both surfaces that currently expand raw intro rows:

- `IntrosTab`
- `OrbitScreen` intro sliver

The active UI should render folded review items, not grouped raw intros. If a
compatibility wrapper is needed during the transition, keep it small and remove
sender headers from the folded path so one target cannot appear under two
headers.

### 5. Wire Processing, Delete, Refresh, and Badge Count

Update `OrbitWired` to store folded review items or the raw rows plus a folded
projection, then:

- call folded accept/pass by group
- track processing by folded group id
- remove processing state only after all underlying actions finish
- reload and publish folded projection
- count folded targets for `_introsCount`
- keep delete scoped to one underlying intro id unless product explicitly asks
  for group delete; this plan does not change delete semantics

Update `FeedWired` if its badge source remains raw.

### 6. Run the Regression Contract

Minimum required commands after implementation:

```sh
flutter test --no-pub \
  test/features/introduction/application/load_introductions_test.dart \
  test/features/introduction/application/accept_introduction_test.dart \
  test/features/introduction/application/pass_introduction_test.dart \
  test/features/introduction/presentation/widgets/intros_tab_test.dart \
  test/features/introduction/presentation/widgets/intros_tab_extended_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart \
  test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart
```

```sh
./scripts/run_test_gates.sh intro
```

```sh
INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh
INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh
INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh
```

The folded duplicate simulator scenario requires four distinct identities:
introducer A, current viewer B, introduced target C, and second introducer D.
The fourth identity may run on an additional simulator or an attached physical
device. Do not mark `DIF-006` `Closed` without green four-identity proof; if
the fixture is unavailable, record the exact blocker and leave the row blocked.

Run `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart`
if the Feed badge code changes.

## Known Risks And Edge Cases

- Cross-introduction acceptance can diverge if B accepts one raw intro while C
  accepts a different raw intro. Folded group accept/pass should apply to every
  current underlying pending row to reduce this risk.
- A future duplicate intro that arrives after one side already accepted an
  older row may still require a reconciliation pass if the old row is still
  active and the new row has not inherited the prior response. Add this only if
  tests prove the simple group-action path is insufficient.
- Existing same-introducer newer-wins behavior in
  `handle_incoming_introduction_use_case.dart` must not be weakened.
- Existing `alreadyConnected` visibility and pending-badge exclusion rules must
  stay unchanged.
- UI must handle long introducer names without row overflow.
- Delete semantics are intentionally not folded in this plan. Group delete is a
  separate product decision.

## Scope Guard

This plan does not:

- add a DB migration or change the persisted introduction row schema; the folded
  projection must read existing raw intro rows directly so upgrade users keep
  their current intros
- change introduction payload protocol fields
- change friend-picker resend eligibility
- permanently block future introductions after a Pass
- change mutual acceptance contact creation rules
- rewrite the Orbit screen outside the intro review surface
- remove existing intro tests or weaken the intro gate

## Done Criteria

The feature is done only when:

- duplicate active intros to the same target render as one row
- multi-introducer attribution is visible in that row
- Accept and Pass each appear only once for the folded row
- Accept/Pass applies to all current underlying pending intro records in the
  fold
- users upgrading from the current shipped build with already-persisted pending
  intro rows see those intros in the folded review design without data loss
- Orbit and Feed user-facing badge/review counts count folded targets
- the four-identity folded duplicate simulator scenario is green, and the
  scenario is included in `INTRO_E2E_SCENARIO=all`
- all existing intro tests still pass
- the intro gate passes
- this source matrix and the intro test inventory are updated with exact test
  evidence

## Pipeline Handoff

Use the adjacent breakdown:

`Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`

Later execution should use `$implementation-session-pipeline-orchestrator`
against that breakdown, not this source plan directly.
