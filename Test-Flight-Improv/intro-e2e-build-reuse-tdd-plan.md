# Intro E2E Harness — Single-Build Reuse (Option 3 + 2) — TDD Plan

**Date:** 2026-06-18
**Branch target:** `124-harness-refactor` (companion to `124-integration-harness-refactor-tdd-plan.md`)
**Scope:** reliability-sim plan **item #154** = `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` (the intro/friends E2E harness, 11 scenarios on 3–4 iOS simulators).
**Status:** PLAN ONLY — analysis complete, implementation deferred. **No tests run, no code changed.**
**Method:** 4-agent read-only adversarial verification workflow + 2 source-grounding探 passes; all file:line anchors working-tree-verified on this branch.

> **Prime directive for the whole rollout:** the 11 intro scenarios stay green at every step.
> The invariant for every phase is: **`INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` passes
> before AND after the change** (same per-scenario verdicts), and each phase is independently
> shippable and reversible. The build-count reduction must never weaken per-scenario isolation.

This plan extends the `124` build-reduction program to the **shell** intro harness that 124 does
**not** touch. 124 collapsed `integration_test/*.dart` app builds; `smoke_test_friends.sh` is a
separate `xcrun simctl`-driven harness with its own `reset_simulators.sh` that rebuilds **per device,
per scenario**. The same proven idea — *one build, parameterized at runtime instead of compile time* —
applies here.

---

## 0. What actually ships

| # | Change | Slice | Migration | Builds (all-run) |
|---|--------|-------|-----------|-------------------|
| Opt 2 | Move `AUTO_SETUP_USERNAME` compile-time → runtime (file in app Documents); one universal binary | **S1** (Dart) + **S2** (shell) | none | enables 1-binary |
| Opt 3 | Per-scenario reset reuses the prebuilt app (uninstall+install, **no rebuild**); hoist build to run start | **S3** (shell) | none | **34 → 1** |
| sibling | `run_ios_notification_tap_ui_smoke.sh` migrate off the compile-time define | **S4** | none | (separate harness) |

**Landing order:** S1 → S2 → S3 → S4. S1 is the pure-Dart TDD floor and is independently useful
(keeps a `String.fromEnvironment` fallback, so nothing breaks before the shell changes land).
S2 cannot land before S1 (the app must read the runtime username). S3 builds on S2.

**Headline:** an `INTRO_E2E_SCENARIO=all` run goes from **34** `flutter build ios --simulator`
invocations to **1**, with per-scenario identity/relay isolation preserved.

---

## 1. Problem statement

`prepare_devices` (smoke_test_friends.sh:798-826) / `prepare_four_devices` (:828-861) run
`./reset_simulators.sh` (:805 / :835) at the **start of every one of the 11 scenarios**
(dispatch `case all)` at :1938-1951). `reset_simulators.sh` builds the app **once per device**
in a sequential loop (reset_simulators.sh:90-101, build at :36-39):

```
flutter build ios --simulator --no-pub \
  --dart-define=AUTO_SETUP_USERNAME=$name \   # a | b | c | d   ← ONLY per-build difference
  --dart-define=E2E_TEST_MODE=true \          # constant
  --dart-define=DISABLE_LOCAL_DISCOVERY=true  # constant
```

**Verified build math:** 10 three-device scenarios × 3 + 1 four-device scenario × 4 = **34 builds**.
All 34 are **semantically identical except the baked username** → only **4 distinct binaries**, so
~30 builds are pure redundant compile/link/codesign work. Because the username is a `--dart-define`,
each value change invalidates Flutter's incremental Dart-kernel cache and re-runs App.framework
relink + codesign + asset embed every time (verification workflow, dimension `build-redundancy`,
all claims CONFIRMED).

`AUTO_SETUP_USERNAME` (main.dart:1749) has **exactly 4 references, all in one block**
(main.dart:1749-1777). It is used only to (a) gate the auto-setup block and (b) stamp
`IdentityModel.username` on the generated identity (main.dart:1769) + a debug log (:1777). It drives
**no compile-time branching** → the same binary is valid for a/b/c/d (dimension
`username-runtime-feasibility`, CONFIRMED). `E2E_TEST_MODE` / `DISABLE_LOCAL_DISCOVERY`
(e2e_test_mode.dart:1-5) **are** real compile-time gates and must stay as dart-defines.

---

## 2. Goals / Non-goals

**Goals**
- Cut the intro-suite app builds **34 → 1** per `all` run with **zero scenario-coverage loss** and
  **identical per-scenario isolation**.
- Move the username to a runtime channel that mirrors the harness's existing Documents-file pattern.
- Keep every phase independently shippable; keep a `String.fromEnvironment` fallback during migration.

**Non-goals (this round)**
- Parallelizing builds/resets (verification Option 4): once builds = 1 there is nothing to parallelize;
  parallel `flutter build` into the shared `build/ios/iphonesimulator/Runner.app` output is unsafe.
  **DEFER.**
- Trimming `sleep`/poll-cycle waits (verification Option 5): small, flakiness-prone, orthogonal to
  build reuse. **DEFER** — track separately.
- Touching the `integration_test/*.dart` build counts — owned by plan **124**.

---

## 3. Corrected source anchors (working-tree-verified)

**`reset_simulators.sh`** (103 lines)
- `flutter_build_for_name` :29-58 (the sole `flutter build` site, :36-39) — per-name dart-define at :37.
- Step 1 uninstall loop :60-65 (:63 `simctl uninstall`); Step 2 boot :67-75; notification pre-grant :77-83.
- Step 3 per-device loop :90-101 — `flutter_build_for_name` :94, `simctl install build/ios/iphonesimulator/Runner.app` :96, re-grant :97, `simctl launch` :98. `INTRO_E2E_DEVICE_SET` 3-vs-4 select :9-24.

**`smoke_test_friends.sh`** (1992 lines)
- `prepare_devices` :798-826 (`./reset_simulators.sh` :805; `read_export` per device :808-810; peer-id/username derivation :812-817). `prepare_four_devices` :828-861 (:835 reset with `INTRO_E2E_DEVICE_SET=four`).
- `get_docs_dir` :19-54 — `xcrun simctl get_app_container "$1" "$BUNDLE_ID" data` :48, returns `…/Documents` :53.
- `write_config` :116-129 (terminates app before staging a file, :122). `read_export` :78-96 (240s deadline waits for `intro_e2e_identity.json`). `relaunch_devices` :156-164. Dispatch `case` :1938-1990 (per-scenario selectors `happy|refresh|…|folded-duplicate`).
- Constants: `EXPORT_FILE=intro_e2e_identity.json` :9, `CONFIG_FILE=intro_e2e_config.json` :10, `RESULT_FILE=intro_e2e_result.json` :11, `BUNDLE_ID=com.mknoon.app` :8.

**`lib/main.dart`**
- `final appDocDir = await getApplicationDocumentsDirectory();` :385 (1364 lines **before** auto-setup — in scope, and `getApplicationDocumentsDirectory` creates the dir if missing).
- `wipeKeychainOnce(appDocDir.path)` :392 (debug one-shot keychain wipe; see §6).
- Auto-setup block :1748-1802 — `const autoSetupUsername = String.fromEnvironment('AUTO_SETUP_USERNAME')` :1749; gate `.isNotEmpty` :1750; `generateNewIdentity(...)` :1753-1757; `repository.saveIdentity(IdentityModel(... username: autoSetupUsername ...))` :1761-1775; `exportIdentityForIntroE2E(...)` :1792-1795.

**Helpers to inject (already closure-driven, testable)**
- `generate_identity_use_case.dart` — `enum GenerateIdentityResult` :6, `generateNewIdentity({callGenerate, callMlKemKeygen, repo, onProgress})` :25.
- `build_qr_payload_use_case.dart` — `enum BuildQRPayloadResult` :10, `buildQRPayload({...}) → (BuildQRPayloadResult, String?)` :26.
- `intro_e2e_runner.dart` — `exportIdentityForIntroE2E({signedQrPayloadJson, mlKemPublicKey})` :39-52; file idiom `_loadConfig` :317-322 / `_configFile` :331-338 / `_deleteConfigIfPresent` :324-328; file constants :30-32.
- `e2e_test_mode.dart` :1-5 (`kE2ETestMode` / `kDisableLocalDiscovery` declaration pattern).
- `dev_keychain_wipe.dart` :21-58 (marker `.dev_keychain_wiped` in Documents).

**Sibling consumer**
- `scripts/run_ios_notification_tap_ui_smoke.sh:512` also passes `--dart-define=AUTO_SETUP_USERNAME=TapSmoke` (S4).

**Test surfaces**
- Use-case test idiom: `test/features/identity/application/generate_identity_use_case_test.dart` (fake repo + injected bridge closures, no path_provider, no real bridge).
- path_provider mock idiom: `test/features/home/presentation/screens/first_time_experience_wired_test.dart:118-128` (`setMockMethodCallHandler` on `plugins.flutter.io/path_provider`).
- Per-test temp-file isolation w/ **sync** teardown: `test/flutter_test_config.dart:43-71` (cf. [[feedback_testwidgets_sync_io_only]]).
- **No existing precedent** for shell/harness tests that stub `flutter`/`xcrun` or count builds (verification confirmed) → S2/S3 introduce new, isolated harness-contract-test scaffolding under `scripts/test/`.

---

## 4. Design — runtime username channel + first-launch ordering

**Channel (decided):** a per-device JSON file `auto_setup.json` in the app Documents container,
written by the harness via the existing `get_app_container … data` path it already uses for
`intro_e2e_config.json`. Shape:

```json
{ "username": "a" }
```

**Why this channel** (verification, `username-runtime-feasibility`):
- It mirrors the harness's existing Documents-file mechanism — zero new transport.
- `appDocDir` is resolved at main.dart:385, long before auto-setup at :1749, so the file is readable
  synchronously in `main()` **before** P2P node init (which is mandatory — peerId derives from the
  identity keys, so the identity must exist before the node starts).
- **Rejected alternatives:** `simctl launch` argv (REFUTED — Flutter doesn't surface argv to Dart
  without native Runner changes); `SIMCTL_CHILD_*` env (REFUTED — `String.fromEnvironment` can't read
  process env; would need `Platform.environment`); routing through `intro_e2e_runner` (REFUTED —
  **timing blocker:** the runner starts *after* node init, intro_e2e_runner.dart:241 / waits for
  transport readiness :100 — far too late to create the identity).

**First-launch ordering** — two viable flows; plan adopts **Flow B as default**, **Flow A as the
optimization (OQ-ORDER):**
- **Flow A (1 launch):** install shared app → host `mkdir -p "$container/Documents"` + write
  `auto_setup.json` → launch (identity generated, export written). Depends on the data container
  being host-writable immediately post-install.
- **Flow B (2 launches, guaranteed):** install → launch-once (app creates Documents at main.dart:385;
  with no `auto_setup.json`, `performAutoSetup` returns `skippedNoUsername` → **no identity yet**) →
  write `auto_setup.json` → relaunch (identity generated, export written). This uses only the
  app-creates-Documents guarantee and the existing terminate/relaunch idiom (smoke_test_friends.sh:122/156-164).

Either way: **`read_export` (prepare_devices :808-810) must run after the launch that follows
staging** — the export `intro_e2e_identity.json` only appears once the username is present.

---

## 5. Slices

### S1 — Dart: runtime username + extracted auto-setup use case *(no migration; the TDD floor)*

Pure-Dart, host-testable, independently shippable. Keeps `String.fromEnvironment` as a fallback so
the current compile-time harness (and S4's tap-smoke) keep working until the shell slices land.

#### 5.1 RED — write these first

New `test/core/debug/auto_setup_config_test.dart` (**file does not exist yet**) — uses a real temp
dir (`Directory.systemTemp`, per the repo's file-IO test idiom):
1. `resolveAutoSetupUsername(dir)` returns `"a"` when `dir/auto_setup.json` = `{"username":"a"}`.
2. returns the `String.fromEnvironment('AUTO_SETUP_USERNAME')` fallback (here `''` in a host test)
   when the file is **absent** — precedence is *file wins, else env, else empty*.
3. returns `null`/empty (and does **not throw**) when the file is malformed JSON or missing the
   `username` key — `main()` must never crash on a bad fixture.
4. trims/treats whitespace-only `username` as empty.

New `test/features/identity/application/auto_setup_use_case_test.dart` (**file does not exist yet**) —
mirror `generate_identity_use_case_test.dart` (fake `IdentityRepository`, injected `callGenerate` /
`callMlKemKeygen` / `callSign` / `exportQr` closures; no path_provider, no real bridge):
5. `username == ''` → `AutoSetupResult.skippedNoUsername`; **no** generate, **no** save, **no** export.
6. `repo.loadIdentity()` already non-null → `AutoSetupResult.alreadyExists`; **no** generate (locks
   main.dart:1751-1752 semantics).
7. fresh + generate success → `repo.saveIdentity` called once with `identity.username == username`,
   `exportQr` called exactly once → `AutoSetupResult.success`.
8. generate fails (`GenerateIdentityResult.coreLibError`/`dbError`) → `AutoSetupResult.generateFailed`;
   no save, no export.
9. QR build fails → identity still saved, `exportQr` **not** called, returns `success` (preserve the
   current silent-skip-export behavior at main.dart:1790).

#### 5.2 GREEN — implementation (sketch; do not implement now)

- New **`lib/core/debug/auto_setup_config.dart`** (mirrors intro_e2e_runner.dart:317-338 + e2e_test_mode pattern):
  ```dart
  const _kAutoSetupFile = 'auto_setup.json';
  /// File wins; falls back to the compile-time define; else null.
  Future<String?> resolveAutoSetupUsername(String docDirPath) async {
    try {
      final f = File('$docDirPath/$_kAutoSetupFile');
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString());
        final u = (m is Map ? m['username'] : null);
        if (u is String && u.trim().isNotEmpty) return u.trim();
      }
    } catch (_) {/* malformed fixture must not crash main() */}
    const envU = String.fromEnvironment('AUTO_SETUP_USERNAME');
    return envU.isNotEmpty ? envU : null;
  }
  ```
- New **`lib/features/identity/application/auto_setup_use_case.dart`** — `enum AutoSetupResult { success, alreadyExists, skippedNoUsername, generateFailed }` + `Future<AutoSetupResult> performAutoSetup({required String username, required IdentityRepository repo, required Future<...> Function() callGenerate, callMlKemKeygen, callSign, required Future<void> Function(String qrJson, String? mlKemPk) exportQr})`. Body lifted **verbatim** from main.dart:1750-1801 (behavior-preserving), parameterized by injected closures.
- Rewrite **main.dart:1748-1802** to:
  ```dart
  final autoSetupUsername = await resolveAutoSetupUsername(appDocDir.path);
  if (autoSetupUsername != null) {
    await performAutoSetup(
      username: autoSetupUsername, repo: repository,
      callGenerate: () => callIdentityGenerate(bridge),
      callMlKemKeygen: () => callMlKemKeygen(bridge),
      callSign: (d, k) => callSignPayload(bridge: bridge, dataToSign: d, privateKey: k),
      exportQr: (qr, pk) => exportIdentityForIntroE2E(signedQrPayloadJson: qr, mlKemPublicKey: pk),
    );
  }
  ```
  `appDocDir` is already in scope from :385.

#### 5.3 Invariants / notes
- **Behavior parity:** with no `auto_setup.json` and the define still set, S1 is byte-equivalent to
  today (env fallback) — so S1 ships safely *before* any shell change.
- **No new compile-time surface:** the only new compile read is the same `String.fromEnvironment`
  fallback inside `resolveAutoSetupUsername`.

#### 5.4 Gates
`flutter analyze` 0 new · `test/core/debug/auto_setup_config_test.dart` + `test/features/identity/application/auto_setup_use_case_test.dart` green · `generate_identity_use_case_test.dart` stays green (use-case extraction must not change its contract).

---

### S2 — Shell: `reset_simulators.sh` builds **once** + stages the runtime username *(depends on S1)*

Removes the per-device dart-define; builds **one** universal `Runner.app` and stages `auto_setup.json`
per device. This alone cuts the per-`reset` builds from 3–4 → **1** (so the `all` run drops 34 → 11);
S3 takes it to 1.

#### 5.1 RED — harness contract test (new scaffolding)

New `scripts/test/reset_simulators_contract_test.sh` (**new infra; no precedent — isolated bash test**):
- Put **fake `flutter` and `xcrun`** first on `PATH` (stub bins that append their argv to a log file
  and exit 0; fake `xcrun simctl get_app_container … data` echoes a per-device temp dir; fake
  `flutter build` `touch`es a `build/ios/iphonesimulator/Runner.app` marker).
- Run `reset_simulators.sh` with stub `DEVICE_A/B/C`.
- **Assert (RED today):** `grep -c 'build ios' flutter.log == 1` (today = 3) · each device's
  `Documents/auto_setup.json` contains the correct `{"username":"<a|b|c>"}` (today = absent) ·
  `simctl install` is called once per device with the **same** `Runner.app` path · `auto_setup.json`
  is written **before** that device's `simctl launch`.

#### 5.2 GREEN — implementation (sketch)
- `flutter_build_for_name` → `flutter_build_intro_e2e` (no `AUTO_SETUP_USERNAME` define; keep
  `E2E_TEST_MODE=true` + `DISABLE_LOCAL_DISCOVERY=true`); call it **once** before the device loop.
- Per-device loop: `simctl uninstall` → `simctl install <shared Runner.app>` → resolve
  `container=$(xcrun simctl get_app_container "$dev" "$BUNDLE_ID" data)` → `mkdir -p
  "$container/Documents"` → write `auto_setup.json` (`{"username":"${NAMES[$i]}"}`) → grant
  notifications → `simctl launch` (Flow A). If OQ-ORDER lands on Flow B, launch-once before staging.
- `reset_simulators.sh` keeps owning uninstall/boot/grant (its existing Steps 1-2).

#### 5.3 Gates
`bash -n reset_simulators.sh` clean · `scripts/test/reset_simulators_contract_test.sh` green · a live
single-scenario run (`INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`) passes with **1** build.

---

### S3 — Shell: hoist the build out of per-scenario reset (Option 3 final mile) *(depends on S2)*

Split "build the shared app" (once per `all` run) from "reset device state" (once per scenario,
**no rebuild**). This is where 11 → **1**.

#### 5.1 RED — full-suite contract test (new observable seam)

Add a minimal **`INTRO_E2E_DRY_RUN=1`** mode to `smoke_test_friends.sh` that emits a structured
op-log (`BUILD`, `RESET <dev>`, `PHASE <stepId>`) and exits without invoking simulators — this is the
testable seam (and doubles as documentation).

New `scripts/test/intro_e2e_build_count_contract_test.sh`:
- **Assert (RED today):** `INTRO_E2E_SCENARIO=all INTRO_E2E_DRY_RUN=1 ./smoke_test_friends.sh`
  emits exactly **one** `BUILD` op (today: one per scenario = 11) and a `RESET` op per device per
  scenario, and **zero** `flutter build` reachable from any per-scenario `prepare_*` path.

#### 5.2 GREEN — implementation (sketch)
- New `build_intro_e2e_app()` (the S2 build step) called **once** at the top of every dispatch arm
  (`case all)` and each single-scenario arm) *before* the first scenario.
- `reset_simulators.sh` gains a **reset-only mode** (default) that does uninstall + install-of-prebuilt
  + stage `auto_setup.json` + grant + launch, with **no `flutter build`**; a `--build` flag (or a
  sibling `build_intro_e2e_app.sh`) does the one-time build. `prepare_devices` / `prepare_four_devices`
  call **reset-only**.
- The prebuilt `Runner.app` path is the same artifact for all devices and all 11 scenarios.

#### 5.3 Invariants (the correctness floor — see §6)
- **Per-scenario container wipe MUST remain.** Reset-only still does `simctl uninstall` + `install`
  (or a data-container wipe) so each scenario gets a **fresh identity / fresh peerId** and a clean
  Documents (stale `intro_e2e_config.json` / `intro_e2e_result.json` gone). Skipping the wipe to save
  time would cause peerId reuse → identity + relay-inbox bleed across scenarios (verification:
  `refactor-options-and-risk`, correctness claims CONFIRMED).
- **No rebuild ≠ no reinstall.** Reinstalling the prebuilt app is cheap (copy + register, no compile);
  it is what re-arms the keychain wipe and resets the data container.

#### 5.4 Gates
`bash -n` clean · both contract tests green · **the real `INTRO_E2E_SCENARIO=all
./smoke_test_friends.sh` passes end-to-end with exactly 1 build and identical per-scenario verdicts
vs the pre-change baseline.**

---

### S4 — Sibling: `run_ios_notification_tap_ui_smoke.sh` off the compile-time define *(optional, low value)*

`scripts/run_ios_notification_tap_ui_smoke.sh:512` bakes `--dart-define=AUTO_SETUP_USERNAME=TapSmoke`.
S1's env fallback keeps it working unchanged, so S4 is **optional**. If pursued: have it install the
same universal build and stage `auto_setup.json` with `{"username":"TapSmoke"}` (mirrors S2).
**Recommend DEFER** unless that harness is also rebuild-bound — out of the #154 critical path.

---

## 6. Cross-cutting invariants (must hold across all slices)

1. **Per-scenario identity freshness.** Each scenario regenerates fresh peerIds/ML-KEM keys — preserved
   only by the per-scenario container wipe (uninstall+install of the prebuilt app). `prepare_devices`
   already re-reads exports each scenario (:808-817), so fresh peer IDs flow through naturally.
2. **Relay isolation by fresh peers.** Relay inbox is keyed by peerId; fresh per-scenario peers mean a
   prior scenario's envelopes are addressed to defunct peers and cannot bleed in. Holds **only** with
   invariant 1 — never reuse a container across scenarios.
3. **Keychain reset depends on the Documents wipe.** Identity secrets + the DB-encryption key live in
   the iOS **Keychain** (identity_repository_impl.dart:10-12,134-147), which the simulator does **not**
   reliably clear on uninstall. The debug build's one-shot `wipeKeychainOnce(appDocDir.path)`
   (main.dart:392), gated by `.dev_keychain_wiped` in Documents (dev_keychain_wipe.dart:21-58),
   re-arms whenever Documents is cleared — so an uninstall+install (or data-container wipe) yields a
   truly fresh identity **without** a rebuild. A pure relaunch is insufficient (marker + keychain
   survive). ⚠ If a non-debug build (no wipe) is ever used, only uninstall is robust.
4. **Build from HEAD at run start.** The single shared artifact is built once per run from current
   sources — never cached across script invocations — so a fresh Go-bridge/Dart change can't be masked.
5. **Compile-time gates unchanged.** `E2E_TEST_MODE` + `DISABLE_LOCAL_DISCOVERY` stay dart-defines on
   the shared build; only `AUTO_SETUP_USERNAME` moves to runtime.
6. **Fallback parity.** With the file absent, `resolveAutoSetupUsername` returns the env value — so any
   not-yet-migrated caller keeps working.

---

## 7. Test & harness-contract-test infrastructure

- **Dart (S1):** standard host unit tests (fake repo + injected closures + temp-dir file IO). Fully
  covered by existing idioms; no device needed.
- **Shell (S2/S3):** **new** isolated contract tests under `scripts/test/` using PATH-shim fakes for
  `flutter`/`xcrun` (no precedent in-repo — this is net-new scaffolding, called out explicitly). They
  assert *invocation shape* (build count, install-of-prebuilt, username-file staging order), **not**
  app behavior. The `INTRO_E2E_DRY_RUN` op-log is the deterministic seam for the build-count assertion.
- **Live verification (mandatory before close):** one real `INTRO_E2E_SCENARIO=all
  ./smoke_test_friends.sh` on the 3+1 booted iPhone sims (DEVICE_A/B/C/D), confirming all 11 scenarios
  pass with **1** build and identical verdicts. This cannot be host-faked — it is the acceptance gate.

---

## 8. Risk & rollout

| Risk | Mitigation |
|------|-----------|
| Container not host-writable pre-launch (Flow A) | Default to **Flow B** (launch-once → stage → relaunch); Flow A is an OQ-gated optimization. |
| Per-scenario isolation silently weakened | Invariants 1–3; S3 contract test asserts a `RESET <dev>` (uninstall+install) per scenario; live `all` run must match baseline verdicts. |
| Stale keychain identity if a non-debug build is used | Invariant 3; keep uninstall in reset-only mode (don't rely solely on the debug marker wipe). |
| `read_export` 240s timeout if export never written (username not staged before launch) | Stage `auto_setup.json` before the identity-producing launch; contract test asserts staging precedes launch. |
| Sibling tap-smoke harness breaks | S1 env fallback keeps it green; S4 optional. |

**Rollout:** S1 (Dart, ship alone) → S2 (single build + staging) → S3 (hoist, 34→1) → S4 (optional).
Each phase reversible; revert any slice without disturbing earlier ones.

---

## 9. Effort

| Slice | Scope | Effort | Migration |
|-------|-------|--------|-----------|
| S1 | extract `performAutoSetup` + `resolveAutoSetupUsername`; rewrite main.dart block; 2 new unit tests | **S** ~0.5–1 day | none |
| S2 | `reset_simulators.sh` single build + username staging; 1 contract test | **M** ~0.5–1 day | none |
| S3 | build/reset split + `INTRO_E2E_DRY_RUN` seam + hoist; 1 contract test; live `all` verify | **M** ~1 day | none |
| S4 | tap-smoke migration (optional) | **S** ~0.25 day | none |

**Total ~2–3 days** (S4 excluded). Net: **34 → 1** intro-suite builds per `all` run.

---

## 10. Deferred / Open questions

- **OQ-ORDER:** verify on first device run whether `simctl get_app_container … data` + `mkdir -p
  Documents` is host-writable immediately post-install (enables Flow A, 1 launch) or whether Flow B
  (2 launches) is required. Default to Flow B until confirmed.
- **OQ-CLEANUP:** optionally delete `auto_setup.json` after consumption (mirror
  `_deleteConfigIfPresent` intro_e2e_runner.dart:324-328). Not required — the per-scenario container
  wipe removes it anyway and the existing-identity branch skips regeneration.
- **DEFER — Option 4 (parallelize):** moot once builds = 1; parallel `flutter build` into the shared
  output dir is unsafe. Parallelizing the per-scenario `simctl` reinstall/relaunch across distinct
  UDIDs is safe but a small, separate win.
- **DEFER — Option 5 (sleeps/poll tuning):** the dominant non-build cost is the per-phase
  terminate+relaunch+poll cycle (poll_cycles up to 90 @ 500ms = app-behavior timing, not gratuitous
  script sleep). Tune cautiously and separately; keep out of the build-reuse change.
- **DEFER — S4** unless the tap-smoke harness is itself rebuild-bound.

---

### Provenance
4-agent read-only adversarial verification workflow (build-redundancy / username-runtime-feasibility /
reset-isolation-semantics / refactor-options-and-risk) + 2 source-grounding探 passes, 2026-06-18,
branch `124-harness-refactor`. All anchors working-tree-verified. Companion to
`124-integration-harness-refactor-tdd-plan.md` (which owns `integration_test/*.dart` build counts;
this plan owns the `smoke_test_friends.sh` / `reset_simulators.sh` intro shell harness — reliability-sim
plan item #154). PLAN ONLY — nothing implemented.
