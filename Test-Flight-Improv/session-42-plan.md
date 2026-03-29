# Session 42 Plan — Intro Picker Reproduction And Contract Pin

## real scope

What changes in this session:

- add the smallest direct repro/contract coverage for the intro picker so the
  reported filtering symptom is either reproduced against repo code or
  disproved with a permanent test
- verify whether introducer-side intro data stays limited to the exact
  `(recipient, introduced)` pair or whether unexpected local rows are what make
  the picker look wrong
- pin the current duplicate-exclusion contract so later work does not widen
  into status-policy changes
- refresh
  `Test-Flight-Improv/23-introduction-picker-filtering-bug-session-breakdown.md`
  only if the new evidence materially disproves the proposal's root-cause
  narrative or changes whether Session `43` should run

What does not change in this session:

- no production fix beyond the minimum non-behavioral extraction needed to make
  a direct test possible
- no status-policy rewrite for `passed`, `expired`, or `mutualAccepted`
  introductions
- no named-gate expansion
- no closure-doc refresh in `Test-Flight-Improv/00-INDEX.md` unless Session
  `42` evidence unexpectedly becomes stable closure state, which is not the
  planned path

## closure bar

Session `42` is sufficient when all of the following are true:

- the repo has a deterministic direct test at the picker seam or an extracted
  helper that encodes the reported scenario and proves whether the symptom is
  real in current code
- the current contract is pinned: only the exact already-introduced pair for
  the active recipient is excluded under the current feature spec, and the
  session does not silently widen this into status-based eligibility changes
- the evidence clearly narrows the real seam to one of:
  `FriendPickerWired`, introducer-side intro creation, introducer-side intro
  update/listener flow, or duplicated/unexpected local intro rows
- if the proposal's narrative is disproved, the breakdown artifact is refreshed
  so Session `43` is not forced on stale assumptions
- no speculative production fix is bundled into this session

## source of truth

Authoritative sources for this session:

- controlling scope/order artifact:
  `Test-Flight-Improv/23-introduction-picker-filtering-bug-session-breakdown.md`
- product contract:
  `UI-20-Intro-friends/intro-feature-spec.md`
- proposal under review:
  `Test-Flight-Improv/23-introduction-picker-filtering-bug.md`
- regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- named gate policy:
  `Test-Flight-Improv/test-gate-definitions.md`
- current production seams:
  `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
  `lib/features/introduction/application/send_introduction_use_case.dart`
  `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
  `lib/features/introduction/application/introduction_listener.dart`
  `lib/core/database/helpers/introductions_db_helpers.dart`
  `lib/features/introduction/domain/models/introduction_model.dart`
- current direct tests:
  `test/features/introduction/presentation/screens/friend_picker_test.dart`
  `test/features/introduction/regression/introduction_regression_test.dart`
  `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  `test/features/introduction/integration/introduction_smoke_test.dart`
  `test/features/introduction/integration/introduction_multi_node_test.dart`

Conflict rules:

- the session breakdown controls scope, ordering, and whether Session `42`
  stays evidence-gated
- current code and direct tests beat stale prose in the proposal
- the feature spec beats the proposal on status-policy expectations unless repo
  evidence proves the spec stale
- `Test-Flight-Improv/test-gate-definitions.md` and
  `scripts/run_test_gates.sh` matter only if Session `42` grows beyond
  direct intro suites; if they disagree, the script wins

## session classification

`evidence-gated`

## exact problem statement

The proposal claims two picker failures:

- after `A` introduces `D` to `B`, `C` is missing from `B`'s picker
- after the same intro, `B` is missing from `C`'s picker

Current repo evidence does not prove either symptom from picker logic alone.
`FriendPickerWired` loads introductions by introducer and excludes only contacts
that match the active recipient as either `recipientId` or `introducedId`,
which means a single stored intro `(A, B, D)` should still leave `C` visible in
`B`'s picker and `B` visible in `C`'s picker. The unresolved risk is therefore
not "status filtering is wrong" but one of:

- the escaped bug depends on unexpected local intro rows or duplicated semantic
  records on the introducer device
- a broader data-path seam is polluting what the picker reads
- the proposal is stale and the repo already satisfies the intended contract

User-visible behavior that must improve in this session:

- the repo must gain deterministic evidence for the real behavior at the picker
  seam so downstream work is driven by tests instead of the proposal narrative

Behavior that must stay unchanged in this session:

- the current contract that duplicate exact-pair exclusions are not broadened
  into status-based re-introduction eligibility rules
- the conversation entry flow and intro acceptance flow unless a direct
  reproducer proves they are required to explain the picker data

## files and repos to inspect next

Production files:

- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/introduction/application/send_introduction_use_case.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `lib/features/introduction/domain/models/introduction_model.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  only if a real repro requires the banner or sheet entry path

Test files:

- `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  as the preferred new direct seam for `FriendPickerWired` filtering coverage
- `test/features/introduction/presentation/screens/friend_picker_test.dart`
  only if the repo already prefers keeping the new filtering assertions in the
  existing picker screen test file
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/shared/fakes/in_memory_introduction_repository.dart`
  for deterministic repo-backed intro state in direct tests

## existing tests covering this area

Covered today:

- `test/features/introduction/presentation/screens/friend_picker_test.dart`
  covers pure `FriendPickerScreen` rendering, search, selection, and button
  state; it does not cover `FriendPickerWired._loadFriends()`
- `test/features/introduction/regression/introduction_regression_test.dart`
  already pins exact same-recipient exclusion by replicating the current
  `alreadyIntroduced` set logic
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  proves the conversation entry path opens the picker and excludes an
  already-introduced friend for the same recipient
- `test/features/introduction/integration/introduction_smoke_test.dart`
  proves the repository exposes existing intros for duplicate prevention
- `test/features/introduction/integration/introduction_multi_node_test.dart`
  covers intro send/accept/pass flows across nodes

Missing today:

- no direct test encodes the exact proposal scenario and asserts what `B` sees
  in `B`'s picker after `(A, B, D)` exists
- no direct test encodes the claim that `B` disappears from `C`'s picker after
  `(A, B, D)` exists
- no existing test proves whether unexpected extra introducer-side intro rows
  can appear after send/listener/status-update flows

Current tests that pin intentional behavior:

- same-recipient duplicate exclusion stays intentional
- intro integration suites are optional/manual direct suites, not named gates

## regression/tests to add first

Add these proofs before any production change:

- one direct picker regression in
  `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  that seeds contacts `B`, `C`, and `D`, seeds exactly one intro
  `(introducer=A, recipient=B, introduced=D)`, and asserts:
  - `B`'s picker excludes `D`
  - `B`'s picker still shows `C`
  - `C`'s picker still shows `B`
- one introducer-side data-path regression that sends or seeds the same intro
  flow and verifies the introducer repository does not accumulate unrelated
  extra rows that would make the picker fail for the wrong reason

Why these prove the seam:

- the first test directly answers whether current picker logic reproduces the
  proposal's reported symptom
- the second test distinguishes a picker bug from polluted local intro state

If the first direct test already disproves the proposal and the second test
shows clean introducer-side data, stop. Session `42` should not invent a fix.

## step-by-step implementation plan

1. Add the smallest direct test harness for `FriendPickerWired` filtering.
   Prefer fakes and direct widget/helper coverage over `ConversationWired` so
   the repro is isolated from banner and sheet-entry concerns.
2. Encode the proposal scenario exactly with one stored intro `(A, B, D)` and
   assert the active-recipient results for `B` and `C`.
3. Run the new direct test first.
   If it passes and disproves the proposal, keep it as the contract pin and do
   not touch production code.
4. Add the narrowest introducer-side data-path regression needed to check
   whether send/listener/status-update flows create duplicate or unexpected
   local intro rows for the introducer.
5. Run the existing intro direct suites to confirm the new evidence did not
   regress same-recipient exclusion or intro wiring behavior.
6. Only if the new tests expose a real failure, stop after identifying the
   smallest confirmed seam and refresh the breakdown artifact for Session `43`.
   Do not implement the production fix in Session `42`.
7. Only inspect `conversation_wired.dart` or broader wiring if the isolated
   picker/data-path tests cannot explain the failure.

## risks and edge cases

- the proposal's status-based expectations conflict with the current feature
  spec, so a naive test could accidentally encode the wrong contract
- current picker logic has a reverse-pair exclusion branch; Session `42` must
  distinguish intended exact-pair behavior from accidental cross-recipient
  filtering
- intro rows are keyed by `id`, so semantic duplicates with new IDs would not
  be prevented by repository upsert behavior alone
- listener-driven saves happen on recipient/introduction devices; Session `42`
  must confirm whether introducer-side state is polluted or not before blaming
  the picker
- the worktree is already dirty in nearby intro/conversation files, so direct
  intro suites are safer than broad gate runs unless the session expands

## exact tests and gates to run

Direct tests:

- `flutter test test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
- `flutter test test/features/introduction/presentation/screens/friend_picker_test.dart`
  only if Session `42` intentionally keeps the new direct assertions there
- `flutter test test/features/introduction/regression/introduction_regression_test.dart`
- `flutter test test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
- `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`

Named gates:

- none by default; intro-picker behavior is not owned by a frozen named gate
- run `./scripts/run_test_gates.sh baseline` only if Session `42` has to change
  `lib/features/conversation/presentation/screens/conversation_wired.dart` or
  other broader conversation entry wiring
- run `./scripts/run_test_gates.sh completeness-check` only if Session `42`
  adds a new integration/cross-feature file that must be classified in
  `Test-Flight-Improv/test-gate-definitions.md`

## known-failure interpretation

- no intro-specific known failure is documented in the controlling breakdown,
  regression strategy, or gate-definition docs for this session
- if an existing direct suite is already red before the new repro is added, log
  the exact failing test and treat it as pre-existing unless the failure is
  clearly caused by the new Session `42` changes
- if the new direct reproducer fails against untouched production code, that is
  desired evidence for Session `42`; stop after capturing the confirmed seam and
  hand off to Session `43` rather than broadening into a fix here

## done criteria

- a direct picker repro/contract test exists and is deterministic
- the repo evidence clearly says one of:
  - the proposal symptom is disproved by current code and the new direct test
    now pins that contract
  - a real failure is confirmed and narrowed to one production seam for Session
    `43`
- same-recipient duplicate exclusion remains covered by direct tests
- no speculative production fix ships in Session `42`
- if the proposal narrative is disproved or materially narrowed, the breakdown
  artifact is refreshed before Session `43` planning

## scope guard

Non-goals for this session:

- changing which intro statuses allow re-introduction
- redesigning the picker UI or conversation banner
- fixing every possible intro data-integrity edge case without a reproducer
- widening named gates or rewriting stable closure docs
- bundling the production fix that belongs to Session `43`

Overengineering in this session would include:

- touching both picker UI and intro data-path code before the new tests identify
  the actual seam
- adding broad end-to-end coverage when a fake-backed direct test can prove the
  behavior
- turning Session `42` into a product-policy rewrite around passed/expired
  introductions

## accepted differences / intentionally out of scope

- the proposal's expectation that `passed` or `expired` intros should become
  eligible again is intentionally left unchanged because it conflicts with the
  current feature spec and is not proven by repo evidence
- reverse-direction exact-pair exclusion behavior stays under the current
  contract unless the new Session `42` evidence proves that assumption wrong
- `FriendPickerScreen` rendering behavior, intro acceptance UX, and Orbit/Feed
  follow-up surfaces are out of scope for this evidence session

## dependency impact

- Session `43` depends entirely on the evidence produced here
- if Session `42` disproves the proposal and finds no polluted introducer-side
  state, Session `43` should be downgraded to `stale/already-covered` or held
  pending an external repro instead of forcing a fix
- if Session `42` confirms a picker-only failure, Session `43` should stay
  narrowly in `friend_picker_wired.dart` plus the matching direct test seam
- if Session `42` confirms bad introducer-side local data, Session `43` should
  target the confirmed create/listener/db seam and rerun the same direct intro
  suites rather than widening into unrelated conversation work
