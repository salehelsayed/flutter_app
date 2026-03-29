# Session 37 Plan — 1:1 Network-Switch Failure Recovery Regressions

## Real Scope

What changes in this session:

- add one deterministic regression for the foreground case where a 1:1 send
  fails during a transport/network switch, then auto-heals on the next
  online-transition retry while the app stays open
- add one deterministic regression for the lock/resume case where that same
  failed row is preserved across pause and then recovers exactly once on resume
- update the 1:1 test-matrix and closure docs so this scenario is explicitly
  classified in the correct layer and not rediscovered later

What does not change in this session:

- no production messaging, retry, lifecycle, or transport code
- no new multi-device harness
- no new simulator/emulator + CLI orchestrator work
- no UI redesign for failed/retrying status
- no guarantee changes for fully suspended background retry behavior

---

## Closure Bar

This session is sufficient when all of the following are true:

- the repo has an explicit regression for:
  - failed foreground send during transport loss -> online transition heals the
    same row exactly once
  - failed foreground send -> user locks/pauses -> resume heals the same row
    exactly once
- at least one of those regressions lives inside the existing 1:1 named gate
  without widening the gate list
- the broader 1:1 test matrix clearly records where these scenarios live
- closure docs make the current promise precise:
  foreground retry after network return is covered; full suspended-background
  retry remains an accepted limitation unless future code changes that contract

---

## Source of Truth

Authoritative sources for this session:

- current 1:1 closure bar:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- current 1:1 matrix mapping:
  `Test-Flight-Improv/session-33-plan.md`
- regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- named gate membership:
  `Test-Flight-Improv/test-gate-definitions.md`
- current retry/lifecycle/send code:
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/core/services/pending_message_retrier.dart`
  - `lib/core/lifecycle/handle_app_paused.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`

Conflict rules:

- current code and tests beat stale prose
- `test-gate-definitions.md` and `scripts/run_test_gates.sh` win on named-gate
  membership
- this session should tighten the matrix and closure docs around what the repo
  already proves, not broaden the program

---

## Session Classification

`implementation-ready`

Why:

- the missing coverage is now concrete and narrow
- existing fake-network and lifecycle helpers already support the scenario
- the work is test-only plus doc classification

---

## Exact Problem Statement

The repo has adjacent coverage for:

- happy-path transport switching
- relay-down degradation and online-transition retry
- send-then-lock / pause-resume recovery

But it does not yet pin the exact user-visible seam that was observed on two
devices:

1. sender taps send during a network switch
2. UI shows `Failed to send message. Message saved.`
3. keeping the app open eventually sends the same row after the node becomes
   online again
4. if the user locks the phone after that failure, the same row should still be
   recoverable on resume exactly once

What must improve:

- that exact combined seam must have deterministic regression coverage
- the matrix must say where the scenario is covered
- the closure docs must distinguish covered foreground/resume recovery from the
  still-accepted limitation of fully suspended background retry semantics

What must stay unchanged:

- no change to send/retry semantics
- no change to snackbar text or status icons
- no attempt to promise stronger background behavior than the current code

---

## Files And Repos To Inspect Next

Production/reference files:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/core/lifecycle/handle_app_paused.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`

Primary tests:

- `test/integration/relay_down_degradation_integration_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `test/core/resilience/f2_transport_switch_recovery_test.dart`
- `test/integration/rapid_lock_unlock_integration_test.dart`

Docs to update after implementation:

- `Test-Flight-Improv/session-33-plan.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`

---

## Existing Tests Covering This Area

Already covered:

- happy-path transport switching:
  `test/core/resilience/f2_transport_switch_recovery_test.dart`
- degradation and online-transition retry, but without the exact
  user-triggered send-failure seam:
  `test/integration/relay_down_degradation_integration_test.dart`
- send-then-lock / pause-resume recovery:
  `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- rapid repeated pause/resume exact-once:
  `test/integration/rapid_lock_unlock_integration_test.dart`
- stuck `sending` -> `failed` -> retry flow:
  `test/features/conversation/integration/stuck_sending_recovery_test.dart`

Missing:

- one deterministic regression that starts with a real `sendChatMessage(...)`
  failure during transport loss and proves foreground online-transition healing
- one deterministic regression that starts from that failed row, pauses, then
  proves resume recovery exactly once

---

## Regression / Tests To Add First

Add these tests first:

1. `test/integration/relay_down_degradation_integration_test.dart`
   - add a test for:
     `send fails during transport loss -> row persists as failed with envelope
     -> online transition retrier heals the exact same row once`
   - this is the closest existing deterministic home for the “phone kept open”
     case

2. `test/features/conversation/integration/send_then_lock_delivery_test.dart`
   - add a test for:
     `send fails during transport loss -> user pauses/locks ->
     handleAppResumed retry heals the exact same row once`
   - this keeps the lock-after-failure proof inside an existing 1:1 gate member
     without widening the named gate list

Do not add a new top-level test file unless one of those files proves too
awkward after inspection.

---

## Step-By-Step Implementation Plan

1. Confirm the existing fake transport/lifecycle helpers can force:
   - direct send failure
   - inbox failure on the initial send
   - later online recovery
2. Add the foreground auto-heal regression in
   `test/integration/relay_down_degradation_integration_test.dart`.
3. Add the lock/resume recovery regression in
   `test/features/conversation/integration/send_then_lock_delivery_test.dart`.
4. Keep both tests exact-once:
   - same message ID
   - one sender row
   - one receiver delivery after the recovery path appropriate to the test
5. Run the direct suites.
6. Run the named 1:1 gate because a gate member file changed.
7. Run `./scripts/run_test_gates.sh completeness-check` if gate docs or matrix
   classification text changes.
8. Update closure docs so the scenario is recorded as covered in the correct
   places without overclaiming stronger background guarantees.

Stop rule inside implementation:

- if a test requires real device network orchestration to be trustworthy, stop
  and keep it out of scope for this session
- prefer deterministic fake-network/lifecycle proof over a new flaky device
  harness

---

## Risks And Edge Cases

- a foreground retry test can accidentally prove only inbox persistence, not the
  online-transition retrier, unless the state transition is explicit
- a lock/resume test can accidentally prove only sender-row status change unless
  receiver-side delivery or inbox drain is asserted deliberately
- the closure docs can overclaim “background retry while suspended” if they do
  not distinguish foreground online-transition retry from resume-time recovery
- widening the named 1:1 gate is unnecessary if one regression can live inside
  an existing gate member file

---

## Exact Tests And Gates To Run

Direct tests:

- `flutter test test/integration/relay_down_degradation_integration_test.dart`
- `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh 1to1`

Required classification check if docs/gate definitions change:

- `./scripts/run_test_gates.sh completeness-check`

Not required by default:

- `./scripts/run_test_gates.sh baseline`
  - no Flutter production code change is planned
- `./scripts/run_test_gates.sh transport`
  - this session adds deterministic regressions and doc classification, not a
    real-stack transport harness change

---

## Known-Failure Interpretation

- Treat the named gates according to `Test-Flight-Improv/test-gate-definitions.md`.
- Do not misclassify any unrelated pre-existing red item as a Session 37
  regression.
- The session is only blocked by failures in:
  - the two changed direct suites
  - the 1:1 gate
  - or completeness-check if gate/classification docs are edited

---

## Done Criteria

- the foreground network-switch failure -> online-transition recovery seam has
  a deterministic regression
- the lock-after-failure -> resume recovery seam has a deterministic regression
- the lock-after-failure proof lives inside an existing 1:1 gate member file
- the direct suites pass
- the 1:1 gate passes
- completeness-check passes if classification docs changed
- the 1:1 matrix and closure docs now record the scenario accurately

---

## Scope Guard

- do not change production send/retry/lifecycle code
- do not add a new device or CLI orchestration layer
- do not widen the named transport gate
- do not redesign failure/retrying UI in this session
- do not claim guaranteed delivery while the app is fully suspended unless the
  implementation actually changes that contract

---

## Accepted Differences / Intentionally Out Of Scope

- the repo may still auto-heal a failed row later without explicitly surfacing
  “retrying in background” to the user; that UX gap is not fixed here
- fully suspended/background retry semantics remain weaker than
  foreground-online-transition or resume recovery semantics
- real two-device network-flip orchestration stays in the device/nightly tier,
  not this deterministic regression session

---

## Dependency Impact

- future 1:1 reliability or transport work should use these regressions before
  asking for new network-switch coverage
- future matrix updates should treat this seam as covered and avoid inventing a
  second harness unless a new real-stack bug proves the need
- closure docs should become the maintenance-time reference so the session plan
  is not the only record
