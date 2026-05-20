# INTEGRATE-DE-011 Dispatcher Pressure Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-011` Dispatcher pressure never drops message-bearing events below capacity.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-011-plan.md`.
- Source status: accepted/covered with a host Go dispatcher below-capacity pressure proof. The source plan classified production dispatcher behavior as already sufficient after the row-owned proof passed.

## Integration Scope

Import only the missing row-owned Go proof and documentation. Current main already keeps message-bearing events in FIFO `messageQueue`, records pressure below capacity, coalesces status/diagnostic events, and drops only at capacity, so production code stayed untouched.

In scope:
- `go-mknoon/node/node_test.go`: add `TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan, and the integration breakdown ledger.

Out of scope:
- Production dispatcher changes, DE-012 overflow replay recovery, DE-013 schema validation, DE-019 EventChannel recovery, DE-020 starvation, Flutter listener/UI behavior, fake-network tests, relay/device harnesses, receipt protocol, notifications, media, source docs wholesale, COMPLETE_1 docs, simulator/device proof, and 3-party E2E.

## Verification

Focused row check:
- `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run '^TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure$' -count=1)` passed (`ok github.com/mknoon/go-mknoon/node 0.623s`).

Affected preservation checks:
- `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestEventDispatcher_(CoalescesAddressesUpdatedAndRelayState|PreservesMessageEvents|EmitsPressureAndOverflowDiagnostics)|TestDE010EventDispatcherCallbackPanicDoesNotStopLoopAndLogsFailure|TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure' -count=1)` passed (`ok github.com/mknoon/go-mknoon/node 1.598s`).
- `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -count=1)` passed (`ok github.com/mknoon/go-mknoon/node 381.407s`).

Static and hygiene checks:
- `gofmt -w go-mknoon/node/node_test.go` completed.
- Scoped `git diff --check` on `go-mknoon/node/node_test.go`, `test-inventory.md`, and the integration breakdown passed after doc closure.

Named gates:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+202 -3` only on preserved non-DE-011 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Verdict

Accepted. DE-011 is host Go dispatcher proof only; no iOS 26.2 simulator/live proof was required or run.
