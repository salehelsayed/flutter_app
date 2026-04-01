# Session 59 Plan - Friend picker progress UX and rollout closure

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Consume the landed Session `58` optional progress-report contract in
  `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
  so the picker owns truthful in-flight counts while a multi-friend send runs.
- Extend
  `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
  to render visible progress feedback for the active send window without
  regressing search, selection, or the existing close path once sending
  completes.
- Keep the send button disabled for the entire send window and preserve the
  existing `onIntroductionsSent(...)` completion path.
- Add or tighten direct UI and wiring regressions for visible progress and
  disabled-send behavior, then refresh the report-level closure docs if the
  rollout lands cleanly.
- Do not reopen Session `58` batching semantics, Go or bridge APIs, picker
  filtering policy, or unrelated conversation/orbit/report work.

### closure bar

- The friend picker shows truthful progress while a multi-friend send is in
  flight, including an initial `0/total` state and a final `total/total`
  completion state.
- The send button stays disabled during the full send window, even when friends
  remain selected.
- Completion still exits through the existing `onIntroductionsSent(...)` path
  without duplicate sends or UI dead-ends.
- Direct widget or wiring regressions permanently prove progress visibility,
  progress advancement, and disabled-send behavior.
- The report closure docs reflect the landed batching plus picker-progress
  behavior without overclaiming unrelated intro flow changes.

### source of truth

- `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
  is the active sequencing and closure contract.
- `Test-Flight-Improv/29-batch-parallel-intro-sending.md` provides the broader
  user-facing goal; the session breakdown wins where the source doc still
  bundles application and UI work together.
- Current code and tests beat stale prose:
  - `lib/features/introduction/application/send_introduction_use_case.dart`
  - `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
  - `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
  - `test/features/introduction/presentation/screens/friend_picker_test.dart`
  - `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  - `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of
  truth for named-gate and optional direct-suite classification.
- `UI-20-Intro-friends/intro-feature-spec.md` should be refreshed only for the
  shipped picker progress and send-contract behavior that actually lands.

### session classification

`implementation-ready`

### exact problem statement

- Session `58` now provides a truthful optional progress callback from
  `sendIntroductions(...)`, but `FriendPickerWired` still only tracks
  `_isSending` and does not consume or surface that contract.
- `FriendPickerScreen` still renders only search, list, and a count-based send
  button; it has no visible progress state, progress text, or progress bar.
- The current button disablement is selection-count only at the pure-screen
  layer, so the UI contract does not yet prove that sending keeps the button
  disabled through the full operation.
- User-visible behavior that must improve: the picker should show truthful
  sending progress while multi-friend sends are in flight instead of looking
  frozen.
- Behavior that must stay unchanged: duplicate filtering, selection flow,
  close-after-success behavior, current intro architecture, and the Session `58`
  batching contract.

### files and repos to inspect next

- Repo scope stays inside
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app`; no second repo is
  involved.
- Primary production files:
  - `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
  - `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_de.arb`
  - `lib/l10n/app_ar.arb`
- Primary tests:
  - `test/features/introduction/presentation/screens/friend_picker_test.dart`
  - `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  - `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
- Closure docs:
  - `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
  - `UI-20-Intro-friends/intro-feature-spec.md`
  - `Test-Flight-Improv/00-INDEX.md`

### existing tests covering this area

- `test/features/introduction/presentation/screens/friend_picker_test.dart`
  already covers header text, empty states, selection visuals, count-based
  button copy, enablement at zero selection, and close/send callbacks.
- `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  already pins exact-pair duplicate exclusion, which stays intentionally
  unchanged.
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  already proves the conversation-to-picker DI path and full send wiring, but
  it does not assert visible progress.
- `test/features/introduction/integration/introduction_smoke_test.dart` and
  `test/features/introduction/integration/introduction_multi_node_test.dart`
  already provide companion acceptance coverage on the landed Session `58`
  engine.

### regression/tests to add first

- Add pure-screen regression coverage in
  `test/features/introduction/presentation/screens/friend_picker_test.dart`
  for visible sending progress and disabled-button behavior while sending.
- Add wired-screen regression coverage in
  `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  that drives a real in-flight send and proves the progress UI advances
  truthfully through the live Session `58` callback contract.
- Add or tighten one intro wiring smoke assertion only if the widget-level
  proofs are insufficient to show the user-visible contract across the existing
  conversation launch path.

### step-by-step implementation plan

1. Materialize the doc-scoped Session `59` plan and keep the scope pinned to
   picker rendering plus closure.
2. Add the missing progress and disabled-state regressions in the friend picker
   widget and wired tests before broadening production changes.
3. Extend `FriendPickerWired` with the smallest sending-progress state needed
   to consume `sendIntroductions(..., onProgress: ...)` while preserving the
   existing success callback flow.
4. Extend `FriendPickerScreen` with an explicit sending-state surface that can
   render progress text or a progress bar and disable the send action for the
   whole send window.
5. Add the minimal localized progress copy required by the new UI and
   regenerate localization outputs.
6. Run the direct widget and intro integration suites, plus the companion
   Session `58` integration checks the breakdown assigns to this session.
7. Refresh the report breakdown and stable closure docs only after the picker
   behavior is verified.

### risks and edge cases

- Progress must reflect the use-case callback, not a local optimistic counter,
  or the UI can drift from actual send completion.
- If the send button remains enabled during sending, duplicate sends become
  possible even though `_isSending` guards the wired layer.
- Localization generation touches already-dirty `lib/l10n/*` files, so edits
  must merge carefully instead of overwriting unrelated worktree changes.
- The picker should not imply new product behaviors such as cancellation,
  background progress persistence, or a maximum selection cap.

### exact tests and gates to run

- `flutter test test/features/introduction/presentation/screens/friend_picker_test.dart`
- `flutter test test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
- `flutter test test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
- `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
- `./scripts/run_test_gates.sh baseline` only if execution changes broader
  conversation or banner entry wiring beyond the picker-owned surface
- `./scripts/run_test_gates.sh completeness-check` only if a brand-new test
  file path is added or an existing path is reclassified

### known-failure interpretation

- None of the consulted docs mark the targeted picker widget or intro direct
  suites as accepted red tests.
- Treat failures in the listed friend-picker tests or intro integration suites
  as real regressions for Session `59` unless a rerun proves unrelated flake.
- Treat localization-generation failures as real session blockers because the
  rendered picker copy depends on them landing coherently.

### done criteria

- The picker shows visible truthful progress while sending is in flight.
- The send button stays disabled throughout the send window.
- Completion still returns through the existing `onIntroductionsSent(...)`
  success path.
- Direct widget or wiring regressions prove progress visibility and
  disabled-send behavior.
- The required acceptance tests pass.
- The report breakdown and stable closure docs are refreshed to match landed
  reality.

### scope guard

- No changes to Session `58` batching semantics beyond narrow bug fixes proven
  necessary by Session `59` tests.
- No Go, bridge, transport, or intro payload redesign.
- No picker filtering-policy changes, search redesign, selection cap, cancel
  support, or background progress persistence.
- No unrelated conversation, orbit, feed, or notification-surface work unless
  a test proves a real dependency.
- Do not revert unrelated dirty worktree changes.

### accepted differences / intentionally out of scope

- The visible progress surface may stay small and local to the picker footer;
  no broader loading overlay is required.
- The picker may keep its current overall visual structure; only the sending
  state needs to become truthful.
- No new named gate is required unless execution adds a new classified test
  path.

### dependency impact

- This is the report-closing session; once it lands, the breakdown and stable
  closure docs should reflect Report `29` as closed maintenance-time work.
- If execution proves the Session `58` progress contract insufficient, stop and
  reopen the report rather than inventing picker-local progress semantics.

## Structural blockers remaining

- None.

## Incremental details intentionally deferred

- Exact visual styling of the progress bar can stay minimal as long as the
  counts and disabled-send state remain truthful.
- A dedicated progress model type is unnecessary unless the existing integer
  callback proves too awkward in the wired layer.

## Accepted differences intentionally left unchanged

- No cancel button or background-send affordance.
- No redesign of the picker list rows or search experience.
- No widening into intro notification, orbit badge, or feed follow-up work.

## Exact docs/files used as evidence

- `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
- `Test-Flight-Improv/29-batch-parallel-intro-sending.md`
- `lib/features/introduction/application/send_introduction_use_case.dart`
- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
- `test/features/introduction/presentation/screens/friend_picker_test.dart`
- `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `UI-20-Intro-friends/intro-feature-spec.md`

## Why the plan is safe or unsafe to implement now

- Safe to implement now because Session `58` already supplies the truthful
  optional progress contract, the remaining gap is isolated to the picker UI
  and closure docs, and the breakdown provides explicit tests, dependencies, and
  scope guardrails for the final report-closing slice.
