# 390 - Android integration harnesses cannot reach the Go bridge without the canonical-runtime lease

Status: EXECUTED and CLOSED 2026-08-19 — host census 7/7, device leg green on `emulator-5554` with its mutation re-red
Type: Bug
Spec: free-text intent (no formal spec) — gap **G15** of `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md` §4.10
Classification: implementation-ready
Closure tier: **host for the census and the repairs; device for one representative proof**

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-19 | Evidence Collector | `MainActivity.kt`, `AppDelegate.swift`, the `GoBridgeClient(` census, `dtr13_…_contract_test.sh` | Root cause live; only one harness "fixed"; two `lib/` entrypoints hash-pinned | verify→refute |
| 2026-08-19 | Planner (wf_8b0d7fc0-053, 8 agents) | + `_support/canonical_runtime_device_test_lease.dart`, `run_reliability_simulations.sh`, `critical_features.json`, `benchmark_harness.dart` | The map's fix is the wrong seam, its date is wrong, four offenders cannot self-lease | write plan |
| 2026-08-19 | Reviewer (wf_7e8945e4-3fa, 3 workers + lead source verification) | + `group_multi_device_real_harness.dart:5934-5942`/`:1958`, `CanonicalRuntimeLease.kt:55-65`/`:185-188`, `cold_start_sendable_no_user_action_test.dart`, `CanonicalRuntimeH0ProbeReceiver.kt` | **Root cause CONFIRMED; the model harness is itself double-leasing and the Test Contract did not survive counterexample construction.** 5 blockers | apply deltas (this document) |

## Problem And Evidence

- **Behavior to improve:** on Android the native `GoBridge` is constructed only inside an `attachRuntimeOwner` lambda, so an integration harness that constructs `GoBridgeClient()` without first acquiring the canonical-runtime lease gets no `com.mknoon/go_bridge` channel. Every bridge call returns `ok:false`, and `generateNewIdentity` collapses it into `GenerateIdentityResult.coreLibError` — setup dies about a second in, with no message naming the cause.
- **Impact:** twelve-ish harnesses that a real command executes are latently broken, and the one harness held up as the model is broken a *second* way (below). Nothing has failed yet **because nothing has run them** — there is no CI (`.github` absent, `.git/hooks` empty, no Makefile, no cron), so every gate is a human-issued command and five green surfaces report "pass" over these files without executing them.

### Confirmed root cause

Verified end to end in current source at HEAD `9bc1d6bcb`:

- `com.mknoon/go_bridge` is registered in exactly one place — the `GoBridge` Kotlin constructor's field initializers (`GoBridge.kt:31-38`), handlers installed in its `init` block (`:50-53`).
- **There are four `GoBridge(` construction sites in `android/`, not two.** `MainActivity.kt:92` and `HeadlessCanonicalRecoveryWorker.kt:625` in the main source set, **plus `android/app/src/debug/kotlin/com/mknoon/app/CanonicalRuntimeH0ProbeReceiver.kt:361` and `:1291` in the debug source set that `flutter test -d` compiles.** All four sit behind an explicit attach/trigger — none constructs eagerly at launch — so none rescues a harness, but the count claim must be right or a reader will assume the debug set is a back door.
- The trigger is the Dart `attachRuntime` call over `mknoon/canonical_runtime_lease` (`CanonicalRuntimeLease.kt:126`, handled `:141` → `:195-209`, lambda at `:206`). Broker `acquire` (`:46-71`) re-returns the live token **only for an identical `(ownerId, binding, role)` triple** (`:55-62`); otherwise it returns null when state is not `RELEASED` (`:63-65`) and Kotlin answers `result.error("lease_unavailable", …)` (`:185-188`). `MethodChannelCanonicalRuntimeLeaseGateway.acquire` (`lib/core/notifications/canonical_runtime_lease.dart:100-106`) is a bare `invokeMethod` with **no `PlatformException` catch**, so a rejected acquire throws out of `setUpAll`.
- **Blast radius is every bridge call.** Both `invokeMethod` sites (`go_bridge_client.dart:924`, `:929`) sit inside the same `try` at `:921` whose `on MissingPluginException` at `:954` returns `ok:false` for every cmd. There is no third `invokeMethod`.
- **iOS is unaffected**, eagerly constructing at `AppDelegate.swift:375` — but wrapped in `#if canImport(GoMknoon)` (`:374`/`:377`), so eager-but-conditional on the xcframework.

**Failure shape.** Construction does no platform work (`GoBridgeClient` declares no constructor; both channels are `static const`, `go_bridge_client.dart:27-28`), and `initialize()` (`:216-242`) invokes no `MethodChannel` — it only subscribes to the `EventChannel` (`:229-233`), whose `MissingPluginException` lands asynchronously. So nothing throws at the construction line; it fails later as an unexplained `coreLibError`.

### The second defect, found by review — fix this first

**`integration_test/group_multi_device_real_harness.dart` acquires the lease twice, with conflicting bindings, and is broken on Android at HEAD.**

- `main()` at `:5938-5942` constructs `CanonicalRuntimeDeviceTestLease(binding: 'group-multi-device-real-$configuredRole')` and registers `setUpAll(runtimeLease.acquire)` / `tearDownAll(runtimeLease.release)`.
- `setupGroupMultiDeviceStack` at `:1958` then calls `ensureCanonicalRuntimeAttachedForTest()`, which uses the hardcoded binding `'v1:0000…0000'` (`:561-562`).
- Same `ownerId`, same role, **different binding** → the identical-triple branch does not match, state is `ACTIVE` not `RELEASED`, the broker returns null, Kotlin answers `lease_unavailable`, and the uncaught `PlatformException` kills setup **before the first bridge call**.
- Three runners target that `main()` directly — `run_group_multi_device_real.dart:13`, `run_b1b_sibling_device_convergence.dart:30`, `run_invite_reliability_multi_device.dart:30`, all listed at `run_reliability_simulations.sh:526-529`. The six files that merely *import* the harness are unaffected because they never run its `main()`, which is why recent device runs stayed green and hid this.
- Introduced by `90bc7d601` (2026-08-19), one day old: `git log -S"setUpAll(runtimeLease.acquire)"` on that file gives `d44b63448` (08-06); `git log -S"ensureCanonicalRuntimeAttachedForTest"` gives `90bc7d601`.

**Consequence for this plan:** the invariant is **"exactly one acquire, with one binding, on each harness's actual runtime path"** — not "every harness has a lease". Copying the model's shape onto twelve more harnesses would propagate a collision.

### The established seam, in full

```dart
final runtimeLease = CanonicalRuntimeDeviceTestLease(
  binding: 'transport-e2e-device-test',      // per-harness, kebab, '-device-test' suffix
);
setUpAll(runtimeLease.acquire);
tearDownAll(runtimeLease.release);
```

placed immediately after `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` and before the host `sqfliteFfiInit()` branch — identical in `transport_e2e_test.dart:886-890`, `wifi_relay_fallback_smoke_test.dart:460-464`, `background_reconnect_test.dart:63-67`.

**The lease is not side-effect-free.** `acquire()` (`_support/canonical_runtime_device_test_lease.dart:24-52`) is Android-guarded, **throws `StateError` if already active** (not idempotent), deletes and recreates a real SQLCipher database (`canonical_runtime_device_test_lease.db`, its own password, a probe table), takes the single process-wide writable token and attaches the Go runtime. `release()` (`:54-73`) quiesces the Go runtime with a deadline that can red an otherwise-passing run. **It logs nothing** — zero `print(` in the file.

### The census, re-derived

`GRAPH_OK=1 grep -rn 'GoBridgeClient(' integration_test/ lib/ test/ tool/`, excluding `.wt-386`:

- **20 files / 24 matches under `integration_test/`**, one being `RecordingGoBridgeClient()` (`group_multi_device_real_harness.dart:1959`, subclass at `:512`).
- Minus the group harness → **19 candidates / 23 sites**; minus the three `_support`-leased → **16 unleased**.
- `lib/`: 4 files. The two production bootstrap files hold the lease at their caller. `lib/smoke_test_main.dart` and `lib/smoke_test_restore.dart` reference the lease zero times — **resolved as out of scope**, see Deferred.
- `test/`: 5 host files, no real bridge. `tool/`: 0.

**The executed/dormant split is not asserted here as a number.** Two defensible criteria give materially different answers (14/2 and 9/7), so a fixed split would be a false precision. Step 1 requires the executor to derive it and **write the list into the plan** before repairing anything; TC-390-04's allow-list is where that list lands and is reviewed.

### Derived at execution (2026-08-19) — the list Step 1 asked for

The census reproduced exactly: 20 files / 24 matches under `integration_test/`, one being `RecordingGoBridgeClient()`; 19 candidates / 23 sites; 16 unleased constructing files.

**Attribution is per (constructing file, entrypoint) pair, not per file.** A file with no `main()` cannot repair itself, and a file that constructs the bridge next to its own lease is already covered. That yields **15 unleased entrypoints covering all 16 unleased files** — two fewer offenders than a per-file count, and two entrypoints (`cold_start_sendable_no_user_action_test.dart`, `sims_dispatcher.dart`) the plan's per-file view never named.

**Executed criterion, applied uniformly.** A file is executed when one of: (a) a `run_test_gates.sh` array or gate that is actually dispatched; (b) an `active` capability in `tool/sims/critical_features.json`; (c) selection by `run_reliability_simulations.sh:164-173`'s filter over `check_reliability_simulation_discovery.sh --records-tsv` — category in {1to1, group, intro, move-feature} AND type in {runner, test} — or being the harness such a selected runner launches; (d) a repo script that `flutter test`s / `dart run`s it directly. Confirmed NOT executed by membership alone: `NIGHTLY_ONLY_TESTS`, `OPTIONAL_MANUAL_TESTS`, `OUT_OF_GATE_TESTS`, each referenced only inside `classify_path` (`run_test_gates.sh:1441`, `:1446`, `:1451`).

| Entrypoint | Constructing files it reaches | Executed? | Evidence |
|---|---|---|---|
| `android_background_crypto_preflight_app.dart` | itself | **yes** (c) | `run_1to1_reaction_notification_device.dart` is 1to1/**runner** → `Process.start('dart', capture driver)` `:158` → `flutter build apk --debug --target` `:579-584`, installed and launched |
| `benchmark_harness.dart` | `benchmark_helpers`, `benchmark_bridge_crossing_harness`, `benchmark_encryption_harness` | **yes** (a) | `run_test_gates.sh benchmark-sim` `:1926-1932`, once per each of 17 BENCHMARK keys |
| `cold_start_sendable_no_user_action_test.dart` | `benchmark_helpers` | **yes** (c) | records `1to1/test`; the second `benchmark_helpers` entrypoint (`:10` imports, `:23` calls `createBenchmarkNode()`) |
| `conversation_bridge_test.dart` | itself | **yes** (c) | records `1to1/test` |
| `group_invite_reliability_proof_test.dart` | itself | **yes** (c) | records `group/test` |
| `group_real_crypto_onboarding_test.dart` | itself | **yes** (c) | records `group/test` |
| `group_recovery_cli_e2e_test.dart` | itself | **yes** (c)+(a) | records `group/test`; also `run_test_gates.sh group-real-network-nightly` `:1180`, conditional on `CLI_PEER_FIXTURE` |
| `group_removal_rotation_keyless_converge_proof_test.dart` | itself | **yes** (c) | records `group/test` |
| `group_removal_rotation_keyless_proof_test.dart` | itself | **yes** (c) | records `group/test` |
| `routing_smoke_harness.dart` | itself | **yes** (c) | `run_routing_smoke_e2e.dart` is 1to1/runner AND group/runner → `Process.start('flutter', …)` `:109` with `harness: _aliceHarness`/`_bobHarness` |
| `sims_dispatcher.dart` | `support/android_critical_performance_campaign.dart` | **yes** (b) | capability `performance.device.critical` (`active`, `required`), `buildProfile: android.e2e.standard` → `build_orchestrator.dart:1175` targets this file |
| `transport_census_harness.dart` | itself | **yes** (d) | `scripts/run_transport_census.sh:130` `flutter test "$HARNESS"` |
| `soak_e2e_test.dart` | itself | **yes** (c) | records `1to1/test` |
| `setup_device.dart` | itself | **no** | records `support/support`; no gate, script or capability runs it |
| `smoke_test.dart` | itself | **no** | records `ignored/ignored`; only in `NIGHTLY_ONLY_TESTS` |

**13 executed, 2 dormant.** Both dormant files were repaired anyway rather than allow-listed — the change is four lines each and identical to the other thirteen, so the allow-list ships **empty** and there are no exemptions to argue about. `lib/smoke_test_main.dart` / `lib/smoke_test_restore.dart` stay out of scope as the plan already resolved.

### What the plan did not have — self-guarding, and the seven harnesses it would have wrongly charged

`setupGroupMultiDeviceStack` calls `ensureCanonicalRuntimeAttachedForTest()` immediately before constructing its bridge, so `group_multi_device_real_harness.dart` is **self-guarded**: it takes the lease in the same file that builds the bridge. Seven entrypoints reach the bridge only through it — `benchmark_group_publish_harness` (via `benchmark_harness`), `foreground_group_push_simulator_harness`, `group_multi_party_device_real_harness`, `group_multi_party_device_real_android_harness`, `group_smoke_harness`, `notification_open_during_other_chat_harness`, `notification_sound_smoke_harness`. A census that demanded a lease in every reaching entrypoint would have charged all seven and produced exactly the double acquire the plan's hard rule forbids. The census therefore accepts **self-guarded OR every reaching entrypoint**, and never accepts mere transitive reachability of a seam (which branch runs is `--dart-define`-dependent and unknowable from source).

### Four offenders cannot fix themselves — and one has two entrypoints

`benchmark_helpers.dart:5`, `benchmark_bridge_crossing_harness.dart:7`, `benchmark_encryption_harness.dart:5` and `support/android_critical_performance_campaign.dart` have no `main()` and cannot host `setUpAll`. The repair belongs in their entrypoints — but **`benchmark_helpers.dart` has two**: `benchmark_harness.dart` (dispatching via `--dart-define=BENCHMARK=…`, `run_test_gates.sh:1891`, `:1926-1932`) **and** `integration_test/cold_start_sendable_no_user_action_test.dart`, an independent `main()` that imports it at `:10` and calls `createBenchmarkNode()` at `:23`. Leasing only `benchmark_harness.dart` leaves that path unleased.

**And leasing `benchmark_harness.dart` naively regresses a working gate:** `BENCHMARK=GROUP_PUBLISH` reaches `setupGroupMultiDeviceStack`, which performs its own acquire with the fixed binding — the same collision as the model harness. Wave 0 must land first.

### Existing coverage

**None.** No test, no `scripts/test/*.sh` contract and no `tool/` check fails when a harness constructs `GoBridgeClient()` without a lease.

### Refuted findings (do NOT re-introduce)

- **"Already fixed after `f1b568bca`."** Zero commits on `GoBridge.kt` and `CanonicalRuntimeLease.kt`; one on `MainActivity.kt` (`3c7e704e7`, +116/−0 app-visibility, touching no GoBridge line).
- **"Something else registers the channel."** `com.mknoon/go_bridge` appears in exactly one non-comment place in `android/`. No harness installs a mock handler for it.
- **"Permission, flavour or emulator artifact."** `android/app/build.gradle.kts` declares no `productFlavors`/`flavorDimensions`.
- **"Only `generateNewIdentity` is affected."** Refuted — the shared `try`/`on MissingPluginException`.
- **"A census under `test/integration/` cannot resolve the repo root."** Refuted — both runners `cd` to the repo root (`run_test_gates.sh:5-6`, `run_host_test_gates.sh:5-6`), relative-root censuses are established green prior art (`test/features/conversation/application/delivered_status_minting_sites_test.dart:31`, `test/integration/group_reaction_notification_device_criteria_test.dart:413`), and host-all auto-discovers the file (`run_host_test_gates.sh:482`, batch predicate `:970`).
- **"Call-order can be checked by source position."** Refuted by measurement: it reds 2 of the 3 already-correct files, because execution order is lease-first via `setUpAll` while source order is bridge-first (`transport_e2e_test.dart` constructs `:434`, leases `:889`).
- **"Within `integration_test/` there are no legitimate exemptions."** Refuted — the four no-`main()` libraries.
- **The map's G15 row is wrong three ways:** `f1b568bca` is dated **4 Aug 2026** (not 08-17); the row names `wifi_relay_fallback_smoke_test` and `background_reconnect_test` as broken when the same commit leased them; and it prescribes `ensureCanonicalRuntimeAttachedForTest()` when the reusable seam is `_support/`.

### Affected production / test / gate files

- `integration_test/group_multi_device_real_harness.dart` (Wave 0, the double lease).
- The executed unleased harnesses under `integration_test/` (list derived in Step 1), plus `benchmark_harness.dart` and `cold_start_sendable_no_user_action_test.dart` for the library cases.
- One new host census test plus its allow-list.
- **No `lib/` change. No new file under `integration_test/scripts/`. No new scenario id.**

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `1a4b6c5af1c6cd13`, `stale:integration_test/scripts/capture_group_reaction_notification_device.dart`. Not rebuilt — 389 is mid-execution against that file.
- Query / profile: `--profile tdd --budget 700` for planning, `--profile review --budget 800` for the audit; both `confidence=anchored` on symbol anchors only.
- Anchors: `CanonicalRuntimeDeviceTestLease` → `_support/canonical_runtime_device_test_lease.dart:13`; `GoBridgeClient` → `lib/core/bridge/go_bridge_client.dart:26`.
- Graph gaps that required raw source search: the `integration_test/` census, all `android/**/*.kt` (including the debug source set), `ios/**/*.swift`, `scripts/**/*.sh`, `tool/sims/critical_features.json`.
- Reuse rule: anchors are search starting points; every count and line was re-derived from current source.

## Scope Contract And Guard

**In scope:**
- **Wave 0:** resolve the double acquire in `group_multi_device_real_harness.dart` so exactly one binding owns the runtime on both its direct-`main()` and imported paths.
- **Wave 1:** the host census plus its allow-list.
- **Wave 2:** lease each executed unleased harness via `CanonicalRuntimeDeviceTestLease` with the full `setUpAll`/`tearDownAll` pair and a per-harness binding; for the library cases, lease **every** entrypoint that reaches them.
- **Wave 3:** one device run proving a repaired harness reaches the bridge.

**Must preserve:**
- The three `_support`-leased transport tests stay singly-leased → TC-390-05.
- `BENCHMARK=GROUP_PUBLISH` keeps working → TC-390-05 (it is the same double-acquire invariant).
- `lib/` stays out of the census → TC-390-06.
- Discovery and `completeness-check` stay green → TC-390-07.

**Hard `Do not`:**
- **Do not add a lease to any harness that already reaches an acquire transitively.** That is the Wave-0 defect; re-creating it is the main hazard of this plan.
- **Do not use `ensureCanonicalRuntimeAttachedForTest()` as the seam for new work.** Use `_support/`. (Wave 0 may still choose it as the *single* acquirer inside the group harness — that is a different decision.)
- **Do not add a file under `integration_test/scripts/`** — `check_reliability_simulation_discovery.sh:719` finds every file there and fails closed at `:1233-1234`.
- **Do not edit `lib/`**, including `lib/smoke_test_main.dart` / `lib/smoke_test_restore.dart` (hash-pinned at `dtr13_profile_entrypoint_preservation_contract_test.sh:202-241`).
- **Do not write the census as a call-order check by source position**, and **do not match on loose tokens** like `Lease` or `acquire` — `android_background_crypto_preflight_app.dart` already carries 17 `Lease` hits from `DurableNotificationToneLease` plus an unrelated `acquire`.
- **Do not filter the census to `_test.dart`** — 9 of the 20 offender files, including all four no-`main()` libraries, would never be scanned.
- **Do not touch anything Plan 389 owns.**

**Deferred / accepted difference:**
- **`lib/smoke_test_main.dart` / `lib/smoke_test_restore.dart` — RESOLVED as out of scope, not an open question.** Both are manual `flutter run -t` roots with **no automated executor anywhere in the repo**, and an `integration_test/`-scoped census can never cover them. Editing either also forces a DTR13 re-pin. If someone runs them on Android by hand they will hit the same defect; that is accepted and recorded.
- **The 11 repaired harnesses other than the device-proven one** → covered by the census plus the single representative proof, not individually device-run.
- **`./scripts/run_test_gates.sh reliability-sim all` aborts early** — `run_1to1_reaction_notification_device.dart` invoked with no `--scenario` defaults to `all`, hits `selected.length != 1` and `exit(64)`; with `continue_on_failure=0` the loop exits at `:921`. A separate pre-existing defect, recorded not fixed.
- **Accepted difference — the census is a regression tripwire, not a proof.** Seven known escapes: a lease call in a dead helper; a bridge constructed in `main()`'s body before `setUpAll` runs; a lease literal in a string constant or a comment; a lease inside `group(skip: true)`; a subclass construction (`RecordingGoBridgeClient` is exactly that and is invisible); and — the dominant shape — **indirect construction through an imported library**, which no construction-site census can see. TC-390-08 carries the mechanism.

**Dependencies:**
- Plan 389 is executing (host green, device pending). File sets are **confirmed disjoint**, but contention extends past the Pixel to the emulator, the state guard, and the host-all glob. Serialize Wave 3.
- Plan 388 landed in `dbb46336e`.

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| **TC-390-00** | No harness acquires the canonical-runtime lease twice with conflicting bindings on one runtime path | `test/integration/android_bridge_runtime_lease_census_test.dart::'no harness acquires the runtime lease twice'` | integration host / real repo tree | causal RED — `group_multi_device_real_harness.dart` holds both seams today (`:5938-5942` binding `group-multi-device-real-…`, `:1958` → `:561-562` binding `v1:0000…`), and the broker rejects a non-identical triple (`CanonicalRuntimeLease.kt:55-65`, `:185-188`) → exactly one acquirer remains on both the direct-`main()` and imported paths | restore the second acquire → TC-390-00 red | `flutter test test/integration/android_bridge_runtime_lease_census_test.dart`; host-all-only → direct command; auto-classified at `run_test_gates.sh:1526-1529` |
| **TC-390-01** | A new unleased `GoBridgeClient()` site reds the census, and the census provably scanned a non-empty file set | `…::'a new unleased bridge construction is reported and the scan is non-empty'` | integration host / real repo tree + a temp fixture file | causal RED (no census exists — compile failure) → the census reports every unleased offender, **and asserts `scannedFileCount` is at least the current `integration_test/**/*.dart` count**; adding a synthetic bare `GoBridgeClient();` names that file | point the census root at a non-existent directory → the scan-count assertion reds (without it the census passes vacuously at zero offenders) | same command; AUTO (glob) |
| **TC-390-02** | The matcher is type-exact and covers non-`_test.dart` files | `…::'the lease matcher is type-exact and scans every dart file'` | integration host / fixtures: a file with `DurableNotificationToneLease` + an unrelated `acquire`; a `library;` file with no `main()` | causal RED against a token matcher on `Lease`/`acquire` — that form clears `android_background_crypto_preflight_app.dart`, which carries 17 unrelated `Lease` hits → only a reference to `CanonicalRuntimeDeviceTestLease` (or the Wave-0 chosen single seam) satisfies it, and the four no-`main()` libraries are scanned | filter the walk to `*_test.dart` → TC-390-02 red on the library fixture | same command; AUTO (glob) |
| **TC-390-03** | A library with no `main()` is satisfied only when **every** entrypoint that reaches it leases | `…::'a no-main library requires all of its entrypoints to lease'` | integration host / fixtures: one library, two importing entrypoints | causal RED (a construction-site census charges the library, which cannot act; and single-entrypoint attribution clears `benchmark_helpers.dart` while `cold_start_sendable_no_user_action_test.dart:10`/`:23` stays unleased) → the library passes only when both entrypoints lease | lease one entrypoint and not the other → TC-390-03 red naming the unleased one | same command; AUTO (glob) |
| **TC-390-04** | Every executed offender is repaired, and the allow-list may not contain an executed file | `…::'the allow-list contains no executed harness'` | integration host / real tree + the executed list derived in Step 1 | causal RED (16 unleased offenders at HEAD) → zero executed offenders remain; **the allow-list is checked against the executed list and reds if it names one**, so seeding it with every offender cannot pass | move any executed file into the allow-list → TC-390-04 red | same command; AUTO (glob) |
| **TC-390-05** | The already-correct harnesses stay singly-leased, and `BENCHMARK=GROUP_PUBLISH` still reaches its stack | `…::'the leased transport harnesses hold exactly one acquire'` + `./scripts/run_test_gates.sh performance` discovery for the benchmark path | integration host / real tree, plus a discovery-only check of the benchmark dispatch | GREEN sentinel for the three transport tests (they pass today) → still pass; the benchmark entrypoint gains a lease **without** a second acquire downstream | add a second `runtimeLease.acquire()` to a transport test, or lease `benchmark_harness.dart` while leaving `setupGroupMultiDeviceStack`'s acquire in place → TC-390-05 red (this is the TC-390-00 invariant applied to the repairs) | same command; plus `./scripts/run_test_gates.sh performance --list`-equivalent discovery, never a full perf run |
| **TC-390-06** | `lib/` is out of the census's scope | `…::'production bridge constructions are not censused'` | integration host / real tree | GREEN sentinel (nothing censuses `lib/` today) → still passes; `production_canonical_inbox_projection_composition.dart:186` is not reported | widen the census root to include `lib/` → TC-390-06 red | same command; AUTO (glob) |
| **TC-390-07** | Discovery and completeness stay green; nothing was added under `integration_test/scripts/` | `./scripts/check_reliability_simulation_discovery.sh` + `./scripts/run_test_gates.sh completeness-check` | host shell / real tree | GREEN sentinel (both pass today) → still pass | add any file under `integration_test/scripts/` → discovery reds at `:1233-1234` | both commands, exit 0 |
| **TC-390-08** | On a real device, a repaired harness reaches the Go bridge and completes | device run of **one cleanly-launchable repaired harness** on `emulator-5554` | device proof / Android emulator `emulator-5554` | manual/device-only proof (today it dies ~1s in at `GenerateIdentityResult.coreLibError`) → the run passes, having made at least one successful bridge call. **The oracle is the run's own pass/fail, not a log line** — `CanonicalRuntimeDeviceTestLease` prints nothing, and `[STACK-DIAG]` exists only in `group_multi_device_real_harness.dart:574` inside the banned seam | revert that harness's lease and re-run → the ~1s `coreLibError` death returns | `flutter test -d emulator-5554 integration_test/<chosen>.dart`; the census cannot prove the mechanism — this row does |

### Test Notes

- **Wave 0 is a decision, not a mechanical edit.** Either drop the `main()` `setUpAll`/`tearDownAll` pair at `group_multi_device_real_harness.dart:5939-5942` so `ensureCanonicalRuntimeAttachedForTest()` is the single acquirer on both paths, or make that function tolerate an already-`ACTIVE` lease held by the same owner (check status first, skip to `attachRuntime`). Record which was chosen and why. The second option also fixes the `BENCHMARK=GROUP_PUBLISH` regression risk for free.
- **Pick the device harness from the cleanly-launchable set.** Six of the sixteen cannot be launched by a bare `flutter test -d` at all — the four no-`main()` libraries, the `runApp` app `android_background_crypto_preflight_app.dart`, and `transport_census_harness.dart`; two more pass vacuously without a CLI peer fixture; three need roles, a relay address or an unlocked keyguard. Five are clean. Name the chosen one and why.
- **Run the device leg on `emulator-5554`, not the Pixel.** `flutter test -d` on the physical phone destroys a stamped release install and the state guard fails closed (`failKeystoreAlreadyLost` is live at HEAD). The Go AAR ships x86_64 and no `abiFilters` narrowing applies to `flutter test -d`, so the emulator is a correct target for this proof.
- **The lease's binding must be unique per harness** — kebab-case, `-device-test` suffix, matching the three existing users. Two harnesses in one process with different bindings is the Wave-0 defect in miniature.
- **`tearDownAll(runtimeLease.release)` is not optional.** `release()` quiesces the Go runtime on a deadline; omitting it leaves the runtime attached and the probe database on disk, and a too-slow quiesce can red an otherwise-passing run.
- **The census's dominant blind spot is import indirection.** Most offenders construct the bridge inside an imported library rather than in the entrypoint, so a construction-site census attributes the defect to a file that cannot fix it. TC-390-03 is the partial answer; the residual is recorded as an accepted difference.

## Implementation Steps

1. Snapshot `git status --short`. **Stop-if** anything Plan 389 owns is dirty. **Derive the executed/unleased list yourself** — re-run the census, then for each candidate establish whether a real command runs it (a `run_test_gates.sh` array that is actually dispatched, a `critical_features.json` capability, or a script that `flutter test`s / `dart run`s it — note `check_reliability_simulation_discovery.sh` output IS consumed and executed by `run_reliability_simulations.sh:162`, while `NIGHTLY_ONLY_TESTS`/`OPTIONAL_MANUAL_TESTS`/`OUT_OF_GATE_TESTS` are read once inside `classify_path` and never run). **Write that list into this plan** before repairing anything.
2. **Wave 0** — resolve the double acquire per Test Notes. TC-390-00 is its causal RED.
3. **Wave 1** — land the census. It may ship with an allow-list, but TC-390-04 rejects any allow-list entry that is on the executed list, so it cannot be landed "green and empty".
4. **Wave 2** — lease the executed harnesses in small batches, full `setUpAll`/`tearDownAll` pair, unique binding, removing each from the allow-list as it lands. For library cases lease **every** reaching entrypoint.
   - Stop-if: a harness already reaches an acquire transitively → do not add a second one; record it.
5. **Wave 3** — one device leg on `emulator-5554`, after 389's device runs.

## Risks And Blind Spots

- **Propagating the Wave-0 collision** is the main hazard → TC-390-00 and TC-390-05, plus the Step-4 stop-if.
- **A vacuous census** that scans nothing → TC-390-01's scan-count assertion.
- **A loose matcher** that clears a file on unrelated `Lease` tokens → TC-390-02.
- **Single-entrypoint attribution** that leaves a second path unleased → TC-390-03.
- **A tautological allow-list** → TC-390-04's executed-list cross-check.
- **Lifecycle / derived-state durability:** N/A — the lease is per-process and re-acquired each run; nothing derived persists.
- **Sibling-surface consistency:** two lease seams exist. Wave 0 settles which one owns the group harness; the rest standardise on `_support/`, and TC-390-05 keeps the transport three green.
- **Destructive-action side effects:** **not N/A.** `acquire()` deletes and recreates `canonical_runtime_device_test_lease.db` on the device, and `release()` quiesces the Go runtime on a deadline. TC-390-05 and TC-390-08 are what catch a mis-paired lease; the deleted database is a dedicated probe file, not user data.
- **Invariant re-verification under new transitions:** the added `setUpAll`/`tearDownAll` is a new transition per harness. TC-390-00 asserts the post-transition invariant (one acquire per path) rather than only the headline fact that a lease exists.
- **Construction / call-site census:** re-derive every count at execution time — 20 files / 24 matches under `integration_test/` at HEAD, 4 `GoBridge(` sites in `android/` including two in the debug source set. Never assert a fixed list; that is what TC-390-01 exists to prevent.
- **Build-artifact provenance:** Wave 3 must run a build containing the repair. Read the deploy's `FAILED` lines per the repo's provenance guard.
- **Permission / ACL verb symmetry:** N/A.
- **Fake side-effect fidelity:** TC-390-00/04/05/06 run against the **real repo tree**; the fixture files exist only for TC-390-01/02/03 where a synthetic file is the point.
- **Composite-node / relationship assertions:** TC-390-03 asserts the relationship between a library and **all** its entrypoints on one allow-list entry, not independent facts.

## Gate Cadence

- **Per-plan closure:** the five causal host rows, the three sentinels, discovery + completeness, and one device leg.
- **Graph-affected first:** `python3 graphify-arch/tdd_context.py affected <each repaired harness> --budget 600` before any lane — a hint only; the graph is thin on `integration_test/`.
- **Full `host-all` is not a per-plan gate.** Owned by the notification wave (383/384/385/386/388/389) and final rollout.
- **Shared tests outside the feature/core globs:** the census lives in `test/integration/` and is host-all-only, so it gets the direct `flutter test <path>` command below.

## Acceptance Gates  (literal — copy/paste)

```bash
# Dirty-tree snapshot. Plan 389's files must be clean.
git status --short
git status --short -- integration_test/scripts/ test/integration/group_reaction_   # expect: EMPTY

# Re-derive the census and the executed list yourself — the plan asserts no split
GRAPH_OK=1 grep -rn 'GoBridgeClient(' integration_test/ lib/ | grep -v '.wt-386'

# --- Causal REDs (before any repair) ---
flutter test test/integration/android_bridge_runtime_lease_census_test.dart   # compile RED: file absent
# after the census lands, before Wave 0/2 repairs, it must red on:
#   - the double acquire in group_multi_device_real_harness.dart  (TC-390-00)
#   - 16 unleased offenders                                       (TC-390-04)

# --- Focused GREEN (after Waves 0-2) — exit 0, zero failures ---
flutter test test/integration/android_bridge_runtime_lease_census_test.dart

# --- Preservation sentinels — exit 0 ---
git diff --name-only -- lib/                       # expect: EMPTY
git status --short -- integration_test/scripts/    # expect: EMPTY
./scripts/check_reliability_simulation_discovery.sh   # expect: exit 0, 0 unclassified
./scripts/run_test_gates.sh completeness-check        # expect: PASS, 0 unmatched

# --- Device leg on the EMULATOR (after plan 389's device runs) ---
adb devices -l                                     # expect: emulator-5554 present
flutter test -d emulator-5554 integration_test/<chosen cleanly-launchable harness>.dart

# --- Hygiene ---
flutter analyze            # 0 new issues
git diff --check
```

## Execution Interpretation And Done Criteria

- **Expected RED:** the census file does not exist (compile RED). Once it lands it must red on the `group_multi_device_real_harness.dart` double acquire (TC-390-00) and on the 16 unleased offenders (TC-390-04). TC-390-01/02/03 are authored to red against the *wrong* census shapes — vacuous scan, token matcher, single-entrypoint attribution — and must be written before the census is finalised.
- **GREEN sentinel:** TC-390-05 (transport three + the benchmark path), TC-390-06, TC-390-07.
- **Pre-existing dirty tree / known failure:** `reliability-sim all` aborts at `exit(64)` for an unrelated reason. `sims-contracts` exits 1 at contract #26 (**G28**, plan 387).
- **Environment blocker (NOT a product blocker):** the emulator or the state guard held by a Plan 389 run.
- **Scope drift (BLOCKING):** any `lib/` edit; any file added under `integration_test/scripts/`; a second acquire added to any path that already has one; a call-order-by-position census; a `_test.dart`-only walk; touching anything Plan 389 owns.

- [x] The executed/unleased list is derived and written into this plan before any repair.
- [x] Wave 0's choice is recorded, with its reason.
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded for each causal row.
- [x] The allow-list contains no executed file — it ships empty.
- [x] `git diff --name-only -- lib/` is empty and nothing was added under `integration_test/scripts/`.
- [x] One cleanly-launchable repaired harness passes on `emulator-5554` — `group_real_crypto_onboarding_test.dart`, 4/4.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.

## Device/Relay Proof Profile

- **Profile:** single-device.
- **Boundary being proven:** that the canonical-runtime lease causes the native `GoBridge` to construct and `com.mknoon/go_bridge` to register, so a harness can call it. Unreachable at host tier — there is no native side there.
- **Live availability check:** `adb devices -l` on 2026-08-19 → `21071FDF600CSC` (Pixel 6) and `emulator-5554`, both `device`.
- **Pinned target:** Android emulator **`emulator-5554`**. Deliberately not the Pixel: `flutter test -d` there destroys the stamped release install and the state guard fails closed. Single-device is sufficient — this is a process-local native registration, not a two-peer behaviour.
- **Automation:** harness-driven, no user taps.
- **Closure role:** **required closure evidence** — the census is a tripwire and cannot prove the mechanism.
- **`FLUTTER_DEVICE_ID`:** sufficient; this is a single-device proof.
- **Registration:** the chosen harness is already registered; this plan adds no scenario.
- **Discovery command:** `./scripts/check_reliability_simulation_discovery.sh`.
- **Closure command:** `flutter test -d emulator-5554 integration_test/<chosen>.dart` → passes, having made a successful bridge call.
- **Deferred device work:** the other repaired harnesses are not individually device-proven.

## Handoff

- **First causal RED command:** `flutter test test/integration/android_bridge_runtime_lease_census_test.dart` (compile RED — the file does not exist)
- **Preservation command:** `./scripts/check_reliability_simulation_discovery.sh`
- **Manual registration:** none. `test/integration/*_test.dart` is auto-classified at `run_test_gates.sh:1526-1529`.
- **Migration:** none.
- **Boundary closure:** one `flutter test -d emulator-5554` run of a repaired harness.
- **Unresolved evidence:** none. The `lib/smoke_test_*` question is resolved as out of scope (manual `flutter run -t` roots, no automated executor).

## Reviewer Findings (wf_7e8945e4-3fa — 3 workers + lead source verification, 2026-08-19)

Verdict **plan-fixes-required**; core bet (the root cause) **CONFIRMED**, with every Dart/Kotlin/Swift citation verified exact and the census arithmetic reproduced. All deltas are applied above.

**Blockers closed (5):**
1. **The model harness is itself broken.** `group_multi_device_real_harness.dart` acquires twice with conflicting bindings (`:5938-5942` vs `:1958`→`:561-562`); the broker rejects a non-identical triple and the Dart gateway does not catch the resulting `PlatformException`. The draft held it up as "already fixed" and as a GREEN sentinel, and told 12 harnesses to copy its shape. Now Wave 0, with TC-390-00 as its causal RED and the invariant restated as "exactly one acquire, one binding, per runtime path".
2. **TC-390-04 was `{}=={}` at landing.** The draft's Step 2 seeded the allow-list with every offender, so all acceptance commands exited 0 with zero harnesses repaired. The row now rejects any allow-list entry that is on the executed list.
3. **TC-390-08's oracle did not exist.** `[STACK-DIAG]` is printed only by `ensureCanonicalRuntimeAttachedForTest` — the seam the plan bans — and `CanonicalRuntimeDeviceTestLease` has zero `print(`. The oracle is now the run's own pass/fail.
4. **The prescribed entrypoint repair regressed a working gate.** Leasing `benchmark_harness.dart` breaks `BENCHMARK=GROUP_PUBLISH`, which reaches `setupGroupMultiDeviceStack` and acquires again. Folded into the Wave-0 invariant and TC-390-05.
5. **The census could pass scanning zero files**, and a `_test.dart` filter would skip 9 of 20 offenders including all four no-`main()` libraries. TC-390-01 now asserts a non-empty scan count and TC-390-02 pins the walk.

**Plan-fixes applied:** the seam recipe was incomplete — the constructor takes a required per-harness `binding`, `tearDownAll(runtimeLease.release)` is half the pattern, `acquire()` throws if already active, and the lease deletes/recreates a real SQLCipher database and quiesces the Go runtime, so "destructive side effects: N/A" was false; `benchmark_helpers.dart` has **two** entrypoints (`cold_start_sendable_no_user_action_test.dart:10`/`:23`), so single-entrypoint attribution leaves a path unleased; **import indirection is the dominant blind spot** and was missing from the escape list; there are **four** `GoBridge(` sites in `android/`, two of them in the debug source set that `flutter test -d` compiles; the 12/3/1 split was not reproducible (two defensible criteria give 14/2 and 9/7) so the plan now requires the executor to derive and record the list instead of asserting one; the device leg moves to `emulator-5554` because `flutter test -d` on the Pixel destroys the stamped install and the state guard fails closed; six of sixteen offenders cannot be launched by a bare `flutter test -d`; and HEAD was restamped to `9bc1d6bcb`.

**Confirmed sound and kept:** the root cause and every native/Dart citation; the 20/24 → 19 → 16 census; the `f1b568bca` date correction and the two already-leased files; the three map corrections; the no-CI finding; and the refutation of the repo-root worry — both runners `cd` to the root and relative-root censuses are established prior art.

## Execution Record (2026-08-19)

### Wave 0 — the decision, and why

**Chosen: make `ensureCanonicalRuntimeAttachedForTest()` tolerate an already-ACTIVE lease.** It now calls `gateway.status()` first and acquires only when nothing owns the runtime; `attachRuntime()` runs either way. `MethodChannelCanonicalRuntimeLeaseGateway` already exposed `status()` (`canonical_runtime_lease.dart:83`, `:137-140`), so **no `lib/` change was needed**. The `[STACK-DIAG]` line now says `joined` or `acquired` honestly.

Three reasons this beat the alternative (dropping the `main()` `setUpAll`/`tearDownAll` pair):

1. **The alternative cannot fix `benchmark_harness.dart`.** `BENCHMARK=GROUP_PUBLISH` reaches `setupGroupMultiDeviceStack` through `benchmark_group_publish_harness.dart:74`, so Wave 2 leasing that entrypoint would recreate the identical collision. Tolerance fixes both at once.
2. **The alternative breaks a pre-existing gate.** `test/integration/group_multi_device_shared_path_test.dart:36-62` asserts, by source scan, that the group harness's `main()` contains `final runtimeLease = CanonicalRuntimeDeviceTestLease(`, `setUpAll(runtimeLease.acquire);`, `tearDownAll(runtimeLease.release);` **in that order**, before the MD-004 `testWidgets`. Dropping the pair reds it. The plan did not know this test existed — the graph's `affected` step surfaced it.
3. **It keeps the release.** `tearDownAll(runtimeLease.release)` is what quiesces the Go runtime; dropping the pair leaves the runtime attached and the probe database on disk.

`attachRuntime` is idempotent — it returns the handler's existing `runtimeAttached` (`CanonicalRuntimeLease.kt:201-204`) and requires only that the handler already holds a token, which the entrypoint's own acquire set over the same channel. The join therefore costs one extra `status` round trip and nothing else.

### Wave 2 — two deviations from the plan's recipe, both narrowing risk

- **`support/android_critical_performance_campaign.dart` self-guards** inside `_measureProductionGoBridge()` rather than being leased at its entrypoint. `sims_dispatcher.dart` is the shared prebuilt-APK target for **every** sims scenario; only this one crosses the bridge. Leasing the dispatcher would have made `android.voice_recorder_native_smoke` (an `active`, `required` capability) attach the Go runtime and open a probe database it does not use.
- **`android_background_crypto_preflight_app.dart` self-guards** through a one-shot helper called before each of its two bridge constructions. It is built as a real APK (`flutter build apk --debug --target`) and has no `flutter_test` lifecycle at all, so `setUpAll` does not exist there; it holds the lease for the life of the process, the shape production uses. The guard is load-bearing — `acquire()` throws `StateError` if called twice and the two sites sit on branches a re-executed `main()` can reach in either order.

Both are accepted by the census's **self-guarded** branch, which is the same branch that clears `group_multi_device_real_harness.dart`.

### Evidence

| Row | State at HEAD | After | Mutation re-red |
|---|---|---|---|
| TC-390-00 | RED — the joiner acquired unconditionally under its own fixed binding | GREEN | pre-Wave-0 tree is exactly the mutation; plus `expected 1 acquire on runtimeLease, found 2` and `owns 2 leases` both re-red on demand |
| TC-390-01 | GREEN, non-vacuous — 227 files scanned against a pinned floor of 200 | GREEN | a root pointed at a missing directory scans 0 |
| TC-390-02 | GREEN — fixture with `DurableNotificationToneLease` + a bare `acquire` is still reported | GREEN | a token matcher clears it; a `_test.dart` walk skips the library fixture |
| TC-390-03 | GREEN — library cleared only when **both** entrypoints lease | GREEN | lease one of two → the other is named |
| TC-390-04 | RED — 17 unleased (site, entrypoint) pairs | GREEN | `benchmark_harness.dart` onto the allow-list → tautology assertion reds; drop its lease → named for all 3 files it reaches |
| TC-390-05 | RED — `benchmark_harness.dart` held no lease | GREEN | second acquire / second owner both re-red |
| TC-390-06 | GREEN | GREEN | widening the root to `lib/` reports the production bootstrap |
| TC-390-07 | GREEN | GREEN | discovery PASS exit 0; completeness-check PASS 1469/1469 |
| TC-390-08 | manual/device-only | **GREEN on `emulator-5554`** | lease reverted, rebuilt and re-run on the same emulator → **4 × `GO_BRIDGE_MISSING_PLUGIN`, 0 passed / 4 failed** |

**TC-390-08, `flutter test -d emulator-5554 integration_test/group_real_crypto_onboarding_test.dart`.** Chosen from the cleanly-launchable set: no `fromEnvironment` fixture, no role, no relay account (`:263`), four real-crypto `testWidgets`. Real Gradle `assembleDebug` (28.4s) and a real install, then `GO_BRIDGE_INIT_SUCCESS` with `"type":"native"` and successful `BRIDGE_CALL_TIMING` for `identity.generate` (41ms), `mlkem.keygen`, `node:start`, `group:create`, `group:updateConfig`, `payload.sign`, `message.encrypt`, `message.decrypt`, plus `"layer":"GO"` push events from the Go runtime. **4/4 passed, exit 0.**

**The mutation proves the mechanism, not just correlation.** Reverting only that harness's four-line lease block and its import, then rebuilding and re-running on the same emulator, gives `GO_BRIDGE_MISSING_PLUGIN {"cmd":"identity.generate","initialized":true,"error":"No implementation found for method generateIdentity on channel com.mknoon/go_bridge"}` four times and **0 passed / 4 failed**. Note `GO_BRIDGE_INIT_SUCCESS type:native` still fires in the mutated run — `initialize()` only subscribes to the EventChannel, whose failure lands asynchronously — which is exactly why TC-390-08's oracle is the run's own pass/fail and not a log line. The tree was restored from a snapshot and the census re-verified green afterwards.

The emulator is `arm64-v8a` (Apple Silicon host), not x86_64 as the plan assumed. That is still a correct target: `android/app/libs/GoMknoon.aar` ships `arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`, and the only `abiFilters` narrowing (`build.gradle.kts:274-279`) applies solely when the sims property `simsAndroidAbi` is set, which a bare `flutter test -d` does not set.

### Corrections to the plan, found in source

- **The plan's per-file offender view is not the actionable one.** Attribution must be per (constructing file, entrypoint): 16 unleased files map to **15** entrypoints, two of which the plan never named (`cold_start_sendable_no_user_action_test.dart`, `sims_dispatcher.dart`).
- **Self-guarding had to be added as a coverage rule.** Without it the census charges the seven harnesses that reach the bridge only through `setupGroupMultiDeviceStack`, and repairing them would create exactly the double acquire the plan's hard rule forbids.
- **A lease constructed inside another entrypoint's `main()` must not count.** Only one `main()` runs per process; the first draft of the census charged every importer of the group harness.
- **The plan's own pairing idea is a loose-token trap.** Counting bare `.acquire` / `.release` charges `group_multi_device_real_harness.dart` for an unrelated `traceLease.release()` and for the joiner's own `gateway.acquire` — the very failure TC-390-02 exists to reject. The count is bound to the owner's variable.
- **`test/integration/group_multi_device_shared_path_test.dart` was not in the plan** and constrains Wave 0's choice (see above).
- **The Go AAR is not x86_64-only** (four ABIs), and the emulator on this host is arm64.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-19 | Step 1 — derive | census + `run_test_gates.sh`, `check_reliability_simulation_discovery.sh --records-tsv`, `critical_features.json`, `run_transport_census.sh`, `run_routing_smoke_e2e.dart` | census reproduced 20/24 → 19/23 → 16 unleased | 15 unleased entrypoints; 13 executed / 2 dormant | list written into this plan | write the census |
| 2026-08-19 | Wave 1 — census `3e0a74f50` | `test/integration/android_bridge_runtime_lease_census_test.dart` | `flutter test` → 4 passed / 3 failed | causal RED on TC-390-00, TC-390-04 (17 pairs), TC-390-05 | fixtures caught two real model bugs while being authored | Wave 0 |
| 2026-08-19 | Wave 0 — join `ba7707652` | `group_multi_device_real_harness.dart` | TC-390-00 GREEN | status-first joiner; no `lib/` change | tolerance chosen over dropping the pair, 3 reasons above | Wave 2 |
| 2026-08-19 | Wave 2 — repairs `647c4efe2` | 15 entrypoints under `integration_test/` | census **7/7 GREEN**; analyze clean | allow-list ships empty; 4 mutation re-reds proven | 2 self-guard deviations recorded | Wave 3 |
| 2026-08-19 | Wave 3 — device | `group_real_crypto_onboarding_test.dart` on `emulator-5554` | 4/4 passed, exit 0 | `GO_BRIDGE_INIT_SUCCESS type:native` + 8 successful bridge cmds | TC-390-08 GREEN | mutation re-run |
| 2026-08-19 | Wave 3 — mutation | same harness, lease reverted then restored | 0 passed / 4 failed | 4 × `GO_BRIDGE_MISSING_PLUGIN` on `com.mknoon/go_bridge` | mechanism proven; tree restored, census re-verified 7/7 | **plan CLOSED** |
