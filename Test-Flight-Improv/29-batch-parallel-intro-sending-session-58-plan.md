# Session 58 Plan - Capped intro batching and progress-report contract

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Replace the outer sequential friend loop in
  `lib/features/introduction/application/send_introduction_use_case.dart`
  with ordered batch execution capped at `10` selected friends at a time.
- Keep each intro chain logically intact: generate one intro ID, build the two
  existing payloads, send to recipient, send to introduced friend, save
  locally, and emit the per-intro flow event.
- Preserve returned `List<IntroductionModel>` ordering to match the input
  friend order, not completion order.
- Expose a minimal optional progress-report contract at the use-case seam that
  reports truthful `completed` and `total` counts and can be consumed later by
  Session `59`.
- Keep `contactRepo.setIntrosSentAt(...)` as one once-after-all-batches action.
- Do not add visible picker progress UI, do not change `P2PService` or bridge
  APIs, and do not pull Session `59` work into this session.

### closure bar

- Sending `<= 10` friends completes in one batch; sending `> 10` splits into
  ordered `10 + remainder` batches.
- No more than `10` intro chains are active at once, which also keeps the
  underlying single-message send work bounded at the tested seam.
- Send-false and inbox-fallback cases do not block sibling intros in the same
  batch or later batches.
- Result ordering, two-message delivery semantics, local save semantics, and
  final `introsSentAt` behavior remain intact.
- The progress seam emits an initial `0/total`, advances monotonically as intro
  chains settle, and ends at `total/total`.
- Direct regressions permanently pin cap, split, peak concurrency, fallback
  continuation, ordering, progress, and once-only `introsSentAt`.

### source of truth

- `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
  Session `58` row and Session `58` breakdown entry are the active scope and
  sequencing contract.
- `Test-Flight-Improv/29-batch-parallel-intro-sending.md` supplies the broader
  problem statement and desired batching behavior; the session breakdown wins
  wherever the source doc still bundles UI progress work with the application
  seam.
- Current code and tests beat stale prose:
  - `lib/features/introduction/application/send_introduction_use_case.dart`
  - `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
  - `lib/core/services/p2p_service.dart`
  - `test/features/introduction/application/send_introduction_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
  - `test/shared/fakes/fake_p2p_network.dart`
  - `test/shared/fakes/fake_p2p_service_integration.dart`
  - `test/shared/fakes/in_memory_contact_repository.dart`
  - `test/shared/fakes/intro_test_user.dart`
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of
  truth for named gates and direct-suite classification.
- `Test-Flight-Improv/14-regression-test-strategy.md` supplies the
  regression-first rule and Baseline Gate expectation.
- `UI-20-Intro-friends/intro-feature-spec.md` is not needed to execute Session
  `58`; the current repo and the session breakdown already define the narrow
  application-only contract.

### session classification

`implementation-ready`

### exact problem statement

- `sendIntroductions(...)` still serially awaits each selected friend's two
  sends and local save before starting the next friend, so larger selections
  scale linearly.
- `FriendPickerWired` still only tracks `_isSending`; there is no explicit
  use-case progress seam for Session `59` to consume.
- `P2PService` still exposes only single-message `sendMessage(...)` and
  `storeInInbox(...)`, so batching must remain Flutter-side orchestration over
  the existing single-message contract.
- The current direct application tests prove two-friend happy-path behavior,
  encryption/plaintext branching, persistence, and non-null `introsSentAt`, but
  they do not prove cap batching, peak active work, or truthful progress.
- `sendIntroductions(...)` is also wrapped by `test/shared/fakes/intro_test_user.dart`
  and consumed by intro integration and orbit wiring tests, so the progress
  contract must remain optional and source-compatible for existing callers.
- User-visible behavior that must improve: multi-friend sends should stop
  behaving like one long serial loop.
- Behavior that must stay unchanged: intro payload shape, per-intro
  delivery/fallback semantics, local save behavior, final `introsSentAt`, and
  the no-new-batch-API architecture.

### files and repos to inspect next

- Repo scope stays inside
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app`; no second repo is
  involved.
- Primary production files:
  - `lib/features/introduction/application/send_introduction_use_case.dart`
  - `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
  - `lib/core/services/p2p_service.dart`
- Primary direct tests and helpers:
  - `test/features/introduction/application/send_introduction_test.dart`
  - `test/features/introduction/integration/introduction_smoke_test.dart`
  - `test/features/introduction/integration/introduction_multi_node_test.dart`
  - `test/shared/fakes/fake_p2p_network.dart`
  - `test/shared/fakes/fake_p2p_service_integration.dart`
  - `test/shared/fakes/in_memory_contact_repository.dart`
  - `test/shared/fakes/intro_test_user.dart`
- Blast-radius references only if optional-parameter compatibility is lost:
  - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`

### existing tests covering this area

- `test/features/introduction/application/send_introduction_test.dart`
  currently proves:
  - `N` selected friends yields `N` intro records on a 2-friend happy path
  - ordered recipient/introduction pairing for `[contactC, contactD]`
  - four P2P deliveries for two friends
  - ML-KEM vs plaintext branching
  - local persistence
  - non-null `introsSentAt`
- `test/features/introduction/integration/introduction_smoke_test.dart`
  indirectly exercises the two-friend send path through `IntroTestUser`, but it
  does not assert batching, concurrency cap, or progress reporting.
- `test/features/introduction/integration/introduction_multi_node_test.dart`
  exercises listener-stream delivery and later intro lifecycle flows after a
  send, but not `> 10` sends or batching semantics.
- `test/shared/fakes/fake_p2p_network.dart` already provides delay and
  failure/call-count hooks, but not peak-concurrency tracking.
- `test/shared/fakes/in_memory_contact_repository.dart` stores
  `setIntrosSentAt(...)` effects but does not count calls.
- `Test-Flight-Improv/test-gate-definitions.md` classifies
  `introduction_smoke_test.dart` and `introduction_multi_node_test.dart` as
  optional/manual direct suites, and keeps
  `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  outside the frozen named gate lists unless intro-to-orbit wiring changes.

### regression/tests to add first

- Add the new deterministic batching regressions in
  `test/features/introduction/application/send_introduction_test.dart` before
  touching production code.
- Add direct proof that `10` friends stay in one batch and `15` or `20` split
  into `10 + remainder` without changing result ordering.
- Add direct peak-concurrency proof using the smallest local spy or helper
  extension needed to hold sends open and record max active work.
- Add direct fallback-continuation proof where one or more sends return
  `false` and inbox fallback occurs without blocking sibling intros or the next
  batch.
- Add direct once-only `contactRepo.setIntrosSentAt(...)` proof with a tiny
  tracking wrapper or spy around the existing in-memory repository.
- Add direct progress-contract proof that the seam emits `0/total`, advances
  only when an intro chain fully settles, and finishes at `total/total`.
- Do not add a new regression file or promote these checks into
  `test/features/introduction/regression/introduction_regression_test.dart`
  unless the direct application seam proves insufficient.

### step-by-step implementation plan

1. Add the failing direct regressions in
   `test/features/introduction/application/send_introduction_test.dart`
   before changing production code.
2. Introduce the smallest explicit optional progress seam on
   `sendIntroductions(...)`, likely an optional callback carrying truthful
   `completed` and `total` counts. Emit `0/total` before any batch work starts
   so Session `59` does not need to infer initialization state.
3. Extract the current per-friend logic into a single-intro helper that keeps
   the current inner order: recipient send, introduced-friend send, local save,
   then per-intro flow event emission.
4. Replace the outer sequential loop with ordered chunking over slices of at
   most `10`, launch one future per friend in the current batch, and wait for
   that batch to settle before starting the next.
5. Keep result ordering tied to input order by collecting the batch futures in
   slice order and flattening them in that same order, not completion order.
6. Update progress only after each intro chain settles, not after raw network
   send attempts or batch boundaries, so the contract reflects user-meaningful
   completion.
7. Keep `_sendPayload(...)`, `P2PService`, and bridge behavior unchanged; rely
   on the existing send-false to inbox-fallback path inside each intro chain.
8. After all batches settle, call `contactRepo.setIntrosSentAt(...)` once, emit
   the final done event, and return ordered results.
9. Only if the new tests expose a real seam gap, make the smallest helper
   change required in `FakeP2PNetwork`, `InMemoryContactRepository`, or
   `IntroTestUser`; do not pre-emptively widen shared test infra.
10. Stop and re-evaluate if implementation starts requiring non-optional caller
    updates, picker rendering changes, localization, notification-contract
    redesign, or bridge/API changes.

### risks and edge cases

- Collecting results by completion order would silently regress the current
  two-friend ordering contract.
- A progress callback that is not optional would widen the blast radius across
  `FriendPickerWired`, `IntroTestUser`, and many existing intro/orbit tests.
- Progress must reflect a completed intro chain, not a batch start or a first
  send attempt, otherwise Session `59` will consume a misleading contract.
- Peak-concurrency proof is not available from current helpers; the new direct
  regression will need either a file-local spy or a very small fake extension.
- Send-false and inbox fallback are the intended continuation path; unexpected
  hard exceptions from crypto or persistence should not be swallowed just to
  force later batches through.
- Per-intro `SEND_INTRODUCTION_SENT` event order may vary under concurrency and
  should not be over-specified in tests.

### exact tests and gates to run

- `flutter test test/features/introduction/application/send_introduction_test.dart`
- `flutter test test/features/introduction/integration/introduction_smoke_test.dart`
- `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh completeness-check` only if execution adds a
  brand-new test file path that is not already classified in
  `Test-Flight-Improv/test-gate-definitions.md`
- `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  only if implementation breaks optional-parameter compatibility or touches
  intro-to-orbit follow-up wiring

### known-failure interpretation

- None of the consulted docs mark the targeted intro application or optional
  direct intro suites as accepted red tests.
- Treat failures in
  `test/features/introduction/application/send_introduction_test.dart`,
  `test/features/introduction/integration/introduction_smoke_test.dart`,
  `test/features/introduction/integration/introduction_multi_node_test.dart`,
  or `./scripts/run_test_gates.sh baseline` as real regressions for Session
  `58` unless a rerun proves unrelated flake.
- If `orbit_intros_wiring_test.dart` is rerun because the blast radius grew,
  treat its failures as real regressions, not as optional noise.
- A failing completeness check means the new test file path is unclassified,
  not that batching behavior is wrong.

### done criteria

- `sendIntroductions(...)` runs selected friends in batches capped at `10`.
- Later batches start only after the current batch settles.
- Ordered results still align with input friend order.
- Each intro still performs its two sends, local save, and per-intro flow
  event emission.
- `contactRepo.setIntrosSentAt(...)` happens once after all batches complete.
- A minimal optional progress contract exists at the use-case seam and is
  sufficient for Session `59` to consume without reading send internals.
- Permanent direct regressions cover cap, split, peak concurrency, fallback
  continuation, progress, and once-only `introsSentAt`.
- The listed direct suites and Baseline Gate pass.

### scope guard

- No visible picker progress UI, button-copy changes, localization, or
  `FriendPickerScreen` rendering changes in Session `58`.
- No non-optional signature change that forces widespread caller edits.
- No batch API in `P2PService`, Flutter bridge, or Go code.
- No cancellation, retry-policy changes beyond existing inbox fallback, or
  selection-limit product work.
- No notification aggregation redesign.
- No broad repository/database refactor unless the new regressions prove a
  concrete save-layer defect.
- Do not touch unrelated dirty worktree changes.

### accepted differences / intentionally out of scope

- Session `58` owns the batching engine and progress-report contract, not the
  picker UX that consumes it.
- The source doc's UI progress cases are intentionally split: Session `58`
  lands the truthful use-case seam, Session `59` lands the visible picker
  rendering.
- The current per-introduction payload/send model stays intact even though the
  product prose originally described the work as one feature.
- Per-intro `SEND_INTRODUCTION_SENT` event order may vary under concurrency;
  the stable contract is one event per completed intro plus one final done
  event.
- No persisted/background progress state is introduced.

### dependency impact

- Session `59` must consume the Session `58` progress seam instead of inventing
  picker-local counters or timing assumptions.
- If Session `58` cannot keep the progress seam optional and truthful, Session
  `59` must be replanned before implementation.
- If execution unexpectedly requires orbit or other intro call-site changes,
  the blast radius should be documented before Session `59` planning proceeds.
- After Session `58` lands, refresh
  `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
  with any clarified progress semantics before planning or executing Session
  `59`.

## Structural blockers remaining

- None.

## Incremental details intentionally deferred

- Whether the optional progress seam uses a tiny value type or a minimal
  callback signature can be decided during execution as long as it stays
  optional, truthful, and source-compatible.
- Whether the peak-concurrency proof lives in a file-local spy or a very small
  fake extension can be decided by the first failing regression.

## Accepted differences intentionally left unchanged

- No visible picker progress UI in Session `58`.
- No new batch API below the Flutter use case.
- No requirement to touch orbit wiring unless optional-parameter compatibility
  is lost.

## Exact docs/files used as evidence

- `Test-Flight-Improv/29-batch-parallel-intro-sending-session-breakdown.md`
- `Test-Flight-Improv/29-batch-parallel-intro-sending.md`
- `Test-Flight-Improv/29-batch-parallel-intro-sending-session-58-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/introduction/application/send_introduction_use_case.dart`
- `lib/features/introduction/presentation/screens/friend_picker_wired.dart`
- `lib/core/services/p2p_service.dart`
- `test/features/introduction/application/send_introduction_test.dart`
- `test/features/introduction/integration/introduction_smoke_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/shared/fakes/fake_p2p_network.dart`
- `test/shared/fakes/fake_p2p_service_integration.dart`
- `test/shared/fakes/in_memory_contact_repository.dart`
- `test/shared/fakes/intro_test_user.dart`

## Why the plan is safe or unsafe to implement now

- Safe to implement now because the plan is pinned to the current sequential
  use-case code, keeps the progress seam optional to avoid widening the call-site
  blast radius, adds regression-first proof for the new batching behavior, and
  limits verification to the intro suites and baseline gate that actually cover
  this seam.
