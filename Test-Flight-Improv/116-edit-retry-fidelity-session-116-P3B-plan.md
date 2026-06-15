# 116-P3B Receiver Divergence and Ignored-Edit Idempotency Plan

Status: accepted

Source doc: `Test-Flight-Improv/116-edit-retry-fidelity.md`
Breakdown: `Test-Flight-Improv/116-edit-retry-fidelity-session-breakdown.md`
Session: `116-P3B`

## Scope

Close the receiver-side Phase 3B contract:

- emit `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH` for divergent non-edit
  duplicate text without applying the unauthenticated incoming text;
- map `HandleChatMessageResult.ignoredEdit` to an explicit
  `ChatMessageProcessState.ignoredEdit` idempotent success path;
- confirm ignored-edit direct nonces with `ok=true`;
- map staged ignored-edit replays to `rejected/'ignored_edit'`.

## Implementation Notes

- `handle_incoming_chat_message_use_case.dart` now emits duplicate mismatch
  telemetry with only id prefix and text lengths before returning duplicate.
- `chat_message_listener.dart` now treats ignored edits as an explicit process
  state and confirms their direct nonces with `ok=true`.
- `recovered_inbox_chat_disposition.dart` now maps ignored edit replay outcomes
  to rejected with reason code `ignored_edit`.
- The local parent controller took over after the spawned worker stalled with
  partial code/test edits on disk, so a clean parent-captured RED run is not
  available. The behavior was accepted from the focused direct suite and gate
  evidence below.

## Verification

- `dart format` on the six P3B Dart/test files: passed, 0 changed.
- `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart test/features/conversation/application/chat_message_listener_test.dart test/features/conversation/application/recovered_inbox_chat_disposition_test.dart`: passed, 96 tests.
- `./scripts/run_test_gates.sh 1to1`: final aggregate rerun passed with `+793` after the bridge timeout row and send-then-lock 7c stale expectation were closed.
- Focused rerun `flutter test test/core/bridge/p2p_bridge_client_test.dart --plain-name "callP2PInboxStore timeout bridge hang triggers TimeoutException after 15s"`: passed before the final aggregate rerun.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`: passed.
- `./scripts/run_test_gates.sh completeness-check`: passed, 841/841 files classified.
- `git diff --check`: passed.
- `./graphify-arch/refresh_arch_graph.sh`: passed from repo root.

## Execution Verdict

Verdict: accepted

P3B host implementation is complete. The previous broad `1to1` aggregate
timeout row is closed by the final `+793` pass; no P3B code or gate blocker
remains.
