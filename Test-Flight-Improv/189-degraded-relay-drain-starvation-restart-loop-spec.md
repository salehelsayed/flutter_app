# 189 - Degraded-relay inbox-drain starvation + no-exit 30s node-restart loop (1:1 delivery takes minutes)  (Bug — Spec)

Status: awaiting-review (spec only — problem + impact + current state + test cases; no solution design).

Relation to earlier work:
- **141/145** built the notification-open + deferred-startup drains; **182** added the network-change drain; **183** added the keepalive-drop one-shot drain. None of them covers the state this spec targets: *foreground, steady network, chronically degraded relay* — where the ONLY recurring drain is the 30s health check, and that is exactly the path that skips it (Defect A).
- **FDC-03/18** made send custody concurrent and durable — which is why the SENDER side is healthy in this incident (custody ~0.5–3 s measured) and the entire user-visible delay is the RECEIVER never pulling.
- **188** documented the `EnableDcutrUpgrade → ForceReachabilityPublic` coupling; that mechanism produces the same NO_CIRCUIT signature as Defect B and gets a regression guard here (Group E).
- **185/187** (send truthfulness / doomed-dial skip) are siblings on the send path and are NOT touched.

Framing note: this is a **receive-side delivery-latency** bug pair. Two defects cooperate: (A) the drain starves whenever the health check is in its recovery branch, and (B) the node is stuck in a permanent 30 s restart loop that guarantees the health check is *always* in its recovery branch. Fixing either one collapses the user-visible symptom; fixing only A leaves the churn (battery, broken direct-dial/DCUtR, group-recovery thrash); fixing only B leaves A latent for the next degraded episode.

---

## Problem Statement

When a device's relay session is chronically degraded, incoming 1:1 messages sit in the relay durable inbox for **minutes** even though the app is foreground, the network is up, and the device reconnects to the relay every 30 seconds. The receiver retrieves them only when an unrelated trigger fires — most reliably, when the user *sends* a message from that device.

**Live-debug evidence (2026-07-02, Pixel 6 on cellular ↔ iPhone 11 on WiFi, both foreground, build 1.0.0+106):**
- Relay journal store→ack latencies: iPhone→Pixel **0–1 s** (FCM foreground push → drain); Pixel→iPhone **86–368 s** across the morning's sends.
- Controlled repro: message stored for the iPhone at 07:50:56Z (custody confirmed 0.4 s after send-tap on the Pixel); relay logged `Peer …HhaG5Enge7BH has 1 pending messages` on **every 30 s reconnect for >10 minutes** with no `retrieve_pending` and no ack, app foreground the whole time.
- The iPhone's earlier drains correlate 1:1 with its own outbound sends (acks at 06:49:00, 07:37:56, 07:41:51 — each at the exact moment the iPhone user sent), because a send re-establishes the circuit, Go `relayState` flips to `online`, and the *next* health-check tick takes the non-recovery branch that actually drains.
- Both devices flap at the relay on a metronomic 30 s cycle (relay `Peer connected/disconnected` at :10/:40 for the Pixel, :15/:45 for the iPhone; iPhone `symptomsd` shows relay TCP conns living exactly 30.03 s). Pixel FLOW: `watchdogRestartCount=1304` over ~10.9 h ≈ one full node restart per 30 s for the process's entire lifetime.
- Loop signature per cycle (Pixel logcat): `RELAY_RECOVERY_START recoverySource=cold_start_health_check` → Go `RefreshRelaySession: warm … success` → `reserve … success` (~150 ms) → `Timed out waiting for circuit address after 3s/7s` → `ReconnectRelays: in-place recovery failed … performing full restart` → node restart → `Timed out waiting for circuit address after 10s` → `RELAY_OUTAGE_TIMING phase=recovered` (false) → 20 s later the next tick repeats.
- Cross-defect side effect: peers dialing each other's relay circuit get `NO_RESERVATION (204)` (the reservation exists only in brief windows), and `peer:ping` (183 keepalive) fails chronically, so the keepalive drop-drain latch is consumed once and never re-arms.

### Defect A — recovery ticks never drain
`_performHealthCheck` drains the offline inbox at the END of the function (`p2p_service_impl.dart:3888`, comment: *"Drain offline inbox on each health check so we pick up messages stored while we were unreachable"*). But the relay-recovery branch (`:3812`–`:3871`) ends with `return;` at `:3871` — before the drain. A device whose `relayState != 'online'` on every tick (`_stateNeedsRelayRecovery`, `:3544-3552`) takes the recovery branch on every tick and **never reaches the only periodic drain**. `performImmediateHealthCheck` (`:4713` → `:4746`) funnels into the same function and inherits the same skip. The drain written for "messages stored while we were unreachable" is unreachable precisely while the device is unreachable.

### Defect B — the restart loop has no exit path
The manual relay reservation **succeeds** (`relayclient.Reserve`, node.go:995-1049) but `/p2p-circuit` never appears in `host.Addrs()`, because in go-libp2p v0.39.1 (go.mod:17) only autorelay's `relayFinder` publishes circuit addresses, and nothing bridges manual-reservation success into the advertised address set. The app's verdict poll `waitForCircuitAddress` (node.go:1798-1835) greps `h.Addrs()` for `/p2p-circuit` with 3 s (foreground, config.go:46) / 10 s (config.go:41) budgets — while relayFinder's own `tryNode` allows a 20 s IdentifyWait and every full restart (`ReconnectRelays` Stop+Start, node.go:1146-1245) resets relayFinder from scratch. Result: a self-sustaining loop — the watchdog kills the node before autorelay can finish, forever. Additionally the loop's bookkeeping is self-blinding: `ReconnectRelays` returns `err=nil` with `Success:false` (node.go:1229-1245), Dart emits `RELAY_OUTAGE_TIMING phase=recovered` and resets its failure counter, so no escalation/backoff ever engages, and every cycle is mis-attributed as `cold_start_health_check` because `_hasEverBeenOnline` never latches.

---

## Impact Analysis

| Scenario | Delivery latency | Frequency |
|---|---|---|
| Receiver healthy, push arrives (Android foreground FCM) | 0–1 s | baseline |
| Receiver chronically degraded, idle (this bug) | **minutes → unbounded** (10+ min observed, until any drain trigger) | every message to an affected device |
| Receiver degraded, user sends something | ≤ ~30 s (next tick takes normal branch) | the accidental "workaround" |
| Receiver degraded, keepalive latch fresh | one drain ~16–24 s after latch | once per latch; latch never re-arms while pings fail |

- **Severity: high.** Core product promise (message delivery) degrades to minutes with zero user feedback; both test devices were in the affected state simultaneously, on current build 106, on ordinary networks (cellular CGNAT + home WiFi).
- Collateral of Defect B beyond latency: full node restart every 30 s ⇒ battery/radio burn on both ends of the relay link, all libp2p conns/streams killed every cycle (node.go:598-608), group pubsub torn down + `needsGroupRecovery` latched every cycle (node.go:571-591, relay_session.go:390-392), listeners re-bound to new random ports (node.go:338-345) invalidating LAN adverts, direct-dial/DCUtR structurally broken (`NO_RESERVATION 204`), push-token re-registration gated on a healthy transition that never fires (p2p_service_impl.dart:3858-3862).
- Workarounds: send any message from the affected device; background+resume the app; toggle connectivity (182 drain). All accidental, none discoverable.

---

## Current State (verified file:line, 2026-07-02 working tree)

### Dart health check / drain
| Item | Location |
|---|---|
| `healthCheckInterval = 30s` | `lib/core/services/p2p_service_impl.dart:355` |
| `Timer.periodic` health check | `:2733` (started `:2725`) |
| `_performHealthCheck` entry | `:3711` |
| `_stateNeedsRelayRecovery` (true iff `relayState != 'online'`) | `:3544-3552` |
| Recovery branch: `await _attemptRelayRecovery` … **`return;`** | `:3812` … `:3871` |
| The only periodic drain call (normal branch only) | `:3888` |
| `_attemptRelayRecovery` (no drain inside; verified `:3211-3340`) | `:3211` |
| `performImmediateHealthCheck` → same function | `:4713` → `:4746`; callers: resume `handle_app_resumed.dart:194`, relay-degraded push `:4447`, addresses push `:4272` |
| `_drainOfflineInbox` + single-in-flight coalescing | `:2024`, `:2029-2052`; durable pipeline `:2117`, bridge `inbox:retrieve_pending` `:2125` |

### Every other drain trigger (none periodic, none fires foreground+idle+steady-network)
| Trigger | Location |
|---|---|
| App resume (unawaited) | `handle_app_resumed.dart:218-227`; per-screen `conversation_wired.dart` resume re-drain |
| FCM foreground push | `main.dart:4672` → `handle_foreground_remote_message_use_case.dart` (works on Android; iOS push path is a SEPARATE defect, out of scope here) |
| Network change (182), 5 s flap floor | `p2p_service_impl.dart:2663`, drain `:2691` |
| Keepalive drop latch (183), one-shot until ping succeeds | `active_peer_keepalive_use_case.dart:165-181` (drop event `:174`; reset `:112-119`; 8 s interval `:90`, 2-miss `:50`) |
| Node-started one-shot (141) | `p2p_service_impl.dart:3373-3383` |
| UI one-shots (feed activation, banner retry tap, invite accept) | various |
| Send path | **does NOT drain** (verified: `sendMessage`/`sendMessageWithReply` contain no drain; the observed drain-on-send is the indirect relayState flip) |

### Go node restart loop
| Item | Location |
|---|---|
| `waitForCircuitAddress` polls `h.Addrs()` for `/p2p-circuit`, 200 ms cadence | `go-mknoon/node/node.go:1798-1835` (match `:1814-1815`) |
| Budgets: foreground 3 s / full 10 s / warm+reserve dial 3 s / autorelay retry cadence 1 s | `go-mknoon/node/config.go:46, :41, :44, :43` |
| In-place recovery (warm `:953-974`, explicit reserve `:995-1049`, wait `:1054-1073`) | `node.go` |
| `ReconnectRelays`: in-place → full `Stop()` `:1191` + `Start` `:1193-1209`, 10 s wait `:1217`, returns `err=nil` + `Success:circuitOk` `:1229-1245` | `node.go:1146-1245` |
| Deterministic circuit addr already constructed for dialing | `node.go:1357` (`/p2p/<relayID>/p2p-circuit/p2p/<peer>`) |
| AutoRelay config: `WithBootDelay(0)`, backoff/minInterval 1 s | `node.go:393-399` |
| Reachability coupling: `enableDcutrUpgrade` ON ⇒ `ForceReachabilityPublic()` ⇒ autorelay never publishes circuits | `node.go:373-376`; Dart default OFF `lib/core/bridge/p2p_bridge_client.dart:76-79`; Dart map wholesale-overrides Go defaults (`p2p_bridge_client.dart:125`) |
| go-libp2p pin v0.39.1 (relayFinder is sole circuit-addr publisher; purges reservation instantly on relay disconnect) | `go-mknoon/go.mod:17` |
| Stop() collateral: host close, pubsub teardown, port-0 re-listen, `needsGroupRecovery` | `node.go:558-647`, `:338-345`, `relay_session.go:390-392` |
| Unused escalation scaffolding: `refreshFailureThreshold = 3` never compared | `p2p_service_impl.dart:352` |

### Observability anchors available to tests
Dart: `RELAY_RECOVERY_START` (`:3204`), `RELAY_OUTAGE_TIMING` (`:3286/:3781/:4426`), `P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN` (`:4785`), `P2P_HEALTH_CHECK_RECOVERY_RESULT` (`:3849`), `KEEPALIVE_PEER_DROP`. Go: `circuit_address:timing` (node.go:1816/:1827), `relay:reservation_timing` (`:1029/:1042`), `relay:warm_timing`, `relay:state` (`:1991`), `addresses:updated` (`:1923`).

### Existing test coverage and the gap
Drain paths are tested only via manual triggers (`test/core/inbox/inbox_round_trip_test.dart`, `test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart`, `app_lifecycle_recovery_test.dart`, `main_keepalive_wiring_test.dart`, group drain suites). Go has relay/watchdog integration tests (`go-mknoon/integration/relay_test.go`, `watchdog_failover_test.go`, `local_relay_harness_test.go`). **No test anywhere asserts the drain runs on a recovery tick, no test models a chronically-degraded relay and detects drain starvation, and no test bounds consecutive watchdog restarts or catches a false `phase=recovered`.**

---

## Scope Clarification

| Area | Status |
|---|---|
| Health-check tick behavior: drain on recovery ticks (Defect A) | **In scope** |
| Restart-loop exit: circuit-addr verdict and/or watchdog escalation + truthful recovery bookkeeping (Defect B) | **In scope** |
| Regression guard: default-flag reachability stays Private; DCUtR-flag coupling cannot silently re-create NO_CIRCUIT | **In scope** (guard only; no flag-flip work) |
| iOS push→drain dead path (stale FCM token slot, foreground onMessage not firing) | **Out of scope** — separate diagnosis + spec (needs unredacted iOS logs) |
| Android netlink SELinux denial / anet fix / 0-announced-addresses | **Out of scope** — separate spec; FDC-11 port-mining already covers the LAN-advert path |
| Relay-server changes (push payloads, token store, inbox protocol) | **Out of scope / unchanged** |
| 183 keepalive design (interval, latch semantics) | **Unchanged** (its one-shot behavior is documented, not redesigned) |
| Send-path behavior (185/187, FDC-01/02 budgets, concurrent custody) | **Unchanged — must not re-baseline** |
| go-libp2p version upgrade | **Out of scope** (a solution may choose it, but this spec does not require it) |

Open diagnostic question the plan must carry (not assume): *why* relayFinder never publishes on these devices under default flags (Private reachability). The loop's no-exit structure is proven; the initiating trigger is not. Group F pins the diagnostic.

---

## Test Cases

### Group A — Defect A: the drain runs on every health-check tick
- **TC-189-01 (RED on current code)** — relay chronically degraded: node status returns `relayState != 'online'` on every tick. Drive ≥3 health-check ticks. Expected: `_drainOfflineInbox` / `inbox:retrieve_pending` is invoked on **each** tick (observable via `P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN` or fake-bridge call count ≥3), even though every tick enters the recovery branch (`RELAY_RECOVERY_START` also ≥3).
- **TC-189-02** — recovery attempt FAILS (relay:reconnect returns unhealthy retry state): the tick still drains. Drain must not be conditional on recovery success — a degraded relay link can still serve `retrieve_pending` (proven live: the flapping iPhone acked over a degraded session the moment anything asked).
- **TC-189-03** — recovery attempt THROWS (bridge exception mid-`_attemptRelayRecovery`): the tick still drains and the health-check timer keeps ticking (no unhandled error kills the periodic loop).
- **TC-189-04** — `performImmediateHealthCheck` (resume / relay-degraded push) on a degraded node also reaches a drain — same funnel, same guarantee.
- **TC-189-05 (regression)** — healthy tick (`relayState == 'online'`): drain still runs exactly as today (`:3888` path), single-in-flight coalescing intact — concurrent tick + manual `drainOfflineInbox()` produce ONE in-flight drain (existing `:2029-2052` behavior preserved, no double `retrieve_pending` storm).
- **TC-189-06 (behavioral outcome)** — end-to-end sim: receiver in a permanently-degraded relay state; sender stores a message into the receiver's relay inbox; receiver acks/retrieves within **one health-check interval + drain timeout** (≤ ~35 s), with NO send/resume/network-change/notification trigger on the receiver. This is the falsifiable restatement of the live 10-minute repro.
- **TC-189-07 (starvation regression lock)** — replay of the incident shape: N=10 consecutive degraded ticks; assert zero ticks skip the drain (count(RELAY_RECOVERY_START) == count(drain begins) over the window).

### Group B — Defect B: the restart loop terminates
- **TC-189-10 (RED)** — Go: relay accepts warm + `Reserve` (manual reservation succeeds) but autorelay never publishes a `/p2p-circuit` addr (as observed). Expected: the recovery verdict treats reservation-success as circuit truth (the node already constructs the circuit addr deterministically — node.go:1357) OR otherwise reaches a **stable non-restarting state**: no `Stop()+Start()` churn on subsequent health cycles. Falsifier: a second full restart within 2 cycles under this fixture.
- **TC-189-11 (RED)** — truthful recovery bookkeeping: when `ReconnectRelays` ends with `Success:false`, Dart must NOT emit `RELAY_OUTAGE_TIMING phase=recovered` nor reset its consecutive-failure accounting. `phase=recovered` ⇔ the retry status is actually healthy/usable.
- **TC-189-12 (RED)** — escalation/backoff: with a relay that never yields a usable session, consecutive full restarts back off (e.g. attempt counter grows and inter-restart spacing increases or restarts cap) instead of one hard restart per 30 s forever. Falsifier: ≥5 full restarts at fixed 30 s cadence. (Exact backoff shape is solution-space; the spec requires only: monotone non-constant, bounded restart rate, and a live counter observable in FLOW.)
- **TC-189-13** — genuine outage then recovery: relay unreachable for M cycles (dial fails), then reachable again → node converges to `relayState='online'`, `_hasEverBeenOnline` latches, recovery-source attribution stops reporting `cold_start_health_check` on later ticks, and exactly one truthful `phase=recovered` fires. Backoff must not delay convergence beyond one backoff step after the relay returns.
- **TC-189-14** — reservation visible to peers: while the node reports a usable relay session, a second node dialing `<relay>/p2p-circuit/p2p/<node>` does NOT get `NO_RESERVATION (204)` (uses the existing local relay harness). This locks the cross-defect symptom that broke direct dial and 183 pings.
- **TC-189-15 (collateral bound)** — over a 5-minute window with a reserve-ok/no-circuit-publish relay fixture, group pubsub is NOT torn down repeatedly and `needsGroupRecovery` does not latch on every cycle (bounded by the backoff of TC-189-12).

### Group C — cross-defect integration (the incident, end to end)
- **TC-189-20** — two-node + local-relay sim reproducing the full incident: receiver wedged in the no-circuit state, sender sends 3 messages over 2 minutes. Expected: every message acked by the receiver ≤35 s after store (Defect-A fix), AND receiver's restart count over the window ≤2 (Defect-B fix). Both assertions in one scenario so neither fix can silently regress the other.
- **TC-189-21** — sender-side invariants untouched: custody still confirmed via concurrent durable inbox in <5 s (`CHAT_MSG_SEND_CUSTODY_CONFIRMED`), no double relay write, 187's skip + 185's retriable-'sent' semantics unchanged (existing suites stay green, no re-baseline).

### Group D — device/measurement runsheet (Pixel 6 + iPhone 11, the original repro)
- **TC-189-30** — repeat the 2026-07-02 protocol (Pixel cellular, iPhone WiFi, both foreground, idle receiver): Pixel→iPhone store→ack p95 ≤35 s (was 86–368 s+); relay journal shows NO metronomic 30 s `Peer connected/disconnected` flap for either peer over 10 minutes; `watchdogRestartCount` stable (Δ ≤2 over 30 min, was ~60/30 min).
- **TC-189-31** — reverse direction stays fast: iPhone→Pixel store→ack unchanged (0–2 s with FCM foreground push).

### Group E — regression guards
- **TC-189-40** — all existing drain triggers (resume, network-change 5 s floor, keepalive one-shot latch, 141 startup one-shot, notification-open) behave exactly as their existing suites assert — no trigger removed or re-ordered.
- **TC-189-41** — default-flag reachability: with the production Dart flag map (`enableDcutrUpgrade=false`), the Go node runs `ForceReachabilityPrivate()` (autorelay eligible to publish circuits). Guard test at the flag→reachability seam (node.go:373-376) so a flag-map change that silently forces Public (the 188 coupling) fails a named test, not field debugging.
- **TC-189-42** — `refreshFailureThreshold` (`:352`) either becomes load-bearing under Defect-B accounting or is removed; a constant that reads like an escalation cap but is never compared may not survive review as-is (dead-scaffolding lock).

### Group F — diagnostic (carried, not blocking)
- **TC-189-50** — instrumentation exists to answer "why does relayFinder not publish": a debug/dev build path enabling `GOLOG_LOG_LEVEL=autorelay=debug` (or equivalent surfaced logging) captures relayFinder's tryNode/Reserve/purge outcomes on-device, and one captured run from the Pixel is attached to the plan's closure evidence. Without this, any Defect-B fix risks treating the symptom while the initiating trigger recurs elsewhere (e.g. after a future go-libp2p upgrade).

---

## Scope guard (non-goals)

- Do NOT redesign the drain pipeline, its paging, or its coalescing — the fix surface is *when it is invoked*, not *how it drains*.
- Do NOT change send-path budgets, FDC-01/02 race shape, or 185/187 semantics; no re-baselining their suites.
- Do NOT flip `enableDcutrUpgrade` or change DCUtR behavior (188 owns that); this spec only locks the reachability default with a guard test.
- Do NOT require a go-libp2p upgrade for GREEN; if the solution chooses one, Group B/C tests still define done.
- Do NOT touch the relay server; every fix here is client-side (Dart + go-mknoon).
- iOS push→drain and Android netlink are separate specs (out of scope here by decision, not omission).
