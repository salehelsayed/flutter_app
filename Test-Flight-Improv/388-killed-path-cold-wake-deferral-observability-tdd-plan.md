# 388 - Killed-path cold-wake storage deferral: make it self-describing, and make one existing device leg able to see it

Status: **EXECUTED (Waves 1-2) 2026-08-19** — Wave 1 closed at host tier, Wave 2 closed at host tier AND on device (`payload_fast_path_cold_kill` carries `coldWakeDeferralScan: 'clean'`). **Wave 3 (TC-388-13) NOT RUN**: plan 386's device legs are still open and this plan's own dependency rule says Wave 3 waits — see Wave 3 Disposition.
Type: Bug
Spec: free-text intent (no formal spec) — gaps **G21** and **G22** of `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md` §4.8
Classification: implementation-ready
Closure tier: **host for Wave 1** (the instrumentation is fully provable at host tier); **device for Waves 2–3** (harness integration, one G21 sample, two G22 artifacts). Wave 1 does NOT close on the device leg — see TC-388-12.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-19 | Evidence Collector | `background_message_handler.dart`, `background_storage_liveness_journal.dart`, `flow_event_emitter.dart`, both host tests, `docker-ws/plan383_g17_recipient_logcat_run{1,2}.txt`, `android/app/build.gradle.kts` | Seam confirmed unchanged since the Plan-383 measurement; exact elapsed discarded at both surfaces; journal has no device reader | verify→refute pass |
| 2026-08-19 | Planner (wf_30b19014-b7a, 10 agents) | + `notification_android_payload_campaign.dart`, `run_notification_tap_device_real.dart`, `device_criteria.dart`, `intro_e2e_runner.dart`, `build_orchestrator.dart`, `production_application_bootstrap.dart`, `CanonicalRuntimeH0ProbeSourceTest.kt`, 386's plan | Map's headline experiment is not runnable; a different existing leg already sits in the exact G21 slot and throws its evidence away | write plan |
| 2026-08-19 | Reviewer (wf_8f60597c-91a, 3 workers + lead source verification) | + `notification_tap_device_criteria_test.dart`, `check_reliability_simulation_discovery.sh`, `run_test_gates.sh` `classify_path`, `android_notification_payload_campaign.dart` (support), `notification_tap_campaign_adapter_contract_test.sh` | **6 blockers, ~14 plan-fixes; core bet CONFIRMED.** Two rows removed as theater/redundant; the new parser file pair de-scoped entirely | apply deltas (this document) |

## Problem And Evidence

- **Behavior to improve:** when the first FCM wake after an app kill exhausts the 2s `display_eligibility` phase budget, the Android background isolate returns without a card and without a suppression event, and the only timing signal it records is a **three-value bucket**. Nobody can tell a comfortable 0.4s from a 1.97s near-miss, and no device gate has ever asserted on the outcome.
- **Impact:** the alert is lost (the message is not — `direct_stage` completed in both measurements). G21's severity is explicitly unmeasured: N=2, one device, one kind, and both samples overran by only ~170–180 ms. The project cannot decide whether this needs a product fix because the instrument cannot measure it.

### Confirmed root cause / current gap

Four confirmed mechanisms, all re-verified in source at HEAD **`59ce6b818`**:

1. **The exit is terminal for that wake.** `background_message_handler.dart:686-693` catches `BackgroundStorageDeadlineExceeded` from the `display_eligibility` phase, awaits `_recordBackgroundStorageDeferred(outcome: 'storage_deferred')` at `:687`, and does a bare `return;` at `:692`. That returns from `firebaseMessagingBackgroundHandler` (body `:591-1663`, no handler-level `finally`). The direct `show()` at `:1139`, the durable `runFinalEffect` publish lane at `:1240`, and all four `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` sites (`:697`, `:797`, `:940`, `:1649`) are downstream. `displayEligibility` is `late final` and never assigned on this path, so the `:694` suppression branch is structurally unreachable.
2. **Exact elapsed is discarded at both surfaces.** The FL details map (`:1701-1714`) and the journal record (`background_storage_liveness_journal.dart:236-243`) each carry the same six keys, and each calls `bucketBackgroundStorageElapsed` (`handler:1707`, `journal:240`). Three buckets, boundaries 2s and 8s (`journal:101-111`). The raw milliseconds exist exactly once, in an unused `toString()` at `handler:108`. The journal record is typed `<String, String>`.
3. **The exception carries TOTAL elapsed, never phase-local.** `_startedAt` is stamped in the constructor (`:117-118`); the `elapsed` getter (`:126-129`) always measures from it; both throw branches — aggregate-exhausted (`:134-139`) and phase timeout (`:141-147`) — pass that same getter. **No phase-start stamp exists anywhere in `run<T>`: phase-local time is not merely unemitted, it is never computed.** One `_BackgroundStorageDeadline` instance per wake (`:625-630`) is shared by all 11 `.run` sites, and **all 11 are sequentially `await`ed** — no `Future.wait`, `unawaited`, `.then(`, `scheduleMicrotask` or `Timer(` appears in `firebaseMessagingBackgroundHandler`, so a single mutable `_phaseStartedAt` field cannot be corrupted by overlap.
4. **The emitted `phase` is the mapped enum, and the mapping collapses.** `:1683-1692` maps phase names to `BackgroundStorageLivenessPhase`, with `_ => localState` swallowing everything unlisted — so `preview_resolution` and `durable_effect_authority` are **permanently indistinguishable** in both the event and the journal. The Plan-383 lock documents this as deliberate ("Pinning the truthful current mapping, not a wished one", `background_storage_deadline_test.dart:1186-1189`).

Real device evidence, read directly from the artifact (`docker-ws/plan383_g17_recipient_logcat_run1.txt`, one line; `_run2.txt`, one line):

```
08-18 12:04:00.012 I/flutter ( 3956): [FLOW] {"ts":"2026-08-18T10:04:00.008733Z", …
  "event":"PUSH_BACKGROUND_STORAGE_DEFERRED","details":{
  "kind":"group_reaction","phase":"display_eligibility","outcome":"storage_deferred",
  "elapsedBucket":"2s_to_8s","buildMode":"debug","engineRole":"flutterfire_background"}}
```

Recomputed against the `PUSH_BACKGROUND_MESSAGE_RECEIVED` anchor (`handler:611-620`, emitted unconditionally with no early return before it): run 1 `10:03:57.838427Z → 10:04:00.008733Z` = **2.170306 s**; run 2 `10:19:40.216377Z → 10:19:42.396501Z` = **2.180124 s**. Branch A (aggregate exhausted) fires only at `elapsed >= 8.000s`, so 2.170306s excludes it; `bound < 2s` would require the phase to start after 6s, which the observed total bounds out. Therefore `bound = 2.000s` exactly — **the 2s phase budget was the binding constraint, not the 8s aggregate**. The abandoned resolver's own later logs (`Future.timeout` does not cancel) put phase-local lower bounds at **2.182 s / 2.255 s**.

### Existing coverage

- `background_storage_deadline_test.dart` (15 tests, `:185`–`:1133`) proves the deadline is **bounded** at host tier — but its `setUp` installs `deadlineScale = 16` (`:52-56`), i.e. **4320 ms aggregate / 4000 ms phase**, only 320 ms of slack. It proves boundedness, not production timing, and its own comment says so (`:35-51`).
- The Plan-383 lock is test 15, `'durable effect authority timeout stays storage-deferred with no fallback card'` (`:1133-1204`). Its assertions are narrower than the name: `record['phase'] == 'local_state'`, `record['outcome'] == 'storage_deferred'`, `journalFiles hasLength(1)`, and `_notificationEffects isEmpty` before and after a late resolver answer. **Its phase is `local_state`, not `display_eligibility`, so it does not cover the G21 exit at all.**
- **Three** existing assertions pin the record shape, not two. `background_storage_liveness_journal_test.dart:90` (`allowedKeys`) and `:91-98` (whole-map equality) — and `background_storage_deadline_test.dart:378-388` (`unorderedEquals` over the six keys), which lives inside a **third** test the first draft never named: `'group eligibility timeout is relay-deferred without false stage'` (`:335`).
- `test/integration/notification_tap_device_criteria_test.dart:57-66` is a **passing** test that builds a `payload_fast_path_cold_kill` artifact with `evidence: {'coldAlertChannel': 'mknoon_messages'}` and asserts `validateNotificationArtifact(artifact).ok, isTrue`.
- A format-agnostic `[FLOW]` parser **already exists and is already wired into the campaign**: `androidNotificationFlowRecords(String logcat)` (`integration_test/support/android_notification_payload_campaign.dart:359`) finds `[FLOW] ` by `indexOf` anywhere in a line and JSON-decodes the remainder, and `_flowRecordsSince(cursor)` (`campaign:1282-1283`) wraps it over `_logcatSince` with five existing call sites (`:1415`, `:1517`, `:1544`, `:1564`, `:2512`). It is already host-tested at `android_notification_payload_campaign_support_test.dart:561`.

### Missing coverage

- **No test anywhere asserts the FL details map of `PUSH_BACKGROUND_STORAGE_DEFERRED`.** Census: one `lib/` site (`handler:1702`), zero hits under `test/`. Adding a key to the FL map alone breaks nothing.
- **No device gate has ever asserted on this outcome.** But one existing leg already sits in the exact slot and discards the evidence — see below.

### Refuted findings (do NOT re-introduce)

- **"Re-measure on a release AOT build" is not runnable as written.** `flowEventLoggingEnabled` does have a `lib/` override — `production_application_bootstrap.dart:511`, gated on `--dart-define=FDC_FLOW_LOG` (`:506-510`) — but it lives inside `_prepareNormalApplication()`, which **the FCM background isolate never runs** (`background_message_handler.dart:590-595`). So this event has no `[FLOW]` line in profile or release **even with `FDC_FLOW_LOG=1`**.
- **"Nothing downstream can observe it."** `_recordBackgroundStorageDeferred` is awaited at `:687` *before* the return and emits both an FL event and a durable journal record. The accurate statement is "no card and no `SUPPRESSED` event".
- **"The recovery vehicle is default-off and uninjected."** `production_application_bootstrap.dart:643` passes `recoveryGraphRegistered: true`, and `canonical_recovery_runtime.dart:302-306` treats a null loader as enabled. It is live in production. It still cannot present: its surface drains **staged** display rows, and the durable-effect authority block opens at `handler:1042` — 350 lines downstream of the return.
- **"The announcement variant is untested on the killed path at every tier."** Too wide. `android_announcement_reaction_recipient` (TC-15, `group_reaction_notification_device_criteria.dart:486`) does kill the recipient and was device-accepted by Plan 257 — but that run is 2026-07-11/14, **three weeks before the deadline seam landed** (`f1b568bca`, 2026-08-04), and no artifact survives. The true hole is the announcement **MESSAGE** killed path.
- **"1:1 reaction is the cheapest next killed-path leg."** Refuted — it is the most expensive. See Deferred.
- **"Exact elapsed cannot be recovered from the existing captures."** It can, by hand, via the `PUSH_BACKGROUND_MESSAGE_RECEIVED` anchor. This plan's instrumentation is for **machine grading of future runs**, not for recovering these two.
- **"A new `[FLOW]` parser and support file are needed."** Refuted by review — `androidNotificationFlowRecords` / `_flowRecordsSince` already do it, are format-agnostic, and are already host-tested. The first draft's new file pair (and the two `classify_path` registrations it implied) is **de-scoped**.
- **"`test/integration/*_test.dart` needs a `classify_path` record."** Refuted: `scripts/run_test_gates.sh:1526-1529` already auto-classifies `^test/integration/.*_test\.dart$` as "repo integration direct suite", and `check_reliability_simulation_discovery.sh` `discover_candidates()` (`:716-742`) never enumerates `test/` at all, so a record line there is unreachable dead code.

### The finding that reshapes the plan

**`_runColdPayloadLeg` already sits in the exact G21 slot, already captures the evidence, and throws it away.** Independently re-verified by review; every sub-claim holds.

- `integration_test/scripts/notification_android_payload_campaign.dart:791-910`, catalogued at `run_notification_tap_device_real.dart:89-103`, in `_androidPayloadCampaignIds` at `:168`/`:172`, dispatched from `run()` at `:256-257`.
- Sequence: `:804` `_terminateReceiver()` → `:805` `_deviceLogcatCursor()` → `:807` `_awaitToneWindow()` → `:809` `_sendText(marker)` → `:816` `_waitForNotification(marker)`. **Nothing touches the receiver between the kill and the graded send**: `_awaitToneWindow` (`:1109-1117`) is a pure host-side `Future.delayed`, and `_deviceLogcatCursor` (`:2480-2481`) reads the byte length of an already-running host-side stream file. **The graded push IS the first wake.**
- **No warm-up, no first-wake rejection.** A census of the full 3128-line adapter for `warm.?up|throwaway|first.?wake|storage_deferred` returns zero hits. The map's "the one device gate that exists cannot observe this" is true only of `groups.muted_notification_campaign`, which does enforce a warm-up (`capture:3589-3617`, `received.skip(1)`).
- **It runs on a warm install.** Install happens once at `:233-236`, then `_runA6()` → `_runWarmPayloadLeg()` → `_runColdPayloadLeg()` (`:248-257`). ProfileInstaller/ART profile work is outside the measured window — **one of Plan 383's two confounds is already removed, at zero cost**.
- **Flow logging is on**: the profile is `provider-configured-debug-apk` (`tool/sims/critical_features.json:53-58`), so `kDebugMode` is true.
- **The window is already captured and already rotation-proof**: `:805` cursor → `:864` `preRestoreLog = await _logcatSince(logcatCursor)`, with live-streaming enforced by `scripts/test/notification_tap_campaign_adapter_contract_test.sh:242-243` (`_deviceLogcatCursor`) and `:248-249` (`_startDeviceLogStream`, with the `logcat -d` ban following). The only predicate applied to it is `:865-873`.
- **Today, if G21 trips, the leg dies at `:816` as an untyped `_waitForNotification` timeout.**

**The receiver is the EMULATOR, not the Pixel.** `_terminateReceiver` targets `emulator` (`:2600`), `receiverIdentity = await _identity(emulator)` (`:239`), and `_sendText` runs on `physical` (`:2024`) — sender = Pixel, receiver = `emulator-5554`. Plan 383's two G21 samples were on the **physical Pixel**. Wave 2 therefore measures a **different device class**; see TC-388-12's honest scope.

### Affected production / test / gate files

- `lib/features/push/application/background_message_handler.dart` — `_BackgroundStorageDeadline.run`, `BackgroundStorageDeadlineExceeded`, `_recordBackgroundStorageDeferred`.
- `lib/features/push/application/background_storage_liveness_journal.dart` — `recordTerminal` / `_persistTerminal`, plus one new closed phase-name enum.
- `test/features/push/application/background_storage_deadline_test.dart` (**three** tests touched: the two new rows plus the existing `:335` key-set widening), `test/features/push/application/background_storage_liveness_journal_test.dart` (**10** `recordTerminal(` call sites, `allowedKeys` at `:78-85`, whole-map equality at `:91-98`).
- `integration_test/scripts/notification_android_payload_campaign.dart`.
- `tool/sims/device_criteria.dart` `_notificationEvidenceRequirements` (`:626-707`, cold-kill entry at `:630-632`).
- `test/integration/notification_tap_device_criteria_test.dart` (new row **and** repair of the existing green rows at `:62` and `:137`).
- `scripts/test/notification_tap_campaign_adapter_contract_test.sh`.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `9159ad66b3b286d0`, `stale:lib/smoke_test_main.dart`. `graphify-arch/.needs_incremental_refresh` is present; **not rebuilt** — every seam line was read in current source, and a rebuild would churn shared files.
- Query / profile: `python3 graphify-arch/tdd_context.py query "_recordBackgroundStorageDeferred _BackgroundStorageDeadline background_message_handler.dart storage_deferred elapsedBucket" --profile tdd --budget 700` → `confidence=anchored`. Review pass: `--profile review --budget 800` on `BackgroundStorageDeadlineExceeded recordTerminal` → `confidence=anchored`.
- Anchors: `_recordBackgroundStorageDeferred` → `background_message_handler.dart:1669`; `recordTerminal` → `background_storage_liveness_journal.dart:174`; `_BackgroundStorageDeadline` → `handler:111`.
- Surfaced proof/gate files: `background_message_handler_test.dart`, `background_message_handler_staging_test.dart`, `background_push_notification_fallback.dart`.
- Graph gaps that required raw source search: everything under `integration_test/scripts/`, `tool/sims/*.json`, `android/**/*.kts`, `android/**/*.kt`, `scripts/**/*.sh`, and the `docker-ws/*.txt` device artifacts.
- Reuse rule: anchors are search starting points; every conclusion here was re-derived from current source or command output.

## Scope Contract And Guard

**In scope:**
- Compute and emit phase-local elapsed, exact total elapsed, and the applied budget at every deferral, on **both** surfaces (FL event and durable journal).
- Emit a **closed-domain** raw phase identifier alongside the mapped enum, so `preview_resolution` and `durable_effect_authority` stop collapsing into `local_state` — **as an enum or validated allow-list, never a free caller string** (see the first Hard `Do not`).
- Make the payload campaign read the window `_runColdPayloadLeg` already captures, using the **existing** `_flowRecordsSince` helper: classify a cold-leg failure as a storage deferral by name instead of an untyped timeout, and record a scan result on every successful run.
- Re-run two already-registered killed-path reaction scenarios to produce artifacts that do not exist (Wave 3).

**Must preserve:**
- The journal's **redaction contract and its closed-domain guarantee** → `background_storage_liveness_journal_test.dart` forbidden-substring scan plus the new domain assertion (TC-388-04, TC-388-06).
- The Plan-383 deferral lock → `background_storage_deadline_test.dart:1133` (TC-388-07).
- The journal's 200 ms caller bound → its existing bound test (TC-388-06).
- The Kotlin H0 probe's source-parse of both files → `CanonicalRuntimeH0ProbeSourceTest.kt:190-232` (TC-388-08).
- The `_runColdPayloadLeg` source-slice freeze → `test/integration/android_notification_payload_campaign_support_test.dart:131-157` (TC-388-10).
- The two currently-green cold-artifact rows → `notification_tap_device_criteria_test.dart:57-66` and `:132-139` (TC-388-11).

**Hard `Do not`:**
- **Do not persist a free caller-provided `String` in the journal record.** `background_storage_liveness_journal.dart:50-52` states the invariant in its own doc comment: *"Values are fixed rather than caller-provided strings so an identifier cannot accidentally be persisted in the phase field."* The raw phase identifier must be a closed enum or a validated allow-list with an explicit `unknown` fallback. At HEAD all 11 `.run(` sites pass compile-time literals; the guard exists so a future interpolated argument cannot leak.
- **Do not change any deadline constant, or rename/reformat one.** The values are pinned in four places, two of them enforcing gates, and the Kotlin pin parses the Dart source **by constant name**: `background_message_handler.dart:78-81`, `CanonicalRuntimeH0ProbeReceiver.kt` (hard-coded `8_000`), `run_android_canonical_runtime_h0_probe.sh:388-393`, and `CanonicalRuntimeH0ProbeSourceTest.kt:200-232`.
- **Do not add a fallback card, a retry, or any alerting change for `storage_deferred`.** This plan measures.
- **Do not create a new `[FLOW]` parser or support file.** `androidNotificationFlowRecords` / `_flowRecordsSince` already exist, are format-agnostic, and are already host-tested. Calling them requires no edit to any Plan-386 file.
- **Do not edit `scripts/run_test_gates.sh` or `scripts/check_reliability_simulation_discovery.sh`.** No registration is needed (see Refuted findings), and `run_test_gates.sh` is the one file Plan 386 also edits.
- **Do not insert a method between `_runColdPayloadLeg` and `_restartAndDrain`, and do not insert any statement between `await _waitForNotification(marker);`, `await _terminateReceiver();` and `await _setNetworkAvailable(false);`.** The freeze slice is delimited by the next method's signature and its regex requires those three adjacent. Also keep the string `headless FCM process exit before cold tap` out of any new comment inside the leg (`support_test:154-157` asserts its absence).

**Deferred / accepted difference:**
- **Alerting for `storage_deferred`** → owner: dropped-push-recovery activation wave (GAP-N08/WP), gated on Wave 2's measurement series.
- **A positive control that makes the device leg prove Wave-1 code** (a debug-only lever installing a 1 ms `display_eligibility` budget for one graded send, so the run emits a record carrying the new fields) → owner: unowned, deliberately not built. It adds a new production debug lever for a benefit Wave 1 already gets at host tier. Its absence is why TC-388-12 is **not** Wave-1 closure.
- **Release/profile AOT re-measurement** → owner: a follow-on plan. A `--profile` APK is AOT **and** debuggable and `run-as` reaches the journal (verified live on `21071FDF600CSC`), but sims builds debug only (`build_orchestrator.dart:1113-1116`), the E2E poller is hard-gated on `kDebugMode` (`intro_e2e_runner.dart:881-884`), and the state guard restores the APK at teardown. Wave 2 removes the ProfileInstaller confound for free; only the JIT-vs-AOT confound needs this.
- **1:1 REACTION killed-path device leg** → owner: unowned, costed. Needs four things that do not exist, two inside `lib/`: a poller config action calling `send_reaction_use_case.dart:127-135`; composition-root wiring of `ReactionRepository` into the poller (the adapter contract sh pins the analogous staging-store wiring at `:255-261`); and a reaction-aware card oracle, because `_observeAudibleChannel` (`campaign:1125-1133`) resolves by body-equals-marker.
- **Media MESSAGE and announcement MESSAGE killed-path legs** → owner: unowned. Media **reactions** are already killed and graded three per run by the Plan-330 lane (`capture:2523-2537`).
- **Upgrading the scan from evidence to a catalog required check** → owner: unowned. 12 editable locations across 7 files.
- **Accepted difference:** on the success path the artifact's scan value is knowable a priori, so it is a **presence-and-provenance** guard, not a measurement. The anti-fabrication weight is carried by TC-388-10's source contract, exactly as `device_criteria.dart:616-622` describes for every other claimed-true check.

**Dependencies:**
- **Plan 386's source waves have LANDED** — `4040feb82`, `9c6874e25`, `59ce6b818`. Only its device legs remain, and its `Status:` header is still `execution-ready`. The working tree is clean for all five directories this plan's stop-if names.
- **Waves 1–2 touch none of Plan 386's files**, now that the parser file pair and the `run_test_gates.sh` registration are de-scoped. Re-check `git log --oneline -5` before editing anyway.
- **Wave 3** re-runs scenarios inside the reaction campaign. Confirm G16's provider-evidence repair is device-green before scheduling it; if 386's device legs are still open, Wave 3 waits.
- Waves 1–3 contend for the **device pair**: `critical_features.json:673` marks `device:android-physical`, `device:android-emulator` and `relay-mutation:staging` `exclusive`.

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.
**Rows removed by review:** the first draft's TC-388-05 (all-five-exits field presence) was **theater** — every exit funnels through one shared `_recordBackgroundStorageDeferred` and the fields ride on the exception, so no per-catch field can be withheld and the named mutation is inexpressible; its genuine content is folded into TC-388-04. The first draft's TC-388-09 (a new parser) is **de-scoped** — the parser already exists and is already host-tested. Numbering is preserved for traceability.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| **TC-388-01** | A deadline exception carries phase-local elapsed and the budget actually applied, on both throw branches, distinct from total elapsed | `background_storage_deadline_test.dart::'phase-local elapsed and the applied budget are exact on both throw branches'` | unit host / `_FakeMonotonicClock` (`:1352-1360`) + `debugSetBackgroundStorageMonotonicClockFactory` (`handler:184-188`) + in-body `debugSetBackgroundStorageDeadlineDurations` | causal RED (`BackgroundStorageDeadlineExceeded` has no `phaseElapsed`/`budget` member — compile failure; the missing field IS the contract) → **exact equalities** against the injected clock: phase 1 advances the clock by a chosen `d1`; phase 2 trips with `phaseElapsed == bound`, `elapsed == d1 + bound`, `budget == bound`; **and** a second case where the aggregate remainder is smaller than the configured phase, asserting `budget == remaining ≠ phase`; **and** an aggregate-exhausted case asserting `phaseElapsed == Duration.zero` | remove the `_phaseStartedAt` stamp → the exact `phaseElapsed` equality reds; return the configured `phase` instead of `bound` → the aggregate-remainder case reds; stamp after the `remaining` check instead of before → the aggregate-exhausted case reds | `flutter test test/features/push/application/background_storage_deadline_test.dart`; AUTO (glob) + already in `GROUP_TESTS` (`run_test_gates.sh:687`) |
| **TC-388-02** | The FL deferral event carries exact `elapsedMs`, `phaseElapsedMs`, `budgetMs` and the closed-domain `phaseName` | `background_storage_deadline_test.dart::'the deferral flow event carries exact timings and the closed phase identifier'` | unit host / captured `FlowEventSink` lease + injected clock, same fixture as TC-388-01 | causal RED (no test reads the FL map today; the four keys do not exist at `handler:1701-1714`) → the captured details map carries all four; `int.parse(phaseElapsedMs) == bound.inMilliseconds` and `int.parse(elapsedMs) == (d1 + bound).inMilliseconds` — **exact, not a range**; `elapsedBucket` unchanged | emit total elapsed as `phaseElapsedMs` → reds (the two exact values differ by `d1`); emit the configured phase as `budgetMs` → reds on the aggregate-remainder case | same command as TC-388-01; AUTO (glob) |
| **TC-388-03** | The durable journal record carries the same four fields and survives the atomic rename | `background_storage_liveness_journal_test.dart::'terminal records carry exact timings across the atomic publish'` | unit host / real files in a temp root, read back after publish | causal RED (extend `allowedKeys` at `:78-85` first → `record.keys.toSet()` at `:90` and the whole-map equality at `:91-98` fail because production emits only six keys) → the read-back record has all ten keys with the exact values | drop the four keys from `_persistTerminal` → TC-388-03 red | `flutter test test/features/push/application/background_storage_liveness_journal_test.dart`; AUTO (glob) + `GROUP_TESTS` (`run_test_gates.sh:688`) |
| **TC-388-04** | The raw phase identifier discriminates the collapsed phases **and** is drawn from a closed domain that a caller cannot widen | `background_storage_liveness_journal_test.dart::'the raw phase identifier is closed-domain and tells local_state phases apart'` | unit host / drives a deferral per phase name + a source census of `storageDeadline.run('` first arguments | causal RED (`preview_resolution` and `durable_effect_authority` both map to `localState` at `handler:1692`, so their records are identical apart from timings) → both keep `phase == 'local_state'` **and** carry distinct raw identifiers; every one of the 11 `.run(` first arguments is a literal member of the declared domain; an out-of-domain value maps to `unknown` | delete the raw identifier → the discrimination assertion reds; pass an interpolated (non-literal) phase name → the census assertion reds; drop the `unknown` fallback → the out-of-domain case throws instead of degrading | `flutter test test/features/push/application/background_storage_liveness_journal_test.dart`; AUTO (glob) |
| **TC-388-06** | Redaction, the closed key-set, and the 200 ms caller bound survive the widening | `background_storage_liveness_journal_test.dart::'release records use complete atomic slots, stay bounded, and redact'` | unit host / **three** edit sites: the `recordTerminal(...)` calls (10 sites, `:50`, `:130`, `:162`, `:202`, `:233`, `:258`, `:296`, `:323`, `:337`, `:361`), `allowedKeys` `:78-85`, whole-map equality `:91-98` | GREEN sentinel (passes today; **the fixture is widened at all three sites, and until it is, the whole file is red — this is expected, not a defect**) → still passes; the nine forbidden substrings still absent and the 200 ms bound still met | set the raw phase identifier to a value containing `messageId` and pass it through the widened API → the forbidden-substring scan reds (and TC-388-04's domain assertion reds first) | `flutter test test/features/push/application/background_storage_liveness_journal_test.dart`; AUTO (glob) |
| **TC-388-07** | The Plan-383 deferral lock still holds: a held durable-effect authority stays `storage_deferred` with no card, before and after a late answer | `background_storage_deadline_test.dart::'durable effect authority timeout stays storage-deferred with no fallback card'` (`:1133`) | unit host / existing fixture, untouched | GREEN sentinel (passes today) → still passes; `record['phase']` is still `'local_state'` (TC-388-04 adds a sibling identifier, it does not remap the enum) | change the `_ => localState` default at `handler:1692` to a new enum value → TC-388-07 red | same command as TC-388-01; AUTO (glob) |
| **TC-388-08** | The Kotlin H0 probe's source-parse of both Dart files still holds | `android/app/src/test/kotlin/com/mknoon/app/CanonicalRuntimeH0ProbeSourceTest.kt` (`:190-232`) | JVM unit / regex parse of Dart source text compared to native artifact integers | GREEN sentinel (passes today) → still passes; it extracts `_productionBackgroundStorageAggregateDeadline`, `_productionBackgroundStoragePhaseDeadline` and `backgroundStorageLivenessJournalMaxCallerImpact` **by constant name**, none of which this plan touches | rename or reformat any of those three constants → TC-388-08 red | `./android/gradlew -p android :app:testDebugUnitTest --tests '*CanonicalRuntimeH0ProbeSourceTest*'` — **not** via `host-run bash -lc`, which the bridge refuses (see Acceptance Gates); existing registration, no new entry |
| **TC-388-10** | A cold-leg failure is classified: if the graded wake was storage-deferred, the campaign says so by name instead of dying as an untyped `_waitForNotification` timeout | `scripts/test/notification_tap_campaign_adapter_contract_test.sh::'cold leg failures are classified against the captured wake window'` + `android_notification_payload_campaign_support_test.dart:131-157` (unmodified) | host contract shell / `grep -Fq` source assertions over the adapter | causal RED for the new sh assertions (`run()`'s cold dispatch has no classifier; the leg stores no cursor field) → the contract asserts the cold cursor is stored on the instance, `run()`'s cold dispatch is wrapped, the classifier calls `_flowRecordsSince`, and it raises a `_Failure` naming the phase and exact ms | delete the classifier from `run()` → the sh assertion reds; move any statement between the three frozen statements → the freeze regex at `:147-153` reds | `/claude-host-bin/host-run bash scripts/test/notification_tap_campaign_adapter_contract_test.sh` (exit 0) and `flutter test test/integration/android_notification_payload_campaign_support_test.dart` (exit 0, file unmodified); already inside `./scripts/run_test_gates.sh sims-contracts` |
| **TC-388-11** | The cold-kill artifact proves the deferral scan ran on the graded window, and the validator requires it | `test/integration/notification_tap_device_criteria_test.dart::'cold-kill artifacts must carry a wake deferral scan result'` | integration host / artifact-map fixtures against `device_criteria.dart` `_notificationEvidenceRequirements` | causal RED (the cold-kill entry at `:630-632` carries only `coldAlertChannel`, so an artifact omitting the scan validates clean) → an artifact missing `coldWakeDeferralScan` is rejected; one carrying `'clean'` passes; any other value is rejected. **Blast radius the executor must expect:** the two currently-green rows at `:62` and `:137` red until their evidence maps gain the key | remove the `coldWakeDeferralScan` entry from `_notificationEvidenceRequirements` → TC-388-11 red | `flutter test test/integration/notification_tap_device_criteria_test.dart` (host-all-only → direct command, run **whole-file**, no `--plain-name`); **no registration needed** — `run_test_gates.sh:1526-1529` already auto-classifies this path |
| **TC-388-12** | On the real pair, a killed 1:1 first wake on a warm install reaches its card, and the classifier + scan are proven wired end to end | device run of `payload_fast_path_cold_kill` in `notifications.android_payload_campaign` | device proof / sender = physical `21071FDF600CSC`, **receiver = `emulator-5554`**, real relay, `android.production_fcm` | manual/device-only proof → the artifact carries `coldWakeDeferralScan: 'clean'` beside `coldAlertChannel == mknoon_messages`: one machine-recorded warm-install first-wake sample that did not defer, on the **emulator**. **This is Wave-2 harness-integration evidence, NOT Wave-1 closure** — on the clean path no deferral record is emitted, so the run exercises none of Wave 1's new fields and a stale APK would produce a byte-identical pass | revert the classifier and the scan and re-run → the artifact loses `coldWakeDeferralScan` and TC-388-11 rejects it | `.claude/skills/sims/scripts/run_with_devices.sh major --only notifications.android_payload_campaign`; already registered (`run_notification_tap_device_real.dart:89-103`, `:168`/`:172`) |
| **TC-388-13** | Two already-registered killed-path reaction kinds are re-proven current on a build that contains the deadline seam | device runs of `--scenario android_announcement_reaction_recipient` (`group_reaction_notification_device_criteria.dart:486`) and the Plan-330 media-target reactions (`capture_group_reaction_notification_device.dart:2523-2537`) | device proof / same pinned pair, `groups.reaction_notification_campaign` | manual/device-only proof → each produces a passing artifact, including the campaign's own empty-`pidof`-before-delivery assertion, on a post-`f1b568bca` build. Today the only announcement-reaction evidence is Plan 257's, dated three weeks before the seam landed, with no surviving artifact | not a code mutation — this row is **currency verification**, and its falsifier is the run: if either kind now defers on its first wake, the existing criteria fails on the missing card. **Honest limit: that failure will be untyped**, because the classifier lands only in the payload lane; typing it in the reaction lane is deferred | `.claude/skills/sims/scripts/run_with_devices.sh major --only groups.reaction_notification_campaign`; existing registration, no new entry |

### Test Notes

- **TC-388-01/02 must set their own budgets in the test body.** The file's `setUp` installs `deadlineScale = 16` → 4320 ms aggregate / 4000 ms phase, only 320 ms of slack, which cannot satisfy an aggregate-remainder case and a robust phase-local case at once. Call `debugSetBackgroundStorageDeadlineDurations(aggregate:, phase:)` inside the test; `tearDown` at `:176` already restores.
- **Assert exact equalities against the injected clock, never relations.** `phaseElapsed < elapsed` alone is passed by an implementation with **no** stamp at all: `onTimeout` fires exactly `bound` after `action()` is attached, so the true phase-local elapsed already *is* ~`bound`. The `_FakeMonotonicClock` makes exact equality cheap; use it.
- **`budget == phase` is the non-discriminating case.** `bound = min(remaining, phase)`, so in the ordinary case `bound == phase` and an implementation emitting the configured constant passes. The aggregate-remainder case (start the tripping phase with `remaining < phase`) is what makes `budgetMs` load-bearing.
- **Stamp placement is load-bearing.** `run<T>` is `Future<T> run<T>(...)`, **not `async`** (`handler:131`), so the aggregate-exhausted branch at `:134-139` throws synchronously before the phase begins. Stamp `_phaseStartedAt` as the **first statement after the `if (!enabled)` guard**, before the `remaining` check — otherwise that branch reports the *previous* phase's stale stamp.
- **TC-388-04 assertions bind two things on one record.** Assert the mapped enum and the raw identifier on the **same** decoded record, not via two independent reads.
- **TC-388-10: the diagnosis cannot be wrapped around `_waitForNotification`.** A deferral means no card appears, so the leg dies at `campaign:816` — 48 lines before the window is read at `:864`. Wrapping `:816` in a try/catch breaks the freeze regex, which requires the three statements adjacent with only whitespace between. Freeze-safe shape: store the cursor on the instance at `:805` (before the frozen triple), and classify in `run()`'s cold dispatch at `:256-257`, outside the frozen slice.
- **Scope the success-path scan to the wake window, not `preRestoreLog`.** `preRestoreLog` spans the cursor at `:805` all the way to `:864` — the graded wake **plus** the tap at `:851`, the cold relaunch at `:852-856`, the observer action at `:857-862` and the UI wait at `:863`, roughly a minute. `engineRole` is the hard-coded `'flutterfire_background'`, so a later wake's deferral would be misattributed to the graded one. Take a second cursor immediately after the frozen triple and scope the success-path scan to `[coldCursor, postCardCursor)`. The failure-path classifier may read the full window, where the extra span is harmless.
- **The parser is already there and already format-agnostic.** `androidNotificationFlowRecords` locates `[FLOW] ` by `indexOf` and JSON-decodes the remainder, so it handles the 383 artifacts' `-v time` prefix and the campaign's stream format identically. Use `_flowRecordsSince(cursor)` (`campaign:1282-1283`) and filter on `event == 'PUSH_BACKGROUND_STORAGE_DEFERRED'`. **Do not** anchor anything on a date/time prefix.
- **The scan result is a presence-and-provenance guard, not a measurement.** On the success path `'clean'` is knowable a priori, so a leg that hard-coded it would pass TC-388-11 and TC-388-12. That is the exact failure mode `device_criteria.dart:616-622` describes for every claimed-true check, and the repo's answer is the same one used everywhere else: the source contract (TC-388-10) is what proves the scan ran.
- **Why the 1:1-reaction host row cannot substitute for a device leg.** `background_message_handler_test.dart:915-998` (`'authenticated durable-authority deferral presents the non-durable fallback card (direct reaction)'`) stubs the eligibility resolver to return instantly at `:921-923`, so the 2s budget can never be consumed; it also fakes the stager, resolver, DB and plugin channel and runs in-process. It asserts `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED`, a different exit.

## Implementation Steps

1. Snapshot `git status --short` and `git log --oneline -5`. **Stop-if for Wave 1:** `lib/features/push/` or `test/features/push/` is dirty. **Stop-if for Waves 2–3:** additionally `integration_test/scripts/`, `test/integration/` or `tool/sims/` is dirty. (Split by wave deliberately: Plan 386's own stop-if claims the same two shared directories, so a single five-directory guard would deadlock the two plans against each other.) Add the causal REDs before any production edit.
2. **Wave 1 production edits.**
   - `background_message_handler.dart`: add a closed phase-identifier enum (or a validated allow-list) covering the 11 `.run` names plus `unknown`; stamp `_phaseStartedAt = _elapsed()` as the **first statement after the `if (!enabled)` guard** in `run<T>`; give `BackgroundStorageDeadlineExceeded` `phaseElapsed` and `budget`, populated on both throw branches (`:134-139` → `phaseElapsed == Duration.zero`, `budget == Duration.zero`; `:141-147` → `phaseElapsed == bound`, `budget == bound`); add `elapsedMs`, `phaseElapsedMs`, `budgetMs`, `phaseName` to the FL details map at `:1701-1714` and pass them to `recordTerminal`.
   - `background_storage_liveness_journal.dart`: widen `recordTerminal`/`_persistTerminal` to take the three durations and the closed phase identifier, and write them as decimal-millisecond strings at `:236-243` so the record stays `<String, String>`.
   - **Expect the whole of `background_storage_liveness_journal_test.dart` to red first** — 10 `recordTerminal(` call sites must pass the new arguments. Widen them, then `allowedKeys`, then the whole-map equality.
   - Stop-if: any deadline **constant** needs changing, or the phase identifier cannot be closed-domain → replan.
3. **Wave 2 edits.** In `notification_android_payload_campaign.dart`:
   - store the cold cursor on the instance at `:805` (one added line, before the frozen triple), and take a second cursor immediately after the frozen triple;
   - on the **success** path, call `_flowRecordsSince` over `[coldCursor, postCardCursor)` and put `coldWakeDeferralScan: 'clean'` into the scenario artifact's evidence — or raise a named `_Failure` if a deferral is present on a run that still carded;
   - on the **failure** path, wrap `run()`'s cold dispatch at `:256-257` in a classifier that re-reads from the stored cursor and raises `_Failure('Cold graded wake was storage-deferred: <phaseName> <phaseElapsedMs>ms', assertionsAttempted: _assertionsAttempted)`, otherwise rethrowing unchanged.
   - Register `coldWakeDeferralScan` in `device_criteria.dart` `_notificationEvidenceRequirements` under `payload_fast_path_cold_kill` (`:630-632`) with the allowed set `{'clean'}`; add the key to the two existing green fixtures at `notification_tap_device_criteria_test.dart:62` and `:137`; add the new rejecting row; and add the source assertions to the adapter contract sh.
   - **No new files. No `classify_path` edits. No `scripts/run_test_gates.sh` edit.**
4. Run focused GREEN → preservation sentinels → `affected` → the `groups` lane → the sims-contracts shell → Wave 2's device leg. Wave 3 runs after 386's device legs close.

## Risks And Blind Spots

- **A `display_eligibility`-only fix leaves siblings behind** → the fields are added once, in `run<T>` and the shared `_recordBackgroundStorageDeferred`, so all exits inherit them structurally; TC-388-04's per-phase discrimination is what proves the *identity* of each exit survives. Verified census: `_recordBackgroundStorageDeferred` has **11** call sites (`:649`, `:672`, `:687`, `:757`, `:770`, `:786`, `:876`, `:1107`, `:1446`, `:1506`, `:1523`), **five** carry `outcome: 'storage_deferred'` (`:690`, `:760`, `:789`, `:879`, `:1110`), and there are **six** card-killing bare `return;` exits before the show lane (`:677`, `:692`, `:762`, `:775`, `:791`, `:1115`). **The three sets differ**: `:677`/`:775` are `custody_write_pending`, and `:879` records but does **not** return. Re-derive all three at execution time.
- **The device leg cannot prove Wave 1** → named and accepted. On the clean path no deferral record exists, so `buildMode` self-certifies nothing and a stale APK yields a byte-identical pass. TC-388-12 is demoted to harness-integration evidence and the positive-control option is recorded under Deferred.
- **The device sample is on the emulator, not the Pixel** → stated in TC-388-12. Plan 383's N=2 are Pixel samples; comparing them is cross-device and must be reported as such, not as a re-measurement.
- **Lifecycle / derived-state durability:** the new fields must survive the temporary-file → atomic-rename publish → TC-388-03 reads the record back off disk after publish.
- **Sibling-surface consistency:** TC-388-04 (all collapsed phases, plus the closed-domain census over all 11 `.run(` sites).
- **Destructive-action side effects:** N/A — `_pruneOldest` is count-based, not byte-based, so four added string fields cannot change what it deletes. The 200 ms caller bound is the only size-sensitive contract, held by TC-388-06.
- **Invariant re-verification under new transitions:** N/A — no transition is added. But one **existing** invariant is re-opened and re-closed: the journal's "no caller-provided strings" rule (`journal:50-52`), guarded by TC-388-04's domain assertion.
- **Construction / call-site census:** re-derive the three sets above with `grep -n '_recordBackgroundStorageDeferred(' `, `grep -n "outcome: '" ` and a read of each catch block. Never assert the fixed lists.
- **Build-artifact provenance:** unresolved for the device leg by design (see the second bullet). The campaign's state guard and the repo's `versionName 1.0.0-<sha>` deploy stamp remain the only provenance signals, and neither is asserted by this plan's artifact.
- **Permission / ACL verb symmetry:** N/A — no permission or ACL check is added or changed.
- **Fake side-effect fidelity:** the host fixtures write **real files** through the production `_writeAtomically`/`_pruneOldest` path. The one fake that matters is called out in Test Notes: the 1:1-reaction host row stubs the eligibility resolver so the budget can never be consumed.
- **Composite-node / relationship assertions:** TC-388-01 asserts three durations on one thrown object; TC-388-02 asserts the exact pair on one details map; TC-388-04 asserts the enum and the raw identifier on one decoded record.

## Gate Cadence

- **Per-plan closure:** the focused causal tests (TC-388-01…04, 10, 11), the preservation sentinels (TC-388-06, 07, 08, plus the unmodified campaign freeze), the `groups` curated lane (all three push host tests are in `GROUP_TESTS` at `run_test_gates.sh:685`, `:687`, `:688`), `sims-contracts` for the adapter shell, and the device legs.
- **Graph-affected first:** after the Wave 1 production edits and **before** the `groups` lane, run `python3 graphify-arch/tdd_context.py affected lib/features/push/application/background_message_handler.dart lib/features/push/application/background_storage_liveness_journal.dart --budget 600` and `flutter test` the files it names. Path-string tests have no import edge and stay lane-only — including `CanonicalRuntimeH0ProbeSourceTest.kt`, which is Gradle-side and invisible to the graph.
- **Full `host-all` is not a per-plan gate.** It is owned by the notification wave carrying plans 383/384/385/386 and by final rollout/release closure.
- **Shared tests outside the feature/core globs:** `test/integration/notification_tap_device_criteria_test.dart` and `test/integration/android_notification_payload_campaign_support_test.dart` are `host-all`-only and get direct `flutter test <path>` commands below. No new `test/integration/` file is created.

## Acceptance Gates  (literal — copy/paste)

```bash
# Dirty-tree snapshot + landing check before execution
git status --short
git log --oneline -5          # confirm Plan 386's 4040feb82 / 9c6874e25 / 59ce6b818 are present

# --- Causal REDs (before production edits) — each must FAIL for its documented reason ---
flutter test test/features/push/application/background_storage_deadline_test.dart \
  --plain-name 'phase-local elapsed and the applied budget are exact on both throw branches'
flutter test test/features/push/application/background_storage_liveness_journal_test.dart
#   ^ whole file: after widening allowedKeys + the whole-map equality it reds because
#     production emits six keys. Expect the 10 recordTerminal call sites to be widened too.
flutter test test/integration/notification_tap_device_criteria_test.dart
#   ^ whole file, NOT --plain-name: a selector miss exits non-zero and would record a false RED.

# --- Focused GREEN (after the fix) — exit 0, zero failures ---
flutter test test/features/push/application/background_storage_deadline_test.dart
flutter test test/features/push/application/background_storage_liveness_journal_test.dart
flutter test test/integration/notification_tap_device_criteria_test.dart

# --- Preservation sentinels — exit 0, and the campaign support test must be UNMODIFIED ---
flutter test test/features/push/application/background_storage_deadline_test.dart \
  --plain-name 'durable effect authority timeout stays storage-deferred with no fallback card'
flutter test test/integration/android_notification_payload_campaign_support_test.dart
git diff --name-only -- test/integration/android_notification_payload_campaign_support_test.dart \
  integration_test/support/android_notification_payload_campaign.dart \
  scripts/run_test_gates.sh scripts/check_reliability_simulation_discovery.sh   # expect: EMPTY

# Kotlin H0 source pin. NOTE: `/claude-host-bin/host-run bash -lc '<cmd>'` is REFUSED
# ("shell commands must name a script file inside the repo") — call gradlew path-qualified:
./android/gradlew -p android :app:testDebugUnitTest --tests '*CanonicalRuntimeH0ProbeSourceTest*'
# If the container cannot reach the Android SDK, use the repo-script form the two existing
# native gates use (scripts/test/run_app_visibility_native_371.sh:118,
# scripts/test/run_android_headless_recovery_native_374.sh:74) via
# `/claude-host-bin/host-run bash <that script>`.

# --- Graph-affected dependents BEFORE the lane ---
python3 graphify-arch/tdd_context.py affected \
  lib/features/push/application/background_message_handler.dart \
  lib/features/push/application/background_storage_liveness_journal.dart --budget 600
# then: flutter test <each test file it names>

# --- Curated lane + contract shell — exit 0 ---
./scripts/run_test_gates.sh groups
/claude-host-bin/host-run bash scripts/test/notification_tap_campaign_adapter_contract_test.sh
./scripts/run_test_gates.sh sims-contracts   # expect: 43 PASS / 1 FAIL, exit 1 — G28 is pre-existing (plan 387)

# --- Registration: nothing to add, so verify the auto-classification instead ---
./scripts/run_test_gates.sh completeness-check          # expect: PASS, 0 unmatched
grep -c 'coldWakeDeferralScan' tool/sims/device_criteria.dart   # expect: >= 1

# --- Device (Wave 2; Wave 3 after 386's device legs close) ---
flutter devices --machine ; adb devices -l     # expect: 21071FDF600CSC + emulator-5554 both 'device'
.claude/skills/sims/scripts/run_with_devices.sh major --list
.claude/skills/sims/scripts/run_with_devices.sh major --only notifications.android_payload_campaign
.claude/skills/sims/scripts/run_with_devices.sh major --only groups.reaction_notification_campaign

# --- Hygiene ---
flutter analyze            # 0 new issues
git diff --check
```

## Execution Interpretation And Done Criteria

- **Expected RED:** TC-388-01/02/04 fail to compile or assert because the fields and the phase-identifier domain do not exist. TC-388-03 fails on the widened `allowedKeys` and the whole-map equality. **Also expected and previously unattributed:** `background_storage_deadline_test.dart:378-388` inside `'group eligibility timeout is relay-deferred without false stage'` reds on the added keys, and **all 10 `recordTerminal(` call sites** in the journal test must be widened before that file compiles. TC-388-11 fails because `_notificationEvidenceRequirements` has no entry, and the two existing green rows at `:62`/`:137` red until their fixtures gain the key. TC-388-10's new sh assertions fail because the classifier does not exist.
- **GREEN sentinel:** TC-388-06 (redaction + bound + closed domain), TC-388-07 (the Plan-383 lock, `phase` still `local_state`), TC-388-08 (the Kotlin constant parse), and the campaign support test passing **with a clean `git diff`**.
- **Pre-existing dirty tree / known failure:** `./scripts/run_test_gates.sh sims-contracts` exits **1** at contract #26 (`run_claude_docker_update_contract_test.sh`). That is **G28**, recorded and deliberately unfixed by Plan 387. 43 PASS / 1 FAIL is the baseline.
- **Environment blocker (NOT a product blocker):** the device pair held by a Plan 386 device run — both devices are `exclusive` in `critical_features.json:673`. A release/profile AOT build is `N/A (blocked by the debug-only sims builder and the kDebugMode-gated poller)`.
- **Scope drift (BLOCKING):** any change to a deadline constant or its name; any alerting or fallback-card change; a free-`String` phase field in the journal; a new parser file; any edit to `scripts/run_test_gates.sh`, `check_reliability_simulation_discovery.sh`, or the two Plan-386 campaign-support files; any statement inserted into the frozen three-statement sequence.

- [x] Every behavior has a named test or a justified proof. (TC-388-13 excepted — deferred with cause, see Wave 3 Disposition.)
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded — **20 mutations, 20/20 re-red**, including the aggregate-remainder case (`budgetMs` 110 where the configured phase is 400).
- [x] Preservation sentinels and named gates pass with semantic outcomes. `sims-contracts` is 43 PASS / 1 FAIL at the recorded G28 baseline, not clean — stated, not claimed clean.
- [x] The journal's closed-domain guarantee is re-established (TC-388-04): the run-site census, an all-member `fromWireName` round-trip, a member-by-member freeze of the wire names, and the `unknown` fallback.
- [x] Wave 2's device leg produced an artifact carrying `coldWakeDeferralScan: 'clean'` (2026-08-19T16:14:23Z), understood as harness-integration evidence rather than Wave-1 closure.
- [x] `flutter analyze` has no issues; `git diff --check` is clean.
- [x] The Scope Contract And Guard is respected: 8 files changed, zero new files, no edit to `scripts/run_test_gates.sh` or `check_reliability_simulation_discovery.sh`, no deadline constant touched, no alerting change.

## Device/Relay Proof Profile

- **Profile:** paired-device (os-notification-device-lab).
- **Boundary being proven:** that the classifier and the scan are wired into a real campaign run, on a real FCM wake into a cold, killed Android app's background isolate. **Not** proven here: that Wave 1's new fields are emitted on device — the clean path emits no record.
- **Live availability check:** `adb devices -l` on 2026-08-19 → `21071FDF600CSC device usb:0-1.4.1.4 product:oriole model:Pixel_6` and `emulator-5554 device product:sdk_gphone16k_arm64`.
- **Pinned targets:** sender = physical Android `21071FDF600CSC`; **receiver = Android emulator `emulator-5554`** (the campaign's own assignment: `_terminateReceiver` targets `emulator` at `campaign:2600`, `_sendText` runs on `physical` at `:2024`). No iOS leg — iOS is deferred to GAP-N12, and the deadline is Android-only (`handler:628`).
- **Automation:** fully harness-driven. The campaign installs, kills (`am kill` with a bounded `stop-app` fallback, never `force-stop`), sends, observes and restores. No user taps.
- **Closure role:** **supporting evidence.** TC-388-12 proves harness integration and contributes one G21 sample; Wave 1 closes at host tier. TC-388-13 is currency verification for two G22 kinds.
- **`FLUTTER_DEVICE_ID`:** host selector only; both device IDs are pinned by the campaign's resource declaration.
- **Registration:** `payload_fast_path_cold_kill` is already registered. This plan adds **no new scenario and no new required check** — only an evidence key in `_notificationEvidenceRequirements`.
- **Discovery command:** `.claude/skills/sims/scripts/run_with_devices.sh major --list` → `notifications.android_payload_campaign` must be listed.
- **Closure command:** `.claude/skills/sims/scripts/run_with_devices.sh major --only notifications.android_payload_campaign` → the `payload_fast_path_cold_kill` artifact carries `coldWakeDeferralScan: 'clean'` beside its existing `coldAlertChannel`.
- **Deferred device work:** the positive control that would make this leg prove Wave 1; the 1:1-reaction leg; the media/announcement **message** legs; the profile-AOT re-measurement.

## Rollback

- **Reversible by:** `git revert` of the Wave 1 and Wave 2 commits. No schema, no wire format, no key material, no migration.
- **What a PRIOR shipped build does with post-change data:** nothing in production reads the liveness journal — the readers are two Dart host tests plus one Kotlin test that parses the *source*, not the records. Slot files are read independently and pruned by count (`_pruneOldest`), so six-key and ten-key records coexist in one directory. The `terminal-v1-` filename prefix is a slot-naming prefix, not a consumed version marker; it is left unchanged deliberately, since no reader keys off it.
- **NOT recoverable once landed:** nothing.
- **Staging:** accept the risk. The change is additive observability whose one-way surface (the journal's key allow-list and its closed-domain rule) is test-locked by TC-388-04 and TC-388-06.

## Handoff

- **First causal RED command:** `flutter test test/features/push/application/background_storage_deadline_test.dart --plain-name 'phase-local elapsed and the applied budget are exact on both throw branches'`
- **Preservation command:** `flutter test test/features/push/application/background_storage_deadline_test.dart --plain-name 'durable effect authority timeout stays storage-deferred with no fallback card'`
- **Manual registration:** one `coldWakeDeferralScan` entry in `tool/sims/device_criteria.dart` `_notificationEvidenceRequirements` (extend the existing `payload_fast_path_cold_kill` map at `:630-632`). **Nothing else** — no `classify_path` edits, no family-array entry, no new files.
- **Migration:** none.
- **Boundary closure:** Wave 1 closes at host tier. `.claude/skills/sims/scripts/run_with_devices.sh major --only notifications.android_payload_campaign` closes Wave 2's harness integration on `21071FDF600CSC` (sender) + `emulator-5554` (receiver).
- **Unresolved evidence:** whether the deferral reproduces on a warm install for the group-reaction kind, and whether it reproduces at all on the **Pixel** (Wave 2 measures the emulator). The JIT-vs-AOT confound stays unresolved by design.

## Reviewer Findings (wf_8f60597c-91a — 3 workers + lead source verification, 2026-08-19)

Verdict **plan-fixes-required**; core bet **CONFIRMED** (the first-wake property of `_runColdPayloadLeg` was independently re-verified end to end). All deltas below are applied in this document.

**Blockers closed (6):**
1. **TC-388-11 had an undeclared blast radius.** `notification_tap_device_criteria_test.dart:57-66` is a *passing* test whose cold artifact carries only `coldAlertChannel`; registering a second required key reds it. Now named in the row, in Expected RED, and in Implementation Step 3.
2. **TC-388-06 was not a sentinel.** `recordTerminal` has **10** call sites inside the journal test; widening its signature reds the whole file. Now stated, with all three edit sites named.
3. **`phaseName` as a free String reversed a documented privacy invariant.** `background_storage_liveness_journal.dart:50-52` says phase values are enum-constrained *"so an identifier cannot accidentally be persisted"*. Replaced with a closed domain plus a census assertion over all 11 `.run(` literals.
4. **TC-388-01/02 could not fail for their stated reason.** `phaseElapsed < elapsed` is satisfied by an implementation with no stamp at all (`onTimeout` fires exactly `bound` after attach), and `budget == phase` is the non-discriminating case. Replaced with exact equalities against `_FakeMonotonicClock` plus an aggregate-remainder case and an aggregate-exhausted case.
5. **TC-388-05 was theater.** All exits funnel through one shared record function and the fields ride on the exception, so the named mutation is inexpressible. Row removed; its genuine content folded into TC-388-04.
6. **TC-388-12 could not prove Wave 1.** On the clean path no record is emitted, so a stale APK yields a byte-identical pass and `buildMode` self-certifies nothing. Demoted to harness-integration evidence; closure tier split by wave; the positive-control option recorded under Deferred.

**Plan-fixes applied (selection):** the new parser file pair is **de-scoped** — `androidNotificationFlowRecords`/`_flowRecordsSince` already exist, are format-agnostic and are host-tested (this single de-scope also removed both fabricated `classify_path` registrations, both `grep -c … expect: 1` gates, the `scripts/run_test_gates.sh` contention with Plan 386, and the logcat-format risk). The success-path scan is scoped to `[coldCursor, postCardCursor)` because `preRestoreLog` spans the tap, relaunch and observer. The bare-return census is **six**, not five (`:775` was missing, `:1116` was off by one), and the three sets differ. `_phaseStartedAt` must be stamped before the `remaining` check because `run<T>` is not `async`. HEAD restamped to `59ce6b818` — Plan 386's source waves have landed. Step-1 stop-if split by wave, because 386's guard and 388's guard blocked each other. The Kotlin gate command was **not runnable**: `/claude-host-bin/host-run bash -lc` is refused ("shell commands must name a script file inside the repo"). TC-388-11's test name differed between the Test Contract and the Acceptance Gates, and its RED now runs whole-file. Line cites corrected: `:1693`→`:1692`, `:78-80`→`:78-81`, adapter sh `:227-234`→`:242-243`/`:248-249` and `:240-243`→`:255-261`, and the "both show lanes" phrasing.

**Confirmed sound and kept unchanged:** the census of 11 `_recordBackgroundStorageDeferred` sites and 5 `storage_deferred` outcomes (exact); the 2.170306 s / 2.180124 s arithmetic and the `bound = 2.000s` conclusion (exact to the microsecond); the single-mutable-`_phaseStartedAt` design (no `.run` sites overlap); the freeze-safety argument for the `:805` cursor and the `run()`-level classifier; and the whole `_runColdPayloadLeg` first-wake analysis.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
| 2026-08-19 | Wave 1 causal RED | `background_storage_deadline_test.dart`, `background_storage_liveness_journal_test.dart` | both files fail to COMPILE: `No named parameter 'phaseElapsed'` / `'phaseName'` | the missing fields are the contract, exactly as TC-388-01/03 predicted | proceed | Wave 1 production |
| 2026-08-19 | Wave 1 GREEN | `background_message_handler.dart`, `background_storage_liveness_journal.dart` | deadline 18/18, journal 11/11 | injected-clock exactness holds: ordinary `137/300/727`, aggregate-remainder `53/110/843` (budget ≠ the 400 ms configured phase), aggregate-exhausted `0/0/690` | Wave 1 closed at host tier | Wave 2 |
| 2026-08-19 | Wave 1 sentinels | — | Plan-383 lock GREEN (`phase` still `local_state`); Kotlin `CanonicalRuntimeH0ProbeSourceTest` 5 tests / 0 failures via `run_android_headless_recovery_native_374.sh` | the three parsed constants are untouched | — | — |
| 2026-08-19 | graph-affected | — | `affected` named 4 host test files; all GREEN (88 tests) | no import-level dependent broke | — | — |
| 2026-08-19 | Wave 2 causal RED | `notification_tap_device_criteria_test.dart` | the `:56-66` cold row reds on the new required evidence key | blast radius is ONE row, not two — the `:132-139` row fails earlier on the missing check either way | proceed | Wave 2 fix |
| 2026-08-19 | Wave 2 GREEN | `notification_android_payload_campaign.dart`, `device_criteria.dart`, `notification_tap_device_criteria_test.dart`, `notification_tap_campaign_adapter_contract_test.sh` | criteria 18/18; adapter contract PASS on the host bridge; campaign freeze GREEN and UNMODIFIED | — | Wave 2 host tier closed | device leg |
| 2026-08-19 | adversarial review (wf_9157b16b-7c6, 5 lenses + 16 refutation agents) | — | 2 findings CONFIRMED, 14 refuted | **(a)** the success-path scan filtered `post_show_unknown`, which is the CALLER-side argument — the wire value is `shown_state_unknown`, so the filter was dead code and a post-show timeout would have failed a correctly-carded run. **(b)** phase-START and phase-END stamping were indistinguishable because nothing advanced the clock between phases | both fixed; see Deviations | re-mutate |
| 2026-08-19 | mutation matrix | — | 20 mutations, **20/20 re-red** | includes all five the review constructed as wrong-but-passing | — | gates |
| 2026-08-19 | gates | — | `groups` lane 4569 tests + Go gates exit 0; `completeness-check` 1468/1468 with 0 unmatched; `flutter analyze` no issues; `git diff --check` clean | — | — | device leg |
| 2026-08-19 | gates | — | `sims-contracts --continue-on-failure` = **43 PASS / 1 FAIL, exit 1**; this plan's contract is **#17 PASS** | the single failure is #26 `run_claude_docker_update_contract_test.sh` = G28, plan 387's recorded and deliberately unfixed baseline | matches the documented baseline | device leg |
| 2026-08-19 | Wave 2 device (first attempt) | — | `run_with_devices.sh major --only notifications.android_payload_campaign` → BLOCKED(environment) | `MKNOON_RELAY_ADDRESSES` + FCM service account are not in the container env; the host bridge does not forward them | not a product blocker | re-run through the repo-resident wrapper |
| 2026-08-19 | **Wave 2 device CLOSED** | — | `/claude-host-bin/host-run bash docker-ws/run_payload_campaign_380.sh` → `PASS notifications.android_payload_campaign assertions=9` (build 1m7s) | `build/sims/proofs/notifications.android_payload_campaign/payload_fast_path_cold_kill.json` @ 2026-08-19T16:14:23Z carries `coldWakeDeferralScan: "clean"` beside `coldAlertChannel: "mknoon_messages"`, devices `["21071FDF600CSC","emulator-5554"]` | **TC-388-12 closed** — one machine-recorded warm-install first-wake sample that did NOT defer, on the EMULATOR | Wave 3 |
| 2026-08-19 | Wave 3 | — | not run | plan 386's TC-386-11 is 3/5 with `android_group_reaction_recipient` and `android_announcement_reaction_recipient` both BLOCKED | **this plan's dependency rule fires: Wave 3 waits.** See Wave 3 Disposition | hand off |

## Deviations From The Plan As Written

Each is a deliberate departure, with the reason. None widens scope; two were forced by the plan's own fixture.

1. **TC-388-01/02 assert against the resolver-advanced clock, not against `bound`.** The plan's cell says `phaseElapsed == bound`. That is unachievable with the fixture the plan mandates: `Future.timeout` fires on the REAL timer while `_FakeMonotonicClock` only moves when a stubbed resolver moves it, so the fake clock can never read `bound` at the instant `onTimeout` runs. The substituted form is stronger — total elapsed, phase-local elapsed and the applied bound are three DIFFERENT numbers in every case (`727 / 137 / 300`), so an implementation that emits one of them three times cannot pass, whereas `phaseElapsed == bound` would have made two of the three identical.
2. **A third row was added to the deadline test.** TC-388-04's headline behaviour — that `preview_resolution` and `durable_effect_authority` still collapse to `local_state` yet carry distinct raw identifiers — is a HANDLER property. Asserting it only at the journal layer with hand-passed enums would not prove the handler forwards the right identifier. `'collapsed local_state phases carry distinct raw phase identifiers'` drives both deferrals through `firebaseMessagingBackgroundHandler`; the journal test keeps the closed-domain census, the `unknown` fallback and the persisted discrimination.
3. **The success-path window uses an implicit read-to-EOF, not an explicit `postCardCursor`.** `_logcatSince(cursor)` reads to the file's length AT CALL TIME, so calling it immediately after the frozen triple IS `[coldCursor, postCardCursor)`. A second cursor variable would have added nothing; the ordering is enforced instead by the contract shell's `scan_at < tap_at` and `scan_at < prerestore_at` checks inside the cold-leg slice.
4. **The scan excludes two record shapes the plan did not distinguish.** `PUSH_BACKGROUND_STORAGE_DEFERRED` carries three outcomes. `shown_state_unknown` is written by the post-show validators and the recent-shown mark, AFTER the card is published, so it can never be why an alert is missing. And `pending_overlay` is the single `storage_deferred` site that records and then FALLS THROUGH — the overlay is enrichment, the card still goes out. Failing a carded run on either would be a false red, so the scan keeps only `storage_deferred` / `custody_write_pending` and drops `pending_overlay` by `phase`.
5. **The failure-path classifier is bounded by a latch, and is narrow.** It catches `_Failure` only, so a `_Blocked` keeps exit 78 instead of being re-typed as a product defect; it stands down once `_coldWakeWindowScannedClean` is set, so a failure downstream of the graded window (the tap, the relaunch, the network restore, `_restartAndDrain`) is never re-headlined as a graded-wake deferral; and it does not re-wrap the leg's own diagnosis.
6. **`TC-388-06`'s named test does not contain the 200 ms bound.** `'release records use complete atomic slots, stay bounded, and redact'` has no timing assertion. The caller bound is actually held by the two other journal tests (the stalled-writer and stalled-prune rows), both of which were widened and both of which pass. The 200 ms constant itself is pinned by the Kotlin source-parse (TC-388-08).
7. **Two extra contract assertions were added beyond TC-388-10.** The classifier must not re-type environment blockers, and the diagnosis must carry total elapsed — on the aggregate-exhausted branch phase-local elapsed and the budget are both zero, so without it the message reads `0ms of 0ms`.

## Wave 3 Disposition (2026-08-19) — NOT RUN, and why

**The rule fired.** Dependencies says *"if 386's device legs are still open, Wave 3 waits."* They are
open: plan 386 is EXECUTED with TC-386-11 at **3/5** (`386-...-tdd-plan.md:526-534`), and BOTH
remaining scenarios are BLOCKED. Plan 386's own handoff says the same thing from the other side:
*"Coordinate before starting. Plan 388 Wave 3 already claims re-running these same two scenarios and
states it waits for 386's device legs."*

**The blocker is G21 itself — this plan's subject.** 386's `android_group_reaction_recipient` is
blocked because the first FCM wake after the kill opens SQLCipher cold and exceeds the 2 s
`display_eligibility` budget, so the isolate returns at `PUSH_BACKGROUND_STORAGE_DEFERRED` upstream of
the presenter. Measured on device 2026-08-19: push received 12:15:24.952, deferral 12:15:27.340,
`elapsedBucket=2s_to_8s`, `kind=group_reaction`. `android_announcement_reaction_recipient` — the
scenario TC-388-13 names — never ran at all, because the campaign fails fast behind it.

**This is a THIRD real-device G21 sample, and the first on a post-`f1b568bca` build.** Plan 383's N=2
were Pixel samples from 2026-08-18; this one is the emulator on 2026-08-19. G21's severity is no
longer N=2.

**Closing it is explicitly outside this plan.** 386's handoff prices the fix as re-scoping those two
scenarios' evidence contract, and rules out the warm-up push that worked for plan 383 (the recipient
authors the target, so its unread is pinned at 0, and the only thing that wakes a killed recipient is
an incoming group MESSAGE — which creates exactly the unread and card those rows assert the absence
of). This plan's Hard `Do not` is *"Do not add a fallback card, a retry, or any alerting change for
`storage_deferred`. This plan measures."* Re-scoping that contract is the owner's call, not a
side-effect of an observability wave.

**Plan-fix for whoever picks Wave 3 up: TC-388-13's gate command covers only half of its own row.**
The Plan-330 media-target reactions are NOT in `groups.reaction_notification_campaign`. They live in
`_runAndroidGroupNotificationProjectionLifecycle()`
(`integration_test/scripts/capture_group_reaction_notification_device.dart:2327`, the three-kind loop
at `:2526-2537`, each preceded by `_terminateAndroidRecipient()`), which is driven by
`run_group_notification_projection_android.dart` — capability
**`groups.notification_projection_durability`**. So Wave 3 needs TWO gate commands, and the media half
is independently runnable because it does not sit behind the reaction campaign's fail-fast. It was
still not run here: no `docker-ws/` wrapper exists for that capability, and creating one is a new file
this plan's Scope Contract forbids.

