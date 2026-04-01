# 29 - Batch Parallel Introduction Sending Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
- Proposal/source doc path:
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/29-batch-parallel-intro-sending.md`
- This recovery pass completed the bounded doc-scoped pipeline for Report
  `29`; this artifact now records the accepted Session `58` and Session `59`
  outcomes plus the stable closure references.
- Existing doc-scoped plan artifact notes:
  `Test-Flight-Improv/29-batch-parallel-intro-sending-session-58-plan.md`
  was refreshed against current repo state before verification, and
  `Test-Flight-Improv/29-batch-parallel-intro-sending-session-59-plan.md`
  was created during this recovery pass before Session `59` execution.
- Recovery-pass note:
  the prior pipeline attempt ended `blocked` / `still_open` on
  `spawn_or_tool_failure`; this artifact is refreshed against the live repo
  state, including the Session `58` local changes in
  `lib/features/introduction/application/send_introduction_use_case.dart` and
  `test/features/introduction/application/send_introduction_test.dart`,
  treats that live state as source of truth, does not revert unrelated work,
  and records the bounded controller-side recovery that accepted the already
  landed implementation after a fresh spawned execution attempt stalled again.
- Downstream workflow rule:
  - future reopen work still plans one session at a time
  - any future rerun must refresh against landed code before execution

## Downstream execution path

- This recovery pass still used the normal ordered session pipeline:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Session `58` ran first. After a fresh spawned execution/QA attempt stalled
  again on the retryable `spawn_or_tool_failure` class, the controller spent
  the normal bounded inner recovery stack locally, accepted the verified repo
  state, and only then continued to Session `59`.
- Session `59` then landed the picker progress UX and the stable closure-doc
  refresh on top of the accepted Session `58` contract.
- This breakdown artifact remains the stable handoff and maintenance ledger;
  do not rely on shared conversational context for future reopen work.

## Recommended plan count

- `2`

## Overall closure bar

Report `29` is closed only when multi-friend introduction sending is materially
faster without changing the current intro architecture or lying to the user:

- `sendIntroductions(...)` no longer serially awaits every selected friend; it
  processes the selection in ordered batches capped at `10`
- no more than `10` intro-send slots are active at once, and later batches do
  not start until the current batch settles
- each selected friend still yields exactly one intro record, two P2P delivery
  attempts, unchanged encryption and inbox fallback behavior, unique intro ID
  generation, and exactly one `contactRepo.setIntrosSentAt(...)` call after
  all batches complete
- the friend picker shows truthful in-flight send progress for multi-friend
  sends and keeps the send button disabled for the entire send window
- permanent direct regressions prove batching semantics, cap enforcement,
  ordered results, progress truth, and unchanged intro data integrity without
  adding a Go batch API or widening the frozen named gates

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/29-batch-parallel-intro-sending.md`
- `UI-20-Intro-friends/intro-feature-spec.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`

Current code and current-test seams that govern the split:

- `lib/features/introduction/application/send_introduction_use_case.dart`
- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
- `lib/core/services/p2p_service.dart`
- `test/features/introduction/application/send_introduction_test.dart`
- `test/features/introduction/presentation/screens/friend_picker_test.dart`
- `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/shared/fakes/fake_p2p_network.dart`
- `test/shared/fakes/fake_p2p_service_integration.dart`

Source-of-truth conflicts and architectural constraints that shape the split:

- the proposal explicitly keeps Go and bridge batch-send APIs out of scope, and
  current `P2PService` still exposes only single-message `sendMessage(...)`
  and `storeInInbox(...)`; batching therefore has to stay as Flutter-side
  orchestration on top of the existing send contract
- the repo now materially diverges from the source doc's fully sequential send
  wording: `sendIntroductions(...)` ships Flutter-side batching with
  `_maxConcurrentIntroductionChains = 10`, ordered `Future.wait(...)` batch
  fan-out, `_sendIntroductionChain(...)`, and an optional `onProgress`
  callback; maintenance work should treat that implementation as the current
  send contract without reopening a Go or bridge batch API
- `FriendPickerWired` and `FriendPickerScreen` now consume that progress
  contract to surface truthful picker progress and to disable send, close,
  search, and row interactions during the in-flight send window
- the intro feature spec still describes duplicate exclusion regardless of
  status, and the current picker regression already pins exact-pair filtering;
  this report should improve sending and progress only, not reopen picker
  filtering policy
- intro integration suites are intentionally classified as direct optional or
  manual suites in `test-gate-definitions.md`; no frozen named intro gate owns
  this rollout today

## Evidence collector summary

- `sendIntroductions(...)` now emits optional `onProgress` updates starting at
  `0/total`, chunks `friendsToIntroduce` into ordered slices of `10`, runs
  each slice via `Future.wait(...)`, and still calls
  `contactRepo.setIntrosSentAt(...)` once after all batches complete.
- Each friend still creates one intro ID, builds two payloads, performs two
  `_sendPayload(...)` calls, saves the intro locally, and emits a
  `SEND_INTRODUCTION_SENT` flow event.
- `_sendPayload(...)` retains the intended send-false to inbox-fallback
  behavior; the rollout did not redesign retry policy.
- Existing intro callers and integration paths still call
  `sendIntroductions(...)` without a progress argument, so the progress seam
  remains optional and source-compatible.
- `FriendPickerWired` now owns send progress state and forwards it to
  `FriendPickerScreen` while preventing duplicate sends during the in-flight
  window.
- `FriendPickerScreen` now renders localized progress text, a determinate
  progress bar, and disabled send/close/search/row interactions during the
  send window.
- `send_introduction_test.dart`, `friend_picker_test.dart`,
  `friend_picker_wired_test.dart`, `intro_wiring_smoke_test.dart`,
  `introduction_smoke_test.dart`, and `introduction_multi_node_test.dart` all
  returned passing evidence during this recovery pass; Session `58` also
  cleared `./scripts/run_test_gates.sh baseline` with an explicit
  `FLUTTER_DEVICE_ID` because multiple simulators were attached.
- `P2PService` remains a single-message interface, which keeps batching and
  progress as application/presentation seams rather than protocol seams.

## Closure mapper

- Real closure target:
  ship bounded parallel intro sending with truthful picker progress on top of
  the current per-introduction payload and single-message transport model.
- Correctness and reliability work:
  batching and cap enforcement, ordered results, unique IDs, unchanged
  encryption and fallback behavior, DB-save consistency, truthful progress
  state, and no double-send regression while a send is active.
- Evidence-only or acceptance-only work:
  none needs its own extra session on current repo evidence; final acceptance
  and bounded doc refresh can stay with the picker-progress session.
- Explicit non-goals:
  no Go or bridge batch API, no intro payload redesign, no cancellation, no
  picker-selection-cap product work, no changed retry policy, and no reopening
  of Orbit or Feed intro follow-up wiring from other reports.

## Session splitter

- Split result:
  one application batching and progress-contract session, then one picker
  progress UX and closure session.
- Why this is the smallest meaningful set:
  the batching engine and the picker UX are different seams with different
  direct regressions, but a third acceptance-only session would mostly repeat
  the same intro suites and doc refresh work that the UI session can already
  own honestly.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Initial status | Current status | Retry count | Final execution verdict | Blocker class | Closure docs touched | Blocker note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `58` | Capped intro batching and progress-report contract | `implementation-ready` | `Test-Flight-Improv/29-batch-parallel-intro-sending-session-58-plan.md` | none | `pending` | `accepted` | `2` | `accepted_after_controller_recovery` | `none` | `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md` | fresh recovery-pass planning refreshed the doc-scoped plan, a new spawned execution/QA attempt stalled again on `spawn_or_tool_failure`, and the controller then used bounded local recovery to verify the live repo state via the direct intro suites plus `baseline`; the batching/progress contract is now accepted |
| `59` | Friend picker progress UX and rollout closure | `implementation-ready` | `Test-Flight-Improv/29-batch-parallel-intro-sending-session-59-plan.md` | `58` | `prerequisite-blocked` | `accepted` | `0` | `accepted` | `none` | `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`, `UI-20-Intro-friends/intro-feature-spec.md`, `Test-Flight-Improv/00-INDEX.md` | planned after Session `58` acceptance, landed picker progress UX plus localized copy and direct regressions, repaired the stale intro wiring fake needed for truthful verification, and closed Report `29` without widening named-gate ownership |

## Ordered session breakdown

### Session 58

- Title:
  `Capped intro batching and progress-report contract`
- Session id:
  `58`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/29-batch-parallel-intro-sending-session-58-plan.md`
- Initial status:
  `pending`
- Exact scope:
  - take the current batching/progress implementation in
    `sendIntroductions(...)` to an accepted state by verifying or correcting
    ordered batch execution capped at `10` selected friends at a time
  - keep each intro chain logically intact: one intro ID, recipient send,
    introduced-friend send, local intro save, and per-intro flow event
  - ensure later batches do not start until the current batch settles, and one
    intro's fallback path does not block sibling intros or the next batch
  - preserve returned `List<IntroductionModel>` ordering to match input friend
    order
  - keep the use-case progress contract optional and truthful so Session `59`
    can consume it without reading send internals or forcing unrelated caller
    rewrites
  - keep `contactRepo.setIntrosSentAt(...)` as a once-after-all-batches action
- Why it is its own session:
  - one coherent application seam
  - different regression family from picker rendering and localization
  - can land as a meaningful verified state before any visible progress UI is
    added
- Likely code-entry files:
  - `lib/features/introduction/application/send_introduction_use_case.dart`
  - `test/features/introduction/application/send_introduction_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/shared/fakes/fake_p2p_network.dart`
  - `test/shared/fakes/fake_p2p_service_integration.dart`
  - `test/shared/fakes/intro_test_user.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
  - `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
    only for the contract surface, not for final visible progress rendering
- Likely direct tests/regressions:
  - `flutter test test/features/introduction/application/send_introduction_test.dart`
  - `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
  - `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
  - `flutter test test/features/introduction/regression/introduction_regression_test.dart`
    only if the batching or fallback path needs permanent regression coverage
    there
  - targeted deterministic proof that:
    - `10` selected friends run in one batch
    - `15` or `20` selected friends split into `10 + remainder`
    - max active send work never exceeds the cap
    - one intro's send failure or inbox fallback does not block siblings or
      later batches
    - `introsSentAt` is written once after all batches complete
    - progress reports advance truthfully from `0/total` to `total/total`
- Likely named gates:
  - none directly own intro batching today
  - use the direct intro application and integration suites above
  - run `./scripts/run_test_gates.sh completeness-check` only if execution
    adds a brand-new explicitly classified test file
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact with the landed Session `58` contract and
    any clarifications needed by Session `59`
  - do not touch `Test-Flight-Improv/00-INDEX.md` yet unless execution
    unexpectedly closes the whole report in one session
  - do not touch `Test-Flight-Improv/test-gate-definitions.md` unless a new
    intro suite path needs explicit classification
- Dependency on earlier sessions:
  - none

### Session 59

- Title:
  `Friend picker progress UX and rollout closure`
- Session id:
  `59`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/29-batch-parallel-intro-sending-session-59-plan.md`
- Initial status:
  `prerequisite-blocked`
- Exact scope:
  - consume the landed Session `58` progress contract in `FriendPickerWired`
    so the picker can show truthful in-flight progress while batched sending
    runs
  - extend `FriendPickerScreen` to render progress feedback without regressing
    search, selection, close behavior, or the disabled-send contract
  - keep the send button disabled for the entire send window and ensure
    completion exits cleanly through the existing `onIntroductionsSent` path
  - run the direct intro UI and integration acceptance set for the batched
    flow, including the conversation-to-picker wiring path
  - own final report-level doc refresh if the rollout lands as intended
- Why it is its own session:
  - different presentation seam and likely localization surface
  - the picker should consume a settled application progress contract rather
    than inventing UI-only counters
  - this session can honestly own final acceptance and closure without
    requiring a third bookkeeping-only session
- Likely code-entry files:
  - `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
  - `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
  - `test/features/introduction/presentation/screens/friend_picker_test.dart`
  - `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  - `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `lib/l10n/` ARB files only if progress copy requires new localized strings
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
    only if picker launch or completion wiring actually changes
- Likely direct tests/regressions:
  - `flutter test test/features/introduction/presentation/screens/friend_picker_test.dart`
  - `flutter test test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  - `flutter test test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
  - rerun `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
    as a companion acceptance check on the landed Session `58` engine
  - focused proof that:
    - progress is visible while a multi-batch send is in flight
    - progress advances truthfully and reaches total completion
    - the send button stays disabled during the whole operation
    - completion still returns through the existing confirmation or close path
      without duplicate sends
- Likely named gates:
  - none directly own this seam
  - use the direct intro UI and integration suites above
  - run `./scripts/run_test_gates.sh baseline` only if execution changes
    broader conversation or banner entry wiring beyond the picker-owned path
  - run `./scripts/run_test_gates.sh completeness-check` only if execution
    adds a new explicitly classified test file
- Matrix/closure docs to update when done:
  - refresh `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
    with final session outcomes
  - update `UI-20-Intro-friends/intro-feature-spec.md` only for the shipped
    batching and progress send contract, not for unrelated intro flow steps
  - update `Test-Flight-Improv/00-INDEX.md` only if final closure audit wants
    an explicit report-level completion note
  - update `Test-Flight-Improv/test-gate-definitions.md` only if execution
    adds a new intro suite path that is not already classified
- Dependency on earlier sessions:
  - Session `58`

## Why this is not fewer sessions

- One session would couple the hardest correctness risk, bounded parallel send
  behavior, with picker rendering and likely localization changes.
- That combined scope would make it too easy to hide batching bugs behind UI
  assertions or to let UI needs drive a speculative send-state API.
- Session `58` alone leaves the repo in a meaningful verified state: batched
  intro sending works and preserves the current data and fallback contract.
  Session `59` then consumes that settled contract for the user-visible
  progress slice.

## Why this is not more sessions

- A separate Go or bridge session would be fake scope because the proposal and
  current repo both keep batching at the Flutter orchestration layer.
- A separate DB-only session is not justified because intro persistence stays
  the same contract and should be proven inside the batching session unless
  repo evidence exposes a real repository bug.
- A separate acceptance-only or closure-only session would mostly rerun the
  same intro UI, integration, and doc-update work that Session `59` can own
  without losing verification value.

## Regression and gate contract

- Follow `Test-Flight-Improv/14-regression-test-strategy.md` by keeping or
  tightening the drafted Session `58` application regressions in the working
  tree, then adding picker progress and disabled-state coverage in Session
  `59`.
- `Test-Flight-Improv/test-gate-definitions.md` remains the execution source
  of truth for named gates and direct-suite classification.
- No frozen named gate directly owns intro batching or picker progress today,
  so the rollout should stay on direct intro suites unless execution clearly
  touches a gate-owned shared path.
- Minimum direct verification across the session set:
  - `test/features/introduction/application/send_introduction_test.dart`
  - `test/features/introduction/presentation/screens/friend_picker_test.dart`
  - `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
  - `test/features/introduction/integration/intro_wiring_smoke_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
- Companion named-gate rule:
  - `baseline` only if broader conversation or banner entry wiring changes
  - `completeness-check` only if new explicitly classified test files are
    added or reclassified
  - no `1to1`, `feed`, `groups`, `posts`, or `transport` gate widening is
    justified by this split on current repo evidence

## Matrix update contract

- `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md` is
  the live handoff and closure ledger from decomposition onward.
- Session `59` is the single closure owner for stable-doc refreshes if the
  rollout lands:
  - refresh this breakdown artifact unconditionally
  - refresh `UI-20-Intro-friends/intro-feature-spec.md` only if the shipped
    batching or progress behavior materially updates the intro send contract
  - refresh `Test-Flight-Improv/00-INDEX.md` only if final closure audit
    records the report as landed maintenance state
  - refresh `Test-Flight-Improv/test-gate-definitions.md` only if a new intro
    test path needs explicit classification
- No new matrix doc should be created for this report.

## Pipeline run status

- Pipeline controller run date:
  `2026-03-30`
- Recovery-pass outcome:
  kept the recommended plan count at `2`, refreshed the existing Session `58`
  plan, created the Session `59` plan, and treated the live repo state as
  source of truth without reverting unrelated work.
- Session `58` planning outcome:
  refreshed `Test-Flight-Improv/29-batch-parallel-intro-sending-session-58-plan.md`
  and kept the session `implementation-ready`.
- Session `58` execution outcome:
  one fresh spawned execution/QA orchestrator attempt stalled again on the
  retryable `spawn_or_tool_failure` class, so the controller spent the normal
  bounded inner recovery stack locally. The live Session `58` repo state was
  then accepted after these commands passed:
  `flutter test test/features/introduction/application/send_introduction_test.dart`,
  `flutter test test/features/introduction/integration/introduction_smoke_test.dart`,
  `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`,
  and
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`.
- Session `59` planning outcome:
  created `Test-Flight-Improv/29-batch-parallel-intro-sending-session-59-plan.md`
  and kept the session `implementation-ready`.
- Session `59` execution outcome:
  landed picker progress state in `FriendPickerWired` and
  `FriendPickerScreen`, added the localized progress string, repaired the
  stale `_FakeMessageRepository.deleteMessage` test seam in
  `intro_wiring_smoke_test.dart`, and returned passing evidence from
  `flutter test test/features/introduction/presentation/screens/friend_picker_test.dart`,
  `flutter test test/features/introduction/presentation/screens/friend_picker_wired_test.dart`,
  `flutter test test/features/introduction/integration/intro_wiring_smoke_test.dart`,
  `flutter test test/features/introduction/integration/introduction_smoke_test.dart`,
  and
  `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`.
  `baseline` was not rerun here because broader conversation or banner entry
  wiring did not change.
- Final program acceptance verdict:
  `accepted`
- Final program blocker:
  `none`

## Structural blockers remaining

- None.
- Both runnable sessions are accepted, the closure docs are refreshed, and no
  retryable blocker remains open after the bounded recovery pass.

## Accepted differences intentionally left unchanged

- Do not add a Go or bridge batch-send API.
- Do not collapse recipient delivery into one aggregated payload or redesign
  intro notifications.
- Do not introduce cancellation, selection limits, or new retry policies in
  this report.
- Do not reopen picker filtering policy, Orbit follow-up wiring, or Feed intro
  follow-up work from other reports unless the new regressions prove a real
  dependency.
- Do not widen named gates for this rollout unless execution adds a genuinely
  new classified test file.

## Exact docs/files used as evidence

- `Test-Flight-Improv/29-batch-parallel-intro-sending.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `UI-20-Intro-friends/intro-feature-spec.md`
- `lib/features/introduction/application/send_introduction_use_case.dart`
- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
- `lib/core/services/p2p_service.dart`
- `test/features/introduction/application/send_introduction_test.dart`
- `test/features/introduction/presentation/screens/friend_picker_test.dart`
- `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`
- `test/features/introduction/integration/intro_wiring_smoke_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/shared/fakes/fake_p2p_network.dart`
- `test/shared/fakes/fake_p2p_service_integration.dart`

## Why the recovered closure state is stable

- It includes the controller-critical sections the downstream pipeline checks:
  `recommended plan count`, `session ledger`, `ordered session breakdown`, and
  `downstream execution path`.
- Every intended plan path is doc-scoped, non-colliding, and uses the safe
  default naming scheme next to the source doc.
- It recomposes against the live working tree rather than assuming the older
  sequential baseline or discarding the already landed Session `58` edits.
- It preserves the intended runnable session set while also recording the
  exact recovery path that closed the remaining blocker: a fresh spawned
  execution stall recurred in Session `58`, bounded controller-side recovery
  verified the live repo state, and Session `59` then landed on top of that
  accepted application contract.
- It keeps the rollout on the current proven intro architecture:
  per-introduction payloads over single-message APIs, with no protocol
  redesign.
- It assigns tests, conditional gates, dependencies, and closure ownership
  explicitly enough for future maintenance reopens without relying on old
  conversational context.
