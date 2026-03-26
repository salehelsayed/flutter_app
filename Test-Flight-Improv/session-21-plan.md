# Session 21 Plan: Surface V2 Decryption Failures More Clearly

## 1. real scope

Make incoming 1:1 V2 decryption failures explicit and locally observable instead of collapsing them into the same `notChatMessage` path used for benign non-chat payloads.

Concrete repo evidence says the issue is still real:

- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` emits `CHAT_MSG_RECEIVE_DECRYPT_FAILED` and `CHAT_MSG_RECEIVE_DECRYPT_ERROR`, but both branches still return `HandleChatMessageResult.notChatMessage`.
- The same file also returns `HandleChatMessageResult.notChatMessage` for actual non-chat outcomes such as bad JSON / wrong type / parse failure, so decrypt failure is currently conflated with a benign ignore case.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` already locks in the wrong behavior with `returns notChatMessage when bridge decrypt reports failure`.
- `lib/features/conversation/application/handle_incoming_reaction_use_case.dart` already has the nearby comparison pattern: `HandleReactionResult.decryptionFailed`.
- `lib/features/conversation/application/chat_message_listener.dart` only has an explicit branch for `HandleChatMessageResult.chatMessage`; everything else is effectively dropped after the use-case call, so the caller cannot intentionally distinguish decrypt failure from an unrelated non-chat message.
- `lib/core/utils/flow_event_emitter.dart` already provides the local observability path for this session: structured `[FLOW]` debug events.

In scope:

- classify incoming V2 chat decrypt failures distinctly from benign non-chat outcomes
- keep those failures locally observable through the chosen flow-event path
- prove the listener does not persist, emit, or notify on decrypt failure
- preserve successful receive behavior

Out of scope:

- user-facing crypto settings
- read receipts or delivery receipt redesign
- envelope format changes
- exporter/dashboard/metrics infrastructure beyond existing local flow events

## 2. session classification

`implementation-ready`

Why:

- the gap is explicit in the current code and tests, not hypothetical
- a nearby comparison implementation already exists in `handle_incoming_reaction_use_case.dart`
- no profiling or external dependency is needed before changing this path
- the required regressions are clear and local

Status call: the issue is still real, not stale.

## 3. files and repos to inspect next

Primary production files:

- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `lib/features/conversation/application/handle_incoming_reaction_use_case.dart`

Primary tests:

- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/core/inbox/inbox_round_trip_test.dart`
- `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`

Test-only helpers to inspect only if execution needs them:

- the fake decrypt bridge inside `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/shared/fakes/test_user.dart`

Repo boundary:

- single repo only; no external tree work is expected

## 4. existing tests covering this area

Useful current coverage:

- `handle_incoming_chat_message_use_case_test.dart` already covers:
  - non-JSON / wrong-type `notChatMessage`
  - unknown sender
  - duplicate
  - V2 no bridge/key -> `notChatMessage`
  - V2 decrypt `ok:false` -> currently `notChatMessage`
  - V2 successful decrypt and persist
- `chat_message_listener_test.dart` already covers start/stop, blocked sender rejection, archived suppression, contact updates, media hydration/download, and notification behavior
- `inbox_round_trip_test.dart` already covers successful encrypted inbox drain for V2 chat messages
- `handle_incoming_reaction_use_case_test.dart` already demonstrates the comparison contract where decrypt failure is explicit via `HandleReactionResult.decryptionFailed`

What is missing:

- no chat use-case regression for bridge decrypt throwing
- no chat regression that proves decrypt failure is classified differently from benign non-chat
- no test that captures the existing decrypt-failure flow events through the real `debugPrint`-backed flow-event path
- no listener regression that proves decrypt failure is intentionally handled while still not emitting a message / notification

## 5. regression/tests to add first, if any

Add regressions first in `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`:

- V2 decrypt returns `ok:false`:
  - expect the explicit decrypt-failure classification
  - expect no persistence
  - expect the existing decrypt-failure flow event, not the generic non-chat one
- V2 decrypt throws:
  - expect the explicit decrypt-failure classification
  - expect no persistence
  - expect the existing decrypt-error flow event, not the generic non-chat one

Then add the smallest listener-layer regression in `test/features/conversation/application/chat_message_listener_test.dart`:

- on a real V2 decrypt failure, `incomingMessageStream` stays empty
- no message is persisted
- no notification is shown
- the decrypt-failure result is handled intentionally rather than treating the case as an unrelated non-chat message

Do not start with inbox or end-to-end tests. The use-case classification seam is the first proving layer.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not applicable. Session 21 is not profile-gated or evidence-gated.

## 7. step-by-step implementation or evidence-collection plan

1. Confirm the exact current chat-result contract in `handle_incoming_chat_message_use_case.dart`.
2. Confirm the comparison contract in `handle_incoming_reaction_use_case.dart`.
3. Add the two required failing regressions first in `handle_incoming_chat_message_use_case_test.dart`:
   - decrypt returns `ok:false`
   - decrypt throws
4. Capture flow-event output in those regressions by overriding `debugPrint` or reusing the pattern from `test/core/utils/flow_event_emitter_test.dart`, because `emitFlowEvent()` uses `debugPrint`, not `print`.
5. Implement the smallest production change:
   - introduce an explicit decrypt-failure result for incoming chat handling
   - return it from the V2 decrypt-failure branches instead of `notChatMessage`
6. Update `ChatMessageListener` with the smallest explicit branch needed so decrypt failure is intentionally handled without persisting, emitting, or notifying. Only add a new listener-level flow event if the implementation truly needs one.
7. Add one listener regression to pin that branch.
8. Re-run the direct chat use-case and listener tests first.
9. Re-run `inbox_round_trip_test.dart` to confirm successful encrypted inbox receive behavior is unchanged.
10. Re-run `handle_incoming_reaction_use_case_test.dart` as the comparison suite to ensure the neighboring decrypt-failure semantics remain aligned.
11. Run the `1:1 Reliability Gate`.
12. Run the `Baseline Gate`.

Preferred observability choice:

- reuse structured `[FLOW]` logging already in the repo
- do not add settings, dashboards, exporters, or user-visible UX for this session

## 8. risks and edge cases

- `HandleChatMessageResult.notChatMessage` is used for truly benign cases today; execution must not break those paths while splitting out decrypt failure.
- V2 “no bridge / no key” is adjacent to decrypt failure. Execution should decide deliberately whether it remains benign or joins the new decrypt-failure bucket for consistency with the reaction path, rather than changing it accidentally.
- Listener behavior must remain quiet in the UI on decrypt failure: no persistence, no stream emission, no notification.
- The chosen observability assertion should stay local and deterministic; do not add brittle long sleeps or global logging assumptions.
- Inbox drain uses the same incoming chat path, so a classification change must not break successful encrypted inbox replay.

## 9. exact tests to run after implementation, if code changes occur

- `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `flutter test test/features/conversation/application/chat_message_listener_test.dart`
- `flutter test test/core/inbox/inbox_round_trip_test.dart`
- `flutter test test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`

## 10. subsystem gate(s), if relevant

- `1:1 Reliability Gate`

Canonical gate from `Test-Flight-Improv/14-regression-test-strategy.md`:

```bash
./scripts/run_test_gates.sh 1to1
```

No Feed / Surface Gate is required in planned scope.

## 11. whether Baseline Gate is required

Yes.

Reason:

- Session 21 is implementation-ready and changes Flutter production code in shared 1:1 receive handling
- the roadmap explicitly marks Baseline Gate as required

## 12. whether Startup / Transport Gate is required

No, in planned scope.

Reason:

- this session is about classification and local observability of decrypt failure
- it does not change startup sequencing, transport selection, or reconnect logic
- `inbox_round_trip_test.dart` is the targeted compatibility proof for the shared receive path

## 13. done criteria

- incoming V2 chat decrypt failures are classified distinctly from benign `notChatMessage` outcomes
- both required regressions exist:
  - decrypt `ok:false`
  - decrypt throw
- the chosen local observability path proves decrypt failure is surfaced as a decrypt problem, not as generic non-chat noise
- `ChatMessageListener` intentionally handles the decrypt-failure result without persisting, emitting, or notifying
- successful V2 decrypt / receive behavior remains unchanged
- the direct test set, `1:1 Reliability Gate`, and `Baseline Gate` are green

## 14. dependency impact on later sessions if this session blocks

- later sessions do not need to stop entirely, but incoming 1:1 failure visibility remains weaker and more ambiguous
- future observability or inbox-hardening work would have to build on an unclear chat decrypt-failure contract
- if Session 21 blocks, later work must not assume chat decrypt failure is already distinguishable from benign non-chat input

## 15. scope guard

- keep the session about failure handling and visibility only
- do not add user-facing crypto settings
- do not redesign envelopes or payload formats
- do not broaden into read receipts, delivery receipts, or notification UX redesign
- do not build exporter/dashboard infrastructure
- do not treat generic non-chat filtering as the same thing as decrypt failure after this session
