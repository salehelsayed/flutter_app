# GM-008 Remove C, Restart, Re-add C Planning

Status: accepted (exact three-iOS-simulator GM-008 proof passed after simulator/Xcode build-state cleanup)

Closure status: `accepted` / `covered`; source matrix row GM-008 is `Covered`.

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 19:17:59 CEST | Planner completed | Current plan draft | Draft plan scopes GM-008 to one restart-between-remove-and-re-add proof and uses the accepted GM multi-party harness without expanding `--scenario all`. | Run Reviewer pass for sufficiency, stale assumptions, missing gates, and overengineering. |
| 2026-05-10 19:19:59 CEST | Reviewer started | Current plan draft | Reviewing mandatory sections, device proof classification, exact command contract, and fixture-overclaim risk. | Patch any sufficiency issues, then run Arbiter pass. |
| 2026-05-10 19:20:28 CEST | Reviewer completed | Current plan draft and live device check notes | Sufficient with minor adjustments: clarify attempted `adb` check, preserve fixture-overclaim warning, and keep physical-device/nightly evidence recommended but not closure-blocking. | Run Arbiter pass and classify remaining issues. |
| 2026-05-10 19:20:58 CEST | Arbiter started | Reviewer findings and current plan | No structural blocker identified entering arbitration. | Classify caveats as blockers, incremental details, or accepted differences, then finalize status. |
| 2026-05-10 19:21:15 CEST | Arbiter completed | Final plan | No structural blockers remain. Fixture-overclaim and physical-device/nightly notes are accepted differences/incremental details, not blockers. | Plan is execution-ready; execute GM-008 only in a later implementation pass. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Command | Decision/blocker | Next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-10 19:23:04 CEST | Contract extraction started | Plan file, `Test-Flight-Improv/test-gate-definitions.md`, `git status --short` | n/a | Dirty snapshot matches controller note: only untracked GM-008 plan artifact is present. | Extract execution contract, then verify device availability before implementation work. |
| 2026-05-10 19:23:44 CEST | Contract extracted | Plan file, `Test-Flight-Improv/test-gate-definitions.md` | n/a | Scope is GM-008 only; add host regression and `gm008` runner/harness/criteria support; product edits only on proven failure; required direct tests, `groups`, `completeness-check`, `git diff --check`, and exact three-simulator relay proof are mandatory unless blocked by fixture/device availability. | Record device availability result, then run isolated Executor pass. |
| 2026-05-10 19:23:44 CEST | Device availability verified | `xcrun simctl list devices`, `flutter devices --machine` | `xcrun simctl list devices`; `flutter devices --machine` | Required simulators are present, booted, and visible to Flutter: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. | Spawn Executor agent with bounded GM-008 contract. |
| 2026-05-10 19:24:18 CEST | Executor spawned/running | Plan file | `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...` | Isolated Executor pass started for GM-008 implementation and required tests/gates. | Wait for Executor result, then spawn QA Reviewer. |
| 2026-05-10 19:25:12 CEST | Executor spawn retry | Plan file | `codex exec ... -a never ...` | First child launch failed before repository work because this `codex exec` subcommand rejected `-a`; no code/test/doc work occurred beyond this progress row. | Relaunch Executor with supported approval config. |
| 2026-05-10 19:26:19 CEST | Executor local pass started | Plan file, `Test-Flight-Improv/test-gate-definitions.md`, `git status --short` | n/a | Current executor request authorizes the isolated local Executor pass for GM-008 only; required commands and no-source-matrix/no-breakdown constraint confirmed. | Verify exact simulator availability, then inspect owner files before implementation. |
| 2026-05-10 19:26:19 CEST | Owner-file inspection starting | GM-008 owner files listed in plan | n/a | Inspection starting before any code/test edits. | Read host regression, fake user helpers, harness, runner, criteria, and criteria tests. |
| 2026-05-10 19:27:00 CEST | Device availability reverified | `xcrun simctl list devices`, `flutter devices --machine` | `xcrun simctl list devices`; `flutter devices --machine` | Exact planned simulators are still booted and visible to Flutter: Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. | Continue owner-file inspection. |
| 2026-05-10 19:28:30 CEST | Owner-file inspection completed | `test/features/groups/integration/group_membership_smoke_test.dart`, `test/shared/fakes/group_test_user.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart` | n/a | Existing GM-006/GM-007 host and device proofs cover remove/re-add without Charlie restart; runner/criteria/harness support direct `gm001`-`gm007` only; `--scenario all` remains GM-001/GM-002. A small test-only restart helper is needed to recreate Charlie listener/runtime while retaining persisted repositories in the host test. | Add GM-008 host regression first. |
| 2026-05-10 19:29:07 CEST | Host regression implementation started | `test/shared/fakes/group_test_user.dart`, `test/features/groups/integration/group_membership_smoke_test.dart` | n/a | Adding test-only restart helper and GM-008 host regression before runner/criteria work. | Run the required GM-008 direct host test after edits. |
| 2026-05-10 19:30:56 CEST | Host regression implementation completed | `test/shared/fakes/group_test_user.dart`, `test/features/groups/integration/group_membership_smoke_test.dart` | `dart format test/shared/fakes/group_test_user.dart test/features/groups/integration/group_membership_smoke_test.dart` | GM-008 host proof added with Charlie runtime restart, removed-window exclusion, current epoch re-add, and exactly-once post-readd delivery checks. | Run required direct test 1. |
| 2026-05-10 19:30:56 CEST | Direct test 1 started | `test/features/groups/integration/group_membership_smoke_test.dart`, `test/shared/fakes/group_test_user.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'` | Validating the new host regression before extending device criteria/runner/harness. | Record pass/fail, then continue or patch blocker. |
| 2026-05-10 19:32:04 CEST | Direct test 1 failed | `test/features/groups/integration/group_membership_smoke_test.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'` | Failed because the test captured `removedAt` before setup, causing the remove event to be treated as stale; Charlie still had epoch-1 key state. This is a test timestamp bug, not product evidence. | Patch the host test to timestamp removal at the actual remove boundary and rerun direct test 1. |
| 2026-05-10 19:32:37 CEST | Direct test 1 rerun started | `test/features/groups/integration/group_membership_smoke_test.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'` | Removal timestamp now reflects the actual remove boundary and post-wait membership cleanup is asserted. | Record pass/fail, then continue or patch blocker. |
| 2026-05-10 19:33:12 CEST | Direct test 1 rerun failed | `test/features/groups/integration/group_membership_smoke_test.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'` | The intended timestamp move had not landed in the GM-008 block; the same stale-event failure left Charlie's group present. | Move `removedAt`/`rejoinKeyCreatedAt` inside the actual remove boundary and rerun direct test 1. |
| 2026-05-10 19:33:12 CEST | Direct test 1 second rerun started | `test/features/groups/integration/group_membership_smoke_test.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'` | GM-008 block now computes removal/readd timestamps immediately before `removeMember`. | Record pass/fail, then continue or patch blocker. |
| 2026-05-10 19:33:50 CEST | Direct test 1 second rerun failed | `test/features/groups/integration/group_membership_smoke_test.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'` | Compile failure from an accidental variable move in adjacent GM-007 plus duplicate GM-008 timestamp declarations; no product behavior implicated. | Restore GM-007 timestamps, keep GM-008 boundary timestamps, and rerun direct test 1. |
| 2026-05-10 19:33:50 CEST | Direct test 1 third rerun started | `test/features/groups/integration/group_membership_smoke_test.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'` | Adjacent GM-007 timestamp declarations restored and GM-008 duplicate declarations removed. | Record pass/fail, then continue or patch blocker. |
| 2026-05-10 19:35:08 CEST | Direct test 1 passed | `test/features/groups/integration/group_membership_smoke_test.dart`, `test/shared/fakes/group_test_user.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'` | PASS. Host GM-008 proof passes with no product changes. | Extend GM-008 criteria, runner, and device harness surfaces. |
| 2026-05-10 19:35:08 CEST | Device proof implementation started | `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart` | n/a | Adding direct `gm008` support only; preserving `--scenario all` as GM-001/GM-002. | Run criteria test after edits, then remaining required gates. |
| 2026-05-10 19:40:46 CEST | Device proof implementation completed | `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart` | `dart format integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/shared/fakes/group_test_user.dart test/features/groups/integration/group_membership_smoke_test.dart` | Added direct `gm008` requirement, criteria, positive/negative tests, orchestrator relaunch flow, and harness role branches; `--scenario all` remains unchanged. | Run required direct test 2. |
| 2026-05-10 19:40:46 CEST | Direct test 2 started | `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart` | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` | Validating GM-008 criteria acceptance and rejection cases. | Record pass/fail, then continue with full host suite. |
| 2026-05-10 19:41:13 CEST | Direct test 2 passed | `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart` | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` | PASS. Criteria now accepts valid GM-008 and rejects missing restart proof, leakage, stale epoch, delivery gaps, and convergence gaps. | Run required direct test 3. |
| 2026-05-10 19:41:13 CEST | Direct test 3 started | `test/features/groups/integration/group_membership_smoke_test.dart`, `test/shared/fakes/group_test_user.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` | Validating the full membership smoke suite after adding GM-008 and the restart helper. | Record pass/fail, then continue with member removal integration suite. |
| 2026-05-10 19:41:44 CEST | Direct test 3 passed | `test/features/groups/integration/group_membership_smoke_test.dart`, `test/shared/fakes/group_test_user.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` | PASS. Full membership smoke suite passed. | Run required direct test 4. |
| 2026-05-10 19:41:44 CEST | Direct test 4 started | `test/features/groups/application/member_removal_integration_test.dart` | `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart` | Validating adjacent member removal integration behavior. | Record pass/fail, then continue with new member onboarding suite. |
| 2026-05-10 19:42:09 CEST | Direct test 4 passed | `test/features/groups/application/member_removal_integration_test.dart` | `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart` | PASS. Adjacent member removal integration suite passed. | Run required direct test 5. |
| 2026-05-10 19:42:09 CEST | Direct test 5 started | `test/features/groups/integration/group_new_member_onboarding_test.dart` | `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` | Validating new member onboarding behavior after GM-008 re-add proof changes. | Record pass/fail, then continue with startup rejoin suite. |
| 2026-05-10 19:42:31 CEST | Direct test 5 passed | `test/features/groups/integration/group_new_member_onboarding_test.dart` | `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` | PASS. New member onboarding suite passed. | Run required direct test 6. |
| 2026-05-10 19:42:31 CEST | Direct test 6 started | `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | Validating adjacent startup rejoin behavior. | Record pass/fail, then continue with targeted analyzer. |
| 2026-05-10 19:42:59 CEST | Direct test 6 passed | `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | PASS. Startup rejoin smoke suite passed. | Run required targeted analyzer. |
| 2026-05-10 19:42:59 CEST | Direct test 7 started | `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart` | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart` | Checking compile/analyzer shape for touched GM-008 proof files. | Record pass/fail, then run exact three-simulator proof. |
| 2026-05-10 19:44:02 CEST | Direct test 7 found analyzer info | `test/integration/group_multi_party_device_criteria_test.dart` | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart` | Analyzer exited with one info: use a null-aware map entry in the `_received` test helper. | Patch lint and rerun direct test 7. |
| 2026-05-10 19:44:30 CEST | Direct test 7 rerun started | `test/integration/group_multi_party_device_criteria_test.dart` | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart` | Null-aware map entry lint patched and formatted. | Record pass/fail, then run exact three-simulator proof. |
| 2026-05-10 19:45:00 CEST | Direct test 7 rerun failed | `test/integration/group_multi_party_device_criteria_test.dart` | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart` | Analyzer warned that the null-aware map entry checked a non-null key, not the nullable value. | Patch helper with a null-check pattern and rerun direct test 7. |
| 2026-05-10 19:45:24 CEST | Direct test 7 second rerun started | `test/integration/group_multi_party_device_criteria_test.dart` | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart` | Optional `keyEpoch` map entry now uses a null-check pattern and is formatted. | Record pass/fail, then run exact three-simulator proof. |
| 2026-05-10 19:45:53 CEST | Direct test 7 second rerun found analyzer info | `test/integration/group_multi_party_device_criteria_test.dart` | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart` | Null-check pattern still triggered `use_null_aware_elements`. | Patch helper with null-aware spread and rerun direct test 7. |
| 2026-05-10 19:46:23 CEST | Direct test 7 third rerun started | `test/integration/group_multi_party_device_criteria_test.dart` | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart` | Optional `keyEpoch` map entry now uses a null-aware spread. | Record pass/fail, then run exact three-simulator proof. |
| 2026-05-10 19:46:47 CEST | Direct test 7 passed | `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart` | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart` | PASS. Targeted analyzer reports no issues. | Run required exact GM-008 relay/device proof on the three planned simulators. |
| 2026-05-10 19:46:47 CEST | Direct test 8 started | `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart` | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm008 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` | Starting exact three-simulator GM-008 proof with planned Alice/Bob/Charlie device IDs. | Record pass/fail/blocker and artifact path, then continue with named gates if not hard-blocked. |
| 2026-05-10 19:29:03 CEST | Controller scope check completed | `git status --short`, out-of-scope breakdown metadata/content, Codex session logs | `rg "Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown" ~/.codex/sessions/2026/05/10 -g '*.jsonl'` | Untracked `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` was created by separate Codex session `019e12ec-a988-7de1-97a0-6a73d75ffa61`, not GM-008 Executor session `019e12ec-8920-7ef3-ad4b-4b620db0d3de`; leave it untouched as another agent's out-of-scope artifact. | Continue GM-008 execution and ignore that unrelated untracked file in final status. |
| 2026-05-10 19:50:10 CEST | Direct test 8 first attempt failed | `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm008_tzLFkc/alice.log` | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm008 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` | FAILED ATTEMPT (superseded). The shared dir is `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm008_tzLFkc` and contains only `alice.log`; no GM-008 orchestrator verdict was produced. Alice build failed with `Share Extension_dependency_info.dat: unknown opcode in file` plus Xcode interrupt errors, then the driver attached to a stale app/session reporting `scenario=gm007 role=charlie run=1778422910998` on the Alice simulator. This is not trustworthy GM-008 product evidence, and no active GM-008 runner process remains. | Continue runnable host gates; this failed attempt is superseded by the cleanup and passing exact simulator rerun recorded below. |
| 2026-05-10 19:50:10 CEST | Gate 9 started | `scripts/run_test_gates.sh`, groups gate | `./scripts/run_test_gates.sh groups` | Running the required groups gate after the first direct device proof failure; host verification remains feasible. | Record pass/fail, then run completeness-check if not blocked. |
| 2026-05-10 19:51:25 CEST | Gate 9 passed | `scripts/run_test_gates.sh`, groups gate | `./scripts/run_test_gates.sh groups` | PASS. Group Messaging Gate completed with all tests passed. | Run required completeness-check gate. |
| 2026-05-10 19:51:25 CEST | Gate 10 started | `scripts/run_test_gates.sh`, completeness-check gate | `./scripts/run_test_gates.sh completeness-check` | Running the required completeness-check gate after the groups gate. | Record pass/fail, then run `git diff --check`. |
| 2026-05-10 19:51:46 CEST | Gate 10 passed | `scripts/run_test_gates.sh`, completeness-check gate | `./scripts/run_test_gates.sh completeness-check` | PASS. Completeness check reports `731/731` test files classified. | Run required `git diff --check`. |
| 2026-05-10 19:51:46 CEST | Gate 11 started | repository diff hygiene | `git diff --check` | Running final diff whitespace/conflict-marker hygiene check. | Record pass/fail, then record final Executor result. |
| 2026-05-10 19:52:28 CEST | Gate 11 passed | repository diff hygiene | `git diff --check` | PASS. `git diff --check` reported no whitespace or conflict-marker issues after restoring incidental Xcode `info.plist` timestamp metadata from the device attempt. | Record final Executor result. |
| 2026-05-10 19:52:28 CEST | Executor result recorded | `test/shared/fakes/group_test_user.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, this GM-008 plan | n/a | EXECUTOR RESULT: GM-008 host regression, criteria validation, direct runner support, and harness proof branches were implemented with no product-file changes and no Go fallback. Direct tests 1-7, `groups`, `completeness-check`, and `git diff --check` passed. The first Direct test 8 attempt failed from Xcode build/driver stale-session contamination; artifact dir contains only partial `alice.log`, not a GM-008 orchestrator verdict. Source matrix and session-breakdown closure state were not updated at that time; unrelated untracked `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` remains untouched. | Hand off for QA Reviewer pass with the first-attempt device proof failure explicitly retained. |
| 2026-05-10 19:54:00 CEST | QA Reviewer spawned/running | Plan file, Executor result, repository diff, required test/gate evidence, partial device log | `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...` | Fresh QA Reviewer pass starting. QA must verify GM-008 scope, implementation coherence, test/gate evidence, device blocker classification, and out-of-scope artifact attribution without editing files. | Wait for QA result, then either run a bounded fix pass or record final QA/final verdict. |
| 2026-05-10 19:58:41 CEST | QA Reviewer completed | `/tmp/gm008_qa_result.md`, repository diff, touched proof files, partial device log | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart`; `git diff --check` | QA verdict at that time was `pass-with-external-blocker`. QA found no blocking code/test issues, confirmed scope is GM-008 only, no product files changed, `--scenario all` preserved, source matrix/breakdown closure untouched, and the unrelated untracked breakdown remains out of scope. QA reran targeted analyzer and diff hygiene; both passed. | No fix pass needed from QA; record final QA and interim execution verdict. |
| 2026-05-10 19:58:41 CEST | Fix pass not required | QA report | n/a | No blocking implementation findings were returned by QA. Remaining blocker is the required GM-008 device proof artifact, not a fixable code/test issue from this pass. | Record final QA result. |
| 2026-05-10 19:58:41 CEST | Final QA recorded | `/tmp/gm008_qa_result.md` | n/a | Final QA result is `pass-with-external-blocker`; implementation is code/test acceptable but GM-008 cannot close without a trustworthy `ok: true` device verdict. | Write final execution verdict. |
| 2026-05-10 19:58:41 CEST | Superseded interim verdict written | This GM-008 plan | n/a | INTERIM EXECUTION VERDICT: not accepted at that time. Host/criteria/runner/harness implementation passed QA and all runnable gates, but the first exact Direct test 8 attempt did not produce a GM-008 orchestrator verdict because the device run hit Xcode DerivedData build failure and stale GM-007/Charlie session contamination. | Superseded by the simulator/Xcode cleanup and passing exact simulator rerun recorded below. |
| 2026-05-10 20:17:30 CEST | Direct test 8 recovery cleanup started | Xcode DerivedData, `build/ios`, exact three target iOS simulators | `find ~/Library/Developer/Xcode/DerivedData -name '*Share Extension_dependency_info.dat'`; `xcrun simctl terminate/uninstall`; `xcrun simctl shutdown/boot`; `rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-* ~/Library/Developer/Xcode/DerivedData/Pods-* build/ios ios/build` | Confirmed the bad dependency file was under `DerivedData/Runner-*`; removed Runner/Pods DerivedData and local iOS build output, uninstalled `com.mknoon.app`, `com.mknoon.app.ShareExtension`, and `com.mknoon.app.NotificationService` from the exact Alice/Bob/Charlie simulators, and rebooted those simulators. The interrupted GM-009 plan artifact was also removed before continuing GM-008. | Rerun the exact GM-008 three-simulator proof; do not advance to GM-009. |
| 2026-05-10 20:28:22 CEST | Direct test 8 recovery passed | `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm008_OwsAQ5` | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm008 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` | PASS. Exact simulator proof produced `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm008_OwsAQ5/gmp_1778437132542_gm008_orchestrator_verdict.json` with `scenario: gm008`, `ok: true`, and `gm008 verdicts valid for alice, bob, charlie`. Alice/Bob/Charlie role verdicts all passed on the planned simulator IDs. | Correct final execution verdict and closure docs from interim hold to accepted/covered. |
| 2026-05-10 20:30:00 CEST | Final verdict corrected | This GM-008 plan, source matrix row GM-008, breakdown GM-008 rows | n/a | FINAL EXECUTION VERDICT: ACCEPTED. The prior simulator/Xcode build-state blocker was fixed locally and the required exact three-simulator proof now passes. | Keep GM-009 and later rows open; no final program verdict yet. |

## Execution Verdict

Final execution verdict: `accepted`.

Code/test QA result: `pass-with-clean-recovery`. GM-008 host proof, criteria, direct runner support, and harness branches remain acceptable within this plan's scope, with no product-file changes and no Go fallback.

Recovered proof: the required exact three-iOS-simulator relay command passed after clearing Xcode/Simulator build state and stale app sessions. Artifact directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm008_OwsAQ5`. Orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm008_OwsAQ5/gmp_1778437132542_gm008_orchestrator_verdict.json` records `scenario: gm008`, `ok: true`, and `gm008 verdicts valid for alice, bob, charlie`.

Role evidence summary:
- Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`: removed Charlie, distributed the current epoch to remaining members only, sent the removed-window message while Charlie was restarted/absent, re-added Charlie, received Charlie's post-readd message exactly once, and ended at epoch `2` with A/B/C membership.
- Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`: observed the Charlie restart boundary, received Alice's removed-window message exactly once, received Alice and Charlie post-readd messages exactly once, and ended at epoch `2` with A/B/C membership.
- Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`: restarted after removal, had no group/key before re-add, rejected pre-readd send, rejoined from the current persisted epoch, stored zero removed-window plaintext, had no stale epoch after re-add, published post-readd successfully, received Alice's post-readd message exactly once, and ended at epoch `2` with A/B/C membership.

Files changed in this execution:
- `test/shared/fakes/group_test_user.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-008-plan.md`

Exact tests/gates:
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'`
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
- PASS: `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`
- PASS: `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- PASS: `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- PASS after simulator/Xcode cleanup: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm008 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- PASS: `./scripts/run_test_gates.sh groups`
- PASS: `./scripts/run_test_gates.sh completeness-check` (`731/731` classified)
- PASS: `git diff --check`
- PASS by QA rerun: the targeted `dart analyze ...` command above
- PASS by QA rerun: `git diff --check`

Scope note: source matrix row GM-008 and canonical session-breakdown GM-008 closure state were updated after the recovered simulator proof passed. The untracked `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` was attributed to separate session `019e12ec-a988-7de1-97a0-6a73d75ffa61`, not this GM-008 execution, and was left untouched.

## Closure Audit

Closure verdict: `accepted` / `covered`. The implementation and QA pass are coherent for GM-008, and the required exact three-simulator proof now passes with a trustworthy GM-008 orchestrator verdict.

Docs updated by closure:
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-008-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-008

Closure evidence:
- GM-008 targeted host regression passed.
- GM-008 criteria test passed.
- Full `group_membership_smoke_test.dart` passed.
- `member_removal_integration_test.dart` passed.
- `group_new_member_onboarding_test.dart` passed.
- `group_startup_rejoin_smoke_test.dart` passed.
- Targeted analyzer for the GM-008 harness, runner, criteria, criteria tests, and membership smoke files passed.
- Exact three-iOS-simulator GM-008 proof passed with verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm008_OwsAQ5/gmp_1778437132542_gm008_orchestrator_verdict.json`.
- `./scripts/run_test_gates.sh groups` passed.
- `./scripts/run_test_gates.sh completeness-check` passed with `731/731` classified.
- `git diff --check` passed.
- QA reran the targeted analyzer and `git diff --check`; both passed.

Recovered blocker details: the earlier `simulator/Xcode build-state contamination` was fixed by clearing Runner/Pods DerivedData and `build/ios`, uninstalling the app/extension bundles from the exact three target simulators, rebooting the simulators, and rerunning the exact GM-008 command. The accepted closure depends on the new `gm008` verdict path above, not on the earlier partial failed directory.

Closure scope guard: no product files changed in this plan, no Go fallback was run, no final program verdict was written, and GM-009 or later rows were not updated.

## real scope

Own exactly source row `GM-008`: remove Charlie, restart at least Charlie's app/node between removal and re-add, re-add Charlie with the current persisted config/key epoch, then send both directions after rejoin.

In scope:
- Add or verify a row-owned GM-008 host/app regression in `test/features/groups/integration/group_membership_smoke_test.dart`.
- Extend only the accepted GM multi-party proof surfaces for direct `gm008` support:
  - `integration_test/scripts/run_group_multi_party_device_real.dart`
  - `integration_test/group_multi_party_device_real_harness.dart`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
- Prove the GM-008 closure contract with the existing default relay env and three distinct Flutter iOS simulator roles A/B/C.
- Make product changes only if the row-owned proof exposes a real failure in persisted config/key rejoin after restart.

Out of scope:
- Duplicate add/remove idempotence, stale out-of-order membership events, role changes, media, notifications, physical-device orchestration, multi-relay failover, broad `--scenario all` expansion, and source matrix/breakdown closure edits during execution.
- Reopening GM-001 through GM-007 accepted evidence unless GM-008 finds an actual regression in shared helper behavior.
- Changing Go runtime restart semantics unless a direct GM-008 failure proves app-level persisted config/key rejoin is blocked by `pubsub.go`.

## closure bar

GM-008 is good enough only when row-specific evidence proves:
- Alice/Bob/Charlie initially join the same private group with shared epoch/config.
- Alice removes Charlie, Bob converges to a member list excluding Charlie, and Charlie loses active group access.
- Alice rotates/distributes the current epoch to remaining members only.
- Charlie's app/node is stopped and relaunched after removal and before re-add; the proof records this restart boundary explicitly.
- Charlie's post-restart rejoin does not depend on in-memory Go `PrevKey`/grace state from before restart. The accepted proof must show Charlie re-enters from row-specific persisted/current config and key material, has current final epoch, and has no removed-window plaintext.
- Alice re-adds Charlie under the current epoch/config, then Alice and Charlie both send post-readd messages.
- Alice, Bob, and Charlie all converge on final member list A/B/C and the same current key epoch.
- Bob receives Alice removed-window traffic while Charlie is absent; Charlie receives no removed-window plaintext.
- Alice and Bob receive Charlie's post-readd message exactly once, and Bob/Charlie receive Alice's post-readd message exactly once.
- Exact three-simulator proof writes an orchestrator verdict JSON for `scenario: gm008`, `ok: true`, and per-role verdicts validated by GM-008 criteria.
- Direct tests, named gates, and hygiene checks in this plan pass.

## source of truth

Authoritative inputs:
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GM-008`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` ordered row `GM-008`.
- `Test-Flight-Improv/test-gate-definitions.md` for named gates and optional/manual device orchestrator classification.
- Current code/tests in the GM membership, restart, runner, criteria, and relay/device harness files.
- Accepted GM-006/GM-007 closure evidence as the nearest remove/re-add precedent.
- GL-017/GL-018 plans/tests only for the restart premise: Stop clears runtime state, and app restart must explicitly rejoin from persisted state.

Conflict rule:
- Current code/tests beat stale prose.
- The GM-008 source row wins unless exact repo proof already covers restart-between-remove-and-readd; current evidence does not.
- `test-gate-definitions.md` controls named gate scope.

## session classification

`implementation-ready`

Rationale: GM-008 entered planning as `needs_repo_evidence` / `evidence-gated`, and repo evidence showed missing row-owned proof support. The implementation remained proof-first and product-code-conditional. This session added the row-owned proof support and later closed GM-008 with an accepted exact three-simulator verdict.

## exact problem statement

GM-008 was open before this plan. GM-006 proved immediate remove/re-add with current epoch, and GM-007 proved a longer removed-window visibility boundary, but neither proved the restart boundary where in-memory key-rotation grace or prior Go topic state is unavailable between remove and re-add. The accepted GM-008 proof now covers that restart boundary.

User-visible behavior to prove or improve:
- A removed member who restarts before being re-added can rejoin with the current persisted config/key epoch and resume bidirectional delivery.
- The restarted member does not regain removed-window plaintext and does not send under stale membership/key state.
- Remaining members keep delivery during the removed window and accept the re-added member only under the current config/device binding.

Behavior that must stay unchanged:
- Existing GM-004 through GM-007 removal, offline removal, immediate re-add, and history-boundary semantics.
- Current fail-closed send behavior for removed members.
- Existing key-rotation and signed membership-event validation unless GM-008 proof exposes a concrete defect.

## files and repos to inspect next

Production/app seams:
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`

Host/test seams:
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`

Device proof seams:
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Fallback only if direct proof fails below Flutter/app state:
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

## existing tests covering this area

Covered adjacent behavior:
- `group_membership_smoke_test.dart::GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic` covers remove/re-add without restart.
- `group_membership_smoke_test.dart::GM-007 preserves allowed pre-removal and post-readd messages while excluding removed-window messages` covers removed-window history boundaries without restart.
- GM-004/GM-005 source rows and harness support cover online/offline removal and removed-member non-access.
- `group_startup_rejoin_smoke_test.dart::GL-018 restart rejoin restores all persisted groups exactly once and resumes delivery` covers generic app-layer restart rejoin, not remove/re-add membership mutation.
- `group_messaging_smoke_test.dart::message is received after app restart with rejoin` and `group_resume_recovery_test.dart::watchdog restart rejoins topics and receives subsequent live messages` cover adjacent restart receive paths.

Missing for GM-008:
- No GM-008-named host regression.
- No `gm008` scenario requirement or GM-008-specific criteria validation.
- No `--scenario gm008` runner support.
- No GM-008 branch in `integration_test/group_multi_party_device_real_harness.dart`.
- No exact relay/device verdict artifact for restart-between-remove-and-readd.

## regression/tests to add first

Add proof before product fixes:
- Host regression in `test/features/groups/integration/group_membership_smoke_test.dart`, named:
  - `GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch`
- Criteria tests in `test/integration/group_multi_party_device_criteria_test.dart`:
  - accepts complete GM-008 Alice/Bob/Charlie verdicts;
  - rejects missing restart proof;
  - rejects Charlie removed-window plaintext;
  - rejects Charlie stale epoch after restart/re-add;
  - rejects missing Charlie post-readd send delivery to Alice/Bob;
  - rejects missing Alice post-readd delivery to Bob/Charlie;
  - rejects missing final member/key convergence.

If the host regression passes by adding proof only, keep production untouched. If it fails because current app code cannot re-add after restart using persisted/current config/key, patch the smallest implicated application seam and rerun the full command set.

## step-by-step implementation plan

1. Reconfirm `git status --short` and do not revert unrelated changes.
2. Add the GM-008 host regression by adapting the GM-006/GM-007 pattern:
   - Create Alice/Bob/Charlie with shared initial group/key.
   - Remove Charlie and wait for Bob to exclude Charlie and Charlie to lose active group access.
   - Rotate to the current rejoin epoch for Alice/Bob only; assert Charlie is not a key distribution target.
   - Simulate Charlie restart after removal and before re-add. Prefer a test-local restart helper that disposes/recreates Charlie's listener/runtime while preserving only the state that a real app restart would persist; if the existing fake cannot represent that cleanly, add the smallest test helper in `test/shared/fakes/group_test_user.dart`.
   - Send one Alice removed-window message and prove Bob receives it while restarted Charlie does not.
   - Re-add Charlie from current config/key epoch, not from an old in-memory key/grace object.
   - Send Charlie-to-Alice/Bob and Alice-to-Bob/Charlie post-readd messages; assert exactly-once received tuples and final A/B/C epoch convergence.
3. Extend `group_multi_party_device_criteria.dart`:
   - Add `_gm008Requirement` with roles `alice`, `bob`, `charlie`.
   - Add `gm008` to supported scenario errors and dispatch.
   - Expected messages: `aliceDuringCharlieRestartedRemoval` to Bob only, `charlieAfterRestartReadd` to Alice/Bob, and `aliceAfterRestartReadd` to Bob/Charlie.
   - Add `_validateGm008RestartReaddProof` requiring explicit restart fields and final convergence.
4. Add positive and negative criteria tests in `group_multi_party_device_criteria_test.dart`.
5. Extend `run_group_multi_party_device_real.dart` for direct `--scenario gm008` only:
   - Keep `--scenario all` unchanged.
   - Add a GM-008 custom runner path if Charlie must be terminated and relaunched between remove and re-add.
   - Reuse the existing `restoreMnemonic`, `mode`, log, verdict, and terminate helpers from GM-003/GM-005 instead of adding broad orchestration.
6. Extend `group_multi_party_device_real_harness.dart` for GM-008:
   - Add roles map entry for `gm008`.
   - Add Alice/Bob/Charlie role branches.
   - Alice creates group, removes Charlie, rotates key, waits for Charlie restart-ready/relaunch boundary, re-adds Charlie with current config/key, sends after re-add, and records proof.
   - Bob verifies removed-window delivery, final member/key convergence, Charlie post-readd delivery, and Alice post-readd delivery.
   - Charlie records self-removal, exits for orchestrator restart, relaunches with restored identity, proves no removed-window plaintext, imports/accepts current readd config/key, sends post-readd, receives Alice post-readd, and records restart proof.
7. Run direct RED/GREEN commands in the exact order listed below. Stop before production edits if only proof support was missing and all behavior passes.
8. If product failure occurs, patch only the smallest app seam named by the failure. Re-run the failing direct test first, then the full GM-008 test/gate set.
9. Do not update the source matrix or breakdown during execution. Closure updates belong to a later closure pass after evidence exists.

## risks and edge cases

- `flutter drive` relaunch can reset the app container. GM-008 criteria must record whether Charlie rejoined from actual persisted app storage or a row-owned restart fixture, and closure must not overclaim OS-level persistence if the harness used fixture restore.
- A false positive could pass by reusing an in-memory `GroupKeyInfo.PrevKey` or stale fixture. Criteria must require final current epoch, no stale epoch after re-add, and no removed-window plaintext.
- Charlie self-removal may delete local group/key state; re-add must install the current epoch/config cleanly.
- Alice/Bob must keep delivery while Charlie is absent.
- Three-simulator relay proof can fail due simulator install, process termination, relay reachability, Xcode build state, or app launch flake. Treat repeatable simulator fixture unavailability as an execution-time fixture blocker with exact simulator/log evidence, not as product failure.
- If restart support requires relaunching Alice instead of Charlie to satisfy the row, keep it as an implementation-time adjustment only after Charlie-restart proof is judged insufficient by criteria.

## exact tests and gates to run

Direct host proof:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'
```

Criteria guard:

```sh
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
```

Adjacent host suites:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Targeted analyzer for touched proof files:

```sh
dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart
```

Exact relay/device proof:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm008 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gates and hygiene:

```sh
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Conditional Go fallback only if a failing GM-008 proof points into Go group runtime/key handling:

```sh
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery|PublishGroupMessage' -count=1)
```

## known-failure interpretation

- Do not classify existing unrelated dirty files or unrelated red tests as GM-008 regressions.
- If `--scenario gm008` is unsupported before implementation, that is expected RED proof support, not a product failure.
- If the device orchestrator fails before launching all required roles because a listed simulator is unavailable or cannot install/launch the app, record it as a fixture/device failure for execution evidence, clean the simulator/Xcode state where appropriate, and rerun before current closure.
- If host GM-006/GM-007 regress while adding GM-008 proof support, treat that as in-scope because shared remove/re-add proof helpers were touched.
- `--scenario all` currently expands only to GM-001/GM-002 in this runner; do not treat that accepted operator limitation as a GM-008 failure.

## done criteria

- This plan remains scoped to GM-008 and says `Status: execution-ready` before implementation starts.
- A GM-008-named host regression exists and passes.
- GM-008 criteria accept a valid verdict and reject missing restart, stale epoch, removed-window leakage, missing post-readd delivery, and incomplete convergence.
- Direct `--scenario gm008` relay/device proof passes on three distinct iOS simulator ids with the default relay env and records an `ok: true` orchestrator verdict path.
- Required direct tests, named gates, and `git diff --check` pass, or execution records a precise simulator/Xcode fixture blocker without closing the source row.
- Source matrix and breakdown are not marked covered until a separate closure pass cites exact GM-008 evidence.

## scope guard

Do not:
- Broaden into GM-009 through GM-012 duplicate/out-of-order membership rows.
- Add physical-device orchestration or require Android.
- Expand `--scenario all`.
- Rework the full GM harness architecture or introduce a new orchestration framework.
- Touch source matrix/breakdown closure state during execution.
- Patch Go/libp2p unless GM-008 direct proof demonstrates a Go-layer defect.
- Close GM-008 from GM-006/GM-007 or GL-017/GL-018 evidence alone.

Overengineering boundary: the right implementation is one row-named host proof plus one direct `gm008` multi-party device scenario, reusing existing runner/criteria patterns.

## accepted differences / intentionally out of scope

- GM-008 may close with a Charlie-restart proof if it explicitly records the restart boundary and current epoch rejoin. Restarting every peer is not required by the source row because it says all peers restart or Charlie restarts.
- If the current Flutter driver relaunch path resets the app container, a row-owned fixture restore can be accepted only as Flutter-app/device proof of restart-without-in-memory-state, not as proof of OS persistent-storage survival. The closure note must state this difference.
- Real physical iOS/Android devices, multi-relay failover, notifications, media, and stale out-of-order event ordering remain separate work.
- `GM-008` should use direct `--scenario gm008`; `--scenario all` operator convenience remains intentionally unchanged.

## dependency impact

- GM-009 through GM-012 should continue to treat duplicate/out-of-order remove/re-add semantics as unresolved until their own rows run.
- Later group reliability rows may rely on GM-008 only after closure records exact host, criteria, and device verdict evidence.
- If GM-008 exposes a product gap in persisted config/key rejoin after restart, later remove/re-add rows should pause until the narrow fix and GM-008 gates pass.

## Device/Relay Proof Profile

Classification: `three-party/simulator-lab` with relay-backed Flutter app proof. It is not host-only, not single-device, not paired-device, not multi-relay, not OS-notification, and not simulator-fixture-blocked at planning time.

Live availability checks run during planning:
- `flutter devices --machine`: available supported targets include Pixel 6 `21071FDF600CSC`, physical iPhone `00008030-001A6D2801BB802E`, booted iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`, plus macOS and Chrome.
- `xcrun simctl list devices available`: confirms the four relevant iOS 26.1 simulators are booted.
- `adb devices`: attempted via `command -v adb`; result was `adb not found`. Android is not needed for this iOS simulator-based GM proof.

Planned role/device mapping:
- Alice/A: `38FECA55-03C1-4907-BD9D-8E64BF8E3469` (`iPhone 17 Pro`, booted)
- Bob/B: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`, booted)
- Charlie/C: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`, booted)
- Spare: `1B098DFF-6294-407A-A209-BBF360893485` (`iPhone 16e`, booted)

Relay env:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
```

Script args and env expectations:
- External command uses `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm008 -d <alice,bob,charlie>`.
- Runner-internal Flutter defines should include `GROUP_MULTI_PARTY_SCENARIO=gm008`, `GROUP_MULTI_PARTY_ROLE=<alice|bob|charlie>`, `GROUP_MULTI_PARTY_RUN_ID=<runId>`, `GROUP_MULTI_PARTY_MODE=proof` or a GM-008-specific restart mode, optional `GROUP_MULTI_PARTY_RESTORE_MNEMONIC=<charlie mnemonic>` for relaunch, `E2E_SHARED_DIR=<temp dir>`, and `E2E_DB_NAME=group_multi_party_gm008_<runId>_<role>.db`.
- The direct device run is required closure evidence for GM-008 because the matrix requires fake network, integration/E2E, regression, and release gate evidence, and this row explicitly mentions restart/app and multi-party group behavior.
- A single `FLUTTER_DEVICE_ID` is not sufficient for closure. GM-008 needs three distinct role devices passed through the runner `-d` list. `FLUTTER_DEVICE_ID` may be useful for unrelated single-device direct tests but cannot close this row.
- Physical-device and nightly evidence remain recommended follow-up confidence, not structural closure blockers for this session unless the implementation phase chooses to claim them.

## Reviewer findings

- Sufficiency: sufficient with minor adjustments.
- Missing files/tests/gates: none structurally. The plan includes host regression, criteria tests, direct three-simulator proof, groups gate, completeness-check, and hygiene. Conditional Go tests are correctly scoped to Go-layer failures only.
- Stale or incorrect assumptions: the plan now avoids overclaiming OS persistent-storage survival when the Flutter driver relaunch path restores a row fixture.
- Overengineering: none after keeping `--scenario all`, physical-device orchestration, Android, multi-relay failover, and GM-009 through GM-012 out of scope.
- Decomposition: narrow enough for one session. The GM-008 host proof, criteria, runner, and direct device scenario are one coherent proof surface.
- Minimum needed for sufficiency: keep the explicit restart proof fields, current-epoch convergence checks, direct `--scenario gm008` evidence, and fixture-overclaim caveat.

## Arbiter decision

- Structural blockers: none.
- Incremental details intentionally deferred: physical-device and nightly evidence remain recommended confidence only; `--scenario all` expansion remains operator convenience outside this row.
- Accepted differences intentionally left unchanged: a Charlie-restart proof is sufficient for the source row if it records the restart boundary and current-epoch rejoin; fixture restore may prove restart-without-in-memory-state but must not be documented as OS persistent-storage survival.
- Final classification: `execution-ready`.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-006-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-007-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-017-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-018-plan.md`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

## Why this is safe to implement now

The plan has an explicit single-row scope, regression-first proof, named direct tests and gates, device/relay closure profile, fixture caveat, scope guard, stop rule, and doc-scoped closure bar. It does not ask implementation to touch source matrix or breakdown closure state, and it keeps product changes conditional on a failing GM-008 proof rather than assuming a behavior defect.
