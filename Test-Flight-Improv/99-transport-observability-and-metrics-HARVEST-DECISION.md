# NET-REL-04 Transport Observability & Metrics — Harvest + Decision

**Date:** 2026-05-29 (updated 2026-05-30 with a live two-phone same-LAN run)
**Tracking ID:** NET-REL-04 (TOM-001..005 rollout)
**Step:** DECISION (host evidence + real physical-device evidence harvested)
**Verdict:** `closed_with_residual` — 4 of 5 NET-REL-04 acceptance criteria met (AC4 descoped by design); LAN residual **`discharged`** as of the 2026-05-30 two-phone same-LAN run (see §5b/§6).

> **2026-05-30 update (headline):** A live two-phone same-Wi-Fi run (physical iPhone 13 ↔ physical Pixel 6, real
> identities, connected as contacts) produced the evidence the simulator structurally cannot: real mDNS discovery
> + a real same-LAN message exchange delivered over **non-relay** transports — genuine **`wifi`** (iPhone→Android,
> LocalWsServer over the LAN) and **`direct`** (Android→iPhone, direct libp2p stream over the LAN) — with the relay
> online but **never used** (zero `relay`, zero `inbox` for the live messages). This discharges the LAN residual.
> The run also surfaced and FIXED a real production bug: the Transport Diagnostics card was unreachable after
> onboarding/QR-connect because `transportMetrics` was not threaded through FTE / QRScanner / Orbit `FeedWired`
> construction sites (see §5c). On-device card read is now CONFIRMED on BOTH phones after a clean fresh round:
> iPhone card `direct 4 / wifi 3`, Android card `direct 6 / wifi 1`, **`relay 0` and `inbox 0` on both** —
> corroborated by FLOW logs (iPhone sent 3× `local`/wifi, Pixel sent 3× `direct`, zero `transport:"relay"`
> anywhere). Acceptance criteria #1 (read on-device) and #5 (baseline mix) are met on real hardware, both platforms.

---

## 1. As-Built Contract (Summary)

The landed implementation is an **on-device, session-scoped, aggregate-only** transport
census + the pre-existing relay Prometheus suite.

- **Buckets:** `direct`, `relay`, `wifi`, `inbox`, `unknown` (kTransportBuckets order).
- **Fallback rungs:** `reuse`, `local_race`, `direct_race`, `relay_probe`, `inbox_fallback`, `failed`.
- **Send-attempt legs:** `reuse`, `local`, `direct`, `relay_probe`, `inbox` (distinct vocabulary from rungs).
- **LAN snapshot fields:** `discoveryActive (bool)`, `discoveredPeerCount (int)`,
  `suspectedPermissionDenied (bool, default false; heuristic only — true after zero peers for >=12s while
  discovery active; never authoritative, no iOS permission API)`.
- **Baseline report:** single multi-line string, aggregate-only, no identifiers, exactly 5 lines:
  1. `Transport mix (N=$n): ...` integer percentages per bucket, normalized to sum to exactly 100 (floor each,
     remainder to largest-count bucket); `N=0` → `no data`.
  2. `Median latency: direct 120ms, relay -, wifi 5ms, ...` (`-` when no samples).
  3. `Fallback rungs: reuse 4, local_race 1, ...` count per rung.
  4. `Send attempts (tried/failed): reuse 4/0, local 3/2, ...` per leg.
  5. `LAN: discovery active, 2 peers` (+ optional `, perm: suspected-denied`).

- **Bias fix (CONFIRMED):** receive path (`p2p_service_impl.dart` ~173-178) resolves
  `msg.transport ?? _inferTransportForPeer(msg.from) ?? 'unknown'`. `_inferTransportForPeer` returns `relay` ONLY
  when a matching connection's multiaddr contains `/p2p-circuit`, `direct` for a non-empty non-circuit multiaddr,
  else `null` → falls through to `'unknown'`. The old default-to-`'relay'` bias is **replaced with `'unknown'`**.
  Local WiFi inbound paths record `'wifi'` explicitly.
- **Canonicalization:** `'local'→'wifi'`, `'reuse'→'direct'`, others/`null` → `'unknown'`.
- **Privacy:** in-memory, session-scoped, aggregate integer counts + bounded int latency samples (ring buffer,
  256/transport) + `(bool,int)` LAN snapshot only. No peer IDs / content / conversation IDs / timestamps.
  `textPreview` confirmed removed from all send-path FLOW events.
- **On-device readout:** debug-builds-only card "TRANSPORT DIAGNOSTICS (SESSION)" reached via Feed → tap own
  RingAvatar → Settings → bottom debug section. Shows mix, rungs, latency (median/p95), LAN, and a copyable
  Baseline report (`SelectableText`, key `settings-transport-debug-report`).

---

## 2. Acceptance Criteria by Evidence

| AC | Criterion | Met | Evidence |
|----|-----------|-----|----------|
| **AC1** | Developer can read on-device session transport mix + fallback-rung distribution + median send latency per transport. | **true (logic) / device-confirmed mechanism only** | HOST PASS: `test/core/debug/transport_metrics_test.dart` (+24) — exact-count census, rung distribution, bucketed median/p95, baseline report. HOST PASS: `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` (+2) — renders "TRANSPORT DIAGNOSTICS (SESSION)", mix/rungs/latency/LAN, refresh. Production wiring `p2p_service_impl.dart:213-519`. Caveat: a developer physically reading the card on a real device/TestFlight is host-only — the render test proves composition, not a real-device read. (Both physical devices now build & run, but the debug card was not manually read in the automated integration runs; that read is part of the §7 manual procedure.) |
| **AC2** | Relay exposes aggregate circuit/inbox load gauges in Grafana (largely already met); only addition = privacy-safe 1:1-vs-group circuit classification. | **true (for the "largely already met" gauges)** | GO PASS: `go-relay-server/metrics_test.go` — `TestRelayMetricsDeltas` asserts +1 deltas on `inboxStoredCounter`, `inboxMessagesPending`, `activeStreams.WithLabelValues(proto)`, `streamErrorsCounter`, `streamDuration`; `TestRelayMetricsHandlerScrapeContract` serves `/metrics`, asserts presence of `relay_inbox_stored_total`/`relay_active_streams`/`relay_stream_duration_seconds_count` and asserts NO leakage (`12D3Koo`, `/p2p/`, `messageBody`, `conversationId`). Full `go test ./...` green (9.255s). The 1:1-vs-group classification is **explicitly out of scope** and the closure doc does not claim it shipped. |
| **AC3** | Transport label no longer silently defaults to relay; unknown distinguishable from relay. | **true** | HOST PASS: `test/core/services/p2p_service_inbound_transport_test.dart` (+6) drives the REAL `P2PServiceImpl` receive path: T1 (core) null + peer-not-connected → `'unknown'` (`isNot('relay')`), census `unknown==1`/`relay==0`; T2 explicit `'relay'` stays `'relay'`; T3 live circuit → inferred `'relay'`; T4 live non-circuit → `'direct'`; T5 local WiFi → `'wifi'`. HOST PASS: `transport_metrics_test.dart` "null and unrecognized → unknown only". Bias fix confirmed in as-built contract. |
| **AC4** | Hole-punch attempts/outcomes are countable (enables NET-REL-02/03). | **false (descoped by design)** | NOT addressed by this rollout. `99-...-metrics.md` §5 Non-goals: "Out of scope: relay 1:1-vs-group classification, opt-in aggregate collectors, and hole-punch counters." §7 residuals repeats hole-punch out of scope. No hole-punch counter or test was landed and none claimed. NET-REL-04 is therefore 4-of-5; the closure doc's "closed" refers to the narrower TOM-scoped contract. Honest descope, not oversight. |
| **AC5** | Produce baseline report: "X% direct, Y% relay, Z% wifi, W% inbox; median latency per transport." | **true (composition) / wifi-share needs device** | HOST PASS: `transport_metrics_test.dart` baseline group — percentages sum to 100 (50/30/10/0/10, regex sum==100), `N=0` → no data, includes rung counts + LAN line + send-attempt line. HOST PASS: `transport_metrics_privacy_test.dart` (+5) PR1b — report + getters aggregate-only (no peer IDs / `/p2p-circuit` / `/ip4/` / content), contains "Transport mix" / "Median latency" / "Fallback rungs" / "LAN: discovery active, 2 peers". HOST PASS: `p2p_service_lan_availability_test.dart` (+4) — report has LAN line, no peer IDs/hosts/ports. Caveat: the **real-world wifi share / LAN fraction** the report would show is host-only-needs-device — standard simulators cannot produce true LAN discovery or WiFi transport. |

**Score: 4 of 5 met (AC1, AC2, AC3, AC5). AC4 not met — explicitly descoped.**

---

## 3. Host Dart Test Results

| Command | Passed | Summary |
|---|---|---|
| `flutter test test/core/debug/transport_metrics_test.dart` | ✅ | All passed (+24) |
| `flutter test test/core/debug/transport_metrics_privacy_test.dart` | ✅ | All passed (+5) |
| `flutter test test/core/utils/flow_event_emitter_test.dart` | ✅ | All passed (+8) |
| `flutter test test/core/services/p2p_service_inbound_transport_test.dart` | ✅ | All passed (+6) |
| `flutter test test/core/services/p2p_service_transport_census_test.dart` | ❌ | **Compilation failed** — `_CensusFakeP2PService` missing `discoverLocalPeer` + `incomingLocalMediaStream`. No assertions ran. |
| `flutter test test/core/services/p2p_service_transport_latency_test.dart` | ✅ | All passed (+6) |
| `flutter test test/core/services/p2p_service_lan_availability_test.dart` | ✅ | All passed (+4) |
| `flutter test .../settings_transport_diagnostics_card_test.dart` | ✅ | All passed (+2) |
| `flutter test .../send_chat_message_use_case_test.dart` | ✅ | All passed (+73) |
| `flutter test .../send_group_message_use_case_test.dart` (fanout-without-identity) | ✅ | All passed (+1) |

**Not all green.** One stale test file (`p2p_service_transport_census_test.dart`) fails to **compile** because its in-file `_CensusFakeP2PService` does not implement the newer `P2PService` members (`discoverLocalPeer` at `p2p_service.dart:182`, `incomingLocalMediaStream` at `:59`). This is a test-maintenance staleness, NOT a logic regression: the census logic it would have covered is independently and exactly pinned by `transport_metrics_test.dart` (exact-count census) and `p2p_service_inbound_transport_test.dart` (real receive-path unknown-vs-relay). **Follow-up:** update the fake to satisfy the current interface so the census file compiles and runs.

---

## 4. Go Relay Test Results

| Command | Passed | Summary |
|---|---|---|
| `go test ./...` (go-relay-server) | ✅ | Full suite passed: `ok github.com/mknoon/relay-server 9.255s` |
| `go test -run Metrics -v ./...` | ✅ | `TestRelayMetricsDeltas` + `TestRelayMetricsHandlerScrapeContract` PASS (0.403s) |

**All green.** AC2's "largely already met" relay gauges are pinned by the delta + scrape-contract tests, including a leakage negative control.

---

## 5. Real Physical-Device Evidence

### iPhone13 (iOS 26.4.2, id `00008110-00184D622289801E`) — BUILT, PARTIAL (re-run 2026-05-29 23:15)

- Initial harvest run was BLOCKED at iOS code-signing (Xcode "No Accounts" for team `397R9Q4WMX`; device not in
  the `com.mknoon.app` / `.ShareExtension` / `.NotificationService` provisioning profiles). **RESOLVED** by adding
  the paid Apple Developer account (team `397R9Q4WMX`) to Xcode → Accounts; automatic signing then registered the
  device and built/installed/launched the app. (One transient first-launch/debugger-attach stall on the cold build
  required a kill + clean re-run; the incremental re-run launched and ran normally.)
- `buildInstalled: true`. Now **matches the Pixel6 evidence**:
- `wifi_transport_test.dart`: **12/12 PASSED on real iOS hardware** — `LOCAL_WS_SERVER_STARTED/STOPPED`,
  `LOCAL_WS_MESSAGE_SENT/RECEIVED` (bound to `localhost`/loopback, which is why iOS shows no Local Network prompt),
  concurrent sends, max-connection rejection+recovery, remote-close graceful failure, stale host:port fast-fail,
  WiFi media via HTTP PUT (`LOCAL_MEDIA_UPLOAD_SUCCESS`/`LOCAL_MEDIA_PERSISTED`, SHA-256 verified, persisted to the
  real iOS Data container). Genuine non-relay LAN/WiFi mechanism — but same caveat: mechanism-in-isolation, does
  NOT set `message.transport`, does NOT prove wifi-beats-relay.
- `transport_e2e_test.dart`: **3/3 PASSED, self-contained only** ("No CLI peer fixture"). Real relay online
  (`relay:state online`, `healthyRelayCount=1`, `relay:warm_timing` 267ms, relayId `12D3KooWGMYMmN1RGUYj`);
  `discover peer_not_found → relay:probe → inbox staged-forward` → **`[TEST] Self-contained PASS: status=delivered
  transport=inbox`**. Observed transports: `inbox`. No message delivered over relay (no paired peer).
- `wifi_relay_fallback_smoke_test.dart`: **1/1 PASSED, self-contained only** ("No CLI peer"). `inbox:store` path
  exercised against the live relay. No relay-vs-wifi fallback scenario ran. Observed transports: `inbox`.
- **Transports observed: `inbox` (real end-to-end) + genuine non-relay `local`/`wifi` WS mechanism.** Two-phone
  wifi-beats-relay still NOT proven (self-contained, no paired peer).

### Pixel6 (Android 16 / API 36, id `21071FDF600CSC`) — BUILT, PARTIAL

- `buildInstalled: true`.
- `wifi_transport_test.dart`: **12/12 PASSED. Genuine LAN/WiFi WS mechanism on real hardware** —
  `LOCAL_WS_SERVER_STARTED/STOPPED`, `LOCAL_WS_MESSAGE_SENT/RECEIVED`, max-connection rejection+recovery,
  remote-close graceful failure, stale host:port fast-fail, WiFi media transfer via HTTP PUT
  (`LOCAL_MEDIA_UPLOAD_SUCCESS`/`LOCAL_MEDIA_PERSISTED`, SHA-256 verified, persisted to app media dir).
  Observed transports: `local`, `wifi`. **This is a real local/wifi transport, NOT relay** — but per the device
  inventory this file exercises the LocalWsServer **mechanism in isolation** (two LocalWsServer instances over
  loopback), does NOT set `message.transport=='local'/'wifi'`, and **does NOT prove wifi-beats-relay** (no relay
  and no `sendChatMessage` race exist in this file).
- `wifi_relay_fallback_smoke_test.dart`: framework "All tests passed (1)" but harness logged
  "No CLI peer — only self-contained scenarios available" / "0/0 passed" — **NO relay-vs-wifi fallback scenario
  ran** (no paired CLI peer fixture). P2P node + identity/ML-KEM started on-device. Observed transports: none.
- `transport_e2e_test.dart`: **3/3 PASSED, self-contained only** ("No CLI peer fixture"). Real end-to-end
  transport exercised: **`transport=inbox`** (store-and-forward) after `relay:probe` returned `NO_RESERVATION`
  and the direct/relay race failed (`peer_not_found`); relay infra came online (`healthyRelayCount=1`, circuit
  addrs to `mknoun.xyz`) but **no message was delivered over a relay transport**. The WiFi-fallback case was only
  "documented", not proven. Observed transports: `inbox`.

### Real-device verdict (honest)

Real on-device transport **classification** works on **both physical platforms (Android Pixel6 AND iOS iPhone13)**:
each device produced genuine `inbox` end-to-end (full real stack: Go bridge + encrypted DB + real P2P node +
ChatMessageListener, against the live relay) and genuine `local`/`wifi` WS-mechanism events. The iOS signing
blocker from the first harvest run is resolved, so iPhone13 now corroborates the Pixel6 result rather than being
absent. **But the two-phone same-LAN "wifi beats relay" proof was still NOT observed on either device:** the wifi
events came from the loopback WS-mechanism test (no relay competitor, no transport-label stamping), and the
fallback/e2e suites ran self-contained with no paired peer (only `inbox` actually fired end-to-end). Per the
06-doc doctrine, a `{direct,relay,inbox}` set-acceptance pass is **never** read as proof of a specific wifi path.

> **SUPERSEDED 2026-05-30 by the live two-phone run in §5b** — the "still NOT observed" conclusion above reflects
> the automated integration tests only. The manual two-phone run below DID observe it.

### §5b. Live two-phone same-LAN run — 2026-05-30 (the residual-discharging evidence)

Setup: physical **iPhone 13** (`user-i`) ↔ physical **Pixel 6** (`user-a`), both freshly onboarded with real
identities, connected as contacts via QR, on the **same normal Wi-Fi**. Both apps run as debug builds via
`flutter run`; FLOW logs captured from both (`/tmp/iphone_run*.log`, Pixel `adb logcat -s flutter`).

- **mDNS discovery worked both ways (real LAN, not loopback):** Pixel `LOCAL_MDNS_PEER_FOUND host:"192.168.0.241"`;
  iPhone `LOCAL_MDNS_PEER_FOUND host:"Android_I0PE8R4E.local." port:46809`. A real LAN-IP WebSocket exchange
  followed: Pixel `LOCAL_WS_MESSAGE_SENT → host:"192.168.0.241" port:52734`; iPhone `LOCAL_WS_MESSAGE_RECEIVED`.
- **User chat messages delivered over non-relay transports:**
  - **iPhone → Android:** `CHAT_MSG_SEND_SUCCESS via:"local"` / `sendPath:"local"` (msgs `6fa72d01`, `30af718d`) =
    the **`wifi`** transport (LocalWsServer over the LAN). This is the genuine `wifi` label the simulator cannot
    produce, on real hardware, set on a real user message.
  - **Android → iPhone:** `CHAT_MSG_SEND_SUCCESS via:"direct"` / `transport:"direct"` / `connectionReused:true`
    (msgs `25229b0f`, `72d29c3c`) = a **`direct`** libp2p stream — a direct peer-to-peer connection over the LAN,
    **not relay**.
- **Relay online but unused:** `relay:state online`, `healthyRelayCount=1` was present, yet **no live message used
  `relay` or `inbox`**. Same-Wi-Fi pair → non-relay transports, relay census flat. This is exactly the
  "same-WiFi pairs use a non-relay path; relay not used" claim NET-REL-01/04 needed.
- **Honest nuance (a real observability finding, not a gap):** the two directions used *different* non-relay
  same-LAN mechanisms. Android used `direct` (not `wifi`) because a **warm direct libp2p connection already
  existed** (opened during the QR contact handshake, over the LAN) and the send ladder's `sendPath:"reuse"` rung
  took it before the LocalWsServer (`wifi`) leg completed. Both `direct` and `wifi` here are same-LAN, non-relay
  paths; **connection reuse biases the census toward `direct`** when a warm direct link exists. mDNS detection was
  NOT the problem — both phones discovered each other. So we proved "genuine `wifi` transport exists and is used on
  a real two-phone LAN, relay not used," not "every same-LAN message is labelled `wifi`."
- **On-device card read (criterion #1 & #5), both phones, fresh round:** iPhone "TRANSPORT DIAGNOSTICS (SESSION)"
  = `direct 4 / wifi 3` + rung `reuse 3`; Android = `direct 6 / wifi 1` + rung `reuse 3`. **`relay 0` and `inbox 0`
  on both.** FLOW corroboration: iPhone sent 3× `local`/wifi, Pixel sent 3× `direct`, **zero `transport:"relay"`**
  on either device. A developer read the live aggregate mix on-device on real hardware — including iOS.
- **Sender/receiver label asymmetry (observability finding):** the same message can be labelled `wifi` by the
  sender (it used the LocalWsServer) and `direct` by the receiver (it received over a direct libp2p stream) — which
  is why iPhone's card (sender of wifi) shows `wifi 3` while Android's card (receiver of those) skews `direct`.
  Both labels are same-LAN, non-relay; this is a labelling-vantage difference, not a transport error. Worth a
  follow-up note in the diagnostics docs so the `direct` vs `wifi` split is read as "send vs receive vantage."

### §5c. Production bug found AND fixed during the live run — Transport Diagnostics card unreachable after onboarding

Tracing why the on-device card did not render after onboarding revealed a real wiring bug: `transportMetrics` was
threaded only through `startup_router.dart`'s `FeedWired`. The **FTE** (`first_time_experience_wired.dart`), the
**QR scanner** (`qr_scanner_wired.dart`), and **Orbit** (`orbit_wired.dart`) had **no `transportMetrics` field**
and built their `FeedWired` / `QRScannerWired` without it, so a user who reached Feed via first-onboarding or
QR-connect got `transportMetrics == null` → the card was suppressed (`settings_wired.dart:513`). The host widget
test passed because it injects the metrics directly, so it never caught this — a textbook "passes in tests,
broken on device" gap.

**Fix landed (compiles clean, 0 errors):** added the optional `TransportMetrics? transportMetrics` field +
constructor param + import to FTE, QRScannerWired, and OrbitWired, and threaded the value through every
construction site: `startup_router → FTE` (×2), `FTE → FeedWired` + `FTE → QRScannerWired`,
`QRScannerWired → FeedWired`, `orbit_wired → QRScannerWired`, `main.dart → OrbitWired`, `feed_wired → OrbitWired`.
**Validated on device, BOTH platforms:** after the fix + a clean fresh round (apps uninstalled from both phones,
reinstalled fresh, re-onboarded), the **"TRANSPORT DIAGNOSTICS (SESSION)"** card renders and reads correctly on
**both** the Android (`direct 6 / wifi 1`) and the iPhone (`direct 4 / wifi 3`) — reached via the FTE/QR/Orbit
paths that previously suppressed it. The prior "card unreachable after onboarding" failure mode is gone on real
hardware. (The iOS device had to be rebooted once to recover a wedged CoreDevice channel that was hanging both
launch and uninstall — a device-state issue, not a code issue.)

---

## 6. LAN Residual Decision

**`discharged`** (as of the 2026-05-30 live two-phone run; was `partially_discharged` on the automated-test-only
evidence).

- **`discharged` because:** a real two-phone same-LAN exchange on physical hardware delivered user messages over
  **non-relay** transports — a genuine **`wifi`** message (iPhone→Android, LocalWsServer over the LAN) and a
  **`direct`** message (Android→iPhone, direct libp2p over the LAN) — with the relay **online but unused** (zero
  `relay`, zero `inbox` for the live messages). This is precisely the simulator-impossible proof the residual
  named. mDNS discovery succeeded both ways (real LAN IP `192.168.0.241` + `.local` host), so this is not loopback
  and not set-acceptance — the `wifi` label was set on a real user message by the real send path.
- **Documented nuance (not a residual):** connection-reuse biases one direction's census to `direct` rather than
  `wifi`; both are same-LAN non-relay paths. To force *both* directions to `wifi` you would have to suppress the
  warm direct connection — not necessary to prove the residual.
- **On-device card read CONFIRMED, both platforms:** criterion #1 (read the live mix on-device) and #5 (baseline
  mix) are now met on real hardware — iPhone card `direct 4 / wifi 3` and Android card `direct 6 / wifi 1`, both
  with `relay 0 / inbox 0`, after the fresh re-onboarded round. No remaining device confirmation is pending.
- **Only a test-infra nicety remains:** the automated headless two-phone harness (§8) is still unbuilt, but it is
  no longer a proof gap — the proof now exists from the manual run plus the on-device card reads.

---

## 7. Manual Two-Phone Same-LAN Procedure (for the remaining wifi proof)

> Verbatim from the device inventory. This is the only way to produce the remaining
> wifi-beats-relay evidence today; no headless harness exists.

**Goal:** produce REAL evidence that a message between two physical phones on the same WiFi traveled over LAN/wifi
(NOT relay), read directly off the on-device Transport Diagnostics card. This is a MANUAL human-driven procedure
because no headless harness exists (see missingHarness, §8).

**PRECONDITIONS**
1. Build/install a DISCOVERY-ENABLED app build on both phones. The default simulator/CI flow sets
   `DISABLE_LOCAL_DISCOVERY=true` (reset_simulators.sh) and the 06 doc 5b confirms simulators share the host mDNS
   stack and structurally cannot produce a local/wifi transport. So you MUST install a build WITHOUT that
   dart-define (local discovery / Bonsoir active). Install on iPhone13 (`00008110-00184D622289801E`) and
   Pixel6 (`21071FDF600CSC`) via: `flutter run -d <DEVICE_ID>` (no DISABLE_LOCAL_DISCOVERY define), or a
   release/profile install of the same.
2. Join BOTH phones to the exact same WiFi network/SSID (same subnet, AP client-isolation OFF so peers can reach
   each other on the LAN).
3. On the iPhone (iOS 14+), when first launched grant the iOS Local Network permission prompt
   (Settings > Privacy & Security > Local Network > <app> = ON). Without it iOS blocks mDNS/Bonjour and the LAN
   path will silently never form. The card's LAN > permission row shows 'suspected-denied' (heuristic: zero peers
   >=12s while discovery active) if it was denied — re-grant and relaunch if so.

**PAIRING + EXCHANGE**
4. On both apps complete identity creation, then add each other as contacts (QR scan one phone from the other) so
   each is a known contact with exchanged ML-KEM keys (required for encrypted send + for
   handleIncomingChatMessage to accept).
5. Keep BOTH apps in the FOREGROUND and on the same WiFi. Wait ~15-30s for local discovery to converge: open
   Settings > Transport Diagnostics card and confirm LAN > discovery = active and LAN > peers >= 1 on at least one
   phone (this is the on-device confirmation the LAN peer was actually found, not relay).
6. From phone A open the conversation with phone B and send several (5-10) text messages. Then from phone B reply
   with several messages. Sending while both are foregrounded on the same LAN with discovery converged makes the
   local/wifi rung the winner of the send race.

**READING THE BASELINE CARD (the evidence)**
7. On EACH phone open Settings and scroll to the 'TRANSPORT DIAGNOSTICS (SESSION)' card. Tap Refresh
   (key `settings-transport-debug-refresh-button`) to re-snapshot the live TransportMetrics.
8. Read the 'Transport mix (N=...)' section. Buckets are direct / relay / wifi / inbox (the metrics layer
   normalizes the internal 'local' label to the 'wifi' bucket). EVIDENCE OF SUCCESS: wifi count > 0 AND it
   accounts for the messages you just exchanged.
9. Read the 'Fallback rungs' section: the local rung count should be > 0 (the local rung fired).
10. CONFIRM IT WAS NOT RELAY: in the same Transport mix, relay count should be 0 (or unchanged from before the
    exchange) for those messages. Because the same-WiFi LAN path won, the relay bucket must NOT have incremented
    for the messages that show under wifi. If relay incremented instead of wifi, the LAN path did NOT win (check
    WiFi/AP isolation, iOS Local Network permission, discovery=active, peers>=1) and retry.
11. Read the 'Latency (median / p95)' section: wifi should show a sample (n>0) with low latency relative to relay,
    corroborating LAN delivery.
12. Optionally copy the 'Baseline report' (SelectableText, key `settings-transport-debug-report`) from each phone
    as the captured artifact — it is aggregate-only (no peer IDs / content) and is the durable record of
    wifi-count>0 / relay-not-used for NET-REL-04.

**NEGATIVE CONTROL (recommended, per 06 doc 2):** repeat steps 6-10 with the phones on DIFFERENT networks (e.g.
one on cellular) so LAN is impossible; the same exchange must then show relay (or inbox) count incrementing and
wifi staying 0 — proving the wifi label in the positive run was real and not hard-coded/defaulted.

---

## 8. Gate-Quality Census Harness — DEFERRED (tracked follow-up; the "06-doc §5 must-build" item)

The user-defined gate run (N≥50 per condition, cold-start to defeat warm reuse, **mandatory Condition B
cross-network**, count-at-sender) is what unblocks NET-REL-02/03 and sizes NET-REL-05. Per the operator decision
on 2026-05-30, building the automated harness for it is **deferred** — NET-REL-02/03 remain gated until it exists,
exactly as accepted in the verdict. The decision logic and required spec are unchanged; only the automation is
deferred.

### What was built (scaffold, compiles, NOT device-validated)
- `integration_test/transport_census_harness.dart` — single-device SENDER harness: reuses the device's onboarded
  identity + contact, loops N sends (cold via `callP2PPeerDisconnect` before each), dumps the full census
  (`transportMix`/`attemptCounts`/`attemptFailureCounts`/`latencyByTransport`/`rungDistribution`/`baselineReport`)
  to stdout. `flutter analyze` clean.
- `scripts/run_transport_census.sh` — single-device launcher (iOS `flutter drive` / Android `flutter test`),
  extracts the `===CENSUS_BEGIN===` block.
- `Test-Flight-Improv/transport-census-RUNBOOK.md` — operator runbook + validity checklist + caveats.

### Why it is not yet a working gate harness — the hard walls hit on 2026-05-30 (record these)
1. **Cross-device `/tmp` filesystem coordination does NOT work on physical devices.** The first design exchanged
   identities via a host `/tmp` dir; the sandboxed Android app cannot create it (`PathAccessException … errno 13`).
   The existing `group_multi_party_device_real_harness.dart` sidesteps this by targeting **simulators** (shared
   host filesystem) — it is not a true two-physical-device harness.
2. **The test runner wipes the state the reuse-identity design depends on.** `flutter test` integration runs on
   Android **uninstall the app afterward by default**, deleting the onboarded `identity.db` + keychain. (Observed:
   the Pixel was wiped mid-session; the iPhone — never reached by `flutter drive` — kept its onboarded state.)
   So "reuse the device's onboarded identity" is not stable across runs.
3. **ML-KEM keypairs are regenerated randomly on every identity restore** (not derived from the mnemonic — see
   project crypto notes). So two devices restoring fixed mnemonics get stable peerIds but **fresh ML-KEM pubkeys
   each run** → the peers MUST exchange ML-KEM pubkeys **at runtime**. With cross-device `/tmp` ruled out, that
   requires either host-mediated file-bridging (`adb pull`/`devicectl` to shuttle each node's fresh
   peerId+ML-KEM-pubkey, then relaunch the sender) or a programmatic P2P contact-request handshake.

### Remaining work to finish the harness (for whoever picks this up)
- A real cross-physical-device identity-exchange channel: **either** (a) host-mediated — each harness writes its
  `{peerId, publicKey, mlKemPublicKey}` to its **app sandbox** dir (path_provider), the orchestrator `adb pull`s
  (Android) / `devicectl` copies (iOS) and re-launches the sender with the peer info via `--dart-define`; **or**
  (b) a programmatic P2P contact handshake so the nodes exchange contact info over the network (no host bridging).
- Defeat the test-runner uninstall (so state persists across phases) or make the harness fully self-provisioning
  in a single launch (restore identity from a dart-define mnemonic + add the peer from dart-define contact info).
- The original spec still holds: omit `DISABLE_LOCAL_DISCOVERY`; drive the REAL use-case→bridge→Go send path with
  the relay also reachable; **count at the sender, once per message** (never pool sender+receiver — the receiver
  relabels wifi→direct); assert the SPECIFIC transport (not the `direct||relay||inbox` set-acceptance from the
  existing e2e tests); ship the paired NEGATIVE CONTROL (Condition B / LAN-blocked → must NOT report wifi, relay
  increments); and read the Track-B per-leg `attemptCounts`/`attemptFailureCounts` line (the direct-delivered-vs-
  failed disambiguator the 02/03 gate turns on).
- Secondary missing primitive: an app-level LAN-block / relay-disable toggle reachable from Dart (today only the
  build-time `DISABLE_LOCAL_DISCOVERY` lever and Go-test-only NW002 forcing exist).

`wifi_transport_test.dart` only tests the WS-server mechanism in isolation and never sets `transport=='local'`, so
it cannot serve as this harness.

---

## 9. Final Verdict

**`closed_with_residual`.**

- **4 of 5 NET-REL-04 acceptance criteria are met** (AC1, AC2, AC3, AC5) — pinned by green host Dart tests
  (exact-count census, real receive-path unknown-vs-relay, baseline composition + privacy) and green Go relay
  metrics contract tests, with real-hardware corroboration that the transport stack boots and classifies
  (`inbox` end-to-end + a genuine non-relay LAN/WiFi WS mechanism) on **both** a physical Pixel6 and a physical
  iPhone13.
- **AC4 (hole-punch counters) is NOT met — explicitly descoped** by the TOM closure spec; the closure doc is
  internally honest and never claims AC4. "Closed" in that doc refers to the narrower TOM-scoped contract.
- **LAN residual: `partially_discharged`.** Real-hardware transport classification works on both physical
  platforms (Pixel6 + iPhone13 — iOS signing blocker resolved), but the two-phone same-LAN wifi-beats-relay proof
  was NOT observed (on both phones the wifi events came from the isolated loopback WS-mechanism test, and the only
  real delivered label was `inbox` — both e2e/fallback suites ran self-contained with no paired peer). It still
  requires the §7 manual procedure or the §8 unbuilt harness.
- **Test-maintenance follow-up (non-blocking):** `test/core/services/p2p_service_transport_census_test.dart`
  fails to compile (stale fake missing `discoverLocalPeer` / `incomingLocalMediaStream`); its coverage is
  redundantly held by `transport_metrics_test.dart` + `p2p_service_inbound_transport_test.dart`.

---

## Appendix A — Discrepancies (no closure-doc-vs-file mismatches found)

1. **AC4** is a NET-REL-04 criterion but is descoped by the TOM closure spec (§5 Non-goals, §7 residuals).
   Internally consistent descope; NET-REL-04 is 4-of-5 closed.
2. **AC2's named addition** (1:1-vs-group circuit classification) is also out of scope; only the pre-existing
   aggregate relay gauges/counters are pinned by `metrics_test.go`. The "largely already met" phrasing is
   accurate and the doc does not claim the new classification shipped.
3. **Every cited evidence file exists and asserts what the closure doc claims** — no discrepancy between
   closure-doc "Landed evidence" file claims and file contents was found.
4. **Real-hardware-only items:** AC1's actual on-device card read and AC5's real-world wifi share / LAN fraction.
   The closure doc's Accepted residuals already acknowledge standard simulators cannot prove true LAN/WiFi —
   correctly host-only-needs-device, not claimed as met by tests.
