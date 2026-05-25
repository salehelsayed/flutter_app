# Group Relay Ready Recovery GRRR-001 Plan

Status: accepted

## Real Scope

Implement one focused Go node fix: when in-place relay recovery succeeds after a failed startup relay warm, close the current Start generation's `relayReady` channel so already joined group discovery loops can continue relay-assisted discovery and rendezvous.

Files in implementation scope:

- `go-mknoon/node/node.go`
- `go-mknoon/node/node_test.go`

Docs in closure scope:

- `Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-GRRR-001-plan.md`

## Closure Bar

The session is accepted only when focused host tests prove:

- Startup relay warm can fail and leave `relayReady` open.
- A later successful in-place `RefreshRelaySession` closes that same current-generation `relayReady` channel.
- Existing `TestGR014GroupDiscoveryResumesAfterRelayReadyClosesLate` remains green, proving `groupPeerDiscoveryLoop` resumes relay-assisted dial/register/discover once `relayReady` closes.
- A refresh completing after `Stop` or after a `Stop`/`Start` cycle does not close a stale or next-generation `relayReady` channel.
- Existing foreground refresh timing, host reuse, and late relayReady group discovery behavior remain green.

## Source Of Truth

Authoritative order when sources disagree:

1. Current worktree code in `go-mknoon/node/node.go` and `go-mknoon/node/pubsub.go`.
2. Existing tests in `go-mknoon/node/node_test.go` and `go-mknoon/node/pubsub_delivery_test.go`.
3. The adjacent session breakdown and this plan.

Current evidence:

- `Start` assigns `n.relayReady = make(chan struct{})` and `n.relayReadyOnce = &sync.Once{}` in `go-mknoon/node/node.go`.
- Startup relay warm captures `relayReadyCh` and `relayReadyOnce` and closes only on warm success.
- `JoinGroupTopic` captures `n.relayReady`, and `groupPeerDiscoveryLoop` waits on it before relay-assisted discovery and rendezvous.
- `refreshRelaySessionOwned` can return `Success: true` for in-place recovery without closing `relayReady`.
- `Stop` resets relay state and `relayReadyOnce`, so a refresh completion path must not close `n.relayReady` by reading mutable node fields after the generation has changed.

## Session Classification

`implementation-ready`

No source-matrix dependency or device-lab prerequisite is required.

## Exact Problem Statement

If startup relay warm fails, `relayReady` remains open. Groups joined during that state capture the open channel and their discovery loop blocks before relay-assisted dial/register/discover. A later successful `RefreshRelaySession` can restore relay connectivity in place, but it does not close `relayReady`, so the group discovery loop remains blocked even though relay recovery succeeded.

Required behavior: successful in-place refresh closes the current Start generation's `relayReady` exactly once, using the existing `relayReadyOnce` semantics, and only when the node generation that began the refresh is still current.

## Device/Relay Proof Profile

- Profile: `host-only`
- Live device availability check: not required.
- Required closure evidence: local Go host tests under `go-mknoon/node`.
- Relay fixture: hook-driven relay warm/circuit success and in-process libp2p test hosts only.
- `FLUTTER_DEVICE_ID`: not applicable.
- `MKNOON_RELAY_ADDRESSES`: not applicable.
- Real-network relay proof is not required because the contract is deterministic channel readiness after successful recovery, not external relay availability.

## Dirty Worktree Scope Note

The workspace is already dirty with unrelated changes. Do not revert unrelated files. Before execution, record `git status --short`; after execution, verify new or modified files are limited to `go-mknoon/node/node.go`, `go-mknoon/node/node_test.go`, and the two doc paths named above.

## Existing Tests Covering This Area

- `TestRefreshRelaySession_UsesForegroundCadenceAndDialTimeout`
- `TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget`
- `TestRefreshRelaySession_WarmsRelaysInParallel`
- `TestRefreshRelaySession_ForegroundFallbackKeepsLongCircuitWait`
- `TestGP009GroupDiscoveryRegistersAndDiscoversAfterRelayReady`
- `TestGR014GroupDiscoveryResumesAfterRelayReadyClosesLate`

## TDD Plan

### RED

Add focused failing tests before production changes:

1. `TestGRRR001RefreshRelaySessionClosesRelayReadyAfterStartupWarmFailure` in `go-mknoon/node/node_test.go`: start a node with a fake relay address and a startup warm hook that fails, wait for the startup attempt, assert the captured `relayReady` is still open, switch the refresh hooks to succeed, call `RefreshRelaySession`, and assert the same captured channel is closed.
2. `TestGRRR001RefreshRelaySessionFailureDoesNotCloseRelayReady` in `go-mknoon/node/node_test.go`: start with `relayReady` open, return a failed in-place refresh result, and assert the captured channel stays open.
3. `TestGRRR001MarkRelayReadyIgnoresStaleHostAfterRestart` in `go-mknoon/node/node_test.go`: capture the old host/channel/once, run `Stop` followed by `Start`, call the close helper with stale identities, and assert neither stale nor new generation readiness is closed by stale state.

### GREEN

Implement the narrowest production fix:

1. In `refreshRelaySessionOwned`, capture under lock the current host pointer, `relayReady` channel, and `relayReadyOnce` for the Start generation being refreshed.
2. After `finalizeRelayRecoveryResult` returns a successful in-place result, close the captured `relayReady` through the captured `relayReadyOnce`.
3. Before closing, reacquire the node lock and verify the node is still started, `n.host` still matches the captured host, `n.relayReady` still matches the captured channel, and `n.relayReadyOnce` still matches the captured once. If any identity differs, skip the close because a Stop or Stop/Start generation change occurred.
4. Keep startup warm success behavior unchanged and keep the close idempotent through `sync.Once`.
5. Do not close `relayReady` on failed refresh, `NOT_STARTED`, restart fallback failure, or stale generation completion.

### REFACTOR

1. Extract a small private helper only if it keeps the generation guard readable, for example a helper that closes the captured relayReady when the captured generation is still current.
2. Keep the helper local to `node.go`; do not introduce new exported APIs or new node lifecycle state unless current identity checks prove insufficient.
3. Run `gofmt` on touched Go files.
4. Avoid sleep-based readiness logic outside test polling and do not add broad relay lifecycle rewrites.

## Exact Tests And Gates To Run

Focused RED/GREEN gate:

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestGRRR001RefreshRelaySessionClosesRelayReadyAfterStartupWarmFailure|TestGRRR001RefreshRelaySessionFailureDoesNotCloseRelayReady|TestGRRR001MarkRelayReadyIgnoresStaleHostAfterRestart'
```

Existing focused regression gate:

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure|TestGR002ConcurrentRefreshRelaySessionCallsCoalesce|TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess|TestRefreshRelaySession_DoesNotReplaceHost|TestRefreshRelaySession_UsesForegroundCadenceAndDialTimeout|TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget|TestRefreshRelaySession_PreservesPubSubMaps|TestGR014GroupDiscoveryResumesAfterRelayReadyClosesLate'
```

Diff hygiene:

```bash
git diff --check -- go-mknoon/node/node.go go-mknoon/node/node_test.go Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-GRRR-001-plan.md
```

Optional package confidence if focused gates are green and time permits:

```bash
cd go-mknoon && go test ./node -count=1 -run 'RefreshRelaySession|RelayReady|GroupDiscovery'
```

## Scope Guard

Do not edit Flutter/Dart files, bridge APIs, relay-server code, database helpers, UI, generated native bindings, PubSub envelope validation, group membership logic, rendezvous namespace semantics, external relay addresses, or AutoRelay retry constants. Do not replace in-place recovery with restart-only behavior. Do not add background goroutines solely to close `relayReady`; the close belongs to successful in-place recovery completion and must remain generation-guarded.

## Known-Failure Interpretation

The RED run is expected to fail before production changes because the refresh success path does not close `relayReady`. The stale Stop/Start guard must fail if a naive implementation closes `n.relayReady` without captured generation checks.

For final validation:

- Any failure in new GRRR-001 tests is blocking.
- Any failure in existing foreground refresh or relayReady-gated discovery tests is blocking unless direct evidence shows it is a pre-existing unrelated failure.
- Failures outside `go-mknoon/node` are out of scope because no broader gate is required.
- If `go test ./node` has pre-existing unrelated failures, capture the failing test names and prove they reproduce without this session's changes before classifying them as non-blocking.

## Done Criteria

- New GRRR-001 tests fail before production changes or are documented as already covered by current dirty worktree behavior.
- Successful in-place refresh closes the current generation's `relayReady` channel.
- Existing group discovery coverage remains green, proving discovery resumes after `relayReady` closes.
- Stale refresh completion after `Stop` or `Stop`/`Start` does not close stale or next-generation readiness.
- Production changes are limited to `go-mknoon/node/node.go`.
- Test changes are limited to `go-mknoon/node/node_test.go`.
- Focused RED/GREEN and existing regression gates pass, or any failure is classified with exact evidence.
- `git diff --check` passes for touched files.
- Breakdown ledger records `GRRR-001` as `accepted` only after execution and closure evidence exists.

## Recovery Input

None yet. If execution blocks inside the scoped owner files, record the blocker class, failing tests, missing contract, touched files, and blocker signature here before same-session recovery.

## Execution Progress

- RED: `cd go-mknoon && go test ./node -count=1 -run 'TestGRRR001RefreshRelaySessionClosesRelayReadyAfterStartupWarmFailure|TestGRRR001RefreshRelaySessionFailureDoesNotCloseRelayReady|TestGRRR001MarkRelayReadyIgnoresStaleHostAfterRestart'` failed before production changes because `closeRelayReadyIfCurrent` did not exist.
- GREEN: `refreshRelaySessionOwned` now captures the current host, `relayReady`, and `relayReadyOnce`; successful finalized `in_place` recovery calls `closeRelayReadyIfCurrent`.
- GREEN: `closeRelayReadyIfCurrent` validates the node is still started and the host/channel/once identities still match before closing via the captured `sync.Once`.
- REFACTOR: ran `gofmt` on `node/node.go` and `node/node_test.go`.
- Verification passed:
  - `cd go-mknoon && go test ./node -count=1 -run 'TestGRRR001RefreshRelaySessionClosesRelayReadyAfterStartupWarmFailure|TestGRRR001RefreshRelaySessionFailureDoesNotCloseRelayReady|TestGRRR001MarkRelayReadyIgnoresStaleHostAfterRestart'`
  - `cd go-mknoon && go test ./node -count=1 -run 'TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure|TestGR002ConcurrentRefreshRelaySessionCallsCoalesce|TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess|TestRefreshRelaySession_DoesNotReplaceHost|TestRefreshRelaySession_UsesForegroundCadenceAndDialTimeout|TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget|TestRefreshRelaySession_PreservesPubSubMaps|TestGR014GroupDiscoveryResumesAfterRelayReadyClosesLate'`
  - `git diff --check -- go-mknoon/node/node.go go-mknoon/node/node_test.go Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-GRRR-001-plan.md`

## Final Verdict

Accepted. The scoped relayReady recovery bug is fixed with focused TDD coverage and no blocker remains for this session.
