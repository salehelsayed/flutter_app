# 183 — Active-chat keepalive: two-phone device-proof runsheet

Status: **PASS (2026-07-01)** — both TC-183-50 + TC-183-51 device-proven on
Pixel 6 → iPhone 11 (see Result log). Cold-start-arming gap found + fixed +
device-re-verified the same day.

Spec: `Test-Flight-Improv/183-active-chat-keepalive-foreground-peer-liveness-spec.md`
Plan: `Test-Flight-Improv/183-active-chat-keepalive-foreground-peer-liveness-tdd-plan.md`

> The host floor proves the whole loop with a faked `PeerLivenessProbe` + fakeAsync
> (arm/cancel/cadence/M-miss→reuse/gate/non-load-bearing/churn/resume). What ONLY a
> device can prove: the new gomobile `peer:ping` binding actually resolves on the
> handset, `ping.Ping` round-trips a real peer, and a real peer drop is detected in
> ~seconds → re-dial → the next send stays on the warm path.

## Build (needs the new gomobile symbols — `BridgePeerPing` / `GoMknoon.peerPing`)

The prebuilt `ios/Runner/GoMknoon.xcframework` + Android `.aar` do NOT yet contain
`PeerPing`; rebuild the bindings first, then build the apps:

```bash
# 1. Regenerate gomobile bindings (adds the new exported bridge.PeerPing).
cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" GOTOOLCHAIN=go1.25.0 make all
cd ../ios && pod install && cd ..
# (verify the symbol landed)
cd go-mknoon && make verify-bindings ; cd ..

# 2. Profile builds with flow logging on (so KEEPALIVE_PEER_DROP / peer:ping land in logs).
flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true
flutter build ios --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true
```

## Rig

- Pixel 6 (Alice): `adb -s 21071FDF600CSC logcat | grep -E 'FLOW|PEER_PING|KEEPALIVE|WARM_PEER|INBOX_DRAIN'`
- iPhone 11 (Bob): `idevicesyslog -u 00008030-001A6D2801BB802E | grep -E 'FLOW|PEER_PING|KEEPALIVE|WARM_PEER|INBOX_DRAIN'`
- Both signed into accounts that are mutual 1:1 contacts; same warmed conversation.
- Actual per-tick events on the SENDER (grep anchors, verified in code):
  `P2P_SERVICE_PEER_PING_BEGIN` → `P2P_SERVICE_PEER_PING_SUCCESS` (reachable) /
  `P2P_SERVICE_PEER_PING_FAILED` (miss) every ≈8 s; on 2 consecutive misses (≈16 s)
  `KEEPALIVE_PEER_DROP{peerId}` → `P2P_SERVICE_WARM_PEER_*` re-dial → `..._INBOX_DRAIN*`.

## TC-183-50 (PROD-CRITICAL) — drop detected in seconds → re-dial → next send fast

1. Open the SAME 1:1 chat on both phones, both foreground. Exchange one message each
   way to confirm the warm/direct path (look for the upgraded/direct transport glyph,
   and `peer:ping` ticks appearing on the SENDER ≈ every 8 s).
2. On the SENDER (Alice), confirm steady-state: a `peer:ping` ≈ every 8 s and NO
   `KEEPALIVE_PEER_DROP` while Bob stays reachable.
3. Force ONLY THE PEER's (Bob's) connection to drop WITHOUT touching Alice's network:
   background Bob, OR turn Bob's WiFi off (leave Alice fully online).
4. **Expected on Alice within ≈ `kKeepAliveMissThreshold` × 8 s (≈16 s):**
   - `KEEPALIVE_PEER_DROP` fires, `details.peerId` = Bob's (short) id.
   - a `warmPeer` re-dial for Bob (`P2P_SERVICE_WARM_PEER_*`).
   - a `drainOfflineInbox` (`P2P_SERVICE_INBOX_DRAIN*` / coalesced with any 182 drain).
5. Immediately send a message from Alice → it must take the warm/recovering path, NOT
   sit on the ~30 s-lagged cold-dial/relay fallback that HEAD exhibits.
6. **Contrast run (same build, keepalive disabled):** repeat steps 1–5 with the loop
   off (e.g. comment the `_keepAliveUseCase.onForegrounded()` wire, or background the
   chat so the loop never arms) and observe the ~30 s lag before the drop is noticed —
   the delta IS the feature.

PASS = the drop is surfaced in ≈seconds (not ~30 s) and the post-drop send stays warm.

## TC-183-51 — bounded cadence + ZERO background pings (battery)

1. Keep the 1:1 chat open + foreground for several minutes. Count `peer:ping` events:
   `count ≈ elapsed / 8 s` (bounded — NOT a tight radio loop).
2. Background the app (home button). **Expect ZERO `peer:ping` while suspended**
   (`onBackgrounded()` cancelled the timer).
3. Foreground again → pings resume (`onForegrounded()` re-armed).

PASS = cadence ≈ elapsed/8 s in foreground; exactly zero `peer:ping` while backgrounded.

> Do NOT flip any feature-flag default ON for this proof. No DB migration is involved.

## Result log

| Date | Tester | TC-183-50 | TC-183-51 | Build SHA | Notes |
|---|---|---|---|---|---|
| 2026-07-01 | Saleh (Pixel 6→iPhone 11) | **PASS** | **PASS** | `3fad4333` + gomobile rebuild | see below |
| 2026-07-01 (re-measure) | Saleh (Pixel 6→iPhone 11) | **PASS** | **PASS** | HEAD `6d7ec800` + 185 working-tree, same gomobile | fuller metrics below |

### 2026-07-01 device-proof — BOTH cases PASS

Build: HEAD `3fad4333`, gomobile bindings rebuilt (`BridgePeerPing` verified in the
iOS xcframework + Android `.aar`), profile builds with `FDC_FLOW_LOG=1` +
`MKNOON_ENABLE_NATIVE_MDNS=true`. Alice = Pixel 6, Bob = iPhone 11.

**TC-183-50 (drop → re-dial → warm) — PASS.** The device-only legs all confirmed:
- Real `peer:ping` binding resolves; `ping.Ping` round-trips a real peer (first
  RTT 189 ms). Steady 8 s cadence, 14 consecutive `PEER_PING_SUCCESS` while Bob
  reachable — **zero false positives**.
- Bob's WiFi off → after Bob actually went dark, 2 consecutive
  `PEER_PING_FAILED` → `KEEPALIVE_PEER_DROP{12D3KooWRv}` at exactly the 2×8 s
  threshold. `WARM_PEER_BEGIN` fired **+1 ms** after the drop, `DRAIN_OFFLINE_INBOX_BEGIN`
  +121 ms — REUSING warmPeer + drainOfflineInbox, once. The `_dropHandled` latch
  held (continued misses, NO repeat drop/re-dial — no spam).
- Post-drop send: press → durable inbox custody in **1.9 s** (`RACE_ALL_FAILED`
  1.74 s → `INBOX_STORE_SUCCESS`), NOT the ~30 s cold-poll lag. On Bob's WiFi
  restore, pings recovered to `SUCCESS` (latch reset) and the queued message
  delivered (`DELIVERY_RECEIPT_APPLIED`).

**TC-183-51 (battery) — PASS.** 8 s foreground cadence; **0** `peer:ping` across a
34 s background window (`onBackgrounded()` cancelled the timer); pings resumed on
foreground (`onForegrounded()` re-armed).

### 2026-07-01 RE-MEASUREMENT — both cases PASS (fuller metrics, current build)

Re-run on the current working tree (HEAD `6d7ec800` + the 185 offline-send changes,
same gomobile bindings), `FDC_FLOW_LOG=1` + `MKNOON_ENABLE_NATIVE_MDNS=true`. All
metrics parsed from each flow event's own ms-precision `ts`. Session: 87 pings ·
61 SUCCESS · 26 FAILED (all during the deliberate outage) · **1 DROP** · 1 receipt.

**TC-183-51 (cadence + battery) — PASS.**
- Cadence `BEGIN→BEGIN` p50 **8002 ms** (5-min clean window: min 7927 / p50 7998 /
  mean 8000 / max 8067). Rock-solid 8 s.
- RTT — real libp2p `P2P_PEER_PING_RESPONSE.rttMs`, n=61: min 14 / **p50 112** /
  mean 131 / max 284 ms (warm-window subset p50 ~82 ms).
- Battery: **0** pings across a **73 s** background window (would have held ~9);
  `onBackgrounded()` cancels the timer.
- Scope: the keepalive is correctly ACTIVE-CHAT-SCOPED — during a ~12-min stretch
  on the Feed (non-1:1 active surface) it was silent (correct: `_activePeerId()`
  null → `_tick` early-returns, no `PING_BEGIN`), and it resumed within one
  interval on re-entering the 1:1 chat. (A mid-run "resume didn't re-arm" alarm was
  a false positive — the app was simply on the Feed, not the chat.)

**TC-183-50 (drop → re-dial → warm → recover) — PASS.**
- Drop fires on the **2nd consecutive miss** (2×8 s); each dark-peer ping consumed
  the full 4 s timeout.
- `KEEPALIVE_PEER_DROP` → `WARM_PEER_BEGIN` **+0 ms**, → `DRAIN_OFFLINE_INBOX_BEGIN`
  **+137 ms** (reuses warmPeer + drain, once).
- Latch: **1** drop across ~13 continuous failed pings — zero re-dial spam.
- Post-drop send (peer dark): press `CONV_FL_SEND_PRESSED` → durable relay custody
  `CHAT_MSG_SEND_CUSTODY_CONFIRMED` in **178.7 ms** (concurrent inbox, FDC-03),
  resolved `CHAT_MSG_SEND_SUCCESS`; the doomed direct dial failed fast
  (`DIAL_PEER_ERROR` ~1.5 s) WITHOUT blocking custody. Not the ~30 s cold-poll lag.
- Recovery: on Bob's WiFi restore the queued message delivered
  (`DELIVERY_RECEIPT_APPLIED`) and pings reset to `SUCCESS` (latch reset).

> Non-obvious for future work: the send at drop-time still spent ~1.5 s on the
> direct dial even though the keepalive had known the peer was dropped for ~87 s —
> i.e. the 183 liveness signal is NOT (yet) consulted by the send race. Custody was
> already concurrent at 179 ms, so this is a wasted-background-dial (battery)
> inefficiency, not a user-visible latency one.

### Finding + fix: cold-start arming (FIXED same day, device-verified)

The keepalive (and the 181 presence heartbeat) armed ONLY in `_onResumed()`.
Flutter delivers no initial `resumed` transition on a cold launch, so after
tapping the icon and opening a chat the loop stayed **dormant until the first
background→foreground cycle** — during the proof the first `peer:ping` did not
fire until Alice was cycled. Fixed by arming both foreground timers from
`initState` (post-frame, guarded on `lifecycleState == resumed`); locked by
`main_keepalive_wiring_test.dart` **TC-183-52**. Re-verified on device: a
force-stopped cold launch + open-chat produced steady 8 s pings with
**`_onResumed()` count = 0** (no cycle needed).
