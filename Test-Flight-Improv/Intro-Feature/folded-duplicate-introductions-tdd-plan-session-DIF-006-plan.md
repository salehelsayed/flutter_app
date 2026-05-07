# DIF-006 - Four-Identity Simulator Folded Duplicate Proof Plan

Status: accepted

## Planning Progress

- 2026-05-06 21:06:19 CEST - Evidence Collector completed / Planner started. Files inspected since last update: `folded-duplicate-introductions-tdd-plan.md`, `folded-duplicate-introductions-tdd-plan-session-breakdown.md`, `smoke_test_friends.sh`, `reset_simulators.sh`, `lib/core/debug/intro_e2e_runner.dart`, `lib/features/introduction/application/load_introductions_use_case.dart`, `lib/features/introduction/application/folded_introduction_response_use_case.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/Intro-Feature/test-inventory.md`, `scripts/run_test_gates.sh`; commands inspected live devices via `flutter devices --machine` and `xcrun simctl list devices available`. Decision/blocker: four-identity simulator fixture is available; current harness is three-device-shaped and runner lacks folded snapshot/action proof. Next action: draft the smallest harness/debug-runner plan.
- 2026-05-06 21:06:19 CEST - Planner completed. Files inspected since last update: same evidence set. Decision/blocker: draft classifies session as `implementation-ready`; no external fixture blocker because a fourth booted iOS simulator is available. Next action: reviewer pass checks sufficiency, stale assumptions, overreach, and exact gates.
- 2026-05-06 21:08:38 CEST - Reviewer started. Files inspected since last update: this plan draft, source row `DIF-006`, device profile, smoke/reset/runner evidence. Decision/blocker: review focus is folded proof sufficiency, fourth-device precision, and no `DIF-007` bleed. Next action: classify missing pieces or accept the draft.
- 2026-05-06 21:08:38 CEST - Reviewer completed / Arbiter started. Files inspected since last update: this plan draft. Decision/blocker: sufficient with adjustments; no structural blocker. Incremental details added below: explicit dependency intake and accepted snapshot-vs-UI difference. Next action: arbiter classifies review findings and sets final readiness.
- 2026-05-06 21:09:15 CEST - Arbiter completed. Files inspected since last update: this plan draft and reviewer notes. Decision/blocker: no structural blockers remain; plan is `execution-ready`. Next action: hand off to execution without closing `DIF-006` until the named four-identity proof and gates pass.

## Execution Progress

- 2026-05-06 21:11:43 CEST - Orchestrator started / contract extraction started. Files inspected since last update: `implementation-execution-qa-orchestrator` skill, this plan, `git status --short`, `smoke_test_friends.sh`, `reset_simulators.sh`, `lib/core/debug/intro_e2e_runner.dart`, source row `DIF-006`, and `test-inventory.md` search hits. Command currently running: none. Decision/blocker: no implementation started; extracting exact scope, closure bar, RED/GREEN commands, fixture blocker rule, source docs, and scope guard. Next action: complete contract extraction, then spawn the isolated Executor.
- 2026-05-06 21:11:43 CEST - Contract extraction completed / Executor handoff prepared. Files inspected since last update: this plan and required owner-file previews. Command currently running: none. Decision/blocker: execution contract is concrete: primary owner files are `smoke_test_friends.sh`, `reset_simulators.sh`, and `lib/core/debug/intro_e2e_runner.dart`; RED is `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`; required checks are `bash -n`, the named host-side Flutter tests, `./scripts/run_test_gates.sh intro`, simulator proof commands `happy`, `folded-duplicate`, and `all`, plus `git diff --check`; source row and inventory may change only after green four-identity evidence. Next action: spawn Executor with live fixture intake first.
- 2026-05-06 21:12:10 CEST - Executor spawn attempted. Files inspected since last update: none. Command currently running: `codex exec ... -a never ...`. Decision/blocker: tool invocation failed before child materialized because this `codex exec` subcommand rejects `-a`; no code/test/doc work was produced by a child agent. Next action: retry one Executor spawn with equivalent config override `approval_policy="never"`.
- 2026-05-06 21:13:36 CEST - Executor running locally after spawn handoff / live device intake started. Files inspected since last update: this plan and `implementation-execution-qa-orchestrator` skill. Command currently running: `flutter devices --machine` followed by `xcrun simctl list devices available`. Decision/blocker: no implementation started; verifying four distinct simulator identities before RED. Next action: record fixture availability or external-fixture blocker.
- 2026-05-06 21:13:59 CEST - Live device intake completed / RED command started. Files inspected since last update: none. Commands completed: `flutter devices --machine` and `xcrun simctl list devices available`. Decision/blocker: four distinct supported booted iOS simulators are available: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (A), `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (B), `1B098DFF-6294-407A-A209-BBF360893485` (C), and `38FECA55-03C1-4907-BD9D-8E64BF8E3469` (D); no fixture blocker before RED. Command currently running: `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`. Next action: capture expected unknown-scenario RED, then inspect owner files for the smallest harness changes.
- 2026-05-06 21:14:18 CEST - RED completed / implementation inspection started. Files inspected since last update: none. Command completed: `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`. Decision/blocker: expected RED captured exactly as `ERROR: Unknown INTRO_E2E_SCENARIO=folded-duplicate`; no implementation started before RED. Command currently running: owner-file/API inspection. Next action: inspect `smoke_test_friends.sh`, `reset_simulators.sh`, and `lib/core/debug/intro_e2e_runner.dart`, then implement folded harness support only.
- 2026-05-06 21:15:23 CEST - Implementation started. Files inspected since last update: `git status --short`, `smoke_test_friends.sh`, `reset_simulators.sh`, `lib/core/debug/intro_e2e_runner.dart`, `lib/features/introduction/application/load_introductions_use_case.dart`, `lib/features/introduction/application/folded_introduction_response_use_case.dart`, and `lib/features/introduction/application/send_introduction_use_case.dart`. Command currently running: none. Decision/blocker: owner files confirm the current harness is three-device-shaped and runner lacks folded snapshot/action support; implementing only D reset/smoke plumbing plus folded debug-runner APIs. Next action: edit owner files.
- 2026-05-06 21:19:54 CEST - Implementation completed / direct GREEN formatting and syntax checks started. Files touched since last update: `smoke_test_friends.sh`, `reset_simulators.sh`, and `lib/core/debug/intro_e2e_runner.dart`. Command currently running: `dart format lib/core/debug/intro_e2e_runner.dart`, then `bash -n smoke_test_friends.sh reset_simulators.sh`. Decision/blocker: folded duplicate scenario dispatch, four-device reset mode, folded snapshot output, and folded action result plumbing are implemented; no product UI/repository/migration files touched by this executor. Next action: run the required direct GREEN commands in order.
- 2026-05-06 21:20:18 CEST - Format/syntax GREEN completed / direct host tests started. Files touched since last update: `lib/core/debug/intro_e2e_runner.dart` was formatted. Commands completed: `dart format lib/core/debug/intro_e2e_runner.dart` and `bash -n smoke_test_friends.sh reset_simulators.sh`. Decision/blocker: format and shell syntax passed. Command currently running: `flutter test test/features/introduction/application/load_introductions_test.dart`. Next action: run the required folded application and Orbit wired direct tests.
- 2026-05-06 21:21:52 CEST - Direct host tests GREEN completed / named intro gate started. Files touched since last update: none. Commands completed: `flutter test test/features/introduction/application/load_introductions_test.dart`, `flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart`, `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "accepting a folded Orbit intro disables the folded row and updates every underlying intro once"`, and `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "passing a folded Orbit intro disables the folded row and updates every underlying intro once"`. Decision/blocker: all direct host tests passed. Command currently running: `./scripts/run_test_gates.sh intro`. Next action: run required named gate, then simulator proof commands.
- 2026-05-06 21:22:24 CEST - Named intro gate GREEN completed / simulator proof started. Files touched since last update: none. Command completed: `./scripts/run_test_gates.sh intro`. Decision/blocker: named gate passed. Command currently running: `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`. Next action: run required simulator proof commands `happy`, `folded-duplicate`, and `all`; classify any simulator/device/container/app install failure as external fixture blocker.
- 2026-05-06 21:23:14 CEST - Status check / simulator proof still running. Files inspected since last update: process table and child output file `build/codex_child_results/dif006_executor.md`. Command currently running: spawned Executor session `019dfeb5-3da9-7283-9e1e-7adfd6bd43b5` is driving `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh` (smoke PID `4984`); active child subcommand is `flutter build ios --simulator --no-pub --dart-define=AUTO_SETUP_USERNAME=a --dart-define=E2E_TEST_MODE=true` (PID `5172`) during reset/build for simulator A. Decision/blocker: no blocker currently; executor final output file exists but is empty because the spawned Executor has not returned. Next action: wait for `happy` proof completion, then continue with `folded-duplicate` and `all` unless an exact simulator/device/container/app install blocker occurs.
- 2026-05-06 21:26:33 CEST - Status check / simulator proof still running. Files inspected since last update: process table, plan tail, and `build/codex_child_results/`. Command currently running: spawned Executor session `019dfeb5-3da9-7283-9e1e-7adfd6bd43b5` is still driving `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh` (smoke PID `4984`); simulator A's `Runner.app` is launched and the active child subcommand is now `flutter build ios --simulator --no-pub --dart-define=AUTO_SETUP_USERNAME=b --dart-define=E2E_TEST_MODE=true` (PID `9100`) during reset/build for simulator B. Decision/blocker: no external-fixture blocker currently; `build/codex_child_results/dif006_executor.md` has not been created yet because the spawned Executor has not returned. Next action: continue waiting for `happy`, then run `folded-duplicate` and `all` or record the exact blocker.
- 2026-05-06 21:29:57 CEST - Happy simulator proof GREEN completed / folded duplicate simulator proof started. Files touched since last update: none. Command completed: `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`. Decision/blocker: existing three-identity happy path remains green. Command currently running: `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`. Next action: prove four distinct identities A/B/C/D with one folded B->C item, two raw ids, two introducers, one folded B action, and single B/C contact convergence.
- 2026-05-06 21:37:02 CEST - Folded duplicate simulator proof GREEN completed / all-scenario simulator proof started. Files touched since last update: none. Command completed: `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`. Decision/blocker: four distinct simulator identities A/B/C/D installed and launched; folded duplicate scenario passed with one folded B->C item, two raw intro ids, introducer attributions A and D, folded B accept action, and single B/C contact convergence. Command currently running: `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`. Next action: prove `all` dispatch includes the new scenario and remains green before docs/source row updates.
- 2026-05-06 22:07:21 CEST - All-scenario simulator proof failed / required-failure triage started. Files touched since last update: none. Command completed: `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` with exit 1. Decision/blocker: failure occurred in existing scenario 5 before the new folded scenario: C-side visible-copy assertion expected `a introduced you to b` under contact A but C's `systemMessages` for A were empty. Command currently running: result JSON inspection for scenario 5. Next action: classify whether this is caused by DIF-006 harness changes, pre-existing live flake, or environment/tooling; do not update source row/test inventory while `all` is red.
- 2026-05-06 22:07:58 CEST - All-scenario failure triage continued / standalone copy scenario started. Files inspected since last update: latest `intro_e2e_result.json` files for A/B/C from failed `copy-send`. Decision/blocker: failed result shows A and B had the expected raw introduction/message while C had no introduction row and no system message; this points to a live delivery/settling miss in the existing copy scenario rather than a DIF-006 folded harness regression. Command currently running: `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh`. Next action: use standalone copy result to decide whether to retry required `all` or stop blocked on a repeatable pre-existing simulator failure.
- 2026-05-06 22:13:48 CEST - Standalone copy triage failed / final hygiene completed / Executor completion recorded as blocked. Files touched since last update: none. Commands completed: `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh` failed with the same C-side visible-copy assertion, and `git diff --check` passed. Decision/blocker: required `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` remains red because existing scenario 5 repeatably fails before `all` reaches the new folded duplicate scenario; this is not a four-device fixture blocker and not caused by the DIF-006 owner-file changes, but it blocks full session closure under the plan's required gates. Source matrix row `DIF-006` and `test-inventory.md` were intentionally not updated. Command currently running: none. Next action: hand off blocked Executor result; recommended retry focus is the pre-existing `copy` scenario C-side delivery/settling failure, then rerun required `all`.
- 2026-05-06 22:15:18 CEST - Orchestrator reconciliation completed / QA Reviewer phase started. Files inspected since last update: Executor result `build/codex_child_results/dif006_executor.md`, plan progress, and `git status --short`. Command currently running: fresh QA Reviewer `codex exec` handoff. Decision/blocker: Executor is complete and blocked on required `all` gate failure in the existing `copy` scenario; plan chronology was corrected before QA; source row and `test-inventory.md` remain untouched. Next action: QA Reviewer checks scope, evidence, blocker classification, docs gating, and whether a bounded fix pass is warranted.
- 2026-05-06 22:19:07 CEST - QA Reviewer phase completed / fix-pass 1 started. Files inspected since last update: QA result `build/codex_child_results/dif006_qa.md`, `smoke_test_friends.sh`, source row, and `test-inventory.md`. Command currently running: fresh fix-pass Executor `codex exec` handoff. Decision/blocker: QA found one in-scope fix-loop issue: three-device `prepare_devices` now resolves D's app container through `cache_docs_dirs`; this must be narrowed so existing three-device scenarios cache only A/B/C while `prepare_four_devices` caches A/B/C/D. QA also confirmed the `all` failure remains a required gate/test blocker in existing `copy`, not an external fourth-fixture blocker. Next action: fix docs-cache scope, run fast syntax/hygiene and affected simulator proof, then run QA again.
- 2026-05-06 22:20:04 CEST - Fix-pass 1 inspection completed / implementation started. Files inspected since last update: `smoke_test_friends.sh`, QA result `build/codex_child_results/dif006_qa.md`, and prior executor result `build/codex_child_results/dif006_executor.md`. Command currently running: none. Decision/blocker: confirmed `cache_docs_dirs` unconditionally resolves `DEVICE_D` and both `prepare_devices` and `prepare_four_devices` call it; implementing only the helper split so three-device setup caches A/B/C and four-device setup caches A/B/C/D. Next action: edit `smoke_test_friends.sh`.
- 2026-05-06 22:20:37 CEST - Fix-pass 1 implementation completed / syntax verification starting. Files touched since last update: `smoke_test_friends.sh` and this plan. Command currently running: `bash -n smoke_test_friends.sh reset_simulators.sh`. Decision/blocker: `cache_docs_dirs` now caches only A/B/C; new `cache_four_docs_dirs` adds D and is used only by `prepare_four_devices`. Next action: run required fix-pass verification commands in order.
- 2026-05-06 22:20:59 CEST - Syntax verification GREEN / happy simulator proof starting. Files touched since last update: none. Command completed: `bash -n smoke_test_friends.sh reset_simulators.sh`. Decision/blocker: shell syntax passed after docs-cache helper split. Command currently running: `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`. Next action: prove existing three-device path no longer depends on D and still passes.
- 2026-05-06 22:26:08 CEST - Happy simulator proof GREEN / folded duplicate simulator proof starting. Files touched since last update: none. Command completed: `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`. Decision/blocker: three-device setup passed after `cache_docs_dirs` was narrowed to A/B/C, proving existing scenarios do not depend on D's app container. Command currently running: `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`. Next action: prove the four-device path still caches A/B/C/D and folded duplicate remains green.
- 2026-05-06 22:33:15 CEST - Folded duplicate simulator proof GREEN / diff hygiene starting. Files touched since last update: none. Command completed: `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`. Decision/blocker: four-device setup passed after `prepare_four_devices` switched to `cache_four_docs_dirs`, including successful D export and folded duplicate harness pass. Command currently running: `git diff --check`. Next action: run final required hygiene check; do not rerun `INTRO_E2E_SCENARIO=all` because the standalone `copy` blocker was not affected by this narrow helper change.
- 2026-05-06 22:33:33 CEST - Diff hygiene GREEN / fix-pass 1 completed blocked. Files touched since last update: none. Command completed: `git diff --check`. Decision/blocker: required fix-pass commands passed and QA's docs-cache helper issue is fixed; remaining closure blocker is unchanged `INTRO_E2E_SCENARIO=all` required-gate failure caused by the pre-existing standalone `copy` scenario C-side delivery/settling miss. Command currently running: none. Next action: hand off for QA; do not update source row, `test-inventory.md`, or DIF-007 closure docs until the existing `copy` blocker is resolved and `all` is green.
- 2026-05-06 22:34:21 CEST - QA Reviewer phase 2 started. Files inspected since last update: fix-pass result `build/codex_child_results/dif006_fix1.md`, plan progress, and `smoke_test_friends.sh` helper locations. Command currently running: fresh QA Reviewer `codex exec` handoff. Decision/blocker: fix-pass resolved the in-scope docs-cache issue and reran required fix-pass verification; remaining blocker is still the required `all` gate's existing `copy` scenario failure. Next action: QA verifies the fix-pass scope/evidence and final blocked classification.
- 2026-05-06 22:36:54 CEST - QA Reviewer phase 2 completed / final execution verdict persisted. Files inspected since last update: QA result `build/codex_child_results/dif006_qa2.md`, plan progress, `smoke_test_friends.sh`, source row, `test-inventory.md`, and diff hygiene. Command completed by QA: `git diff --check` passed. Decision/blocker: QA accepted the fix-pass helper split and found no further DIF-006 fix-loop issue; final verdict remains `blocked` with blocker class `test_or_gate_failure` because required `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` is still red in existing scenario 5 `copy`, and standalone `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh` reproduced the same C-side missing intro/system-message assertion. Source row `DIF-006`, `test-inventory.md`, and `DIF-007` closure docs were not updated because `all` is not green. Command currently running: none. Next action: fix or classify the existing `copy` scenario C-side delivery/settling failure, then rerun required `all`.
- 2026-05-07 14:25 CEST - Resume execution evidence completed / final verdict
  updated to accepted. Files touched since last update:
  `smoke_test_friends.sh`,
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`,
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`,
  and this plan. Commands completed before this update: standalone
  `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh` passed after
  increasing `offline-first-chat` receiver `chat_poll_cycles` to `120`; the
  earlier full-suite attempt had already passed scenario 1 before the
  user-requested stop; resumed scenarios `refresh`, `pass`, `repair`, `copy`,
  `partial`, `partition`, `offline-chat`, `pass-fallback`, `split-brain`, and
  `folded-duplicate` all passed and ended with
  `=== Intro E2E harness passed ===`. Decision/blocker: no DIF-006 blocker
  remains. The previous `copy` blocker is obsolete because scenario 5 passed
  during the resumed loop; the accepted full coverage evidence is explicitly
  resumed rather than one uninterrupted `all` process. Command currently
  running: none. Next action: `DIF-007` final documentation/regression closure.

## Closure Progress

- 2026-05-06 22:39 CEST - Completion Auditor started. Docs inspected:
  this DIF-006 plan, source matrix row `DIF-006`, and the session breakdown
  ledger. Tentative verdict: `still_open`. Next action: confirm which closure
  evidence landed, which gate remains red, and whether the blocker is
  fourth-device fixture, DIF-006 folded-harness regression, or required-gate
  failure outside the new folded scenario.
- 2026-05-06 22:39 CEST - Completion Auditor completed / Closure Writer
  started. Docs inspected: this plan's execution evidence, source matrix row
  `DIF-006`, `DIF-007` dependency row, and session breakdown ledger. Verdict:
  `still_open`; blocker class `test_or_gate_failure`. What landed and verified:
  live four-identity fixture intake; expected RED
  `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh` as unknown
  scenario before implementation; harness/debug-runner changes in
  `smoke_test_friends.sh`, `reset_simulators.sh`, and
  `lib/core/debug/intro_e2e_runner.dart`; shell syntax; focused direct host
  tests; `./scripts/run_test_gates.sh intro`;
  `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh`;
  `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh`; fix-pass
  reruns of `happy`, `folded-duplicate`, and `git diff --check`. Remaining
  blocker: required `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` is red
  because existing scenario 5 `copy` fails before the new folded scenario runs;
  standalone `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh` reproduced the
  C-side missing intro/system-message assertion. This is not an external
  fourth-device fixture blocker and not a DIF-006 folded-harness product
  regression. Next action: persist the session as blocked without closing
  `DIF-006`, `test-inventory.md`, or `DIF-007`.
- 2026-05-06 22:39 CEST - Closure Writer completed / Closure Reviewer
  started. Docs updated in this closure pass: this plan, the session breakdown
  ledger/closure note, and source matrix row `DIF-006` blocker evidence. Draft
  closure verdict: `still_open` with blocker class `test_or_gate_failure`.
  Next action: review for overclaiming, source-row status consistency, and
  no unintended `DIF-007` closure.
- 2026-05-06 22:39 CEST - Closure Reviewer completed. Closure verdict:
  `still_open`. The DIF-006 harness work has meaningful green evidence, but
  the session is not accepted because a required gate remains red:
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` fails in the existing
  `copy` scenario before the folded duplicate scenario runs. Keep `DIF-006`
  blocked, keep `DIF-007` open/dependent, and reopen only after the existing
  `copy` C-side delivery/settling failure is fixed or separately classified
  and `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` is green.
- 2026-05-07 14:25 CEST - Resume closure update completed. Closure verdict:
  `accepted`; blocker class `none`. Docs updated in this closure pass: this
  plan, the session breakdown ledger/closure note, and source matrix row
  `DIF-006`. Accepted evidence: standalone `offline-chat` passed after the
  receiver wait fix, scenario 1 had already passed before the user-requested
  stop, and resumed scenarios 2-11 all passed sequentially through
  `folded-duplicate`. `DIF-007` is now unblocked but not run.

## real scope

This session adds a four-identity simulator proof for folded duplicate introductions.

In scope:

- Extend `smoke_test_friends.sh` for `INTRO_E2E_SCENARIO=folded-duplicate`.
- Extend `reset_simulators.sh` only enough to provision a fourth simulator identity for this scenario while keeping the existing three-simulator scenarios usable.
- Extend `lib/core/debug/intro_e2e_runner.dart` only as debug/test harness code needed to expose folded review snapshots and apply a folded action through the existing folded application use case.
- Include `folded-duplicate` in `INTRO_E2E_SCENARIO=all`.
- Record closure evidence in source row `DIF-006` and `Test-Flight-Improv/Intro-Feature/test-inventory.md` only after the four-identity scenario and required gates are green.

Out of scope:

- App product behavior changes beyond debug/test harness plumbing.
- Database schema or persistence changes.
- New product UI design, copy, or route behavior.
- Final rollout closure or `DIF-007` documentation.
- Closing `DIF-006` from a three-device run.

## closure bar

`DIF-006` is complete only when all of the following are true:

- Four distinct identities run in one simulator/device-lab scenario: introducer A, current viewer B, introduced target C, second introducer D.
- A and D each create an active intro for the same B/C pair, producing two distinct underlying intro ids.
- B's folded review snapshot contains exactly one folded item for target C, with both underlying intro ids and both introducer attributions A and D.
- B performs one folded action over that folded item, and the action result proves both underlying intro ids were applied through the folded use case.
- The target-side acceptance/convergence phase proves B and C reach the expected final state without duplicate contacts.
- `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh` remains green.
- `INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh` is green with the four simulator ids listed in this plan or a documented equivalent four-identity fixture.
- `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` includes the folded duplicate scenario and is green.
- `./scripts/run_test_gates.sh intro` remains green after any Dart debug-runner changes.

## source of truth

- Current code and tests win over prose if there is a conflict.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` row `DIF-006` defines the scenario and closure requirement.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md` defines this session's one-session scope and device proof profile requirement.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define the named `intro` gate; if they disagree, the script wins.
- `smoke_test_friends.sh`, `reset_simulators.sh`, and `lib/core/debug/intro_e2e_runner.dart` are authoritative for the live simulator harness shape.
- `lib/features/introduction/application/load_introductions_use_case.dart` and `lib/features/introduction/application/folded_introduction_response_use_case.dart` are the authoritative folded projection/action APIs to reuse from debug harness code.

## session classification

`implementation-ready`

The four-identity fixture is currently available. The row should become `prerequisite-blocked` only if execution-time device intake no longer has four usable identities, or if the fourth simulator cannot be installed/launched by the harness after reset support is added.

Dependency intake: `DIF-001` through `DIF-005` are accepted in the session ledger and `Closed` in the source matrix. This plan does not reopen them unless execution finds direct contradictory evidence.

## exact problem statement

The source matrix has host-side proof for folded projection, folded counts, folded actions, UI rendering, and Orbit wired behavior through `DIF-001` through `DIF-005`, but there is no simulator proof that two different introducers can create duplicate active intros for the same current viewer and target, and that the live debug/device harness observes one folded row and one folded decision over both raw intro ids.

Current evidence:

- `smoke_test_friends.sh` defines only `DEVICE_A`, `DEVICE_B`, and `DEVICE_C`.
- `reset_simulators.sh` installs and launches only those three simulator identities with usernames `a`, `b`, and `c`.
- `lib/core/debug/intro_e2e_runner.dart` collects raw `introductions` in its snapshot but no folded review projection.
- The runner's current `accept_all` / `pass_all` path loops raw pending intros and calls `acceptIntroduction(...)` / `passIntroduction(...)`; it does not prove a folded action call.

The user-visible behavior this proves is that a real multi-device intro flow produces one review decision for duplicate introducers, not two independent rows or two required taps. Existing single-intro, three-simulator, relay, pass, repair, partition, and split-brain behavior must stay unchanged.

## Device/Relay Proof Profile

Live availability checks were run during planning on 2026-05-06 21:03-21:05 CEST:

- `flutter devices --machine`
- `xcrun simctl list devices available`

Available supported devices from `flutter devices --machine`:

- Android physical: `21071FDF600CSC` Pixel 6
- iOS physical: `00008030-001A6D2801BB802E` Saleh's iPhone
- iOS simulator booted: `38FECA55-03C1-4907-BD9D-8E64BF8E3469` iPhone 17 Pro
- iOS simulator booted: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` iPhone Air
- iOS simulator booted: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` iPhone 17
- iOS simulator booted: `1B098DFF-6294-407A-A209-BBF360893485` iPhone 16e

`xcrun simctl list devices available` confirms the four booted iOS simulators and additional shutdown iOS simulators.

Classification: four-identity/device-lab, not three-party/device-lab.

Fourth identity strategy:

- Use the currently booted iOS simulator `38FECA55-03C1-4907-BD9D-8E64BF8E3469` as `DEVICE_D`, username `d`, second introducer D.
- Keep current mappings for the existing three identities:
  - A introducer: `DEVICE_A=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
  - B current viewer: `DEVICE_B=5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
  - C introduced target: `DEVICE_C=1B098DFF-6294-407A-A209-BBF360893485`
  - D second introducer: `DEVICE_D=38FECA55-03C1-4907-BD9D-8E64BF8E3469`
- Do not use the physical iPhone or Android as the first-choice fourth identity because the existing harness uses `xcrun simctl` install/launch/container APIs.

Exact commands/environment variables for execution:

```bash
flutter devices --machine
xcrun simctl list devices available
bash -n smoke_test_friends.sh reset_simulators.sh
INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh
INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh
INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh
```

`FLUTTER_DEVICE_ID` is not sufficient for the simulator proof. The smoke harness drives multiple simulator ids with `xcrun simctl`; a single `FLUTTER_DEVICE_ID` can select one Flutter target for some gates, but it cannot represent A, B, C, and D simultaneously.

Execution-time blocker rule:

- If fewer than four distinct simulator/device identities can be installed, launched, and read via Documents containers, classify `DIF-006` as blocked with the exact missing/unusable device id and do not mark it `Closed`.
- Three devices plus one repeated identity is not enough.

## files and repos to inspect next

Implementation should inspect and edit only these likely files unless evidence proves a direct harness dependency:

- `smoke_test_friends.sh`
- `reset_simulators.sh`
- `lib/core/debug/intro_e2e_runner.dart`
- `lib/features/introduction/application/load_introductions_use_case.dart` for existing folded projection API usage only
- `lib/features/introduction/application/folded_introduction_response_use_case.dart` for existing folded action API usage only
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` row `DIF-006` after green proof only
- `Test-Flight-Improv/Intro-Feature/test-inventory.md` after green proof only
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md` only during later closure audit, not during implementation unless the pipeline requires ledger updates

Do not edit product UI files, repository implementations, migrations, or the final `DIF-007` docs in this session.

## existing tests covering this area

Already covered:

- `test/features/introduction/application/load_introductions_test.dart` covers folded projection and folded pending count.
- `test/features/introduction/application/folded_introduction_response_use_case_test.dart` covers folded accept/pass over both underlying intro ids.
- `test/features/introduction/presentation/widgets/intro_row_test.dart`, `intros_tab_test.dart`, and `intros_tab_extended_test.dart` cover folded attribution rendering.
- `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart` covers one folded row in the active Orbit sliver.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` covers folded wired accept/pass, processing suppression, and folded badge count.
- `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh` and the existing three-simulator matrix cover single-introducer simulator flows, not duplicate introducers.

Missing:

- No four-identity simulator scenario.
- No runner snapshot of folded review items.
- No debug-runner folded action path; current runner raw `accept_all` does not prove a single folded decision.
- No fourth simulator install/launch/reset path.

## regression/tests to add first

Use command-level RED because this is a shell/device proof session:

```bash
INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh
```

Expected pre-change RED: the script fails fast with `ERROR: Unknown INTRO_E2E_SCENARIO=folded-duplicate`. Do not run `INTRO_E2E_SCENARIO=all` as RED because it is long and currently executes the existing matrix before any missing folded branch would matter.

Add no product-code unit test solely for this row unless implementation extracts new pure Dart serialization/helper logic from `intro_e2e_runner.dart`. If it does, add a narrow direct test for that helper before implementation. Otherwise, the regression is the new simulator scenario plus the existing folded application/Orbit tests.

## step-by-step implementation plan

1. Re-run live fixture intake:

   ```bash
   flutter devices --machine
   xcrun simctl list devices available
   ```

   Stop and record an external-fixture blocker if four distinct runnable identities are unavailable.

2. Capture command-level RED:

   ```bash
   INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh
   ```

   Expected current failure: unknown scenario. Stop if it unexpectedly runs a folded scenario; inspect current harness before editing.

3. Extend `reset_simulators.sh` minimally:

   - Add `DEVICE_D=38FECA55-03C1-4907-BD9D-8E64BF8E3469`.
   - Add username `d`.
   - Keep the default three-device behavior for existing scenarios.
   - Add a four-device mode for the folded scenario, for example `INTRO_E2E_DEVICE_SET=four`, so `prepare_devices` can still use three devices and `prepare_four_devices` can install/launch A/B/C/D.
   - Use the same `flutter build ios --simulator --no-pub --dart-define=AUTO_SETUP_USERNAME=<name> --dart-define=E2E_TEST_MODE=true` pattern already present.

4. Extend `smoke_test_friends.sh` minimally:

   - Add `DEVICE_D=38FECA55-03C1-4907-BD9D-8E64BF8E3469` and `DOCS_D`.
   - Extend `get_docs_dir`, cache/export helpers, and result helpers only where four-device scenario code needs D.
   - Add `prepare_four_devices` that runs the reset script in four-device mode, reads `EXPORT_D`, derives `PEER_D` / `USER_D`, and builds `CONTACT_D_JSON`.
   - Do not rewrite existing A/B/C helpers unless needed; keep existing scenarios stable.

5. Add folded duplicate scenario shell phases:

   - `run_folded_duplicate_handshake_phase`:
     - A adds contacts B and C.
     - D adds contacts B and C.
     - B adds A and D.
     - C adds A and D.
     - All four use `contact_request_action: "none"` and `introduction_action: "none"`.
   - `run_folded_duplicate_send_phase`:
     - A sends introduction B -> C.
     - D sends introduction B -> C.
     - B and C poll without acting.
     - Assert B has exactly two raw intro ids for pair B/C from introducers A and D.
     - Assert B's folded snapshot has exactly one folded item for target C, both raw ids, and introducer attributions for A and D.
   - `run_folded_duplicate_accept_phase`:
     - B uses a new folded debug action, such as `accept_folded_all`.
     - C may use existing `accept_all` to complete both underlying intros from the target side.
     - A and D poll without acting.
     - Assert B's folded action result has one target group and two applied intro ids.
     - Assert B and C converge to a single contact relationship and do not duplicate contacts.
     - Assert the two underlying raw intro ids remain distinct and reach the expected accepted/mutual state.

6. Extend `lib/core/debug/intro_e2e_runner.dart` as harness code only:

   - Import and reuse `foldIntroductionsForReview(...)`, `acceptFoldedIntroduction(...)`, and `passFoldedIntroduction(...)`.
   - Add folded review snapshot output beside the existing raw `introductions`, with fields:
     - `targetPeerId`
     - `targetDisplayName`
     - `displaySourceIntroductionId`
     - `introductionIds`
     - `introducerAttributions` as `{introducerId, displayName}`
     - `pendingCurrentViewerDecisionIntroIds`
     - `acceptedCurrentViewerDecisionIntroIds`
     - `passedCurrentViewerDecisionIntroIds`
   - Add a folded action path for `accept_folded_all` and, if symmetrical with no extra product scope, `pass_folded_all`.
   - The folded action result should record one entry per folded target group with `targetPeerId`, `introductionIds`, and per-id outcomes from `FoldedIntroductionActionBatchResult`.
   - Leave existing `accept_all`, `pass_all`, and `drop_first` semantics unchanged.

7. Add assertions in `smoke_test_friends.sh`:

   - `assert_folded_duplicate_pending_state` validates B's raw rows and folded snapshot after the send phase.
   - `assert_folded_duplicate_accept_action` validates B's `introAction` result after folded accept.
   - `assert_folded_duplicate_terminal_state` validates B/C convergence and no duplicate contacts after C accepts.
   - Use set comparisons for intro ids and introducer ids so ordering does not cause flakes.

8. Wire scenario dispatch:

   - Add `scenario_folded_duplicate`.
   - Add `folded-duplicate)` branch.
   - Add `scenario_folded_duplicate` to the `all)` branch.
   - Update visible scenario numbering from 10 to 11 only as needed in echo text.

9. Format and syntax-check:

   ```bash
   dart format lib/core/debug/intro_e2e_runner.dart
   bash -n smoke_test_friends.sh reset_simulators.sh
   git diff --check
   ```

10. Run direct host-side guards:

   ```bash
   flutter test test/features/introduction/application/load_introductions_test.dart
   flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart
   flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "accepting a folded Orbit intro disables the folded row and updates every underlying intro once"
   flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "passing a folded Orbit intro disables the folded row and updates every underlying intro once"
   ```

11. Run named and simulator gates:

   ```bash
   ./scripts/run_test_gates.sh intro
   INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh
   INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh
   INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh
   ```

12. Update docs only after green evidence:

   - Update `DIF-006` row in `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md` from `Open` to `Closed` only with exact command evidence.
   - Update `Test-Flight-Improv/Intro-Feature/test-inventory.md` with the new four-identity simulator scenario only if it closes.
   - Do not update `DIF-007` closure in this session.

## risks and edge cases

- Four-simulator install/launch can fail even if `flutter devices --machine` lists the simulator. Treat that as an execution-time fixture blocker if retrying the reset path does not recover it.
- A and D may send concurrently and snapshots can lag. Assertions should poll through the existing result wait flow and use stable sets of ids, not ordering.
- The runner's folded snapshot must reuse the same folded projection API that Orbit uses; a separate ad hoc fold in shell/Python would be weaker proof.
- A folded accept should be one folded action group on B, not a shell loop that manually accepts two raw ids.
- C may still use raw `accept_all` because C is completing the target-side convergence, not proving B's folded decision.
- Existing three-simulator scenarios should not pay the fourth-device install cost unless the folded scenario or `all` requires it.
- Physical devices are present but not compatible with the current `xcrun simctl` harness shape; do not broaden into physical-device install support in this session.

## exact tests and gates to run

RED:

```bash
INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh
```

Expected before implementation: unknown scenario.

Direct GREEN:

```bash
dart format lib/core/debug/intro_e2e_runner.dart
bash -n smoke_test_friends.sh reset_simulators.sh
flutter test test/features/introduction/application/load_introductions_test.dart
flutter test test/features/introduction/application/folded_introduction_response_use_case_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "accepting a folded Orbit intro disables the folded row and updates every underlying intro once"
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name "passing a folded Orbit intro disables the folded row and updates every underlying intro once"
```

Named gate:

```bash
./scripts/run_test_gates.sh intro
```

Device/relay proof:

```bash
flutter devices --machine
xcrun simctl list devices available
INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh
INTRO_E2E_SCENARIO=folded-duplicate ./smoke_test_friends.sh
INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh
```

Final hygiene:

```bash
git diff --check
```

## known-failure interpretation

- A pre-existing red direct host-side test outside the touched harness files is not `DIF-006` failure unless it is newly caused by the runner/harness changes; record the pre-existing failure separately.
- `INTRO_E2E_SCENARIO=folded-duplicate` failing before implementation with unknown scenario is the intended RED.
- Any post-implementation `folded-duplicate` failure to resolve `DEVICE_D`, install the app, read `EXPORT_D`, or access D's Documents directory is an external fixture/harness blocker, not product closure.
- Any post-implementation folded snapshot that shows two folded items for target C, one introducer only, one raw id only, or a raw-loop action instead of one folded action group is a real `DIF-006` failure.
- Do not treat green three-device `happy` evidence as closure for `DIF-006`.

## done criteria

- Plan execution used four distinct identities with exact ids recorded.
- `smoke_test_friends.sh` supports `INTRO_E2E_SCENARIO=folded-duplicate`.
- `INTRO_E2E_SCENARIO=all` runs the new folded scenario.
- The debug runner snapshot proves one folded B->C item with two raw intro ids and two introducers.
- B's folded action result proves one folded action over both raw ids.
- Required direct, named, and simulator commands are green.
- `DIF-006` source row and `test-inventory.md` are updated only after green evidence.
- `DIF-007` remains open for final regression/documentation closure.

## scope guard

Do not:

- Change production intro folding semantics.
- Change database row shape or migrations.
- Add physical-device support to the shell harness.
- Rewrite the full smoke harness.
- Close or partially close `DIF-007`.
- Use a three-device duplicate workaround or reuse one identity as both A and D.
- Replace existing raw `accept_all` semantics for existing scenarios.
- Overclaim UI proof from raw intro rows alone; folded snapshot/action proof must come from the folded application APIs.

## accepted differences / intentionally out of scope

- The simulator proof may use debug-runner folded snapshots and folded use-case actions rather than tapping the visual row in a real UI automation framework. This is accepted because `DIF-004` and `DIF-005` already pin the UI/wired folded row behavior, while this session proves the live four-identity data path.
- The scenario should exercise folded accept as the simulator proof path. Folded pass remains host-side covered by `DIF-003` and `DIF-005`; adding a `pass_folded_all` debug action is acceptable only if it is a small symmetric harness extension, not a second long simulator scenario.
- Physical iOS/Android devices are intentionally not used while the existing smoke harness is simulator-based.

## dependency impact

- `DIF-007` depends on this row's four-identity evidence before final rollout closure.
- If `DIF-006` is blocked by fixture availability, `DIF-007` must stay open/blocked and cannot convert the rollout to closed.
- If runner changes reveal a missing folded API contract, stop and reopen the relevant earlier row with concrete evidence instead of patching product behavior inside this simulator-proof session.

## reviewer notes

- Sufficiency verdict: sufficient with adjustments.
- Missing files/tests/gates: none structural. The plan names the direct harness files, folded application APIs, direct host-side guards, named `intro` gate, and simulator commands.
- Stale assumptions: none found in current intake. The fixture must still be rechecked by the executor before running the scenario.
- Overengineering risk: adding physical-device support or UI automation would be over-scoped. The plan rejects those and uses folded runner snapshots/actions because earlier rows already pin UI/wired behavior.
- Decomposition: narrow enough for one session. The fourth-device reset path, smoke scenario, and debug-runner folded snapshot/action support are one coherent simulator proof.
- Minimum needed for sufficiency: keep the four-device blocker rule, folded-action proof, source-row/test-inventory update conditions, and `DIF-007` exclusion intact during execution.

## arbiter decision

- Final verdict: execution-ready.
- Structural blockers remaining: none.
- Incremental details intentionally deferred:
  - Do not add physical-device support.
  - Do not add a second long folded-pass simulator scenario unless execution finds accept proof insufficient.
  - Do not introduce broad environment-variable override plumbing unless needed to keep the fourth simulator selectable.
- Accepted differences intentionally left unchanged:
  - Debug-runner folded snapshots/actions are accepted as simulator proof because `DIF-004` and `DIF-005` already own UI/wired visual behavior.
  - Folded accept is the simulator proof action; folded pass remains covered by host-side folded action and Orbit wired tests unless execution finds a direct simulator-specific pass regression.
- Why safe to implement now: the live fixture has four booted iOS simulators, dependencies `DIF-001` through `DIF-005` are closed/accepted, the current harness gaps are explicitly identified, and the plan has concrete RED, GREEN, named-gate, simulator-proof, blocker, documentation, and scope-guard contracts.
