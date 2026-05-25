# Group Relay Ready Recovery Session Breakdown

Status: closed
Recommended plan count: 1
Source bug: successful in-place relay recovery can leave group discovery blocked because `relayReady` remains open after startup relay warm failure.

## Run Mode Snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: no
- Source proposal, matrix, or closure doc path: this self-contained breakdown, created from the 2026-05-24 user bug statement and current Go node code.
- Source row/status vocabulary: doc-local single-session vocabulary: `unresolved`, `accepted`, `accepted_with_explicit_follow_up`, `blocked`, `skipped_due_to_dependency`.
- Overall closure bar: after startup relay warm fails, a later successful in-place `RefreshRelaySession` must close only the current Start generation's `relayReady` channel so joined group discovery loops can continue relay-assisted discovery and rendezvous. Stale refresh work from a stopped or restarted node must not close an old or next-generation channel.
- Final verdict policy: write `closed` only after `GRRR-001` is accepted with focused host Go test evidence and a persisted final program verdict. Write `still_open` if the relayReady close, stale Stop/Start guard, or focused tests remain missing or blocked.
- Dirty worktree at artifact creation: existing unrelated product/test/doc edits are present. Executors must record a fresh `git status --short` before code execution and preserve unrelated changes.

## Program Scope

Fix one Go node recovery gap: `Start` creates `n.relayReady` and closes it only when startup relay warm succeeds, while `JoinGroupTopic` captures that channel and `groupPeerDiscoveryLoop` waits on it before relay-assisted group discovery. `RefreshRelaySession` and `refreshRelaySessionOwned` can later succeed in place without closing the captured channel, leaving relay-assisted group discovery blocked.

Out of scope: Flutter/Dart, bridge APIs, relay-server persistence, external relay configuration, group membership policy, PubSub validation semantics, database migrations, generated native bindings, and broad retry architecture.

## Session Ledger

| Session | Status | Classification | Scope | Plan | Blocker |
| --- | --- | --- | --- | --- | --- |
| GRRR-001 | accepted | implementation-ready | Close the current `relayReady` channel after successful in-place relay recovery and guard against stale Stop/Start channel closure | `Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-GRRR-001-plan.md` | none |

## Ordered Session Breakdown

### GRRR-001 - RelayReady Recovery Close And Generation Guard

- Dependency state: none; runnable now.
- Exact scope: update Go node relay recovery so successful `RefreshRelaySession` closes the current Start generation's `relayReady` channel after in-place recovery succeeds. The close must be guarded by the host/start generation and captured channel/once identity so a refresh completing after `Stop` or `Stop`/`Start` cannot close stale or next-generation readiness.
- Likely code-entry files: `go-mknoon/node/node.go`.
- Likely direct tests: `go-mknoon/node/node_test.go`; existing supporting regression in `go-mknoon/node/pubsub_delivery_test.go`.
- Existing evidence: `go-mknoon/node/node.go` creates `n.relayReady` in `Start` and closes it only in startup relay warm success; `go-mknoon/node/pubsub.go` captures `relayReady` in `JoinGroupTopic`; `groupPeerDiscoveryLoop` waits on that channel before relay-assisted dial/register/discover. `refreshRelaySessionOwned` can report successful in-place recovery without closing `relayReady`.
- Tests to add first: a `RefreshRelaySession` RED test proving a startup-warm-failed `relayReady` closes after successful refresh, a failed-refresh test proving `relayReady` remains open, and a stale Stop/Start generation guard test. Existing `TestGR014GroupDiscoveryResumesAfterRelayReadyClosesLate` proves group discovery resumes once the channel closes.
- Supporting existing regressions: foreground refresh cadence/budget tests and existing relayReady-gated group discovery tests.
- Named gates: host-only Go node focused gates listed in the session plan.
- Closure docs to update: this breakdown ledger and final verdict only.

## Downstream Execution Path

1. Planning: reuse `Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-GRRR-001-plan.md` when it remains execution-safe; otherwise refresh only that plan path with `$implementation-plan-orchestrator` using `model: gpt-5.5` and `reasoning_effort: xhigh`.
2. Execution: run `$implementation-execution-qa-orchestrator` for `GRRR-001` only, using the plan file as the contract. Require `model: gpt-5.5` and `reasoning_effort: xhigh`.
3. Closure: run `$implementation-closure-audit-orchestrator` for `GRRR-001`, then update this ledger with final execution verdict, docs touched, and blocker class if any. Require `model: gpt-5.5` and `reasoning_effort: xhigh`.
4. Final acceptance: after the one session is resolved, run final program closure against this breakdown only. Persist exactly one final program verdict from `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`.

## Host-Only Proof Profile

- Profile: `host-only`
- Live device availability check: not required; this is Go node channel/recovery/discovery behavior covered by host tests.
- Required closure evidence: focused `go test` commands from the session plan.
- Relay fixture: hook-driven relay warm/circuit success plus in-process libp2p test hosts only; no external relay address or mobile simulator is required.
- Supporting evidence only: Flutter, simulator, paired-device, real-network, and multi-relay device-lab gates are not required for this one bug.
- Environment variables: none required.

## Controller Progress

- 2026-05-24: Artifact intake created for one current bug only. Breakdown and doc-scoped plan are the only owned write paths for this controller turn.
- 2026-05-24: GRRR-001 executed and accepted. Added focused RED tests for successful refresh closing `relayReady`, failed refresh not closing it, and stale Stop/Start generation protection. Implemented a captured host/channel/once identity helper in `go-mknoon/node/node.go`. Focused refresh and existing discovery regression gates passed.

## Final Program Verdict

Verdict: `closed`

Evidence:

- `cd go-mknoon && go test ./node -count=1 -run 'TestGRRR001RefreshRelaySessionClosesRelayReadyAfterStartupWarmFailure|TestGRRR001RefreshRelaySessionFailureDoesNotCloseRelayReady|TestGRRR001MarkRelayReadyIgnoresStaleHostAfterRestart'`
- `cd go-mknoon && go test ./node -count=1 -run 'TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure|TestGR002ConcurrentRefreshRelaySessionCallsCoalesce|TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess|TestRefreshRelaySession_DoesNotReplaceHost|TestRefreshRelaySession_UsesForegroundCadenceAndDialTimeout|TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget|TestRefreshRelaySession_PreservesPubSubMaps|TestGR014GroupDiscoveryResumesAfterRelayReadyClosesLate'`
- `git diff --check -- go-mknoon/node/node.go go-mknoon/node/node_test.go Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/group-relay-ready-recovery-session-GRRR-001-plan.md`

Closure rationale: successful in-place relay refresh now closes only the current Start generation's `relayReady` channel. Existing discovery coverage proves closing that channel resumes relay-assisted group discovery.
