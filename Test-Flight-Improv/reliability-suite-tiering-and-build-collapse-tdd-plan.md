# Reliability Suite — Tiering (L6) + Multi-Party Build Collapse (L1/L1b/L12) — TDD Plan

**Date:** 2026-06-18
**Branch target:** `124-harness-refactor` (companion to `124-integration-harness-refactor-tdd-plan.md` and `intro-e2e-build-reuse-tdd-plan.md`)
**Scope:** the full `run_with_devices.sh` reliability suite (~24h), whose cost is dominated by the **109 multi-party device scenarios** (71% of 154 plan items) run via `run_group_multi_party_device_real.dart`.
**Status:** PLAN ONLY — analysis complete, implementation deferred. **No tests run, no code changed.**
**Method:** 5-agent read-only adversarial audit of the suite (build model / runner orchestration / non-multiparty builds / network time-sinks / parallelism+tiering) + targeted source-anchor verification. All file:line anchors working-tree-verified on this branch.

> **Prime directive:** every per-scenario verdict stays identical before and after each change. The full
> 109-scenario sweep remains the release gate; tiering only changes *what runs on a routine invocation*,
> never *what a scenario asserts*. Each slice is independently shippable and reversible.

This plan implements the two highest-value levers from the suite audit:
- **Slice A = L6 (tiering)** — a curated "smoke" subset for routine runs; reserve the full 109 for nightly/release. **Ship first** (low risk, no harness surgery).
- **Phase 0 + Slice B = L1 + L1b (build collapse)** — move the multi-party harness's per-run parameters from compile-time `--dart-define` to an app-visible runtime config channel, so **one** built app serves all 109 scenarios × all roles (≈357 iOS builds → 1). Gated by a mandatory 2-scenario probe that proves both app visibility and build-cache reuse (Phase 0).
- **Slice C = L12** — collapse the 109 shell plan rows into one `--scenario all` process so the single warm build is actually reused across the sweep.

It is the same runtime-parameterization principle as `intro-e2e-build-reuse-tdd-plan.md`, applied to the multi-party harness at ~100× scale. The channel must be app-visible before `main()` consumes it; do not assume host `Process.start(... environment: ...)` reaches a Flutter app launched by `flutter drive`.

**Session evidence folded in (2026-06-18):** #154 failed when a simulator launched to onboarding with no `intro_e2e_identity.json`. The stable fix was a single file-backed runtime channel (`Documents/auto_setup.json`) written after install and before launch; `SIMCTL_CHILD_AUTO_SETUP_USERNAME` and username dart-defines were removed from the executable intro/notification harnesses. A focused #154 rerun passed all 11 scenarios on iOS 26.1. That run proves file-backed simulator config is reliable and that removing per-role username defines speeds repeated builds (first build ~122s, then ~48s, then ~16-20s incremental builds in the same command). It does **not** prove that arbitrary host environment passed to `flutter drive` is visible inside the simulator app.

---

## 0. What actually ships

| Slice | Change | Files | Migration | Effect |
|-------|--------|-------|-----------|--------|
| **A (L6)** | curated smoke tier via `RELIABILITY_GROUP_TIER` + `smokeGroupMultiPartyDeviceScenarioIds` | criteria.dart, run_group_multi_party_device_real.dart, run_reliability_simulations.sh | none | routine run **24h → ~20-40 min** |
| **0** | 2-scenario timing probe (de-risk gate for B) | — (manual measured run) | none | confirms app visibility + cache reuse on runtime-config-only change |
| **B (L1+L1b)** | per-run params `--dart-define` → app-visible runtime config; one sweep-level runId | group_multi_party_device_real_harness.dart, run_group_multi_party_device_real.dart | none | **~357 builds → 1** |
| **C (L12)** | 109 shell plan rows → 1 `--scenario all`; orchestrator continue-on-failure + verdict reconstruction | run_reliability_simulations.sh, run_group_multi_party_device_real.dart | none | single warm build reused across sweep |

**Landing order:** A → 0 → B → C. A is independent and ships immediately. 0 must pass before B. C depends on B (otherwise a single process still rebuilds per scenario).

---

## 1. Problem statement

A full `run_with_devices.sh` run takes ~24h, executing 154 plan items **strictly sequentially**
(run_reliability_simulations.sh:598-623) against one fixed pool of 4 booted iPhone sims. The cost
concentrates in the **109 multi-party scenarios** (`dart run run_group_multi_party_device_real.dart
--scenario X`, one shell plan item each).

**Root cause (audit, CONFIRMED):** every role of every scenario is launched as a fresh `flutter drive`
(iOS, run_group_multi_party_device_real.dart:144-151) with **per-launch `--dart-define`s** —
`GROUP_MULTI_PARTY_SCENARIO/_ROLE/_RUN_ID/_MODE`, `E2E_DB_NAME` (embeds scenario+runId+role),
`E2E_SHARED_DIR` (:152-166) — and the harness reads **all of them via compile-time
`String.fromEnvironment`** (group_multi_party_device_real_harness.dart:77-116). Any define change busts
Flutter's kernel cache → a full rebuild + reinstall. Verified build math: 84 three-role ×3 + 11
four-role ×4 + ~61 stateful-relaunch extras ≈ **~357 iOS builds** at ~2-4 min each = the bulk of the 24h.

Two structural facts make the fix tractable and the tiering obvious:
- The harness consumes these values **only at runtime** — 180 `if (_scenario == '…')` comparisons, zero
  `const`/`switch` dependence (audit CONFIRMED). So changing their *source* from compile-time
  `String.fromEnvironment` to a runtime config loader is a small logical change despite the ~49K-line file;
  the hard part is choosing a channel the simulator app actually sees before startup.
- These orchestrators are documented as **Nightly / Release Pool, not per-PR gates**
  (test-gate-definitions.md:46-53). Running all 109 on every invocation is itself the core inefficiency.

---

## 2. Goals / Non-goals

**Goals**
- **A:** a curated ~8-12-scenario smoke tier covering each risk area, selectable without touching the
  external `run_with_devices.sh` scope parser; full 109 stays the default for nightly/release.
- **B:** one built binary serves every scenario × role × relaunch (≈357 → 1), with byte-identical
  per-scenario verdicts. Gated by an empirical cache-reuse probe (Phase 0).
- **C:** the 109 scenarios run in one `--scenario all` process (so the warm build is reused), with
  per-scenario PASS/FAIL granularity and `--only`/resume preserved.

**Non-goals (this round)**
- Parallel role launches / item-level parallelism / sharding (audit L3/L7/L8) — separate plans.
- Trimming settle/poll waits (audit L4) — separate; risky.
- The non-multiparty 22+16+4 build dedup (audit L9/L10/L11) — track separately (group_lifecycle 4→1 is a
  trivial follow-on of B's pattern).
- Changing what any scenario asserts.

---

## 3. Corrected source anchors (working-tree-verified)

**`group_multi_party_device_real_harness.dart`** (~49.5K lines) — the 9 compile-time reads to flip (B):
- `const _sharedDir = String.fromEnvironment('E2E_SHARED_DIR', defaultValue:'/tmp')` :77-80
- `const _role …('GROUP_MULTI_PARTY_ROLE', 'alice')` :81-84 · `const _scenario …('…_SCENARIO', 'gm001')` :85-88
- `const _runId …('…_RUN_ID', 'adhoc')` :89-92 · `const _mode …('…_MODE', 'proof')` :93-96
- `const _restoreMnemonic …('…_RESTORE_MNEMONIC', '')` :101-104 · `const _restoreIdentityPath …` :105-108
- `const _reuseExistingIdentity = bool.fromEnvironment('…_REUSE_EXISTING_IDENTITY', false)` :109-112
- `const _configuredDbName = String.fromEnvironment('E2E_DB_NAME', '')` :113-116
- `main()` :49492 → `Directory(_sharedDir).createSync(recursive:true)` :49499 (runtime FS already happens here).
- `import 'dart:io'` already present :3 (so `Platform.environment` is in scope).
- Genuine consts to LEAVE: `_identityExchangeTimeout = Duration(minutes:90)` :117, `_liveTopicLeavePropagationDelay` :118.

**`run_group_multi_party_device_real.dart`** (2566 lines)
- `_startHarnessRole` :132-187 — argv built :144-169 (the `--dart-define`s to relocate :152-166); per-role
  uninstall :182-184; `Process.start('flutter', args)` :186. `import 'dart:io'` :5.
- `main(List<String> args)` :2515 — already reads `Platform.environment['MKNOON_RELAY_ADDRESSES']` :2520
  and passes it as a child `--dart-define` :164 (constant across launches → cache-stable; **keep**).
  `--list-scenarios` branch :2531-2542; the sweep loop `for (final scenarioToRun in _scenariosToRun(scenario))` :2558.
- `_scenariosToRun(scenario)` :255-518 (switch; `'all'` → `allGroupMultiPartyDeviceScenarioIds` :510-511).
- Per-scenario fresh runId via `DateTime.now().millisecondsSinceEpoch` and fresh `systemTemp.createTemp`
  (e.g. :1090-1091) — the L1b consolidation targets.
- Per-scenario verdict file `${scenario}_orchestrator_verdict.json` (~:1145-1158) — the granularity source for C.

**`scripts/run_reliability_simulations.sh`** (632 lines)
- scope case :57-104; awk scope selector :125-134.
- Multi-party expansion: `group_multi_party_scenarios()` :192-202 (calls `--scenario all --list-scenarios`),
  consumed at :223-233 to emit one plan row **per** scenario. `--only`/`--start-at` selector awk :245-279.
  run loop :598-623; `run_path` :474-548 (`dart run … --scenario X` :515-528). `--list`/dry-run exit :567-570.

**`integration_test/scripts/group_multi_party_device_criteria.dart`** — `allGroupMultiPartyDeviceScenarioIds`
(unmodifiable list, :631); `_scenarioRequirements` 110 keys; `roleDeviceMapForScenario` :707-710;
`scenarioRequirement(...)`. This is where `smokeGroupMultiPartyDeviceScenarioIds` (A) lives.

**Test surfaces** — Dart unit idiom: `test/features/identity/application/generate_identity_use_case_test.dart`
(pure function + injected map). Shell contract precedent: none in-repo (S/A and C add isolated tests under
`scripts/test/`, mirroring the intro-plan's PATH-shim approach). Dry-run/`--list` plan inspection already
works (used to enumerate the 154-item plan during the audit).

---

## 4. Slice A — L6 tiering *(ship first; no migration; lowest risk)*

A curated smoke subset of the 109, selected via an **env var** (`RELIABILITY_GROUP_TIER`) so it flows
through the external `run_with_devices.sh`/`run_test_gates.sh` unchanged (they export env transparently;
no new scope keyword to add to the external wrapper's parser).

### 4.1 RED — write these first

New `test/integration/group_multi_party_smoke_tier_test.dart` (**does not exist**):
1. `smokeGroupMultiPartyDeviceScenarioIds` is a **strict subset** of `allGroupMultiPartyDeviceScenarioIds`
   (every smoke id ∈ all; size in [8,12]).
2. Every smoke id resolves via `scenarioRequirement(id)` without throwing (valid, runnable).
3. **Risk-area coverage:** the smoke set contains ≥1 representative per category — create
   (`private_abc_create`), membership add/remove (`private_online_add`/`private_online_remove`),
   offline (`private_offline_add`/`gm003`), reactions (`private_reaction_roundtrip`), recovery/restart
   (`ge012`/`ge014`), relay transport (`private_relay_only_delivery`), roles
   (`private_admin_role_transfer_delivery`), 4-role (`private_process_death_matrix`). (Assert the exact
   curated ids — this test is the coverage contract.)

Orchestrator arg test (extend existing CLI parse coverage or new `…_scenarios_to_run_test.dart`):
4. `_scenariosToRun('smoke')` returns `smokeGroupMultiPartyDeviceScenarioIds` (does **not** throw, is **not**
   treated as a single literal scenario).

New `scripts/test/reliability_group_tier_contract_test.sh` (**new infra**, mirror intro-plan PATH-shim):
5. `RELIABILITY_GROUP_TIER=smoke ./scripts/run_reliability_simulations.sh group --list` emits a plan whose
   multi-party rows == the smoke set (e.g. 10), **not** 109.
6. Unset/`full` → 109 rows (default unchanged). Bad value → fail loudly (don't silently run all).

### 4.2 GREEN — implementation (sketch; do not implement now)
- `group_multi_party_device_criteria.dart`: add `const smokeGroupMultiPartyDeviceScenarioIds = <String>[…]`
  (the curated ids) next to `allGroupMultiPartyDeviceScenarioIds` :631 — **single source of truth**.
- `run_group_multi_party_device_real.dart`: in `_scenariosToRun` (:255), add `case 'smoke': return
  smokeGroupMultiPartyDeviceScenarioIds;` (so `--scenario smoke [--list-scenarios]` works); add `smoke` to
  the usage string.
- `run_reliability_simulations.sh`: in `group_multi_party_scenarios()` (:192-202), when
  `${RELIABILITY_GROUP_TIER:-full}` == `smoke`, list via `--scenario smoke --list-scenarios` instead of
  `--scenario all`; validate the var (`smoke|full` only) and echo the chosen tier in the plan header (:550).

### 4.3 Invariants / notes
- **Coverage honesty:** the smoke tier is NOT a release gate. Document loudly in the plan header and
  test-gate-definitions.md that `full` (109) remains the nightly/release requirement.
- **Zero behavior change** to any scenario; this only filters the *set* that runs.
- Smoke-id selection is a judgement call — the §4.1.3 test freezes it; the team should reconcile against
  failure history before merge.

### 4.4 Gates
`flutter analyze` 0 new · the 2 Dart tests + the shell contract test green · `RELIABILITY_GROUP_TIER=smoke
… group --list` shows the curated set · (optional live) the smoke tier runs green on sims in ~20-40 min.

---

## 5. Phase 0 — 2-scenario runtime-channel + cache-reuse probe *(MANDATORY gate before Slice B)*

The entire B premise is: *Flutter reuses the iOS build when no app-visible runtime parameter is encoded in
`--dart-define` or sources.* Two separate facts must be proven on this toolchain before the refactor:
1. the chosen runtime channel is visible to the app before the harness reads `_scenario`/`_role`/DB/shared-dir;
2. changing only that runtime config does not trigger a rebuild.

- **Procedure (manual, measured — not a unit test):** behind a throwaway local branch, prototype the
  runtime channel for just two scenarios (e.g. `private_abc_create` then `private_reaction_roundtrip`):
  build once, launch scenario 1's roles, then scenario 2's roles, all with identical dart-defines and only
  app-visible runtime config differing. Prefer the #154-proven file-backed shape: a per-role JSON manifest
  staged in the simulator app data container after install and before launch. If using `Platform.environment`,
  prove with an in-app marker/log that `flutter drive` actually forwards the value to the simulator app; host
  `Process.start(... environment: ...)` alone is not sufficient evidence.
- **Pass criterion:** every launched role logs/exports the expected scenario+role+DB/shared-dir values from
  the runtime channel, and scenario 2's launches show a **cache hit** (no "Compiling…/Building…/pod install"
  Dart-kernel recompile; wall-clock collapses to attach+install, not a full build). Record before/after
  seconds in the plan's implementation log.
- **Decision gate:** if scenario 2 still recompiles, the full-collapse premise is **refuted** for this
  toolchain → fall back to the audit's *per-scenario build-reuse only* option (stabilize within a scenario,
  one build per scenario, ~357 → ~110) and re-scope B. If the app cannot see the chosen runtime channel before
  startup, re-scope B to a #154-style install/stage/launch path or prebuilt-app attach flow before proceeding.

### 5.1 Phase 0 implementation log

- **2026-06-18 20:47 CEST — PASS.** Added and ran the isolated Phase 0 probe
  `scripts/run_group_multi_party_phase0_probe.sh` with target
  `integration_test/group_multi_party_phase0_runtime_channel_probe.dart` against iOS 26.1 simulators
  `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and
  `1B098DFF-6294-407A-A209-BBF360893485`.
- Runtime-channel evidence: the probe staged
  `Documents/group_multi_party_phase0_runtime.json` per simulator/role and launched the same installed
  debug app for `private_abc_create` then `private_reaction_roundtrip`. The app emitted six markers in
  `build/group-multi-party-phase0/phase0_20260618T204134/runtime_visibility_verdict.json`, each with
  `source: documents-file` and the expected `scenario`, `role`, `runId`, `mode`, `dbName`, and `sharedDir`.
- Cache-reuse evidence: the first identical `flutter build ios --simulator --debug --no-pub --target
  integration_test/group_multi_party_phase0_runtime_channel_probe.dart` took 221s total, with Xcode
  `189.4s`; the second identical build after scenario 1 took 76s total, with Xcode `20.7s`. Logs are
  `build/group-multi-party-phase0/phase0_20260618T204134/logs/build_first.log` and
  `build/group-multi-party-phase0/phase0_20260618T204134/logs/build_scenario_1_cache_probe.log`.
- Decision: Phase 0 supports proceeding to Slice B with the file-backed Documents runtime channel. Do not
  use host `Process.start(... environment: ...)` as the runtime channel without separate in-app proof.

---

## 6. Slice B — L1 + L1b build collapse *(gated by Phase 0; no migration)*

Move every per-run parameter from compile-time `--dart-define` to a single app-visible runtime config channel,
so the `--dart-define` set is **identical across all launches** (only constant values such as
`MKNOON_RELAY_ADDRESSES` / rapid key-rotation grace remain defines) → the build cache stays warm → one build.
The runtime channel may be `Platform.environment` only if Phase 0 proves the simulator app receives it through
the actual launch path. Otherwise use the #154-proven file-backed manifest staged before launch.

### 6.1 RED — write these first

New `test/integration/group_multi_party_runtime_config_test.dart` (**does not exist**) — for an extracted
**pure** parser `resolveGroupMultiPartyConfig(Map<String,String> values)` (injectable map; no direct
`Platform`/filesystem dependency in the parser):
1. full value map → typed config with matching `scenario/role/runId/mode/sharedDir/dbName/restore*/reuse`.
2. missing keys → the current defaults (`alice`/`gm001`/`adhoc`/`proof`/`/tmp`/`''`/`false`) — **byte-equivalent
   to today's `String.fromEnvironment` defaults**.
3. `reuseExistingIdentity` parses `'true'`/absent → bool; empty restore strings stay empty.

New `test/integration/group_multi_party_launch_spec_test.dart` (**does not exist**) — for an extracted pure
`buildHarnessLaunchSpec({...}) → ({List<String> args, RuntimeConfigPlan runtimeConfig})` from `_startHarnessRole`:
4. the returned `args` contain **no** `--dart-define=GROUP_MULTI_PARTY_*`, `E2E_DB_NAME`, or `E2E_SHARED_DIR`
   (the cache-stability invariant) — the **mutation-verified RED**: this fails on today's code.
5. `runtimeConfig` carries scenario/role/runId/mode/dbName/sharedDir/restore/reuse with the correct values
   and names the app-visible staging mechanism (file-backed by default; env only if Phase 0 proved it).
6. `args` still contain the `drive`/`test` subcommand, `-d <device>`, and the constant
   `--dart-define=MKNOON_RELAY_ADDRESSES=…` (kept).

L1b — runId consolidation test (in `…_launch_spec_test.dart` or a small orchestrator test):
7. across a simulated 2-scenario sweep, `buildHarnessLaunchSpec` receives **one** sweep-level runId (not a
   fresh `DateTime.now()` per scenario) — locks the single-runId hygiene.

### 6.2 GREEN — implementation (sketch)
- **Harness** (group_multi_party_device_real_harness.dart:77-116): replace the 9 `const _X =
  String/bool.fromEnvironment(...)` with `final _X = …` sourced from a single runtime config loader. The
  loader should read the Phase-0-proven channel (file-backed manifest by default; `Platform.environment`
  only if the real `flutter drive` launch path proved it reaches the app). The ~180 `_scenario`/`_role`/…
  call sites are **unchanged**. ⚠ Flipping `const`→`final` makes `flutter analyze`
  fail at any genuine const-context use — that analyzer error **is** the audit for hidden const deps;
  resolve each before GREEN is done (audit reported zero, but the compiler is the proof).
- **Orchestrator** (`_startHarnessRole` :144-187): stop appending the per-run `--dart-define`s (:153-163);
  instead stage the runtime config through the Phase-0-proven app-visible mechanism. If the final mechanism
  is file-backed, the orchestrator must own or wrap install/stage/launch ordering; do not just pass a host
  env map to `flutter drive` and assume the app saw it. Keep constant defines such as
  `MKNOON_RELAY_ADDRESSES` (:164) and rapid key-rotation grace stable across the sweep. Build the spec via
  the extracted `buildHarnessLaunchSpec` so it is the tested seam.
- **L1b** (single runId): mint `runId` once in `main()` (:2515) and thread it into every `_run*Scenario`/
  `_startHarnessRole`, removing the ~11 per-scenario `DateTime.now().millisecondsSinceEpoch` sites
  (:1090 etc.). Note: with everything in env, per-scenario runId would no longer bust the cache either —
  L1b is **defense-in-depth + hygiene** ensuring the define set is provably invariant, not the sole
  mechanism.

### 6.3 Invariants
- **Cache-stability invariant (the whole point):** the `--dart-define` list on every `flutter drive`/`test`
  is identical across all launches in a sweep (only constant relay define) — asserted by RED #4.
- **Isolation preserved:** per-role `E2E_DB_NAME` and per-scenario shared dir still differ — but now via
  runtime config (no cache impact). If the shared dir is stabilized for any reason, signal/DB files must
  remain namespaced by scenario+role to avoid cross-scenario collision (today `createTemp` per scenario
  handles this; keep per-scenario subdirs).
- **Default parity:** `resolveGroupMultiPartyConfig` defaults are byte-equivalent to the old
  `String.fromEnvironment` defaults (RED #2), so a plain `flutter test integration_test/<harness>` with no
  env still behaves as before.
- **MKNOON_RELAY_ADDRESSES** stays a define because the prod app may read it at compile time; it is constant
  per sweep so it does not bust the cache. (If a future change moves it to env too, even cleaner.)

### 6.4 Gates
`flutter analyze` 0 new (const→final audit clean) · the 3 Dart unit tests green · Phase 0 probe PASSED ·
**live: a single `dart run … --scenario all` (or two back-to-back scenarios) builds once and all attempted
scenarios pass with identical verdicts vs baseline** · device: the 3-4 iPhone sim pool.

### 6.5 Slice B implementation log

- **2026-06-18 — implemented with the Phase-0-proven Documents-file channel.** Added
  `integration_test/scripts/group_multi_party_runtime_config.dart` with a pure
  `resolveGroupMultiPartyConfig(Map<String, String>)` parser and a `GroupMultiPartyRuntimeConfig` model.
- Harness change: `integration_test/group_multi_party_device_real_harness.dart` no longer reads the nine
  per-run values through `String/bool.fromEnvironment`; it resolves `_sharedDir`, `_role`, `_scenario`,
  `_runId`, `_mode`, restore fields, reuse flag, and DB name from
  `Documents/group_multi_party_runtime_config.json` via `path_provider`, preserving legacy defaults when the
  file is absent.
- Orchestrator change: `integration_test/scripts/run_group_multi_party_device_real.dart` now builds a tested
  `HarnessLaunchSpec` whose Flutter args contain only stable compile-time defines
  (`MKNOON_RELAY_ADDRESSES` and constant rapid key-rotation grace). Per-run `GROUP_MULTI_PARTY_*`,
  `E2E_DB_NAME`, and `E2E_SHARED_DIR` values are staged into the installed iOS app container under
  `Documents/group_multi_party_runtime_config.json`; iOS launches use build/install/stage then
  `flutter drive --no-build`. No host `Process.start(... environment: ...)` channel is used.
- L1b change: `main()` now mints one sweep-level `runId` and threads it through every scenario runner instead
  of generating a fresh timestamp per scenario.
- Host evidence: `flutter test test/integration/group_multi_party_runtime_config_test.dart
  test/integration/group_multi_party_launch_spec_test.dart` passed; the Slice A smoke-tier tests and
  `scripts/test/reliability_group_tier_contract_test.sh` still pass; `flutter analyze` on the five changed
  Slice B Dart files reported no issues. Full-repo `flutter analyze` still exits nonzero on the existing
  analyzer backlog, so the clean claim is scoped to changed files.
- Live simulator evidence: `dart run integration_test/scripts/run_group_multi_party_device_real.dart
  --scenario slice_b_live -d <alice>,<bob>,<charlie>` passed on 2026-06-18 with sweep run id
  `1781811896647`; artifact:
  `build/group-multi-party-slice-b-live/slice_b_20260618T214455/live.log`.
  The sweep built the iOS harness once, staged
  `Documents/group_multi_party_runtime_config.json` for each role launch, used repeated
  `flutter drive --no-build` launches, and produced green verdict parity for `private_abc_create` and
  `private_reaction_roundtrip` across alice, bob, and charlie.
- Live-gate caveat: this Slice B runtime channel is proven for iOS simulators only. The non-iOS launch path still
  does not stage per-run runtime config. Flutter driver output also prints `Running Xcode build...` during the
  `--no-build` launches even though the orchestrator command line uses `--no-build` after the single explicit
  `flutter build ios` harness build.

---

## 7. Slice C — L12 single `--scenario all` plan item *(depends on B)*

So the one warm build is actually reused: stop expanding the multi-party path into 109 separate `dart run`
processes; run them all in one `--scenario all` process (which already loops at :2558).

### 7.1 RED — write these first

Extend `scripts/test/reliability_group_tier_contract_test.sh` (or a sibling):
1. `./scripts/run_reliability_simulations.sh group --list` emits **one** multi-party plan row
   (`dart run … --scenario all`), not 109. (`smoke` tier → one `--scenario smoke` row.)
2. `--only <scenario-id>` still maps to a single `dart run … --scenario <id>` (resume/isolation preserved).

Orchestrator behavior test (new `…_sweep_continue_on_failure_test.dart`, or a process-level test):
3. with `--scenario all`, a mid-list scenario failure does **not** abort the remaining scenarios; the
   orchestrator attempts all, writes each `${scenario}_orchestrator_verdict.json`, and exits **non-zero**
   iff any failed (so the shell still sees red).

### 7.2 GREEN — implementation (sketch)
- `run_reliability_simulations.sh`: special-case `run_group_multi_party_device_real.dart` in the expansion
  (:223-233) to emit a single row with scenario `all` (or `smoke` per `RELIABILITY_GROUP_TIER`) instead of
  one row per listed scenario. Keep the `--only <id>` path mapping to a single-scenario `dart run`.
- `run_group_multi_party_device_real.dart`: wrap each `_runScenario` in the :2558 loop in try/catch,
  accumulate failures, keep writing per-scenario verdicts, and `exit(1)` at the end iff any failed (add a
  `--continue-sweep` default-on, or always-continue under `--scenario all`). Print a per-scenario PASS/FAIL
  summary so the shell's lost per-item line is reconstructed from the orchestrator's own output.

### 7.3 Invariants
- **Granularity preserved:** per-scenario PASS/FAIL is reconstructable from `${scenario}_orchestrator_verdict.json`
  (:1145-1158) and the new summary; resume via `--only`/`--start-at` still works for single scenarios.
- **No coverage change:** `--scenario all` runs exactly the 109 (or smoke subset) — same set, one process.

### 7.4 Gates
`bash -n` clean · the shell + orchestrator tests green · live: `group --list` shows one multi-party row ·
a full `--scenario all` sweep completes with **1** build and per-scenario verdicts identical to the
109-process baseline.

### 7.5 Slice C implementation log

- **2026-06-18 — implemented the collapsed multi-party group plan row.**
  `scripts/run_reliability_simulations.sh` now emits one
  `integration_test/scripts/run_group_multi_party_device_real.dart --scenario all` row for the default/full
  group tier and one `--scenario smoke` row for `RELIABILITY_GROUP_TIER=smoke`. Bare
  `--only <scenario-id>` and `--only path:scenario` still emit an isolated single-scenario runner row.
- Orchestrator change: `integration_test/scripts/run_group_multi_party_device_real.dart` now runs aggregate
  selectors through `runGroupMultiPartyScenarioSweep`, which logs per-scenario `SWEEP PASS`/`SWEEP FAIL`
  summaries, continues after failures when the selected scenario expands to multiple scenarios, and exits `1`
  if any attempted scenario failed.
- RED/host evidence: `bash -n scripts/run_reliability_simulations.sh
  scripts/test/reliability_group_tier_contract_test.sh` passed;
  `scripts/test/reliability_group_tier_contract_test.sh` passed; focused
  `flutter test test/integration/group_multi_party_sweep_continue_test.dart
  test/integration/group_multi_party_scenarios_to_run_test.dart
  test/integration/group_multi_party_launch_spec_test.dart
  test/integration/group_multi_party_runtime_config_test.dart` passed; focused
  `flutter analyze` on the touched Slice B/C Dart files reported no issues.
- Review fix evidence: aggregate scenario failures now persist a standardized failure
  `${scenario}_orchestrator_verdict.json` under the sweep failure-artifacts directory even when the scenario runner
  throws before writing its own verdict. The sweep-continue test now covers a fake runner that throws before writing
  any failure verdict; focused Slice C host tests, shell contract, and focused analyzer still pass.
- Dry-run evidence: `./scripts/run_reliability_simulations.sh group --list` prints
  `Group multi-party tier: full (1 active plan row(s): all; ...)` and exactly one multi-party command row;
  `RELIABILITY_GROUP_TIER=smoke ./scripts/run_reliability_simulations.sh group --list` prints one
  `--scenario smoke` row; `./scripts/run_reliability_simulations.sh group --list --only private_abc_create`
  prints one `--scenario private_abc_create` row.
- Remaining live gate: the full simulator-backed `--scenario all` sweep has not been run in this pass. It remains
  the expensive release-confidence proof for one iOS harness build plus per-scenario verdict parity across the full
  multi-party set.

---

## 8. Cross-cutting invariants

1. **Verdict parity:** every scenario's pass/fail and proof artifacts are identical pre/post (A filters the
   set; B changes only the param *source*; C changes only process grouping).
2. **Cache-stability:** after B, the `--dart-define` set is invariant across all launches (RED 6.1#4).
3. **Per-run isolation:** fresh per-role DB + per-scenario shared dir/topics — preserved, delivered via
   app-visible runtime config not defines.
4. **Tier honesty:** `full` (109) stays the nightly/release gate; `smoke` is routine-only (doc + test).
5. **Build from HEAD:** the one shared build is produced at sweep start from current sources (never cached
   across invocations) so Go-bridge/Dart changes aren't masked.
6. **No external-wrapper dependency for A:** tiering rides an env var through the unchanged
   `run_with_devices.sh`/`run_test_gates.sh` forwarding.

---

## 9. Test & harness-contract infrastructure

- **Dart (A, B):** pure-function unit tests (`resolveGroupMultiPartyConfig`, `buildHarnessLaunchSpec`,
  smoke-subset contract) — host-runnable, no device, injected maps. These are the real TDD core.
- **Shell (A, C):** new isolated contract tests under `scripts/test/` using the dry-run/`--list` plan output
  (deterministic, no sims) — assert plan composition (smoke vs full; 1 row vs 109). No build/sim executed.
- **Live gates (cannot be host-faked):** Phase 0 timing probe (B precondition); one `--scenario all` sweep
  confirming 1 build + verdict parity (B+C acceptance). These run on the 3-4 iPhone sim pool.

---

## 10. Risk & rollout

| Risk | Mitigation |
|------|-----------|
| Host `Process.environment` does not reach simulator app | **Phase 0 app-visibility gate** before B; use #154-style file-backed manifest / explicit install-stage-launch ordering instead of host env if refuted. |
| Flutter does NOT reuse build on runtime-config-only change | **Phase 0 timing gate** before B; fall back to per-scenario reuse (~357→110) if refuted. |
| Hidden `const`-context use of `_scenario` et al. | `const`→`final` flip makes `flutter analyze` fail at any such site — fix before GREEN (compiler is the audit). |
| Cross-scenario state bleed if shared dir/runId stabilized | Keep per-scenario shared subdir + per-role DB name; B passes them via runtime config, not defines (no cache impact). |
| Smoke tier mistaken for full coverage | §4.1.3 coverage test + loud docs; `full` stays the release gate. |
| Lost per-item PASS/FAIL when collapsing to one process (C) | Reconstruct from per-scenario verdict files + summary; keep `--only` single-scenario path. |
| `MKNOON_RELAY_ADDRESSES` define varying | It is constant per sweep → cache-stable; leave as the lone define. |

**Rollout:** ship **A** immediately (routine 24h→minutes). Run **Phase 0**; on pass, land **B** then **C**
(full nightly 357 builds→1). Each slice reverts independently. After B, apply the same `const→final`
pattern to `group_lifecycle_simulator_harness.dart:32` (`GROUP_SIM_SCENARIO`, 4 builds→1) as a trivial
follow-on (tracked, not in this plan's gates).

---

## 11. Effort

| Slice | Scope | Effort | Migration |
|-------|-------|--------|-----------|
| A (L6) | smoke list + orchestrator case + shell tier + 3 tests | **S-M** ~1 day | none |
| 0 | 2-scenario timing probe (throwaway prototype + measure) | **S** ~0.5 day | none |
| B (L1+L1b) | extract config+launch-spec, flip 9 const→final, orchestrator env passing, single runId, 3 tests + live verify | **L** ~2-3 days | none |
| C (L12) | shell single-row expansion + orchestrator continue-on-failure + summary + 2 tests + live verify | **M** ~1-1.5 days | none |

**Total ~4.5-6 days.** Outcome: routine runs in minutes (A); full nightly sweep's ~357 builds → 1 (B+C).

---

## 12. Deferred / open questions

- **OQ-CACHE (Phase 0):** does this toolchain reuse the iOS build on runtime-config-only change? Gate for B.
- **OQ-SMOKE:** freeze the exact smoke id set against failure history before merging A.
- **DEFER — group_lifecycle 4→1 / benchmark harness:** same const→final pattern; trivial follow-on of B.
- **DEFER — parallel role launches (L3), item parallelism (L7), sharding (L8), settle-wait trims (L4),
  non-multiparty build dedup (L9/L10/L11):** separate plans; several depend on B landing first.
- **OQ-RELAY:** B/C keep prod relay; a dedicated/local relay (audit L5) is a separate wall-clock lever.

---

### Provenance
5-agent read-only suite audit (build-model / runner-orchestration / non-multiparty-builds /
network-time-sinks / parallelism-tiering) + targeted anchor verification, 2026-06-18, branch
`124-harness-refactor`. All anchors working-tree-verified. Companion to
`124-integration-harness-refactor-tdd-plan.md` and `intro-e2e-build-reuse-tdd-plan.md` (same
runtime-parameterization pattern). One audit correction folded in: `E2E_SHARED_DIR` is itself a
compile-time `const String.fromEnvironment` (harness:77-80), so B must change the *source* to
a runtime config loader, not merely how it is passed. PLAN ONLY — nothing implemented.
