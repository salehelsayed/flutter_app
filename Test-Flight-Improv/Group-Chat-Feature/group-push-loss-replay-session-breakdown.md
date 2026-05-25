# group push loss replay session breakdown

## Run-mode snapshot

- Active mode: standard
- Degraded local continuation: not explicitly allowed
- Source proposal/matrix doc: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`
- Source bug: message/event loss paths do not consistently trigger automatic group replay.
- Source status vocabulary: `Planned`, `Accepted`, `Blocked`, `Closed`.
- Overall closure bar: dropped group-message overflow diagnostics identify the dropped group message enough for targeted recovery debugging, and live group push loss paths request the existing group inbox drain without adding a new replay protocol.
- Final verdict policy: `closed` when GPLR-001 is accepted with focused Go and Flutter tests plus scoped hygiene evidence.

## Recommended plan count

1

## Session ledger

| Session | Status | Plan path | Owner files | Required gates |
| --- | --- | --- | --- | --- |
| GPLR-001 | Accepted | `Test-Flight-Improv/Group-Chat-Feature/group-push-loss-replay-session-GPLR-001-plan.md` | `go-mknoon/node/event_dispatcher.go`; `go-mknoon/node/node_test.go`; `lib/core/bridge/bridge.dart`; `lib/core/bridge/go_bridge_client.dart`; `test/core/bridge/go_bridge_client_test.dart`; `lib/features/groups/application/group_message_listener.dart`; `test/features/groups/application/group_message_listener_test.dart` | RED/GREEN Go overflow diagnostic selector; RED/GREEN Flutter callback/listener/event-stream recovery selectors; focused Go node selector; focused Flutter bridge/listener selectors; scoped `dart analyze`; scoped `dart format --set-exit-if-changed`; `gofmt`; `git diff --check`; closure accepted with broad `./scripts/run_test_gates.sh groups` failure recorded as unrelated GM-029/GM-028 membership/config smoke work outside GPLR-001 |

## Closure Progress

- `2026-05-23T20:52:27+02:00` - Role: Completion Auditor. Files inspected: GPLR-001 plan, this breakdown, scoped `git status --short`, and scoped owner-file `git diff --name-status`. Decision/blocker: no GPLR blocker; the GPLR closure bar is met because the plan's Execution Result records red-to-green Go/Flutter selectors, focused Go and Flutter suites, `gofmt`, scoped `dart format --set-exit-if-changed`, scoped `dart analyze`, and scoped `git diff --check` as green. Classification: `closed`; ledger result: `Accepted`.
- `2026-05-23T20:52:27+02:00` - Role: Closure Writer. Files inspected/touched: this breakdown only. Decision/blocker: no blocker; updated the GPLR-001 ledger to `Accepted` and recorded the broad `./scripts/run_test_gates.sh groups` failure as unrelated to GPLR-001 because the visible failures are GM-029 role convergence and GM-028 empty-PeerId delivery assertions in membership/config smoke surfaces owned outside this session. Next action: leave final program acceptance to the parent controller.
- `2026-05-23T20:52:27+02:00` - Role: Closure Reviewer. Files inspected: GPLR-001 plan and this breakdown. Decision/blocker: no blocker; the closure update does not edit product or test code, does not update broad gap-closure matrix docs, preserves the external broad-gate caveat, and leaves `Final program verdict` as `Pending`.

## Ordered session breakdown

### GPLR-001 - Group push loss replay hardening

Classification: implementation-ready

Dependency state: satisfied.

Scope:

- Enrich `group:dispatcher_overflow` diagnostics for dropped `group_message:received` events with available dropped-event fields: `groupId`, `messageId`, `keyEpoch`, `senderId`, `senderDeviceId`, and `transportPeerId`.
- Preserve the existing overflow-to-replay path already wired through `emitGroupDiagnosticEvent`, `GroupMessageListener`, and `drainGroupOfflineInbox`.
- Add one generic Flutter group push-loss diagnostic/recovery event for lost live group delivery paths.
- Trigger the existing injected group inbox recovery callback when:
  - `GoBridgeClient` catches `onGroupMessageReceived` callback errors.
  - `GoBridgeClient` successfully recovers the EventChannel after an error or done event.
  - `GroupMessageListener` catches a live group message processing error.
- Keep replay coalescing so bursts of loss signals request one drain at a time.

Out of scope:

- Do not design a new cursor protocol or replay API.
- Do not run device, simulator, relay, or real-network proof for this host-only session.
- Do not change relay recovery state-machine behavior.
- Do not change group message persistence semantics beyond requesting replay after live-push loss.
- Do not edit the broad gap-closure matrix docs owned by the parallel session.

## Downstream execution path

1. `GPLR-001` needs a reusable TDD plan at the plan path.
2. Execute the plan with a fresh execution agent.
3. Close `GPLR-001` with a fresh closure agent.
4. Run final program acceptance and persist the verdict below.

## Final program verdict

closed

- GPLR-001 is the only session in this breakdown and is `Accepted`.
- The closure bar is met by recorded red-to-green Go and Flutter selectors, focused Go and Flutter suites, scoped `gofmt`, scoped `dart format --set-exit-if-changed`, scoped `dart analyze`, and scoped `git diff --check`.
- The broad `./scripts/run_test_gates.sh groups` failure remains accepted as unrelated GPLR-001 evidence because the visible failures are GM-029 and GM-028 membership/config smoke assertions outside the group push-loss replay scope.
