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

## TDD Source Matrix

Status vocabulary:

- `Open`: not implemented or not proven yet
- `Closed`: implemented and backed by direct test evidence
- `Blocked`: cannot be closed without a named prerequisite

| Row ID | Status | Priority | Scenario | Required first failing tests | Closure evidence |
| --- | --- | --- | --- | --- | --- |
| `DIF-001` | `Open` | `P0` | Application projection folds active duplicate intros by target peer across multiple introducers while preserving all underlying intro ids and introducer names. | Add focused tests in `test/features/introduction/application/load_introductions_test.dart` or a new folded projection suite. Cases: two introducers same target fold to one item; different targets remain separate; current user as recipient and introduced both resolve correctly; newest row only affects display fallback, not membership. | Projection tests green; no raw-list tests regressed. |
| `DIF-002` | `Open` | `P0` | User-facing pending count counts one folded target, not duplicate raw rows, and preserves already-connected/non-pending badge rules. | Add repository/helper or application count tests for duplicate raw rows with the same counterparty from two introducers. Include recipient-side and introduced-side cases. | Direct count tests green; `countPendingIntroductions` or its replacement returns folded count where user-facing badges need it. |
| `DIF-003` | `Open` | `P0` | One Accept/Pass action applies to every underlying active pending intro in the folded group. | Add tests for folded accept and folded pass over two pending intro ids. Assert both party statuses update, outbound response calls are made through existing single-intro paths, duplicate taps do not double-apply, and non-party/key-mismatch failures do not get hidden. | Folded accept/pass tests green; existing `accept_introduction_test.dart` and `pass_introduction_test.dart` still pass. |
| `DIF-004` | `Open` | `P0` | Orbit/Intros UI renders one row for duplicate target intros and shows multi-introducer attribution. | Add widget tests for `IntrosTab` and active `OrbitScreen` intro sliver: duplicate `aboza` rows collapse to one row, exactly one Accept and one Pass are visible, attribution names both introducers, and long/blank names use existing fallback/truncation behavior. | Widget tests green; existing intro row, intro tab, and Orbit screen tests still pass. |
| `DIF-005` | `Open` | `P0` | Wired Orbit flow processes a folded Accept/Pass once, disables the whole folded row while processing, reloads to the folded state, and updates the Orbit badge/review count by folded target count. | Add `OrbitWired` tests with two introductions for the same `otherPeerId`. Assert one visible row, one processing state, both underlying rows receive the action, duplicate taps do not create extra updates, and the badge count is one. Add a `FeedWired` badge test if the badge still reads the repository count directly. | `OrbitWired`/Feed badge tests green; direct companion Orbit intro wiring tests green. |
| `DIF-006` | `Open` | `P1` | Full regression and documentation closure prove the folded behavior without weakening existing intro journeys. | No product-code test first. This is closure: run the intro gate and direct companion suites, then update this matrix row statuses and `test-inventory.md` with concrete evidence. | `./scripts/run_test_gates.sh intro` green, direct Orbit/Feed companion tests green, docs updated with exact files and commands. |

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

- add a DB migration or change the persisted introduction row schema
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
- Orbit and Feed user-facing badge/review counts count folded targets
- all existing intro tests still pass
- the intro gate passes
- this source matrix and the intro test inventory are updated with exact test
  evidence

## Pipeline Handoff

Use the adjacent breakdown:

`Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`

Later execution should use `$implementation-session-pipeline-orchestrator`
against that breakdown, not this source plan directly.
