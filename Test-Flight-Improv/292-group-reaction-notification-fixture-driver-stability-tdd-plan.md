# 292 - Group Reaction Notification Fixture/Driver Stability

Status: implementation-complete / focused-host-green / coherent-source live-green; remaining closure gates pending
Type: Bug
Spec: free-text follow-up from DTR-13 live closure
Classification: implemented harness follow-up; closure pending
Closure tier: device
Owner authorization: `W4A-BLOCKERS-AUTH-01`

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-27 | Planner | group reaction Sims runner, fixture drivers, relay manifest | Relay inputs and fixture setup are valid; selector misses and invitation wait are flaky | Add deterministic selector/fixture diagnostics and rerun proof |
| 2026-07-27 | Reviewer | Orbit FAB/widget, capture driver, Android state guard, criteria tests | Generic top-right selection, empty-review acceptance, repeated cold relaunch, and implicit cleanup ownership were not causal enough | Pin exact semantics; add behavioral seams for bounded recovery, invite discrimination, and cleanup |
| 2026-07-27 | Implementer | current-process Android logcat from the failed live run | Creation preceded creator sendability: the first invite inbox store failed while relay recovery was in progress; `TIME_TO_SENDABLE_BADGE` and the self-store succeeded five seconds later | Gate fixture creation on the current process's exact sendable event, then rerun the live scenario |
| 2026-07-27 | Live closer | physical Android `21071FDF600CSC`; emulator `emulator-5560`; final logcat collection | The corrected four-scenario campaign passed once. A preceding attempt exposed one transient `adb logcat -d` exit 255 after fixture success, so final read-only log collection now has a bounded three-attempt retry and classified terminal failure. | Rerun against the final coherent source, then run the affected family gate. |
| 2026-07-28 | Final live closer | Pixel 6 `21071FDF600CSC`; API-35 `emulator-5560`; final Sims report and proof artifact | The final coherent-source build and all four group/announcement message-plus-reaction assertions passed; authoritative cleanup completed | Retain Plan-green as pending until `core-host-all`, final diff hygiene, Graphify, and Wave aggregate `host-all` finish |

## Problem And Evidence
- Behavior: group reaction notification campaign creates a group, delivers invitation, reacts, and verifies notification on the paired targets.
- Impact: real fixture setup is reached, but emulator selectors (`group_name_field_not_found`, `orbit_create_fab_not_found`) and physical invitation wait fail nondeterministically.
- Confirmed gaps: `integration_test/scripts/capture_group_reaction_notification_device.dart` used a generic top-right clickable selector, accepted Orbit's empty review remnant as invite arrival, force-stopped during repeated projection recovery, and created a group before the creator's current process emitted `TIME_TO_SENDABLE_BADGE`.
- Existing coverage: `test/integration/group_reaction_notification_device_criteria_test.dart` and `integration_test/group_announcement_reaction_notification_proof_test.dart`; the new exact host path `test/core/debug/group_reaction_notification_fixture_test.dart` was required because it is outside the pre-existing criteria family.
- Refuted: missing relay/provider inputs; EC2 relay active and current manifest probe passed.
- Resolved selector ownership: `orbit_create_group_fab` is the exact automation
  semantics identifier on the real Orbit create control. Recovery is one
  bounded resume/back/re-entry sequence and never force-stops the app.

## Graph Grounding Snapshot
- Fingerprint/freshness at planning: `d4a9a72d5be10723`, current at that
  snapshot; the final Wave 4A Graphify refresh remains pending.
- Query: `python3 graphify-arch/tdd_context.py query "group reaction notification campaign fixture selectors invitation wait" --profile tdd --budget 700` (broad), refined around campaign runner and fixture driver.
- Anchors: `integration_test/scripts/run_group_reaction_notification_device.dart`
  and
  `integration_test/scripts/capture_group_reaction_notification_device.dart`;
  direct criteria anchor
  `test/integration/group_reaction_notification_device_criteria_test.dart`.
- Gaps: exact selector ownership requires targeted source search before implementation.

## Scope Contract And Guard
In scope: a stable create-FAB semantics identifier, one bounded non-force-stop
Orbit recovery, current-process sendability precondition, pending-vs-empty
invitation polling, bounded read-only final-log retries, child transient
cleanup, and preservation of outer app-state restoration.
Must preserve: group membership, reaction semantics, notification payload, relay custody, and cleanup.
Hard `Do not`: change group protocol, notification schema, relay deployment, device policy, or DTR-13 composition.
Cleanup ownership: the child removes only request/result files, a left-open status bar, and `.json.pending` proof residue. `AndroidAppStateGuard.restoreAll()` in the outer Sims adapter remains the authoritative idempotent owner for groups, late invitations, app/private state, and notification state.
Deferred: no product behavior; only the explicitly named final closure gates
remain pending.

## Test Contract
| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | FAB selection requires exact `orbit_create_group_fab` semantics and recovery is bounded around one Orbit re-entry | `test/integration/group_reaction_notification_device_criteria_test.dart::{Orbit create FAB exposes its exact automation semantics, create FAB recovery is bounded and re-establishes Orbit once, create FAB recovery stops after its exact bounded probes}` | widget + fake UI dumps | generic top-right selector/repeated relaunch -> exact center or classified bounded miss | restore generic selector or a second recovery -> red | exact Flutter test; AUTO integration |
| TC-02 | Invitation wait discriminates an empty remnant from a real pending invite | `test/core/debug/group_reaction_notification_fixture_test.dart::{invite wait discriminates an empty review from a pending invite, invite wait keeps an empty review pending through its bound}` | host fake projection | empty remnant returned success -> only group/header projection completes | accept exact empty label -> red | exact Flutter test path (outside the prior criteria family) |
| TC-03 | Fixture recovery and cleanup do not churn force-stop; child cleanup is idempotent and outer restoration remains authoritative | `test/core/debug/group_reaction_notification_fixture_test.dart::{transient fixture cleanup is idempotent and attempts every action, outer campaign retains authoritative app-state cleanup in finally}` plus `test/integration/group_reaction_notification_device_criteria_test.dart::group fixture uses exact FAB semantics without force-stop recovery` | host callbacks/source preservation | repeated `_launchAndroid` and implicit ownership -> one resume/back recovery plus child/outer split | call cleanup twice or restore `_launchAndroid` recovery -> red | both exact Flutter test paths |
| TC-04 | Group creation waits for the creator's exact current-process sendable evidence and times out causally | `test/core/debug/group_reaction_notification_fixture_test.dart::{creator readiness accepts only the current-process sendable event, creator readiness times out without treating nearby text as ready}` | fake PID-scoped log reader | live invite raced relay readiness -> exact event passes; nearby prose/absence exhausts bound | accept substring prose or remove wait -> red | exact Flutter test path |
| TC-05 | Real campaign completes on available pair | Sims scenario `groups.reaction_notification_campaign` | physical Android `21071FDF600CSC` + explicit available emulator, automated | runs reached fixture then failed -> group reaction/notification pass and outer cleanup | remove readiness or exact selector -> device red | `./scripts/run_test_gates.sh sims major --only groups.reaction_notification_campaign`; existing classify/scenario |
| TC-06 | A transient final `adb logcat -d` disconnect is retried read-only and a persistent failure remains classified | `test/core/debug/group_reaction_notification_fixture_test.dart::{bounded fixture read retries a transient adb reconnect, bounded fixture read returns the final classified failure}` | host callbacks / fake process reads | one transient exit 255 discarded an otherwise successful fixture -> second read returns evidence; three failures retain the final classified error | remove retry or swallow the final error -> red | exact Flutter test path |

## Implementation Steps
1. Snapshot tree; add TC-01 through TC-04 RED and retain the live readiness-race timestamps.
2. Repair selector ownership/recovery, readiness gating, invitation polling,
   bounded final-log reads, and transient cleanup; preserve fixture schema and
   outer restore ownership.
3. Run focused tests, `GROUP_TESTS`, exact Sims scenario, analysis, hygiene.

## Risks And Blind Spots
- False positive fixture readiness -> TC-02 discriminator.
- Cleanup after partial group creation -> TC-03 receipt asserts removals.
- Emulator/physical asymmetry -> TC-03 pins both IDs and records phase per target.
- Transient ADB reconnect during final evidence capture -> TC-06 retries only
  the read, never the product action.

## Gate Cadence
- Per-plan: focused tests, `GROUP_TESTS`, exact Sims scenario, analysis.
- Full `host-all` belongs to dependency-wave/final closure, not this plan.

## Acceptance Gates
```bash
git status --short
flutter test test/core/debug/group_reaction_notification_fixture_test.dart
flutter test test/integration/group_reaction_notification_device_criteria_test.dart
flutter test test/features/groups/presentation/widgets/expandable_fab_test.dart
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh sims major --only groups.reaction_notification_campaign
# Repository strict analysis supersedes a weaker standalone `flutter analyze`.
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: selector miss or invitation wait lacks bounded phase evidence.
- Availability note: an unavailable Android target or version is N/A under
  repository policy, not an environment blocker; the required live pair was
  available for the recorded run.
- [x] causal RED/GREEN evidence; [x] final coherent-source paired campaign and
  cleanup; [x] focused and affected shared gates recorded; [x] strict analysis;
  [ ] `core-host-all`, final diff hygiene, Graphify, and Wave aggregate
  `host-all`.

## Handoff
- First causal RED: fixture test command above.
- Preservation: `./scripts/run_test_gates.sh groups`.
- Manual registration: existing group reaction scenario; migration: none.
- Boundary closure: physical Android + available Android emulator.

## Exact Inverse Rollback Contract

Restore only the Plan-292 execution-start selector/recovery/readiness/invite/
cleanup/log-read hunks in
`integration_test/scripts/capture_group_reaction_notification_device.dart`,
`lib/features/groups/presentation/widgets/expandable_fab.dart`,
`lib/features/orbit/presentation/screens/orbit_screen.dart`, and
`test/integration/group_reaction_notification_device_criteria_test.dart`;
remove only `test/core/debug/group_reaction_notification_fixture_test.dart`.
Do not restore any shared file wholesale. Preserve group membership and
reaction semantics, notification schema, relay/provider deployment and inputs,
the outer `AndroidAppStateGuard` ownership, all build profiles/defines, DTR-13
composition, and unrelated dirty-tree changes.

After the inverse, run exactly:

```bash
flutter test test/integration/group_reaction_notification_device_criteria_test.dart
flutter test integration_test/group_announcement_reaction_notification_proof_test.dart
flutter test test/features/groups/presentation/widgets/expandable_fab_test.dart
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh runtime-roots
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

The same rollback must withdraw Plan 292's focused-host/Plan-green status and
any current-source group live-row claim from Plan 289, the roadmap, and the
index. The prior four-assertion PASS remains historical only for its recorded
source digest.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-27 | RED — causal host seams | new `test/core/debug/group_reaction_notification_fixture_test.dart`; updated criteria test | `flutter test test/core/debug/group_reaction_notification_fixture_test.dart test/integration/group_reaction_notification_device_criteria_test.dart` -> exit 1; missing readiness, pending-invite, cleanup, exact-FAB/recovery APIs | Compilation RED named each absent seam; no production source had yet changed for this implementation pass | implement the reviewed seams |
| 2026-07-27 | GREEN — exact selector/readiness/invite/cleanup | capture driver; `ExpandableFab`; Orbit screen; both exact tests | initial two-file command -> 43 pass; `flutter test test/features/groups/presentation/widgets/expandable_fab_test.dart` -> 12 pass; targeted five-file `flutter analyze` -> no issues; `git diff --check` -> clean | FAB exposes exact semantics; recovery performs one bounded resume/back sequence without force-stop; creator PID-scoped log must contain exact `TIME_TO_SENDABLE_BADGE`; empty invite remnant cannot pass; transient cleanup is one-shot while the outer guard remains authoritative | exercise the live campaign |
| 2026-07-27 | GREEN — bounded evidence read | capture driver; `group_reaction_notification_fixture_test.dart`; criteria test | combined focused fixture/criteria command -> 45 pass | Final `adb logcat -d` collection retries up to three read-only attempts with 500 ms spacing and preserves the final classified failure; product actions are never redriven | focused-host-green | rerun live row on final coherent source |
| 2026-07-27 | Historical live PASS — superseded as closure evidence by later source changes | physical Android `21071FDF600CSC`; emulator `emulator-5560`; `build/sims/operator-inputs/wave4a-group-pass-report.json` | central build PASS; all four Android group message/reaction notification scenarios PASS; report SHA-256 `58931a97720f0ed726eccc93256fefe6d5574d4a445818260a14a5408b2d4142` | One coherent intermediate snapshot proved exact selector, readiness, invite, reaction, notification, and cleanup behavior | not final current-source evidence because source changed afterward | rerun the same exact row, then `groups` |
| 2026-07-28 | Final coherent-source live PASS | Pixel 6 `21071FDF600CSC`; API-35 `emulator-5560`; `build/sims/operator-inputs/wave4a-group-final-pass-report.json` | build PASS plus `groups.reaction_notification_campaign` PASS with four group/announcement message-plus-reaction assertions; cleanup complete; report SHA-256 `0aa1c02f5f03986a443297424aeeb12422db65d6796f45fd7fb6da7b08c0b116`; proof-artifact SHA-256 `e8b9a8cda9a4539580745006262f5102ff9c062aebecdb67e12b9db51bd8dad5` | Report and proof share coherent source digest `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e`; exact selectors, fixture readiness, invitation, notification/reaction, and cleanup are green on the final current source | live-green, not yet Plan-green | finish the explicitly pending closure gates |
| 2026-07-28 | Focused and shared gate PASS | fixture/criteria/FAB tests; adapter contracts; Wave 4A shared gates; strict analysis | group fixture/criteria/FAB total 57/57; relevant adapter contracts PASS; `runtime-roots` 20/20 over 1,026 files with trustworthy/no-drift result in 79.75 s; completeness 1,346/1,346; `1to1` 2,441 Flutter plus relay Go gates in 185.83 s; `intro` 300 in 21.10 s; `groups` 3,239 Flutter plus 13 focused Go tests and relay toolchain in 322.03 s; architecture boundaries six tests over 1,026 sources with the 182-dependency/24-placement baseline and zero issues; Sims contracts 38/38 in 1,296.64 s; `./scripts/check_flutter_analyze_strict.sh` exited 0 in 405.8 s with zero errors, warnings, or infos and three reviewed suppression occurrences across three package roots; no causal failure | Available focused, family, inventory, architecture, Sims-contract, and strict-analysis evidence is green | Plan-green remains withheld | await `core-host-all`, final `git diff --check`, Graphify, and Wave aggregate `host-all` |

## Current-Source Evidence And Remaining Placeholders

- Final live receipt:
  `build/sims/operator-inputs/wave4a-group-final-pass-report.json`, SHA-256
  `0aa1c02f5f03986a443297424aeeb12422db65d6796f45fd7fb6da7b08c0b116`;
  proof-artifact SHA-256
  `e8b9a8cda9a4539580745006262f5102ff9c062aebecdb67e12b9db51bd8dad5`;
  coherent source digest
  `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e`;
  authoritative cleanup complete.
- Focused/current shared receipts are PASS with the exact counts and durations
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

- L1 clear: the three live captures and current relay attestation support a
  fixture/driver flake classification.
- L2 plan-fix: TC-01 now names the existing criteria test as the insertion point;
  it must assert selector recovery rather than only artifact validation.
- L3 tighten: inspect both emulator and physical-device selector paths and keep
  invitation polling in the shared fixture driver, not only one scenario.
- L4 plan-fix: the family gate is `./scripts/run_test_gates.sh groups`; the
  Sims scenario remains the real boundary command.
- L5 tighten: partial group creation and late invitation cleanup must be
  idempotent and leave no notification claims behind.

Required updates applied: existing test/driver paths and executable gate names
are corrected; cleanup and cross-target selector obligations are explicit.
