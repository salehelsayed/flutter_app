# FDC-S5 - Go-bridge concurrency design note  (Spike / Decision)

Status: open — source-read design contract (verdict + Option A prioritization) = settled and usable now; only the M1/M2 **device confirmation** in the Exit Gate below is outstanding.

> **Implementation note (2026-06-26).** The host-runnable deliverables are now IMPLEMENTED and green:
> - **M1 read-concurrency microbench** `TestConcurrentSendDialNoSerialize`
>   (`go-mknoon/node/benchmark_bridge_concurrency_test.go`, run under `-race`, `GOTOOLCHAIN=go1.25.0`) — the
>   primary host-runnable proof (M2 below also has a host wiring test). **Measured:** 8 concurrent dials finish in ~0.6 s vs a ~4.8 s serial floor;
>   a real user send completes in **<1 ms while 8 speculative warm dials each block ~0.6 s** (not
>   head-of-line blocked). Mutation-verified: serializing the dials behind a shared mutex drives elapsed to
>   ~4.8 s and the assertion RED.
> - **M2 cold-start lock-window instrument** — `Start()` now emits
>   `node:startup_timing{phase:"start_lock_window", lockHoldMs}` while still holding the bootstrap write
>   lock (`go-mknoon/node/node.go`), surfaced through the existing raw passthrough (no Dart change). Host
>   test `TestStartEmitsColdStartLockWindow`; host window measured ~15 ms (directional — device authoritative).
> - **M1 `queueWaitMs` instrument** — the iOS/Android bridges emit `bridge:dispatch_timing {method,
>   queueWaitMs}` (the platform-receive→background-dispatch delay) **DEBUG builds only**
>   (`ios/Runner/GoBridge.swift`, `android/.../GoBridge.kt`), folded into FLOW logs by the Dart client's
>   raw-passthrough set (`go_bridge_client.dart`) alongside `BRIDGE_CALL_TIMING{bridgeMs}`. Dart host test
>   in `go_bridge_client_test.dart`.
>
> Outstanding = only the **M1/M2 two-device measurement run** (warm-state `queueWaitMs` delta + cold-start
> block window on a real iOS + Android pair), deferred to the post-FDC-04 two-device smoke per the
> classification above; it gates nothing hard.

Informs (advisory design-gate — shapes how the plans below are written; does **not** block their
delivery or sequencing, matching FDC-00's "gates nothing hard" classification):
- **FDC-04 (LAN-aware eager `warmPeer`)** — its plan adopts this note's prioritization contract before
  finalizing (a design-gate, not a delivery gate). The whole point
  of `warmPeer` is to *speed up* the next send; if the warm dial head-of-line-blocks that send on the
  single bridge, warming makes the reported case *worse*. This spike sets whether warm needs a
  priority lane / separate channel, or whether "keep warm off the cold-start critical path + bound it"
  is sufficient (and cheaper).
- **Informs FDC-02 (staggered ranked race) / FDC-03 (concurrent durable inbox + 2s-serial fix).** Those
  plans assume `race(legLAN, legDirect, legRelay)` + parallel `storeInInbox` actually run *concurrently
  over the wire*. If the bridge serialized them, the "race" would be a disguised serial ladder and the
  budgets in those plans would be wrong. This spike confirms whether Dart `Future.wait` over the bridge
  yields **real Go-level concurrency** (it largely does — see Decision) so those plans can keep their
  parallel shape.

The **source-read design contract** (the verdict + the Option A prioritization) should be in hand
**before the Phase-0 plans are written** (it shapes FDC-04/05), because P0-1/P0-2/P0-3 all add
concurrent bridge traffic and assume it doesn't self-throttle. The **device confirmation** (the M1/M2
Exit Gate below) is **deferred to the post-FDC-04 two-device smoke** (FDC-00 MVP cut) and does **not**
block Phase-0 host delivery — matching the "advisory, gates nothing hard" classification above.

---

## Question

When Dart fires several bridge calls "in parallel" (`Future.wait([warmPeer, fastReprime, send])`, or
the §6.2 multi-leg race + parallel `storeInInbox`), **do they actually run concurrently end-to-end, or
does the single `MethodChannel('com.mknoon/go_bridge')` + the gomobile FFI + a Go-side mutex serialize
them so the user's send waits behind speculative warm/probe work?** And if there is a serialization
point, **what is the cheapest mitigation that keeps the user's send first**: a Dart priority queue, a
second MethodChannel, coarse batched Go calls, or simply "keep warm off the critical path"?

## Why it blocks

The proposal asserts this as a *risk* in two places without measuring it:
- §10: *"The single Go bridge is a serialization point. `warmPeer` + `fastReprime` + the user's send all
  funnel through one bridge channel; Dart `Future.wait` parallelism does **not** yield Go-level
  concurrency, so they can head-of-line block each other. Prioritize the user's send over speculative
  warm/reprime on the bridge."*
- §12 / "Risks prior art confirms": *"Berty (`bertybridge`), status-go, go-waku all funnel through one
  serialized FFI. Their mitigation: heavy work inside Go behind coarse batched calls; keep warm/probe
  dials off the send-critical path."*

If FDC-04 invents a mitigation against an **assumed** blanket serialization that does not actually exist
(e.g. builds a Dart priority queue / second channel), it pays complexity for nothing and may even hurt
(a queue adds latency it was meant to remove). If it assumes concurrency that does **not** exist on the
cold path, `warmPeer` will delay the very first send. Either invented assumption is wrong; this spike
replaces both with a measured layer-by-layer answer.

## Background  (grounded in real source — what exists today)

The "single bridge" is four layers; serialization could live in any of them. Each was read:

**1. Dart — one channel, many in-flight async calls.** `GoBridgeClient` uses a single
`MethodChannel('com.mknoon/go_bridge')` (`lib/core/bridge/go_bridge_client.dart:26`). Every command goes
through one `send()` → `await _methodChannel.invokeMethod<String>(...)`
(`go_bridge_client.dart:790`, `:841`/`:846`). Dart `invokeMethod` is **async and non-blocking**: N
overlapping `send()` calls produce N outstanding platform messages; the Flutter platform-channel layer
does **not** force request/response pairing — replies are correlated per-call. So Dart-level parallelism
is real up to the platform boundary. Each call already self-times: `BRIDGE_CALL_TIMING` emits
`{cmd, bridgeMs, outcome}` around the invoke (`go_bridge_client.dart:837-858`), and `GO_BRIDGE_SEND`
fires on entry (`:831-835`).

**2. iOS native — concurrent global queue (NOT serialized).** `GoBridge.handleMethodCall` routes almost
every method through `runOnBackground`, which is
`DispatchQueue.global(qos: .userInitiated).async { ... }` (`ios/Runner/GoBridge.swift:35-42`).
`.global(...)` is a **concurrent** queue — `dialPeer`, `sendMessage`, `relayProbe`, `nodeStatus` each
dispatch on it (`:101-106`, `:97-98`, `:83-84`) and run on **different threads simultaneously**. There
is no serial `DispatchQueue` and no per-call lock at the Swift layer. (Exceptions intentionally on the
main thread: `bgBegin`/`bgEnd`, `:183-217`.)

**3. Android native — unbounded cached thread pool (NOT serialized).** `runOnBackground` is
`executor.execute { ... }` where `executor = Executors.newCachedThreadPool()`
(`android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt:38`, `:55`). A cached pool spawns a fresh
thread per concurrent task — `dialPeer`/`sendMessage`/`relayProbe` (`:89-92`, `:86`) run in parallel.
Not serialized at the Kotlin layer.

**4. Go gomobile bridge — `nodeMu` held only to read the singleton pointer, released before I/O.** Every
exported function takes `nodeMu.Lock(); n := singletonNode; nodeMu.Unlock()` and then does its work
**after releasing the lock**:
- `SendMessage` — `go-mknoon/bridge/bridge.go:1027-1029`, then `n.SendMessageWithTransport(...)` at `:1048`.
- `DialPeer` — `bridge.go:951-953`, then `n.DialPeerWithTimeout(...)` at `:971`.
- `RelayProbe` — `bridge.go:904-906`, then `n.DialPeerViaRelay(...)` at `:924`.
`nodeMu` is a plain `sync.Mutex` (`bridge.go:33`) but its critical section is a **pointer read of a few
nanoseconds**, not the network call. So at the bridge layer the heavy work runs lock-free.

**5. Go node — `n.mu` is a `RWMutex`; send/dial take a *read* lock, also released before I/O.**
- `SendMessageWithTransport` — `n.mu.RLock(); h := n.host; n.mu.RUnlock()` (`node.go:1417-1419`), then
  `openChatStreamForSend` / `writeFrame` / `readFrame` run **after** unlock (`:1404-1426`).
- `DialPeerWithTimeout` — `n.mu.RLock(); h := n.host; n.mu.RUnlock()` (`node.go:1171-1173`), then
  `h.Connect(ctx, ai)` at `:1174`.
`RWMutex` allows **many concurrent readers**, so concurrent sends/dials/probes do not block each other on
`n.mu`.

**6. The ONE real Go-level head-of-line block: `Node.Start` holds the *write* lock across the whole
bootstrap.** `func (n *Node) Start` does `n.mu.Lock(); defer n.mu.Unlock()` (`node.go:219-220`) and the
deferred unlock means the **write lock is held for the entire node bring-up** — connmgr, relay parse,
host construction, listen addrs (`:218-468`). While `Start` holds the write lock, any concurrent
`SendMessageWithTransport`/`DialPeerWithTimeout`/`NodeStatus` that calls `n.mu.RLock()` **blocks until
Start returns.** This is exactly the **cold notif-tap / cold-open** window the proposal already flags as
the case warming can't help (§6.1 "Honest scope", R5 `:114`).

**7. gomobile / libp2p notes.** gomobile does not globally serialize cgo calls — each exported call runs
on its own goroutine off the calling native thread, so layers 2-3's concurrency reaches Go. Below
app code, go-libp2p's swarm **coalesces concurrent dials to the same peer** (dialSync /
`DefaultDialRanker`) — so `warmPeer`'s speculative dial and the send's dial to the *same* peer
**dedupe into one dial** rather than racing wastefully (a benefit, not a block).

**Net:** the proposal's blanket "the single bridge serializes, `Future.wait` gives no Go concurrency" is
**largely refuted for the warm/steady state** (concurrent at Swift, Kotlin, and Go read-lock layers). The
real serialization is **narrow and cold-path only**: the `Start()` write lock. Plus two *resource*
(not mutex) pressures to measure: native thread-pool / QoS saturation if warm fans out across the
roster, and shared libp2p resource contention.

## Options  (mitigation, given the findings)

### Option A — "Keep warm off the cold-start critical path" only (no bridge plumbing). RECOMMENDED default
- **Description:** Do not add any Dart queue or second channel. Rely on the measured warm-state
  concurrency. Address the one real block by **not firing `warmPeer`/`fastReprime` until the node is
  started** (gate on `node:start` ack / `isStarted`), so warm never contends for the `Start()` write
  lock; and **bound warm** (single-shot, per-peer cooldown, only the open peer — never the roster) so it
  can't saturate the native thread pool. This is precisely the proposal's own §6.1 "Honest scope" and
  the prior-art "keep warm/probe off the send-critical path."
- **Pros:** Zero bridge complexity; no added latency; matches measured reality; additive-only. Lets the
  FDC-02/03 race keep its true-parallel shape.
- **Cons:** Does nothing for the cold-start window itself (that's FDC's cold-start plan / P1-3, not this);
  relies on FDC-04 honoring the "node-started" gate.
- **Cost:** S. iOS/Android: none (no native change). NET-REL-07: none.

### Option B — Native QoS / thread-priority hint for the user's send (additive, small native change)
- **Description:** Keep one channel, but tag the user's `sendMessage`/LAN-send so the native dispatch
  uses a higher priority than speculative warm/probe: iOS `DispatchQueue.global(qos: .userInteractive)`
  for send vs `.utility` for `dialPeer`/`relayProbe` warm calls; Android set thread priority
  (`Process.setThreadPriority`) in the warm path's `runOnBackground`. Cheap insurance against thread-pool
  scheduling delays under heavy fan-out.
- **Pros:** Directly makes "user's send first" true at the scheduler if measurement shows contention;
  small, additive. Doesn't change the protocol or Go.
- **Cons:** Needs a way to distinguish "warm dial" from "send dial" at the native switch (today both map
  to `dialPeer`/`sendMessage` with no priority flag) → either a new method name suffix or a payload
  flag the native side reads. Marginal benefit if Option A already keeps warm bounded.
- **Cost:** S-M. iOS + Android both touched. NET-REL-07: none (client-only).

### Option C — Dart-side priority queue / single-flight in front of the bridge. NOT RECOMMENDED
- **Description:** Serialize-with-priority all bridge calls through a Dart queue that always lets the
  user's send jump speculative warm/probe.
- **Pros:** Total control of ordering in pure Dart; host-testable.
- **Cons:** **Re-introduces serialization the platform doesn't have** — it would *slow down* the FDC-02/03
  race (legs would queue instead of truly racing). Adds latency to the thing it's meant to speed up.
  Solves a problem the measurements show is largely absent. High regression surface against existing
  NET-REL send-ladder test locks.
- **Cost:** M. Client-only. NET-REL-07: none, but high *behavioral* risk.

### Option D — Second MethodChannel for speculative/background work. NOT RECOMMENDED (for this purpose)
- **Description:** Route warm/probe/reprime over a separate `com.mknoon/go_bridge_bg` channel so they
  can't share a queue with sends.
- **Pros:** Physical isolation of speculative traffic.
- **Cons:** **The channels aren't the bottleneck** — both native sides already dispatch concurrently and
  Go is read-lock-concurrent, so a second channel buys ~nothing over Option A while doubling the
  event/lifecycle/reinit surface (`reinitialize`/recovery at `go_bridge_client.dart:217-276`,
  `:498-529`). Pure cost.
- **Cost:** M-L. Both platforms. NET-REL-07: none.

### Option E — Coarse batched Go calls (the prior-art mitigation, scoped to where it pays)
- **Description:** Move heavy multi-step work inside one Go call rather than chatty Dart round-trips
  (already true: decrypt/store/transport-classify all happen inside one `SendMessage`/`InboxRetrieve`).
  Extend only if a *new* hot path (e.g. drain decrypt fan-out) would otherwise N+1 the bridge.
- **Pros:** Fewer FFI crossings; lock-free heavy work; matches Berty/Waku.
- **Cons:** Not a serialization fix per se (bridge is already concurrent); relevant only to crossing
  *count*, which is mostly recipient-side (out of FDC-04 scope).
- **Cost:** Per-case. Go-only. NET-REL-07: none.

## Method  (how to measure — instruments, events, devices, commands)

The findings above are from **source reading**; this method *confirms* them empirically before FDC-04
relies on them. Two measurements.

**M1 — Warm-state concurrency check (does parallel warm inflate the send?).**
- Instruments (already present): `GO_BRIDGE_SEND` (`go_bridge_client.dart:831`) and
  `BRIDGE_CALL_TIMING {cmd, bridgeMs, outcome}` (`:850-858`). Add one field to `send()`: a monotonic
  `enqueuedAtMicros` captured *before* `invokeMethod` and a `dispatchedAtMicros` captured native-side at
  `runOnBackground` entry, surfaced back so `queueWaitMs = dispatched - enqueued` is logged alongside
  `bridgeMs` (the **queue-wait** is the serialization signal; `bridgeMs` alone hides it).
- Procedure: warm device (node already started). Fire `warmPeer(peer)` (= `dialPeer` + `discoverLocalPeer`)
  concurrently with a real user `message:send` to the same and to a *different* peer. Compare the send's
  `queueWaitMs` and `bridgeMs` with vs without concurrent warm, p50/p95 over ≥30 trials each, iOS and
  Android.
- Also run a **Go microbenchmark** (specify, do not execute here): `go test -race` a harness that calls
  `Start` once, then launches K=8 concurrent `SendMessageWithTransport`/`DialPeerWithTimeout` against a
  fake host and asserts they overlap (timestamps interleave), proving the `n.mu.RLock` path is
  read-concurrent. Command shape: `cd go-mknoon && go test ./node -run TestConcurrentSendDialNoSerialize -race`.

**M2 — Cold-start `Start()` write-lock blocking window.**
- Instruments: existing `node:startup_timing` raw passthrough (`go_bridge_client.dart:666`,
  `_rawFlowPassthroughEvents`); add a Go log/event capturing the wall-clock interval during which
  `Start()` holds `n.mu` (timestamp at `:219` lock-acquire vs `:468`-ish return), and have a concurrent
  `NodeStatus`/`SendMessage` issued during cold start record its `n.mu.RLock` **wait** time.
- Procedure: cold-launch (or notif-tap cold), fire a speculative `warmPeer`/`nodeStatus` as early as the
  Dart path allows, and measure how long that call blocks on the `Start()` write lock. Real device, iOS
  + Android, ≥20 cold launches.

Devices/sims: real iOS + Android device pair preferred (cold-start timing and thread scheduling are not
faithfully reproduced on sim). Host-fake Go microbench (M1 Go part) is the only host-runnable piece.

## Decision Criteria

- **Warm-state (M1):** if concurrent `warmPeer` inflates the user send's `queueWaitMs` by **< 5 ms p95**
  and `bridgeMs` is statistically unchanged → **confirm warm-state concurrency; pick Option A** (no queue,
  no second channel). If `queueWaitMs` inflation is **≥ 20 ms p95** on either platform → escalate to
  **Option B** (QoS/priority) for the send path; only consider C/D if B fails.
- **Cold-start (M2):** if a concurrent call blocks on the `Start()` write lock for **> 50 ms** → confirm
  the cold-start HOL and **require FDC-04 to gate `warmPeer`/`fastReprime` behind node-started**
  (`isStarted`/`node:start` ack) so warm never contends; optionally feed a follow-up to **shrink the
  `Start()` lock scope** (hold the write lock only for the `singletonNode`/`host` field swap, build the
  host outside the lock) — but that is a Go change owned by the cold-start plan, flagged here, not done
  here.
- **Thread-pool saturation:** if M1 shows send `queueWaitMs` growing with warm fan-out breadth → enforce
  FDC-04's "bound warm to the open peer only, never the roster" as a hard requirement (matches prior-art
  Berty "hundreds of peers cripples the phone").

## Expected Output  (what dependent plans consume)

1. **A one-line verdict the FDC-04 plan can cite:** *"The bridge is concurrent in the warm/steady state at
   every layer (iOS concurrent global queue `GoBridge.swift:35-42`; Android cached thread pool
   `GoBridge.kt:38`; Go bridge `nodeMu` pointer-read-only `bridge.go:1027-1029`; Go node `n.mu` RWMutex
   read-concurrent `node.go:1417-1419`). Real Go concurrency IS achieved by `Future.wait`. The ONE
   serialization point is `Node.Start`'s write lock held across bootstrap (`node.go:219-220`,
   `:218-468`), which blocks sends only on the cold path."*
2. **The mitigation decision:** **Option A (keep warm off the cold-start critical path + bound it)** as the
   default; **Option B (QoS hint)** held in reserve, taken only if M1 shows ≥20 ms p95 contention.
   **Reject Option C (Dart priority queue) and Option D (second channel)** as solving an absent problem —
   FDC-04 must **not** add either.
3. **Two measured numbers:** warm-state send `queueWaitMs` delta under concurrent warm (p95), and the
   cold-start `Start()`-lock blocking window (ms). The latter sets how hard FDC-04 must gate warm behind
   node-start, and is an input to the cold-start plan (P1-3).
   - **Host-measured (microbench, directional — device authoritative):** under 8 concurrent warm dials a
     real user send completes in **<1 ms** (no detectable queue-wait inflation; warm-state concurrency
     confirmed → **Option A**); the cold-start `Start()` write-lock hold window is **~15 ms** on host
     (`node:startup_timing{phase:start_lock_window}`). The host cold-start window is below the 50 ms
     decision threshold, but cold-launch/relay-warm timing is *not* faithfully reproduced off-device, so
     FDC-04 still honors the PS-3 node-started gate as a hard constraint; the **device** number authoritative.
4. **A hard constraint for FDC-02/03:** the staggered ranked race + parallel `storeInInbox` keep their
   true-parallel shape (no hidden serial ladder) — confirmed, so their per-leg budgets stand.

## Exit Gate

Spike is done when:
- **[✅ host done / ⏳ device pending]** M1 and M2 have run on at least one real iOS + one real Android device
  (warm-state delta + cold-start block window recorded), and the Go read-concurrency microbench passes. →
  **Microbench passes** (`TestConcurrentSendDialNoSerialize`, `-race`); M1/M2 **device run still pending**
  (deferred to the post-FDC-04 two-device smoke). The M1 `bridge:dispatch_timing` + M2 `start_lock_window`
  instruments needed for that device run are now wired (see Implementation note).
- **[✅ done]** The verdict line, the chosen mitigation (A, ±B), and the two numbers are written into the
  FDC-04 plan's Background as a cited assumption (RC5 row), and FDC-02/03 carry the "true-parallel confirmed"
  note. (The two *numbers* there are the host-measured values; device numbers replace them after the smoke.)
- **[✅ done]** FDC-04 explicitly records the "do not fire `warmPeer` until node started" gate (PS-3 /
  TC-04-05 / INV-4) and the "bound to the open peer, never the roster" constraint (PS-4 / TC-04-11 / INV-7).

## Risks / Unknowns

- **Measurement faithfulness:** thread scheduling and cold-start timing differ on sim vs device; treat
  host/sim numbers as directional, device numbers as authoritative (consistent with the proposal's
  "host-testable ≠ validated", §9.1).
- **`queueWaitMs` instrumentation is additive but touches the hot path** — keep it `kDebugMode`-gated like
  the existing timing telemetry (memory: 145/156 telemetry is debug-gated) so it doesn't ship cost.
- **Shrinking the `Start()` lock scope is a real Go refactor with its own race surface** — explicitly *out
  of scope here*; this spike only quantifies the window and hands it to the cold-start plan.
- **go-libp2p internal locks (peerstore, connmgr, swarm dial limits)** are resource contention, not app
  mutexes; the same-peer dial coalescing is a *benefit*. If M1 ever shows send slowdown that isn't
  `queueWaitMs` (i.e. `bridgeMs` itself inflates under warm), suspect swarm dial-limit contention and
  bound concurrent speculative dials — but source review gives no reason to expect this in the
  single-open-peer case.
- **iOS `.userInteractive` QoS overuse can invert priorities** if applied too broadly; Option B must tag
  *only* the user send, not all traffic.
