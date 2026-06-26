# FDC-S1 — Cold-start timing measurement  (Spike / Decision)

Status: **EXECUTED** — instrumentation landed (observation-only) + device campaign run
on Pixel 6 + iPhone 13. Numbers, Expected-Output values, and decisions are in
**`FDC-S1-cold-start-timing-RESULTS.md`** (harness: `fdc-s1-measurement/`). Headlines:
T_nodeStart 1158ms (Android) / 206ms (iOS); T_circuit 1564/913ms p90 (both ≤3s →
keep budget); DialTimeout = no-retime; FDC-04 warm-aggressiveness is PLATFORM-SPLIT;
T_mdns ≈3.5s flaky (start discovery earlier). Only `G_nse` (d) awaits a manual
peer-push+tap.

Gates:
- **FDC-07 (cold-start: earlier mDNS/reserve — proposal P1-3 §6.4)** — cannot be finalized until this
  resolves. P1-3 explicitly says *"Do NOT blindly cap the cold relay dial at 3s … Measure cold
  time-to-circuit first"* (proposal §8 P1-3, §11 Q3). FDC-07 would otherwise invent a re-timing of
  `DialTimeout` / `ForegroundRelay*Timeout` with no data, risking *more* abandoned reservations →
  *more* inbox fallback (proposal §10 bullet 1, §8 P1-3).
- **FDC-04 (LAN-aware eager `warmPeer` — proposal P0-1 §6.1)** — *calibrated*, not blocked. The numbers
  here set how aggressively `warmPeer` may dial on cold notif-tap, and confirm the proposal's "honest
  scope" claim that warming **cannot** overlap reading-time on the coldest path because the Go node
  is not started yet (proposal §6.1 "Honest scope", §10 bullet 1). Without the measured
  process-start→`node:start`-return gap, FDC-04 would over-promise P0 latency on cold launches.

## Question

On **real iOS and Android cold launches** (process spawned fresh, including the cold *notif-tap*
path), what are the measured wall-clock values for:

- **(a)** process-start (and notif-tap) → `node:start` returns (`NodeState` with a peerId/host ready);
- **(b)** process-start → **first circuit-v2 reservation / first circuit address** available;
- **(c)** process-start → **first bonsoir mDNS resolve** of a same-WiFi peer;
- **(d)** **where `peerId` first becomes available on a cold notif-tap** — is the *self* peerId and the
  *sender* peerId already in hand inside the iOS **NSE** (out-of-process), or only after the **main
  isolate** boots and `node:start` returns?

And from those: what are **realistic foreground budget values**, **how aggressively may FDC-04 warm
on cold start**, and **should the 15s `config.go:28 DialTimeout` be re-timed at all** (it is consumed
by a background goroutine, not the user send)?

## Why it blocks

The proposal repeatedly defers timing decisions to a measured cold-start trace and warns against
guessing:

- The §6.1 "Honest scope" paragraph and §10 bullet 1 both assert that on a **cold notif-tap the Go
  node isn't started yet** (`node:start` is gated behind deferred Firebase + bridge + ~25 startup
  listeners — confirmed: `main.dart:3066 startLiveServices()` starts the listener fleet; node-start
  is invoked through the Go bridge before that). The whole P0-1 warm story therefore hinges on **how
  long that gap actually is**. If it is, say, 400ms, FDC-04 can warm aggressively and still help on
  cold tap; if it is 4s, warming on cold tap is pointless and the win is purely FDC-07 (fast
  node-start + early reserve). The dependent plans would otherwise *invent* this number.
- P1-3 (FDC-07) is explicitly gated on "measure cold time-to-circuit first" (§8 P1-3, §11 Q3). The
  `15s DialTimeout` (`config.go:28`) looks scary but is consumed by a **background warm goroutine**
  (`node.go:429-439 warmRelayConnectionForStart`, fire-and-forget), not by the user's send — the
  foreground budgets are already separate (`config.go:39-41 ForegroundRelayDialTimeout=3s`,
  `ForegroundRelayReserveTimeout=3s`, `ForegroundCircuitAddressWaitTimeout=3s`). Re-timing the wrong
  timer is a no-op at best and a regression at worst.
- Open question §11 Q1 — "where is `peerId` first available on iOS cold notif-tap (NSE vs main
  isolate)" — directly determines whether `warmPeer` can fire from the notification handler before
  the chat screen builds. The answer is a hard architectural fact, not a tunable.

## Background (grounded in real source — what exists today)

**Cold-start path is already partially instrumented in Go; the instrumentation is relative, not
process-anchored.** `node.go` emits a `node:startup_timing` event family but each duration is
measured from a *local* start, not from process spawn:

- `node.go:417-421` — `phase:"host_ready"`, fields `libp2pNewMs` (`:362 time.Since(libp2pStart)`) and
  `pubsubInitMs` (`:383`). This is `libp2p.New(...)` + `initPubSub()` only — it does **not** include
  the Dart-side bridge init, Firebase deferral, key decode, or the gap from process spawn.
- `node.go:450-454` — `phase:"relay_warm_done"`, `relayWarmMs` measured from `:426 relayWarmStart`
  (the moment the warm goroutine is spawned at `:429`), `relaysAttempted`. First relay socket only.
- `node.go:919 / :931` — `relay:reservation_timing`, `reserveRpcMs` from `:886 reserveStart`.
- `node.go:1697 / :1707` — `circuit_address:timing`, `elapsedMs` from `:1684 start` (the
  circuit-address wait loop, `waitForCircuitAddress`).
- `node.go:645 / :668` — `relay:warm_timing`, `elapsedMs` from `:636` (per-relay warm attempt).

None of these carries a **process-start epoch anchor**, so (a)/(b)/(c) cannot be computed today
without adding one. The warm relay dial is bounded by the **background** `DialTimeout = 15s`
(`config.go:28`, used by `BackgroundTimeouts()` `config.go:116-123`); the **foreground** path uses
`ForegroundRelayDialTimeout = 3s` / `ForegroundRelayReserveTimeout = 3s` /
`ForegroundCircuitAddressWaitTimeout = 3s` (`config.go:39-41`) and `InteractiveDialTimeout = 4s` /
`InteractiveSendTimeout = 3s` / `InteractiveDiscoverTimeout = 2s` (`config.go:76-79`).

**Warm path (Dart).** `p2p_service_impl.dart:572-647 warmBackground()` is fire-and-forget; it does a
"fast circuit check" poll after a fixed `Duration(seconds: 2)` (`:596`) emitting
`P2P_FAST_CIRCUIT_CHECK` (`:604-611`), then runs inbox drain + `_startLocalDiscovery`
(`:624-640`) concurrently and emits `P2P_SERVICE_WARM_BACKGROUND_BEGIN`/`...COMPLETE`
(`:585-589`, `:642-646`). bonsoir advertising/discovery starts only inside `_startLocalDiscovery`
(`:649-659 localP2P.start()`), i.e. *after* node-start, matching the proposal §3 "cold open → empty
discovered-peers map" claim.

**LAN discovery (bonsoir).** `bonsoir_discovery_service.dart` emits `LOCAL_MDNS_ADVERTISE_START`
(`:82-84`) and `LOCAL_MDNS_DISCOVERY_START` (`:95-97`) but **no resolve-complete timing event** —
there is no flow-event marking when a specific peer's `service.resolve(...)` returns with an
endpoint. `discoverLocalPeer(peerId, timeout)` is exposed at `p2p_service_impl.dart:4131-4143` →
`local_p2p_service.discoverLocalPeer`. So (c) needs a new resolve-complete event.

**Resume path (Dart).** `handle_app_resumed.dart:130-191` already measures step durations with local
`DateTime.now()` diffs (`healthMs` `:137`, `reinitMs` `:146`, `hcMs` `:164`, `drainMs` `:190`) via
`debugPrint`, but these are **serial awaited** (bridge health → `performImmediateHealthCheck` →
`retryPushRegistration` → `drainOfflineInbox`) and are *not* epoch-anchored flow events — they cannot
be correlated to a process-start clock without a new anchor.

**iOS cold notif-tap.** `ios/NotificationService/NotificationService.swift:7-12` constructs a
`NotificationPreviewResolver` with `KeychainPushKeyReader()` + `BridgePushDecryptor()` and
**decrypts the push preview out-of-process** (`:27-33 previewResolver.resolve(userInfo:…)`). So in the
NSE: the **self** decryption key is reachable from the App-Group keychain, and the **sender** peerId
is carried in `userInfo` (the resolver reads chat decrypt-input from it — `NotificationPreviewResolver.swift`
decrypt paths). But the **Go libp2p node is not running in the NSE** — the NSE only decrypts a
preview and hands content back (`:59 contentHandler`). The host/peerId on the libp2p side becomes
available only after the **main isolate** boots and `node:start` returns (`node.go:368
n.peerId = h.ID().String()`). Cold-start deferral (memory: project 164) pushes Firebase +
`startLiveServices` off the pre-`runApp` path, so node-start is *later* on cold launch than a warm
resume. This is the crux of question (d).

## Options (instrumentation approaches — pick the measurement vehicle)

### Option A — Epoch-anchored flow-events, reuse existing `emitFlowEvent`/`emitEvent` (RECOMMENDED)

Capture a single **process-start monotonic anchor** at the earliest point of `main()` (before
`runApp`), thread it (or a global `Stopwatch`/epoch) so every cold-start milestone emits an
`*_TIMING` flow-event carrying `sinceProcessStartMs`. Add the few missing anchors; reuse the existing
`node:startup_timing` family by adding a `processStartEpochMs` / `sinceProcessStartMs` field.

- **Pros:** uses the app's existing telemetry spine (`emitFlowEvent` Dart + `emitEvent` Go); events
  already flow to the debug sink; minimal new surface; correlates Dart and Go on one clock; works on
  both iOS + Android identically; no new tooling.
- **Cons:** Dart and Go have separate clocks — must anchor with a **shared wall-clock epoch** passed
  into `node:start` config (or emit Go events with `time.Now().UnixMilli()` and subtract the Dart
  process-start epoch in post-processing). Need to avoid clock-skew by anchoring both to the same
  `node:start` invocation timestamp.
- **Cost:** ~6 new/edited emit sites (see Method); no behavior change.
- **Additive-only / NET-REL-07 impact:** zero — pure observation, no relay/protocol change, no
  timeout change. Mirrors the existing holepunch tracer "instrument-only" precedent (`node.go:317-327`).
- **iOS/Android:** identical. iOS NSE timestamp logged via the NSE's existing
  `LogPushPreviewEventEmitter` (`NotificationService.swift:6`), correlated by `messageId`/push-id to
  the main-isolate node-start event.

### Option B — External wall-clock harness (xcrun/adb + screen capture)

Drive cold launches from the host (`xcrun simctl launch` / `adb shell am start`), timestamp from the
OS launch log and from a first-frame screenshot; read node-readiness from `adb logcat` / device
console `[NODE]` log lines (`node.go:372-374`).

- **Pros:** captures the true *user-perceived* process-spawn → first-useful-frame, including OS
  app-launch overhead the in-app anchor misses.
- **Cons:** coarse (frame granularity); cannot see NSE-vs-main-isolate peerId availability; sim mDNS
  is shared-host and unreliable for (c) (memory + `e2e_test_mode.dart:2 kDisableLocalDiscovery`);
  hard to correlate to the specific peer/circuit. Not reproducible in CI.
- **Cost:** low setup, high per-run manual effort.
- **Additive-only:** N/A (no code change) but blind to (d).
- **iOS/Android:** asymmetric tooling.

### Option C — Hybrid (A for in-process milestones + B for the OS-launch prefix)

Use Option A for (a)–(d) in-process, and one Option-B measurement per platform to capture the OS
process-spawn → `main()` prefix that A cannot see, then add the two.

- **Pros:** complete picture; the prefix is measured once per platform and added as a constant.
- **Cons:** two methods; the prefix is device-variable.
- **Decision:** **Adopt Option A as the spine; take Option C's single OS-prefix measurement per
  platform** so the reported "process-start" number is honest about the pre-`main()` OS cost.

## Method (exactly how to measure)

**Instrument (all additive, observation-only — no timeout/behavior change):**

1. **Process-start anchor (Dart).** At the first line of `main()` in `lib/main.dart` (before
   `runApp`), record `final processStartEpochMs = DateTime.now().millisecondsSinceEpoch;` and a
   monotonic `Stopwatch`. Pass `processStartEpochMs` down into the `node:start` bridge config so Go
   can compute `sinceProcessStartMs`. (Carrier: extend `NodeConfig` with an optional
   `ProcessStartEpochMs int64` — additive field, ignored by older code paths.)

2. **(a) node:start return.** Emit a Dart flow-event `FDC_COLDSTART_NODE_START_RETURN_TIMING` with
   `sinceProcessStartMs` at the call site where the `node:start` bridge call resolves (the
   `LocalP2PService` start path, `main.dart:1893-1914` region). In Go, add
   `sinceProcessStartMs` to the existing `host_ready` emit (`node.go:417-421`) computed as
   `time.Now().UnixMilli() - cfg.ProcessStartEpochMs`.

3. **(b) first circuit reservation / address.** Add `sinceProcessStartMs` to the existing
   `relay:reservation_timing` (`node.go:919/931`) and `circuit_address:timing` (`node.go:1697/1707`)
   emits. Also emit a one-shot `FDC_COLDSTART_FIRST_CIRCUIT_TIMING` from the Dart side at the first
   `node:status` that reports a non-empty `circuitAddresses` (the `P2P_FAST_CIRCUIT_CHECK` site,
   `p2p_service_impl.dart:604-611`, already runs at the 2s poll — add `sinceProcessStartMs` and a
   `circuitReady` bool there, and at the EventChannel circuit-address push handler).

4. **(c) first mDNS resolve.** Add a resolve-complete flow-event
   `FDC_COLDSTART_FIRST_MDNS_RESOLVE_TIMING { peerId, sinceProcessStartMs }` in
   `bonsoir_discovery_service.dart` at the point a `service.resolve(...)` first returns an endpoint
   for any peer (the resolved-event handler near `:101`), and a per-peer variant when
   `discoverLocalPeer` (`p2p_service_impl.dart:4131-4143`) resolves the requested peer. Pair with the
   existing `LOCAL_MDNS_DISCOVERY_START` (`:95-97`) to get start→resolve delta.

5. **(d) peerId availability on cold notif-tap.** In the iOS NSE, emit (via the existing
   `LogPushPreviewEventEmitter`, `NotificationService.swift:6`) `FDC_NSE_PEERID_AVAILABLE
   { selfKeyPresent, senderPeerIdPresent, nseEpochMs, pushId }` right after `previewResolver.resolve`
   (`:33`). On the main isolate, emit `FDC_COLDSTART_NOTIF_TAP_NODE_READY { pushId,
   sinceProcessStartMs, sinceNseEpochMs }` when `node:start` returns on a launch whose route is a
   notif-tap (correlate by `pushId`/`messageId` carried through the route target,
   `prepare_notification_open_use_case.dart` route plumbing). This yields the **NSE-vs-main-isolate
   gap** directly.

6. **Resume comparison (control).** Convert the existing `handle_app_resumed.dart:130-191` local
   `DateTime` diffs into epoch-anchored flow-events (`FDC_RESUME_STEP_TIMING { step, ms }`) so
   warm-resume and cold-start are on the same axis (sanity baseline; resume should be far faster than
   cold).

**Run (devices — NOT sim for (c)):**

- **Devices:** ≥2 real iOS (one older e.g. iPhone SE/11-class, one current) and ≥2 real Android (one
  low-end / Go-edition-class, one flagship). Two of each on one WiFi for the (c) same-WiFi resolve.
  Real devices because: sim mDNS is host-shared/unreliable (forces `DISABLE_LOCAL_DISCOVERY`, memory;
  `e2e_test_mode.dart:2`), and cold-launch CPU/IO timing on a sim does not reflect a phone.
- **Scenarios, ≥10 cold trials each (kill app fully between trials):**
  - S-warm-cold: force-quit → tap app icon → first conversation open (measures a,b,c).
  - S-notif-tap-cold: force-quit → push from peer → tap notification (measures a,b,c,d).
  - S-network: WiFi-only, cellular-only, and WiFi→cellular switch mid-launch (network-change re-warm,
    proposal §12 "borrow verbatim").
- **Commands (capture flow-events):** run the app's existing flow-event/debug sink capture; pull Go
  `[NODE]` console lines via `xcrun simctl spawn booted log stream` (device: Console.app) and
  `adb logcat -s NODE` for cross-checking the Go-side `host_ready`/timing emits. Take an
  `xcrun simctl io <udid> screenshot` (or device screen-record) at first useful frame for the
  Option-C OS-prefix add-on, per the MEMORY screenshot-on-stall practice.
- **Aggregate:** report **median + p90** per metric per device-class per scenario (not mean — cold
  start is heavy-tailed).

## Decision Criteria (the concrete thresholds that pick values)

Let `T_nodeStart` = median (a), `T_circuit` = median (b), `T_mdns` = median (c),
`G_nse` = median NSE→main-isolate node-ready gap (d).

1. **Foreground relay budgets (`ForegroundRelay*Timeout`, currently 3s).**
   - If `T_circuit` p90 ≤ current 3s budget → **keep 3s** (no change; budgets already cover the
     measured cold reserve).
   - If `T_circuit` p90 is in (3s, 5s] → **raise** foreground reserve/circuit-wait to
     `ceil(p90)` (so a genuinely-cold reserve isn't abandoned into inbox fallback). Do **not** lower.
   - If `T_circuit` p90 > 5s → **do not cap harder**; instead FDC-07 must move mDNS/reserve *earlier*
     (start before `warmBackground`'s post-startup fire-and-forget) rather than shorten the timer.
     Record the dominant sub-phase (`libp2pNewMs` vs `relayWarmMs` vs `reserveRpcMs` vs
     `circuitAddressWaitMs`) to know *what* to move earlier.

2. **`config.go:28 DialTimeout = 15s` re-timing — default answer is DO NOT re-time.**
   - Re-time **only if** the measurements show the user's *send* path (not the background warm
     goroutine) actually blocks on this timer. Evidence required: a foreground send whose latency
     tracks the 15s value. Source says it is consumed by the fire-and-forget warm goroutine
     (`node.go:429-439`) and the send path uses Interactive/Foreground budgets — so the expected
     conclusion is **leave 15s as-is** and instead ensure FDC-07 starts the warm earlier. Capping it
     risks abandoning a slow-but-succeeding cold QUIC/TLS handshake → more inbox fallback
     (proposal §8 P1-3, §10 bullet 1). **Explicitly warn FDC-07 against blindly capping cold dials.**

3. **How aggressively FDC-04 warms on cold start.**
   - If `T_nodeStart` (a) ≤ ~800ms → cold-tap `warmPeer` can fire essentially at node-ready and still
     overlap some reading time → FDC-04 may warm on cold notif-tap (bounded, debounced).
   - If `T_nodeStart` > ~1.5s → cold-tap warming gives little overlap; FDC-04 should **skip
     speculative dial on the coldest path** and rely on FDC-07 (fast node-start + early reserve);
     warm only after node-ready for the *warm-open* case. This confirms/quantifies proposal §6.1
     "Honest scope".

4. **(d) NSE peerId availability.**
   - If self-key + sender peerId are present in the NSE (expected from
     `NotificationService.swift:7-33`), record it as a **known fact**, but conclude that
     `warmPeer` **still cannot dial from the NSE** (no libp2p host there) — the earliest a warm dial
     can start is `node:start` return on the main isolate, i.e. `T_nodeStart + G_nse` after tap.
     This sets the hard floor FDC-04 must respect.

5. **mDNS (c).** If `T_mdns` p90 ≤ the LAN send budget (`interactiveLocalBudget` 1500ms,
   `send_chat_message_use_case.dart:21`) → LAN-first is reachable on cold open with early start;
   if > 1500ms → FDC-07/FDC-04 must start bonsoir discovery *before* the first send window (proposal
   §3 "LAN advantage routinely missed") or raise the LAN budget. Report start→resolve delta so we
   know whether the cost is *starting* discovery vs the resolve RTT.

## Expected Output (the values the dependent plans consume)

- **`FOREGROUND_RELAY_BUDGET_MS` = N** (one of: keep 3s / raise to ceil(p90) / "do-not-cap, move
  earlier") — consumed by FDC-07 and any budget edit (each gated on a mutation-verified RED test +
  1to1/feed gate re-run, proposal §10 last bullet).
- **`DIALTIMEOUT_RETIME` = {no | yes→value}** — default **no**, with the evidence rule in Criterion 2.
- **`COLD_WARM_AGGRESSIVENESS` = {warm-on-cold-tap | warm-only-after-node-ready}** + the measured
  `T_nodeStart` median/p90 — consumed by FDC-04.
- **`NSE_PEERID_FACT` = {self+sender available in NSE: yes/no}** and **`G_nse` gap ms** — consumed by
  FDC-04 (and answers proposal §11 Q1 / Q3).
- **`T_circuit`, `T_mdns` median+p90 per device-class** — the calibration inputs proposal §11 Q3
  asks for.

## Exit Gate

Spike is done when:
1. The 5 instrumentation sites (Method 1–5) are landed as **observation-only** (no timeout/behavior
   change; additive `NodeConfig.ProcessStartEpochMs`), verified by zero diff in existing send-path
   behavior and no NET-REL test-lock regression.
2. ≥10 cold trials per scenario per device-class are captured on ≥2 real iOS + ≥2 real Android, with
   median+p90 tables for (a)(b)(c)(d).
3. The five Expected-Output values are filled in with numbers, and the DialTimeout-retime decision is
   recorded with its evidence (send-path-blocks: yes/no).
4. FDC-04 and FDC-07 reference this doc's numbers instead of inventing budgets.

## Risks / Unknowns

- **Dart↔Go clock skew.** The two runtimes have independent clocks; anchoring requires passing one
  shared epoch through `node:start` config and computing Go deltas against it. Mitigate by also
  emitting raw `time.Now().UnixMilli()` so post-processing can re-base.
- **Heavy-tailed cold start.** Means are misleading; report median+p90 and never tune to the mean.
- **iOS NSE memory/time limits.** The NSE has a hard ~30s budget and tight memory; the extra
  `FDC_NSE_PEERID_AVAILABLE` emit must be trivial and must not delay `contentHandler`
  (`NotificationService.swift:59`). Emit *after* content is handed back if needed.
- **Cold notif-tap on a fresh process may never have started the node before the screen wants to
  send** — confirming the proposal's honest-scope claim; the measurement must capture the *send
  attempt* timestamp too, or it cannot prove the warm window is empty.
- **Sim mDNS unreliability** blocks (c) on simulators — (c) is **device-only**; do not report sim
  numbers for it (consistent with `e2e_test_mode.dart:2 kDisableLocalDiscovery` and proposal §6.5
  "device-only validation").
- **The single Go bridge serializes** warm + reprime + send (proposal §10 bullet 3); a cold trace
  that fires all three will show head-of-line blocking — measure with the user-send prioritized, or
  the numbers over-state warm cost.
- **Do NOT let this spike's instrumentation drift into a behavior change.** Any timeout edit belongs
  to FDC-07 *after* the numbers exist — this doc only measures.
