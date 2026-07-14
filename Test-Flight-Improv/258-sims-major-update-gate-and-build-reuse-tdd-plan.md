# 258 - `$sims` major-update regression gate, truthful verdicts, build reuse, and resource-aware concurrency  (Modification)

Status: **awaiting-review**
Spec: free-text intent (no formal spec): make `$sims` the pre-major-update critical-feature gate, remove duplicate/inert rows, automate available Android proof legs, reuse compatible builds, and support checkpointed fix-as-you-go without weakening final release evidence.
Date: 2026-07-14

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-14 | Evidence Collector — orchestration/build | `$sims` adapters; `run_{test_gates,reliability_simulations,host_test_gates}.sh`; discovery; group runtime config; APK caches | Current `$sims all` is a 69-row reliability subset, not a release gate. Group iOS already has partial build collapse; generalize rather than replace it. | derive RED contracts |
| 2026-07-14 | Evidence Collector — scenario audit | four placeholders, voice smoke, proof wrappers, 1:1 and notification runners, Android capture precedents | Three Android campaigns survive; artifact wrappers are capture-owned support; voice is recorder-only; print-only runners cannot pass. New VC-00/VC-02 supersedes Plan 188's decision to abandon DCUtR. | freeze dispositions |
| 2026-07-14 | Evidence Collector — plan/index | `00-INDEX.md`, predecessor reliability build-collapse plan, current contract tests | Allocate Plan 258. Preserve predecessor tier/runtime work, supersede its release-gate and cross-run-cache limits. | emit new plan |
| 2026-07-14 | Planner / Reviewer (sufficiency) | this plan + bundled `$tdd-plan` tier matrix/checklist | 27 spec cases, 35 matrix rows, zero empty tier/mutation/gate/registration cells; device closure is availability-bounded. | hand off to execution |
| 2026-07-14 | Concurrency follow-up | both `$sims` adapters, reliability runner, host batch gate, performance lane, Plan 258 | Add `--simultaneous` now with fail-closed resource classification; preserve this baseline while the major manifest grows the scheduler to all lanes. | add scheduler RED contracts |

## Execution Progress

| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (`git status --short`) | | | scope confirmed | |
| 2026-07-14 | simultaneous scheduling baseline | `run_reliability_simulations.sh`; both `$sims` helpers/docs; `sims_simultaneous_contract_test.sh` | `bash scripts/test/sims_simultaneous_contract_test.sh` | host bounded; performance/device/build exclusive; one current read-only validator in deferred pool | preserve and generalize through manifest |
| | RED tests added | | exact focused commands below | RED for expected reasons | |
| | gate/manifest implementation | | | scoped files only | |
| | build cache/runtime dispatch | | | one build per compatible profile | |
| | Android/proof cleanup | | | selected = attempted = terminal verdicts | |
| | direct GREEN | | exact focused commands below | all causal tests green | |
| | infrastructure-wave GREEN | | `host-all` once | no preservation regression | |
| | live major run | | `$sims major` report | all mandatory rows pass; policy N/A only | |
| | QA (independent) | | rerun commands/report audit | blocking: none/list | verdict |

## Source Of Truth

- Intent: this plan's `Exact Problem Statement` and 27 `TC-258-*` cases.
- Gate definitions: `scripts/run_test_gates.sh`; script behavior wins over prose.
- Sims manifest (new): `tool/sims/critical_features.json`; every executable row is compiled from it.
- Compatibility discovery: `scripts/check_reliability_simulation_discovery.sh`; after Plan 258 it validates/exports the manifest, but no longer invents release coverage from filename heuristics.
- Existing predecessor: `Test-Flight-Improv/reliability-suite-tiering-and-build-collapse-tdd-plan.md`.
- Reopened DCUtR owner: `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md:34-70` and `VC-02-dcutr-default-on-upgrade-tdd-plan.md:352-357`.
- Voice/video implementation boundary: the complete `Voice-Video-Call-1to1-Feature` is plan-only and not implemented as of 2026-07-14. Its Plan-258 capability records are inactive future contracts and do not participate in or block the current `$sims major` gate.
- Device policy and TDD cadence: `AGENTS.md`.
- Numbering/index: `Test-Flight-Improv/00-INDEX.md`.

## Session Classification

**Implementation-ready.** No product decision or schema migration is required. Live device closure is bounded by the targets discovered when the gate executes; missing credentials, permissions, drivers, or artifacts are blockers, not hardware `N/A`.

## Exact Problem Statement

The current `$sims all` name overstates its coverage. It selects only discovery records in the `1to1`, `group`, `intro`, and `move-feature` categories whose kind is `runner` or `test` (`scripts/run_reliability_simulations.sh:133-142`). Its current dry run has 69 rows: 42 direct `flutter test` processes, 24 Dart runners, and 3 shell runners. In contrast, the working tree contains 1,184 host Dart test files, 141 Go test files, 20 host performance files, native Android/iOS tests, a nested Dart package, and 54 explicitly ignored discovery records. `run_test_gates.sh reliability-sim` only delegates to that subset (`scripts/run_test_gates.sh:1163-1167`); `run_test_gates.sh all` is a separate curated gate and includes neither reliability-sim nor full host-all (`:1176-1187`). A green `$sims all` therefore is not evidence that all current critical features survived a major update.

The existing plan also contains dishonest or wasteful rows. The outer loop labels every zero exit PASS without checking whether anything ran (`scripts/run_reliability_simulations.sh:714-725`). Four placeholder proof files skip without a define and fail deliberately when enabled because no rig driver exists. `run_1to1_device_real.dart` prints recipes and exits zero (`:144-180`); `run_notification_tap_device_real.dart` instead exits 78 blocked (`:131-155`). Four scheduled Flutter files merely validate artifacts. Each top-level integration file is launched in a separate `flutter test` process (`run_reliability_simulations.sh:612-623`), and changing per-scenario dart-defines creates avoidable build-key churn.

What must improve: `$sims` must expose explicit `smoke`, `full`, and `major` modes; no-argument `$sims` must select `major` so the safe meaning is the default. `major` must compile one deduplicated, machine-readable plan covering every registered critical feature across analyzer, host Dart, full Go, native Android/iOS, nested packages, reliability/device proofs, post-capture validators, and critical performance. Mandatory skips, print-only success, zero attempted checks, missing artifacts, and blocked required lanes must prevent release green. It must build once per compatible profile, persist a current-source-attested cache, and optionally support a fix/rerun/resume loop followed by one clean full major run. Its `--simultaneous` scheduler must overlap only rows with compatible declared resources, preserve dependency order, and produce the same terminal verdict set as serial execution.

What must stay unchanged: the current group smoke subset, runtime-config channel, single aggregate multi-party row, exact `--only` scenario selection, and nonzero aggregate failure behavior remain locked. Host tests still use exact paths. Shared devices, shared build/profile writers, relay-mutating campaigns, unknown resource declarations, and performance measurements remain exclusive. Product assertions, transport semantics, and feature flags do not change merely to make the gate green.

This gate materially reduces regression risk; it cannot prove the absence of every bug. Its honest guarantee is: every critical surface registered in the manifest ran at its required real boundary, or was recorded `N/A` only because that target capability was unavailable under project policy, and no mandatory result was skipped or blocked.

## Root Cause (verify -> refute confirmed)

### Confirmed

- **Coverage is fragmented.** Reliability, host-all, curated gates, full Go, native tests, package tests, and performance are separate commands; no current umbrella composes them without duplication.
- **Verdicts are exit-code-only.** The reliability loop maps any zero exit to PASS (`run_reliability_simulations.sh:720-725`), so a skipped test or print-only catalog can false-green.
- **Discovery is not a critical-feature registry.** It scans selected filename locations and explicitly ignores many rows; `all` means all selected discovery rows, not all critical code.
- **Device builds are process/file shaped.** Forty-two direct device files each become their own `flutter test`. `flutter test --help` exposes no prebuilt-app option; `flutter drive --help` supports `--use-application-binary`, so real reuse requires a shared app harness/runtime dispatcher or explicit install/launch control.
- **Existing caches are not uniformly source-attested.** The reaction capture cache verifies revision/profile/artifact hashes (`capture_1to1_reaction_head_provenance.dart:591-627`), but its dirty working-tree identity is only `HEAD+working-tree` (`:719-729`), so a second edit at the same HEAD can reuse stale APKs (`:802-853`).
- **The skill adapter is iOS-biased.** It chooses booted iPhone simulators before Android (`.claude/skills/sims/scripts/run_with_devices.sh:229-245`) and requires two/four iPhone simulators (`:283-304`), contrary to the current physical-Android + Android-emulator default for non-iOS behavior.

### Refuted / do not re-introduce

- **“No build reuse exists.”** Refuted: group multi-party iOS already stages Documents JSON runtime config and builds once (`run_group_multi_party_device_real.dart:367-427`); the iOS notification smoke has `--skip-build`; reaction capture has an APK cache. Plan 258 generalizes and attests these seams.
- **“Every one of the 69 rows is duplicate.”** Refuted: the runner already suppresses literal direct targets and repeated paths (`run_reliability_simulations.sh:149-197`). Capability-level runner-vs-runner duplicates and artifact-only rows remain.
- **“Every Flutter invocation is a full clean rebuild.”** Refuted as unproven. Independent processes/install opportunities and compile-define churn are proven; Flutter may reuse intermediates. Acceptance therefore asserts deterministic build counts, not a speculative clean-build count or wall-clock threshold.
- **“All suspect rows false-green.”** Refuted: notification-tap exits 78 and artifact wrappers fail closed when artifacts are absent. They are still invalid default-plan rows because they block without performing their owning capture.
- **“One universal binary can cover the entire gate.”** Refuted: platform, architecture, app ID, signing/provider config, permissions, mode/flavor, and compile-time flags create legitimate profiles. The invariant is one build per compatible profile.
- **“Delete DCUtR because Plan 188 closed it forever.”** Refuted by the accepted 2026-07-13 VC roadmap, which explicitly reverses Path 3 and reopens CV-11/12/13/30. Delete the inert placeholder executable from today's default plan, but preserve an activation-gated VC-02 capability owned by its real Android runner.
- **“The voice file proves voice-message E2E.”** Refuted: it proves only native record -> stop -> file/duration (`voice_message_e2e_test.dart:27-68`). Full send/receive/playback remains a distinct media journey.
- **“No Android notification automation exists.”** Refuted: the intro/reaction runners already automate build/install, `am kill`, UIAutomator notification selection/tap, relay/provider capture, and artifact validation. Reuse that infrastructure.

## Real Scope

### In scope

1. A repo-owned typed sims manifest, planner, verdict model, device resolver, build-profile cache, checkpoint/resume state, report verifier, and `smoke|full|major` CLI.
2. A deduplicated `major` composition: analyzer delta, Dart-only host-all batch, full Go modules once, Android/iOS native tests, nested package tests, cleaned reliability/device rows, capture-owned proof validation, and critical performance.
3. A central `prepare-builds` phase and immutable content-addressed artifacts; child runners consume artifact paths and runtime configs.
4. Replacement/removal/reclassification of the specific inert, print-only, blocked, and artifact-only rows listed below.
5. Automated Android campaigns on explicitly discovered targets, with iOS used only for iOS-specific boundaries.
6. Optional `--fix-as-you-go`, stable-ID `--only`, `--resume`, and final-clean-run enforcement.
7. Updating both repo-owned Claude adapter docs/scripts and the installed Codex `$sims` adapter so they delegate to the same repo CLI. The repo CLI remains the behavior source of truth.
8. A bounded `--simultaneous` scheduler driven by manifest resource locks and dependencies. It may overlap host/process lanes and device campaigns only when targets, build writers, relay state, artifacts, and performance isolation do not conflict; missing metadata is exclusive/failing, never optimistically parallel.
9. Gate docs/index updates and contract tests.

### Out of scope

- Implementing any `Voice-Video-Call-1to1-Feature` product behavior, including VC-01/VC-02 transport changes; Plan 258 only preserves inactive future proof-registration contracts.
- Adding product behavior merely because a critical feature lacks tests. Such a gap is a failing manifest row and gets its own TDD plan.
- Provisioning APNs/FCM/relay credentials or unavailable hardware.
- Unbounded parallelism, overlapping work on the same target/build writer/relay mutation, timing-wait reduction, or performance-budget retuning beyond build reuse and existing critical thresholds.
- Fixing unrelated analyzer debt. `major` fails on new issues against a pinned baseline; reducing the baseline is separate work.
- Automatically editing production code unless the user explicitly invokes `$sims ... --fix-as-you-go` in a later execution turn.

## Scenario Disposition And Deduplication

| Current path/capability | Plan 258 disposition | Why / non-duplicate boundary |
|---|---|---|
| `connectivity_restore_inbox_drain_proof_test.dart` | Delete placeholder after adding `android.connectivity_restore_inbox_drain`; fuse execution with `fdc04_network_change_rewarm`. | One foreground ADB Wi-Fi off/on cycle can prove both, but must retain distinct drain/no-resume and rewarm assertions. |
| `keepalive_drop_skip_direct_proof_test.dart` | Delete placeholder after adding `android.keepalive_drop_skip_direct`. | Host tests prove predicate/latch; real Go/relay timing and no-dial wire evidence are distinct. |
| `wake_token_distribution_proof_test.dart` | Delete placeholder after extending/extracting the existing Android capture into `android.wake_token_directionality`. | Existing marker proves storage occurred, not `A-registered == B-stored == B-attached`; artifact stores SHA-256 values only, never tokens. |
| `dcutr_upgrade_proof_test.dart` | Remove inert executable from current default plan. Register activation-gated `vc02.dcutr_upgrade` and `vc02.dcutr_symmetric_cgnat_negative` under VC-02's real runner. | New VC roadmap reopens it. Positive upgrade + transport badge share one campaign; symmetric-CGNAT is topology-specific `N/A` only when unavailable. |
| `voice_message_e2e_test.dart` | Replace with runtime scenario `android.voice_recorder_native_smoke`; pregrant/restore `RECORD_AUDIO`; permission/plugin absence fails. Rename honestly. | Native recorder boundary is not duplicate of synthetic voice send or full two-peer playback. |
| TC-A6/B11/B12 proof wrappers | Consolidate shared validation under `integration_test/proof_bindings/notification_tap_proof_binding_test.dart`, classify `support`, invoke once from the owning capture. Delete the three default rows. | TC-B12 tables duplicate the runner; A6/B11 remain distinct assertions but need no device build for validation. |
| intro proof wrapper | Move/reuse validation under `integration_test/proof_bindings/intro_accept_notification_proof_binding_test.dart`, invoked by `run_intro_accept_notification_android.dart`; remove its default row. | Capture runner already performs the real Android kill/tap/route journey. |
| `validate_group_reaction_notification_artifacts.dart` | Classify `support`; invoke only from its capture owner. | Pure artifact validation is not a default device scenario. |
| `run_1to1_device_real.dart` | Convert to a truthful capability dispatcher/facade: selected IDs delegate to real owning campaigns or return typed BLOCKED/N/A; zero after printing is forbidden. | Catalog and execution reconciliation become machine-checked. |
| `run_notification_tap_device_real.dart` | Implement Android A6/B11/B12/cold-kill automation by reusing existing FCM/ADB/UIAutomator infrastructure; keep APNs/NSE receiver as a separate iOS-specific lane. | `am kill` preserves notification eligibility; `am force-stop` is forbidden for the push/tap leg. |
| LAN direct, early mDNS, warm-local, online-direct badge, LAN media | One LAN campaign/build with separate assertion IDs. | Not semantically duplicate. Physical Android + emulator cannot honestly prove same-LAN/mDNS; current topology is N/A until a second suitable physical Android exists. |
| `run_media_delivery_ui_smoke.dart` and `run_media_stable_id_smoke.dart` targeting the same test | One executable capability row unless their distinct boundary IDs justify separate runtime assertions in a shared invocation. | Confirmed runner-vs-runner duplicate missed by path extraction. |

## Target Architecture

### Modes and families

| Invocation | Contract |
|---|---|
| `$sims` / `$sims major` | Safe default and pre-major-update gate: every mandatory critical capability across all tiers. Release-green eligible. |
| `$sims full` | Every cleaned executable reliability/device scenario. Not release-green by itself. |
| `$sims smoke` | Fast curated routine subset with at least one representative per risk class. Not release-green. |
| `--family 1to1|group|intro|move-feature|media|notifications|transport` | Orthogonal filter for diagnosis; cannot produce a major release-green verdict. |
| `--simultaneous` | Use the manifest scheduler's bounded concurrency. It changes timing only, never selected coverage, requiredness, dependency order, or verdict rules. |

The CLI source is `./scripts/run_test_gates.sh sims <mode> ...`; `reliability-sim` remains a compatibility alias to the reliability family/full mode until callers migrate.

### Critical-feature manifest

`tool/sims/critical_features.json` records, for every top-level `lib/features/*` module and selected critical `lib/core/*` boundary:

- stable capability ID and feature owner;
- proof boundary (host/native/relay/device/performance) and distinct assertion IDs;
- mode/family membership and requiredness;
- exact command or aggregate runner/scenario ID;
- build-profile ID, capture/artifact dependencies, resource locks (read/write/exclusive), target capabilities, concurrency class, and allowed N/A reason;
- expected terminal verdict schema and artifact validator.

A contract test scans top-level feature modules. A new module or default-enabled critical flag without a manifest owner is a hard RED. Explicit noncritical/support classification requires a rationale; it cannot silently inherit PASS from host-all.

### Resource-aware scheduler

The planner emits a deterministic dependency DAG. Each row declares the
resources it reads or writes; the executor may run two ready rows together only
when every lock is compatible and the global cap has room. Required resource
classes are:

- `host.cpu` with bounded capacity for ordinary analyzer/Dart/Go/package/native
  host work; the existing exact-path Flutter host batch remains one plan node
  with its own internal concurrency;
- `build:<profile>` as a single-writer lock, so one profile is prepared once and
  every consumer waits for that attested artifact;
- `device:<explicit-id>` and `device-control:<explicit-id>` as exclusive locks;
  distinct Android and iOS targets may overlap only when no other lock conflicts;
- `relay-mutation:<namespace>` and capture-owned artifact writers as exclusive,
  with validator read dependencies after the matching capture;
- `performance.global` as an exclusive barrier: no host, build, device, or relay
  neighbor runs during a critical measurement;
- `unknown` as global-exclusive and plan-invalid for `major` until classified.

Default `--simultaneous` limits are four ordinary host/process workers and the
available set of disjoint targets. `SIMS_HOST_CONCURRENCY` and
`SIMS_MAX_PARALLEL` may lower or bound those pools but cannot override a lock.
Serial and simultaneous runs must have identical selected IDs and final typed
verdicts; reports additionally record start/end times, dependency waits, lock
assignments, and maximum observed concurrency. On failure, already-running
independent work is collected, no dependent work starts, fail-fast stops new
dispatch, and `--continue-on-failure` remains diagnostic/non-release-green.

The already-green adapter baseline in
`scripts/test/sims_simultaneous_contract_test.sh` is a preservation sentinel:
broad host Dart uses bounded batching, performance is exclusive, all current
device/build-sharing reliability rows serialize, and the one explicitly
allowlisted read-only validator is deferred until producers finish. Plan 258
replaces that path allowlist with the manifest locks above rather than growing
another shell-side source of truth.

### Build profiles and cache

| Profile | Artifact / use | Expected reuse |
|---|---|---|
| `host.flutter_tester` | no app artifact; exact host paths batched | one Flutter host invocation per compatible batch |
| `android.e2e.standard` | fat/universal debug APK + universal runtime dispatcher | physical Android + compatible emulator; connectivity, keepalive, recorder, ordinary 1:1/group journeys |
| `android.production_fcm` | provider-configured normal/E2E APK pair | notification/push phases in one session |
| `android.e2e.wake_token` | emission-enabled APK (`MKNOON_EMIT_WAKE_TOKEN=true`) | wake directionality only; explicit compile-time exception |
| `ios.simulator.e2e` | `Runner.app` built once, `simctl install` + staged runtime config | all compatible iOS-simulator scenarios |
| `ios.device.production` | signed/provider-attested IPA | physical APNs/NSE/OS-only scenarios |
| declared exception | PiP/native source set, distinct app ID/permission/flavor/mode/ABI/feature-default | exactly one separately named profile; never a hidden child rebuild |

`prepare-builds` hashes actual current bytes, including relevant tracked modifications and untracked app inputs—not only HEAD. The fingerprint includes source/dependency closure (conservatively all `lib`, selected `integration_test`, nested package, assets and native inputs), entrypoint, platform/architecture, mode/flavor, sorted compile defines, app ID, provider/signing **hashes only**, `pubspec.lock`, Gradle/CocoaPods/Xcode/Flutter/Dart versions, and build options. Runtime scenario/role/run ID/DB/config JSON is excluded by design. Metadata stores input digest, artifact digest, profile, command, and redacted toolchain data.

Corrupt, unattested, wrong-profile, or wrong-source artifacts miss/fail closed. Reinstalling/resetting the same artifact is allowed and is not a build. Child runners receive `SIMS_ARTIFACT_<PROFILE>` paths and may not invoke `flutter build`, Gradle, or Xcode unless their manifest row declares an exception.

### Runtime dispatch and reset

Generalize the proven group Documents-file channel. Every launch stages a nonce-bound JSON config, launches the installed artifact, and requires the app to acknowledge the same profile/scenario/role/run nonce before actions begin. Missing, stale, corrupt, or wrong-profile config fails; there is no release-mode fallback scenario.

The scenario contract restores process/app data, identities, permissions, notification shade/channels, network state, logs, and temporary artifacts as applicable. A full reinstall of the same cached APK/app is acceptable when data reset is safer; rebuilding is not. Every network mutation has `finally` restoration and a postcondition.

### Verdict and fix-as-you-go state machine

Terminal results are typed: `PASS`, `FAIL`, `BLOCKED`, `SKIP`, `N/A`. Only `PASS`, plus policy-valid `N/A` for a genuinely unavailable target capability, can satisfy a mandatory major row. A mandatory skip, zero attempted assertions, print-only runner, missing artifact, missing credential/permission, exit 78, selected-target loss, or unregistered critical feature makes major non-green.

```text
freeze manifest/source/device/build digests
  -> run stable IDs fail-fast
  -> failure checkpoint + classification (product/test/harness/environment/flake)
  -> optional user-authorized fix
  -> Graphify affected + focused causal tests
  -> --only <stable-id>
  -> --resume after that ID
  -> mandatory clean full `$sims major` on current digests
```

The checkpoint persists stable ID, manifest/source digests, exact redacted command/env, target assignments/state, build profile/artifact hashes, logs, failure class, last passed IDs, and next ID. A manifest/source/artifact mismatch invalidates the applicable checkpoint/cache. `--continue-on-failure` is diagnostic and always release-non-green. Passing retry/resume evidence never replaces the final clean full run.

## Files To Inspect / Change During Execution

Production gate/orchestrator:

- `tool/sims/{sims.dart,manifest.dart,planner.dart,scheduler.dart,verdict.dart,build_cache.dart,checkpoint.dart,device_matrix.dart,report.dart}` (new)
- `tool/sims/critical_features.json` and analyzer baseline (new)
- `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, `scripts/run_reliability_simulations.sh`, `scripts/check_reliability_simulation_discovery.sh`
- `.claude/skills/sims/{SKILL.md,scripts/run_with_devices.sh}` and installed Codex adapter sync

Device/proof:

- `integration_test/scripts/run_1to1_device_real.dart`
- `integration_test/scripts/run_notification_tap_device_real.dart`
- existing Android intro/reaction capture helpers; extract shared ADB/build/runtime seams rather than copy them
- `integration_test/proof_bindings/` (new capture-owned bindings)
- the four manual placeholders, voice file, and four artifact-validator rows named above

Tests/docs:

- ten new Dart contract/criteria files and four new shell contracts named below
- existing group build-collapse/sweep contracts
- `Test-Flight-Improv/{test-gate-definitions.md,_current-test-map.md,00-INDEX.md}`

## Existing Tests Covering This Area

- `scripts/test/reliability_group_tier_contract_test.sh` locks smoke/full selection, aggregate single-row execution, and exact scenario selection.
- `test/integration/group_multi_party_{runtime_config,launch_spec,sweep_continue,smoke_tier}_test.dart` lock runtime config, stable defines, single sweep run ID, and aggregate failure behavior.
- `scripts/test/host_test_gate_batch_contract_test.sh` locks exact-path host batching and the current eight Go tails.
- `scripts/test/sims_simultaneous_contract_test.sh` locks the current fail-closed `--simultaneous` baseline: bounded host batching, performance isolation, serialized shared device/build rows, and deferred read-only validation.
- `scripts/test/group_reaction_notification_device_contract_test.sh` is the fail-closed device-runner precedent.
- `test/core/services/{p2p_service_impl,connectivity_signal}_test.dart` provide the connectivity host floor.
- `send_chat_message_use_case_test.dart`, `active_peer_keepalive_use_case_test.dart`, and `p2p_service_peer_liveness_test.dart` provide the keepalive host floor.
- Plan-188 Go tracer guards remain preservation coverage; VC-02 owns their future polarity/real device activation.
- Current gap: no suite-wide manifest/verdict/cache/checkpoint/resource-DAG contract, no default shell-contract lane, and no major umbrella. The current shell scheduler intentionally knows only the conservative adapter baseline.

## RED Test Catalog  (add before implementation — INV-RED-FIRST)

1. `test/tool/sims/sims_manifest_test.dart` (4 tests; TC-01/02/03/21/22/26)
   - `no-argument mode is major and smoke/full cannot claim release green`
   - `every critical feature and core boundary has one complete manifest owner`
   - `capability IDs are unique and duplicate commands or boundaries are rejected`
   - `major composition contains analyzer host Go native package reliability and performance exactly once`
   - RED on HEAD: no manifest/major mode exists. GREEN: typed complete deduplicated plan. Mutations: remove a module/lane, duplicate the host Go tail, or let an adapter bypass the repo CLI.

2. `test/tool/sims/sims_verdict_test.dart` (4 tests; TC-04/05/23/24)
   - `mandatory skip blocked zero-attempt print-only and missing artifact never pass`
   - `N/A requires an unavailable live target capability`
   - `aggregate selected attempted and terminal IDs reconcile exactly`
   - `diagnostic continuation and partial retry cannot produce release green`
   - RED on HEAD: verdict is only process exit code. Mutation: map SKIP/0-attempt/exit-78 to PASS or omit a selected terminal ID.

3. `test/tool/sims/sims_build_cache_test.dart` (4 tests; TC-07/08/10/24)
   - `compatible rows request and build one profile once`
   - `runtime config changes hit while source/native/asset/lock/toolchain/profile mutations miss`
   - `corrupt or unattested artifact fails closed`
   - `build report records hits misses hashes invalidations and declared exceptions without secrets`
   - RED on HEAD: no central cache; dirty cache key can remain `HEAD+working-tree`. Mutation: omit any fingerprint input, accept wrong hash, or allow an undeclared child build.

4. `test/tool/sims/sims_runtime_dispatch_test.dart` (3 tests; TC-09)
   - `one installed artifact acknowledges two nonce-bound scenarios without rebuilding`
   - `missing stale corrupt or wrong-profile config cannot fall back to another scenario`
   - `scenario reset restores process data identity permission notification and network state`
   - RED on HEAD: most harnesses use compile defines/direct tests; group legacy defaults can select `gm001`. Mutation: remove nonce/profile check or one reset postcondition.

5. `test/tool/sims/sims_checkpoint_test.dart` (3 tests; TC-11/12)
   - `failure checkpoint persists stable ID digests command targets artifacts and classification`
   - `only retry then resume skips prior passes but still requires final clean major`
   - `manifest source or artifact mismatch invalidates resume`
   - RED on HEAD: only order-dependent `--start-at N`/`--only N` exists and no checkpoint is persisted.

6. `test/tool/sims/sims_device_matrix_test.dart` (3 tests; TC-13)
   - `non-iOS two-peer work prefers physical Android plus Android emulator and pins IDs`
   - `iOS is selected only for an iOS boundary or explicit parity claim`
   - `only target unavailability becomes N/A; credentials permissions artifacts and device loss do not`
   - RED on HEAD: helper prefers iPhone simulators and requires them for multi-device suites.

7. `test/tool/sims/sims_scheduler_test.dart` (5 tests; TC-27)
   - `missing or unknown resource metadata is exclusive and invalid for major`
   - `shared target build writer relay mutation and performance locks never overlap`
   - `ready rows with disjoint host and explicit-device resources overlap within the cap`
   - `capture validators wait for their artifact and independent validators may overlap`
   - `serial and simultaneous execution reconcile the same IDs verdicts and failures`
   - RED for major on HEAD: only the conservative shell allowlist exists; there is no manifest DAG or typed resource lock model. Mutations: remove one lock, start a dependent validator early, exceed the cap, or drop a parallel failure.

8. `test/tool/sims/sims_proof_binding_registry_test.dart` (3 tests; TC-06/17/19)
   - `proof bindings are support owned by captures and absent from default executable plan`
   - `inert placeholder files and print-only catalog success are forbidden`
   - `VC-02 DCUtR capability remains activation-gated after placeholder removal`
   - RED on HEAD: the wrappers/placeholders/catalog are scheduled today.

9. `test/integration/android_1to1_reliability_device_criteria_test.dart` (6 tests; TC-14/15/16/18/19)
   - connectivity artifact requires 3-message drain, network-change markers, no resume, and rewarm;
   - keepalive artifact requires drop/skip, no discover/dial/error, bounded custody, recovery delivery, re-arm;
   - wake artifact requires three equal SHA-256 values and rejects raw tokens;
   - recorder artifact requires pregranted permission, real plugin, decodable nonempty M4A/duration, cleanup;
   - selected/attempted/terminal 1:1 scenario IDs are equal;
   - LAN/topology results use policy N/A without claiming the boundary.
   - RED on HEAD: no real campaign artifacts/drivers satisfy these criteria.

10. `test/integration/notification_tap_device_criteria_test.dart` (5 tests; TC-20)
   - Android A6, B11, B12 warm, B12 cold-kill each require their exact real relay/crypto/FCM/UI checks;
   - iOS receiver requires APNs/NSE/app-group checks and stays a separate platform row.
   - RED on HEAD: the runner exits blocked and the wrappers only validate external artifacts.

11. Four new process contracts under `scripts/test/` (TC-01/03/04/07/10/11/12/21/22/23/26/27):
    - `sims_major_plan_contract_test.sh`
    - `sims_verdict_process_contract_test.sh`
    - `sims_build_count_contract_test.sh`
    - `sims_checkpoint_process_contract_test.sh`
    - PATH shims inject analyzer, host Dart, Go, native, mandatory-skip, print-only, exit-78, missing-artifact, stale-cache, undeclared-build, middle-sweep, device-loss, and resource-conflict failures. Every injected break must return nonzero and a typed report; same-profile builds count 1, declared profiles each count 1, and no conflicting timestamps overlap.

## Test Coverage Matrix  (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation that re-reds | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-258-01 modes/default | CLI safety | host unit + process | `sims_manifest_test.dart::no-argument mode...`; `sims_major_plan_contract_test.sh` | no major mode | default to full/smoke or grant release green | focused Dart + `sims-contracts` | AUTO host; add shell to `SIMS_CONTRACT_TESTS` |
| TC-258-02 feature totality | codebase inventory | host unit | `sims_manifest_test.dart::every critical feature...` | manifest absent | remove module/flag owner | focused Dart | AUTO (`test/**`) |
| TC-258-03 capability dedup | composition | host unit + process | `sims_manifest_test.dart::capability IDs...`; plan contract | path-only dedup | add duplicate boundary/Go tail | focused + contracts | AUTO + shell array |
| TC-258-04 truthful verdict | orchestration | host unit + process | `sims_verdict_test.dart::mandatory skip...`; verdict process contract | zero exit = PASS | map SKIP/BLOCKED/0 attempts to PASS | focused + contracts | AUTO + shell array |
| TC-258-05 reconciliation | aggregate | host unit | `sims_verdict_test.dart::aggregate selected...` | print-only runner attempts zero | omit attempted/terminal ID | focused Dart | AUTO |
| TC-258-06 proof ownership | artifact validation | host unit | `sims_proof_binding_registry_test.dart::proof bindings...` | validators scheduled as device tests | classify binding executable/remove owner | focused Dart + discovery | AUTO; `proof_bindings` = support |
| TC-258-07 one build/profile | build orchestration | host unit + process | build-cache tests + build-count contract | no central owner | build same profile twice/merge incompatible | focused + contracts | AUTO + shell array |
| TC-258-08 cache attestation | current-source correctness | host unit | `sims_build_cache_test.dart::runtime config changes...`; corrupt artifact test | weak/fragmented cache | omit lock/native/toolchain input or accept hash mismatch | focused Dart | AUTO |
| TC-258-09 runtime isolation/reset | app harness | host integration | three `sims_runtime_dispatch_test.dart` tests | compile define/direct file path | accept stale nonce or skip reset | focused Dart | AUTO |
| TC-258-10 build authority | process boundary | shell contract | `sims_build_count_contract_test.sh::undeclared child build` | runners build internally | invoke flutter/Gradle/Xcode build in child | contracts gate | shell array |
| TC-258-11 checkpoint/resume | durability | host unit + process | checkpoint tests + process contract | only ephemeral numeric index | omit digest/stable ID or rerun prior passes | focused + contracts | AUTO + shell array |
| TC-258-12 fix-as-you-go | state transition | host unit + process | `only retry...final clean`; checkpoint contract | no enforced final clean | grant green after resume | focused + contracts | AUTO + shell array |
| TC-258-13 device policy | OS target selection | host unit | three device-matrix tests | iOS-first resolver | select iPhone for ordinary two-peer or mislabel credential N/A | focused Dart | AUTO |
| TC-258-14 connectivity | OS network + relay | host criteria | Android criteria::connectivity artifact | placeholder only | omit no-resume/drain/rewarm check | focused Dart | AUTO |
| TC-258-14 connectivity | real OS/two-peer | device-proof | `run_1to1_device_real.dart::android.connectivity_restore_inbox_drain` | no driver | remove ADB toggle or terminal artifact | `$sims major --only android.connectivity_restore_inbox_drain` | manifest + dispatcher scenario |
| TC-258-15 keepalive | logic/wire criteria | host criteria | Android criteria::keepalive artifact | placeholder only | allow dial/error/no recovery | focused Dart | AUTO |
| TC-258-15 keepalive | real bridge/relay | device-proof | dispatcher::`android.keepalive_drop_skip_direct` | no driver | remove real drop/custody/delivery leg | `$sims major --only android.keepalive_drop_skip_direct` | manifest + dispatcher scenario |
| TC-258-16 wake direction | crypto/secret-safe criteria | host criteria | Android criteria::wake hash equality | marker lacks equality | compare presence only or emit raw token | focused Dart | AUTO |
| TC-258-16 wake direction | real native/bridge/relay | device-proof | dispatcher::`android.wake_token_directionality` | no directionality driver | invert stored token or omit attached value | `$sims major --only android.wake_token_directionality` | manifest + emission profile scenario |
| TC-258-17 DCUtR disposition | future feature registration | host unit | proof registry::VC-02 activation | inert current row | delete VC capability or activate before prod flag | focused Dart | AUTO; VC-02 owner |
| TC-258-18 recorder | native-plugin criteria | host criteria | Android criteria::recorder artifact | permission early return | allow no permission/plugin/empty file | focused Dart | AUTO |
| TC-258-18 recorder | Android plugin | device-proof | dispatcher::`android.voice_recorder_native_smoke` | flag not set/current row skips | remove pregrant/decodability/cleanup | `$sims major --only android.voice_recorder_native_smoke` | manifest scenario; standard profile |
| TC-258-19 truthful 1:1 dispatcher | orchestration | host criteria | registry + Android criteria::ID equality | catalog returns zero | print only or omit terminal verdict | focused + contracts | AUTO + manifest |
| TC-258-19 executable 1:1 | mixed device boundaries | device-proof | `run_1to1_device_real.dart::<selected scenario>` | no dispatch | selected ID does not invoke owner | `$sims full --family 1to1` | manifest/owner scenarios |
| TC-258-20 notification | capture schema | host criteria | five notification criteria tests | runner blocked/wrappers only | omit FCM/crypto/tap/cold checks | focused Dart | AUTO |
| TC-258-20 notification Android | OS/provider/two-peer | device-proof | notification runner::A6/B11/B12 Android phases | no capture driver | use force-stop, omit real provider/relay, or no artifact | `$sims major --only notifications.android_payload_campaign` | manifest scenario; FCM profile |
| TC-258-20 notification iOS | APNs/NSE | device-proof | notification runner::`payload_fast_path_ios_receiver` | no capture driver | substitute Android/fake NSE | `$sims major --only notifications.ios_payload_fast_path` | manifest scenario; iOS production profile |
| TC-258-21 major lane totality | analyzer/host/Go/native/package | host/process | manifest composition + plan contract | lanes separate/omitted | omit one lane or duplicate host Go tail | `sims major --list` + contracts | manifest; shell array |
| TC-258-22 critical performance | host budget | host performance | manifest::performance membership | absent from reliability all | remove critical target | `run_host_test_gates.sh performance-host` | existing performance glob + manifest |
| TC-258-22 critical performance | runtime budget/build reuse | device performance | shared benchmark/perf runtime dispatcher | compile-define loop rebuilds | build per PERF_TARGET/BENCHMARK | `$sims major --lane performance-device` | manifest scenario; shared profile |
| TC-258-23 controlled failures | causal gate verification | process mutation | verdict/build/checkpoint shell contracts | failures can false-green | any injected failure ignored | `sims-contracts` | shell array |
| TC-258-24 reporting | auditability/privacy | host unit | build/verdict report tests | fragmented/no report | omit counts/hash/reason or leak secret | focused Dart | AUTO |
| TC-258-25 predecessor preservation | group tier/runtime/sweep | host + shell sentinel | existing four group tests + tier contract | GREEN on HEAD | re-add per-run defines/builds or lose `--only` | exact preservation command | existing AUTO + shell contract |
| TC-258-26 skill adapters | single source of truth | host/process | manifest adapter assertion + major plan contract | adapters call old subset | place gate logic in skill/bypass repo CLI | contracts gate | shell array; adapter docs |
| TC-258-27 safe simultaneous scheduling | dependency/resource equivalence | host unit + process | five `sims_scheduler_test.dart` tests + existing simultaneous shell contract + plan contract | no major manifest DAG; shell baseline is deliberately narrow | omit target/build/relay/performance lock, start validator before capture, exceed cap, or lose a failure | focused Dart + `sims-contracts` | AUTO host + current shell sentinel + shell array |

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** TC-258-11/12 persist checkpoint/build/verdict state across process restart and invalidate it when inputs change. Runtime scenario state is reconstructed from nonce-bound config, never an in-memory fallback.
- **Sibling-surface consistency:** TC-258-02/21 require every feature and every major tier; TC-258-13 applies one device policy to Claude/Codex adapters; Android/iOS notification siblings are separately locked.
- **Destructive-action side-effects:** TC-258-09 asserts scenario cleanup restores network, permissions, app/process/data and notification state while preserving immutable cached artifacts and prior evidence. Cache pruning may delete only unreferenced fingerprints; add this assertion to `sims_build_cache_test.dart` if pruning is implemented.
- **Invariant re-verification under new transitions:** TC-258-12 re-verifies all manifest/source/artifact/device invariants after a fix and again on the final clean run. Connectivity/keepalive tests assert full post-recovery state, not only the transition marker.
- **Concurrency / ordering:** TC-258-27 compares serial and simultaneous selected/attempted/terminal sets, injects conflicts at each lock class, and proves capture-before-validator and performance-barrier ordering.

## Invariants (locked by tests)

- **INV-258-1 — release honesty:** no mandatory skip, block, missing artifact, zero-attempt, print-only success, or diagnostic-only run can be release green -> TC-04/05/12/23.
- **INV-258-2 — critical totality:** every critical feature/core boundary has a manifest owner and real required tier -> TC-02/21.
- **INV-258-3 — capability dedup:** a capability/boundary executes once; distinct assertions may share one campaign/build -> TC-03.
- **INV-258-4 — current-source artifact:** reuse requires matching input and artifact digests -> TC-08.
- **INV-258-5 — one build per compatible profile:** runtime-only data never rebuilds; incompatible compile inputs never share -> TC-07/09/10.
- **INV-258-6 — exact reconciliation:** selected IDs = attempted IDs = terminal verdict IDs -> TC-05/19.
- **INV-258-7 — availability bounded:** only unavailable target capability is N/A; no missing credential/permission/driver/artifact is N/A -> TC-13.
- **INV-258-8 — secret safety:** reports store hashes/redacted identifiers, never wake/push/signing token contents -> TC-16/24.
- **INV-258-9 — final clean:** fix/retry/resume is provisional until a complete current-digest major run passes -> TC-12.
- **INV-258-10 — schedule equivalence:** simultaneous execution changes overlap only; coverage, dependency order, build count, and typed terminal verdicts equal the serial plan, while conflicting resources never overlap -> TC-27.
- **INV-RED-FIRST / INV-MUTATION-VERIFIED:** applies to every new behavior row above.

## Step-By-Step Implementation Plan

1. **Snapshot and characterize.** Record `git status --short`, current analyzer baseline, `host-all --list`, reliability `all --list`, discovery TSV, full Go/native/package inventories, and live devices. Preserve unrelated dirty files. Run existing group/host shell contracts as green sentinels.
2. **Add RED contracts first.** Add the ten Dart files (40 named tests) and four shell scripts. Confirm they fail for the catalogued missing manifest/mode/verdict/cache/driver/resource-scheduler reasons—not syntax or fixture mistakes. Mutation-run the existing group and simultaneous sentinels before changing their seams.
3. **Typed model and plan compiler.** Implement `tool/sims` manifest/parser/planner/verdict/report and add `run_test_gates.sh sims`. Add stable IDs and JSON/TSV plan output. Add `--dart-only` plan/execution support to host-all so major does not repeat its eight Go sentinels before full Go.
4. **Resource DAG and scheduler.** Replace the interim path allowlist with typed read/write/exclusive locks and dependencies from the manifest. Add bounded ready-queue dispatch, deterministic result collection, fail-fast/diagnostic semantics, timing/lock reporting, performance barriers, and serial-equivalence verification. Unknown resources fail closed.
5. **Register all contract tests.** Add one `sims-contracts` lane that runs every `scripts/test/*_test.sh`; keep Dart tests AUTO under `test/**`. Make compatibility discovery compare exactly with manifest scenarios rather than scrape runner source as authority.
6. **Central build preparation.** Implement profiles, content fingerprints, immutable cache metadata, artifact verification, build-count report, and declared exceptions. First support standard Android and iOS-simulator profiles; port existing group/APK cache users without losing their tests.
7. **Runtime dispatcher and reset.** Add nonce/profile handshake and staged runtime JSON. Migrate direct integration rows in compatible batches. Convert benchmark/performance/group lifecycle selection away from per-target compile defines. Stop-if: if a scenario truly reads a compile-time value before runtime config can load, declare a separate profile and test it; do not hide an internal rebuild.
8. **Proof-binding cleanup.** Extract shared pure validators; consolidate the two optional Flutter bindings under `integration_test/proof_bindings`, classify support, and call them post-capture on `flutter-tester`. Remove the four default artifact rows and standalone group-validator row. Verify capture artifacts still fail closed.
9. **Android campaign replacement.** Reuse/extract the existing reaction/intro ADB, APK, config, UIAutomator, logcat, and restoration utilities. Implement connectivity+rewarm, keepalive, wake-hash equality, and recorder scenarios. Delete each placeholder only after its replacement criteria test and live dispatcher row exist.
10. **Truthful 1:1/notification runners.** Replace recipe-only 1:1 paths with delegation/typed results. Implement Android A6/B11/B12 warm/cold phases; keep iOS APNs/NSE separate. Remove the DCUtR inert file while registering the inactive VC-02 capabilities; do not implement VC product changes here.
11. **Checkpoint/fix loop.** Persist stable-ID state and add `--only <id>`, `--resume`, `--fix-as-you-go` adapter workflow. On a later authorized fix: classify product/test/harness/environment/flake, run Graphify `affected` and focused causal tests, rerun the ID, resume, then run a clean full major.
12. **Compose major without duplication.** Analyzer delta -> Dart-only host-all batch -> nested package -> both full Go modules once -> Android native -> iOS native on an available simulator -> reliability/device profiles -> capture-owned validators -> critical performance. Under `--simultaneous`, the DAG overlaps only compatible ready nodes and still ends with the exclusive performance barrier. No `run_test_gates.sh all` + `host-all` double-run.
13. **Wave acceptance.** Run focused contracts and affected curated lanes during slices. Per AGENTS cadence, run full host-all once after the infrastructure wave and once as part of final rollout, not after every slice. Execute a controlled failure/resource-conflict matrix, compare serial and simultaneous plans/verdicts, then run a real availability-bounded `$sims major --simultaneous`; audit the report, locks, and build counts.
14. **Docs/adapters/graph.** Update gate definitions/current test map, both adapters, and index. Refresh Graphify once after coherent app-owned script/tool changes.

Stop-if conditions:

- A mandatory selected scenario cannot emit attempted/assertion/verdict evidence -> it is BLOCKED and the plan is replanned; never print-and-pass.
- A required available-device leg lacks credentials, permission, or a driver -> BLOCKED, not N/A.
- The same artifact cannot safely select two scenarios through an acknowledged runtime channel -> split a declared profile; do not claim reuse.
- A proposed dedup merges distinct proof boundaries -> share setup/build only; retain separate assertion IDs.
- A row lacks complete resource metadata or a dependency cycle exists -> reject the major plan; do not guess concurrency.
- An execution failure reveals product code breakage outside explicit fix-as-you-go authorization -> record checkpoint and ask for authority rather than editing it.

## Risks And Edge Cases

| Risk | Mitigation / test |
|---|---|
| Stale dirty-tree artifact reused | actual-byte input digest + artifact digest; TC-08 |
| Universal APK does not cover physical/emulator ABI | profile attestation; split ABI profiles only when required; TC-07 |
| Runtime config from prior scenario runs | invocation nonce/profile handshake; TC-09 |
| Reset makes later scenarios false-green or damages device state | per-capability reset contract and `finally` restoration; TC-09/14/15/20 |
| Capability dedup drops a unique assertion | distinct boundary/assertion IDs, selected-attempted-terminal reconciliation; TC-03/05 |
| Host-all plus full Go repeats tests | host `--dart-only` plan and capability dedup; TC-03/21 |
| Child runner silently rebuilds | PATH-shim build-count contract + declared exception list; TC-10 |
| Existing skipped probes poison major | only authoritative mandatory assertions are skip-intolerant; allowlisted non-authoritative probes cannot satisfy a capability; TC-04 |
| Two rows corrupt one device/build/relay state | typed exclusive locks + timestamp conflict audit; TC-27 |
| Validator starts before capture is durable | explicit artifact dependency edge and digest handoff; TC-27 |
| Parallel failure is lost or ordering changes verdict | deterministic collection + selected/attempted/terminal serial-equivalence test; TC-05/27 |
| Host concurrency starves or invalidates performance | bounded CPU pool; `performance.global` barrier; TC-22/27 |
| Provider/signing hashes leak secrets | record hashes/labels only; redact commands/env; TC-24 |
| Fix-as-you-go creates a patch that passes only the failed row | affected sentinels + resume + mandatory final clean major; TC-12 |
| Android emulator cannot prove LAN/mDNS | mark that capability N/A; require second suitable physical Android when available; TC-13 |
| New VC-02 plan conflicts with old Plan 188 | inactive capability points to VC-02; preserve 188 guards and remove only inert executable; TC-17 |

## Device/Relay Proof Profile

**Closure requires device proofs for available critical OS/real-stack boundaries.** At planning time, discovery found:

- physical Android Pixel 6 `21071FDF600CSC` (API 36);
- installed Android AVDs `Pixel_7` and `mknoon_play_35` (not booted in the initial `flutter devices` snapshot; the resolver may launch one, then must rediscover/pin it);
- three USB iPhones and an available booted iPhone Air simulator.

These IDs are evidence only, never hardcoded. Every run re-resolves using `flutter devices --machine`, `adb devices`, and `xcrun simctl list devices available`. Non-iOS two-peer behavior uses one physical Android plus one available Android emulator. iPhone/simulator rows are selected only for APNs/NSE, iOS lifecycle, native RunnerTests, or explicit parity.

PROD-CRITICAL legs:

- `android.connectivity_restore_inbox_drain`
- `android.keepalive_drop_skip_direct`
- `android.wake_token_directionality`
- `notifications.android_payload_campaign`
- `notifications.ios_payload_fast_path` when an iOS target is available
- the full existing group multi-party release lane

Recorder is a mandatory native-plugin smoke, while the separate two-peer media journey remains the voice-message end-to-end leg. Same-LAN/mDNS and symmetric-CGNAT are `N/A (target/topology unavailable by project policy)` when the required topology is absent; missing automation is never N/A.

## Acceptance Gates  (literal, copy/paste)

```bash
# 0) Snapshot and baselines (counts are captured because this tree is actively changing)
git status --short | tee /tmp/plan-258-dirty-tree.txt
./scripts/run_host_test_gates.sh host-all --list > /tmp/plan-258-host-before.txt
./scripts/run_test_gates.sh reliability-sim all --list > /tmp/plan-258-reliability-before.txt
./scripts/check_reliability_simulation_discovery.sh --records-tsv > /tmp/plan-258-discovery-before.tsv
flutter analyze --machine > /tmp/plan-258-analyze-before.txt || true

# 1) RED before implementation, GREEN afterward: 40/40 named Dart contract cases
flutter test \
  test/tool/sims/sims_manifest_test.dart \
  test/tool/sims/sims_verdict_test.dart \
  test/tool/sims/sims_build_cache_test.dart \
  test/tool/sims/sims_runtime_dispatch_test.dart \
  test/tool/sims/sims_checkpoint_test.dart \
  test/tool/sims/sims_device_matrix_test.dart \
  test/tool/sims/sims_scheduler_test.dart \
  test/tool/sims/sims_proof_binding_registry_test.dart \
  test/integration/android_1to1_reliability_device_criteria_test.dart \
  test/integration/notification_tap_device_criteria_test.dart
# expect after implementation: 40 passed, 0 failed, 0 skipped

# 2) Shell/process contracts: current 5 + new 4 = 9/9 scripts
./scripts/run_test_gates.sh sims-contracts
# expect: 9 contract scripts passed, 0 failed; includes the already-green
#         sims_simultaneous_contract_test.sh preservation sentinel

# 3) Preservation sentinels for inherited build collapse/tiering
flutter test \
  test/integration/group_multi_party_runtime_config_test.dart \
  test/integration/group_multi_party_launch_spec_test.dart \
  test/integration/group_multi_party_sweep_continue_test.dart \
  test/integration/group_multi_party_smoke_tier_test.dart
./scripts/test/reliability_group_tier_contract_test.sh
./scripts/test/sims_simultaneous_contract_test.sh
# expect: captured pre-edit test count all pass; shell contract PASS

# 4) Plan/discovery audit: no duplicate IDs/commands, every critical module owned
./scripts/run_test_gates.sh sims major --list --format json \
  > build/sims/major-plan.json
dart run tool/sims/sims.dart verify-plan build/sims/major-plan.json
# expect: 0 unregistered critical modules; 0 duplicate capability/boundary rows;
#         every row has lane/profile/requiredness/verdict/registration

# 5) One infrastructure-wave host sweep (Dart exact paths batched; full Go is separate)
./scripts/run_host_test_gates.sh host-all --dart-only \
  --batch-flutter --concurrency 4 --reporter failures-only
# expect: Step-0 host Dart path count + 9 new Dart files; all authoritative tests pass

(cd packages/background_push_crypto && flutter test && dart analyze)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)
(cd android && ./gradlew testDebugUnitTest)
IOS_SIM_ID="$(dart run tool/sims/sims.dart devices --first ios-simulator)"
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination "platform=iOS Simulator,id=$IOS_SIM_ID" \
  CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests
# expect: every discovered package/native/Go test passes; only explicitly
# non-authoritative, allowlisted probes may skip and cannot satisfy a capability

# 6) Controlled failure matrix (all injected breaks must be caught, then removed)
./scripts/run_test_gates.sh sims-contracts --mutation-matrix
# expect: analyzer, Dart, Go, mandatory-skip, print-only, exit-78,
# missing-artifact, stale-cache, undeclared-build, mid-sweep, device-loss,
# resource-conflict/dependency-order = 12/12 caught

# 7) Availability-bounded build preflight and dry run
./scripts/run_test_gates.sh sims major --prepare-builds --list
# expect: actual build count == unique compatible selected profiles;
# second identical invocation reports 0 builds and all profile cache hits

./scripts/run_test_gates.sh sims major --list --format json \
  > build/sims/major-serial-plan.json
./scripts/run_test_gates.sh sims major --simultaneous --list --format json \
  > build/sims/major-simultaneous-plan.json
dart run tool/sims/sims.dart verify-schedule-equivalence \
  build/sims/major-serial-plan.json build/sims/major-simultaneous-plan.json
# expect: identical selected IDs/dependencies/build profiles; no conflicting locks overlap

# 8) Optional repair loop (only when explicitly requested by the user)
"${CODEX_HOME:-$HOME/.codex}/skills/sims/scripts/run_with_devices.sh" \
  major --fix-as-you-go

# 9) Mandatory final clean run; retry/resume output alone cannot close
"${CODEX_HOME:-$HOME/.codex}/skills/sims/scripts/run_with_devices.sh" \
  major --simultaneous
dart run tool/sims/sims.dart verify-report build/sims/latest/report.json \
  --require-mode major --require-clean-full-run
# expect: planned == attempted == terminal; all mandatory = PASS or policy-valid N/A;
#         0 FAIL, 0 BLOCKED, 0 mandatory SKIP, 0 zero-attempt, 0 undeclared builds

# 10) Hygiene
flutter analyze --machine > /tmp/plan-258-analyze-after.txt || true
dart run tool/sims/sims.dart verify-analyzer-delta \
  /tmp/plan-258-analyze-before.txt /tmp/plan-258-analyze-after.txt
./scripts/run_test_gates.sh completeness-check
git diff --check
# expect: 0 new analyzer issues; completeness and diff checks pass
```

## Known-Failure Interpretation

- **Expected RED:** the 40 new Dart cases and four new shell contracts before their owning implementation; each must fail for the catalogued missing behavior. The separate current `sims_simultaneous_contract_test.sh` is already GREEN and remains a preservation sentinel.
- **Pre-existing dirty tree:** the Step-0 snapshot is authoritative. Do not revert, absorb, or reformat unrelated work.
- **Policy N/A:** only an unavailable target/topology/version capability. It remains visible in the report and does not count as PASS.
- **Environment/configuration blocker:** available target but missing credentials, permissions, relay/provider config, driver, or artifact -> `BLOCKED`, major non-green.
- **Product/test/harness failure:** classified in the checkpoint; fix only under explicit fix-as-you-go authority, without weakening assertions.
- **Suspected flake:** must reproduce or pass a bounded retry policy recorded in the report; a retry does not erase the initial result and final clean major remains required.
- **Scope drift:** production feature changes, VC-01/VC-02 implementation, or unrelated analyzer cleanup are blocking and require a separate plan/authority.

## Done Criteria

- [ ] All 27 spec cases have the named 35 matrix rows; zero empty tier/mutation/gate/registration cells.
- [ ] All new behavior tests were RED for the expected reason before implementation and mutation-verified afterward.
- [ ] `$sims` defaults to `major`; `smoke` and `full` are explicit and cannot claim release green.
- [ ] Critical-feature manifest owns every current feature/core critical boundary and rejects unregistered additions.
- [ ] Major plan is capability-deduplicated and does not run host Go sentinels plus full Go twice.
- [ ] Typed verdict rejects mandatory skip/block/zero-attempt/print-only/missing-artifact states.
- [ ] Build cache is current-source/content-attested; one actual build per selected compatible profile; no undeclared child builds.
- [ ] Runtime nonce/profile handshake and reset contracts pass across two scenarios using one artifact.
- [ ] `--simultaneous` is serial-equivalent, overlaps only compatible ready rows, never overlaps shared target/build/relay/performance locks, and records dependency/lock timing evidence.
- [ ] Artifact validators are capture-owned support and absent from the default device plan.
- [ ] Connectivity, keepalive, wake, recorder, and Android notification replacements are live-proven on available explicit Android IDs before their inert rows are deleted.
- [ ] VC-02 DCUtR capabilities remain activation-gated; no future requirement is silently discarded.
- [ ] Fix-as-you-go checkpoint/only/resume works, and a separate final clean `$sims major` report is green.
- [ ] Existing group tier/runtime/build-collapse/sweep sentinels remain green.
- [ ] Full Go/native/nested-package/host/performance lanes are represented once and pass at final closure.
- [ ] Analyzer delta has 0 new issues; completeness and `git diff --check` pass; docs/adapters agree with repo CLI.

## Scope Guard (hard “Do not”)

- Do not claim `$sims full` or a family-filtered run is a major release gate.
- Do not turn a mandatory skip, print-only zero, exit 78, missing artifact, permission, credential, or driver into PASS/N/A.
- Do not choose an iPhone merely as the second peer for non-iOS behavior when the Android pair is available.
- Do not hardcode unavailable hardware/version requirements; use project-policy N/A only for actual target absence.
- Do not cache by HEAD or `HEAD+working-tree` alone, and do not record secret contents in cache/report metadata.
- Do not permit child runners to build without a declared profile exception.
- Do not mark a row parallel-safe from its filename or optimistic inference; incomplete/unknown resource metadata is exclusive and major-invalid.
- Do not merge distinct assertions merely because they share setup/build; dedup the campaign, preserve assertion IDs.
- Do not delete the reopened VC-02 DCUtR requirement or alter VC-01/VC-02 product code in this plan.
- Do not weaken product assertions to achieve build reuse or green status.
- Do not run full host-all after every slice; follow the wave/final cadence in `AGENTS.md`.
- Do not edit production code during a later failure unless fix-as-you-go was explicitly requested for that run.

## Accepted Differences / Intentionally Out Of Scope

- One build means one artifact per compatible profile, not one universal Android/iOS binary.
- Reinstalling the same attested artifact and resetting app/device state may still occur; the optimization targets builds, not every launch/install.
- Wall-clock improvement is reported but is not the acceptance oracle; deterministic build counts and coverage/verdict equality are.
- `--simultaneous` does not mean every test runs together. On a one-pair live device matrix, most device campaigns remain serial; immediate savings come primarily from bounded host work, disjoint platform targets, and post-capture validation.
- A test suite cannot guarantee no unknown bug exists. Plan 258 guarantees total execution of the registered critical contract and prevents silent omissions.
- Current same-LAN/mDNS and symmetric-CGNAT proof can be N/A when the topology is absent. Their host/native guards remain mandatory.
- The complete `Voice-Video-Call-1to1-Feature`, including VC-01/VC-02, is not implemented. Its capabilities stay inactive and outside the current major gate until the owning production behavior lands; activation then makes the corresponding real-device rows mandatory through manifest totality.
- Existing analyzer debt is baseline-tracked; no new issue is allowed, but wholesale cleanup is separate.

## Dependency Impact

- Future critical features and default-enabled flags must add manifest ownership before major can green.
- VC-01/VC-02 consume the activation-gated DCUtR capability IDs and real Android dispatcher rather than the inert proof file.
- Notification Plans 225/252/256/257 retain their evidence schemas but move scheduling/validation under capture owners.
- The old reliability tier/build-collapse plan remains historical evidence for group multi-party; Plan 258 supersedes its claim that that sweep alone is the release gate and its “never cache across invocations” policy.
- `$sims` Claude/Codex adapters depend only on the repo CLI, preventing future behavioral drift between skills.

## Reviewer Findings

Sufficiency self-check: **YES on all blocking gates.** Every TC-258 case has a named test at the lowest tier that can fail for the real reason; OS/real-relay/real-crypto rows also have device closure. All behavior-bearing edits name a re-red mutation. Commands are literal. Every new Dart/shell/device/proof row states registration. No schema migration exists. The PROD-CRITICAL real-stack legs are named. Preservation sentinels and dirty-tree capture are explicit. Verify->refute findings—including existing partial build reuse and the VC-02 reversal—are recorded. Blind spots cover lifecycle, sibling surfaces, destructive reset/cleanup, and post-fix invariant re-verification.

Residual execution risk: live provider/relay credentials and topology can block device rows; the verdict model deliberately reports those as blocking rather than manufacturing green evidence. Build-profile splits may expand after empirical ABI/signing checks, but each split is declared and contract-counted.

## Arbiter Decision

Structural blockers: **none**. Deferred details: exact live target IDs, profile fingerprints, and dynamic baseline counts are captured at execution start. Accepted differences: per-profile rather than universal build reuse; availability-policy N/A for genuinely absent topology; analyzer delta rather than debt eradication. **Plan is implementation-ready after user review.**

## Final Execution Verdict

Verdict: pending | Files changed: plan/index only in this turn | Tests run: read-only discovery/dry-run/device inventory; no implementation tests | Blocking: implementation not started | QA verdict: plan structurally sufficient | Non-blocking follow-up owner: Plan 258 executor
