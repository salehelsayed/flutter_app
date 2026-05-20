# INTEGRATE-DE-010 Native Dispatcher Panic Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-010` Native callback panic does not kill the Go dispatcher loop.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-010-plan.md`.
- Source status: accepted/covered with a host Go dispatcher callback-panic proof. The source plan classified DE-010 as tests/docs-only; production panic recovery was already present.

## Integration Scope

Import only the missing row-owned Go proof and documentation. Current main already recovers and logs callback panics inside `EventDispatcher.deliver`, so production code stayed untouched.

In scope:
- `go-mknoon/node/node_test.go`: add `TestDE010EventDispatcherCallbackPanicDoesNotStopLoopAndLogsFailure`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan, and the integration breakdown ledger.

Out of scope:
- Production dispatcher changes, DE-011 dispatcher pressure proof, DE-012 overflow replay recovery, Dart EventChannel recovery, Flutter listener/UI behavior, fake-network tests, relay/device harnesses, receipt protocol, notifications, media, source docs wholesale, COMPLETE_1 docs, simulator/device proof, and 3-party E2E.

## Verification

Focused row check:
- `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run '^TestDE010EventDispatcherCallbackPanicDoesNotStopLoopAndLogsFailure$' -count=1)` passed (`ok github.com/mknoon/go-mknoon/node 0.471s`).

Affected preservation checks:
- `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestEventDispatcher_(CoalescesAddressesUpdatedAndRelayState|PreservesMessageEvents|EmitsPressureAndOverflowDiagnostics)|TestDE010EventDispatcherCallbackPanicDoesNotStopLoopAndLogsFailure' -count=1)` passed (`ok github.com/mknoon/go-mknoon/node 1.581s`).

Static and hygiene checks:
- `gofmt -w go-mknoon/node/node_test.go` completed.
- Scoped `git diff --check` on `go-mknoon/node/node_test.go` passed before doc closure.

Named gates:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+202 -3` only on preserved non-DE-010 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Verdict

Accepted. DE-010 is host Go dispatcher proof only; no iOS 26.2 simulator/live proof was required or run.
