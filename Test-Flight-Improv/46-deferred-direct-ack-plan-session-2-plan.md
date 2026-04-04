# Session 2 Plan - Acceptance, gate validation, and reliability closure update

## Final verdict

`execution-safe`

Session `1` is already accepted in
`Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md`, and
the remaining work is acceptance-only:

- prove the new no-confirm contract from the sender side, not just the
  receiver-side deferred-ACK unit seam
- prove the sender fallback path still converts an unacked direct send into
  inbox-backed delivery instead of false direct `delivered`
- rerun the named gates required by the breakdown
- refresh the stable 1:1 closure reference and final breakdown/program ledger

No new protocol or architecture work is justified in this session unless the
acceptance proof exposes a real gap.

## Final plan

### real scope

- add one sender-side Go acceptance regression proving a direct 1:1
  `chat_message` to a no-confirm receiver returns `acked=false` without a
  transport reply
- add one Dart acceptance regression proving an unacked direct send result
  falls back to inbox handoff and ends as inbox-backed `delivered`, not false
  direct `delivered`
- rerun the direct suites that now cover the receiver no-confirm seam and the
  sender inbox-handoff seam
- rerun:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
- update:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md`

### closure bar

- the reproduced false-delivered seam is closed from both sides:
  - receiver-side no-confirm/no-persist does not emit a transport ACK
  - sender-side unacked direct send falls back to inbox-backed delivery or a
    truthful non-delivered state
- at least one current-session acceptance proof pins the no-confirm contract
  at the sender boundary, not only inside `handleIncomingMessage(...)`
- the stable 1:1 closure doc now states that direct `delivered` depends on a
  receiver-side terminal confirmation or inbox-backed fallback, not raw frame
  read
- the required named gates pass after the acceptance proof lands
- this session does not reopen non-chat direct-message semantics, sender UI
  redesign, or broader transport/resume architecture

### source of truth

- Governing docs:
  - `Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md`
  - `Test-Flight-Improv/46-deferred-direct-ack-plan.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Accepted Session `1` evidence:
  - `go-mknoon/node/node.go`
  - `go-mknoon/bridge/bridge.go`
  - `lib/core/bridge/go_bridge_client.dart`
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/p2p/domain/models/chat_message.dart`
- Current acceptance-proof seams:
  - `go-mknoon/node/send_message_recovery_test.go`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`

### session classification

`acceptance-only`

### exact problem statement

- Session `1` already proves the receiver-side deferred-ACK contract locally,
  but the rollout is not closed until the sender boundary is also pinned:
  no-confirm must stay unacked and re-enter the inbox-backed path rather than
  presenting false direct delivery.
- The stable 1:1 closure doc still describes honest delivery semantics
  generically; it does not yet capture the new direct-ack contract or the
  accepted non-chat difference.

### files and repos to inspect next

- Acceptance proofs:
  - `go-mknoon/node/send_message_recovery_test.go`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
- Stable closure docs:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md`

### existing tests covering this area

- `go-mknoon/node/transport_label_test.go` already proves the receiver-side
  timeout/no-confirm seam inside `handleIncomingMessage(...)`.
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
  already proves inbox fallback on unacked sends in the legacy empty-reply
  shape, but it does not yet pin the explicit `acked=false` contract from the
  new Go sender path.
- `./scripts/run_test_gates.sh 1to1` and `./scripts/run_test_gates.sh baseline`
  already passed once during Session `1`, but Session `2` owns the final
  acceptance rerun after the sender-side proof and closure-doc updates land.

### regression/tests to add first

- Add a Go test in `go-mknoon/node/send_message_recovery_test.go`:
  - receiver has an event dispatcher but never confirms
  - sender transmits a `chat_message` envelope
  - `SendMessage(...)` returns `acked=false`, empty reply, and no stream-open
    error
- Add a Dart test in
  `test/features/conversation/application/send_chat_message_use_case_test.dart`:
  - `sendMessageWithReply` returns `sent=true`, `acked=false`,
    `transport='direct'`
  - `storeInInbox` succeeds
  - final row is `status='delivered'`, `transport='inbox'`
  - the unacked path calls `storeInInbox` exactly once

### step-by-step implementation plan

1. Add the Go sender-side no-confirm acceptance regression.
2. Add the Dart sender fallback regression for explicit `acked=false`.
3. Run the direct suites below.
4. Rerun the named gates below.
5. Refresh the stable 1:1 closure reference with the deferred direct-ack
   contract and the accepted non-chat difference.
6. Update the breakdown ledger for Session `2` and write the final program
   rollout verdict.

### risks and edge cases

- Do not mistake a receiver-side timeout unit test for a full sender-side
  acceptance proof; Session `2` must pin the sender boundary explicitly.
- Do not broaden this session into transport bootstrap/resume work just
  because the broader repo has other reliability areas.
- Keep the closure wording precise: `delivered` still means transport ACK or
  inbox-backed delivery, not read receipt, and non-chat direct messages remain
  on the accepted lighter confirmation model.

### exact tests and gates to run

- Direct tests:
  - `cd go-mknoon && go test ./node ./bridge`
  - `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `flutter test test/features/conversation/application/chat_message_listener_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if execution unexpectedly
    broadens into startup/resume/reconnect/inbox-drain wiring

### known-failure interpretation

- A sender-side result of `acked=false` with no inbox handoff is still a real
  acceptance failure for this rollout.
- Existing unrelated workspace dirt or generated-file churn is not Session `2`
  evidence.
- No device-background run is required in this workspace if the current
  session lands a truthful no-confirm sender proof and the named gates still
  pass; the breakdown allows a receiver-background or no-confirm acceptance
  check, and this plan intentionally chooses the no-confirm proof path.

### done criteria

- The current session leaves one direct sender-side no-confirm proof in Go and
  one direct sender inbox-handoff proof in Dart.
- The stable 1:1 closure reference now reflects the new direct-ack contract.
- Session `2` is recorded honestly in the breakdown ledger with the final
  program verdict.
