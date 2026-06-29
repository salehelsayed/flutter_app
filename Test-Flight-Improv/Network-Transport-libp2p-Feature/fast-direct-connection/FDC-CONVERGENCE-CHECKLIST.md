# FDC Convergence & Close — Operational Checklist

**Companion to [FDC-16-convergence-close-tdd-plan.md](FDC-16-convergence-close-tdd-plan.md).** This is the live check-off tracker for the epic's Phase-4 closure: device-proof + deploy + soak + FDC-S6 verdict + FDC-S0 re-measure. All Phase-0..3 authoring is DONE; nothing here is new features. Every row is **deferred-not-waived** until its box is checked.

**Legend** — category: `▢ host` (host-RED/CI) · `⚙ deploy` · `📱 device` · `🛰 live-relay-env` (gitignored/external) · `⏳ soak` · `⚖ decision` · `🚩 flag-flip`.
**Rule:** all Go gates run under `GOTOOLCHAIN=go1.25.0`; after any Go run, `git checkout -- go-mknoon/testdata/interop_vectors.json` (path is `go-mknoon/testdata/…`, NOT `…/node/…` — the latter silently no-ops). Never flip a prod flag ahead of its device/saturation gate. Never `git checkout`/`stash` shared files (concurrent `new-orbit` tree). `git status --short` before starting.

> ⭐ **KEYSTONE: CV-08 (FDC-11 D1) — ✅ CLOSED 2026-06-29 (`121f0551`).** D1 is GREEN both OS; this unblocked the soak, FDC-15 media, FDC-13 outgoing badge, FDC-14b ✦, and the S0 LAN-win metric. The **soak (CV-36)** is now the unavoidable long pole. P4.0 prereqs have landed.

---

## Execution scope — this environment vs deferred (recorded 2026-06-27)
> **Nothing below is removed from the plan** — env-blocked rows stay deferred-not-waived. This split only records *where* each can run, for whoever picks it up next.

**✅ Executable in THIS environment (host / authoring / git-op) — the session's actual to-do:**
- **CV-01** — review + **git-merge FDC-10 to main**. Code is **already committed on `new-orbit`** (clean tree; Redis backend/gauge/pool + `TC-10-01..05` present) → a **git op, NOT implementation**. Host tests already green.
- **CV-02 (Go half)** — `go test ./... && make lint` for the new exported bridge fns (the framework **rebuild** + native dispatch are device-deferred).
- **CV-07** — author + register the `classify_path()` cases + `dcutr_upgrade_proof_test.dart` + the 1:1 device-real orchestrator + assign every `--only N` (the device **run** is deferred).
- **CV-14** — FDC-09 send-side wake-token attach (host Go, RED-first).
- **CV-28** — **✅ ALREADY DONE** (FDC-06 shipped default-ON + kill-switch); only a cosmetic literal-test wording gap.
- **CV-42** — S0 M3 aggregation host bit (if not already carried by FDC-01).
- Flag-flip **lock tests** (CV-09/13/19) may be authored in parked/default-OFF form — but **not flipped to GREEN** here.

**⛔ Deferred — env-blocked (kept in plan, deferred-not-waived):**
- **2-phone both-OS rig — ✅ NOW AVAILABLE (2026-06-28):** iPhone 11 (`00008030-001A6D2801BB802E`) + iPhone 13 (`00008110-00184D622289801E`) — both iOS **26.5**, same WiFi — **+ a physical Android**. The device campaign (**CV-08 keystone** + CV-10/11/12/15/16/17/20/23/24/25/26/27/29/30/32/34/37/46) is **RUNNABLE** — no longer env-blocked (still gated on their own prereqs: gomobile rebuild CV-02, relay deploy CV-03 for push/presence, plan 170 for CV-29's burst, one peer on cellular for DCUtR CV-11/12). **iOS-major caveat WAIVED** (decision 2026-06-28: 11+13 are both 26.5 — proceed on what we have; CV-29's "2nd iOS major" dropped).
- **Touches LIVE PROD — ✅ DEPLOY AUTHORIZED (2026-06-28)** — `.env` (EC2_HOST `13.60.15.36`/Redis/Grafana) + `se.pem` present; the EC2 relay redeploy is now go: CV-03/04/05/06/35 (deploy) + CV-15/16/18/21/22/45 (live-relay) are **RUNNABLE**. ⚠ Deploy **NET-REL-07-safe**: SAME endpoint/peer-ID (old clients are pinned), `wakeTokenGateEnforced=OFF` (CV-14 attach not yet saturated), opaque-routing OUT.
- **Soak (sample collection)** — CV-36/38/39/47.
- **Decision (needs soak + device data)** — CV-40 (S6 verdict), CV-49 (S0 scorecard).
- **Flag-flip GREENs (device-gated)** — CV-09/13/19 (+ `EnableLibp2pLanMedia`).
- **External plan** — CV-29 gated on plan 170.

---

## P4.0 — One-time prerequisites (unblock everything)
- [ ] **CV-01** ▢ **Review + git-merge FDC-10 to main** — code is **already committed on `new-orbit`** (clean tree; Redis backend/gauge/pool + `TC-10-01..05` present). A **git op, NOT implementation**. **NOT merged this session — touching `main` not authorized.** ✅ Host tests confirmed green (2026-06-28): `go -C go-relay-server test ./...` `ok` + `go test -tags integration ./...` `ok` (miniredis failover 13.2s). Box stays open until an authorized merge.
- [x] **CV-14** ▢ FDC-09 **send-side wake-token attach** — ✅ **LANDED** (2026-06-28, RED→GREEN→mutation). New `InboxStoreDetailedWithWakeToken(to,msg,timeoutMs,wakeToken)` sets `req.WakeToken` on the store frame; `inboxRequest.WakeToken json:"wakeToken,omitempty"`; existing `InboxStoreDetailed` delegates with `""` (every prior caller + frame byte-identical, NET-REL-07); bridge `InboxStore` threads `wakeToken`. Tests `node/inbox_wake_token_test.go` (CV-14a attach; CV-14b omit-when-absent). RED proven (`wakeToken="" want "wake-tok-abc-123"`), mutation re-reds. `go test ./...` green (node+bridge `ok`); CV-14 + parked-lock tests pass under `-race` (targeted). *Production token-distribution path (recipient-issued token) deferred — bridge accepts it; tests inject directly. Must saturate before CV-19.* ⚠️ `go test -race ./node/` ALSO surfaces 4 **pre-existing** DATA RACEs in relay-recovery/watchdog tests (`TestReconnectRelays_WatchdogRestart`, `TestBenchmark_NodeStart_StopStart_Succeeds`, `TestGR020…`, `TestRecoveryCoalescing…`) — committed code CV-14 does not touch (`git status`: only inbox.go/bridge.go/feature_flags_runtime_test.go changed); NOT a CV-14 regression. **→ root-caused + RESOLVED by CV-50** (FDC-S1 `processStartEpochMs`, now `atomic.Int64`; `-race ./node/` clean).
- [x] **CV-28** ▢ FDC-06 **pause-flush default-ON — ✅ ALREADY DONE** (FDC-06 shipped it: `handle_app_paused.dart:67-68` `kFdcPauseFlushEnabled = !killswitch && !explicitOff`, wired `main.dart:4385`, comment `:4358` "ships ENABLED"). Locked by the ENABLED group + `expect(kFdcPauseFlushEnabled, isTrue)`. Only a cosmetic verbatim-test gap. Preserve: `./scripts/run_host_test_gates.sh core-host-all`
- [x] **CV-07** ▢ Author missing harness — ✅ **AUTHORED + REGISTERED** (2026-06-28). NEW `integration_test/scripts/run_1to1_device_real.dart` (pure `dart:io` `--list-scenarios`/`--scenario`/`-d` orchestrator, 16 campaign scenarios `fdc11_lan_direct_d1`…`fdc06_pause_flush_open_send`, each mapped to its CV/TC/mode — the `--only N` slot = 1-based index in `--scenario all --list-scenarios`) + NEW `integration_test/dcutr_upgrade_proof_test.dart` (TC-12-12/13, device-gated `--dart-define=FDC_DCUTR_DEVICE_PROOF=1`, skips on host). `classify_path()` + new `expand_1to1_device_real` wired in `scripts/check_reliability_simulation_discovery.sh`. **`./scripts/check_reliability_simulation_discovery.sh` PASS** (exit 0, 0 unclassified, no expansion errors; all 16 scenarios + both TC checks list). `flutter analyze` 0-new on both files. *Device RUN deferred-not-waived.*
- [x] **CV-02** ⚙ Consolidated **gomobile rebuild** (07 reserve_dispatch / 08-09 PresenceSet+Get / 11 HandleLANPeerFound / 12 dcutr / 14b isRelay) + native GoBridge.swift/.kt dispatch — ✅ **Go half green**: `go test ./...` `ok` (all pkgs); `make lint` 0 issues (after `//nolint:funlen` on the renamed store loop — same precedent as `HandleInboxStream`); `bridge` race-clean (4 node races are pre-existing relay-recovery, not mine — see CV-14). ✅ **DONE 2026-06-28 (P4.0 build)**: `make ios`+`make android` (GOTOOLCHAIN=go1.25.0) regenerated `ios/Runner/GoMknoon.xcframework` (Bridge.objc.h now exports all 5: BridgePresenceGet/PresenceSet/HandleLANPeerFound/MediaLANSend/RegisterWakeTokens) + `android/app/libs/GoMknoon.aar` (bridge.Bridge 61→66 native methods: presenceGet/presenceSet/handleLANPeerFound/mediaLANSend/registerWakeTokens). Native dispatch wired: `GoBridge.swift` +5 cases (relayPresenceGet/relayPresenceSet/lanPeerFound/inboxRegisterWakeTokens/mediaLanSend), `GoBridge.kt` +5 (casing trap honored: Dart `mediaLanSend`→Go `mediaLANSend`). `media:lan_received`/dcutr/isRelay ride the generic event channel (no native case). `scripts/verify_gomobile_bindings.sh all` clean (check_ios/macos/android all `missing=` empty). Plus Dart build-flag gap fixed: `enableLibp2pLANDial` dart-define (`MKNOON_ENABLE_LIBP2P_LAN_DIAL`, default OFF) added to `p2p_bridge_client.dart` (`flutter analyze` 0-new). **Device install: Pixel 6 ✅ (app-profile.apk, FDC_FLOW_LOG live + GO_BRIDGE_INIT_SUCCESS native, no crash) + iPhone 13 ✅ (devicectl, signed team 397R9Q4WMX); iPhone 11 ⛔ PENDING device-unlock (kAMDMobileImageMounterDeviceLocked — build+sign fine, retry `xcrun devicectl device install app --device 00008030-001A6D2801BB802E build/ios/iphoneos/Runner.app` once unlocked).** Test-build flags ON: `--dart-define=MKNOON_ENABLE_LIBP2P_LAN_DIAL=true --dart-define=MKNOON_ENABLE_DCUTR_UPGRADE=true --dart-define=MKNOON_ENABLE_LIBP2P_LAN_MEDIA=true --dart-define=FDC_FLOW_LOG=1` (prod defaults untouched). Source edits NOT committed (3 files: GoBridge.swift/.kt + p2p_bridge_client.dart); artifacts gitignored.
- [x] **CV-03** ⚙🛰 **Relay redeploy** — ✅ **DONE 2026-06-28**. Cross-compiled unified binary from `new-orbit` (FDC-10 Redis + FDC-09 presence_set + wake-gate) `GOOS=linux GOARCH=amd64` (sha `17d3…`, distinct from prior `2f91…`), `scp`→`sudo install /usr/local/bin/relay-server`→`systemctl restart` (backup `~/relay-server-backup-pre-20260628-094400` staged). Boot log: `Control-plane: backend=redis durable=true prefix=relay:` · `Server config: dns=mknoun.xyz ip=13.60.15.36 ws=4000 tcp=4005 wss=4001 quic=4002` · **`Peer ID: 12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (byte-identical to client pin — NET-REL-07 ✅)**. `wakeTokenGateEnforced=OFF` (package-var default, not env-wired) · opaque-routing OUT. External TCP reachable 4001/4005/4000; clients reconnected (conns≥1). On-box env already had RELAY_BACKEND=redis+REDIS_URL+RELAY_PRIVATE_KEY (EnvironmentFile=/etc/mknoon/relay-server.env) → no env edit; old binary lacked the durable gauge (pre-FDC-10). *(Note: 1 front-end, not ≥2 — see CV-04.)*
- [ ] **CV-04** ⚙ Provision relay #2 + inject WSS+QUIC into client pool (currently 1-peer) — **ACCEPTED 1-FE + Redis durability for now (handover-authorized).** Redis backend gives restart-durability with a single front-end; 2nd front-end deferred-not-waived (no LB/standby; brief outage on restart per production-stack audit).
- [x] **CV-05** ⚙ Ops runbook written (Redis flip / pool / gauge scrape) — ✅ `FDC-10-durable-inbox-redis-pool-ops-runbook.md` (verify gauge / Redis flip / revert).
- [x] **CV-06** 🛰 Confirm durability gauge. ✅ **`curl -s http://localhost:2112/metrics | grep relay_backend_durable` → `1`** (single front-end; `:2112` localhost-only, scraped via SSH; boot log `durable=true`). Re-confirm on each front-end if CV-04 adds a 2nd.
- [x] **CV-50** 🔴▢ **Fix the FDC-S1 `processStartEpochMs` data race** (triaged 2026-06-28) — `go test -race ./node/` (full pkg) = **3 races / 6 FAILs** (`TestReconnectRelays_WatchdogRestart…`, `TestGR020…`, `TestRecoveryCoalescing…`, + benchmark `NodeStart_StopStart`). **Root cause = ONE field on 3 node instances:** `n.processStartEpochMs` (plain `int64`, `node.go:67`, FDC-S1 observation-only) is **written** by `Start()` `node.go:268` and **read** by the relay-warm goroutine `Start.func2` `node.go:520-527` via `sinceProcessStartMs()` `node.go:2017`. That goroutine outlives a Stop/Start (authors captured `relayReadyCh`/`ctx` locally at `:518-519` but **missed the epoch read**) → a reconnect/watchdog/StopStart re-`Start`'s `:268` write races the lingering read. **NOT relay-recovery logic** (the recovery tests merely surface it via restart), **NOT a CV-14 regression**, **NOT a delivery bug** (field `never gates logic`; only garbles a `node:startup_timing` metric). It's an **FDC-S1 follow-up** and **fails `-race` → blocks CV-03 + the FDC-08/FDC-11 `-race` closure gates**. **Fix (minimal, host-only, ~3 lines):** make `processStartEpochMs` an `atomic.Int64` → `.Store(cfg.ProcessStartEpochMs)` at `:268`, `.Load()` at `:2017` (one writer / many emit-goroutine readers; idiomatic for an observation-only scalar; fixes all 3 + any future reader). Verify: `GOTOOLCHAIN=go1.25.0 go -C go-mknoon test -race ./node/ -count=1` clean. ⚠ `node.go` is on the shared concurrent tree → one writer, coordinate. **✅ FIXED 2026-06-28:** `processStartEpochMs` → `atomic.Int64` (`:67`), `.Store()` (`:268`), `.Load()` (`:2017`); `sync/atomic` already imported; stale "written once before any reader spawns" comment corrected. **RED** baseline (committed plain-`int64`, byte-identical to fix-reverted) = 3 DATA RACEs all at `node.go:268`↔`:2017`, 3 `--- FAIL`; **GREEN** (atomic) = `go test -race ./node/ -count=1` → **0 races / 0 FAILs**, `ok 467s` — so the RED baseline IS the mutation proof (no redundant revert cycle). `go build ./...` + gofmt clean; interop reverted; `git diff --check` clean. Go-only change ⇒ `flutter analyze` unaffected (0-new). Unblocks CV-03 + FDC-08/FDC-11 `-race` closure gates.

## P4.1 — Device-proof campaign (one 2-device same-WiFi rig + real relay + APNs)
- [x] **CV-08** ⭐📱 **FDC-11 D1 — two-phone same-WiFi LAN-direct win, BOTH OS** — ✅ **CLOSED 2026-06-29** (commit `121f0551`). Real Pixel 6 ↔ iPhone 11, same WiFi: **`MSG_RECEIVED_TRANSPORT:"direct"` BOTH directions**, `connections:2` both, iPhone 11 16+ min with **zero `0x8BADF00D`**. Closure required three fixes landed together: **175** (vendored `bonsoir_darwin` off-main `DNSServiceProcessResult` via `DispatchSourceRead` — killed the scene-update watchdog SIGKILL that blocked PASS #4), **174** (advert libp2p-port self-heal — `LocalP2PService.updateLibp2pPorts` re-advertises the resolved QUIC/TCP ports), and FDC-11 fixes **A** (unique mDNS name `mknoon-<peerIdTail>`) / **B** (`node.go splitHostAddresses` → `ListenAddresses()` fallback for Android SELinux netlink) / **C** (`.local`→`/dns4` multiaddr — the key unlock). *(manual; /sims N/A — sim shares bonsoir)* → unblocked **CV-09**
- [x] **CV-09** ▢🚩 Flip `EnableLibp2pLANDial` default→true + lock — ✅ **CLOSED 2026-06-29** (commit `4cce15c1`; plan `176-cv09-…`). **Device-proven on the DEFAULT flag (NO dart-define): `MSG_RECEIVED_TRANSPORT:"direct"` both ways.** KEY: the **LOAD-BEARING flip is the Dart `defaultValue` in `p2p_bridge_client.dart`** (the always-sent feature-flag map overrides Go `DefaultFeatureFlags` wholesale via `config.go:207-208`) — flipping only the Go default is a **prod no-op**. Go default + the guard test (`feature_flags_runtime_test.go` LANDial assertion inverted to require `true`) flipped too; NEW Dart anti-trap guard `test/core/services/p2p_service_lan_dial_flag_test.dart` (asserts the SENT `node:start` value). Host RED→GREEN + full preservation green (the Go flip is inert for the ~36 nil-flag integration tests, as predicted).
- [ ] **CV-10** 📱 FDC-11 T7 relay→direct upgrade real-circuit half
- [ ] **CV-11** 📱 FDC-12 TC-12-12 real relay→direct upgrade fires+sticks. `/sims 1to1 --only <N>`
- [ ] **CV-12** 📱 FDC-12 TC-12-13 symmetric-CGNAT graceful no-upgrade. `/sims 1to1 --only <N>`
- [ ] **CV-13** ▢🚩 Flip `EnableDcutrUpgrade` default-on + update TC-12-01 lock. `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ ; ./scripts/run_test_gates.sh transport`
- [ ] **CV-15** 📱🛰 FDC-09 TC-09-20 iOS visible-wake (not silent-throttled)
- [ ] **CV-16** 📱🛰 FDC-09 TC-09-21 `presence_set{background}` lands pre-suspend
- [ ] **CV-17** 📱 FDC-09 TC-09-22 presence TTL tune (FDC-S3 Method 1) *(shared w/ CV-22)*
- [ ] **CV-18** 🛰 FDC-09 TC-09-24 old-relay `Unknown action: presence_set` degrade (needs old+new relay)
- [ ] **CV-14→CV-19** ▢🚩 After CV-14 **saturates**: flip `wakeTokenGateEnforced` ON. `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...`
- [ ] **CV-20** 📱 FDC-09 TC-09-23 non-contact cannot wake (gate e2e) — *requires CV-19*
- [ ] **CV-21** 🛰 FDC-08 LR1 live relay answers presence w/o circuit dial + NET-REL-07 e2e. `./scripts/run_test_gates.sh transport ; /sims 1to1 --only <N>`
- [ ] **CV-22** 🛰 FDC-08 presence TTL constants device-tuned (~180s / 10-15s) *(shared w/ CV-17)*
- [ ] **CV-23** 📱 FDC-07 TC-07-05 cold T_circuit ≤3s + reserve_dispatch anchor
- [ ] **CV-24** 📱 FDC-07 TC-07-06 early mDNS + LAN opportunistic
- [ ] **CV-25** 📱 FDC-04 TC-04-15 warm-open send = `local`
- [ ] **CV-26** 📱 FDC-04 WiFi→cellular re-warm fires
- [ ] **CV-27** 📱 FDC-04 TC-04-05 cold notif-tap PS-3 no-op
- [ ] **CV-30** 📱 FDC-13 real-wire `transport:upgraded`→badge *(needs CV-11/13)*
- [ ] **CV-32** 📱 FDC-14 badge reaches `onlineDirect` on real LAN pair *(needs FDC-14b producer)*
- [ ] **CV-33** ⚙ FDC-15 native `mediaLanSend` + `media:lan_received` emit (rebuild)
- [ ] **CV-34** 📱 FDC-15 D1 two-phone LAN media (`/mknoon/media-lan/1.0.0`), both OS *(toggle `EnableLibp2pLanMedia` ON for the rig)*
- [ ] **CV-29** 📱 FDC-06 T8 open-send-lock delivers on the iPhone 11/13 (iOS 26.5) pair — **2nd-iOS-major WAIVED** (decision 2026-06-28: work with what we have). Single-message T8 runnable now; **N≥3 burst still BLOCKED on plan 170** (+ CV-28 ✅ + CV-07 ✅ + CV-06 durable custody).

## P4.2 — Win-rate soak
> **Precondition LANDED 2026-06-29 (plan `177-lan-classifier-dns4-local-private`, commit `fd278a71`):** the FDC-S6 win-rate classifier `lan_address_classifier.dart` now counts `/dns4|/dns6|/dnsaddr/<host>.local` as private/LAN (RFC 6762). It previously returned `lanPrivateIp:false` for **iOS-resolved** peers (Fix C's `/dns4` shape), so CV-36/37 could **never certify** a clean LAN win whenever iOS was the discoverer. **Device-confirmed:** iPhone 11 now emits `P2P_LAN_PEER_FOUND_REQUEST{lanPrivateIp:true}` (was `false`). A **pilot** run is done (A→i 54/54 clean = 100%, Wilson-LB 93.4% — UNDERPOWERED at n=54; i→A showed a real 39-direct/14-`wifi` mix + 23% double-delivery). The full soak campaign (CV-36/37/38/39) **stays OPEN**. Capture-procedure note: launch the iPhone advertiser FIRST, then the Pixel, so the Pixel doesn't latch its suspected-denied mDNS gate before discovery.
- [ ] **CV-35** ⚙ Soak+baseline binaries `flutter build (profile) --dart-define=FDC_FLOW_LOG=1`
- [ ] **CV-36** ⏳ Win-rate soak: libp2p-LAN Wilson-LB ≥95%, ≥385 sends/dir, 3 platform-dirs (A→A / i→i / A↔i) — duration floor removed by decision 2026-06-29 (no 14-day soak; the ≥385-sample Wilson-LB criterion is the sole gate). `fdc-s6-measurement/fdc_s6_capture.sh + fdc_s6_parse.py`
- [ ] **CV-37** 📱 bonsoir-fed-dial reliability both OS (Wilson 95% LB ≥95%, ≥385)
- [ ] **CV-38** ⏳ double-delivery rate by (first,second)-leg pair
- [ ] **CV-39** ⏳ failure-delta ≤ +1.0pp vs bonsoir+WS baseline (Newcombe CI)

## P4.3 — FDC-S6 verdict
- [ ] **CV-40** ⚖ Per-component verdict → VERDICT block; Status open→closed (retire-chat Y/N · retire-media Y/N · keep-bonsoir=always). *retire-media also needs CV-34 OR recorded relay-CDN-only acceptance*
- [ ] **CV-41** ▢ *(conditional — only if retire-chat=Y)* WS-chat-removal repoint (`startAdvertising` off `wsPort` → libp2p host port) — NEW follow-on plan, full RED. `./scripts/run_test_gates.sh transport ; run_host_test_gates.sh core-host-all`

## P4.4 — Staged prod flag-flips (each at its gate; all reversible)
| Flag | Default → | Gated on | Lock | Box |
|---|---|---|---|---|
| `kFdcPauseFlushEnabled` | OFF → ON | host lock only (ready) | CV-28 | [ ] |
| `EnableLibp2pLANDial` | false → **true ✅** | CV-08 D1-GREEN ✅ | CV-09 ✅ | [x] (`4cce15c1`, device-proven) |
| `EnableDcutrUpgrade` | false → true | CV-11/12 close | CV-13 | [ ] |
| `wakeTokenGateEnforced` | OFF → ON | **CV-14 saturate** then CV-20 | CV-19 | [ ] |
| `EnableLibp2pLanMedia` | stays OFF | FDC-S6 media verdict | — | (no flip this phase) |

> **Parked dark-ship lock added (2026-06-28):** `node/feature_flags_runtime_test.go::TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof` pins `EnableLibp2pLANDial` / `EnableDcutrUpgrade` / `EnableLibp2pLANMedia` = **false** by default, so an accidental flip ahead of its device gate re-reds. This is the *pre-flip* polarity; CV-09/CV-13 invert the matching assertion once D1 / the DCUtR campaign close. **No flag flipped to ON this session** (Scope Guard).
>
> **Update 2026-06-29:** CV-09 **inverted the `EnableLibp2pLANDial` assertion** (it now pins **`true`** by default, `4cce15c1`). The parked-false lock in `TestFeatureFlags_FdcTransportFlagsShipDarkUntilDeviceProof` remains for **`EnableDcutrUpgrade`** (CV-13) + **`EnableLibp2pLANMedia`** (CV-34) only — those two stay dark until their device gates close.

## P4.5 — FDC-S0 re-measure = epic close
- [x] **CV-42** ▢ M3 online→inbox mis-route After ≈0 — ✅ **RIGOR ALREADY CARRIED BY FDC-01** (confirmed 2026-06-28): the `FDC-01 — direct-timeout misroute + per-step budget` group in `test/features/conversation/application/send_chat_message_use_case_test.dart:4180-4302` locks "slow-but-online peer delivers direct, NOT `transport:'inbox'`" and rides the `1to1` gate. No new host code (per plan: "rigor in FDC-01"). The *After-rate aggregation* number is part of the deferred FDC-S0 scorecard (CV-49). Preserve: `./scripts/run_test_gates.sh 1to1`
- [ ] **CV-43** ▢ M1b/M5 Go benchmarks After. `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ -run TestBenchmark -v | grep BENCHMARK`
- [ ] **CV-44** ▢ M8 reaction-to-offline After (FDC-18)
- [ ] **CV-45** 🛰 M9 inbox durability survives relay restart (FDC-10 failover)
- [ ] **CV-46** 📱 M1/M2/M4/M5/M7 device scorecard captures (≥10 trials)
- [ ] **CV-47** ⏳ M6 LAN win-rate same-WiFi (REUSE CV-36 soak)
- [ ] **CV-48** ▢ M10 host-gate floor After. `./scripts/run_test_gates.sh 1to1 ; feed ; transport`
- [ ] **CV-49** ⚖ Populate scorecard Before/After/Delta/Verdict + frozen-baseline & close-commit hashes (LAST). *device-only metrics (M1 same-WiFi, M6) marked deferred-not-waived*

---

## Open blockers / gaps to resolve before /sims
- [ ] **FDC-10 is `awaiting-review`** — the durability deploy chain (CV-03..06) + S0 M9 (CV-45) are blocked until it lands.
- [ ] **Live-relay-env is gitignored but PRESENT locally** (`.env`: EC2_HOST `13.60.15.36`/Redis/Grafana creds + `se.pem`) — CV-03/06/15/16/18/21/22/45 are reachable *in principle*, but they connect/deploy to **LIVE PROD** → require **explicit authorization**; do not run unprompted.
- [x] **Device scenario `--only N` ids UNDEFINED** — ✅ **RESOLVED** (2026-06-28, CV-07): `dcutr_upgrade_proof_test.dart` + `run_1to1_device_real.dart` authored; discovery script lists all 16 1:1 device scenarios + both dcutr TC checks (`--only N` = 1-based index in `run_1to1_device_real.dart --scenario all --list-scenarios`). Device *run* still deferred (no 2-phone rig).
- [ ] **plan 170** (send-button) gates CV-29 (FDC-06 T8 N≥3 burst).
- [ ] **FDC-13 1to1 pass count printed inconsistently** (+1250 vs +13) → reconcile the true count in CV-48.
- [ ] **FDC-14b producer** (onlineDirect signal source, Route B) being built this session — CV-32 device-proofs it once it + FDC-11 land.

## Epic-close sign-off (all must be ✓)
- [ ] Every CV-01..49 box checked **or** explicitly recorded deferred-not-waived with reason + owner.
- [ ] All host gates green (`1to1`/`feed`/`transport`/`groups`/`core-host-all`/`feature-host-all`); `flutter analyze` 0-new; `git diff --check` clean.
- [ ] NET-REL-07 verified: an old (pre-update) client still texts + notifies against the redeployed relay.
- [ ] FDC-S6 Status = closed with a per-component verdict; any retire spawned + executed.
- [ ] **FDC-S0 scorecard published** (Before→After→Delta) → epic CLOSED.
