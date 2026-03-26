# Session 26 Plan: Make Group Sends Explicitly Sequential In One Thread

## 1. real scope

Close the remaining determinism gap from `18-group-discussion-reliability-audit.md`: one group conversation screen should not start overlapping local send pipelines. Group sends should be intentionally sequential, not merely “best effort” because the user happened to tap slowly.

Concrete repo evidence already narrows the scope:
- `lib/features/conversation/presentation/widgets/compose_area.dart` already supports disabling send when `isSending` is true.
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` builds `ComposeArea(...)` without passing `isSending`.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` exposes `_onSend(...)` and `_onRecordStop()` as separate local send entrypoints with no shared explicit reentry guard.
- `test/features/conversation/presentation/widgets/compose_area_test.dart` already proves the shared compose widget disables send when `isSending` is true.
- `test/features/groups/presentation/group_conversation_wired_test.dart` already covers text/media/voice send behavior, including voice-stop send kickoff, but does not currently pin “only one local send pipeline at a time across all entrypoints”.
- `test/features/groups/integration/group_edge_cases_smoke_test.dart` currently uses sequential await for its “rapid message burst” case and explicitly says it is not proving concurrent local send serialization.

In scope:
- add the missing regression first for “no overlapping local send pipelines from one group thread”
- choose and pin one explicit local contract for the group screen:
  - required contract: while one local group send pipeline is active for the screen, a second local send start is blocked rather than queued
  - that contract must apply to both `_onSend(...)` and `_onRecordStop()`, not only the text-send button path
- keep the authoritative contract in one shared group-screen guard, not only in `ComposeArea`, because `isSending` there only disables the send-arrow path and does not serialize voice-stop callbacks
- preserve send order and deterministic UI behavior within one conversation screen
- preserve the existing composer-only update pattern if the implementation threads send state through the group screen
- lock the send-state shape before execution:
  - preferred path: keep the guard and any send-state ownership local to `group_conversation_wired.dart`
  - if preserving the composer-only update pattern requires touching shared composer state in `conversation_screen.dart` / `ConversationComposerViewState`, treat that as expanded shared-surface scope and run the matching 1:1 direct tests + `1to1` gate
- keep the fix local to the group screen / wired orchestration seam

Out of scope:
- durable outbox design
- local FIFO or queue architecture unless a failing regression proves a simple guard cannot satisfy the required contract
- distributed ordering protocol
- changing transport / bridge behavior
- changing media retry parity or upload durability
- changing delivery semantics, read receipts, or acknowledgements
- broad lifecycle or startup ordering work unless a minimal compatibility adjustment is unavoidable
- assuming the 1:1 voice path already proves cross-entry `_onSend(...)` + `_onRecordStop()` serialization; it does not

## 2. session classification

`implementation-ready`

Why:
- the gap is concrete and local to the group UI/send orchestration layer
- the 1:1 conversation path already demonstrates the minimal `_onSend(...)` / send-button-disable guard shape
- cross-entry text-send + voice-stop blocking is still a new group-specific contract that must be proven directly
- the main missing piece is one shared local guard + regression coverage, not new infrastructure

Execution note:
- there is no longer a hard dependency on an “accepted Session 25” before this session because the ordinary-media parent-row durability foundation is already present in the current repo
- execution should still stay local to Session 26 scope and should not reopen Session 25 retry/lifecycle work

## 3. files and repos to inspect next

Primary planning / rationale docs:
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/session-25-plan.md`

Primary code:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart` as the existing 1:1 reference for local `_isSending` guard / release semantics
- `lib/features/conversation/presentation/screens/conversation_screen.dart` as the existing 1:1 reference for `isSending` UI wiring

Primary tests:
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/conversation/presentation/widgets/compose_area_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart` only if shared conversation/composer state is touched
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` only if shared conversation/composer state is touched
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` only if the chosen implementation touches send-phase background-task ordering

Gate / regression references:
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh 1to1` only if the implementation touches shared conversation/composer files or other shared 1:1 send-surface code
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` only if the implementation escapes into lifecycle / lock-unlock / recovery wiring

Execution note:
- `./scripts/run_test_gates.sh` is the execution source of truth for named gates.
- `Test-Flight-Improv/14-regression-test-strategy.md` is the policy/rationale reference for why this session adds the regression first and then runs direct suite + gates.
- `Test-Flight-Improv/test-gates-reference.md` is not required for Session 26 because it does not add anything essential beyond the frozen gate definitions.
- `Test-Flight-Improv/test-gate-definitions.md` remains the planning reference for gate membership and documented known failures, but its known-failure ledger must be revalidated against the current repo state before being treated as authoritative.
- the checked-in known-failure ledger currently still marks `baseline` red, and its cited `integration_test/loading_states_smoke_test.dart:288` location is stale because that file is now shorter in the current repo.
- do not treat any older local rerun note as authoritative until it is re-run in the current workspace.

## 4. existing tests covering this area

Already present and relevant:
- `test/features/conversation/presentation/widgets/compose_area_test.dart`
  - already proves the shared compose widget disables send when `isSending` is true
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  - covers group composer rendering and composer-state wiring, including the composer-only rebuild boundary, but not explicit `isSending` propagation
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - already protects the 1:1 composer-only rebuild boundary on the shared conversation surface
  - becomes required companion coverage only if Session 26 touches shared composer state or shared conversation screen wiring rather than staying group-local
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - already protects the 1:1 wired composer-update boundary on the shared conversation surface
  - becomes required companion coverage only if Session 26 touches shared composer state or shared conversation screen wiring rather than staying group-local
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - covers many group send/orchestration paths, including voice-stop send kickoff and failure restore behavior, but does not currently pin “only one local send pipeline at a time across `_onSend(...)` and `_onRecordStop()`”
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
  - covers a rapid burst, but explicitly uses sequential await and therefore does not prove overlapping local sends are prevented

What is missing:
- no direct regression currently proves a second send cannot start while the first send is still in flight
- no direct regression currently proves text/media send and voice-stop send share the same local serialization guard
- no direct regression currently proves the shared local guard releases after success so a later send can start
- no direct regression currently proves the shared local guard releases after failure / early return so the thread does not deadlock
- no direct regression currently proves the group screen passes or honors explicit sending state in the composer path without breaking the composer-only rebuild boundary
- no direct regression currently proves that any shared composer-state change preserves the existing 1:1 composer-only rebuild boundary if `ConversationComposerViewState` or other shared conversation-surface files are edited
- no direct regression currently pins the chosen product contract for the second send attempt: blocked until the first local pipeline finishes

## 5. regression/tests to add first, if any

Yes. Add the orchestration regression first in `test/features/groups/presentation/group_conversation_wired_test.dart`.

Minimum first regressions:
- gate a first text/media send so it stays in flight
- attempt a second text/media send from the same group conversation while the first is still active
- prove the second attempt does not start a concurrent publish/send pipeline
- add one cross-entry regression:
  - keep a first send in flight
  - attempt to start the other local entrypoint (`_onRecordStop()` if the first path was `_onSend(...)`, or vice versa)
  - prove it also does not start a concurrent local pipeline
- add one release regression:
  - let the first gated send finish
  - prove a later send can then start normally
- add one failure / early-return release regression:
  - force the first path to fail or return early while it owns the guard
  - prove the guard clears and a later send can start
- prove the chosen explicit contract:
  - required contract: the second local send start is blocked while the first local pipeline is active
  - do not introduce queue semantics unless a failing regression proves the guard cannot cover the required behavior

Required companion regression:
- add one narrow screen-level assertion in `test/features/groups/presentation/group_conversation_screen_test.dart` if the implementation wires a new `isSending` prop through the group screen
- if send state is threaded through the screen, keep the existing composer-only update contract explicit in that screen-level test
- if preserving composer-only update behavior requires touching shared composer-state files instead of a group-only prop, add matching direct coverage in `test/features/conversation/presentation/screens/conversation_screen_test.dart` and `test/features/conversation/presentation/screens/conversation_wired_test.dart` so the 1:1 composer-only rebuild boundary stays pinned too

Do not add a new integration harness unless the widget/orchestration tests fail to capture the behavior cleanly.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not required. This session is not profile-gated or evidence-gated.

The repo evidence is already enough to proceed:
- the shared widget has an `isSending` seam
- the group screen currently does not use it
- the group wired layer currently has two local send entrypoints and no shared reentry guard
- the 1:1 path already proves `_onSend(...)` / send-button guard semantics, but it does not prove cross-entry text-send + voice-stop serialization
- `ComposeArea.isSending` is only a UI affordance for the send-arrow path, so the authoritative contract still has to live in a shared group-screen guard
- the current burst test is intentionally not a concurrency proof

## 7. step-by-step implementation or evidence-collection plan

1. Re-open the 1:1 reference path in `conversation_wired.dart`, `conversation_screen.dart`, and `compose_area.dart`.
   - confirm how the local `_isSending` guard is entered and released there
   - confirm how `isSending` is exposed to the shared compose widget there
   - do not treat the 1:1 path as proof of cross-entry `_onSend(...)` + `_onRecordStop()` serialization
2. Re-open the group screen/wired path.
   - confirm that `GroupConversationScreen` currently has no `isSending` prop
   - confirm that `_onSend(...)` and `_onRecordStop()` currently have no shared local reentry guard
3. Add the failing regressions first in `test/features/groups/presentation/group_conversation_wired_test.dart`.
   - hold the first send in flight with a gate
   - attempt a second text/media send immediately
   - prove no overlapping local send pipeline starts
   - add a cross-entry attempt through the voice-stop path (or the reverse ordering if that test shape is cleaner)
   - prove the second local start is blocked rather than queued
   - add a release regression that proves a later send can start once the first in-flight path finishes
   - add a failure / early-return release regression that proves the guard clears after upload / publish failure or any equivalent early return
4. Add a narrow companion screen-level test in `group_conversation_screen_test.dart` if the implementation adds explicit `isSending` propagation.
   - keep the composer-only rebuild contract explicit if the screen-level prop is added
   - if preserving that contract requires touching shared conversation/composer state, add matching direct regressions in `conversation_screen_test.dart` and `conversation_wired_test.dart`
5. Implement the smallest safe production change.
   - preferred path:
     - add one explicit screen-local send-in-flight guard in `group_conversation_wired.dart`
     - use it from both `_onSend(...)` and `_onRecordStop()`
     - keep guard ownership local to the group wired seam if possible
     - wire `isSending` through to `ComposeArea` only if needed for the UI-level block / affordance
     - if preserving composer-only updates cannot be done without shared composer-state edits, treat that as expanded scope and run the extra 1:1 suites / gate rather than assuming the group tests are enough
     - release the guard on success, failure, and every early-return path that should unblock a later send
   - fallback path only if a failing direct regression proves the simple guard is insufficient:
     - add the smallest possible additional local coordination
     - keep it purely in-memory and screen-local
6. Preserve current behavior:
   - no change to transport or publish semantics
   - no change to media durability or retry ownership
   - no change to voice/media send ownership beyond sharing the same local reentry guard
   - no change to the shared `ComposeArea` contract unless a tiny compatibility change is required
   - no change to the shared 1:1 conversation surface unless a tiny compatibility change is required to preserve the composer-only update path
7. Re-run the direct tests.
8. Run the Group Messaging Gate.
9. Run the 1:1 Reliability Gate only if the implementation changed shared conversation/composer files or other shared 1:1 send-surface code.
10. Run the Baseline Gate.
   - specify `FLUTTER_DEVICE_ID=<device-id>` when multiple Flutter targets are attached
11. Run the Startup / Transport Gate only if the implementation unexpectedly changes lifecycle / background-task / recovery wiring.
12. Interpret gate outcomes against the currently documented known failures in `Test-Flight-Improv/test-gate-definitions.md`.
    - current rerun output is the source of truth; do not rely on stale gate notes alone
    - `./scripts/run_test_gates.sh` is the source of truth for gate membership
    - revalidate any claimed known failure against the current repo before using it as an explanation
    - a pre-existing red `baseline` or `transport` item should not be treated as a Session 26 regression unless the changed code clearly caused or widened it

## 8. risks and edge cases

- Do not widen this into a durable outbox queue.
- Do not accidentally fix only the text-send button while leaving `_onRecordStop()` able to start a concurrent local pipeline.
- Do not accidentally drop a user’s second send attempt without making the chosen contract explicit and tested.
- The chosen contract for this session is “block while sending”; make sure the UI state is clear and the first send reliably releases the guard on success, failure, and all early returns.
- Do not assume the 1:1 reference path already proves cross-entry serialization; it only proves the narrower `_onSend(...)` / send-button guard shape.
- Do not expand the implementation into a local FIFO unless a failing regression proves the simple guard cannot satisfy the required behavior.
- Do not break voice/media send paths while adding explicit send serialization.
- Do not introduce deadlocks where a failed send never clears the sending guard.
- If send state is threaded through the group screen, do not break the composer-only rebuild boundary already covered in `group_conversation_screen_test.dart`.
- If shared `ConversationComposerViewState` or other shared conversation-surface files are touched to preserve that boundary, do not skip the matching 1:1 direct tests and `1to1` gate.
- Do not break existing optimistic message rendering or composer restore behavior.
- Do not widen the fix into lifecycle, background-task, or transport code unless the smallest implementation truly requires it.
- Do not misread a previously documented red named gate as a Session 26 failure if the failure is already listed under known failures in `Test-Flight-Improv/test-gate-definitions.md` and is unrelated to the changed files.
- Do not trust a documented known-failure note or older local rerun explanation without checking that it still matches the current files and failure shape.

## 9. exact tests to run after implementation, if code changes occur

Direct tests:
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`

Conditional shared conversation coverage if shared conversation/composer files are changed:
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`

Conditional shared-widget safety net only if `ComposeArea` is changed:
- `flutter test test/features/conversation/presentation/widgets/compose_area_test.dart`

Optional nearby integration safety net if the direct tests still leave a determinism ambiguity:
- `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart`
  - note: this is not the primary concurrency proof because its rapid-burst case is intentionally sequential today

Conditional background-task safety net only if the implementation touches send-phase background-task ordering:
- `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`

## 10. subsystem gate(s), if relevant

Required:
- Group Messaging Gate
  - `./scripts/run_test_gates.sh groups`

Conditional shared-surface gate:
- 1:1 Reliability Gate
  - only if implementation touches `conversation_screen.dart`, `conversation_wired.dart`, shared composer state, or any other shared 1:1 send-surface code while preserving the group composer update behavior
  - `./scripts/run_test_gates.sh 1to1`

Not required by default:
- Startup / Transport Gate
  - only if the implementation changes lifecycle, lock/unlock, startup, or recovery orchestration rather than only the group screen send seam

## 11. whether Baseline Gate is required

Yes, if production code changes land in `group_conversation_wired.dart`, `group_conversation_screen.dart`, the shared compose path, or any shared conversation/composer state used by both group and 1:1 surfaces.

Command:
- `./scripts/run_test_gates.sh baseline`
- if multiple Flutter targets are attached, use `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh baseline`

Interpretation note:
- `./scripts/run_test_gates.sh` is the execution source of truth
- do not rely on stale known-failure notes alone
- the checked-in known-failure ledger currently still documents `baseline` as red
- its cited `integration_test/loading_states_smoke_test.dart:288` location is stale because the file is now shorter, so the exact explanation must be revalidated on rerun
- a plain `baseline` invocation may fail for environment reasons when multiple Flutter targets are attached and no device is specified
- only treat it as a Session 26 regression if the changed scope clearly introduced or widened the failure
- if a red result remains after using the correct device invocation, evaluate it against the known-failure ledger in `Test-Flight-Improv/test-gate-definitions.md`

## 12. whether Startup / Transport Gate is required

No, not by default.

Run it only if the implementation changes:
- lifecycle / pause-resume wiring
- background-task ordering around send completion
- startup / recovery orchestration
- device-backed recovery behavior beyond the local screen send guard

Command when needed:
- `./scripts/run_test_gates.sh transport`
- if multiple Flutter targets are attached, use `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`

Interpretation note:
- if `transport` is run, use the same known-failure rule from `Test-Flight-Improv/test-gate-definitions.md`
- revalidate any claimed transport known failure against the current repo state before using it as a pass/fail explanation
- do not reopen unrelated existing transport-gate failures as part of Session 26 unless the send-serialization fix clearly affects them

## 13. done criteria

Session 26 is done when all of the following are true:
- a sequential-send regression was added first
- one group conversation screen can no longer start overlapping local send pipelines
- the chosen contract is explicit and tested:
  - second local send start is blocked while the first local pipeline is active
  - that contract is proven across both `_onSend(...)` and `_onRecordStop()`
- a later send can start again after the first path succeeds
- a later send can start again after the first path fails or returns early
- the implementation stays small and local
- the composer-only rebuild boundary is preserved if screen-level send-state wiring is added
- if shared conversation/composer files changed, the matching 1:1 direct tests pass and the 1:1 Reliability Gate passes
- media/voice/text send behavior still works
- the direct tests pass
- the Group Messaging Gate passes
- the Baseline Gate is rerun on the current workspace, using an explicit device when the environment requires it, and any remaining red result is shown to be pre-existing / unrelated before Session 26 is accepted
- the Startup / Transport Gate passes if execution touched that layer

## 14. dependency impact on later sessions if this session blocks

If Session 26 blocks:
- the group reliability program still has a smaller remaining determinism gap even after Sessions 24 and 25 harden the main media/voice trust path
- users may still experience locally ambiguous behavior when sending multiple messages rapidly from the same group thread, including cross-entry cases such as text send plus voice stop
- later group-cleanup work can still proceed, but the “fast sequential” UX contract would remain unpinned
