# VC-09 — Call reliability hardening + quality metrics  (Feature Improvement)

Status: accepted (post /tdd-review)
Spec: free-text intent (no formal NN spec) — VC-00 story row VC-09 (`Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md:74`) + the VC-09 story brief. Closes the epic's reliability/metrics contract (VC-00 "Metrics goals" table).

---

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-13 | Evidence Collector | 5 grounding digests (metrics-telemetry, platform-av-push, relay-server-ops, signaling-messaging, harness-conventions) + re-verified anchors on HEAD: `lib/core/services/connectivity_signal.dart:21-54`, `p2p_service_impl.dart:186-188,536-537,2749`, `flow_event_emitter.dart:6,202-218`, `go-relay-server/inbox.go:2033,2066-2278`, `metrics.go:10-13,250-262`, `main.go:102-107,229-236`, `go-mknoon/node/inbox.go:419`, `go_bridge_client.dart:128-140`, `run_test_gates.sh:21,538,870,1036-1039`, `run_host_test_gates.sh:144-184`, `check_reliability_simulation_discovery.sh:380-392` | all seams grounded; verified-absent on HEAD: `interfaceChange*` in lib/test, `call_quality` anywhere, `relay_call_` metrics, `iceTransportPolicy`/`CallPrivacy` in lib | draft plan |
| 2026-07-13 | Planner | tier-matrix, sufficiency-checklist, FDC-03 exemplar, VC-00 roadmap | 20 spec cases across unit/widget/Go-host/relay-Go/device-proof; relay redeploy required (rule 2); executes only on the post-VC-05 tree (stop-if) | write RED catalog + matrix |
| 2026-07-13 | Reviewer (sufficiency) | this file vs sufficiency-checklist | all gates pass after fixes (matrix zero-empty-cells; PROD-CRITICAL leg named; registration per test; refuted-findings section present) | hand to Arbiter |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | EC2 redeploy + live probe | | (redeploy + :2112 probe evidence) | live metric visible | |
| | measurement runsheet | | (VC-09 RESULTS doc rows) | <10s recovery met/missed | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

---

## Source Of Truth

- **Roadmap:** `VC-00-roadmap.md` — VC-09 story row (:74), Metrics goals table (:147-159, VC-09 owns the getStats row and closes the loop), and the 7 non-negotiable rules (:103-143). Rules 1, 2, 3, 4, 5, 6 are restated below where this plan touches them.
- **Gate definitions:** `scripts/run_test_gates.sh` (script wins over prose); `scripts/run_host_test_gates.sh`; discovery `scripts/check_reliability_simulation_discovery.sh`.
- **Landed-sibling contracts (verify at execution start — VC-09 runs on the committed post-VC-05 tree, never on today's HEAD):** VC-05's `lib/features/call/` feature (CallSessionController / peer-connection factory / in-call screen / call device orchestrator), VC-04's `call_*` signaling channel (callId + seq envelope contract), VC-03's TURN creds. File names below marked **[VC-05 contract anchor]** are the roadmap-defined shapes; re-resolve exact paths against the landed VC-05/VC-04 diffs before writing a single test.
- **Telemetry conventions:** `lib/core/utils/flow_event_emitter.dart` (sanitize-always, gate = mutable `flowEventLoggingEnabled`, default `kDebugMode` at `:6`, force-on in profile via `--dart-define=FDC_FLOW_LOG=1`, `lib/main.dart:320-330` — NEVER describe flow events as "debug-only"); `go-relay-server/metrics.go` promauto `relay_` convention; privacy pins `test/core/debug/transport_metrics_privacy_test.dart`.
- **Relay ops:** redeploy procedure of `Test-Flight-Improv/142-relay-media-push-payload-too-large-tdd-plan.md:141-150`; additive-action back-compat contract `go-relay-server/NOTES.md:114-121` + `inbox.go:2276-2277`.
- **Measurement doc conventions:** `Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/FDC-S0-baseline-and-improvement-measurement.md` (+ its RESULTS twin) — freeze table, median+p90/p95 never mean, deferred-not-waived device rows.
- Line numbers drift: every anchor cited here was re-verified on HEAD `new-orbit` 2026-07-13; re-verify each anchor again on the post-VC-05 tree before editing.

---

## Session Classification

**implementation-ready** — with one hard sequencing gate: **VC-09 starts only after VC-05 is merged and its gates are green** (VC-08 desirable for the video-degrade rows; see Stop-if). All client behavior is host-testable through injectable seams (fake stats source, fake signaling sender, fake connectivity stream, fake clock); the relay half is plain Go tests; the network-switch and forced-relay proofs are Android device+emulator rows per VC-00 rule 1 (restated below).

---

## Exact Problem Statement

After VC-05 (audio) and VC-08 (video), a 1:1 call works — until the network moves. There is **no ICE restart**: a WiFi→cellular switch (the single most common mid-call event on a phone) kills the media path permanently; flutter_webrtc's peer connection keeps a dead candidate pair and the call dies with no recovery attempt, no "reconnecting" feedback, and no recorded reason. The app already has an OS connectivity source (`connectivity_plus` ^6.1.0, `pubspec.yaml:70`) wired into transport re-warm via `connectivityRestoredSignal()` → `P2PServiceImpl.onNetworkChanged` (`lib/main.dart:2463-2467`, `lib/core/services/p2p_service_impl.dart:186-188,536-537,2749`) — but that detector (`restoredEdges`, `connectivity_signal.dart:33-54`) fires **only on none→connected edges**, so a direct WiFi→cellular interface swap (connected→connected) emits nothing; calls need an interface-change detector that does not exist.

Second, **no call leaves a quality trail**. The epic's contract (VC-00 metrics table :156: "Call setup time, ICE pair type, loss/RTT/jitter, drop cause → flow events + relay Prometheus counters", owner VC-05/**VC-09**) is unclosed: there is no periodic `getStats` sampler, no end-of-call summary, no drop-cause taxonomy, and the relay has zero call metrics (`grep relay_call_ go-relay-server/metrics.go` = 0). "Why was this call bad?" is unanswerable — the exact question the epic exists to answer.

Third, two product-grade controls are missing: a Signal-style **"always relay" privacy toggle** (force `iceTransportPolicy: 'relay'` so the peer never learns your IP) and a **low-bandwidth degradation ladder** (sustained loss/bitrate collapse should drop video before the call becomes unusable audio+frozen video).

**What must improve:** calls survive a real network switch on a real device (reconnect < 10 s, pre-committed); every call emits privacy-clean quality samples + one summary; the relay aggregates fleet-level pair-type/drop-cause/TURN-share counters (opt-in, rate-limited, zero peer ids); the relay-only toggle and the auto-degrade ladder exist, both polarities test-locked.

**What must stay unchanged → preserved-green sentinels:** VC-05/VC-08 call setup/answer/video behavior (capture their suites green at execution start); the five transport-diagnostic events + `TransportMetrics` privacy pins (`test/core/debug/transport_metrics_privacy_test.dart`); `IncomingMessageRouter` unknown-type forward-compat (`test/core/services/incoming_message_router_test.dart:256,265`); relay push closure (`go-relay-server` `^TestRelayNotificationClosure_`); the existing `restoredEdges` drain behavior (`test/core/services/connectivity_signal_test.dart`); `go_bridge_client_test.dart` cmd-map pin; the `1to1` / `transport` gates.

---

## Root Cause (verify → refute confirmed)

This is a feature-improvement plan; "root cause" = verified missing mechanisms (all re-checked on HEAD 2026-07-13):

1. **No interface-change signal.** `restoredEdges` (`lib/core/services/connectivity_signal.dart:33-54`) seeds `wasConnected=false` and emits only on `!wasConnected && isConnected`; a `[wifi]→[mobile]` event (both connected) is swallowed at `:41-45`. `grep -rn interfaceChange lib/ test/` = 0 hits. **The seam:** `connectivity_plus`'s `onConnectivityChanged` (already a dependency) + a new pure detector beside `restoredEdges`, consumed by the call feature — NOT by re-using `P2PServiceImpl.onNetworkChanged` (:2749), which is the transport re-warm path with its own 5s flap debounce and single-active-peer semantics.
2. **No stats sampler / no call flow events.** `flow_event_emitter.dart` exists (sanitize-before-sink-and-gate, `:202-218`) but nothing call-shaped feeds it; `grep -rn call_quality lib/ go-mknoon/ go-relay-server/` = 0.
3. **No relay call action or metrics.** `HandleInboxStream` switch (`go-relay-server/inbox.go:2066-2278`) has 13 cases, none call-related; unknown action → `{"status":"ERROR","error":"Unknown action: X"}` (`:2276-2277`) — the additive-action seam. `metrics.go` has no `relay_call_*`.
4. **No client→relay report primitive.** `go_bridge_client.dart` cmd map has `relay:presence_get`/`relay:presence_set`/`peer:ping` (`:128-140`) but nothing call-quality; `go-mknoon/node/inbox.go` has the `RelayPresenceSet` client-request precedent (`:419`) to mirror.
5. **No `iceTransportPolicy` control** anywhere in lib/ (grep = 0), no settings entry, no persistence model.

**Refuted / do-NOT-re-introduce (from the digests' adversarial passes — carried corrections):**
- "Flow events are debug-only" — REFUTED. Gate is the mutable `flowEventLoggingEnabled` (default `kDebugMode`, `flow_event_emitter.dart:6`), force-enabled in profile/release via `--dart-define=FDC_FLOW_LOG=1` (`lib/main.dart:320-330`). Device runsheets depend on the profile-build override; sanitization is unconditional (runs before sink AND gate check).
- "Transport diagnostic event set is four events" — REFUTED. It is FIVE (incl. `transport:downgraded`, `bridge.dart:61-81`). New call diagnostic events routed through the Go→Dart pipe would need BOTH the `bridge.dart` allowlist and the `go_bridge_client.dart` switch — VC-09 avoids that pipe entirely (sampler is Dart-side, from flutter_webrtc), so no allowlist edits.
- "Go ack proves delivery/handling" — REFUTED (ordering). For non-deferred types (all `call_*`), Go writes `{"ack":true}` BEFORE emitting `message:received` (`go-mknoon/node/node.go:1854-1860`). VC-09's re-offer sender must judge reconnect success by **ICE connection state**, never by signaling ack.
- "go-relay-server has zero pion modules" — REFUTED. `pion/turn/v2` etc. are already indirect deps (`go-relay-server/go.mod:96-112`). Irrelevant to VC-09 (no TURN code here — VC-03 owns), recorded so nobody "fixes" go.mod.
- Stale line cites: `relay_stream_duration_seconds` is `metrics.go:257-262` (not :265-278); `classify_path()` is `run_test_gates.sh:870`; proof-glob branch `:1036-1039`; the `all` gate Go wiring is `:1149-1158` (bridge gate + relay-all, not relay-only).

---

## Real Scope

**In scope (VC-09):** Items 5-6 ride this story because both are pure consumers of the sampler (5) and the pc-factory param (6) built here — splitting them re-opens the same files twice; the epic row (VC-00:74) bundles them for that reason.
1. `interfaceChangeEdges(...)` pure detector in `lib/core/services/connectivity_signal.dart` (emits on connected-set change while connected AND on restored edges; silent on →none).
2. `lib/features/call/application/call_reconnect_controller.dart` (new): on interface-change signal OR ICE `disconnected/failed` → `restartIce()` + re-offer via VC-04 signaling (same `callId`, `seq+1`); `reconnecting` call-state + bounded retry (≤3 restarts, 20 s deadline) → `ended(failed, cause)`; kill-switch `MKNOON_CALL_ICE_RESTART` (Dart-side dart-define, default ON; OFF = pre-VC-09 fail-fast, test-locked — rule 3). Re-offers reuse VC-04's landed offer envelope type verbatim — a restart offer is the same type with the same `callId` and a higher `seq`; the callee distinguishes it by having an active call for that `callId` (TC-04). Never mint a new `call_*` type (Scope Guard).
3. Callee-side re-offer application: same `callId` + higher `seq` applied; stale/duplicate `seq` ignored (idempotent).
4. `call_quality_sampler.dart` (new): every **3 s** (within the 2-5 s brief window) pull `getStats` through an injectable stats-source seam; whitelist-extract numerics + candidate-pair type (host→`direct`, srflx/prflx→`punched`, relay→`turn`); emit `CALL_QUALITY_SAMPLE` flow events + one `CALL_QUALITY_SUMMARY` (setup ms, duration, final pair type, RTT median/p95, jitter, loss %, bitrate, drop cause) per `flow_event_emitter` conventions. Raw stats maps never reach `emitFlowEvent`.
5. Auto video-off degradation ladder: **3 consecutive samples (~9 s) with loss ≥ 12% OR video send bitrate < 60 kbps** → video track disabled via VC-08's video-mute seam, `CALL_DEGRADE_VIDEO_OFF` emitted, never auto-re-enabled; kill-switch `MKNOON_CALL_AUTO_DEGRADE` (default ON; OFF polarity test-locked — rule 3). Thresholds: loss threshold = 12% (the 10% unusable-video floor + 2pp flap margin so ambient 10-11% loss never triggers); 60 kbps is below any usable video encode; 3-sample persistence avoids single-sample flap.
6. "Always relay" toggle: `CallPrivacyPreferences` model + `SecureKeyStore` load/save (mirrors `media_download_preference_use_cases.dart:1-24`), settings card `settings_call_privacy_card.dart`, wired into VC-05's peer-connection factory as `iceTransportPolicy: 'relay'` vs `'all'`. Both polarities + reopen-durability test-locked. Latency/quality tradeoff documented in the card copy + RESULTS doc. Harness override pinned: `const kCallForceRelay = bool.fromEnvironment('MKNOON_CALL_FORCE_RELAY', defaultValue: false)`, consumed ONLY where the pc factory resolves policy — `effectivePolicy = kCallForceRelay ? 'relay' : prefValue` (override wins, never written to the store). TC-14 carries the precedence cases: override true + stored pref OFF → factory receives `'relay'`; override absent → stored value wins.
7. Relay `call_quality_report` action (additive, delegating named handler per `inbox.go:2027-2032` nolint rule): aggregate-only payload (enum pairType, enum dropCause, numeric setupMs/rttMedianMs/lossPct/durationS) → Prometheus `relay_call_reports_total{pair_type}`, `relay_call_drops_total{cause}`, `relay_call_setup_seconds{pair_type}` histogram with pinned `Buckets: {0.25, 0.5, 1, 2, 3, 5, 8, 13, 21, 30}` (setup-time scale; do NOT copy `relay_stream_duration_seconds`' 0.01-floor buckets, `metrics.go:257-262` — bucket choice is unfixable post-deploy without breaking Grafana history; TC-10 asserts the bucket list); enum clamp to `unknown` (label-cardinality + privacy guard); per-peer 30 s rate limit; env flag `RELAY_CALL_QUALITY_REPORT_ENABLED` default **off** (mirrors `loadDirectReactionPushEnabledFromEnv`, `main.go:102-107`); nothing persisted, no peer ids in any label or log line.
8. Client reporter: `report_call_quality_use_case.dart` + new `P2PService.reportCallQuality` primitive (bridge cmd `relay:call_quality_report` → `go-mknoon/node/inbox.go` client request mirroring `RelayPresenceSet` `:419`), fired once fire-and-forget on call end; gated by dart-define `MKNOON_CALL_QUALITY_REPORT` default **OFF** (privacy opt-in — rule 3) AND first-line `_allowsAccountNetworkSideEffects('p2p_call_quality_report', ...)` (rule 4); old relay's `Unknown action` ERROR → graceful skip (NET-REL-07 pattern).
9. **EC2 redeploy + live verification** (rule 2) — section below.
10. Measurement RESULTS doc `VC-09-reliability-quality-RESULTS.md` (FDC-S0 conventions): WiFi→cellular mid-call recovery **median < 10 s over 5 trials (pre-committed)**; TURN-forced quality baseline.
11. Device↔emulator e2e (rule 1): mid-call `adb shell svc wifi disable` on the USB device → reconnect proven; forced-relay call connects with pair type `relay`/`turn` asserted.

**Out of scope (owning story):** ring/background answer paths (**VC-06/VC-07**); codec work, camera switch, any new video UI (**VC-08**); TURN server internals/creds (**VC-03**); `call_*` envelope type definitions, TTL, glare (**VC-04** — VC-09 only *consumes* its channel with `seq+1`); circuit holding / DCUtR (**VC-01/VC-02**); new UI surfaces beyond the reconnecting state + the settings toggle; any client→server telemetry beyond the single aggregate report (no fleet export pipeline — the metrics-telemetry digest confirms none exists and VC-09 does not create one); Go `feature_flags.go` / `p2p_bridge_client.dart` flag-map edits (VC-09 flags are Dart-side dart-defines only — deliberately avoids the VC-00 shared-flag-file collision).

---

## Cross-Session Rules Restated (VC-00 :103-143 — the ones VC-09 touches)

- **Rule 1 (execution environment):** the implementing agent runs the full loop on a USB-connected Android device + Android emulator. Serials via `adb devices -l`; per-device suites `flutter test integration_test/<file> -d <serial>`; two-party orchestrator `-d <serialA>,<serialB>`. iOS legs: deferred-not-waived (orchestrator prints recipe, exits 0). See Execution Environment.
- **Rule 2 (EC2 redeploy):** this story touches `go-relay-server/` → not done until the relay is rebuilt, redeployed to `mknoun.xyz`/13.60.15.36 (systemd `relay-server`), and the live probe passes (`relay_call_reports_total` visible on :2112 after one reported call). Literal commands + rollback below.
- **Rule 3 (kill-switch + staged rollout):** `MKNOON_CALL_ICE_RESTART` (default ON), `MKNOON_CALL_AUTO_DEGRADE` (default ON), `MKNOON_CALL_QUALITY_REPORT` (default OFF) + relay env `RELAY_CALL_QUALITY_REPORT_ENABLED` (default off). Every OFF polarity (= revert path) is test-locked (TC-05, TC-16, TC-12).
- **Rule 4 (Move-feature gate):** the new network primitive `reportCallQuality` calls `_allowsAccountNetworkSideEffects('p2p_call_quality_report', ...)` first-line (pattern `p2p_service_impl.dart:555-572`, sibling tokens `:2339,:2409,:5114`). Test-locked (TC-12c).
- **Rule 5 (signaling semantics):** re-offers ride VC-04's fast-path-only `call_*` channel (never durable-inboxed, never retrier-swept), same `callId`, monotonic `seq`; Go acks non-deferred types BEFORE emit (`node.go:1854-1860`) so the reconnect controller treats signaling ack as "node received", judging success only by ICE state (TC-02/TC-04).
- **Rule 6 (gate hygiene):** every new `*_test.dart` classifies (completeness-check, `classify_path` at `run_test_gates.sh:870`); Go tests only via pinned invocations with `GOTOOLCHAIN=go1.25.0`; new go-mknoon gate copies the synthetic-path pattern (`run_host_test_gates.sh:144-184`); ONE_TO_ONE_TESTS array change → update `test-gate-definitions.md` + `test-gates-reference.md` + `_current-test-map.md` together; pass counts are never hardcoded — **capture green baseline at execution start**. Family-registration lock (epic-wide): **NO new test-family array this epic** (no `CALL_TESTS`) — headline call host tests append to ONE_TO_ONE_TESTS; any heavy two-party e2e that needs family registration rides `NIGHTLY_ONLY_TESTS` (`run_test_gates.sh:556`); VC-09's device proofs classify via the `_proof_test.dart` manual device-proof glob (`:1036-1039`) and run via the epic's call device orchestrator `integration_test/scripts/run_call_device_real.dart` (honoring the `--scenario` / `--list-scenarios` discovery contract).

---

## Files To Inspect Next

**Production (edited):**
- `lib/core/services/connectivity_signal.dart` (`restoredEdges` :33-54 — add `interfaceChangeEdges` beside it; do not touch `restoredEdges`).
- `lib/features/call/application/call_reconnect_controller.dart` (NEW), `call_quality_sampler.dart` (NEW), `call_auto_degrade_policy.dart` (NEW), `report_call_quality_use_case.dart` (NEW), `call_privacy_preference_use_cases.dart` (NEW).
- `lib/features/call/domain/models/call_quality_sample.dart`, `call_quality_summary.dart`, `call_privacy_preferences.dart`, `call_end_cause.dart` (NEW; drop-cause enum: `local_hangup|remote_hangup|ice_failed|reconnect_timeout|signaling_lost|media_stall|unknown`).
- **[VC-05 contract anchors — resolve exact paths on the landed tree]:** CallSessionController (state machine gains `reconnecting`; end transition fires sampler summary + reporter), peer-connection factory (gains `iceTransportPolicy` param), in-call screen (reconnecting banner), `integration_test/scripts/run_call_device_real.dart` orchestrator.
- `lib/features/settings/presentation/widgets/settings_call_privacy_card.dart` (NEW; template `settings_transport_diagnostics_card.dart`).
- `lib/core/services/p2p_service.dart` + `p2p_service_impl.dart` (`reportCallQuality` primitive; Move gate `:555-572`).
- `lib/core/bridge/go_bridge_client.dart` (cmd map `:128-140` gains `relay:call_quality_report`).
- `go-mknoon/node/inbox.go` (client request beside `RelayPresenceSet` `:419`), `go-mknoon/bridge/bridge.go` (dispatch entry).
- `go-relay-server/call_quality.go` (NEW: named handler + rate limiter + enum clamp), `inbox.go` (one delegating case in the `:2066` switch), `metrics.go` (3 promauto vars), `main.go` (env-flag load beside `:102-107`).
- `scripts/run_test_gates.sh` (ONE_TO_ONE_TESTS append), `scripts/run_host_test_gates.sh` (synthetic Go path), `scripts/check_reliability_simulation_discovery.sh` (proof + scenario cases).

**Direct tests (new/extended):** listed per-row in the RED catalog.

**Dependency-only context (NOT edited):** `flow_event_emitter.dart` (:6,:38,:202-218), `bridge.dart` allowlist (:61-81 — untouched), `secure_key_store.dart`, `media_download_preference_use_cases.dart` (persistence template), `active_peer_keepalive_use_case.dart`, `main.dart` DI (:2463-2467), relay `push_token_store.go`/`reaction_push.go` (rate-limit/capability precedents), `run_1to1_device_real.dart` (orchestrator conventions).

---

## Existing Tests Covering This Area

| Test | Covers | Status |
|---|---|---|
| `test/core/services/connectivity_signal_test.dart` | `restoredEdges` edge semantics | exists — preserved sentinel; extended with TC-01 |
| `test/core/debug/transport_metrics_privacy_test.dart` (:94, :234) | flow-event privacy (no peer id/multiaddr; active redaction) | exists — preserved sentinel; VC-09 adds the call twin (TC-08) |
| `test/core/bridge/go_bridge_client_test.dart` (cmd-map pin, ~:212) | bridge cmd surface | exists — extended with `relay:call_quality_report` (TC-13a) |
| `test/core/services/incoming_message_router_test.dart` (:256, :265) | unknown-type forward-compat | exists — preserved sentinel (VC-09 adds no router types) |
| `go-relay-server/protocol_contract_test.go` | unknown-action ERROR shape | exists — preserved sentinel (additive-action contract) |
| `go-relay-server/` `^TestRelayNotificationClosure_` | push closure | exists — preserved (relay-notification gate) |
| VC-05/VC-08 call suites (paths per landed plans) | call setup/answer/video | exist post-VC-05/08 — capture green baseline at execution start |
| ICE restart / reconnect / sampler / summary / report / toggle / degrade | — | **MISSING — the VC-09 gap; every row below** |

Already in curated family arrays?: `connectivity_signal_test.dart` and `go_bridge_client_test.dart` auto-glob into `core-host-all`; `go_bridge_client_test.dart` is in ONE_TO_ONE_TESTS. No call test is in any curated array yet (VC-05 registration to be confirmed at execution start).

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> "RED on HEAD" below means **the committed post-VC-05 tree** (Stop-if in the step plan). Rows 01, 08, 10-13 were additionally verified RED-relevant on *today's* HEAD (symbols absent — Root Cause greps). Fakes: `FakeCallStatsSource` (canned getStats maps), `FakeCallSignalingSender` (records envelopes), `StreamController<List<ConnectivityResult>>` for connectivity, `FakeP2PService`, fake clock — all constructor-injected; no new global state.

1. `test/core/services/connectivity_signal_test.dart::VC-09-01 interfaceChangeEdges emits on wifi→cellular swap, restored edge, and stays silent on →none`
   - Tier: unit/application
   - Shape: drive `interfaceChangeEdges(controller.stream)` with `[wifi]→[mobile]` (emit), `[mobile]→[none]` (silent), `[none]→[wifi]` (emit), `[wifi]→[wifi]` (silent).
   - RED on HEAD because: `interfaceChangeEdges` does not exist (grep 0 hits — compile RED); the existing `restoredEdges` provably swallows connected→connected (`:41-45`).
   - GREEN asserts: exactly the 2 emissions above, in order.
   - Mutation that re-reds: reuse `restoredEdges`' `isConnected && !wasConnected` predicate → wifi→cellular emission lost → RED.

2. `test/features/call/application/call_reconnect_controller_test.dart::VC-09-02 network-change signal triggers restartIce + re-offer with same callId and seq+1`
   - Tier: unit/application
   - Shape: controller wired to fake signal stream, fake pc (records `restartIce` calls), `FakeCallSignalingSender`; connected call (callId `c1`, last seq 4); fire one signal event.
   - RED on HEAD because: `call_reconnect_controller.dart` does not exist; VC-05's controller has no network-change subscription (VC-05 scope has none per VC-00 :70).
   - GREEN asserts: `restartIce` called once; sender captured exactly one re-offer envelope with `callId=='c1' && seq==5`; state == `reconnecting`; flow events contain `CALL_RECONNECT_BEGIN`.
   - Mutation that re-reds: revert the signal subscription in the controller → zero `restartIce` calls → RED.
   - Distinct-event discriminator: asserts `CALL_RECONNECT_BEGIN` AND NOT `CALL_ENDED` (a network blip must not be recorded as an ended call).

3. `test/features/call/application/call_reconnect_controller_test.dart::VC-09-03 bounded retry: 3 failed restarts / 20s deadline ends the call failed(reconnect_timeout)`
   - Tier: unit/application
   - Shape: fake clock; ICE stays `failed` after each restart; advance through 3 attempts then past the 20 s deadline.
   - RED on HEAD because: no retry loop exists — nothing transitions to `ended(failed, reconnect_timeout)`.
   - GREEN asserts: exactly 3 `restartIce` calls (never 4); terminal state `ended(failed)` with `cause==CallEndCause.reconnectTimeout`; `CALL_RECONNECT_FAILED{cause:reconnect_timeout}` emitted once.
   - Mutation that re-reds: drop the attempt cap → 4th restart observed → RED; drop the deadline → no terminal state → RED.

4. `test/features/call/application/call_reconnect_controller_test.dart::VC-09-04 callee applies re-offer with higher seq; stale/duplicate seq is ignored (idempotent)`
   - Tier: unit/application
   - Shape: feed the answer-side handler a re-offer `callId c1 seq 5` (apply), then `seq 5` again and `seq 3` (both ignore).
   - RED on HEAD because: no re-offer application path exists; VC-04's glare/seq contract covers initial offers, not mid-call restarts (VC-04 scope).
   - GREEN asserts: `setRemoteDescription` called exactly once; one answer sent (`seq` echoing 5); stale/duplicate produce no pc calls and emit `CALL_REOFFER_IGNORED{reason:stale_seq}`.
   - Mutation that re-reds: remove the seq comparison → duplicate re-offer applied twice → RED.
   - Distinct-event discriminator: `CALL_REOFFER_APPLIED` AND NOT `CALL_REOFFER_IGNORED` for the fresh seq; inverse for the stale one.

5. `test/features/call/application/call_reconnect_controller_test.dart::VC-09-05 kill-switch OFF: no restart attempted, legacy fail-fast preserved`
   - Tier: unit/application
   - Shape: construct controller with `iceRestartEnabled: false` (injects the `MKNOON_CALL_ICE_RESTART` const); fire signal + ICE `failed`.
   - RED on HEAD because: the flag and the branch don't exist (compile RED).
   - GREEN asserts: zero `restartIce`; call ends `failed(ice_failed)` exactly as pre-VC-09 (rule 3 revert path); companion assertion pins the const default `kCallIceRestartEnabled == true`.
   - Mutation that re-reds: ignore the flag in the branch → restart attempted with flag off → RED.

6. `test/features/call/application/call_quality_sampler_test.dart::VC-09-06 samples every 3s, classifies pair types, aggregates RTT/jitter/loss/bitrate`
   - Tier: unit/application
   - Shape: fake clock + `FakeCallStatsSource` returning candidate-pair stats (host/host, then srflx, then relay across runs) + inbound-rtp (jitter, packetsLost/packetsReceived) + outbound-rtp (bytesSent); advance 9 s.
   - RED on HEAD because: `call_quality_sampler.dart` does not exist.
   - GREEN asserts: exactly 3 `CALL_QUALITY_SAMPLE` events; pair classification host→`direct`, srflx→`punched`, relay→`turn`; sample details carry `rttMs/jitterMs/lossPct/bitrateKbps` numerics; interval == 3 s (2-5 s brief window).
   - Mutation that re-reds: revert the pair-type mapping (e.g. srflx→direct) → classification assertion RED; revert the timer → 0 samples → RED.

7. `test/features/call/application/call_quality_sampler_test.dart::VC-09-07 end-of-call summary emitted exactly once with setup ms, final pair type, aggregates, drop cause`
   - Tier: unit/application
   - Shape: run 5 samples, call `onCallEnded(CallEndCause.remoteHangup)` twice.
   - RED on HEAD because: no summary path exists.
   - GREEN asserts: exactly one `CALL_QUALITY_SUMMARY` (second `onCallEnded` is a no-op) with `setupMs` (from injected connect timestamp), `finalPairType`, `rttMedianMs`/`rttP95Ms` (median+p95 per FDC-S0 :144 — never mean), `lossPct`, `durationS`, `cause=='remote_hangup'`.
   - Mutation that re-reds: remove the emitted-once latch → two summaries → RED; report mean instead of median → fixture chosen so mean≠median → RED.

8. `test/features/call/application/call_quality_sampler_test.dart::VC-09-08 privacy: samples/summary carry no IP, candidate address, or peer id — fabricated identifying stats are excluded`
   - Tier: unit/application (privacy pin — twin of `transport_metrics_privacy_test.dart:234`)
   - Shape: stats source returns candidates with `'ip':'192.168.1.7'`, `'address':'10.0.0.3'`, `'relatedAddress'`, a full `12D3KooW…` peer id and a raw sdp blob; capture via `debugSetFlowEventSink` (`flow_event_emitter.dart:38`).
   - RED on HEAD because: sampler doesn't exist; and the design risk is real — raw getStats maps DO contain addresses, and the generic sanitizer blocklist (`:75-103`) does not know `ip`/`address` keys, so pass-through emission would leak. The whitelist-extraction (only numerics + enum pair type leave the sampler) is the mechanism under test.
   - GREEN asserts: serialized captured events contain none of `192.168.1.7`, `10.0.0.3`, `12D3KooW`, `candidate:`; details keys ⊆ the fixed whitelist.
   - Mutation that re-reds: pass the raw stats map into `emitFlowEvent` details → IP string appears in the sink → RED.

9. `test/features/call/application/call_quality_sampler_test.dart::VC-09-09 sampler stops on end: no samples after dispose, timer cancelled`
   - Tier: unit/application (destructive-cleanup blind-spot row)
   - Shape: 2 samples → `onCallEnded` → advance clock 30 s.
   - RED on HEAD because: sampler doesn't exist (and a naive periodic Timer keeps firing on a disposed pc — the failure this locks out).
   - GREEN asserts: sample count frozen at 2; stats source not called after end; `dispose()` idempotent.
   - Mutation that re-reds: remove the `_timer?.cancel()` in the end path → post-end samples appear → RED.

10. `go-relay-server/call_quality_report_test.go::TestCallQualityReport_IncrementsAggregateCounters`
    - Tier: relay Go host (real handler func, no libp2p stream needed — call the named handler directly, like `handlePresenceSet` tests)
    - Shape: enabled store; report `{pairType:"turn", dropCause:"ice_failed", setupMs:2100, ...}`.
    - RED on HEAD because: `call_quality.go`, the switch case, and `relay_call_*` metrics don't exist (verified grep 0) — compile RED.
    - GREEN asserts: `relay_call_reports_total{pair_type="turn"}` +1; `relay_call_drops_total{cause="ice_failed"}` +1; `relay_call_setup_seconds{pair_type="turn"}` observed once (via `prometheus/testutil`) with the pinned bucket list `{0.25, 0.5, 1, 2, 3, 5, 8, 13, 21, 30}` asserted (testutil.CollectAndCompare or declaration check — never the copied 0.01-floor stream buckets); response `{"status":"OK"}`; **nothing persisted** — a subsequent `retrieve` for the peer returns no call entries.
    - Mutation that re-reds: revert the counter bump → testutil count 0 → RED.

11. `go-relay-server/call_quality_report_test.go::TestCallQualityReport_RateLimit_FlagGate_EnumClamp`
    - Tier: relay Go host
    - Shape: three sub-asserts: (a) second report from same peer within 30 s → `{"status":"OK","rateLimited":true}` and counters NOT incremented; (b) flag disabled (default) → `{"status":"ERROR","error":"call_quality_report disabled"}` and counters untouched; (c) `pairType:"my-peer-id-12D3KooW"` → counted under `pair_type="unknown"` (label-cardinality + privacy clamp — no free-form strings ever become label values).
    - RED on HEAD because: none of the mechanisms exist (compile RED).
    - GREEN asserts: as above; also `default:` unknown-action contract unchanged for a bogus action (sentinel co-assert).
    - Mutation that re-reds: (a) drop the limiter map → both increments land → RED; (b) default the env flag to true → (b) branch flips → RED; (c) pass label through unclamped → labeled series exists → RED.

12. `test/features/call/application/report_call_quality_use_case_test.dart::VC-09-12 reporter: flag OFF skips, flag ON sends exactly one aggregate report, old-relay ERROR is a graceful skip`
    - Tier: unit/application
    - Shape: fake `P2PService.reportCallQuality` recorder; run with `reportingEnabled:false` then `true`; then make the fake throw the `Unknown action` ERROR shape.
    - RED on HEAD because: use case + primitive don't exist (compile RED).
    - GREEN asserts: OFF → zero calls + `CALL_QUALITY_REPORT_SKIPPED{reason:flag_off}`; ON → exactly one call whose payload contains ONLY the whitelist keys (no callId, no peerId) + `CALL_QUALITY_REPORT_SENT`; ERROR → no throw, `..._SKIPPED{reason:relay_unsupported}` (NET-REL-07 pattern); companion pins const default `kCallQualityReportEnabled == false`.
    - Mutation that re-reds: invert the flag default → OFF branch sends → RED; include callId in payload → whitelist assertion RED.
    - Distinct-event discriminator: `_SENT` vs `_SKIPPED{reason}` — same terminal call state, different event.

12c. `test/core/services/p2p_service_impl_call_report_test.dart::VC-09-12c reportCallQuality is Move-gated first-line`
    - Tier: unit/application
    - Shape: `P2PServiceImpl` with a denying `AccountMigrationNetworkGate`; call `reportCallQuality(...)`.
    - RED on HEAD because: the primitive doesn't exist (compile RED).
    - GREEN asserts: bridge never invoked when gate denies; gate consulted with token `'p2p_call_quality_report'` (pattern `p2p_service_impl.dart:555-572`); allow → bridge cmd `relay:call_quality_report` invoked once.
    - Mutation that re-reds: remove the first-line gate call → denied-gate send goes through → RED.

13a. `test/core/bridge/go_bridge_client_test.dart` (extend the cmd-map pin ~:212) — `relay:call_quality_report` → `relayCallQualityReport` entry added to the pinned map.
    - Tier: unit/application. RED on HEAD because the map has no such entry (`:128-140` verified). GREEN: pin includes the new cmd. Mutation: remove the cmd-map entry → pin RED.

13b. `go-mknoon/node/call_quality_report_client_test.go::TestCallQualityReportClient_MarshalsAggregateRequestAndParsesResponse`
    - Tier: Go host (go-mknoon; synthetic-path gate — see registration)
    - Shape: mirror the `RelayPresenceSet` request/parse tests (`go-mknoon/node/inbox.go:383-419` shapes): build the request JSON, parse OK / rateLimited / `Unknown action: call_quality_report` (→ unsupported, not error) responses.
    - RED on HEAD because: the client func doesn't exist (compile RED).
    - GREEN asserts: request `action=="call_quality_report"`, payload keys exactly the aggregate whitelist; the three response mappings.
    - Mutation that re-reds: map `Unknown action` to a hard error → unsupported assert RED.

14. `test/features/call/application/call_privacy_preference_use_cases_test.dart::VC-09-14 always-relay toggle: OFF default→policy 'all', ON→policy 'relay'; storage round-trip; corrupt value→default`
    - Tier: unit/application
    - Shape: fake `SecureKeyStore` (template: `media_download_preference_use_cases.dart:1-24`); load missing/corrupt → default OFF; save ON → reload ON; map preference → `iceTransportPolicy` value passed to the peer-connection factory param; force-relay precedence via the injectable override param (`forceRelay: true` mirroring `kCallForceRelay`) + stored pref OFF → factory receives `'relay'`; override absent/false → stored value wins; override never written to the store.
    - RED on HEAD because: model/use-cases/factory param don't exist (grep `iceTransportPolicy` lib/ = 0; compile RED).
    - GREEN asserts: both polarities produce the right policy string; round-trip; corrupt-decodes-to-default; override-wins precedence (and no store write from the override path).
    - Mutation that re-reds: hardcode `'all'` in the factory → ON polarity RED; invert the precedence (pref wins over override) → override case RED.

14b. `test/features/settings/presentation/widgets/settings_call_privacy_card_test.dart::VC-09-14b toggle renders persisted state on fresh mount and persists a flip`
    - Tier: widget (SYNC teardown for global-isolation IO per tier-matrix)
    - Shape: pump card with fake store holding ON → switch rendered ON (reopen/derived-state durability row); flip → store written; tradeoff copy ("relay adds latency; hides your IP") present.
    - RED on HEAD because: widget doesn't exist.
    - GREEN asserts: as above. Mutation: seed local state instead of reading the store on mount → fresh-mount assertion RED.

15. `test/features/call/application/call_reconnect_controller_test.dart::VC-09-15 ICE restart under always-relay keeps iceTransportPolicy relay (no policy escape)`
    - Tier: unit/application (sibling-surface consistency row)
    - Shape: controller constructed with relay policy ON; drive a restart; inspect the re-offer/pc config used for the restart.
    - RED on HEAD because: restart path doesn't exist; the hazard (restart falling back to a default-'all' config, leaking IP mid-call for a privacy user) is exactly what a naive implementation does.
    - GREEN asserts: restart never constructs a new pc with `'all'`; forced-relay stays forced across restart; `CALL_RECONNECT_BEGIN.details.policy=='relay'`.
    - Mutation that re-reds: rebuild config from defaults in the restart path → RED.

16. `test/features/call/application/call_auto_degrade_test.dart::VC-09-16 3 consecutive bad samples turn video off once; flag OFF never degrades; no auto re-enable`
    - Tier: unit/application
    - Shape: feed the policy sampler outputs: 2 bad + 1 good (no action), then 3 consecutive bad (loss 15%) → video-off; then good samples (no re-enable); rerun with `autoDegradeEnabled:false`.
    - RED on HEAD because: policy doesn't exist.
    - GREEN asserts: exactly one video-mute invocation on VC-08's seam; `CALL_DEGRADE_VIDEO_OFF{trigger:'loss'}` once; no un-mute ever issued; flag OFF → zero invocations; companion pins const default `kCallAutoDegradeEnabled == true`.
    - Mutation that re-reds: threshold to 1 sample → the 2-bad+1-good prefix triggers → RED; add auto re-enable → RED.
    - Distinct-event discriminator: `CALL_DEGRADE_VIDEO_OFF` AND NOT a user-initiated video-mute event (VC-08's) — auto vs manual mute must be distinguishable in the quality trail.

17. `test/features/call/application/call_reconnect_controller_test.dart::VC-09-17 post-reconnect full-state re-verification`
    - Tier: unit/application (invariant re-verification blind-spot row)
    - Shape: mid-call with video ON + mic muted (VC-08 states) → disruption → successful restart (ICE back to connected).
    - RED on HEAD because: no reconnect transition exists.
    - GREEN asserts: state back to `connected`; sampler still sampling (next tick fires); mic-muted and video states preserved (not reset by the new offer); `CALL_RECONNECT_SUCCESS{elapsedMs}` emitted; summary at end counts `reconnects==1`.
    - Mutation that re-reds: tear down + recreate session state on restart → mute flag lost → RED.

18. `integration_test/call_reliability_proof_test.dart::VC-09-18 device↔emulator: WiFi off mid-call → reconnected within deadline` — **PROD-CRITICAL**
    - Tier: device-proof (`@Tags(['device'])`; VC-00 rule 1)
    - Shape: two-party via orchestrator scenario `vc09-network-switch`: emulator leg answers, USB-device leg calls; once connected ≥10 s, the orchestrator runs `adb -s <usb> shell svc wifi disable`; device leg (cellular data present → true WiFi→cellular switch; else re-enable after 5 s for loss/restore recovery) must reach `CALL_RECONNECT_SUCCESS` and both legs assert media flowing (fresh samples with non-zero bitrate) within the 20 s app deadline; the test also logs `RECOVERY_ELAPSED_MS=<n>` in a stable grep-able line, and the orchestrator scenario fails the run if a single trial exceeds 20 s and WARNS (non-fatal, runsheet-visible) above 10 s — the 5-trial median stays the closure number, but the target is visible per automated run; runsheet records the elapsed ms against the <10 s target.
    - RED on HEAD because: without the VC-09 restart path the call never recovers — the proof times out on the post-VC-05 tree (and the test file doesn't exist).
    - GREEN asserts: reconnect event on the device leg; post-reconnect sample on both legs; call still ends cleanly (`local_hangup`).
    - Mutation that re-reds: disable `MKNOON_CALL_ICE_RESTART` in the launch dart-defines → proof times out → RED (this is also the kill-switch device check).
    - **This row is the wire/transport leg proof — do NOT treat unit coverage (TC-02/03/17) as sufficient on its own.**

19. `integration_test/call_reliability_proof_test.dart::VC-09-19 forced-relay call connects with pair type turn/relay`
    - Tier: device-proof
    - Shape: orchestrator scenario `vc09-forced-relay`: the **device leg exercises the real production chain** — before dialing, the test enables the real toggle (writes the `CallPrivacyPreferences` value through the real SecureKeyStore-backed use case at app start, or taps the settings-card switch via the integration driver) so settings → store → load → pc-factory param is proven on-device; the **emulator leg only** launches with `--dart-define=MKNOON_CALL_FORCE_RELAY=true` (launch determinism; the dart-define is never the device leg's mechanism). Call connects; each leg asserts its sampler's pair type == `turn` (never `direct`/`punched`); runsheet captures the TURN quality baseline (setup ms, RTT median/p95, loss) from the `[FLOW]` capture. Restart-durability step: after the first forced-relay call, `adb shell am force-stop com.mknoon.app` (applicationId default, `android/app/build.gradle.kts:25`) + relaunch, open Settings, assert the toggle renders ON — recorded as a runsheet observation row (M2).
    - RED on HEAD because: no forced-relay plumbing, no sampler, no scenario.
    - GREEN asserts: connected + `finalPairType=='turn'` both legs — with the device leg's policy sourced from the persisted real preference, not a harness define.
    - Mutation that re-reds: drop `iceTransportPolicy` from the config → pair type comes up `direct`/`punched` on LAN-adjacent rigs → RED.

### Preserved (green-on-HEAD, must STAY green — locked, not RED)
- **P1** `connectivity_signal_test.dart` existing `restoredEdges` suite — `interfaceChangeEdges` is additive; `restoredEdges` untouched.
- **P2** `transport_metrics_privacy_test.dart` (:94, :234) — flow sanitizer + privacy pins.
- **P3** `incoming_message_router_test.dart::routes unknown types…` (:256) — VC-09 adds no router types.
- **P4** relay `protocol_contract_test.go` unknown-action shape + `^TestRelayNotificationClosure_` — additive action must not disturb either.
- **P5** VC-05/VC-08 call suites + `./scripts/run_test_gates.sh 1to1` / `transport` — capture green baseline at execution start (rule 6).

---

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 interface-change detector | pure edge logic | unit | `test/core/services/connectivity_signal_test.dart::VC-09-01` | symbol absent (grep 0) | reuse restored-only predicate | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (glob, existing classified file) |
| TC-02 restart + re-offer seq+1 | controller + signaling | unit/app | `call_reconnect_controller_test.dart::VC-09-02` | no controller/subscription | remove signal subscription | `flutter test test/features/call/application/call_reconnect_controller_test.dart` + `./scripts/run_test_gates.sh 1to1` | AUTO (feature glob) + **add file to ONE_TO_ONE_TESTS** (rule 6 4-doc update) |
| TC-03 bounded retry → ended(failed) | retry cap + deadline | unit/app | `…::VC-09-03` | no retry loop | drop cap / deadline | same as TC-02 | same file (already registered) |
| TC-04 re-offer idempotency | seq compare | unit/app | `…::VC-09-04` | no apply path | remove seq comparison | same as TC-02 | same file |
| TC-05 ICE-restart kill-switch OFF | flag polarity (rule 3) | unit/app | `…::VC-09-05` | flag absent (compile) | ignore flag in branch | same as TC-02 | same file |
| TC-06 sampler cadence + pair classification | timer + mapping + aggregates | unit/app | `call_quality_sampler_test.dart::VC-09-06` | sampler absent | invert srflx mapping / remove timer | `flutter test test/features/call/application/call_quality_sampler_test.dart` + `1to1` | AUTO (feature glob) + **add file to ONE_TO_ONE_TESTS** |
| TC-07 summary once + drop cause | end aggregation, median/p95 | unit/app | `…::VC-09-07` | no summary path | remove once-latch / use mean | same as TC-06 | same file |
| TC-08 privacy whitelist | no IP/peerId/candidate leaves sampler | unit/app | `…::VC-09-08` | sampler absent; raw stats would leak | pass raw stats to emitFlowEvent | same as TC-06 | same file |
| TC-09 sampler cleanup on end | destructive side-effects | unit/app | `…::VC-09-09` | sampler absent | remove timer cancel | same as TC-06 | same file |
| TC-10 relay counters | Prometheus aggregate bump, nothing persisted | relay Go | `go-relay-server/call_quality_report_test.go::TestCallQualityReport_IncrementsAggregateCounters` | action/metrics absent (grep 0) | revert counter bump | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestCallQualityReport' -count=1)` + `./scripts/run_test_gates.sh all` | AUTO within `run_relay_all_go_gate` (`./...` glob, `run_test_gates.sh:865-868`; wired into `all` at `:1149-1158`) |
| TC-11 rate limit + flag gate + enum clamp | abuse/privacy guards | relay Go | `…::TestCallQualityReport_RateLimit_FlagGate_EnumClamp` | mechanisms absent | drop limiter / default flag true / unclamped label | same as TC-10 | same (AUTO relay-all) |
| TC-12 client reporter flag + graceful skip | opt-in send, NET-REL-07 skip | unit/app | `report_call_quality_use_case_test.dart::VC-09-12` | use case absent | invert flag default / leak callId | `flutter test test/features/call/application/report_call_quality_use_case_test.dart` | AUTO (feature glob) |
| TC-12c Move gate first-line | rule 4 | unit/app | `p2p_service_impl_call_report_test.dart::VC-09-12c` | primitive absent | remove first-line gate call | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (`test/core/services/` glob) |
| TC-13a bridge cmd-map pin | Dart↔Go cmd surface | unit/app | `go_bridge_client_test.dart` extended pin | cmd absent (`:128-140`) | remove cmd-map entry | `./scripts/run_test_gates.sh 1to1` | already in ONE_TO_ONE_TESTS |
| TC-13b Go client request shape | marshal/parse + unsupported mapping | Go host (go-mknoon) | `go-mknoon/node/call_quality_report_client_test.go::TestCallQualityReportClient_MarshalsAggregateRequestAndParsesResponse` | client func absent | map Unknown-action to hard error | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'CallQualityReportClient' -count=1)` via host-all | **NEW synthetic path** in `run_host_test_gates.sh` (`GO_NODE_CALLQUALITY_TEST` + `RUN='CallQualityReportClient'`, pattern `:144-184` + branches at `:394`/`:431`) |
| TC-14 always-relay polarities + storage + force-relay precedence | pref model + factory param + override merge | unit/app | `call_privacy_preference_use_cases_test.dart::VC-09-14` | model/param absent (grep 0) | hardcode 'all' in factory / invert override precedence | `flutter test test/features/call/application/call_privacy_preference_use_cases_test.dart` | AUTO (feature glob) |
| TC-14b toggle UI + reopen durability | widget + fresh-mount reconstruct | widget | `settings_call_privacy_card_test.dart::VC-09-14b` | widget absent | seed local state, skip store read | `flutter test test/features/settings/presentation/widgets/settings_call_privacy_card_test.dart` | AUTO (feature glob) |
| TC-15 restart preserves relay policy | sibling-consistency | unit/app | `call_reconnect_controller_test.dart::VC-09-15` | restart path absent | rebuild config from defaults on restart | same as TC-02 | same file |
| TC-16 auto-degrade ladder + kill-switch | thresholds + polarity (rule 3) | unit/app | `call_auto_degrade_test.dart::VC-09-16` | policy absent | 1-sample threshold / auto re-enable / ignore flag | `flutter test test/features/call/application/call_auto_degrade_test.dart` | AUTO (feature glob) |
| TC-17 post-reconnect invariants | full-state re-verification | unit/app | `call_reconnect_controller_test.dart::VC-09-17` | no reconnect transition | recreate session state on restart | same as TC-02 | same file |
| TC-18 network-switch recovery **(PROD-CRITICAL)** | OS boundary, real devices, rule 1 | device-proof | `integration_test/call_reliability_proof_test.dart::VC-09-18` | no restart → proof times out | launch with `MKNOON_CALL_ICE_RESTART=false` | `dart integration_test/scripts/run_call_device_real.dart --scenario vc09-network-switch -d <serialA>,<serialB>` | classify_path case in `check_reliability_simulation_discovery.sh` (record "1to1" test) + orchestrator `--scenario vc09-network-switch`; `run_test_gates.sh` proof-glob AUTO (`:1036-1039`) |
| TC-19 forced-relay pair type | TURN policy on wire | device-proof | `…::VC-09-19` | no policy/sampler/scenario | drop iceTransportPolicy from config | `dart integration_test/scripts/run_call_device_real.dart --scenario vc09-forced-relay -d <serialA>,<serialB>` | same registration (second `--scenario` case) |
| TC-20 measurement RESULTS rows | <10s recovery number; TURN baseline | manual measurement (runsheet) | `VC-09-reliability-quality-RESULTS.md` steps M1-M3 | n/a (measurement, not behavior — RED/GREEN not applicable by design) | n/a (numbers, not code; honesty rule: report median+p90, never mean) | runsheet execution during TC-18/TC-19 runs (`adb logcat … grep FLOW … tee`) | n/a — deliberate: RESULTS docs are not harness-registered (FDC-S0 convention); linked from Done Criteria |
| REGRESSION floor | no 1:1/transport/call/relay breakage | gate | existing suites | n/a (green) | n/a | `./scripts/run_test_gates.sh 1to1` · `transport` · `./scripts/run_host_test_gates.sh feature-host-all` · `core-host-all` · relay-all — capture green baseline at execution start | n/a (existing registrations) |

No empty cells (n/a entries are justified in-cell).

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** the always-relay preference persists in `SecureKeyStore` but the toggle UI and the pc-factory policy are derived state → **TC-14b** (fresh-mount reconstructs from the store) + **TC-14** (corrupt/missing decodes to default) + the M2 runsheet real-process-restart row (force-stop + relaunch → toggle still ON on the real SecureKeyStore). The reconnecting state is deliberately NOT persisted — a process restart mid-call ends the call (VC-05's lifecycle contract); recorded as Accepted Difference, and the summary's drop-cause taxonomy covers it (`signaling_lost`).
- **Sibling-surface consistency:** the forced-relay policy must hold across *every* pc-config construction site — initial offer (TC-14), answer side (same factory — TC-14 asserts at the factory seam both directions use), and the ICE-restart path (**TC-15**, the classic escape). Auto-degrade vs VC-08 manual video mute distinguished by discriminator events (TC-16) so one surface can't masquerade as the other in the quality trail.
- **Destructive-action side-effects:** call end must cancel the sampler timer, emit exactly one summary, fire at most one relay report, and leave no periodic getStats on a disposed pc → **TC-07** (once-latch), **TC-09** (timer/statsource silence), **TC-12** (single report). What is preserved: the flow-event trail (events are emitted, not stored — nothing to clean).
- **Invariant re-verification under new transitions:** the reconnect transition (new in VC-09) re-verifies the full mid-call state — mute/video flags, sampler liveness, policy — not just the headline `connected` flag → **TC-17**; the degrade transition re-verifies audio continues and no re-enable occurs → **TC-16**.

---

## Invariants (locked by tests)

- INV-1 A connected-set change while connected triggers exactly one restart cycle; →none alone triggers none → TC-01/TC-02.
- INV-2 Re-offers reuse the `callId` with strictly increasing `seq`; stale/duplicate seq is a no-op → TC-02/TC-04.
- INV-3 Reconnect is bounded: ≤3 restarts, ≤20 s, terminal `ended(failed, cause)` → TC-03.
- INV-4 Reconnect success restores the FULL pre-disruption state (mute/video/policy/sampler) → TC-15/TC-17.
- INV-5 Every call yields ≥1 sample per 3 s while connected and exactly one summary → TC-06/TC-07/TC-09.
- INV-6 No IP, candidate address, peer id, or sdp ever leaves the sampler or reaches the relay report → TC-08/TC-10/TC-11/TC-12.
- INV-7 Relay call metrics are aggregate-only, enum-clamped, rate-limited, flag-gated, never persisted → TC-10/TC-11.
- INV-8 Reporting is opt-in (default OFF) and Move-gated → TC-12/TC-12c.
- INV-9 Always-relay ON ⇒ `iceTransportPolicy=='relay'` on every pc construction incl. restarts; OFF ⇒ `'all'` → TC-14/TC-15/TC-19.
- INV-10 Auto-degrade fires only on 3 consecutive bad samples, at most once, never re-enables, and its kill-switch OFF restores VC-08 behavior → TC-16.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

---

## Step-By-Step Implementation Plan

> **Stop-if (hard sequencing gate):** VC-05 merged + its gates green is a precondition; VC-08 should be merged for the degrade rows (if VC-08 has not landed, TC-16's mute seam does not exist → split TC-16 out and land it with/after VC-08; do not fake the seam). At start: snapshot `git status --short` (preserve the dirty tree — never revert/absorb it), capture green baselines for `1to1`, `transport`, `feature-host-all`, `core-host-all`, relay-all, and the VC-05/VC-08 call suites; re-resolve every **[VC-05 contract anchor]** path against the landed diffs. **Stop-if** VC-05's controller/factory shapes diverge from the seams assumed here → adjust the plan's file targets, do not hack adapters around them.

1. **RED discipline — per slice, not waterfall.** Each implementation step below authors its OWN slice's RED rows immediately before going GREEN (step 2 authors TC-01 RED then GREEN; step 3 authors TC-02/03/04/05/15/17 RED then GREEN; and so on — GREEN targets per step are the slice's RED set). Run the focused commands; confirm each fails for its documented reason (compile-RED rows at compile; behavioral rows on assertion) before writing that slice's production code. Register as you author, per slice: ONE_TO_ONE_TESTS appends, synthetic Go path, discovery classify_path cases, orchestrator `--scenario` stubs. Run `./scripts/run_test_gates.sh completeness-check` and `./scripts/check_reliability_simulation_discovery.sh` once after the final slice (both must pass with all new rows visible; a test that runs in no gate is invisible coverage). Rationale: red tests written en masse against not-yet-landed VC-05 seams drift as early slices teach the real shapes — per-slice RED keeps each red honest against the current tree. INV-RED-FIRST holds per slice.
2. **`interfaceChangeEdges`** in `connectivity_signal.dart` (pure, beside `restoredEdges`; set-equality on non-none results; emits on connected→connected set change and disconnected→connected; silent on →none). GREEN: TC-01.
3. **Reconnect controller** — subscribe (a) the signal, (b) ICE state callbacks from VC-05's controller; `restartIce()` + re-offer send via injected `CallSignalingSender` (VC-04 channel); `reconnecting` state + banner hook; bounded retry via injected clock; kill-switch const `kCallIceRestartEnabled = bool.fromEnvironment('MKNOON_CALL_ICE_RESTART', defaultValue: true)` injected as ctor default. Callee re-offer apply with seq guard. GREEN: TC-02/03/04/05/15(partially)/17. Wire the banner into VC-05's screen (one widget assertion inside TC-17's file if VC-05's screen test harness makes it cheap; otherwise the state machine assertion suffices — the screen renders states VC-05 already tests).
4. **Sampler + summary** — `CallQualitySampler(statsSource, clock, emit)` with the whitelist extractor and pair-type classifier; `onCallEnded(cause)` once-latch → summary; wire start/stop into VC-05's session lifecycle. GREEN: TC-06/07/08/09.
4b. **Network-switch device proof (TC-18) — EARLY, immediately after its real dependencies (steps 2-4) land.** Author `integration_test/call_reliability_proof_test.dart` + the `vc09-network-switch` orchestrator scenario, run it on the rig per Execution Environment, and capture the first M1 trials. This is the PROD-CRITICAL payoff: if real-device ICE restart misses the 10 s target or flutter_webrtc `restartIce` misbehaves on a real interface swap, learn it NOW — before the degrade/toggle/report slices (5-8), which TC-18 does not depend on. GREEN: TC-18 (kill-switch mutation included); remaining M1 trials + TC-19 stay in step 9.
5. **Degrade policy** — consume sampler samples; 3-strike thresholds; call VC-08's video-mute seam; `kCallAutoDegradeEnabled` const default ON. GREEN: TC-16.
6. **Always-relay** — `CallPrivacyPreferences` + load/save use cases + `iceTransportPolicy` param through the pc factory (both construction directions + restart path) + settings card. GREEN: TC-14/14b, completes TC-15.
7. **Report pipeline (client)** — `P2PService.reportCallQuality` (Move gate first-line) → `go_bridge_client.dart` cmd → `bridge.go` dispatch → `node/inbox.go` `RelayCallQualityReport` (mirror `RelayPresenceSet:419`); use case with flag + graceful-skip; fire from the session end transition after the summary. GREEN: TC-12/12c/13a/13b.
8. **Relay action** — `call_quality.go` named handler (enum clamp, rate limiter, flag), one delegating case in the `inbox.go:2066` switch, 3 promauto vars in `metrics.go`, env load in `main.go`. GREEN: TC-10/11. Run relay-all locally.
9. **Remaining device proof + measurement** — author the `vc09-forced-relay` scenario (TC-19 — needs step 6's real toggle chain) in the proof file from step 4b; execute per Execution Environment (incl. the force-stop/relaunch durability step); complete the M1 trials started in step 4b; fill `VC-09-reliability-quality-RESULTS.md` (M1-M3). GREEN: TC-19; TC-20 rows captured.
10. **EC2 redeploy + live verification** (rule 2, section below), then re-run the full Acceptance Gates + every mutation revert to confirm re-RED. Stop-if: any failure outside the Scope Guard → replan, do not hack around it.

---

## Execution Environment  (rule 1 — concrete commands for the implementing agent)

```bash
# 0. Rig discovery (canonical pair: USB Pixel 6 21071FDF600CSC + emulator-5554 / AVD mknoon_play_35)
adb devices -l
flutter devices --machine
flutter emulators
# If the emulator is not booted: flutter emulators --launch mknoon_play_35

# 1. Host loop (any machine)
flutter test test/features/call/application/call_reconnect_controller_test.dart
flutter test test/features/call/application/call_quality_sampler_test.dart

# 2. Single-device integration run (per-file, serial explicit)
flutter test integration_test/call_reliability_proof_test.dart -d 21071FDF600CSC \
  --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_RELAY_ADDRESSES=<default pair, see run_test_gates.sh:567>

# 3. Two-party orchestrator (comma-joined -d, conventions of run_1to1_device_real.dart:22,114,142)
dart integration_test/scripts/run_call_device_real.dart --list-scenarios       # discovery contract: bare ids
dart integration_test/scripts/run_call_device_real.dart --scenario vc09-network-switch -d 21071FDF600CSC,emulator-5554
dart integration_test/scripts/run_call_device_real.dart --scenario vc09-forced-relay  -d 21071FDF600CSC,emulator-5554

# 4. Leg assignment (fixed): CALLER = USB device (its WiFi gets toggled; it has the cellular SIM),
#    CALLEE = emulator (host WiFi NAT; its network never changes). The orchestrator itself issues:
adb -s 21071FDF600CSC shell svc wifi disable      # mid-call, after >=10s connected
# recovery variant when no SIM data available:
sleep 5 && adb -s 21071FDF600CSC shell svc wifi enable
# ALWAYS restore at teardown (even on failure):
adb -s 21071FDF600CSC shell svc wifi enable

# 5. Capture (two terminals, started BEFORE the call — runsheet convention of plan 179)
adb -s 21071FDF600CSC logcat -v time | grep -E 'FLOW.*(CALL_RECONNECT|CALL_QUALITY|CALL_DEGRADE)' | tee vc09-device.log
adb -s emulator-5554  logcat -v time | grep -E 'FLOW.*(CALL_RECONNECT|CALL_QUALITY|CALL_DEGRADE)' | tee vc09-emulator.log
```

- Unavailable target = "N/A (target unavailable by project policy)" — never substitute an iOS device.
- **iOS-boundary rows:** none are required for VC-09 closure (reconnect/sampler are cross-platform Dart; CallKit interplay is VC-07's). The orchestrator still carries the **deferred-not-waived** pattern: if handed an iOS UDID it prints the device recipe and exits 0 without claiming proof.
- Profile builds for measurement runs: `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_CALL_QUALITY_REPORT=true` (flow events are NOT debug-only — the profile override at `lib/main.dart:320-330` is the capture mechanism).

---

## Risks And Edge Cases

- **WiFi-disable also drops the libp2p signaling path** on the device leg — the re-offer may only be deliverable after the new interface comes up; the 20 s deadline (not the 10 s target) is the app's bound, and the <10 s target is measured from new-interface-up. Pinned by TC-03 (deadline) + runsheet M1 definition (measurement honesty).
- **Restart glare** (both sides restart simultaneously after a mutual blip) → both send re-offers. VC-04's glare rule (callId ordering) is reused for restarts; TC-04's stale-seq guard prevents double-apply. If VC-04's landed glare contract differs, adopt it verbatim (execution-start check).
- **getStats shape drift** across flutter_webrtc versions → sampler tolerates missing keys (each extractor null-safe, sample skipped fields simply absent). Pinned inside TC-06 fixtures (one run with partial stats).
- **Label cardinality / privacy on the relay** → enum clamp TC-11c is the guard; free-form strings never become labels.
- **Report spam** → per-peer 30 s limiter TC-11a; client sends at most one per call TC-12.
- **Degrade flapping** → 3-strike + one-shot + no auto re-enable (TC-16).
- **Policy escape on restart** (privacy regression) → TC-15.
- **Emulator WiFi toggling is not meaningful** (`svc wifi` on emulators doesn't model a path switch) → the toggled leg is ALWAYS the USB device (Execution Environment leg assignment).
- **Live relay backend is memory** (README systemd unit sets only FIREBASE_SERVICE_ACCOUNT) — irrelevant to VC-09's counters (Prometheus is process-local, nothing persisted), but the env-flag drop-in below is the first systemd env change; one-change-per-deploy rule observed (no other relay change rides along).

---

## Device/Relay Proof Profile

**Requires device for closure** (rule 1): TC-18 (PROD-CRITICAL network-switch recovery) and TC-19 (forced-relay pair type) close only on the USB-device+emulator rig — host fakes cannot exercise a real interface switch or a real TURN allocation. Host tiers close everything else.
Closure scenarios: `dart integration_test/scripts/run_call_device_real.dart --scenario vc09-network-switch|vc09-forced-relay -d <usb>,<emulator>`; discovery: `./scripts/check_reliability_simulation_discovery.sh` must list both (case branch added per `:380-392` syntax); `/sims 1to1 --list` shows the slots (runner, never registrar).
Flag graduation: `MKNOON_CALL_QUALITY_REPORT` stays default-OFF at close; graduates only after the live-relay verification below AND a privacy re-review of one captured report payload (rule 3 staged rollout). iOS legs: deferred-not-waived (recipe printed; VC-07's future macOS session owns any CallKit-interplay proof).
Relay defaults if needed: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (see `run_test_gates.sh:567`).

---

## EC2 Redeploy & Live Verification  (VC-00 rule 2 — literal; grounded in the 142-plan procedure)

```bash
# 0. Pre-deploy: relay tests green locally (see Acceptance Gates); on-box state inspection (NEW —
#    the repo cannot see the live env; record current unit env + version before touching anything)
ssh -i ../se.pem ubuntu@mknoun.xyz 'systemctl cat relay-server --no-pager && /usr/local/bin/relay-server version'

# 1. Rollback snapshot (NEW — keep the running binary; committed relay-server-linux-amd64 is the older fallback)
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo cp /usr/local/bin/relay-server /usr/local/bin/relay-server.vc09-prev'

# 2. Cross-compile + ship (canonical procedure, Test-Flight-Improv/142-...-tdd-plan.md:141-150)
cd go-relay-server && GOOS=linux GOARCH=amd64 go build -o relay-server-linux-amd64 .
scp -i ../se.pem relay-server-linux-amd64 ubuntu@mknoun.xyz:/tmp/relay-server
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo install /tmp/relay-server /usr/local/bin/relay-server \
  && sudo systemctl restart relay-server && systemctl is-active relay-server && /usr/local/bin/relay-server version'
# bump const version = "1.5.1" (main.go:25) → "1.6.0" as part of the change; version output proves the new binary

# 3. Enable the report flag (NEW — systemd drop-in; the ONLY env change in this deploy, rule "one change per deploy")
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo mkdir -p /etc/systemd/system/relay-server.service.d && \
  printf "[Service]\nEnvironment=RELAY_CALL_QUALITY_REPORT_ENABLED=true\n" | \
  sudo tee /etc/systemd/system/relay-server.service.d/vc09-call-quality.conf && \
  sudo systemctl daemon-reload && sudo systemctl restart relay-server && systemctl is-active relay-server'

# 4. Live probe — BEFORE: metric series absent/zero
ssh -i ../se.pem ubuntu@mknoun.xyz 'curl -s localhost:2112/metrics | grep relay_call_ || echo NO_SERIES_YET'
# Make ONE reported call: device+emulator, both launched with --dart-define=MKNOON_CALL_QUALITY_REPORT=true
# (scenario vc09-forced-relay doubles as the probe call). Then AFTER:
ssh -i ../se.pem ubuntu@mknoun.xyz 'curl -s localhost:2112/metrics | grep relay_call_'
#   PASS criterion: relay_call_reports_total{pair_type="turn"} >= 1 visible on :2112
ssh -i ../se.pem ubuntu@mknoun.xyz 'journalctl -u relay-server -n 100 --no-pager | grep CALLQ'
#   PASS criterion: one "[CALLQ]" accept line; MUST contain no peer id (privacy log check — visual)

# 5. Back-compat probe (old-client safety, NET-REL-07): unchanged actions still answer
ssh -i ../se.pem ubuntu@mknoun.xyz 'journalctl -u relay-server -n 200 --no-pager | grep -c "Unknown action" || true'

# 6. Rollback (if any probe fails)
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo install /usr/local/bin/relay-server.vc09-prev /usr/local/bin/relay-server && \
  sudo rm -f /etc/systemd/system/relay-server.service.d/vc09-call-quality.conf && \
  sudo systemctl daemon-reload && sudo systemctl restart relay-server && /usr/local/bin/relay-server version'
```

Redeploy is an explicit operator action, never part of test runs (173-plan rule). The action is additive: an un-upgraded relay answers `Unknown action: call_quality_report` and the client maps it to a graceful skip (TC-12/TC-13b) — client can ship before or after the relay. Grafana: add a `relay_call_*` panel to `grafana-relay-dashboard.json` (same PromQL conventions; TURN share = `relay_call_reports_total{pair_type="turn"} / ignoring(pair_type) group_left sum(relay_call_reports_total)`).

---

## Metrics Ownership & Measurement RESULTS Doc  (VC-00 metrics table :147-159 — VC-09 rows)

| VC-00 metric (owner VC-05/**VC-09**) | Vehicle | Named test / runsheet step |
|---|---|---|
| Call setup time (invite→connected) | `CALL_QUALITY_SUMMARY.setupMs` + `relay_call_setup_seconds` | TC-07; relay TC-10; runsheet **M2** |
| ICE pair type (host/srflx/relay ⇒ direct/punched/turn) | sample+summary `pairType`; `relay_call_reports_total{pair_type}` | TC-06; TC-10; device TC-19 |
| Loss / RTT / jitter / bitrate | `CALL_QUALITY_SAMPLE` + summary median/p95 | TC-06/TC-07; runsheet **M2** |
| Drop cause | summary `cause`; `relay_call_drops_total{cause}` | TC-07; TC-10; TC-03 (reconnect_timeout path) |
| TURN share | Grafana derivation over `relay_call_reports_total` | live-verification step 4 + dashboard panel |
| **Network-switch recovery time** (VC-09's headline) | `CALL_RECONNECT_SUCCESS.elapsedMs` | device TC-18; runsheet **M1** |

**RESULTS doc (created at execution): `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-09-reliability-quality-RESULTS.md`** — FDC-S0/S0-results conventions: Freeze table (commit hash, date, `GOTOOLCHAIN=go1.25.0` caveat, device roster, working-tree state, raw-logs dir `vc09-raw/` in the scratchpad); per-metric verdict table; median+p90/p95, never mean; device-only rows marked deferred-not-waived if the rig is unavailable.
- **M1 (pre-committed hard number): WiFi→cellular switch on the USB device mid-call recovers in < 10 s median over 5 trials** (measured `CALL_RECONNECT_BEGIN`→`CALL_RECONNECT_SUCCESS` elapsedMs from the device `[FLOW]` capture; new-interface-up to media-flowing). Miss ⇒ the story does NOT close green — record the number, file the follow-up, and say so in the verdict (unfalsifiable-wins rule).
- **M2: TURN-forced quality baseline** — from 3 `vc09-forced-relay` calls: setup ms, RTT median/p95, loss %, sustained bitrate. This is the documented "always relay" tradeoff evidence (linked from the settings card copy). Sanity floor: the 3 forced-relay calls must each sustain a connected call ≥ 60 s with loss < 12% (the degrade threshold) on an unshaped network — otherwise the toggle ships with a "may significantly degrade quality" copy variant and a follow-up is filed. Includes the restart-durability observation row: after the first call, `adb shell am force-stop com.mknoon.app` + relaunch → Settings toggle renders ON (real-SecureKeyStore persistence proven across a process restart, not just TC-14b's same-process re-mount).
- **M3: degrade-ladder field check** — one call with the device leg bandwidth-shaped (WiFi hotspot throttle or distance), confirm `CALL_DEGRADE_VIDEO_OFF` fires and audio continues (observation row, no hard number).

---

## Acceptance Gates  (literal — copy/paste; rule 6: capture green baselines at execution start, never hardcode counts)

```bash
# Execution-start snapshot (dirty tree preserved; baselines captured)
git status --short
./scripts/run_test_gates.sh 1to1                     # capture green baseline count
./scripts/run_test_gates.sh transport                # capture (FLUTTER_DEVICE_ID-driven)
./scripts/run_host_test_gates.sh feature-host-all    # capture
./scripts/run_host_test_gates.sh core-host-all       # capture
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)   # capture

# RED (before production edits) — each must FAIL for its documented reason
flutter test test/core/services/connectivity_signal_test.dart --plain-name 'VC-09-01'
flutter test test/features/call/application/call_reconnect_controller_test.dart
flutter test test/features/call/application/call_quality_sampler_test.dart
flutter test test/features/call/application/call_auto_degrade_test.dart
flutter test test/features/call/application/report_call_quality_use_case_test.dart
flutter test test/features/call/application/call_privacy_preference_use_cases_test.dart
flutter test test/features/settings/presentation/widgets/settings_call_privacy_card_test.dart
flutter test test/core/services/p2p_service_impl_call_report_test.dart
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'CallQualityReportClient' -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestCallQualityReport' -count=1)

# Direct GREEN (after implementation) — rerun all of the above; all pass

# Registration verification (rule 6 — no invisible tests)
./scripts/run_test_gates.sh completeness-check
./scripts/check_reliability_simulation_discovery.sh
./scripts/run_host_test_gates.sh host-all --list | grep -i callquality    # synthetic Go path visible
./scripts/run_test_gates.sh 1to1 2>&1 | grep -E 'call_(reconnect_controller|quality_sampler)_test'  # array adds visible

# Preservation sentinels (must stay green vs captured baselines)
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh transport
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh core-host-all
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)       # relay-all incl. ^TestRelayNotificationClosure_
flutter test test/core/debug/transport_metrics_privacy_test.dart
# VC-05/VC-08 call suites per their landed plans (paths resolved at execution start)

# Device proofs (rule 1)
adb devices -l
dart integration_test/scripts/run_call_device_real.dart --scenario vc09-network-switch -d 21071FDF600CSC,emulator-5554
dart integration_test/scripts/run_call_device_real.dart --scenario vc09-forced-relay  -d 21071FDF600CSC,emulator-5554

# EC2 live verification (rule 2) — section above; PASS = relay_call_reports_total visible on :2112 after one reported call

# Hygiene
flutter analyze            # 0 new vs tool/analyzer_baseline (scripts/check_flutter_analyze_baseline.sh)
git diff --check
```

No migration gate: VC-09 adds **no DB schema change** (preferences ride `SecureKeyStore`; quality data is events + Prometheus, deliberately unpersisted — see Accepted Differences).

---

## Known-Failure Interpretation

- Expected RED: every catalog row before its implementation step (compile-RED for new-file rows is the documented reason).
- Pre-existing dirty tree: large (see execution-start `git status --short` snapshot) — preserve; never revert/absorb/reformat (257-plan rule).
- Environment blockers (NOT product): missing USB device/emulator (`adb devices` empty) → device rows blocked, host rows proceed; no SIM data on the device → TC-18 runs the wifi-off/on recovery variant and M1 is recorded as "switch variant unavailable — loss/restore recovery measured instead" (deferred-not-waived for the true-switch number); relay redeploy unreachable (`se.pem`/network) → rule-2 gate blocked, story stays open.
- Scope drift (BLOCKING): failures in VC-04 signaling tests, VC-05 setup tests, VC-08 video tests, or relay push/inbox tests beyond the additive case → stop, diagnose; VC-09 must not modify sibling behavior.
- `transport` gate is device/`FLUTTER_DEVICE_ID`-driven and skips on a bare host — a skip is not a failure.
- Analyzer-baseline drift not caused by VC-09 files: accept, do not rewrite the baseline (257-plan precedent).

---

## Done Criteria

- [ ] RED added first per slice (TC-01…TC-19 catalog via the step-1 per-slice discipline), each failed for the documented reason on the post-VC-05 tree.
- [ ] Mutation-verified: every mutation revert listed in the matrix re-executed → re-RED confirmed.
- [ ] Direct GREEN + preservation sentinels + named gates pass vs captured baselines.
- [ ] No migration (none needed — checked: no schema change).
- [ ] OS-boundary rows proven on the real rig: TC-18 (PROD-CRITICAL) + TC-19 green device↔emulator; WiFi restored at teardown.
- [ ] Every new test's harness registration done AND verified in a gate run (completeness-check, discovery script, host-all --list, 1to1 grep — commands above); rule-6 4-doc update for the ONE_TO_ONE_TESTS change (`test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md`, `run_test_gates.sh`).
- [ ] EC2 redeployed + live probe green (`relay_call_reports_total` on :2112 after one reported call); rollback snapshot retained; version bumped.
- [ ] `VC-09-reliability-quality-RESULTS.md` written: M1 < 10 s median met (or miss recorded honestly + follow-up filed), M2 TURN baseline, M3 observation; freeze table complete.
- [ ] Kill-switch OFF polarities all test-locked (TC-05, TC-16, TC-12); `MKNOON_CALL_QUALITY_REPORT` still default OFF at close (graduation is a separate flag-flip decision).
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

---

## Scope Guard (hard "Do not")

- Do NOT edit VC-04's envelope type definitions, TTL, or glare rules (consume the channel only; adopt its landed glare contract for restart collisions).
- Do NOT edit VC-05's call setup/answer flow beyond: the `reconnecting` state + banner, the `iceTransportPolicy` factory param, sampler/reporter lifecycle hooks.
- Do NOT touch ring/push paths (`background_message_handler.dart`, relay `extractChatPushMetadata`/`buildPushMessage`) — **VC-06/VC-07** own them.
- Do NOT do codec/camera/resolution work or auto-RE-enable video — **VC-08** owns video controls; VC-09 only calls its mute seam.
- Do NOT touch TURN server code/creds (**VC-03**) or circuit-holding/DCUtR (`node.go` host options, `feature_flags.go`, `p2p_bridge_client.dart` flag map — **VC-01/VC-02**; VC-09 flags are Dart-side dart-defines precisely to avoid this collision).
- Do NOT persist call-quality data client-side (no new tables/migrations) or relay-side (counters only); do NOT add any peer-identifying field, label, or log line to the report path.
- Do NOT register `call_*` types in `IncomingMessageRouter` beyond what VC-04 landed; do NOT make call signaling durable/retriable (rule 5).
- Do NOT combine the relay redeploy with any other relay change (one landed story per deploy).
- Do NOT hardcode gate pass counts (rule 6).

---

## Accepted Differences / Intentionally Out Of Scope

- **Quality history is not persisted on-device** — the trail is flow events (capturable) + relay aggregates. A local per-call history table is a could-do; deferred (no owner yet — epic backlog) because the improvement-areas contract needs fleet-level and capture-level answers, not an in-app history UI. No migration keeps this story schema-free.
- **`TransportMetrics` is not extended** with call buckets — its vocabulary is message-transport-specific (`kTransportBuckets`); call aggregates live in the summary event instead. Revisit only if the diagnostics card should show calls (settings UI story).
- **Reconnecting state does not survive process restart** — process death mid-call ends the call (VC-05 lifecycle); drop cause records it. Deliberate, test-locked indirectly via TC-07's cause taxonomy.
- **Client report default OFF at close** — privacy-first staged rollout (rule 3); TURN-share fleet data starts flowing only after the flag graduates (explicit follow-up decision, not this story).
- **iOS device evidence** — deferred-not-waived (rule 1); the Dart logic is platform-neutral and host-locked; a future macOS session owns iOS field proof (VC-07's rig note).
- **Relay rate-limiter is in-memory** (resets on relay restart) — acceptable for an abuse guard on unpersisted counters; mirrors presence-store precedent.

---

## Dependency Impact

- **Depends on:** VC-05 (call feature, pc factory, session controller, device orchestrator — hard Stop-if), VC-04 (signaling channel + seq contract), VC-03 (TURN — forced-relay rows are meaningless without it). VC-08 enriches (degrade rows need its mute seam); VC-06/VC-07 enrich (background calls inherit reconnect for free — no code dependency).
- **Dependents:** none downstream — VC-09 **closes the epic**. The epic's improvement-areas contract (VC-00 metrics table) depends on this story: after VC-09, "why was this call bad?" is answerable from the summary event + relay counters, and flag-graduation decisions (VC-01/VC-02 measurement gates' call-quality dimension) can cite M1/M2 numbers.
- **Collisions:** `lib/features/call/**` + the call orchestrator collide with any in-flight VC-06/07/08 work — sequential on committed trees (VC-00 collision map discipline); `scripts/run_test_gates.sh` array append is a shared-file micro-rebase; relay deploy coordinates with any pending VC-06/07 push-seam deploy (one story per deploy).

---

## Working Piece On Close

A 1:1 call on a real Android device **survives a real network switch**: WiFi dies mid-call and the call is back in under 10 seconds (measured, recorded in the RESULTS doc), or ends honestly with a recorded cause — never a silent hang. Every call leaves a quality trail: per-3s samples and one end-of-call summary (setup ms, direct/punched/TURN path, RTT/jitter/loss/bitrate, drop cause) in the flow-event log, and — for opted-in builds against the redeployed relay — privacy-clean aggregate counters on the live `mknoun.xyz` Prometheus (`relay_call_reports_total`, `relay_call_drops_total`, `relay_call_setup_seconds`, TURN share on Grafana). A user can flip "Always relay (hide my IP)" in Settings and the call provably never uses a direct path — including across reconnects. Sustained bad networks degrade video-to-audio automatically instead of freezing. Everything sits behind test-locked kill-switches, so any regression is one dart-define away from the pre-VC-09 behavior. This is the epic's reliability/metrics contract, closed and buildable-upon.

---

## Reviewer Findings

Sufficiency checklist executed against this draft (2026-07-13): initial pass found (a) TC-20 measurement rows had empty mutation/registration cells → fixed with justified in-cell n/a entries; (b) PROD-CRITICAL leg was implied but unnamed → TC-18 explicitly marked; (c) reporter payload whitelist had no negative assertion (callId leak) → added to TC-12 GREEN asserts + mutation; (d) `transport` gate skip-on-host ambiguity → added to Known-Failure Interpretation; (e) restart-under-forced-relay (policy escape) originally lived only in prose → promoted to TC-15 with its own mutation. All checklist gates now answer Yes. Residual risk flagged for the Arbiter: VC-05 contract anchors are roadmap-shaped, not landed-file-shaped — the execution-start re-resolution step is load-bearing.

**/tdd-review verdict (2026-07-13, applied):** dimension scores — goal-clarity 88 (strong), compartmentalization 70 (adequate), anti-drift 82 (strong), define-good 90 (strong), goal-verification 80 (strong). Material gaps: 0. Moderate gaps: 4, all applied — (1) per-slice RED authoring replaces the waterfall RED catalog (step 1 rewritten; completeness-check/discovery moved to after the final slice); (2) TC-18 device proof pulled forward to new step 4b, immediately after its real dependencies (detector/reconnect/sampler), so the PROD-CRITICAL 10 s finding lands before the unrelated slices 5-8; (3) `MKNOON_CALL_FORCE_RELAY` production wiring pinned (`kCallForceRelay`, factory-resolution-only merge, override-wins, never store-written, TC-14 precedence cases + mutation); (4) TC-19's device leg now exercises the real settings→SecureKeyStore→pc-factory chain (dart-define confined to the emulator leg). Nits applied (7): 12% threshold rationale related to the 10% floor + 2pp flap margin; items-5-6 bundling defense in Real Scope; restart re-offer pinned to VC-04's landed offer type (no new `call_*` type); `relay_call_setup_seconds` buckets pinned `{0.25..30}` + asserted in TC-10 (not the 0.01-floor stream buckets, `metrics.go:257-262`); TC-18 logs grep-able `RECOVERY_ELAPSED_MS` with orchestrator warn >10 s / fail >20 s per trial; M2 TURN sanity floor (3×: ≥60 s connected, loss <12%, else degraded-quality copy variant + follow-up); real process-restart pref durability (force-stop `com.mknoon.app` + relaunch → toggle ON, M2 runsheet row). Cross-plan locks: L5 applied (NO new family array — ONE_TO_ONE_TESTS for headline host tests, NIGHTLY_ONLY_TESTS `run_test_gates.sh:556` for heavy two-party e2e, proof-glob `:1036-1039` for device proofs, orchestrator `run_call_device_real.dart` with `--scenario`/`--list-scenarios`); L2 checked — no-op here (this plan defines no ring-latency metric; ring/push paths are VC-06/VC-07-owned per Scope Guard, and no wake-deposit alternative appears); L1/L3/L4/L6/L7 do not intersect VC-09's surfaces (no TTL, TURN-name, circuit-limit, or punch-outcome content). The pre-committed <10 s median recovery number and the TURN-forced baseline are intact and untouched.

## Arbiter Decision

Structural blockers: none, conditional on the Stop-if (post-VC-05 tree; TC-16 splits out if VC-08 unlanded). Deferred details: exact VC-05 file paths, VC-04 glare adoption, SIM-data availability for the true-switch M1 variant, exact device-leg mechanism for the TC-19 real-toggle enable (settings-card tap vs real-use-case write at app start — either satisfies the production-chain requirement) — all carry execution-start resolution steps. Accepted differences: as listed (no client persistence, report default-OFF, in-memory limiter, iOS deferred-not-waived); plus, per epic lock L2, the 'TTL-d wake deposit' ring alternative is rejected epic-wide (call_* is never durable-inboxed — VC-00 rule 5); VC-09 never proposed it and rule 5 above already restates the fast-path-only contract. Post-review status: accepted (post /tdd-review); all 4 moderate gaps and all 7 nits applied, 0 declined.

## Final Execution Verdict

Verdict: (pending execution) | Files changed: — | Tests run (+counts): — | Blocking: — | QA verdict: — | Non-blocking follow-ups (owner): report-flag graduation decision (epic owner, post-live-data); Grafana call panel polish (ops).
