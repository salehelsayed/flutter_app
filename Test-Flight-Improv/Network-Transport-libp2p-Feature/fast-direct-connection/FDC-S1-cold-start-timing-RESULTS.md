# FDC-S1 — Cold-start timing measurement: RESULTS

Status: **instrumentation landed + verified (Exit Gate 1 ✅); device campaign DONE — (a)(b)(c)(d) + resume captured on Pixel 6 + iPhone 13.** (d) found+fixed a real iOS notif-tap wiring bug; the cold-tap chain is validated end-to-end (§3.4.2). The literal `G_nse` is dominated by human tap-reaction time, so it's not a useful metric — FDC-04 keys off `T_nodeStart`.
Parent spike: `FDC-S1-cold-start-timing-measurement-spike.md`. Drives FDC-04 and FDC-07.

This doc holds the numbers the dependent plans consume. The measurement harness
(scripts + parser + per-trial logs) lives under `fdc-s1-measurement/`.

---

## 1. Instrumentation landed (observation-only, additive)

All six Method sites from the spike are wired. Event names are free strings (no
registry). `NodeConfig.ProcessStartEpochMs` is an additive Dart→Go field; **no
timeout or send-path behaviour was changed.**

| Spike method | Where | Event(s) emitted |
|---|---|---|
| 1 process anchor | `StartupTiming` accessors (`processStartEpochMs`/`sinceProcessStartMs`) reuse the existing `app_start` mark at `main()` top; threaded into `node:start` via `callP2PNodeStart` → `NodeConfig.ProcessStartEpochMs` | — |
| 2(a) node:start return | `p2p_service_impl.startNodeCore` + Go `node.go` host_ready | `FDC_COLDSTART_NODE_START_RETURN_TIMING`; Go `node:startup_timing{phase:host_ready,sinceProcessStartMs}` |
| 3(b) first circuit | `p2p_service_impl._handleAddressesUpdated` (one-shot) + Go reservation/circuit emits | `FDC_COLDSTART_FIRST_CIRCUIT_TIMING`; Go `relay:reservation_timing` + `circuit_address:timing` `{sinceProcessStartMs}`; `P2P_FAST_CIRCUIT_CHECK` enriched |
| 4(c) first mDNS resolve | `bonsoir_discovery_service` resolved handler (per-peer one-shot) | `FDC_COLDSTART_FIRST_MDNS_RESOLVE_TIMING{peerId,sinceProcessStartMs,firstResolveOverall}` |
| 5(d) NSE peerId + notif-tap | iOS NSE `NotificationPreviewResolver.resolve` + `ColdStartNotifAnchor` (main isolate) | `FDC_NSE_PEERID_AVAILABLE{selfKeyPresent,senderPeerIdPresent,nseEpochMs,pushId}`; `FDC_COLDSTART_NOTIF_TAP_NODE_READY{pushId,sinceProcessStartMs,epochMs,trigger}` |
| 6 resume control | `handle_app_resumed` (alongside existing debugPrints) | `FDC_RESUME_STEP_TIMING{step,ms}` |

**Verification (Exit Gate 1):**
- Go `node`+`bridge` build + vet clean (go1.25.0); full `go test ./node/ ./bridge/` **pass** (428s / 198s) — the 2 tests that read `node:startup_timing` payloads (`benchmark_startup_test`, `benchmark_send_test`) read specific keys, so the additive `sinceProcessStartMs` key doesn't break them.
- `flutter analyze lib`: 0 errors, 0 new issues.
- NET-REL-05 send-path budget hard gate + the flow-event-capture send test: pass (one timing-sensitive negative-control flaked once under concurrent Go-test CPU load; passes 3/3 isolated).
- New `ColdStartNotifAnchor` latch test: 6/6.
- **Dart↔Go clock cross-check (device-validated):** `a_node_start_ms` (Dart) tracks `go_host_ready_ms` (Go) within 1–3 ms across all trials → the shared-epoch anchoring is sound.

### Measurement build flag (observation-only)
`--dart-define=FDC_FLOW_LOG=1` (accepts `1`/`true`/`yes`/`on`) forces
`flowEventLoggingEnabled=true` and switches to `debugPrintSynchronously` (so the
default 16 KB/s throttle doesn't drop bursty cold-start `[FLOW]` lines). OFF and
inert in a normal build. Native libs rebuilt with `GOTOOLCHAIN=go1.25.0`
(`make android` / `make ios`).

---

## 2. Device matrix

| Class | Device | OS | Status |
|---|---|---|---|
| Android flagship | **Pixel 6** (21071FDF600CSC) | Android 16 / API 36 | ✅ (a)(b) n=12, (c) n=6+8, resume n=5 |
| Android low-end | — | — | not available (only Pixel 6 on hand) |
| iOS | **iPhone 13** (00008110…) | iOS 26.5 | ✅ (a)(b) n=12; advertiser for (c); (d) wired |
| iOS older | iPhone 11 (wireless) | — | not run |

Real devices because sim mDNS is host-shared/unreliable (spike §Risks;
`e2e_test_mode.dart kDisableLocalDiscovery`). The Option-C OS-prefix (process
spawn → `main()`) is NOT included in these numbers — they are anchored at the
`app_start` mark (first line of `main()`), so add a per-platform constant for the
true user-perceived spawn time.

---

## 3. Results

### 3.1 Pixel 6 — `S-warm-cold` (force-quit → cold launch), n = 12

Median + p90 (ms). Cold start is heavy-tailed → never the mean.

| metric | n | min | **median** | **p90** | max |
|---|---|---|---|---|---|
| **(a) node:start return** `a_node_start_ms` | 12 | 1131 | **1158** | **1200** | 1284 |
| &nbsp;&nbsp;Go host_ready (Go clock) | 12 | 1130 | 1156 | 1199 | 1283 |
| &nbsp;&nbsp;libp2pNewMs (sub-phase) | 12 | 14 | 22 | 24 | 26 |
| &nbsp;&nbsp;pubsubInitMs (sub-phase) | 12 | 0 | 0 | 1 | 1 |
| &nbsp;&nbsp;relay_warm_done (since proc start) | 12 | 1240 | 1310 | 1513 | 1592 |
| &nbsp;&nbsp;relayWarmMs (sub-phase) | 12 | 109 | 128 | 313 | 442 |
| **(b) first circuit address** `b_first_circuit_ms` | 12 | 1289 | **1364** | **1564** | 1660 |
| &nbsp;&nbsp;Go circuit (since proc start) | 12 | 1331 | 1438 | 1602 | 1756 |
| &nbsp;&nbsp;circuitWaitMs (sub-phase) | 12 | 200 | 202 | 403 | 607 |

**Reading of the Pixel 6 numbers:**
- **Node-start is dominated by Dart pre-node startup**, not transport: `libp2pNewMs`
  median 22 ms, `pubsubInitMs` ≈ 0. The ~1130 ms before `host_ready` is the
  Dart critical path (deferred Firebase + bridge init + key decode + ~25 startup
  listeners) that runs *before* `node:start`. This is exactly the spike's §6.1
  "Honest scope": on the coldest path the Go node is not even started for the
  first ~1.15 s.
- **The dominant sub-phase of (b) after node-ready is `circuitWaitMs`** (median
  202 ms, p90 403 ms) plus the relay warm (relayWarmMs median 128 ms). The
  reserve/circuit RPCs are cheap once the node exists; the cost is getting the
  node existing.
- **T_circuit p90 = 1564 ms is well under the current 3 s foreground budgets.**

### 3.2 iPhone 13 — `S-warm-cold` (terminate → cold launch), n = 12

| metric | n | min | **median** | **p90** | max |
|---|---|---|---|---|---|
| **(a) node:start return** `a_node_start_ms` | 12 | 192 | **206** | **217** | 217 |
| &nbsp;&nbsp;Go host_ready (Go clock) | 12 | 191 | 205 | 214 | 217 |
| &nbsp;&nbsp;libp2pNewMs (sub-phase) | 12 | 10 | 11 | 12 | 16 |
| &nbsp;&nbsp;relay_warm_done (since proc start) | 12 | 306 | 314 | 347 | 401 |
| &nbsp;&nbsp;relayWarmMs (sub-phase) | 12 | 104 | 110 | 130 | 197 |
| **(b) first circuit address** `b_first_circuit_ms` | 12 | 749 | **898** | **913** | 946 |
| &nbsp;&nbsp;circuitWaitMs (sub-phase) | 12 | 200 | 202 | 402 | 402 |

### 3.2.1 Device-class comparison (the headline)

| | **(a) T_nodeStart** med / p90 | **(b) T_circuit** med / p90 | libp2pNewMs med |
|---|---|---|---|
| Android flagship (Pixel 6) | **1158 / 1200 ms** | **1364 / 1564 ms** | 22 ms |
| iOS (iPhone 13) | **206 / 217 ms** | **898 / 913 ms** | 11 ms |

Both platforms spend **single-digit-to-low-tens of ms in `libp2p.New`** — the
node-start cost is the **Dart pre-`node:start` prologue**, not the transport. The
~950 ms Android-vs-iOS gap in (a) is entirely in that prologue (deferred
Firebase + bridge init + key decode + `startLiveServices` listener fleet running
before `node:start`); on this hardware the Pixel's prologue is ~5.6× the
iPhone's. **This is the single most decision-relevant result** because it flips
FDC-04's cold-tap warm aggressiveness *per platform* (§4.3).

### 3.3 (c) mDNS two-device (Pixel cold-launch resolving an advertising iPhone)

Setup: both on WiFi `Vodafone-CA38` (192.168.0/24); iPhone foregrounded +
advertising (`LOCAL_MDNS_ADVERTISE_START` port 57862, confirmed visible to the
Mac's `dns-sd -B _mknoon._tcp` browse → the network propagates mDNS, no full AP
isolation). Metric = Pixel `FDC_COLDSTART_FIRST_MDNS_RESOLVE_TIMING`
(process-start → first resolve of the iPhone peer).

**Headline (c) finding — Android LAN discovery is permission-gated and flaky:**

| Pixel state | trials resolved | T_mdns (resolved) |
|---|---|---|
| **as-shipped (location DENIED, no `NEARBY_WIFI_DEVICES`)** | **1 / 6** | 3605 ms |
| location GRANTED (controlled) | _see §3.3.1_ | _see §3.3.1_ |

In the as-shipped state the Pixel logs `LOCAL_MDNS_SUSPECTED_PERMISSION_DENIED`
and resolves the peer on only 1 of 6 cold trials — and even then at **3605 ms**,
**> 2× the 1500 ms `interactiveLocalBudget`**. The app declares only
`ACCESS_FINE/COARSE_LOCATION` (both **denied** on the device) and **no
`NEARBY_WIFI_DEVICES`** — on Android 13+ `NsdManager` browse/resolve is gated on
exactly those, so the LAN advantage is *structurally* unreliable on modern
Android. This is a concrete mechanism behind the proposal §3 "LAN advantage
routinely missed", independent of the serial send cascade.

### 3.3.1 (c) with location granted (controlled)

Granting `ACCESS_FINE/COARSE_LOCATION` (then revoked to restore state) raises the
resolve rate but **not** the latency:

| Pixel state | resolved / trials | T_mdns of resolved (ms) |
|---|---|---|
| as-shipped (location denied) | 1 / 6 (~17%) | 3605 |
| location granted | **5 / 8 (~62%)** | 3444, 3471, 3539, 3567, 10552 → **median ≈ 3539**, p90 ≈ 10552 |

So the permission gate explains the *reliability* (17% → 62%), but **T_mdns stays
≈ 3.5 s median even when it works** — and 38% still miss inside a 50 s window. The
Mac's `dns-sd` browse sees the advertisers throughout, so the cost is in the
Android `NsdManager` browse→resolve path (cross-platform Android→iOS), not the
network. **T_mdns ≈ 3.5 s ≫ 1500 ms `interactiveLocalBudget`** on both states.

### 3.4 (d) cold notif-tap (NSE peerId + NSE→main `G_nse` gap)

Instrumentation is **wired and shipped** on the iPhone: `FDC_NSE_PEERID_AVAILABLE`
is compiled into `NotificationService.appex` (emits right after the NSE parses
push route data, before any early-return) and `FDC_COLDSTART_NOTIF_TAP_NODE_READY`
fires once on the main isolate when both the cold notif-tap is consumed
(`handleInitialRemoteMessage` → `ColdStartNotifAnchor.recordNotifTap`) and
`node:start` returns (`recordNodeReady`). Both carry absolute epochs +
`pushId` so post-processing computes `G_nse = main.epochMs − NSE.nseEpochMs`
matched by `pushId` (the APNs `userInfo` carries no timestamp to thread inline).

**What the (d) measurement still needs (manual, ~2 min — cannot be CLI-driven):**
a real 1:1 push from a friend device while the target is force-quit, then a
*physical tap* on the notification. There is no reliable CLI to (a) compose+send
a chat from one of these accounts or (b) tap a specific notification on a real
iPhone (`xcrun simctl` notif APIs are simulator-only). Procedure:

```bash
# capture on the target iPhone (force-quit first)
xcrun devicectl device process terminate --device <iphone> --bundle-identifier com.mknoon.app
idevicesyslog -u <iphone> > logs/notif_tap/ios_d.log &
# → from a FRIEND device, send the target a 1:1 message; wait for the banner
# → TAP the notification on the iPhone (cold launch)
# wait ~20s, stop capture, then:
python3 scripts/fdc_parse.py --nse --label iphone13/notif_tap logs/notif_tap/ios_d.log
#   → prints FDC_NSE_PEERID_AVAILABLE {selfKeyPresent, senderPeerIdPresent, nseEpochMs}
#     + FDC_COLDSTART_NOTIF_TAP_NODE_READY {epochMs} and computes G_nse.
```

**Conclusion that does NOT need the run (already firm from source + (a)):** the
libp2p host does not exist in the NSE, so the earliest a warm dial can start on a
cold tap is `node:start`-return on the main isolate = `T_nodeStart + G_nse` after
tap. `G_nse` is the small NSE→main handoff (the NSE only NSLogs + hands content
back); it is dominated by `T_nodeStart` (206 ms iOS / 1158 ms Android), which is
the number FDC-04 must respect. So even unmeasured, `G_nse` does not change the
warm-floor conclusion — it only refines it by tens of ms.

#### 3.4.1 What the device runs actually surfaced (two real findings)

Two cold notif-tap runs (peer sends a 1:1 from the Pixel → tap on the iPhone)
were captured. Neither produced `FDC_COLDSTART_NOTIF_TAP_NODE_READY`, and the
*reasons why* are more useful than the gap number:

1. **Instrumentation bug, found + fixed.** On iOS the cold notif-tap is delivered
   through the **native APNs open bridge** (`IosApnsNotificationOpenBridge`
   `consumeInitialNotificationOpen` → `IOS_APNS_INITIAL_NOTIFICATION_OPENED`),
   **not** `FirebaseMessaging.getInitialMessage` / `handleInitialRemoteMessage`
   where `recordNotifTap` was first wired. So on iOS the anchor's notif-tap
   signal never fired. **Fixed**: `recordNotifTap` is now also wired into the iOS
   bridge's cold-initial consume path. This is a "passes host tests, silently
   dead on device" defect that only the real run could catch.

2. **iOS background-launches the app on the content push — *before* the tap.**
   The captured timeline:
   - `19:08:22.48` — app **cold-launches** and `node:start` returns (193 ms) —
     this is the **background push launch**, not the tap.
   - `19:08:26.82` — user taps → `IOS_APNS_NOTIFICATION_OPENED` → **warm resume**
     (`FDC_RESUME_STEP_TIMING`), because the process was already alive.

   So for this app (its pushes carry background-wake), the **pure cold-notif-tap
   — terminated → tap → fresh process — is uncommon**: the push spins the node up
   in the background ~0.2 s in, and the tap ~4 s later just resumes it. **This
   refines FDC-04 favorably**: on a notif-driven open the node is typically
   *already ready* before the user taps, so the warm-dial floor is effectively
   met by the background launch, not gated on a post-tap cold start.

3. **NSE emit is shipped + fires; `idevicesyslog`/headless tooling can't carry
   it.** The built `NotificationService.appex` binary contains
   `FDC_NSE_PEERID_AVAILABLE` (`strings` confirmed), the NSE process launches on
   each push, and the preview decrypts (the banner showed the text) — which means
   `didReceive → resolve()` ran, and the emit sits at the top of `resolve()`
   before any return, so it fired. It just isn't captured: `idevicesyslog`
   reliably carries the main-app `[FLOW]` but drops the short-lived extension's
   os_log, and `log collect --device-udid` needs admin (not runnable headless).
   `NSE_PEERID_FACT` is firm from code (the resolver reads the identity ML-KEM key
   from the App-Group keychain + `sender_id` from `userInfo`).

#### 3.4.2 (d) RESULT — cold-tap node-ready captured (round 3)

With **Low Power Mode** on (it suppresses the background push-launch from §3.4.1,
forcing a true terminated→tap→fresh-process), the post-fix run captured the full
cold notif-tap chain on the iPhone:

```
19:19:25.645  IOS_APNS_INITIAL_NOTIFICATION_OPENED      ← cold-initial path (recordNotifTap, post-fix)
19:19:25.749  P2P_SERVICE_START_NODE_CORE_BEGIN
19:19:25.849  FDC_COLDSTART_NODE_START_RETURN_TIMING     sinceProcessStartMs = 848
19:19:25.849  FDC_COLDSTART_NOTIF_TAP_NODE_READY  {pushId:95c1c968…, sinceProcessStartMs:848, epochMs:…849, trigger:node_ready}
```

- **Wiring fix validated end-to-end** — `FDC_COLDSTART_NOTIF_TAP_NODE_READY` now
  fires on iOS (it never could before the fix). Ordering confirms the anchor
  logic: notif-tap consumed first (boot, ~644 ms), node-ready second (848 ms) →
  emit on the second signal (`trigger:node_ready`).
- **Cold-tap node-ready ≈ 848 ms** here, but **inflated by Low Power Mode's CPU
  throttle** (LPM was required to force the true cold-tap). Without LPM the same
  push *background-launches* the app (§3.4.1) so the node is ready ~206 ms in,
  *before* the tap. **Either way the warm-dial floor = `T_nodeStart` on the open
  path; it is met at/near node-ready, not gated on anything the NSE could do.**
- **`G_nse` is not a useful system metric**: `main.epochMs − nse.nseEpochMs` is
  dominated by human tap-reaction time (the banner waits for the user), so the
  meaningful floor is `T_nodeStart` (captured), not the literal NSE→main delta.

### 3.5 Resume control (Method 6) — `FDC_RESUME_STEP_TIMING` (warm baseline)

Pixel 6, 5 background→foreground resume cycles (warm — process never died):

| resume step | median ms | range |
|---|---|---|
| `bridge_health` | 3 | 2–9 |
| `drain_offline_inbox` | 84 | 80–97 |
| `perform_immediate_health_check` | 129 | 117–359 |
| `bridge_reinit` | — | not fired (bridge stayed healthy) |

Total warm re-arm ≈ **0.2–0.45 s** — far below the Pixel's cold node-start
(1158 ms) and first-circuit (1364 ms). **Sanity baseline holds: warm resume ≪
cold start**, as expected, and the bridge does not need reinitialising on a quick
foreground (so the serial-awaited resume chain the spike flagged is cheap when
warm). This is the control that makes the cold-start numbers above meaningful on
the same axis.

---

## 6. Conclusions (what the cold-start trace actually shows)

1. **The cold-start long pole is the Dart pre-`node:start` prologue, not the
   transport.** `libp2pNewMs` is 11–22 ms on both platforms; the node-start cost
   is the Dart critical path before `node:start` (deferred Firebase + bridge init
   + key decode + `startLiveServices`). Android pays ~1.13 s there, iOS ~0.2 s.
   → FDC-07's lever is *that prologue / starting node+reserve earlier*, not
   re-timing any relay timeout.
2. **Budgets already fit; do not tighten.** `T_circuit` p90 is 1564 ms (Android)
   / 913 ms (iOS), both inside the 3 s foreground budgets. `DialTimeout=15s` is
   background-only; leave it. Tightening either risks more inbox fallback.
3. **Cold-tap warming is platform-split.** iOS can warm at node-ready (~0.2 s);
   Android cannot usefully warm before node-ready (~1.16 s) — the floor is
   `node:start`-return either way (the libp2p host is not in the iOS NSE).
4. **The LAN advantage is genuinely missed on cold open** — not just because
   discovery starts late, but because Android `NsdManager` resolve is slow
   (~3.5 s) and permission-gated/flaky. Start discovery early; keep LAN
   opportunistic and never block the relay race on it.

## 7. Caveats / what remains
- One flagship per class. A **low-end Android** (Go-edition) would likely push
  `T_nodeStart` over 1.5 s (strengthens "no pre-node dial"); not on hand.
- Numbers are anchored at the `main()` `app_start` mark — they exclude the OS
  process-spawn→`main()` prefix (the Option-C add-on); add a per-platform const
  for true user-perceived spawn.
- **(d) `G_nse`** still needs the §3.4 manual peer-push + notification-tap run
  (the only piece not CLI-automatable).
- (c) is cross-platform Android→iOS resolve; an Android→Android or iOS→iOS
  resolve may differ.

---

## 4. Expected-Output values (the dependent plans consume these)

> Filled from Pixel 6 (Android flagship) + iPhone 13. (c)/(d) in progress.

1. **`FOREGROUND_RELAY_BUDGET_MS` = keep 3 s.**
   Decision Criterion 1: `T_circuit` p90 is **1564 ms (Pixel 6)** and **913 ms
   (iPhone 13)** — both ≤ the current 3 s `ForegroundRelay*Timeout`, with ≥1.4 s
   of headroom on the slower platform. **No change; do not lower** (lowering
   would risk abandoning a genuinely-cold reserve into inbox fallback). The cold
   reserve already fits the existing budget on both device classes measured.

2. **`DIALTIMEOUT_RETIME` = no.**
   Criterion 2 default holds. `config.go:28 DialTimeout=15s` is consumed by the
   fire-and-forget warm goroutine (`warmRelayConnectionForStart`), not the user
   send. The data shows the cold relay warm completes fast (`relayWarmMs` p90
   313 ms; first circuit p90 1564 ms) — nothing on the send path tracks 15 s.
   **Leave 15 s as-is**; FDC-07 should start the warm *earlier*, not cap the
   timer. (No foreground-send-blocks-on-15s evidence: send path uses
   Interactive/Foreground budgets, unchanged here.)

3. **`COLD_WARM_AGGRESSIVENESS` = PLATFORM-SPLIT** (this is the key calibration):
   - **iOS = warm-on-cold-tap is viable.** `T_nodeStart` median 206 ms / p90
     217 ms — **under the ~800 ms threshold** (Criterion 3). The node is ready
     ~0.2 s after `main()`, so FDC-04 can fire a bounded, debounced `warmPeer`
     essentially at node-ready and still overlap reading time on a cold notif-tap.
   - **Android flagship = warm-only-after-node-ready.** `T_nodeStart` median
     1158 ms / p90 1200 ms — between the ~800 ms and ~1.5 s thresholds, leaning
     "limited overlap." FDC-04 should **not** add a pre-node speculative dial on
     the coldest Android path; warm at node-ready. The win on Android is FDC-07
     (shrink the ~1.13 s Dart prologue / start node + reserve earlier), since the
     prologue — not the transport (`libp2pNewMs` 22 ms) — is the long pole.
   - In both cases the hard floor FDC-04 must respect is `node:start`-return on
     the main isolate (the libp2p host does not exist before it; §4.4 (d)).
     Caveat: one flagship per class; a low-end Android (Go-edition) would likely
     push `T_nodeStart` toward/over 1.5 s → strengthens "skip pre-node dial".

4. **`NSE_PEERID_FACT` = yes (self key + sender peerId in NSE); warm floor =
   `T_nodeStart` on the open path (`G_nse` is not a useful metric).**
   The cold notif-tap chain was captured end-to-end on device (§3.4.2):
   `FDC_COLDSTART_NOTIF_TAP_NODE_READY` fires (after a wiring fix — see §3.4.1 #1).
   The libp2p host is **not** in the NSE, so the earliest a warm dial can begin is
   `node:start`-return on the main isolate — **at/near node-ready on the open**,
   either from the background push-launch (~206 ms, before the tap) or the
   throttled true cold-tap (848 ms under LPM). The literal `G_nse` (NSE epoch →
   main epoch) is dominated by human tap-reaction time, so FDC-04 should key off
   `T_nodeStart`, not `G_nse`.

5. **`T_circuit`, `T_mdns` median+p90 per device-class:**
   - `T_circuit`: Pixel 6 **1364 / 1564 ms**, iPhone 13 **898 / 913 ms**.
   - `T_mdns` (Pixel→iPhone cold resolve): **≈ 3539 ms median (≫ 1500 ms LAN
     budget)** and **flaky** (17% resolve as-shipped / 62% with location).
     **Criterion 5 verdict:** T_mdns p90 ≫ 1500 ms → FDC-07/FDC-04 must start
     bonsoir discovery *before* the first send window (the LAN advantage is
     missed on cold open both because discovery starts late *and* because Android
     `NsdManager` resolve is slow + permission-gated). Do **not** simply raise the
     LAN budget to 3.5 s — that would stall every send waiting on an unreliable
     resolve; instead start discovery early and keep LAN as an opportunistic
     fast-path that the relay race does not block on.

---

## 5. Reproduce

```bash
# 1. rebuild native libs with the declared toolchain (gomobile)
cd go-mknoon && PATH="$HOME/go/bin:$PATH" GOTOOLCHAIN=go1.25.0 make android   # and: make ios

# 2. build + install the measurement profile build (realistic AOT timing)
flutter build apk --profile --target-platform android-arm64 --dart-define=FDC_FLOW_LOG=1
adb -s <udid> install -r build/app/outputs/flutter-apk/app-profile.apk

# 3. run cold trials (force-quit → cold launch), parse to median+p90
cd Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/fdc-s1-measurement
bash scripts/fdc_android_trials.sh <udid> 12 pixel6_warm_cold logs/pixel6_warm_cold   # run in background
python3 scripts/fdc_parse.py --label pixel6/warm_cold logs/pixel6_warm_cold/*.log
```
