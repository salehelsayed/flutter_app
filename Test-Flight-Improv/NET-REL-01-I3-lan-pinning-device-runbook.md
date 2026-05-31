# NET-REL-01 I3 — Same-WiFi LAN-Pinning Device-Run Runbook

> Status: **device-validation gate.** The NET-REL-01 LAN code (TTL, discover-on-send,
> P3 media, P4 telemetry) is implemented and host-green; this run is the one proof a
> host test structurally **cannot** give — that a real same-WiFi message took the
> `local`/LAN path end-to-end over real mDNS, **not** relay. Do NOT skip and do NOT
> substitute a simulator (sims share the host mDNS stack and force
> `DISABLE_LOCAL_DISCOVERY=true`, so they cannot produce `local`).

---

## 1. Goal

Prove acceptance criterion **NET-REL-01 #1** on hardware: when two real devices are on
the same WiFi with the app foregrounded, the first message between them uses the
**LAN path** within the discovery window, **path-pinned** (NET-REL-06 doctrine — assert
the *specific* transport, never the `{direct, relay, inbox}` set), with a **negative
control** that proves the label isn't defaulted.

Source: `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md` (Test Plan I3
+ I3 negative control). Doctrine: `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`.

---

## 2. What this proves (and what it does NOT)

### Proves
- A real same-WiFi 1:1 send was carried by the LAN transport (real Bonsoir/mDNS resolve
  → real `LocalWsServer` socket), surfaced as the receiver's `local`/`wifi` transport,
  and the NET-REL-04 census `wifi` bucket moved.
- The negative control proves the label is real: with the LAN path blocked (relay
  reachable), the same scenario does **not** report `local`.

### Does NOT prove
- Cross-network / CGNAT behavior (that is NET-REL-08 territory; relay is the steady state
  there per the closed NET-REL-02 gate).
- Media at scale or under loss — this runbook pins the **text** LAN path first; the P3
  local-media path is an optional add-on (§7).
- Anything on a **release/TestFlight** build — the diagnostics card is `kDebugMode`-gated
  and `baselineReport()` is never logged on release. **Use a debug build.**

---

## 3. Prerequisites (hard constraints)

1. **Two real physical devices on the SAME WiFi.** iOS↔iOS is the canonical pair (the
   doc/cap targets iOS Local Network). iOS↔Android is acceptable if both run debug builds
   with discovery on. Known device IDs (project memory): iPhone13 `00008110-...`,
   Pixel6 `21071FDF600CSC`. (Note the iPhone13 iOS-signing blocker — resolve signing or
   use a second provisioned iOS device.)
2. **Debug build** (`kDebugMode == true`) so the Transport Diagnostics card is visible.
3. **Local discovery ENABLED** — do **NOT** pass `DISABLE_LOCAL_DISCOVERY=true`. Verify
   in the LAN snapshot (`baselineReport()` shows "discovery active, N peers").
4. **iOS Local Network permission ALLOWED** on both devices (first-launch prompt). A
   denied prompt is a silent LAN outage — if denied, the P4 `suspected-denied` row should
   appear; reset via Settings → Privacy → Local Network.
5. **Relay reachable** throughout (so "LAN beat relay" is a real race, not "relay was
   down"). Confirm relay liveness independently.
6. Go built before the Flutter run (Flutter does NOT rebuild Go):
   `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install`.

---

## 4. Build & run commands

```sh
# 0. (once) rebuild Go + pods so native LAN/relay code is current
cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install && cd ..

# 1. Device A (debug, discovery ON — do NOT set DISABLE_LOCAL_DISCOVERY)
flutter run --debug -d <DEVICE_A_ID>

# 2. Device B (separate terminal)
flutter run --debug -d <DEVICE_B_ID>
```

Both devices must be on the same WiFi, app foregrounded, and already paired as contacts
(complete a contact exchange first so a 1:1 conversation exists).

---

## 5. Procedure

### Step 0 — Confirm the LAN is live
On each device: Settings → **Transport Diagnostics** → **Refresh** → confirm
`LAN: discovery active, ≥1 peers`. If `0 peers` after ~12 s, the P4 `suspected-denied`
heuristic may fire — check Local Network permission before continuing.

### Step 1 — Cold first-message (the I3 happy path)
1. Foreground both apps fresh (cold-ish — the point of discover-on-send is the
   not-yet-resolved window).
2. From **Device A**, send the **first** 1:1 text message to Device B.
3. On **Device B** (receiver): Settings → Transport Diagnostics → **Refresh** → copy
   `baselineReport()`. Record the per-message transport for the received message.
4. Repeat for **N ≥ 20** distinct first-messages (re-foreground / new conversation
   threads to re-exercise the cold window), summing the `wifi` count.

### Step 2 — Negative control (LAN blocked, relay reachable)
1. Block the LAN path while keeping relay reachable. Options, in order of preference:
   - Put the two devices on **different networks** (e.g. Device B on cellular, Device A
     on WiFi) so mDNS cannot resolve but relay still routes; OR
   - Disable WiFi multicast / put devices on an **AP-isolation** ("guest") WiFi that
     blocks mDNS between clients; OR
   - Toggle a debug build variant with `DISABLE_LOCAL_DISCOVERY=true` on the receiver.
2. Send N ≥ 10 messages. Capture the receiver `baselineReport()`.

---

## 6. Pass criteria (path-pinned) + negative control

**HAPPY (Step 1) — ALL must hold:**
- The received message's stored transport is the **LAN path** — `transport == 'local'`
  (per-message) and the census **`wifi` bucket increments** by the number of LAN sends.
  Pin the *specific* value — **do NOT** accept `direct`/`relay`/`inbox`.
- `relay`/`inbox` buckets do **not** increment for those sends (the LAN path won, relay
  was not silently used).
- Corroborate with FLOW logs on the receiver: a LAN/`local` receive event fired (not a
  relay `message:received`).

**NEGATIVE CONTROL (Step 2) — must hold, else the happy pass is meaningless:**
- With the LAN path blocked (relay reachable), the same scenario reports
  `transport != 'local'` (it is `direct`/`relay`/`inbox`) and the `wifi` bucket does
  **not** move. If BOTH the happy run and this control report `local`, the assertion is
  defaulted/hard-coded — **fail the run.**

**N:** ≥ 20 LAN first-messages (happy) and ≥ 10 (control). Below N=20, report **raw
counts only**, never percentages (per the baseline-runbook N discipline).

---

## 7. Optional add-on — P3 local-media over LAN

If validating media too: with both devices on WiFi (discovery on), send an **image** or
**voice note** A→B and confirm on B the FLOW sequence
`LOCAL_MEDIA_OFFER_SENT → … → LOCAL_MEDIA_RECEIVE_ATTACHMENT_LINKED` (the
`linkIncomingLocalMedia` use-case path), and that the attachment opens from the
LAN-persisted file. Negative control: same send with the media server unreachable →
falls back to relay-CDN (no `ATTACHMENT_LINKED`), attachment still arrives. (P3 host
coverage is already mutation-pinned; this is the device E2E.)

---

## 8. Results template

```
NET-REL-01 I3 — LAN PINNING RESULTS
===================================
Date: ____   Devices: A=____ (OS/net) , B=____ (OS/net)
Build: debug   Local discovery enabled: YES   Relay reachable: YES
iOS Local Network permission allowed (A/B): ___ / ___

HAPPY (same WiFi, cold first-message):
  N (LAN first-messages sent): ____
  Receiver per-message transport == 'local'?            ____ / ____  (must be all)
  Census wifi bucket delta (receiver):                  +____
  relay bucket delta during LAN sends:                  +____  (expect 0)
  inbox bucket delta during LAN sends:                  +____  (expect 0)
  FLOW: local receive event observed (not relay)?       YES / NO

NEGATIVE CONTROL (LAN blocked, relay reachable):
  N: ____   transport != 'local' for all?               YES / NO  (must be YES)
  wifi bucket moved?                                     YES / NO  (must be NO)

VERDICT: PASS / FAIL   (PASS requires happy all-'local' + control all-not-'local')
Notes / anomalies: __________________________________________________
```

## 8b. Recorded run — 2026-05-31 (executor; verdict deferred to monitor)

Real devices: **iPhone 13** (`00008110`, iOS 26.4.2) + **Pixel 6** (`21071FDF600CSC`,
Android 16), **same WiFi** (192.168.0.x), **debug** builds (commit `fb1bcca2` — adds the
greppable `MSG_RECEIVED_TRANSPORT` log), **discovery ON**, iOS **Local Network permission
ALLOWED**. Read via the **Pixel** (`adb logcat`); the iPhone was launched by tap (logs not
piped), so the Pixel was the readable endpoint.

**KEY FINDING (refines the strict `wifi`-only criterion):** on the same physical LAN,
libp2p **also** forms a direct connection over the LAN, and once warm it **wins the send
race** vs the WS path. So same-WiFi delivery is **non-relay** but split between `local`/
`wifi` (WS) and `direct` (libp2p-over-LAN); a clean N≥20 `wifi`-only run is **not
achievable** without disabling the direct leg. Send- and receive-side labels can also
**diverge** (sender logs `local`, receiver logs `direct`) — both legs fire in parallel and
the receiver dedups to whichever arrives first.

```
HAPPY (same WiFi) — LAN path demonstrably used, 0 relay:
  Pixel SEND-side via "local":      3/3  (f63d5dc0,d1edd8ef,1a508f53; proofSource=chat_send_local, sendPath=local/reuse)
  Pixel RECV-side transport "wifi": observed (13:58:43, with LOCAL_WS_MESSAGE_RECEIVED = real WebSocket)
  Warm RECV-side transport:         "direct" (libp2p-over-LAN, non-relay)  [3 warm sends]
  relay during same-WiFi sends:     0
  FLOW: local WS receive event (not relay)?  YES (LOCAL_WS_MESSAGE_RECEIVED)

NEGATIVE CONTROL (Android on cellular = LAN blocked, relay reachable):
  transport != local/wifi for all?  YES — local path reported local_not_discovered, delivery via "relay"
    1st send: CHAT_MSG_SEND_RACE_ALL_FAILED reason=local_not_discovered (transition failure → retry)
    retry:    CHAT_MSG_SEND_SUCCESS via "relay" x2 (c8e92321, 7bfc3cf2)
  local/wifi transport during LAN-blocked?  NO
```

**VERDICT (executor read; monitor decides):** **PASS** under the accepted *"same-WiFi =
non-relay LAN"* framing — the local/WiFi (WS) transport is path-pinned-proven on **both**
send (`via:local`) and receive (`transport:wifi` + `LOCAL_WS_MESSAGE_RECEIVED`) on the same
WiFi, and blocking the LAN forces **relay** (path-pinned negative control). **Not** a strict
`wifi`-only-N≥20 pass (direct-over-LAN dominates warm — recorded as the finding). Fidelity:
**real device, real WiFi, real relay.**

**Deploy notes (for the next runner):** iPhone debug deploy was flaky — needed `flutter
clean` (+ DerivedData wipe) for a stale-simulator-native-assets `EXC_BAD_ACCESS` crash, then
an **iPhone reboot** to clear a hung debug-VM-service connection; first launch required
granting the **Local Network** prompt. Android logs benign `failed to resolve local
interface addresses (permission denied)` warnings on cellular.

---

## 9. Trust caveats (doctrine)

- **Path-pin, never set-accept.** The existing E2E tests accept `{direct,relay,inbox}` to
  dodge flake; that is a false positive for "took the fast path." This run must assert the
  *specific* `local` value (NET-REL-06 §2 default-bias / set-acceptance guards).
- **`wifi` zero is "not measured," not "LAN unused"** — only credible on a real-device,
  discovery-enabled debug build. A simulator or a `DISABLE_LOCAL_DISCOVERY=true` build
  cannot fill it.
- **Census is session-scoped / per-launch.** Capture `baselineReport()` before any kill;
  sum raw counts across launches, recompute percentages (do not average per-session %).
- **Relay must be up during the happy run** or "LAN beat relay" is unproven (it might have
  been "relay was unavailable").
