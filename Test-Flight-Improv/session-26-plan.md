# Session 26 Plan: Explicit Group Send Serialization Closure

## 1. real scope

Session 26 is no longer an open implementation session.

Current repo evidence shows the targeted one-thread group send serialization gap is already closed:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` now owns a shared `_isSending` guard through `_tryBeginSendFlow()` / `_endSendFlow()`.
- that guard is used by both `_onSend(...)` and `_onRecordStop()`.
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` now passes `isSending` through to `ComposeArea`.
- `test/features/groups/presentation/group_conversation_wired_test.dart` already proves:
  - a second text send is blocked while the first local send is in flight and is released after success
  - a voice send blocks a text send while the voice pipeline is active and is released after failure
- `test/features/groups/presentation/group_conversation_screen_test.dart` already proves the `isSending` affordance is threaded through the group compose path.

Scope for Session 26 now:
- document the session as `stale/already-covered`
- preserve the current explicit local send-serialization evidence
- update stale docs that still describe explicit sequential send behavior as open work

Out of scope:
- new production code
- queue/outbox architecture
- transport/lifecycle changes
- new gates caused only by doc edits

## 2. session classification

`stale`

Why:
- the targeted group send-serialization contract is already present in production code
- the direct regression proof is already present
- remaining residual discussion-reliability work is narrower than the original Session 26 scope

## 3. files and repos to inspect next

Primary closure docs:
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`

Primary production seam:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`

Primary direct proof:
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`

Supporting adjacent coverage:
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`

## 4. existing tests covering this area

Primary direct proof already in repo:
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `blocks a second text send while the first local send is in flight and releases after success`
  - `voice send blocks text send while the voice pipeline is active and releases after failure`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  - `passes isSending through to the compose send affordance`

Supporting adjacent proof:
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
  - still acts as broader pressure coverage, but it is not the primary concurrency proof

## 5. regression/tests to add first, if any

None.

Session 26’s send-serialization regressions are already present.

If a closure rerun shows the voice-path proof no longer reaches the durable
upload/send window because its test harness drifted, refresh that existing
widget proof in place before accepting the session. Keep that correction
test-only and do not reopen production scope.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Required stale-session evidence:
- `group_conversation_wired.dart` owns one shared local send-in-flight guard
- both `_onSend(...)` and `_onRecordStop()` use that guard
- `group_conversation_screen.dart` threads `isSending` to the compose affordance
- direct widget tests already prove blocked second-send behavior and release after success/failure
- stale docs claiming sequential send behavior is still open are updated

Direct proof rerun used for this closure pass:
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "blocks a second text send while the first local send is in flight and releases after success"`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "voice send blocks text send while the voice pipeline is active and releases after failure"`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "passes isSending through to the compose send affordance"`

Voice-proof harness note:
- keep the voice guard proof on a valid durable-voice path
- use a recording duration that clears the fake-recorder short-recording cutoff
- use the durable media test file manager and `tester.runAsync(...)` around
  stop/upload so the proof actually enters the active voice pipeline it is
  asserting about

## 7. step-by-step implementation or evidence-collection plan

1. Re-open the group send seam and confirm the shared `_isSending` guard is present.
2. Re-open the direct widget tests that prove the blocked/released contract.
3. Re-run the smallest direct proof for the landed serialization seam.
   - if the voice-path proof has gone stale at the harness level, tighten that
     proof first without changing production behavior
4. Update `Test-Flight-Improv/session-26-plan.md` to stale/closure state.
5. Update stale reliability summaries that still describe explicit sequential send behavior as open work.
6. Mark Session 26 `accepted` and continue to Session 27.

## 8. risks and edge cases

- Do not reopen already-landed group send guard work.
- Do not overclaim queue semantics; the landed contract is blocked second-send start, not a FIFO outbox.
- Do not confuse the broader edge-case smoke test with the primary direct proof.
- Do not rerun named gates for doc-only closure unless unexpected production edits appear.

## 9. exact tests to run after implementation, if code changes occur

No production implementation is planned for Session 26.

If unexpected production edits appear, the required direct suites would be:
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`

Optional nearby integration safety net if the serialization seam changes again:
- `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart`

## 10. subsystem gate(s), if relevant

None for the planned doc-only closure.

If unexpected production code changes land in the group send seam:
- Group Messaging Gate
  - `./scripts/run_test_gates.sh groups`

## 11. whether Baseline Gate is required

No.

Reason:
- Session 26 is being closed as stale/doc-only work
- Baseline Gate is only required when Flutter production code changes land

## 12. whether Startup / Transport Gate is required

No.

Reason:
- no lifecycle, startup, or recovery behavior is being changed in this closure pass

## 13. done criteria

Session 26 is done when all of the following are true:
- the session is explicitly documented as `stale`
- the landed send-serialization evidence is recorded
- stale docs no longer describe explicit sequential send behavior as open
- no new production implementation is attempted
- Session 26 is marked `accepted`

## 14. dependency impact on later sessions if this session blocks

Session 26 should not block later sessions now that the targeted send-serialization seam is already landed.

If a contradiction were discovered, it would be a documentation/evidence blocker unless the direct serialization proof was actually missing or failing.
