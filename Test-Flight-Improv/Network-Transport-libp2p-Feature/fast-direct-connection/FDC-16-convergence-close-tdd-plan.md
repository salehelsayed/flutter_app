# FDC-16 — Convergence & Close (device-proof campaign + 14-day soak + FDC-S6 verdict + FDC-S0 re-measure)  (Modification / Closure-orchestration)

Status: awaiting-review
Spec: free-text intent (no formal spec doc) — closure phase of the [FDC epic](FDC-00-roadmap.md); grounded by a 13-reader inventory workflow (2026-06-27). Companion operational tracker: **[FDC-CONVERGENCE-CHECKLIST.md](FDC-CONVERGENCE-CHECKLIST.md)**.

> **What this plan is.** The Phase-0..3 *authoring + host-code + device-independent spike scaffolding* of the FDC epic is DONE. This plan is the **Convergence & Close phase (Phase 4)** — it does NOT add features; it discharges the **deferred-not-waived** closure obligations every sub-plan left behind (device-proof, live-relay-env, deploy, the 14-day soak, the FDC-S6 verdict, staged flag-flips, and the FDC-S0 re-measure scorecard). It applies **full RED→GREEN→mutation rigor only to the genuinely-new host code** (flag-default-flip locks, the send-side wake-token attach, the S0 aggregation, the conditional WS-removal, and the FDC-S1 `processStartEpochMs` `-race` fix — CV-50); everything else is a **gated closure register** with literal acceptance commands, because a device-proof / live-relay / soak / decision row is not a host unit test and cannot be mutation-reverted on HEAD.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-27 | Evidence Collector | 13-reader grounding workflow over FDC-04/06/07/08/09/10/11/12/13/14/15 + S6 + S0 | 49 convergence rows (CV-01..49) inventoried; FDC-10 still `awaiting-review`; live-relay-env gitignored | build matrix + register |
| 2026-06-27 | Planner | tier-matrix / sufficiency-checklist / plan-template | host-RED rigor on 7 code rows; closure register for the rest | emit FDC-16 + checklist |
| 2026-06-27 | Reviewer (sufficiency) | this doc | see Reviewer Findings | — |
| 2026-06-27 | Arbiter | this doc | see Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | P4.0 prereqs (FDC-10 land + gomobile rebuild + relay redeploy) | | | | |
| | P4.1 device campaign (FDC-11 D1 keystone) | | | | |
| | P4.2 14-day soak | | | | |
| | P4.3 S6 verdict | | | | |
| | P4.4 staged flag-flips (interspersed) | | | | |
| | P4.5 FDC-S0 re-measure scorecard | | | | |

## Source Of Truth
- Intent / sequencing: **FDC-00-roadmap.md** (phase grid, closure strategy, gating graph, durability hazard).
- Per-plan deferred closure rows: each sub-plan's `Done Criteria` / `Device/Relay Proof Profile` / `Acceptance Gates` (grounded 2026-06-27).
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose).
- Sim discovery/registration: `scripts/check_reliability_simulation_discovery.sh`.
- Measurement harness: `fdc-s6-measurement/` (FDC-S6) ; `FDC-S0-baseline-results.md` (the frozen Before).
- Numbering: epic-internal `FDC-NN` (next-free = **FDC-16**; not a top-level `00-INDEX.md` number per the roadmap's Global-numbering note).

## Session Classification
**Mixed: implementation-ready for the host-RED code rows / deploy-gated + device-gated + wall-clock-gated + decision-gated for the rest.** The ~7 host-RED rows can be built now (RED-first). Everything else is blocked on one of: FDC-10 landing, the gomobile rebuild, a relay redeploy, the live-relay-env (gitignored — external), real 2-device hardware, plan 170, token-saturation, or the unavoidable 14-day soak.

## Exact Problem Statement
The epic's host-testable surface is complete, but **none of the wins that touch a real wire or a real OS transition has been proven on a device, no relay change is deployed, the WS-retirement verdict cannot be issued, and the before→after improvement scorecard is unwritten.** Each sub-plan deliberately deferred these as *deferred-not-waived*. Until they close, the epic is "host-green but unvalidated" — exactly the false-positive class the proposal §9.1 warns about (dedup can mask a dead live path).

**What must improve:** every deferred-not-waived row reaches a documented terminal state — proven on device, deployed, soaked, decided, or re-measured — so the epic can close on the FDC-S0 scorecard.
**What must stay unchanged → preserved sentinels:** all host gates green throughout (`1to1` / `feed` / `transport` / `groups` / `core-host-all` / `feature-host-all`); NET-REL-07 (old clients keep texting — additive deploy, same relay endpoint/peer-ID, `wakeTokenGateEnforced=OFF`, opaque-routing OUT); group messaging never regresses; no flag flips to prod ahead of its device-proof.

## Root Cause (verify → refute confirmed)
N/A — this is a closure-orchestration plan, not a bug fix. The "verify→refute" here is the **grounding inventory** (13 readers): it confirmed the deferred rows are real, surfaced that **FDC-10's code is committed on `new-orbit` (clean tree) but its plan is `awaiting-review`** — the durability chain is blocked on the *review+merge-to-main + deploy* git/ops steps, NOT on writing code; confirmed the **live-relay-env is gitignored but PRESENT locally** (`.env`: EC2_HOST `13.60.15.36`/Redis/Grafana + `se.pem`) — reachable in principle but prod-gated (needs explicit deploy authorization), and flagged that several device-proof **scenario ids are UNDEFINED** and the **`classify_path()` cases + the `dcutr_upgrade_proof_test.dart` harness + the 1:1 device-real orchestrator DO NOT EXIST yet** (RED until authored).

**Refuted / do-NOT-re-introduce (already corrected upstream this epic):**
- FDC-14b "ships dark = directReady inert" — FALSE (the relay conn is itself non-circuit); fixed via Route B (Go `isRelay` filter). Do not re-define `directReady` as "any non-circuit conn."
- FDC-09 `presence_set{background}` → reachable — FALSE for §6.3; resolver must map background → unreachable. Do not collapse fg/bg to reachable.

## Real Scope
**In scope (FDC-16 owns the orchestration of):** CV-01..49 below — FDC-10 land + deploy, the consolidated gomobile rebuild, the relay redeploy, the device-proof campaign (FDC-04/06/07/08/09/11/12/13/14/15 device rows), the 14-day FDC-S6 soak, the FDC-S6 verdict, the staged prod flag-flips, and the FDC-S0 re-measure scorecard. Genuinely-new host code: the 4 flag-default-flip locks, the FDC-09 send-side wake-token attach, the FDC-S0 M3/M7 aggregation, and the conditional WS-removal repoint.
**Out of scope (owning work):**
- All sub-plan host code / RED catalogs — **already landed** in FDC-04..15 (this plan only re-runs their gates as preservation + discharges their device rows).
- **plan 170** (send-button frozen-snackbar) — external; gates FDC-06 T8's N≥3 burst (CV-29).
- **FDC-01 (M3) / FDC-18 (M8)** RED rigor — landed in their own plans; S0 only re-runs + aggregates their telemetry.
- The **WS-chat-removal / WS-media-removal** plans themselves — spawned by the FDC-S6 verdict (CV-40); FDC-16 only triggers + tracks them.
- Standing up the **live relay env** (gitignored) — an external ops dependency.

## Files To Inspect Next
**Host-RED code (the only new code this plan adds):**
- `go-mknoon/node/feature_flags.go` — `DefaultFeatureFlags()` flips: `EnableLibp2pLANDial` (CV-09), `EnableDcutrUpgrade` (CV-13). Tests: `feature_flags_runtime_test.go`, `dcutr_upgrade_flag_test.go::TestDcutrFlagOff_ForcesPrivate_ZeroPunches`.
- `go-mknoon/node/inbox.go` + `bridge/` — `InboxStoreDetailed` send-side wake-token attach (CV-14); `wakeTokenGateEnforced` flip (CV-19).
- `lib/core/lifecycle/handle_app_paused.dart:31-36` + `lib/main.dart:4360-4370` — `kFdcPauseFlushEnabled` default-on / drop `enablePauseFlush` gate (CV-28). Test: `handle_app_paused_pause_flush_test.dart`.
- FDC-S0 aggregation — fleet `transport:'inbox'` / `FDC_RESUME_STEP_TIMING` rollup (CV-42); lands WITH FDC-01/FDC-S1.
- (Conditional) WS-chat-removal repoint — `startAdvertising` off `wsPort` → libp2p host port (CV-41), only if verdict = retire-chat.
**Deploy / harness:**
- `scripts/check_reliability_simulation_discovery.sh` — net-new `classify_path()` cases (CV-07): FDC-06 pause-flush, FDC-07 cold-circuit+LAN, FDC-09, FDC-12 `dcutr_upgrade_proof_test.dart`; the 1:1 device-real `--scenario` orchestrator (does not exist yet).
- `go-relay-server/` — land FDC-10 (CV-01); build+deploy unified relay (CV-03).
- `fdc-s6-measurement/{scripts,README.md}` — the soak capture/parse harness (already landed).

## Existing Tests Covering This Area
- Each sub-plan's host suites are GREEN and stay as **preservation sentinels** (re-run, do not edit): `run_test_gates.sh 1to1` / `transport` / `feed` / `groups`, `run_host_test_gates.sh core-host-all` / `feature-host-all`.
- FDC-10 host floor `TC-10-01..05` + miniredis `-tags integration` — exist but **not yet merged** (CV-01).
- FDC-11 `lan_dial_test.go` T1..T10 (host) — landed; D1 device row MISSING (CV-08).
- FDC-12 `dcutr_upgrade_flag_test.go` + host scaffolding — landed; `dcutr_upgrade_proof_test.dart` MISSING (CV-11/12).
- FDC-06 `handle_app_paused_pause_flush_test.dart` (13 locks) — landed; T8 device MISSING (CV-29).
- FDC-S6 precondition lock + `fdc-s6-measurement` harness — landed; soak un-run (CV-36).
- **Missing coverage gaps:** every device-proof scenario (CV-08/10/11/12/15/16/20/23/24/25/26/27/29/30/32/34/37), the `classify_path()` cases (CV-07), the dcutr proof harness + 1:1 device orchestrator, and the S0 After captures (CV-42..49).

## RED Test Catalog  (host code only — add BEFORE the production edit — INV-RED-FIRST)

> Only the genuinely-new host code carries RED tests. The device-proof / live-relay / soak / decision / deploy rows are in the **Closure Gate Register** below (they fail by *absence of evidence*, not by a host assertion, so they are tracked as gated criteria, not mutatable RED tests).

1. **CV-28 — pause-flush default-ON — ✅ ALREADY SHIPPED by FDC-06 (correction 2026-06-27; NOT new work).**
   - **Status: DONE.** `kFdcPauseFlushEnabled` is **default-ON** today: `handle_app_paused.dart:67-68` = `!_kFdcPauseFlushKillSwitch && !_kFdcPauseFlushExplicitOff`, wired at `main.dart:4385` (`enablePauseFlush: kFdcPauseFlushEnabled`; comment `:4358` "ships ENABLED"). FDC-06 shipped "ON + kill-switch." (This plan's earlier draft + the grounding agent wrongly read the `:31-36` helper consts as the default — **corrected**.)
   - **Residual = cosmetic only:** the verbatim `…::deps present + no flag → flush runs` test may not exist word-for-word, but flush-ON is already locked by FDC-06's ENABLED group + the `expect(kFdcPauseFlushEnabled, isTrue)` decision-lock. No substantive work; optionally add the verbatim test for completeness.
   - Acceptance (preservation, not RED): `./scripts/run_host_test_gates.sh core-host-all`.

2. **CV-14 — `go-mknoon` node/bridge `InboxStoreDetailed` attaches the recipient-issued opaque wake-token on the store request**
   - Tier: Go unit (`GOTOOLCHAIN=go1.25.0`).
   - Shape/setup: build a store request for a recipient who has issued wake-tokens; capture the emitted frame.
   - RED on HEAD because: `register_wake_tokens` / `IssueWakeTokensUseCase` exist but are **inert** — the *sender* never attaches the token; the store frame carries none.
   - GREEN asserts: the store frame includes the recipient's opaque wake-token; absent-token recipients are unaffected (additive).
   - Mutation: drop the attach → frame has no token → RED. Run under `go test -race`.
   - **Ship-order note (load-bearing):** this MUST land + saturate the sender fleet *before* CV-19 flips `wakeTokenGateEnforced` ON, or the flip hard-silences every recipient's 1:1 pushes.

3. **CV-09 — `go-mknoon/node/feature_flags_runtime_test.go::DefaultFeatureFlags().EnableLibp2pLANDial == true`** (flag-default-flip lock)
   - Tier: Go unit. RED on HEAD: default is `false` (FDC-11 ships dark). GREEN after flip (post D1). Mutation: revert default→false → RED. **Gate: only flip after CV-08 (D1-GREEN).**

4. **CV-13 — `go-mknoon/node/dcutr_upgrade_flag_test.go::TestDcutrFlagOff_ForcesPrivate_ZeroPunches` re-locked to `DefaultFeatureFlags().EnableDcutrUpgrade == true`** (flag-default-flip lock)
   - Tier: Go unit. RED on HEAD: default `false`. GREEN after flip (post FDC-12 device close CV-11/12). Mutation: revert default→false → RED.

5. **CV-19 — `go-mknoon` `wakeTokenGateEnforced` default-flip lock (false→true)**
   - Tier: Go unit. RED on HEAD: gate recorded-but-inert (default false). GREEN after flip. Mutation: revert → RED. **Gate: only after CV-14 lands + saturates; then CV-20 (TC-09-23) validates e2e on device.**

6. **CV-42 — FDC-S0 M3 aggregation: fleet `transport:'inbox'` mis-route rollup (online→inbox → ~0)**
   - Tier: host (re-run of FDC-01's RED + additive flow-event aggregation). RED on HEAD: FDC-01's `direct_timeout`→inbox lock (a slow-discover online peer must NOT land `transport:'inbox'`). GREEN: aggregation reports the After mis-route rate ≈ 0. Mutation: re-introduce the §4.1 mis-route → FDC-01 lock RED. **Ownership: the RED rigor lives in FDC-01 (landed); S0 re-runs + aggregates.**

7. **CV-41 — (CONDITIONAL) WS-chat-removal repoint** — only authored if CV-40 verdict = retire-chat. Full RED→GREEN→mutation in its own spawned plan: `startAdvertising(peerId, wsPort)` → libp2p host port; RED = a host lock that the advertised port is the libp2p QUIC/host port, not `wsPort`; preservation = `transport` + `core-host-all` green; mutation = revert the repoint → RED.

8. **CV-50 — FDC-S1 `processStartEpochMs` data race (host `-race` fix; triaged 2026-06-28).**
   - Tier: Go `-race` (host). Files: `go-mknoon/node/node.go` (`:67` field decl, `:268` write, `:2017` read).
   - RED on HEAD because: `processStartEpochMs` is a plain `int64` written by `Start()` `:268` and read by the relay-warm goroutine `Start.func2` (`:520-527`) via `sinceProcessStartMs()` `:2017`; that goroutine outlives a Stop/Start (authors captured `relayReadyCh`/`ctx` at `:518-519` but missed the epoch read), so a reconnect/watchdog/StopStart re-`Start` write races its read → `GOTOOLCHAIN=go1.25.0 go -C go-mknoon test -race ./node/ -count=1` = **3 races / 6 FAILs** (`TestReconnectRelays_WatchdogRestart…`, `TestGR020…`, `TestRecoveryCoalescing…`, + `TestBenchmark_NodeStart_StopStart`). (The 4 tests pass clean in isolation — it's a full-package restart phenomenon: 3 races = one field on 3 node instances.)
   - GREEN after fix asserts: make `processStartEpochMs` an `atomic.Int64` (`.Store(cfg.ProcessStartEpochMs)` at `:268`, `.Load()` at `:2017`, `import "sync/atomic"`) → `go test -race ./node/` clean, 0 races. (Atomic over mutex: one writer / many emit-goroutine readers, observation-only scalar; fixes all 3 + any future reader.)
   - Mutation that re-reds: revert the field to plain `int64` (drop `.Store`/`.Load`) → the 3 races return under `-race`.
   - Severity: **observation-only** (the field `never gates logic`; only garbles a `node:startup_timing` metric) — NOT a delivery bug, NOT relay-recovery logic (those tests merely surface it via restart), NOT a CV-14 regression; an **FDC-S1 follow-up**, pre-existing on `new-orbit`. **Blocks CV-03 + the FDC-08/FDC-11 `-race` closure gates.** ⚠ `node.go` is on the shared concurrent tree → one writer, coordinate.

## Test Coverage Matrix — host-RED rows (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| CV-28 | pause-flush default-on — **✅ DONE (FDC-06 shipped)** | unit | already locked: ENABLED group + `expect(kFdcPauseFlushEnabled, isTrue)` | N/A — default is already **ON** (`:67-68`, wired `main.dart:4385`); only a cosmetic verbatim-test gap | re-gate default OFF | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (`test/core/**`) |
| CV-14 | send-side wake-token attach | Go unit | `inbox_*_test.go::store frame attaches recipient wake-token` | sender never attaches (inert) | drop attach | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./... ; go test -race ./...` | AUTO (`go test ./...`) |
| CV-09 | LANDial flag default-on | Go unit | `feature_flags_runtime_test.go::EnableLibp2pLANDial default true` | default false (dark) | revert default→false | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO |
| CV-13 | Dcutr flag default-on | Go unit | `dcutr_upgrade_flag_test.go::…EnableDcutrUpgrade default true` | default false | revert default→false | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ ; ./scripts/run_test_gates.sh transport` | AUTO |
| CV-19 | wake-gate enforce flip | Go unit | `…::wakeTokenGateEnforced default true` | inert (default false) | revert→false | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` | AUTO |
| CV-42 | S0 M3 mis-route ≈0 | host | FDC-01 `direct_timeout`→inbox lock + S0 aggregation | §4.1 mis-route present | re-introduce mis-route | `./scripts/run_test_gates.sh 1to1` | AUTO (rigor in FDC-01) |
| CV-41 | WS-chat-removal repoint (conditional) | host | spawned plan::advertise libp2p port not wsPort | advertises `wsPort` | revert repoint | `./scripts/run_test_gates.sh transport ; run_host_test_gates.sh core-host-all` | AUTO (in spawned plan) |
| CV-50 | FDC-S1 epoch race fix | Go `-race` | `node.go` `processStartEpochMs`→`atomic.Int64` (`:67`/`:268`/`:2017`) | plain `int64` write@`:268` races goroutine read@`:2017` → 3 races/6 FAILs | revert to plain `int64` → races return | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -race ./node/ -count=1` | AUTO (`go test`) |

## Closure Gate Register — device-proof / live-relay / soak / decision / deploy (NOT host unit tests)
> These close by **documented evidence**, not a host assertion. `mutation = N/A — <category> closure gate` is the justified entry for the matrix's mutation column. Every row is **deferred-not-waived**. Scenario ids shown `<N>` are UNDEFINED until assigned (see Gaps).

| CV | Plan | Category | Named proof / scenario | Literal acceptance command | Blocking dep |
|---|---|---|---|---|---|
| CV-01 | FDC-10 | prereq (**review + git-merge — git op, not impl**) | `TC-10-01..05` + miniredis P-E (**already committed on `new-orbit`, clean tree**) | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... ; go test -tags integration ./...` | none (code committed; awaiting code-review + merge to main) |
| CV-02 | 07/08/09/11/12 | gomobile-rebuild | new exported bridge fns; native dispatch (Swift/Kotlin) | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./... ; make lint` → rebuild `.xcframework`/`.aar` (revert `testdata/interop_vectors.json`) | CV-01 |
| CV-03 | 09/10 | deploy | unified relay (Redis + presence_set + wake-gate) → ≥2 front-ends, 1 Redis | n/a (ops) — opt. `go test -tags integration ./...` vs live Redis | CV-01 + live-relay-env |
| CV-04 | FDC-10 | deploy | relay #2 + WSS/QUIC into client pool | n/a (ops) | CV-03 |
| CV-05 | FDC-10 | deploy | ops runbook (Redis flip / pool / gauge) | n/a (doc) | CV-03 |
| CV-06 | FDC-10 | live-relay | `relay_backend_durable=1` every front-end | `curl -s http://<relay>:2112/metrics \| grep relay_backend_durable` | CV-03 |
| CV-07 | 06/07/08/09/12 | host-ci | `classify_path()` cases + dcutr proof harness + 1:1 device orchestrator | `./scripts/check_reliability_simulation_discovery.sh` | none (RED until authored) |
| **CV-08** | **FDC-11** | **device-proof ⭐KEYSTONE** | **D1 two-phone same-WiFi LAN-direct win, both OS** | **n/a (manual two-phone; /sims N/A — sim shares bonsoir)** | **CV-02** |
| CV-10 | FDC-11 | device-proof | `lan_dial_test.go::…UpgradesRelayConnToDirect` real-circuit half | `…go test ./...` + manual 2-phone | CV-02 |
| CV-11 | FDC-12 | device-proof | `dcutr_upgrade_proof_test.dart` TC-12-12 | `/sims 1to1 --only <N>` | CV-02 + CV-07 |
| CV-12 | FDC-12 | device-proof | TC-12-13 symmetric-CGNAT negative | `/sims 1to1 --only <N>` | CV-02 + CV-07 |
| CV-15 | FDC-09 | device-proof | TC-09-20 iOS visible-wake (not silent-throttled) | `check_…discovery.sh ; /sims <scope> --only <N>` (+2-device) | CV-02 + CV-03 |
| CV-16 | FDC-09 | device-proof | TC-09-21 `presence_set{background}` lands pre-suspend | `/sims <scope> --only <N>` (FDC-S3 Method 2) | CV-02 + CV-03 |
| CV-17 | FDC-09 | device-proof | TC-09-22 presence TTL tune (FDC-S3 Method 1) | n/a (manual device) | CV-03 |
| CV-18 | FDC-09 | live-relay | TC-09-24 old-relay `Unknown action: presence_set` degrade | `/sims <scope> --only <N>` (old+new relay) | CV-03 |
| CV-20 | FDC-09 | device-proof | TC-09-23 non-contact cannot wake (gate e2e) | `/sims <scope> --only <N>` (2-device+relay) | CV-19 |
| CV-21 | FDC-08 | live-relay | `relay_presence_get_smoke_test.dart::LR1` | `./scripts/run_test_gates.sh transport ; /sims 1to1 --only <N>` | CV-02 + CV-03 |
| CV-22 | FDC-08 | live-relay | LR1 TTL constants (FDC-S3 Methods 1/2/5) | `/sims 1to1 --only <N>` | CV-03 |
| CV-23 | FDC-07 | device-proof | TC-07-05 cold T_circuit ≤3s + reserve_dispatch | `/sims 1to1 --only <N>` | CV-02 |
| CV-24 | FDC-07 | device-proof | TC-07-06 early mDNS + LAN opportunistic | `/sims 1to1 --only <N>` | CV-07 |
| CV-25 | FDC-04 | device-proof | `warm_peer_lan_aware_smoke_test.dart::TC-04-15` warm-open=local | `check_…discovery.sh ; /sims 1to1 --only <N>` | CV-07 |
| CV-26 | FDC-04 | device-proof | network-change re-warm fires | `/sims 1to1 --only <N>` | device hw |
| CV-27 | FDC-04 | device-proof | TC-04-05 cold notif-tap PS-3 no-op | n/a (manual device) | device hw |
| CV-29 | FDC-06 | device-proof | T8 open-send-lock delivers (N≥3 burst; **2nd-iOS-major WAIVED 2026-06-28** — run on the iOS 26.5 pair) | `/sims <scope> --only <N>` (single-msg now; burst needs plan 170) | **plan 170** (N≥3 burst) + CV-06 (durable custody) |
| CV-30 | FDC-13 | device-proof | real-wire `transport:upgraded`→badge | n/a (manual device) | CV-11/CV-13 |
| CV-32 | FDC-14 | device-proof | badge reaches `onlineDirect` on real LAN pair | n/a (manual device) | CV-08 (+ FDC-14b producer) |
| CV-33 | FDC-15 | gomobile-rebuild | native `mediaLanSend` + `media:lan_received` emit | n/a (rebuild) | CV-08 + FDC-15 host catalog |
| CV-34 | FDC-15 | device-proof | D1 two-phone LAN media (`/mknoon/media-lan/1.0.0`) | n/a (manual device; toggle `EnableLibp2pLanMedia` ON) | CV-33 + CV-09 |
| CV-35 | FDC-S6 | deploy | soak+baseline binaries `--dart-define=FDC_FLOW_LOG=1` | `flutter build (profile) --dart-define=FDC_FLOW_LOG=1` | CV-02 + CV-09 |
| **CV-36** | **FDC-S6** | **wall-clock-soak** | win-rate ≥95% Wilson-LB, ≥385 sends/dir, ≥14d, 3 platform-dirs | `fdc-s6-measurement/fdc_s6_capture.sh + fdc_s6_parse.py` | CV-08 + CV-09 + CV-35 |
| CV-37 | FDC-S6 | device-proof | bonsoir-fed-dial reliability both OS | `fdc-s6-measurement/fdc_s6_parse.py` | CV-08 |
| CV-38 | FDC-S6 | wall-clock-soak | double-delivery by leg-pair | `fdc_s6_parse.py` | CV-36 |
| CV-39 | FDC-S6 | wall-clock-soak | failure-delta ≤ +1.0pp (Newcombe CI) | `fdc_s6_parse.py` | CV-36 |
| CV-40 | FDC-S6 | decision-verdict | per-component retire/keep → VERDICT block; Status open→closed | n/a (doc) | CV-39 (+ CV-34 OR relay-CDN-only acceptance for retire-media) |
| CV-43 | FDC-S0 | host-ci | M1b/M5 Go benchmarks After | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ -run TestBenchmark -v \| grep BENCHMARK` | CV-23/24 + FDC-S1 final |
| CV-44 | FDC-S0 | host-ci | M8 reaction-to-offline After (FDC-18) | n/a (FDC-18 gate) + device smoke | FDC-18 (landed) |
| CV-45 | FDC-S0 | live-relay | M9 inbox durability survives relay restart | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | CV-01/03/06 |
| CV-46 | FDC-S0 | device-proof | M1/M2/M4/M5/M7 device scorecard captures | `SELECT transport,COUNT(*)…` + TransportMetrics + ≥10 manual trials | device + relay + CV-08 |
| CV-47 | FDC-S0 | wall-clock-soak | M6 LAN win-rate (REUSE CV-36 soak) | n/a (read `transportMix()` over ≥14d) | CV-36/CV-40 + CV-09 |
| CV-48 | FDC-S0 | host-ci | M10 host-gate floor After | `./scripts/run_test_gates.sh 1to1 ; feed ; transport` | epic close |
| CV-49 | FDC-S0 | decision-verdict | scorecard Before/After/Delta + frozen-baseline/close hashes | n/a (doc); pull FDC-S1 #5 + FDC-S6 #6 | epic close + soak (LAST) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the staged flag-flips add *default* state. Each flip (CV-09/13/19/28) has a host lock asserting the new default AND the kill-switch/override path still forces OFF (CV-28 explicitly). **Row: CV-28 (+ override assert).**
- **Sibling-surface consistency:** the `wakeTokenGateEnforced` flip (CV-19) gates wake-access; its sibling is the *send-side attach* (CV-14) — the gate must not enforce before the attach saturates. Locked by the ship-order in CV-14/CV-19. **Row: CV-14↔CV-19 ship-order.**
- **Destructive-action side-effects:** the relay redeploy (CV-03) must NOT wipe queued custody — FDC-10's Redis backend + `messageId` dedup preserve it; old-client safety = same endpoint/peer-ID. **Row: CV-06 durability gauge + CV-45 failover.** WS-chat-removal (CV-41) deletes the WS advertise path — its spawned plan asserts what's removed vs preserved (bonsoir kept).
- **Invariant re-verification under new transitions:** flipping `EnableLibp2pLANDial` (CV-09) re-routes every same-WiFi peer incl. group members → `pubsub_delivery_test.go` / `groups` must stay green AFTER the flip, not just before. **Row: CV-09 + `./scripts/run_test_gates.sh groups` preservation.**

## Invariants (locked by tests)
- INV-1: pause-flush ships ON with a working kill-switch (CV-28 + override assert).
- INV-2: `wakeTokenGateEnforced` never flips before send-side token presentation saturates (CV-14 lands+saturates → CV-19); the kill-switch posture at deploy is OFF (NET-REL-07).
- INV-3: each prod flag default-on is mutation-locked (CV-09/13/19/28 re-red on revert).
- INV-4: the relay redeploy is additive — old clients keep texting (same endpoint/peer-ID, gate OFF, opaque-routing OUT); group pubsub unchanged after `EnableLibp2pLANDial` (CV-09 + groups preservation).
- INV-5: the FDC-S6 verdict is issued only on real soak data meeting ≥95% Wilson-LB / ≤+1.0pp failure-delta / ≥14d (CV-36/39/40).
- INV-RED-FIRST + INV-MUTATION-VERIFIED apply to the host-RED rows; device/soak/decision rows close on documented evidence (deferred-not-waived).

## Step-By-Step Implementation Plan
> Dependency-ordered. `git status --short` first (shared `new-orbit` tree, 5 concurrent sessions — do NOT revert others' work). All Go gates under `GOTOOLCHAIN=go1.25.0`; revert `testdata/interop_vectors.json` after Go runs.

**P4.0 — One-time prerequisites (unblock everything):**
1. **Land FDC-10** (CV-01): review+merge the Redis backend/gauge/pool host code; host floor + `-tags integration` green. *Stop-if:* FDC-10 review surfaces a durability defect → fix in FDC-10, do not proceed to deploy.
2. **Author the host-RED rows.** CV-14 (send-side wake-token attach, RED-first); the default-flip locks CV-09/13/19 written but parked default-OFF; CV-28 (pause-flush default-on) is **already shipped** (no work). **CV-50 — apply the FDC-S1 `processStartEpochMs`→`atomic.Int64` fix** (`node.go:67/:268/:2017`) so `go test -race ./node/` is clean; it **blocks CV-03 + the FDC-08/11 `-race` gates** and is host-fixable now (one writer on the shared `node.go`).
3. **Author the missing harness** (CV-07): `classify_path()` cases + `integration_test/dcutr_upgrade_proof_test.dart` + the 1:1 device-real `--scenario` orchestrator; assign every device scenario its `--only N` index. *Stop-if:* `check_reliability_simulation_discovery.sh` doesn't list a new scenario → fix `classify_path`, not the test.
4. **Consolidated gomobile rebuild** (CV-02) + native dispatch wiring; **relay redeploy** (CV-03..06) behind the SAME endpoint/peer-ID, `wakeTokenGateEnforced=OFF`, opaque-routing OUT; confirm `relay_backend_durable=1` (CV-06).

**P4.1 — Device-proof campaign (batch on one 2-device same-WiFi rig + real relay + APNs):**
5. **FDC-11 D1 (CV-08) — KEYSTONE first.** Then, on D1-GREEN, flip `EnableLibp2pLANDial` + lock (CV-09) and re-run `groups` (INV-4).
6. Run the rest: CV-10/11/12 (Dcutr → flip CV-13), CV-15/16/17/18/20 (FDC-09; flip CV-19 only after CV-14 saturates), CV-21/22 (FDC-08 LR1), CV-23/24 (FDC-07), CV-25/26/27 (FDC-04), CV-30 (FDC-13), CV-32 (FDC-14 badge), CV-33/34 (FDC-15 media). CV-29 (FDC-06 T8) only after **plan 170** lands.

**P4.2 — 14-day soak (wall-clock):** 7. Build soak binaries `--dart-define=FDC_FLOW_LOG=1` (CV-35); run ≥14d / ≥385 sends/dir (CV-36); parse win-rate/double-delivery/failure-delta (CV-36/38/39) + bonsoir-dial reliability (CV-37).

**P4.3 — FDC-S6 verdict:** 8. Fill the VERDICT block per-component; Status open→closed (CV-40). If retire-chat → spawn + run WS-chat-removal (CV-41, full RED). If retire-media → gated on CV-34 or recorded relay-CDN-only acceptance.

**P4.4 — Staged flag-flips (interspersed, each at its gate):** CV-09 (post-D1), CV-13 (post-FDC-12 close), CV-19 (post-CV-14 saturation + CV-20), CV-28 (now). *None auto; all reversible.*

**P4.5 — FDC-S0 re-measure = epic close:** 9. Captures CV-42..48; populate the scorecard Before/After/Delta + frozen-baseline/close-commit hashes (CV-49, LAST). Reuses FDC-S1 #5 + FDC-S6 #6.

## Risks And Edge Cases
- **Enforce-before-attach** → all 1:1 pushes hard-silenced (NET-REL-07 break) → pinned by INV-2 (CV-14 saturates before CV-19).
- **Relay redeploy moves endpoint/peer-ID** → old clients can't connect at all → Scope Guard "same endpoint/peer-ID"; pinned by CV-06 + a from-old-client smoke.
- **`EnableLibp2pLANDial` re-routes group members** → `groups`/`pubsub_delivery_test.go` regression → CV-09 + groups preservation.
- **Device scenario `--only N` drift** → `/sims` runs the wrong scenario → CV-07 assigns + `check_…discovery.sh` verifies before each `/sims`.
- **Soak heavy-tailed / under-powered** → Wilson-LB / Newcombe CI (CV-36/39) guard against deciding on noise; ≥385 sends/dir mandatory.
- **Go 1.26.x panic** (`where's my session ticket?`) → `GOTOOLCHAIN=go1.25.0` on every Go gate; revert `testdata/interop_vectors.json`.

## Device/Relay Proof Profile
- **Host-only closure:** CV-28, CV-14, CV-09/13/19 (flag locks), CV-42, CV-48 (host gates), CV-43 (Go benchmarks), CV-45 (failover).
- **Requires device (closure gate) — ✅ RIG AVAILABLE 2026-06-28** (iPhone 11 + iPhone 13 @ iOS 26.5 + a physical Android, same WiFi): CV-08 (KEYSTONE), CV-10/11/12/15/16/17/20/23/24/25/26/27/29/30/32/34/37/46 — runnable now (real bridge after the CV-02 gomobile rebuild; real relay/APNs after CV-03; DCUtR CV-11/12 needs one peer on cellular for cross-NAT; CV-29 2nd-iOS-major waived).
- **Requires live-relay-env (present locally but PROD-GATED — needs explicit authorization):** CV-03/06/15/16/18/21/22/45. (`.env` EC2_HOST/Redis/Grafana + `se.pem` are on this machine but gitignored; connecting/deploying mutates production.)
- **Wall-clock (≥14d):** CV-36/38/39/47.
- **Decision:** CV-40 (S6 verdict), CV-49 (S0 scorecard).
- Flip any feature flag ON only AFTER its device evidence. Relay defaults: see `/sims` / `p2p_bridge_client.dart`.

## Acceptance Gates  (literal — copy/paste)
```bash
git status --short                                   # snapshot shared tree first

# P4.0 — FDC-10 land + Go host (GOTOOLCHAIN pin mandatory)
cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... && go test -tags integration ./...   # CV-01/45
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./... && go test -race ./... && make lint        # CV-02/14/09/13/19
git checkout -- go-mknoon/testdata/interop_vectors.json 2>/dev/null || true                   # revert test rewrite (path is go-mknoon/testdata/, NOT .../node/)

# host-RED code rows
./scripts/run_host_test_gates.sh core-host-all       # CV-28 (pause-flush default-on)
./scripts/run_test_gates.sh 1to1                     # CV-42/CV-48 (M3 ≈0, floor)  — reconcile FDC-13 count (CV-31)
./scripts/run_test_gates.sh groups                   # INV-4 preservation AFTER EnableLibp2pLANDial flip

# harness registration (CV-07) — every new scenario MUST list
./scripts/check_reliability_simulation_discovery.sh

# device-proof campaign (assign --only N via CV-07 first)
# /sims 1to1 --list ; then per row: /sims 1to1 --only <N>   (CV-11/12/15/16/18/20/21/23/24/25)
# CV-08 (FDC-11 D1) + CV-34 (FDC-15 media) = manual two-phone (sim shares bonsoir → /sims N/A)

# live-relay durability gauge (CV-06)
curl -s http://<relay-host>:2112/metrics | grep relay_backend_durable   # expect: 1 on every front-end

# soak (CV-36..39) + scorecard (CV-43/49)
fdc-s6-measurement/fdc_s6_capture.sh   # ≥14d, ≥385 sends/dir ; then fdc_s6_parse.py
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/ -run TestBenchmark -v 2>&1 | grep BENCHMARK   # CV-43

# Hygiene
flutter analyze            # 0 new
git diff --check
```

## Known-Failure Interpretation
- **Expected RED:** the flag-default-flip locks (CV-09/13/19) are RED until their device gate closes — that's correct; do not flip early.
- **Environment blocker (NOT product):** live-relay rows (CV-03/06/15/16/18/21/22/45) — the env is **present locally but PROD-GATED** (touches live prod → needs explicit authorization), not absent; missing 2-device rig → all device rows. Record as deferred-not-waived, not failures.
- **Blocked-external:** CV-29 (FDC-06 T8) until plan 170; CV-44 (M8) rides FDC-18 (landed).
- **Scope drift (BLOCKING):** any host-gate regression (`1to1`/`feed`/`groups`/`transport`/`core-host-all`) — convergence must keep them green.
- **Go FAIL with 0 `--- FAIL:` lines** = the Go 1.26.x quic-go panic → re-run under `GOTOOLCHAIN=go1.25.0`.

## Done Criteria
- [ ] FDC-10 landed + deployed; `relay_backend_durable=1` on every front-end (CV-01..06).
- [ ] **CV-50** FDC-S1 `processStartEpochMs`→`atomic.Int64` fix landed; `GOTOOLCHAIN=go1.25.0 go -C go-mknoon test -race ./node/ -count=1` clean (0 races) — unblocks CV-03 + the FDC-08/11 `-race` gates.
- [ ] gomobile rebuild + native dispatch shipped (CV-02/33); relay redeploy additive, old clients verified texting (NET-REL-07).
- [ ] Harness authored + every device scenario assigned `--only N` and listed by `check_…discovery.sh` (CV-07).
- [ ] **FDC-11 D1 GREEN both OS (CV-08)** → `EnableLibp2pLANDial` flipped + locked (CV-09) → `groups` green.
- [ ] FDC-12 device campaign closed (CV-11/12) → `EnableDcutrUpgrade` flipped (CV-13).
- [ ] FDC-09 send-side wake-token attach landed + saturated (CV-14) → `wakeTokenGateEnforced` flipped (CV-19) → TC-09-23 green (CV-20); CV-15/16/17/18 device/live-relay closed.
- [ ] FDC-08 LR1 + TTL tune (CV-21/22); FDC-07 (CV-23/24); FDC-04 (CV-25/26/27); FDC-13 outgoing (CV-30); FDC-14 badge (CV-32); FDC-15 media D1 (CV-34).
- [x] FDC-06 pause-flush default-on — **already shipped by FDC-06 (CV-28)**; [ ] T8 closed after plan 170 (CV-29).
- [ ] 14-day soak meets ≥95% Wilson-LB / ≤+1.0pp / ≥385 sends-dir (CV-36/38/39); FDC-S6 verdict issued + Status closed (CV-40); conditional WS-removal run if retire (CV-41).
- [ ] FDC-S0 re-measure scorecard populated Before/After/Delta + hashes (CV-42..49); device-only metrics marked deferred-not-waived.
- [ ] `flutter analyze` 0-new; `git diff --check` clean; no Scope Guard violation.

## Scope Guard (hard "Do not")
- **Do NOT** flip any prod flag (`EnableLibp2pLANDial`/`EnableDcutrUpgrade`/`wakeTokenGateEnforced`/`kFdcPauseFlushEnabled`/`EnableLibp2pLanMedia`) ahead of its device/saturation gate.
- **Do NOT** enforce `wakeTokenGateEnforced` before CV-14 send-side attach saturates (hard-silences pushes).
- **Do NOT** change the relay endpoint/peer-ID, ship opaque-routing, or enable the wake-gate in this deploy (old-client/NET-REL-07 safety).
- **Do NOT** edit landed sub-plan host code — re-run their gates as preservation only.
- **Do NOT** issue the FDC-S6 verdict on partial soak (< 14d / < 385 sends-dir / < both OS).
- **Do NOT** `git checkout`/`stash`-revert shared files on the concurrent `new-orbit` tree.
- **Do NOT** author WS-chat/media-removal before the CV-40 retire verdict.

## Accepted Differences / Intentionally Out Of Scope
- **Live-relay-env** is gitignored but **present on this machine** (`.env`: EC2_HOST `13.60.15.36`/Redis/Grafana + `se.pem`) — its live-relay rows are reachable *in principle* but **connect/deploy to LIVE PROD → require explicit authorization**; deferred-not-waived until that go-ahead, not because the env is absent.
- **plan 170** (send-button) owns FDC-06 T8's N≥3 burst.
- **FDC-01 / FDC-18 / FDC-S1** RED rigor lives in their own plans; S0 only re-runs + aggregates.
- **FDC-14b producer** (onlineDirect signal source) is being built separately this session (Route B); CV-32 device-proofs the badge once it + FDC-11 land.
- **Shared presence-TTL tuning** (CV-17/CV-22) is one decision surfaced as two named rows — tune once, record in both.

## Dependency Impact
- **Blocks epic close:** the FDC-S0 scorecard (CV-49) is the epic's done-signal; it depends on the entire chain.
- **FDC-11 D1 (CV-08) is the single keystone** — it gates the soak, FDC-15, FDC-13-outgoing, FDC-14b ✦, and the scorecard's LAN-win metric.
- **FDC-10 (CV-01)** gates the whole durability deploy chain + S0 M9.
- **plan 170** gates CV-29.

## Reviewer Findings
Closure-orchestration plan: host-RED rigor correctly scoped to the 7 code-bearing rows; the 42 device/live-relay/soak/decision/deploy rows are honestly tracked as gated criteria with literal commands + deferred-not-waived, not as faux host tests. Matrix has zero empty cells for host-RED rows; the register supplies tier/command/registration/blocking-dep for the rest with justified `mutation = N/A — <category> closure gate`. Open external dependencies (FDC-10 land, live-relay-env, plan 170, scenario-id assignment, missing harness) are surfaced, not hidden.

## Arbiter Decision
Structural blockers: none for the host-RED rows (implementation-ready now: CV-14, CV-28). Deferred details: every device/soak/deploy/decision row is gated as documented. Accepted differences: live-relay-env + plan 170 + FDC-01/18/S1 rigor are external. **Hand off to execution: start P4.0 (land FDC-10 + author CV-07 harness + CV-14/CV-28 host-RED), then the FDC-11 D1 keystone.**

## Final Execution Verdict
Verdict: (pending) | Files changed: — | Tests run (+counts): — | Blocking: FDC-10 land, gomobile rebuild, live-relay-env, 2-device rig, plan 170, 14-day soak | QA verdict: — | Non-blocking follow-ups: WS-removal plan(s) per CV-40 verdict.
