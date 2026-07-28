# 291 - Intro Notification Campaign Budget

Status: harness implementation-complete / focused-host-green; Plan-252 corrective preservation and coherent-source live proof green; remaining closure gates pending
Type: Bug
Spec: free-text follow-up from DTR-13 live closure
Classification: implemented harness follow-up; closure pending
Closure tier: device
Owner authorization: `W4A-BLOCKERS-AUTH-01`

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-27 | Planner | `run_intro_accept_notification_android.dart`; `intro_e2e_runner.dart` | Fixed 240 s budget is consumed by health/inbox replay and contention | Add phase budget tests and rerun proof |
| 2026-07-27 | Executor | Android runner, Sims adapter, focused budget/runner tests | One absolute 24-minute scenario deadline now caps named phases; each acceptance phase shares one 6-minute allocation across result, card, tap, and redirect waits | Run the exact live Sims scenario on the available Android matrix |
| 2026-07-27 | Live reproducer | physical Android `21071FDF600CSC`; emulators `emulator-5558` and `emulator-5560`; archived report | The new harness budget reached a true cold notification tap. That run then exposed a stream failure and stale B-only state at Plan 252's exact-anchor convergence boundary rather than another Plan-291 budget reset. | Repair the narrow Plan-252 product seam under `W4A-BLOCKERS-AUTH-01`, then rerun this unchanged harness proof. |
| 2026-07-28 | Live closer | Pixel 6 `21071FDF600CSC`; API-35 emulators `emulator-5558` and `emulator-5560`; final Sims report and proof artifact | The corrected exact-anchor preservation and final coherent-source `intro.accept_notification_campaign` passed both the physical-introducer and emulator-introducer assertions | Retain Plan-green as pending until `core-host-all`, final diff hygiene, Graphify, and Wave aggregate `host-all` finish |

## Problem And Evidence
- Behavior: intro acceptance notification campaign completes reciprocal invitation and notification assertions within a contention-aware budget.
- Impact: valid journeys time out at B after preflight.
- Confirmed gap: `integration_test/scripts/run_intro_accept_notification_android.dart:485-503,835-870` and `lib/core/debug/intro_e2e_runner.dart:421-521,1425-1596`.
- Existing coverage: `integration_test/intro_accept_notification_android_proof_test.dart`, `test/core/debug/intro_e2e_runner_custody_test.dart`, and `test/core/debug/intro_e2e_runner_token_proof_test.dart`; missing phase attribution and contention proof.
- Refuted: missing relay/fixture inputs; three-device preflights passed.
- Resolved allocation: a 24-minute absolute scenario deadline caps 2-minute
  preflight, 4-minute install, 5-minute bootstrap, 7-minute fixture, 6-minute
  B/C acceptance, and 2-minute finalization allocations. Allocations are
  ceilings, not additive extensions of the absolute campaign deadline.
- Newly reproduced separate defect: the repeated live run reached a cold tap,
  then failed while the exact introducer-accept anchor was converging from
  stale B-only state. That product behavior belongs to a narrow corrective
  amendment of
  `252-intro-accept-notification-copy-chat-routing-tdd-plan.md`; it is not
  silently absorbed into this harness-budget plan.

## Graph Grounding Snapshot
- Fingerprint/freshness at planning: `d4a9a72d5be10723`, current at that
  snapshot; the final Wave 4A Graphify refresh remains pending.
- Query: `python3 graphify-arch/tdd_context.py query "intro_accept_notification_android.dart IntroE2ERunner" --profile tdd --budget 700`.
- Anchors: Android runner and `lib/core/debug/intro_e2e_runner.dart`;
  executable gate `./scripts/run_test_gates.sh intro` and scenario
  `intro.accept_notification_campaign`.
- Gaps: exact timer constants require source verification.

## Scope Contract And Guard
In scope: one absolute campaign deadline, phase-scoped budget accounting,
acceptance discrimination, bounded child termination, and idempotent late
cleanup under contention.
Must preserve: invite semantics, notification payload/order, cleanup, and existing intro scenarios.
Hard `Do not`: alter invitation protocol, payload schema, topology policy, or DTR composition.
Explicit exclusion: exact-anchor status convergence, notification-open product
routing, and stale B/C introduction state are Plan 252 product ownership.
Deferred: the narrow Plan-252 corrective amendment and coherent-source rerun
are now green; Plan-green still waits for the explicitly named final closure
gates. Plan 291 itself remains harness scope.

## Test Contract
| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | Phase budgets account for setup/replay | `test/core/debug/intro_e2e_budget_test.dart::allocates_budget_by_phase` | host fake clock | fixed deadline exhausts early -> phase budget remains | remove ledger -> red | `flutter test test/core/debug/intro_e2e_budget_test.dart`; AUTO core |
| TC-02 | Polling uses acceptance discriminator | `test/core/debug/intro_e2e_runner_test.dart::waits_for_notification_acceptance_event` | host fake custody | generic health event cannot complete wait -> explicit acceptance completes | accept generic event -> red | exact test; AUTO core |
| TC-03 | Campaign completes under contention | `integration_test/intro_accept_notification_android_proof_test.dart` plus `run_intro_accept_notification_android.dart` scenario `intro.accept_notification_campaign` | one physical Android + two Android emulators, automated three-party topology | original 240 s timeout -> all assertions pass after the separate Plan-252 exact-anchor correction | restore independent/global 240 s deadline -> device red | `./scripts/run_test_gates.sh sims major --only intro.accept_notification_campaign`; existing scenario |

## Implementation Steps
1. Snapshot tree; add TC-01/02 RED.
2. Add phase budget ledger and bounded polling without event changes.
3. Run focused tests, `./scripts/run_test_gates.sh intro`, device proof,
   analysis, and hygiene.

## Risks And Blind Spots
- Premature completion -> TC-02 discriminator.
- Retry/cleanup leakage -> TC-03 cleanup assertions.
- Re-entry -> TC-03 cold-tap leg across the physical + two-emulator topology.
- Product/harness scope blur -> the Plan-252 exact-anchor correction is
  reviewed and recorded separately; Plan 291 changes no routing or intro-state
  semantics.

## Gate Cadence
- Per-plan: focused core tests, `./scripts/run_test_gates.sh intro`, exact Sims
  scenario, and analysis.
- Full `host-all` belongs to dependency-wave/final closure, not this plan.

## Acceptance Gates
```bash
git status --short
flutter test test/core/debug/intro_e2e_budget_test.dart --plain-name 'allocates budget by phase'
flutter test test/core/debug/intro_e2e_budget_test.dart
flutter test test/core/debug/intro_e2e_runner_test.dart --plain-name 'waits for notification acceptance event'
flutter test test/core/debug/intro_e2e_runner_test.dart
bash scripts/test/intro_accept_notification_sims_adapter_contract_test.sh
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh intro
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh sims major --only intro.accept_notification_campaign
# Repository strict analysis supersedes a weaker standalone `flutter analyze`.
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: global deadline expires before B acceptance.
- Availability note: the executed one-physical/two-emulator topology was
  available. Any other unavailable Android target or version is N/A by
  repository policy, not an environment blocker.
- [x] causal RED/GREEN evidence; [x] Plan-252 correction and coherent-source
  three-party proof; [x] focused and affected shared gates recorded; [x] strict
  analysis; [ ] `core-host-all`, final diff hygiene, Graphify, and Wave
  aggregate `host-all`.

## Handoff
- First causal RED: budget test command above.
- Preservation: `./scripts/run_test_gates.sh intro`.
- Manual registration: existing intro scenario; migration: none.
- Boundary closure: physical Android + two available Android emulators.

## Exact Inverse Rollback Contract

The Plan-291 inverse restores only the execution-start absolute-deadline,
phase-budget, acceptance-discriminator, child-supervision, and cleanup hunks in
`integration_test/scripts/run_intro_accept_notification_android.dart` and
`integration_test/scripts/run_intro_accept_notification_sims.dart`; it removes
only `test/core/debug/intro_e2e_budget_test.dart` and
`test/core/debug/intro_e2e_runner_test.dart`. Preserve the registered
three-party scenario, every profile/define/entrypoint, notification
payload/order, invitation protocol, relay/provider boundary, device policy,
and all Plan-252 product code. Do not roll the Plan-252 exact-anchor correction
back with this harness range.

After the Plan-291 inverse, run exactly:

```bash
flutter test integration_test/intro_accept_notification_android_proof_test.dart
flutter test test/core/debug/intro_e2e_runner_custody_test.dart test/core/debug/intro_e2e_runner_token_proof_test.dart
bash scripts/test/intro_accept_notification_sims_adapter_contract_test.sh
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh intro
./scripts/run_test_gates.sh runtime-roots
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

Withdraw Plan 291's focused-host/Plan-green status and every live-row claim
that depends on its enlarged/shared budget. The Plan-252 corrective status
remains independent. If that product correction is separately rolled back,
restore only its convergence/subscription hunks in the resolver, open-flow,
and Intros coordinator wiring plus their exact tests; preserve Plan 291's
harness files. Then run
`flutter test test/features/introduction/application/resolve_introduction_notification_target_use_case_test.dart test/features/push/application/intro_accept_notification_open_flow_test.dart test/core/notifications/intro_accept_open_coordinator_wiring_test.dart`,
`./scripts/run_test_gates.sh 1to1`, `./scripts/run_test_gates.sh intro`,
`./scripts/check_flutter_analyze_strict.sh`, and `git diff --check`, and
withdraw only the Plan-252 corrective GREEN and the exact-C-convergence live
claim.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-27 | Superseded intermediate — result-only budget | `integration_test/scripts/run_intro_accept_notification_android.dart` | Android runner result wait was first increased to a named 360 s budget | This did not establish shared ownership across adapter/child phases and is not the final implementation contract | superseded by the absolute-deadline GREEN below |
| 2026-07-27 | RED — shared deadline | `test/core/debug/intro_e2e_budget_test.dart` | `flutter test test/core/debug/intro_e2e_budget_test.dart --plain-name 'allocates budget by phase'` failed to compile because `IntroCampaignDeadline` did not exist | Causal RED proves the old fresh-timeout runner had no shared phase/campaign ledger | Implement absolute deadline + named phase allocations |
| 2026-07-27 | RED — acceptance discrimination | `test/core/debug/intro_e2e_runner_test.dart` | `flutter test test/core/debug/intro_e2e_runner_test.dart --plain-name 'waits for notification acceptance event'` failed to compile because the acceptance discriminator, cleanup guard, and child supervisor did not exist | Causal RED pins all reviewed counterexamples before runner changes | Wire explicit acceptance/custody matching and bounded cleanup |
| 2026-07-27 | GREEN — host causal/preservation | Android runner, Sims adapter, `intro_e2e_budget_test.dart`, `intro_e2e_runner_test.dart` | Both focused files passed (7 tests); targeted analysis reported no issues; `bash scripts/test/intro_accept_notification_sims_adapter_contract_test.sh` passed; `git diff --check` passed | Absolute deadline is passed adapter → child; same-phase waits cannot reset it; generic health/replay completion is rejected; timed-out children receive SIGTERM then SIGKILL before restore; late cleanup is single-flight/idempotent | Root execution owner runs `./scripts/run_test_gates.sh intro`, exact live Sims proof, and full analysis at combined closure |
| 2026-07-27 | Live RED — separate Plan-252 exact-anchor seam | `build/sims/operator-inputs/wave4a-intro-anchor-race-report.json`; physical Android `21071FDF600CSC`; emulators `emulator-5558` and `emulator-5560` | build PASS; `intro.accept_notification_campaign` FAIL after one assertion; report SHA-256 `dad8b23c965df1de12302752798e9be390107ca1cdc43a3652421279af3492b2` | The expanded budget reached the cold tap and exposed stream failure/stale B-only convergence state. This is causal evidence for a narrow Plan-252 corrective amendment, not evidence that Plan 291 should change product semantics. | Plan-291 harness GREEN retained; current-source closure pending Plan-252 repair and exact rerun |
| 2026-07-28 | Final corrective/focused PASS | intro budget/runner tests; Plan-252 resolver/open-flow/wiring tests; Sims adapter contracts | budget/runner 8/8; resolver/open-flow/wiring 13/13; relevant adapter contracts PASS | The harness budget and exact-anchor product correction are independently covered while their ownership boundary remains intact | focused/current-source-green | run final live row and remaining closure gates |
| 2026-07-28 | Final coherent-source live PASS | Pixel 6 `21071FDF600CSC`; API-35 emulators `emulator-5558` and `emulator-5560`; `build/sims/operator-inputs/wave4a-intro-pass-report.json` | build PASS plus `intro.accept_notification_campaign` PASS with two assertions: physical-introducer and emulator-introducer; report SHA-256 `85ac10b661e90b2d3bccc5a09117d5962f83fb074eeab24ed9ba94e6d9e45a47`; proof-artifact SHA-256 `87e42b8a657baed90edf445c57016c42b91d76871e422db36e52571cd649660b` | Report and proof share coherent source digest `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e`; the final three-party boundary is green | live-green, not yet Plan-green | finish the explicitly pending closure gates |
| 2026-07-28 | Shared gate PASS | Wave 4A shared gates; strict analysis | `runtime-roots` 20/20 over 1,026 files with trustworthy/no-drift result in 79.75 s; completeness 1,346/1,346; `1to1` 2,441 Flutter plus relay Go gates in 185.83 s; `intro` 300 in 21.10 s; `groups` 3,239 Flutter plus 13 focused Go tests and relay toolchain in 322.03 s; architecture boundaries six tests over 1,026 sources with the 182-dependency/24-placement baseline and zero issues; Sims contracts 38/38 in 1,296.64 s; `./scripts/check_flutter_analyze_strict.sh` exited 0 in 405.8 s with zero errors, warnings, or infos and three reviewed suppression occurrences across three package roots; no causal failure | Available family, inventory, architecture, Sims-contract, and strict-analysis evidence is green | Plan-green remains withheld | await `core-host-all`, final `git diff --check`, Graphify, and Wave aggregate `host-all` |

## Plan-252 Corrective-Amendment Boundary

`W4A-BLOCKERS-AUTH-01` authorizes the reproduced exact-anchor convergence
correction that enabled the final live proof. That correction remains a
narrow amendment to Plan 252: arm the exact acceptance-status observation
before the repository reread, accept only the matching introduction/C
acceptance, keep unrelated/B-only events from satisfying convergence, preserve
the immediate A-to-B open, and retain fail-open timeout behavior. Plan 291 owns
only budget, process, acceptance-discriminator, and cleanup mechanics.

## Current-Source Evidence And Remaining Placeholders

- Plan-252 corrective preservation: resolver/open-flow/wiring 13/13; Plan-291
  budget/runner 8/8; relevant adapter contracts PASS.
- Final live receipt:
  `build/sims/operator-inputs/wave4a-intro-pass-report.json`, SHA-256
  `85ac10b661e90b2d3bccc5a09117d5962f83fb074eeab24ed9ba94e6d9e45a47`;
  proof-artifact SHA-256
  `87e42b8a657baed90edf445c57016c42b91d76871e422db36e52571cd649660b`;
  coherent source digest
  `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e`.
- Shared current-source receipts are PASS with the exact counts and durations
  recorded in the 2026-07-28 progress row above.
- `./scripts/check_flutter_analyze_strict.sh`: **PASS** — exit 0 in 405.8 s;
  zero errors, warnings, or infos; three reviewed suppression occurrences
  across three package roots; no causal failure.
- Remaining placeholders; no Plan-green claim is made:
  - `./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter failures-only`: **running/pending**.
  - Final `git diff --check`: **pending**.
  - Final Wave 4A Graphify refresh: **pending**.
  - Wave 4A aggregate `host-all`: **pending centrally in Plan 289 and the roadmap**.

## Reviewer Findings

Historical verdict: **plan-fixes-required**; **resolved** by the required
updates below. Current closure remains pending only on the explicitly named
final gates.

- L1 clear: source and live evidence support a harness-budget gap, not missing
  relay inputs.
- L2 tighten: TC-01/TC-02 must assert phase-specific elapsed budget and reject
  generic health/replay events as acceptance.
- L3 tighten: cover both the Android runner and the Sims wrapper; neither may
  retain an independent 240-second deadline.
- L4 plan-fix: the preservation gate is `./scripts/run_test_gates.sh intro`,
  not the internal `INTRO_TESTS` array name.
- L5 tighten: timeout and cleanup must be idempotent after a late invitation.

Required updates applied: the actual artifact proof path is named, the gate
command is executable, and late-event cleanup/idempotency is an explicit
acceptance obligation.
