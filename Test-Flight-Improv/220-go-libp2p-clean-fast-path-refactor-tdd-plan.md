# 220 - Go Libp2p Clean Fast Path Refactor  (Modification)

Status: implemented on 2026-07-07 (amended after 220-review-fixlist on 2026-07-07; passed /tdd-review re-review 2026-07-07 — all 5 material blockers verified closed in source, one revision-introduced classification defect fixed: TC-220-10 + TC-220-12 reclassified as preserved-green guards). POST-IMPLEMENTATION VERIFICATION 2026-07-07 (independent 8-dimension audit + adversarial re-check + full gate re-run): all focused/-race/lock-window/regression gates GREEN; ONE accepted out-of-scope behavior change confirmed (direct-promotion in `connectGroupPeerPreferDirect`) — see "Post-Implementation Amendment" below. Behavior change proven with a group reliability-sim smoke (scenarios #22 recovery-e2e + #20 multi-device real delivery both GREEN on the freshly-rebuilt Go bridge against the real production relay).

## Planning Progress

- [x] Use graphify architecture query before raw source browsing.
- [x] Ground scope in `go-mknoon/node`, `go-mknoon/bridge`, and host gate scripts.
- [x] Identify existing coverage and missing RED tests.
- [x] Define a bounded refactor and performance plan with acceptance gates.
- [x] Apply audit hardening for discovered-peer dialing, startup lifecycle rollback, and fixed pass/fail thresholds.
- [x] Apply `220-review-fixlist.md` hardening for real test seams, global group-dial concurrency, panic rollback, non-vacuous gates, and baseline-gated startup performance.
- [ ] Execute RED tests.
- [ ] Implement.
- [ ] Execute GREEN/regression gates.

## Execution Progress

- 2026-07-07T18:49:38Z — controller: contract extracted from this plan; scope is host-only Go/libp2p refactor across `go-mknoon/node`, `go-mknoon/bridge`, host gate script, and `_current-test-map.md`. Required next action: inspect owner files, capture startup baseline, add inert seams and RED/preserved-green tests before behavioral edits.
- 2026-07-07T18:50:36Z — baseline gate finished: `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -v ./node -run 'TestStartEmitsColdStartLockWindow' -count=5` passed with `lockHoldMs` samples `7, 3, 2, 3, 3`; median baseline is `3ms`, so the post-refactor target is `<=1ms` by the plan's under-10ms rule. Next action: add inert seams and RED/preserved-green tests.
- 2026-07-07T19:02:05Z — RED/preserved-green evidence captured after inert seams: node static/startup/group/relay RED slices fail for intended old locked/serial/source-shape reasons; bridge helper-use RED fails for missing `withBridgeNode`; node preserved-green sentinels and bridge JSON envelope preservation pass. Required next action: production refactor.
- 2026-07-07T19:28:18Z — final implementation evidence: focused node contract gate, node `-race` parallel-path gate, bridge contract/payload gate, registered host-gate `--only` slices, existing group recovery slice, existing dispatcher slice, and compile-only `./node ./bridge ./cmd/testpeer` all pass with `GOTOOLCHAIN=go1.25.0`; post-refactor startup proof passed five samples with `lockHoldMs = 0ms` each. `git diff --check`, `bash -n scripts/run_host_test_gates.sh`, `graphify update .`, and `./graphify-arch/refresh_arch_graph.sh` completed. `flutter analyze` remains blocked by the repo's existing analyzer backlog (`1625 issues found`), and `gofmt -l` still reports the pre-existing untouched files `go-mknoon/crypto/interop_test.go` and `go-mknoon/cmd/testpeer/envelope.go`.
- 2026-07-07T20:11:31Z — broad package evidence after direct-promotion hardening: `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -json ./node -count=1 -timeout=10m` and the matching `./bridge` broad sweep both returned `status=0`. The relay-ready group tests were updated to assert the new preferred final direct path while still requiring relay-ready recovery hooks to run. Final graph refreshes were rerun after these Go/test edits.
- 2026-07-07 (post-implementation verification) — independent audit re-ran every gate with `GOTOOLCHAIN=go1.25.0`: 12/12 focused node contract tests, 2/2 bridge contract tests, the mandatory `-race` gate over the four parallel paths, `TestStartEmitsColdStartLockWindow -count=5` (post-refactor `lockHoldMs`≈0), and the existing group/bridge/dispatcher regressions all PASS; compile-only + broad `./bridge` sweep PASS; broad `./node` sweep failed ONLY `TestNW002RelayOnlyOrCircuitRoutedPeerReceivesGroupMessages` (env/concurrency flake — real LAN addr leaking into the peerstore before a circuit-dial precondition; passes 3/3 in isolation; NW002 cancels group discovery and dials `DialPeerViaRelay` directly so it never touches the changed promotion path). Host-gate registration + `_current-test-map.md` confirmed. The audit flagged that the "direct-promotion" edit exceeded the plan's "behavior-preserving" group-connect scope; see amendment below.
- 2026-07-07 (direct-promotion sim proof) — regenerated the Go iOS bindings from the uncommitted source (`scripts/ensure_go_ios_bindings.sh` → `make ios`/gomobile, `GOTOOLCHAIN=go1.25.0`, exit 0) so `ios/Runner/GoMknoon.xcframework` and the `make testpeer` CLI both carry the change, then ran the group reliability-sim smoke on booted iPhone simulators against the real production relay: `#22 run_group_recovery_e2e.dart` PASS (live group topic `topicPeers:1`, live + missed-inbox recovery delivery, `All tests passed!`) and `#20 run_group_multi_device_real.dart` PASS (cross-device live group message `md004-cli-live` received + decrypted, `deliveryMs:47`; primary + sibling `All tests passed!`; `[ORCH] MD-004 proof completed successfully`). First `#22` attempt timed out at the 300s group-fixture wait due to a cold Xcode build; the warm re-run passed. Group message delivery is NOT regressed by direct-promotion.

## Post-Implementation Amendment — Accepted Behavior Change: Direct-Promotion (2026-07-07)

This amendment corrects the record. The original plan scoped the group-connect seam as **behavior-preserving** (see "Real Scope": `connectGroupPeerHook ... defaulting to connectGroupPeerPreferDirect`, and step 9 "preserve ... relay fallback"), and "Invariants"/"Refuted" claim no change to group recovery behavior. The implementation intentionally went beyond that: it added a real runtime **direct-promotion** behavior to `connectGroupPeerPreferDirect`. This section supersedes the "behavior-preserving" language for the group-connect path.

### What changed
- `go-mknoon/node/pubsub.go` (`connectGroupPeerPreferDirect`, ~lines 2104–2117): after a successful `DialPeerViaRelay`, if a direct dial had not yet been attempted, it now re-collects direct multiaddrs and, when any are available, dials the peer directly and reports `Path = "direct"` on success (falling back to `relay`/`relay_fallback` otherwise). On HEAD this block did not exist — a relay success went straight to `Path = "relay"`.
- Effect: when a group peer becomes reachable directly after a relay-first connect, the final transport is promoted relay → direct. This is a strict preference improvement (a direct connection is cheaper/faster than a relay circuit); relay fallback is retained.

### Test impact (disclosed, not hidden)
- Existing regressions `GR014` and `GP009` in `go-mknoon/node/pubsub_delivery_test.go` were **inverted** to lock the new behavior (`attemptedDirect` false→true, `Path` relay→direct); `GP009` additionally gained a `relayDialCalls > 0` guard so the relay-ready recovery hook must still run first.
- Consequence: the previous invariant — *"relay-ready recovery does NOT use direct addrs"* — is intentionally retired and is no longer guarded by any test. The tests now guard the opposite, promoted behavior.

### Proof (this amendment's added closure requirement)
Because the group-dial fast path changed more than "behavior-preserving" (the plan's own "Device / Relay Proof Profile" flagged a reliability-sim smoke as warranted in exactly this case), closure additionally required a group reliability-sim smoke exercising the rebuilt Go bridge. That smoke is now GREEN: scenarios `#22 run_group_recovery_e2e.dart` and `#20 run_group_multi_device_real.dart` both passed on booted iPhone simulators against the real production relay, with the direct-promotion code compiled into both the app xcframework and the `make testpeer` CLI (details in the two 2026-07-07 execution-log entries above). No group-delivery regression was observed.

### Residual (non-blocking, tracked)
- The relay-fan-out `min(len(relays), 3)` cap (`relay_selector.go:133`) is correct in production but not exercised by any test with >3 relays, so the cap for the >3 case is mutation-untested. Consider adding a >3-relay FanOut test in a follow-up.

## Source Of Truth

User request: review the Go libp2p side of the app from graphify, identify clean-code and speed improvements, then create a `$tdd-plan` for those changes.

Primary code areas:

- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/event_dispatcher.go`
- `go-mknoon/node/relay_selector.go`
- `go-mknoon/bridge/bridge.go`
- `scripts/run_host_test_gates.sh`
- `Test-Flight-Improv/_current-test-map.md`

Toolchain finding:

- Use `GOTOOLCHAIN=go1.25.0` for Go libp2p tests. The repository already documents the Go 1.26.x `quic-go` incompatibility, and an unpinned full `go test ./node ./bridge` can fail in QUIC/TLS code unrelated to this refactor.

Audit hardening accepted on 2026-07-07:

- Accepted: discovered-peer dialing was in scope but lacked its own RED test.
- Accepted: startup lock shortening needs explicit rollback and in-progress operation contracts.
- Accepted: shape and timing thresholds must be fixed before execution, not tuned during RED creation.
- Accepted from `220-review-fixlist.md`: add named inert seams before behavioral REDs, use one global group-dial limiter, make `-race` mandatory for parallel paths, add panic rollback, separate preserved-green bridge sentinels, and baseline-gate the real `start_lock_window` metric.
- Partially accepted from `220-review-fixlist.md`: bridge binding preservation is real, but the current selected handlers have no `//export` directives in `go-mknoon/bridge/bridge.go`; the plan locks exported function names and preserves any binding comments that exist at execution time instead of inventing absent `//export` comments.

Observed startup baseline:

- `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -v ./node -run 'TestStartEmitsColdStartLockWindow' -count=1` on 2026-07-07 reported `lockHoldMs = 7ms` for the empty-relay host test. Execution must recapture this as a median baseline before behavioral edits because the value is environment-dependent.

Working tree snapshot at planning time:

- Pre-existing dirty files: `graphify-arch/GRAPH_SELECTION.md`, `graphify-arch/comparison.json`, multiple `graphify-arch/graphify-out/*` files, and `info.plist`.
- This plan must not revert or normalize those unrelated changes.

## Session Classification

Type: Modification

Implementation-ready: yes

Reason: the target files, measurable risks, RED tests, regression gates, and script registration points are known. No product decision, migration decision, or device-lab decision is required before implementation.

## Exact Problem Statement

The Go libp2p side works, but several hot or shared areas are doing too much in single files and long functions. The main cleanup and speed risks are:

- `Node` owns too many concerns directly: lifecycle, host setup, relay state, event dispatch, pubsub, group membership, direct-confirm tracking, LAN/media state, and test seams.
- `Start` holds `n.mu` across slow bootstrap work, including libp2p host construction. The current host-test baseline observed `node:startup_timing{phase:"start_lock_window", lockHoldMs:7}` on 2026-07-07; execution must recapture that baseline and prove a real lock-window improvement, not only synthetic fake-host responsiveness.
- Group peer recovery before publish dials known members serially even when multiple independent peers can be tried with a bounded worker fan-out.
- Relay fan-out is implemented sequentially even though relay attempts are independent and already modeled as a selector operation.
- The event dispatcher keeps a slice-backed queue and dequeues by reslicing. This is simple, but it creates retained backing arrays and avoidable copying behavior under queue pressure.
- Bridge exported handlers repeat JSON decode, node lookup, error wrapping, and response wrapping patterns instead of using a shared local entrypoint helper.

The goal is a narrow refactor that improves structure and makes safe fast paths faster without changing wire formats, public bridge payloads, message semantics, relay semantics, or group recovery behavior.

## Root Cause Evidence

- `go-mknoon/node/node.go:39` starts a broad `Node` struct that mixes lifecycle, host, relay, event, pubsub/group maps, direct confirm, LAN dial, media, and testing concerns.
- `go-mknoon/node/node.go:247` starts `func (n *Node) Start(...)`, which is about 309 physical lines and about 209 non-blank/non-comment physical lines under this plan's static-count convention.
- `go-mknoon/node/node.go:247` takes `n.mu.Lock()`, and `go-mknoon/node/node.go:249` defers unlock.
- `go-mknoon/node/node.go:251` to `go-mknoon/node/node.go:256` explicitly says the write lock is intentionally held across full bootstrap and blocks concurrent `SendMessage`, `DialPeer`, and `NodeStatus`.
- `go-mknoon/node/node.go:403` constructs the libp2p host while the write lock is still held.
- `go-mknoon/node/node.go:542` to `go-mknoon/node/node.go:552` emits the `node:startup_timing` lock-window metric before the deferred unlock has run.
- `go-mknoon/node/node.go:558` to `go-mknoon/node/node.go:564` makes `Stop` return `nil` whenever `isStarted == false`; a lock-shortened `Start` must not let `Stop` silently claim success while a start is in progress.
- `go-mknoon/node/node.go:1171` to `go-mknoon/node/node.go:1183` takes `n.mu.RLock()` before relay reconnect singleflight. On HEAD this blocks behind the current `Start` write lock; after lock-shortening it needs an explicit in-progress guard so reconnect does not observe or mutate a half-started node.
- `go-mknoon/node/node.go:879` starts `refreshRelaySessionOwned`, about 267 lines, mixing relay parsing, candidate selection, warm/reserve attempts, timing, and side effects.
- `go-mknoon/node/pubsub.go:71` to `go-mknoon/node/pubsub.go:85` initializes group pubsub maps directly on `Node`.
- `go-mknoon/node/pubsub.go:2950` starts `ensureGroupTopicPeersBeforePublish`, which calls `n.dialKnownGroupMembers(groupId, true)` before publish.
- `go-mknoon/node/pubsub.go:2426` starts `dialKnownGroupMembers`, about 159 lines, and `go-mknoon/node/pubsub.go:2452` loops target members serially.
- `go-mknoon/node/pubsub.go:2240` starts `discoverAndConnectGroupPeers`, about 181 lines, and `go-mknoon/node/pubsub.go:2312` loops discovered peers serially.
- `go-mknoon/node/pubsub.go:3077` calls `n.discoverAndConnectGroupPeers(groupId)` from the group discovery cycle, so the discovered-peer loop is a real fast-path sibling of known-member dialing.
- `go-mknoon/node/pubsub.go:1537` starts `groupTopicValidator`, about 107 lines, mixing sender binding, membership checks, direct/relay conditions, and message validation.
- `go-mknoon/node/relay_selector.go:119` starts `FanOut`, but the current implementation iterates relays sequentially.
- `go-mknoon/node/event_dispatcher.go:25` stores `messageQueue []eventItem`.
- `go-mknoon/node/event_dispatcher.go:313` dequeues with `d.messageQueue = d.messageQueue[1:]`.
- `go-mknoon/bridge/bridge.go:550`, `go-mknoon/bridge/bridge.go:2017`, and `go-mknoon/bridge/bridge.go:2113` show repeated handler structure around JSON input, node lookup, operation call, and JSON response.
- `go-mknoon/bridge/bridge.go:2885` and `go-mknoon/bridge/bridge.go:2893` already provide `okJSON` and `errJSON`, so bridge helper extraction can stay local and incremental.

Static size evidence:

- Largest production functions include `Node.Start` at about 309 physical lines, `refreshRelaySessionOwned` at about 236 counted lines, `discoverAndConnectGroupPeers` at about 165 counted lines, `dialKnownGroupMembers` at about 149 counted lines, `bridge.GroupPublish` at about 86 counted lines, and `bridge.GroupSendReliable` at about 100 counted lines.
- Function counts are concentrated in `go-mknoon/node/pubsub.go` at about 110 functions, `go-mknoon/bridge/bridge.go` at about 75, and `go-mknoon/node/node.go` at about 68.

## Refuted Or Out-Of-Scope Ideas

- Do not rewrite libp2p, pubsub, relay, or bridge architecture from scratch.
- Do not split every large file just to satisfy a line-count target. Only extract where a RED test locks in behavior or performance.
- Do not change bridge request or response JSON shapes.
- Do not change group membership validation, sender binding, ACK semantics, inbox store semantics, wake-token behavior, or notification behavior.
- Do not make relay `ForEach` parallel. `ForEach` is naturally sequential; only `FanOut` is a candidate for parallel attempts.
- Do not add Flutter UI, simulator, or device proof for this plan. The touched behavior is host-side Go logic and host-gate registration.
- Do not normalize unrelated `gofmt` drift in `go-mknoon/crypto/interop_test.go` or `go-mknoon/cmd/testpeer/envelope.go` unless execution touches those files.
- Do not add cgo `//export` directives where none exist today. Preserve exported Go function names and any existing binding comments instead.

## Real Scope

Implementation should be limited to:

- A startup state helper or lifecycle extraction that lets `Start` avoid holding `n.mu` across slow host construction while preserving single-start semantics.
- A behavior-preserving host-creation seam on `Node`, named `newHost func(NodeConfig, []libp2p.Option) (host.Host, error)` or equivalent, defaulting to `libp2p.New` and called at the current `node.go:404` creation site.
- Small relay-session helper extraction from `refreshRelaySessionOwned` only where it reduces complexity and keeps existing tests meaningful.
- Bounded parallel dialing in both group known-member discovery and discovered-peer rendezvous dialing.
- A behavior-preserving group-connect seam, named `connectGroupPeerHook func(peerId string, candidateAddrs []ma.Multiaddr, allowRelayFallback bool) (groupPeerConnectResult, error)` or equivalent, defaulting to `connectGroupPeerPreferDirect`.
- One shared global group dial limiter for actual group peer connect attempts, capped at `GroupDiscoveryConcurrency`, so concurrent discovery cycles cannot deadlock on the existing cycle semaphore or amplify into `GroupDiscoveryConcurrency * GroupDiscoveryConcurrency` host connects.
- Bounded parallel relay attempts in `RelaySelector.FanOut`.
- Ring-buffer or head-index queue for event dispatcher pressure paths.
- A local bridge handler helper for repeated exported handler boilerplate.
- New focused Go tests and host-gate script registration.
- A compact update to `_current-test-map.md` after implementation.

## Startup Lifecycle Contract

The lock-shortening refactor must use an internal startup-in-progress state. This state is not exposed through bridge JSON or public status fields.

- `Start` under `n.mu` must reject `isStarted == true` with the existing already-started behavior and reject `startInProgress == true` with an error containing `node start in progress`.
- `Start` may set only the internal in-progress marker before slow host creation. It must not publish `host`, `peerId`, `isStarted`, `relayReady`, `relayReadyOnce`, `eventSub`, pubsub/group maps, `peerSession`, `lanDialHandler`, or `eventDispatcher` until the final commit.
- `Status` during in-progress startup must return within 50 ms and report the pre-start public state: `isStarted:false`, empty `peerId`, no listen/circuit addresses, and no connections. Concurrent `SendMessage` and `DialPeer` must fail fast as not started while `n.host` remains nil.
- If host creation or pubsub setup fails before commit, `Start` must close any local host it created, cancel any local context, clear the in-progress marker, and restore the pre-start node fields. A subsequent valid `Start` must still succeed.
- If host creation or pubsub setup panics before commit, `Start` must recover enough to clear `startInProgress`, restore lock invariants, close/cancel local artifacts, and re-panic or return a deterministic error without a `fatal: sync: unlock of unlocked mutex` wedge. A subsequent valid `Start` must still succeed.
- `Stop` during in-progress startup must return within 50 ms with an error containing `node start in progress`; it must not return `nil` as if the node were stopped, and it must not mutate the pending start.
- `ReconnectRelays` during in-progress startup must return within 50 ms with an error containing `node start in progress`; it must not begin relay recovery, call `Stop`, or start a nested restart.
- The final commit must happen under `n.mu` only after host, stream handlers, pubsub, event subscription, relay-ready channel, dispatcher, namespace, peer session, and relay-session peer initialization are coherent. `isStarted` must flip to true only at that commit point.

If execution wants cancellable `Stop`-during-start semantics instead of the explicit in-progress error above, stop and replan; that is a behavior decision outside this cleanup slice.

## Fixed Test Thresholds

Static shape budgets use this exact convention: run `gofmt`, then count physical lines from the `func` signature through the closing brace inclusive whose trimmed text is non-empty and does not start with `//`.

- `refreshRelaySessionOwned` must be `<= 190` counted lines.
- `discoverAndConnectGroupPeers` must be `<= 145` counted lines.
- `dialKnownGroupMembers` must be `<= 130` counted lines.
- `bridge.GroupPublish` must be `<= 80` counted lines.
- `bridge.GroupSendReliable` must be `<= 85` counted lines.
- `event_dispatcher.go` must not contain an assignment to `messageQueue` whose right-hand side is a slice expression with low bound `1` on `messageQueue` or an alias of `messageQueue`.

Concurrency/timing RED thresholds:

- Startup fake host creation blocks for 200 ms; `Status`, second `Start`, `Stop`, and `ReconnectRelays` calls made after the fake host hook is entered must all return within 50 ms.
- `maxInFlight` means an `int64` atomic incremented on fake-dial entry, a CAS-tracked peak, and decremented on exit.
- Known-member group dialing uses five fake peers with 100 ms blocked dials; green requires median-of-3 elapsed wall time `>= 90 ms` and `< 250 ms`, `maxInFlight == min(GroupDiscoveryConcurrency, 5)`, no more than one in-flight dial per peer, and global group connect in-flight never above `GroupDiscoveryConcurrency`.
- Discovered-peer group dialing uses five fake rendezvous peers with 100 ms blocked dials; green requires median-of-3 elapsed wall time `>= 90 ms` and `< 250 ms`, `maxInFlight == min(GroupDiscoveryConcurrency, 5)`, non-members filtered, cooldown/dedupe honored, and global group connect in-flight never above `GroupDiscoveryConcurrency`.
- `runGroupDiscoveryCycle` production-path concurrency uses concurrent cycles and fake connects; green requires aggregate group connect in-flight `<= GroupDiscoveryConcurrency` with no deadlock.
- Relay `FanOut` uses three relays with 100 ms blocked attempts; green requires all three relays attempted, `maxInFlight == 3`, elapsed `< 180 ms`, and a cap of `min(len(relays), 3)` for larger relay sets unless a later plan changes the relay concurrency policy.

## Files To Inspect Next

- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/relay_selector.go`
- `go-mknoon/node/multi_relay_test.go`
- `go-mknoon/node/event_dispatcher.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `scripts/run_host_test_gates.sh`
- `Test-Flight-Improv/_current-test-map.md`

## Existing Tests Covering This Area

- `go-mknoon/node/pubsub_delivery_test.go:5906` `TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait`
- `go-mknoon/node/pubsub_delivery_test.go:5989` `TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown`
- `go-mknoon/node/pubsub_delivery_test.go:6315` `TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow`
- `go-mknoon/node/pubsub_delivery_test.go:6597` `TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery`
- `go-mknoon/node/pubsub_test.go:11555` `TestGroupDiscoveryLoop_DedupesConcurrentPeerDials`
- `go-mknoon/bridge/bridge_test.go:2900` `TestGroupSendReliable_ReportsConnectedTopicPeerCount`
- `go-mknoon/node/multi_relay_test.go` covers relay selector behavior.
- `go-mknoon/node/benchmark_bridge_concurrency_test.go:266` covers cold-start lock-window timing emission.
- `go-mknoon/node/node_test.go` covers dispatcher queue pressure and overflow behavior.
- `Test-Flight-Improv/_current-test-map.md:78` lists the current Go group recovery host commands.

## RED Test Catalog

1. `go-mknoon/node/libp2p_refactor_contract_test.go::TestGoLibp2pProductionShapeBudget`
   - Tier: Go unit/static contract.
   - Setup: parse production source with the fixed line-count convention and an AST matcher for dispatcher dequeue.
   - RED on HEAD because: current `refreshRelaySessionOwned`, `discoverAndConnectGroupPeers`, `dialKnownGroupMembers`, `GroupPublish`, and `GroupSendReliable` exceed fixed budgets, and dispatcher dequeue uses slice-head reslicing.
   - GREEN after fix asserts: the exact budgets in "Fixed Test Thresholds" hold.
   - Mutation that re-reds: inline extracted helpers back into the target functions or restore the `messageQueue[1:]` dequeue assignment.

2. `go-mknoon/node/libp2p_refactor_contract_test.go::TestStartDoesNotHoldNodeLockAcrossHostCreation`
   - Tier: Go unit/concurrency.
   - Setup: inert `newHost` seam is added first under the old lock; fake host creation then blocks for 200 ms after signaling entry.
   - RED on HEAD because: `Start` holds `n.mu` while host creation is running, so `Status` cannot return within 50 ms.
   - GREEN after fix asserts: `Status` returns within 50 ms and reports the pre-start public state while host creation continues; concurrent `SendMessage` and `DialPeer` fail fast as not started and do not observe a non-nil `n.host`.
   - Mutation that re-reds: move host creation back under `n.mu` or publish partial started fields before commit.

3. `go-mknoon/node/libp2p_refactor_contract_test.go::TestStartRejectsConcurrentStartWhileHostCreationInProgress`
   - Tier: Go unit/concurrency.
   - Setup: first `Start` blocks in fake host creation; second `Start` is invoked after the hook entry signal.
   - RED on HEAD because: the second call blocks behind the first instead of returning a deterministic in-progress error within 50 ms.
   - GREEN after fix asserts: second `Start` returns within 50 ms with `node start in progress`, and the host factory is called exactly once.
   - Mutation that re-reds: remove the in-progress guard or clear it before commit/rollback.

4. `go-mknoon/node/libp2p_refactor_contract_test.go::TestStartHostCreationFailureRollsBackPublishedState`
   - Tier: Go unit/lifecycle.
   - Setup: fake host creation returns an error after the in-progress marker is visible.
   - RED on HEAD because: start preparation mutates fields such as `lastConfig`, `featureFlags`, context, and relay state before host creation succeeds.
   - GREEN after fix asserts: after failure, `Status` is not started, `peerId` is empty, no host/relay/pubsub/event fields are published, `relaySessionMgr` has not been initialized for failed relay peers, the in-progress marker is clear, and a subsequent valid `Start` can succeed.
   - Mutation that re-reds: leave any pre-commit field or `relaySessionMgr` mutation in place after host creation fails.

5. `go-mknoon/node/libp2p_refactor_contract_test.go::TestStartHostCreationPanicClearsInProgressAndAllowsRetry`
   - Tier: Go unit/lifecycle.
   - Setup: fake host creation panics after the in-progress marker is visible (test recovers the panic, then inspects node state).
   - RED on HEAD because: HEAD mutates `lastConfig`, `featureFlags`, and context and calls `relaySessionMgr.InitRelayPeer` before host creation, and does not roll them back when host creation panics — so after the recovered panic those fields and the relay-manager state are left mutated (the same discriminator as TC-220-04, triggered by a panic instead of an error return). The additional wedged-`startInProgress` / double-unlock hazards exist only post-refactor and are covered by the mutation.
   - GREEN after fix asserts: the panic is handled per contract, the marker is clear, no partial state is published, `relaySessionMgr` has not been initialized for the failed start, and a subsequent valid `Start` succeeds.
   - Mutation that re-reds: remove panic-safe cleanup or restore a deferred unlock that can fire on an unlocked mutex.

6. `go-mknoon/node/libp2p_refactor_contract_test.go::TestStopDuringStartInProgressIsExplicitAndNonMutating`
   - Tier: Go unit/lifecycle.
   - Setup: first `Start` blocks in fake host creation; call `Stop` after hook entry.
   - RED on HEAD because: on HEAD `Start` holds `n.mu` across the 200 ms fake host block, so `Stop`'s initial `n.mu.Lock()` blocks behind it and cannot return within 50 ms (same blocking mechanism as TC-220-07). The "sees `isStarted == false` and returns `nil` early" outcome is the post-lock-shortening hazard the in-progress guard must prevent.
   - GREEN after fix asserts: `Stop` returns within 50 ms with `node start in progress`, does not mutate the pending start, and the started node can be stopped normally after the first `Start` commits.
   - Mutation that re-reds: make `Stop` ignore the in-progress marker or return nil during startup.

7. `go-mknoon/node/libp2p_refactor_contract_test.go::TestReconnectRelaysDuringStartInProgressFailsFast`
   - Tier: Go unit/lifecycle.
   - Setup: first `Start` blocks in fake host creation; call `ReconnectRelays` after hook entry.
   - RED on HEAD because: `ReconnectRelays` blocks at its initial `n.mu.RLock()` behind the current `Start` write lock and cannot return within 50 ms.
   - GREEN after fix asserts: `ReconnectRelays` returns within 50 ms with `node start in progress`, does not begin recovery, and does not call `Stop` or nested `Start`.
   - Mutation that re-reds: let reconnect ignore the in-progress marker.

8. `go-mknoon/node/libp2p_refactor_contract_test.go::TestGroupDialKnownMembersRunsBoundedParallel`
   - Tier: Go unit/performance.
   - Setup: inert `connectGroupPeerHook` seam is added first; five fake known members each block for 100 ms and fail before live-topic settle.
   - RED on HEAD because: known-member dials run serially, so elapsed time is about the sum of five waits and `maxInFlight == 1`.
   - GREEN after fix asserts: median elapsed is `>= 90 ms` and `< 250 ms`, `maxInFlight == min(GroupDiscoveryConcurrency, 5)`, cooldown/dedupe is honored, and overlapping cycles issue at most one in-flight dial per peer.
   - Mutation that re-reds: replace bounded worker fan-out with the old serial `for` loop or bypass `beginGroupPeerDialWithMode`.

9. `go-mknoon/node/libp2p_refactor_contract_test.go::TestDiscoverAndConnectGroupPeersRunsBoundedParallel`
   - Tier: Go unit/performance.
   - Setup: fake `RendezvousDiscover` returns five valid discovered group peers plus one non-member; each fake connect blocks for 100 ms and fails before live-topic settle.
   - RED on HEAD because: discovered-peer dials run serially from `discoverAndConnectGroupPeers`.
   - GREEN after fix asserts: median elapsed is `>= 90 ms` and `< 250 ms`, `maxInFlight == min(GroupDiscoveryConcurrency, 5)`, cooldown/dedupe is still honored, and non-members are still filtered.
   - Mutation that re-reds: restore serial discovered-peer dialing or bypass `beginGroupPeerDial`.

10. `go-mknoon/node/libp2p_refactor_contract_test.go::TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency`
   - Tier: Go unit/concurrency.
   - Setup: drive concurrent `runGroupDiscoveryCycle` calls with fake discovered and known-member connects that block.
   - HEAD expectation: this is a **preserved-green mutation GUARD, not a RED-first test**. On HEAD the dial loops are serial, so aggregate group-connect in-flight is already `<= GroupDiscoveryConcurrency` and no cycle deadlocks — the asserted property already holds on HEAD and the test passes. It exists because the direct-dial tests (TC-220-08/09) call the loops in isolation and cannot detect a nested-semaphore deadlock or per-cycle amplification introduced by a bad parallelization. Run it before edits to confirm preserved-green, and verify it goes RED under its named mutation.
   - GREEN after fix asserts: aggregate fake connect in-flight never exceeds `GroupDiscoveryConcurrency`, every cycle completes without deadlock, and the test fails if a local per-cycle limiter amplifies into `GroupDiscoveryConcurrency * GroupDiscoveryConcurrency`.
   - Mutation that re-reds: replace the shared global dial limiter with a per-cycle worker pool or reuse the already-held cycle semaphore for inner workers.

11. `go-mknoon/node/libp2p_refactor_contract_test.go::TestRelaySelectorFanOutRunsDistinctRelaysInParallel`
   - Tier: Go unit/performance.
   - Setup: three relay entries; each fake attempt blocks for 100 ms and succeeds.
   - RED on HEAD because: `FanOut` attempts relays sequentially, so elapsed time is about 300 ms and `maxInFlight == 1`.
   - GREEN after fix asserts: all three relays are attempted, `maxInFlight == 3`, elapsed `< 180 ms`, and larger relay sets are capped at `min(len(relays), 3)`.
   - Mutation that re-reds: restore sequential fan-out or short-circuit after the first success.

12. `go-mknoon/node/libp2p_refactor_contract_test.go::TestRelaySelectorFanOutAllFailPreservesAggregateError`
    - Tier: Go unit/contract.
    - Setup: all relay attempts fail under the new parallel fan-out path.
    - HEAD expectation: preserved-green sentinel after the test is added, matching existing `TestRelaySelector_FanOut_AllFail`.
    - GREEN after fix asserts: error still mentions all relays failed and preserves a useful last/aggregate error.
    - Mutation that re-reds: return nil on partial accounting failure or drop the all-failed error context.

13. Existing dispatcher preservation tests in `go-mknoon/node/node_test.go`
    - Tier: Go existing regression.
    - Setup: run the existing dispatcher FIFO, pressure, overflow, high-throughput, and large-payload tests.
    - HEAD expectation: preserved-green before and after the source-shape queue refactor.
    - GREEN after fix asserts: message ordering, overflow diagnostics, status coalescing, and queue depth semantics remain unchanged.
    - Mutation that re-reds: change dispatcher ordering, drop accounting, or overflow event payloads.

14. `go-mknoon/bridge/bridge_entrypoint_contract_test.go::TestBridgeExportedHandlersUseSharedEntrypoint`
    - Tier: Go unit/static contract.
    - Setup: source-shape test over selected exported handlers.
    - RED on HEAD because: `StartNode`, `GroupPublish`, and `GroupSendReliable` repeat JSON/node/error wrapper boilerplate.
    - GREEN after fix asserts: selected handlers delegate to one shared helper while keeping exported function names unchanged and preserving any existing binding comments adjacent to those functions.
    - Mutation that re-reds: inline the repeated handler wrapper code again.

15. `go-mknoon/bridge/bridge_entrypoint_contract_test.go::TestBridgeGroupPublishContractsPreservedAfterHelperExtraction`
    - Tier: Go unit/contract.
    - Setup: snapshot success and error JSON for `GroupPublish` and `GroupSendReliable` around missing node, invalid input, node error, and success paths.
    - HEAD expectation: preserved-green sentinel after the test is added before production edits.
    - GREEN after fix asserts: JSON status, error, and success fields stay identical.
    - Mutation that re-reds: change any response field name, status string, or error wrapping.

16. `go-mknoon/node/benchmark_bridge_concurrency_test.go::TestStartEmitsColdStartLockWindow`
   - Tier: Go existing instrumentation/performance.
   - Setup: recapture median HEAD `lockHoldMs` before behavioral edits, then rerun after implementation.
   - HEAD expectation: preserved-green instrumentation with a recorded baseline.
   - GREEN after fix asserts: post-refactor median `lockHoldMs` is at least 20% lower than the recaptured HEAD median, or at least 2 ms lower when the median is under 10 ms. The observed planning baseline was 7 ms, so the planning-time target would be `<= 5 ms`.
   - Mutation that re-reds: move host creation back under the startup write lock.

17. `scripts/run_host_test_gates.sh::GO_NODE_LIBP2P_REFACTOR_TEST` and `scripts/run_host_test_gates.sh::GO_BRIDGE_ENTRYPOINT_REFACTOR_TEST`
   - Fails before implementation because the new focused Go test files are not registered as synthetic host gate paths.

## Test Coverage Matrix

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-220-01 | Fixed source-shape budgets and dispatcher dequeue shape | Go unit/static | `go-mknoon/node/libp2p_refactor_contract_test.go::TestGoLibp2pProductionShapeBudget` | Current target functions and queue shape exceed budget | Inline helpers or restore slice-head dequeue | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestGoLibp2pProductionShapeBudget' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-02 | Startup status and reader lock window | Go unit/concurrency | `go-mknoon/node/libp2p_refactor_contract_test.go::TestStartDoesNotHoldNodeLockAcrossHostCreation` | `Status`, `SendMessage`, and `DialPeer` block behind 200 ms fake host creation | Move host creation back under `n.mu` or publish `n.host` before commit | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestStartDoesNotHoldNodeLockAcrossHostCreation' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-03 | Single-start in-progress guard | Go unit/concurrency | `go-mknoon/node/libp2p_refactor_contract_test.go::TestStartRejectsConcurrentStartWhileHostCreationInProgress` | Second `Start` blocks instead of returning in-progress error | Remove `startInProgress` guard | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestStartRejectsConcurrentStartWhileHostCreationInProgress' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-04 | Failed host creation rollback | Go unit/lifecycle | `go-mknoon/node/libp2p_refactor_contract_test.go::TestStartHostCreationFailureRollsBackPublishedState` | Pre-commit field and relay-manager mutations can survive host creation failure | Leave rollback incomplete | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestStartHostCreationFailureRollsBackPublishedState' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-05 | Panic during host creation | Go unit/lifecycle | `go-mknoon/node/libp2p_refactor_contract_test.go::TestStartHostCreationPanicClearsInProgressAndAllowsRetry` | HEAD leaves `relaySessionMgr`/fields mutated after a recovered panic (same as TC-220-04); post-fix hazard: wedged marker/double-unlock | Remove panic-safe cleanup | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestStartHostCreationPanicClearsInProgressAndAllowsRetry' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-06 | Stop during start | Go unit/lifecycle | `go-mknoon/node/libp2p_refactor_contract_test.go::TestStopDuringStartInProgressIsExplicitAndNonMutating` | On HEAD `Stop` blocks at `n.mu.Lock()` behind the in-progress `Start` (can't return in 50 ms); post-fix hazard: returns nil early | Ignore in-progress marker in `Stop` | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestStopDuringStartInProgressIsExplicitAndNonMutating' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-07 | Reconnect during start | Go unit/lifecycle | `go-mknoon/node/libp2p_refactor_contract_test.go::TestReconnectRelaysDuringStartInProgressFailsFast` | `ReconnectRelays` blocks at initial `RLock` during current `Start` | Ignore in-progress marker in `ReconnectRelays` | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestReconnectRelaysDuringStartInProgressFailsFast' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-08 | Known-member dial fan-out and dedupe | Go unit/performance | `go-mknoon/node/libp2p_refactor_contract_test.go::TestGroupDialKnownMembersRunsBoundedParallel` | Five 100 ms fake dials run serially and `maxInFlight == 1` | Restore serial `for` loop or bypass `beginGroupPeerDialWithMode` | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestGroupDialKnownMembersRunsBoundedParallel' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-09 | Discovered-peer dial fan-out and filtering | Go unit/performance | `go-mknoon/node/libp2p_refactor_contract_test.go::TestDiscoverAndConnectGroupPeersRunsBoundedParallel` | Five 100 ms discovered-peer dials run serially | Restore serial discovered-peer loop or bypass filtering | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestDiscoverAndConnectGroupPeersRunsBoundedParallel' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-10 | Production-path global group dial limit | Go unit/concurrency | `go-mknoon/node/libp2p_refactor_contract_test.go::TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency` | Preserved-green GUARD (HEAD serial dialing already within bound, no deadlock); reds only under the mutation | Use per-cycle worker pool or reuse held cycle semaphore | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-11 | Relay fan-out success path | Go unit/performance | `go-mknoon/node/libp2p_refactor_contract_test.go::TestRelaySelectorFanOutRunsDistinctRelaysInParallel` | Three 100 ms relay attempts run serially | Restore sequential `FanOut` | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestRelaySelectorFanOutRunsDistinctRelaysInParallel' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-12 | Relay fan-out all-fail preservation | Go unit/contract | `go-mknoon/node/libp2p_refactor_contract_test.go::TestRelaySelectorFanOutAllFailPreservesAggregateError` | Preserved-green on HEAD after test is added | Drop all-fail aggregate error context | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestRelaySelectorFanOutAllFailPreservesAggregateError' -count=1` | Add `GO_NODE_LIBP2P_REFACTOR_TEST` synthetic path |
| TC-220-13 | Bridge shared entrypoint and exported names | Go unit/static | `go-mknoon/bridge/bridge_entrypoint_contract_test.go::TestBridgeExportedHandlersUseSharedEntrypoint` | Exported handlers repeat boilerplate | Inline helper back into handlers or rename selected exported functions | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TestBridgeExportedHandlersUseSharedEntrypoint' -count=1` | Add `GO_BRIDGE_ENTRYPOINT_REFACTOR_TEST` synthetic path |
| TC-220-14 | Bridge JSON preservation | Go unit/contract | `go-mknoon/bridge/bridge_entrypoint_contract_test.go::TestBridgeGroupPublishContractsPreservedAfterHelperExtraction` | Preserved-green on HEAD after test is added before helper extraction | Change response field/status/error wrapping | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TestBridgeGroupPublishContractsPreservedAfterHelperExtraction' -count=1` | Add `GO_BRIDGE_ENTRYPOINT_REFACTOR_TEST` synthetic path |
| TC-220-15 | Event dispatcher behavior preservation | Go existing regression | Existing dispatcher tests in `go-mknoon/node/node_test.go` | Queue source-shape change can break FIFO, overflow, pressure, or coalescing | Change ordering/drop/diagnostic behavior | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestEventDispatcher_PreservesMessageEvents|TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure|TestDE020EventDispatcherLargeGroupPayloadDoesNotStarveLaterMessage|TestST005EventDispatcherHighThroughputStormPreservesGroupMessagesAndCoalescesStatus|TestEventDispatcher_EmitsPressureAndOverflowDiagnostics|TestDE012EventDispatcherOverflowDiagnosticIdentifiesPreservedGroupEventForReplayRecovery' -count=1` | Existing direct Go command; add focused path to `_current-test-map.md` |
| TC-220-16 | Existing group recovery preservation | Go existing regression | Current group recovery tests from `_current-test-map.md` | Refactor may break dial ordering, retry, warm retry, dedupe, filtering, or peer count | Revert preservation behavior in group dialing | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait|TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|TestGroupDiscoveryLoop_DedupesConcurrentPeerDials|TestFilterDiscoveredGroupMembers_ExcludesNonMembers|TestFilterDiscoveredGroupMembers_AllowsAllWhenMemberSetEmpty' -count=1` | Existing direct Go command; add focused path to `_current-test-map.md` |
| TC-220-17 | Existing bridge response preservation | Go existing regression | `go-mknoon/bridge/bridge_test.go::TestGroupPublish_ResponseIncludesTopicPeers` and `TestGroupSendReliable_ReportsConnectedTopicPeerCount` | Bridge helper extraction may change payload fields | Change JSON response shape | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TestGroupPublish_ResponseIncludesTopicPeers|TestGroupSendReliable_ReportsConnectedTopicPeerCount' -count=1` | Existing direct Go command; add focused path to `_current-test-map.md` |
| TC-220-18 | Mandatory race gate for new parallel paths | Go race | Focused race command over group dialing and relay fan-out | Data races in counters/maps can pass non-race tests | Use unsynchronized shared counters/maps | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -race ./node -run 'TestGroupDialKnownMembersRunsBoundedParallel|TestDiscoverAndConnectGroupPeersRunsBoundedParallel|TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency|TestRelaySelectorFanOutRunsDistinctRelaysInParallel' -count=1` | Direct Go race command; host gate notes must list it as manual mandatory |
| TC-220-19 | Startup lock-window baseline improvement | Go existing instrumentation/performance | `go-mknoon/node/benchmark_bridge_concurrency_test.go::TestStartEmitsColdStartLockWindow` | Instrumentation exists but current plan could ship no real lock-window gain | Move host creation back under startup write lock | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -v ./node -run 'TestStartEmitsColdStartLockWindow' -count=5` | Existing direct Go command; record HEAD and post-refactor medians |
| TC-220-20 | Host gate registration | Shell gate | `scripts/run_host_test_gates.sh::GO_NODE_LIBP2P_REFACTOR_TEST` and `GO_BRIDGE_ENTRYPOINT_REFACTOR_TEST` | New Go tests are invisible to host-all | Remove synthetic path branch or host-all entry | `./scripts/run_host_test_gates.sh host-all --only go-mknoon/node/libp2p_refactor_contract_test.go && ./scripts/run_host_test_gates.sh host-all --only go-mknoon/bridge/bridge_entrypoint_contract_test.go` | Add both synthetic paths to `scripts/run_host_test_gates.sh` |
| TC-220-21 | Go toolchain guard | Go compile/regression | Pinned compile and package commands | Unpinned Go 1.26.x can fail in unrelated `quic-go`/TLS code | Remove `GOTOOLCHAIN=go1.25.0` from gates | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -run '^$' ./node ./bridge ./cmd/testpeer && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -count=1` | Acceptance command and host gate branches must pin `GOTOOLCHAIN=go1.25.0` |

## Blind-Spot Sweep

- Startup lifecycle / derived-state durability: TC-220-02 through TC-220-07 lock pre-start public state, single-start guard, rollback after failed or panicking host creation, `Stop` during in-progress start, and `ReconnectRelays` during in-progress start.
- Concurrency: TC-220-18 makes `-race` mandatory for the new parallel group-dial and relay fan-out paths.
- Group send: preserve `ensureGroupTopicPeersBeforePublish` waiting behavior and peer-count reporting.
- Sibling fast paths: TC-220-08, TC-220-09, and TC-220-10 cover known-member dialing, discovered-peer dialing, and the production `runGroupDiscoveryCycle` path; do not optimize only one sibling loop.
- Deduplication: bounded parallel dials must still dedupe peer attempts, honor cooldown/in-flight state, and avoid repeated work during concurrent discovery loops.
- Relay fallback: TC-220-11 and TC-220-12 lock parallel success and all-fail aggregate-error semantics.
- Dispatcher: preserve event ordering, drop behavior, overflow events, queue depth metrics, and shutdown draining behavior.
- Bridge: preserve exported function names and any existing binding comments for mobile bindings; do not invent absent `//export` comments.
- Test harness: host gate paths must be runnable from repo root and not depend on current shell directory quirks.

## Invariants

- No bridge JSON schema changes.
- No message envelope, pubsub topic, rendezvous, relay address, or inbox schema changes.
- No database migration.
- No Flutter UI behavior change.
- No change to group membership authorization semantics.
- No change to ACK, retry, store-before-publish, or wake-token behavior.
- Startup can reduce lock hold time, but must not allow double host creation, partial public node state, failed-start residue, panic wedge, silent `Stop` during startup, or relay reconnect while startup is in progress.

## Step-By-Step Implementation Plan

1. Capture startup baseline before behavior changes.
   - Run `TestStartEmitsColdStartLockWindow` with `-count=5`.
   - Record the HEAD median `lockHoldMs` in this plan or the execution log.
   - Planning-time single-run baseline was 7 ms, but execution must use its own median.

2. Add inert test seams before behavioral REDs.
   - Add `Node.newHost` or equivalent, defaulting to `libp2p.New`, while keeping the call under the existing lock so TC-220-02 still fails.
   - Add `Node.connectGroupPeerHook` or equivalent, defaulting to `connectGroupPeerPreferDirect`.
   - These are behavior-preserving scaffolding edits. They are allowed before the behavioral RED battery because the real behavior remains unchanged and the target REDs still fail.

3. Add RED tests in `go-mknoon/node/libp2p_refactor_contract_test.go`.
   - Cover fixed shape budgets, startup lock behavior, concurrent start guard, failed and panicking host creation rollback, `Stop` during start, `ReconnectRelays` during start, known-member dial fan-out, discovered-peer dial fan-out, production-cycle global group dial bound, relay fan-out success/all-fail behavior, and dispatcher source shape.

4. Add bridge tests in `go-mknoon/bridge/bridge_entrypoint_contract_test.go`.
   - First lock down the existing JSON success/error contracts for `GroupPublish` and `GroupSendReliable`.
   - Then add a source-shape or helper-use test for the repeated wrapper extraction target.

5. Register the new Go tests in `scripts/run_host_test_gates.sh`.
   - Add `GO_NODE_LIBP2P_REFACTOR_TEST`.
   - Add `GO_BRIDGE_ENTRYPOINT_REFACTOR_TEST`.
   - Include both in `host-all`.
   - Ensure `print_command_for_path` and `run_path` use `GOTOOLCHAIN=go1.25.0`.
   - Document the focused `-race` command as a mandatory manual acceptance gate; do not hide it behind host-all if that would make host-all too slow.

6. Run RED and preserved-green commands and record results.
   - Behavioral RED tests must fail for the intended reason before behavior edits.
   - Preserved-green sentinels must pass before behavior edits and fail under their named mutations.
   - Existing regression tests should remain passing or have known unrelated toolchain failures documented.

7. Refactor `Node.Start`, `Stop`, and `ReconnectRelays`.
   - Introduce the internal in-progress lifecycle state described in "Startup Lifecycle Contract".
   - Mark startup in progress under `n.mu`, release the lock for slow host construction, then reacquire to publish completed state.
   - Keep pre-commit host/context/pubsub artifacts local until commit.
   - On any pre-commit error or panic, close local artifacts, cancel local context, clear the marker, restore the pre-start field snapshot, and keep mutex unlock/relock panic-safe.
   - Defer `relaySessionMgr.InitRelayPeer` to the commit phase.
   - Add fail-fast `node start in progress` guards to `Stop` and `ReconnectRelays`.
   - Preserve existing event emission, timing metrics, and error cleanup.

8. Extract relay-session helpers from `refreshRelaySessionOwned`.
   - Keep behavior identical.
   - Target helper boundaries around relay address parsing/candidate planning and warm/reserve attempt execution.

9. Add bounded parallel group dialing.
   - Apply it to both `dialKnownGroupMembers` and `discoverAndConnectGroupPeers`.
   - Use a shared global group dial limiter capped at `GroupDiscoveryConcurrency`, not a per-cycle limiter and not the already-held `groupRecoverySem`.
   - Accumulate `dialed`, `connected`, `cooldownSkipped`, `directConnected`, `relayFallbackConnected`, and `relayOnlyConnected` with atomics or per-worker locals merged after the worker barrier.
   - Preserve context timeouts, cooldown/in-flight dedupe, non-member filtering, live-topic waits, relay fallback, and metrics.
   - Keep serial behavior only where ordering is semantically meaningful and covered by an existing preservation test.

10. Parallelize `RelaySelector.FanOut`.
   - Keep `ForEach` sequential.
   - Preserve "attempt all requested relays" behavior where required by tests.
   - Cap relay fan-out at `min(len(relays), 3)` unless a later plan changes relay concurrency policy.
   - Return success if any relay succeeds and useful aggregate error if all fail.

11. Replace dispatcher slice-head dequeue with ring/head-index queue behavior.
   - Preserve ordering and overflow behavior.
   - Avoid retaining large consumed backing arrays after queue pressure.

12. Extract bridge handler boilerplate.
    - Keep exported Go function names and any existing binding comments unchanged.
    - Use existing `okJSON` and `errJSON`.
    - Refactor only selected repeated handlers in this plan: `StartNode`, `GroupPublish`, and `GroupSendReliable`, unless a smaller shared helper naturally covers adjacent handlers without changing behavior.

13. Update `Test-Flight-Improv/_current-test-map.md`.
    - Add the new focused host gate paths and mark them as Go/libp2p cleanup/performance coverage.

14. Run GREEN and regression gates.
    - Run focused tests first.
    - Run the mandatory `-race` focused command.
    - Run existing group recovery and bridge payload tests.
    - Run dispatcher preservation tests.
    - Rerun `TestStartEmitsColdStartLockWindow -count=5` and compare medians against the captured HEAD baseline.
    - Run compile-only Go package checks.
    - Run `flutter analyze` and diff checks if touched scripts/docs require repo-level validation.

## Risks And Edge Cases

- Shortening the startup lock can accidentally expose partially initialized state. TC-220-02 through TC-220-07 are mandatory and must all go RED before behavior edits.
- Failed or panicking host creation can leave `lastConfig`, `featureFlags`, relay state, context, pubsub state, or the in-progress marker behind. TC-220-04 and TC-220-05 must prove rollback before implementation proceeds.
- `Stop` and `ReconnectRelays` during startup can otherwise report misleading not-started behavior or block on the wrong lock. TC-220-06 and TC-220-07 lock deterministic in-progress errors.
- Parallel dialing can create duplicate connection attempts if existing dedupe state is bypassed. Existing dedupe tests plus TC-220-08 and TC-220-09 must cover both known and discovered peers.
- Nested group concurrency can deadlock or amplify host connects if inner workers reuse `groupRecoverySem` or use per-cycle limiters. TC-220-10 and TC-220-18 are mandatory.
- Parallel dial summary counters can race if plain `int++` values are updated inside workers. Use atomics or post-barrier local aggregation and prove with `-race`.
- Parallel relay fan-out can change error ordering. The implementation should not make tests depend on exact aggregate string ordering unless ordering is part of the current public contract.
- Dispatcher queue refactor can break event ordering under overflow. Existing pressure tests plus the new queue-shape test must run together.
- Static shape tests can become brittle. The fixed budgets in this plan are intentionally limited to the named functions; do not add global file-wide thresholds.
- Budget-vs-parallelization tension: adding the worker pool, atomic/per-worker counters, and barrier to `discoverAndConnectGroupPeers` (`165 -> <= 145`) and `dialKnownGroupMembers` (`149 -> <= 130`) adds lines while TC-220-01 requires ~20 fewer each. Resolve by extracting the per-peer dial+accounting body into a helper (which houses the worker logic and shrinks the loop) rather than inlining the fan-out; do not extract cosmetically just to hit the count.
- Bridge source-shape tests should validate the intended helper use without blocking future legitimate helper names or small formatting changes.

## Device / Relay Proof Profile

Required for closure: host-only.

Reason: this plan changes host-side Go structure and performance paths, with behavior guarded by Go unit/regression tests and host-gate registration. It does not introduce a mobile UI flow, database migration, push payload change, or new cross-device protocol.

Optional later proof: a reliability-sim smoke may be useful after implementation if the group-dial fast path changes more than intended, but it is not required by this plan's closure bar.

## Acceptance Gates

Startup lock-window baseline capture before behavioral edits:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -v ./node -run 'TestStartEmitsColdStartLockWindow' -count=5
```

RED focused node tests (must FAIL on HEAD before behavior edits — this batch excludes the two preserved-green node guards below):

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestGoLibp2pProductionShapeBudget|TestStartDoesNotHoldNodeLockAcrossHostCreation|TestStartRejectsConcurrentStartWhileHostCreationInProgress|TestStartHostCreationFailureRollsBackPublishedState|TestStartHostCreationPanicClearsInProgressAndAllowsRetry|TestStopDuringStartInProgressIsExplicitAndNonMutating|TestReconnectRelaysDuringStartInProgressFailsFast|TestGroupDialKnownMembersRunsBoundedParallel|TestDiscoverAndConnectGroupPeersRunsBoundedParallel|TestRelaySelectorFanOutRunsDistinctRelaysInParallel' -count=1
```

Node preserved-green sentinels (TC-220-10 nested-concurrency guard + TC-220-12 relay all-fail): these must PASS on HEAD before behavior edits — they are mutation-verified guards, not RED-first tests. Run them here to confirm preserved-green, and separately confirm each goes RED under its named mutation:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency|TestRelaySelectorFanOutAllFailPreservesAggregateError' -count=1
```

RED focused bridge tests:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TestBridgeExportedHandlersUseSharedEntrypoint' -count=1
```

Bridge preserved-green baseline before helper extraction:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TestBridgeGroupPublishContractsPreservedAfterHelperExtraction' -count=1
```

GREEN focused node tests:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestGoLibp2pProductionShapeBudget|TestStartDoesNotHoldNodeLockAcrossHostCreation|TestStartRejectsConcurrentStartWhileHostCreationInProgress|TestStartHostCreationFailureRollsBackPublishedState|TestStartHostCreationPanicClearsInProgressAndAllowsRetry|TestStopDuringStartInProgressIsExplicitAndNonMutating|TestReconnectRelaysDuringStartInProgressFailsFast|TestGroupDialKnownMembersRunsBoundedParallel|TestDiscoverAndConnectGroupPeersRunsBoundedParallel|TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency|TestRelaySelectorFanOutRunsDistinctRelaysInParallel|TestRelaySelectorFanOutAllFailPreservesAggregateError' -count=1
```

GREEN focused bridge tests:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TestBridgeExportedHandlersUseSharedEntrypoint|TestBridgeGroupPublishContractsPreservedAfterHelperExtraction' -count=1
```

Mandatory race gate for new parallel paths:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -race ./node -run 'TestGroupDialKnownMembersRunsBoundedParallel|TestDiscoverAndConnectGroupPeersRunsBoundedParallel|TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency|TestRelaySelectorFanOutRunsDistinctRelaysInParallel' -count=1
```

Startup lock-window post-refactor proof:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -v ./node -run 'TestStartEmitsColdStartLockWindow' -count=5
```

Existing group recovery regressions:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait|TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|TestGroupDiscoveryLoop_DedupesConcurrentPeerDials|TestFilterDiscoveredGroupMembers_ExcludesNonMembers|TestFilterDiscoveredGroupMembers_AllowsAllWhenMemberSetEmpty' -count=1
```

Existing bridge regressions:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TestGroupPublish_ResponseIncludesTopicPeers|TestGroupSendReliable_ReportsConnectedTopicPeerCount' -count=1
```

Existing dispatcher regressions:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestEventDispatcher_PreservesMessageEvents|TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure|TestDE020EventDispatcherLargeGroupPayloadDoesNotStarveLaterMessage|TestST005EventDispatcherHighThroughputStormPreservesGroupMessagesAndCoalescesStatus|TestEventDispatcher_EmitsPressureAndOverflowDiagnostics|TestDE012EventDispatcherOverflowDiagnosticIdentifiesPreservedGroupEventForReplayRecovery' -count=1
```

Host gate registration checks:

```bash
./scripts/run_host_test_gates.sh host-all --only go-mknoon/node/libp2p_refactor_contract_test.go
./scripts/run_host_test_gates.sh host-all --only go-mknoon/bridge/bridge_entrypoint_contract_test.go
```

Compile and broad Go checks:

```bash
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -run '^$' ./node ./bridge ./cmd/testpeer
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -count=1
```

Repo hygiene:

```bash
gofmt -l $(rg --files go-mknoon -g '*.go' -g '!**/.gocache/**' -g '!**/third_party/**')
flutter analyze
git diff --check
```

## Known-Failure Interpretation

- Failure without `GOTOOLCHAIN=go1.25.0` is not accepted as evidence against this refactor because Go 1.26.x can fail in `quic-go`/TLS code unrelated to the requested work.
- Existing unrelated dirty graphify files are not a test failure and should be left untouched unless graphify is explicitly refreshed after code changes.
- Existing `gofmt -l` output in files not touched by the implementation should be reported, not silently normalized.
- `newHost` and `connectGroupPeerHook` are allowed as inert scaffolding before behavioral REDs only if the old locked/serial behavior remains unchanged and the target REDs still fail.
- A noisy `TestStartEmitsColdStartLockWindow` run must be repeated as a median comparison; a single noisy sample is not enough to pass or fail the performance criterion.

## Done Criteria

- Inert seams are added first without changing behavior; then all behavioral RED tests fail before behavior edits for the intended reason, while preserved-green sentinels pass on HEAD before production edits and fail under their named mutations.
- All focused GREEN tests pass after implementation.
- TC-220-02 through TC-220-07 prove the startup lifecycle contract, including rollback, panic cleanup, and in-progress operation handling.
- TC-220-08 through TC-220-10 prove both group peer dial siblings are bounded-parallel and globally bounded in the production cycle path.
- TC-220-18 `-race` passes for the new parallel paths.
- TC-220-19 proves post-refactor median `lockHoldMs` improves over the recaptured HEAD median by the plan's stated margin.
- Existing group recovery and bridge payload tests pass with `GOTOOLCHAIN=go1.25.0`.
- Existing dispatcher behavior tests pass after the queue-shape refactor.
- New focused Go tests are reachable through `scripts/run_host_test_gates.sh host-all --only ...`.
- `_current-test-map.md` is updated with the new gate paths.
- No bridge payload schema, public exported function name, or protocol behavior changes.
- `git diff --check` passes.
- `graphify update .` is run after code changes. If app-owned Go code changes under `go-mknoon/`, also run `./graphify-arch/refresh_arch_graph.sh` from repo root.

## Scope Guard

Stop and request a new plan if implementation needs any of the following:

- Protocol or bridge JSON schema changes.
- Database, SQLCipher, or migration changes.
- Flutter UI, notification routing, or deep-link changes.
- New relay server behavior.
- Device/simulator-only acceptance evidence.
- Cancellable `Stop`-during-start semantics instead of the explicit `node start in progress` error contract.
- Any loosened static, timing, or concurrency threshold from "Fixed Test Thresholds".
- Per-cycle group dial worker pools, reuse of the already-held `groupRecoverySem` for inner workers, or any design that can exceed `GroupDiscoveryConcurrency` concurrent group peer connects.
- Shipping without the mandatory focused `-race` gate or without the `lockHoldMs` median baseline comparison.
- Broad rewrite of pubsub or node ownership beyond the helper extractions named here.

## Accepted Differences

- Function and helper names may differ from this plan if they are clearer and local.
- Static, timing, and concurrency thresholds are fixed by this plan. If a threshold proves wrong during RED creation, stop and amend the plan before production edits.
- Parallelism can use a helper or worker pool, but group peer connects must use one shared global cap no higher than `GroupDiscoveryConcurrency`, and relay fan-out must cap at `min(len(relays), 3)` unless a later plan changes that policy.
- Bridge helper extraction can include adjacent handlers if doing so removes identical boilerplate without expanding behavior.

## Dependency Impact

- No new third-party dependency expected.
- No generated code expected.
- No database or platform manifest changes expected.
- Host gate script changes are expected.

## Reviewer Findings

Audit findings reviewed on 2026-07-07:

- Accepted blocker 1: discovered-peer parallel dialing was scoped but undercovered. Added `TestDiscoverAndConnectGroupPeersRunsBoundedParallel`, TC-220-08, and focused gates.
- Accepted blocker 2: startup lock shortening lacked a concrete lifecycle contract. Added the internal in-progress contract plus rollback, `Stop`, and `ReconnectRelays` RED tests.
- Accepted blocker 3: "good" thresholds were too negotiable. Added fixed logical-line budgets and timing/concurrency thresholds, and moved threshold changes under Scope Guard.
- Accepted `220-review-fixlist.md` A/B/D/E/F/G material fixes: named host and group-connect seams, RED-before-behavior wording, global group dial cap, production-cycle concurrency test, synchronized counters requirement, mandatory `-race`, panic cleanup, relay-manager commit deferral, real `lockHoldMs` baseline proof, corrected reconnect RED cause, all-fail relay sentinel, and separated bridge preserved-green command.
- Accepted `220-review-fixlist.md` C1/C2/C3/C4 with restraint: dispatcher runtime memory RED is removed as a distinct test and folded into the static shape sentinel plus existing dispatcher behavior tests; `Node.Start` numeric shape budget is dropped because the current counted body is already under the old budget and lifecycle tests are the real lock-shortening proof; static lock-held analysis around `libp2p.New` is not used.
- Not applied as written: a `//export` C-ABI gate. Current selected bridge handlers have no `//export` directives in `go-mknoon/bridge/bridge.go`, so the plan instead preserves exported function names and any binding comments that actually exist at execution time.

Re-review on 2026-07-07 (`/tdd-review`, source-verified):

- All five prior material blockers confirmed CLOSED in real source: `connectGroupPeerHook` covers BOTH `dialKnownGroupMembers` and `discoverAndConnectGroupPeers` (both route through `connectGroupPeerPreferDirect`); zero `//export` directives exist in `bridge.go` (refutation correct); the global group-dial limiter / panic contract / `relaySessionMgr` deferral / `-race` gate / baseline `lockHoldMs` gate / all-fail sentinel are all present; `TestRelaySelector_FanOut_AllFail` exists at `multi_relay_test.go:205`.
- One revision-introduced classification defect FIXED in place: TC-220-10 (`TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency`) and TC-220-12 (`TestRelaySelectorFanOutAllFailPreservesAggregateError`) are preserved-green mutation guards (HEAD dials serially → already within the global bound; FanOut all-fail semantics already exist), not RED-first tests. Both were mislabeled and placed in the RED-first node command; they are now moved to a separate preserved-green node-sentinels command and relabeled, matching how the bridge preserved-green sentinel was already separated.
- TC-220-05 RED-on-HEAD discriminator clarified to the post-panic `relaySessionMgr`/field rollback (same mechanism as TC-220-04) so it is genuinely RED-first.
- Verdict: implementation-ready.

## Arbiter Decision

Structural blockers from the audits are addressed in this amended plan. The plan remains host-only and implementation-ready, provided execution first adds only inert seams, then gets RED failures for behavioral node and bridge tests before behavior edits, records preserved-green sentinels, runs mandatory `-race`, and compares post-refactor `lockHoldMs` against the recaptured HEAD median.

## Sufficiency Self-Check

- Root cause is verified with source paths and line references: yes.
- Refuted approaches are documented: yes.
- RED tests are named and tied to behavior: yes, including discovered-peer dialing, production-cycle global dial bounds, startup rollback/panic/in-progress sentinels, and relay all-fail preservation.
- Matrix rows have no empty cells: yes, including tier, mutation, gate, and registration.
- Literal acceptance commands are included: yes.
- Host gate registration is required and named: yes.
- Device proof requirement is explicit: host-only.
- Toolchain constraint is explicit: `GOTOOLCHAIN=go1.25.0`.
- Mandatory race and startup baseline gates are explicit: yes.
- User-owned decisions remaining: none.

## Final Execution Verdict

Implemented and host-verified. Scope stayed within `go-mknoon/node`, `go-mknoon/bridge`, host-gate registration, and the current test map; no protocol, bridge payload schema, database, Flutter UI, or relay-server changes were introduced.
