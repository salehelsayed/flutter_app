# Admin Demotion Enforcement Session 01 Plan

Status: accepted

## Planning Progress

- 2026-05-29 04:37:00 CEST | Evidence Collector completed | Files inspected since last update: `lib/features/groups/application/update_group_member_role_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/group_membership_update_listener.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `integration_test/group_admin_metadata_convergence_simulator_test.dart`, `Test-Flight-Improv/test-gate-definitions.md` | Decision/blocker: current host exact Scenario 4 already exists and passes, but the simulator wrapper omits that exact Scenario 4; closure must not rely only on host fake-network proof. | Next action: draft the plan around adding simulator coverage and conditional production fixes only if a RED proof fails.
- 2026-05-29 04:39:00 CEST | Planner completed | Files inspected since last update: `$run-flutter-reliability-sims` skill and `run_with_devices.sh`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart` | Decision/blocker: reliability-sim group dry-run resolves devices and contains command `#86` for `private_admin_demotion_enforcement`; direct host coverage should be paired with that narrow simulator command. | Next action: reviewer sufficiency pass.
- 2026-05-29 04:41:00 CEST | Reviewer completed | Files inspected since last update: `Test-Flight-Improv/test-gate-definitions.md`, `integration_test/group_admin_metadata_convergence_simulator_test.dart`, host Scenario 4 command output | Decision/blocker: plan is sufficient if it requires the exact host Scenario 4, direct use-case/listener tests, the group gate when production group behavior changes, and the narrow simulator closure command; missing simulator wrapper hook is a required test adjustment. | Next action: arbiter classification.
- 2026-05-29 04:43:00 CEST | Arbiter completed | Files inspected since last update: all evidence above | Decision/blocker: no structural blocker remains; accepted difference is that full `./scripts/run_test_gates.sh groups` may be recorded as required only if production code changes, while exact host and simulator Scenario 4 remain required for this session. | Next action: execute.

## real scope

Own the reported group-admin demotion Scenario 4:

1. User A creates a group and adds User B.
2. User A promotes User B to admin.
3. User B updates group metadata and photo.
4. User B adds User C, and User C joins with the latest metadata/photo.
5. A/B/C group messaging still fans out.
6. User A changes the group photo.
7. User A demotes User B.
8. The demotion timeline appears on A, B, and C.
9. Demoted User B cannot edit group details and cannot add User D.
10. Any stale or forged metadata/member-add event from demoted User B is rejected by A and C.

This session may adjust tests and, only if a regression fails, production code in the group role-update fanout, incoming membership-event authorization, metadata edit authorization, or add-member authorization paths. It must not redesign group roles, key rotation, invite acceptance, storage schema, or transport.

## closure bar

The session is closed only when the exact Scenario 4 is proved at host level and at the narrow simulator/device level:

- host fake-network Scenario 4 passes and proves A/B/C convergence, demotion timeline visibility, Bob local permission revocation, Bob stale metadata rejection, and Bob stale member-add rejection;
- simulator wrapper includes the exact Scenario 4 so the one-device integration wrapper is not silently missing this case;
- the narrow `$run-flutter-reliability-sims` group command for `private_admin_demotion_enforcement` is run or, if environment fails, the exact device/env blocker is recorded;
- direct use-case/listener tests covering role, metadata, and member-add authorization pass;
- if production group code changes, the named `groups` gate from `Test-Flight-Improv/test-gate-definitions.md` is also required.

## source of truth

Current code and tests win over older prose. `Test-Flight-Improv/test-gate-definitions.md` defines named gates. `$run-flutter-reliability-sims` defines simulator closure rules and device resolution. The reported user journey is the behavioral source for this plan.

Authoritative files:

- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/group_membership_update_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `integration_test/group_admin_metadata_convergence_simulator_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

## session classification

implementation-ready

## exact problem statement

The reported product failure is that an admin demotion initiated by User A does not become visible to all group members and does not revoke User B's admin authority everywhere. The user-visible failures are:

- B and C do not see the timeline message "User A removed admin from User B";
- B can still edit the group name/description after demotion, and C accepts that update while A does not;
- B can still add User D after demotion.

Expected behavior: demotion must converge to A/B/C, timeline history must be visible to all members, local permission checks must block demoted B, and receive-side authorization must reject any stale demoted-B metadata or member-add event.

Current evidence: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "exact Scenario 4 admin demotion enforcement journey passes"` passes in this worktree. The remaining gap is simulator wrapper coverage and any production fix revealed by running the required direct/simulator gates.

## files and repos to inspect next

- `integration_test/group_admin_metadata_convergence_simulator_test.dart`
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/update_group_member_role_use_case_test.dart`
- `test/features/groups/application/update_group_metadata_use_case_test.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_membership_update_listener.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`

## existing tests covering this area

- `test/features/groups/integration/group_admin_metadata_convergence_test.dart` contains `exact Scenario 4 admin demotion enforcement journey passes`. It currently covers the full reported host fake-network flow.
- `test/features/groups/application/group_message_listener_test.dart` covers unauthorized `member_role_updated`, `group_metadata_updated`, and `members_added` receive-side rejection.
- `test/features/groups/application/update_group_metadata_use_case_test.dart` covers non-admin and demoted local-role rejection.
- `test/features/groups/application/add_group_member_use_case_test.dart` covers add-member authorization.
- `integration_test/scripts/run_group_multi_party_device_real.dart` exposes `private_admin_demotion_enforcement`.
- `integration_test/group_multi_party_device_real_harness.dart` names Scenario 4 Admin Demotion.
- `integration_test/scripts/group_multi_party_device_criteria.dart` verifies Scenario 4 membership and Dana absence.
- `integration_test/group_admin_metadata_convergence_simulator_test.dart` currently omits the exact Scenario 4 host helper from its simulator wrapper.

## regression/tests to add first

Add or adjust `integration_test/group_admin_metadata_convergence_simulator_test.dart` so it runs `runExactScenario4AdminDemotionEnforcementJourney()` as a `testWidgets` case. This is the first change because the host exact Scenario 4 already exists, but simulator closure rules require simulator-backed proof for group membership, invite, metadata/photo, and demotion behavior.

If this new wrapper or the existing host Scenario 4 fails, keep the RED evidence and then fix the smallest production path responsible:

- role demotion fanout/inbox/direct delivery if B or C misses the demotion timeline;
- incoming `member_role_updated` handling if B/C do not update Bob's role or Bob's local `myRole`;
- `updateGroupMetadata` or `addGroupMember` authorization if Bob can still mutate locally after receiving demotion;
- incoming metadata/member-add authorization if A or C accepts stale demoted-B events.

## step-by-step implementation plan

1. Add a `testWidgets` wrapper in `integration_test/group_admin_metadata_convergence_simulator_test.dart` for `runExactScenario4AdminDemotionEnforcementJourney()`.
2. Run the exact host Scenario 4 test. If it fails, fix the failing path before moving on.
3. Run focused direct tests for role, metadata, add-member, and listener authorization. If a direct test fails, classify whether the failure is caused by this session, pre-existing, flaky, unrelated-but-required, or environment/tooling-related before fixing.
4. Run the new simulator wrapper test on the resolved one-device simulator, or use `$run-flutter-reliability-sims` command `#3` if the wrapper is sufficient and not too broad for local closure.
5. Run `$run-flutter-reliability-sims` group `--only 86` for `private_admin_demotion_enforcement`.
6. If any production group file changed, run `./scripts/run_test_gates.sh groups`.
7. Update this plan's `## Execution Progress` section with exact command results and final verdict.

Stop if current code plus added simulator wrapper proves the behavior. Do not invent new group state machines or broad transport changes without a failing required regression.

## risks and edge cases

- Direct P2P delivery can fail; demotion must still be replayable through group inbox and/or device reliability scenario evidence.
- Bob can have stale local admin state before receiving demotion; receive-side authorization on A/C must still reject stale Bob metadata/member-add events.
- Bob's `GroupModel.myRole` must update when Bob is the demoted member.
- Duplicate direct replay and pubsub replay must not duplicate timeline rows.
- Metadata/photo changes and membership changes have separate watermarks; a stale metadata event must not roll back a newer A photo update.
- Simulator/device runs can fail due build/native-asset or simulator environment rather than product behavior; those failures must be classified exactly.

## exact tests and gates to run

Required direct tests:

```bash
flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "exact Scenario 4 admin demotion enforcement journey passes"
flutter test test/features/groups/application/update_group_member_role_use_case_test.dart
flutter test test/features/groups/application/update_group_metadata_use_case_test.dart
flutter test test/features/groups/application/add_group_member_use_case_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "member_role_updated changes role and calls updateConfig" --plain-name "unauthorized group_metadata_updated is ignored" --plain-name "unauthorized members_added is ignored"
```

Required simulator/list commands:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 86
```

Required simulator wrapper after adding Scenario 4:

```bash
flutter test -d <resolved-single-device-id> integration_test/group_admin_metadata_convergence_simulator_test.dart
```

Required only if production group code changes:

```bash
./scripts/run_test_gates.sh groups
```

Formatting/check:

```bash
dart format integration_test/group_admin_metadata_convergence_simulator_test.dart
git diff --check
```

## known-failure interpretation

The earlier concurrent `flutter test` run failed with a native-assets `objective_c.dylib.lipo` move error while another Flutter command held the startup/build lock. Treat that as environment/tooling-related unless it reproduces in a sequential retry. Existing unrelated dirty-work failures outside the files touched by this session must not be classified as this session's regressions.

For named gates, use `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` as source of truth. Known red tests remain documented known failures unless the touched group role/metadata/invite code caused or widened them.

## done criteria

- The simulator wrapper contains exact Scenario 4.
- Direct host Scenario 4 passes.
- Direct role, metadata, add-member, and listener authorization tests pass or have exact unrelated/environment failure classification.
- `$run-flutter-reliability-sims` group `--list` resolves devices and `--only 86` is run with pass evidence, or the exact simulator/device blocker is recorded.
- If production group code changes, `./scripts/run_test_gates.sh groups` is run and passes or has exact unrelated/environment failure classification.
- `git diff --check` passes.
- `## Execution Progress` records exact commands and final verdict.

## scope guard

Non-goals:

- no role model redesign;
- no new database migration;
- no key-rotation or invite-acceptance redesign;
- no broad relay or libp2p changes;
- no UI restyling;
- no full group reliability-sim sweep unless the narrow scenario exposes a reason.

Overengineering would include adding a new membership authority service, changing group type semantics, weakening signed audit validation, making demoted admins silently accepted as legacy admins, or bypassing receive-side authorization to make tests pass.

## accepted differences / intentionally out of scope

- Full `./scripts/run_test_gates.sh groups` is mandatory only if production group behavior changes. If this is test-wrapper-only, exact direct tests plus narrow simulator closure are sufficient.
- The one-device `integration_test/group_admin_metadata_convergence_simulator_test.dart` wrapper is not a substitute for the four-device `private_admin_demotion_enforcement` scenario; both have different value.
- Real-world intermittent direct P2P loss is not solved in this session unless the exact simulator scenario shows a reproducible product failure.

## dependency impact

This closes the admin-demotion authority baseline needed by later group metadata/photo, invited-member onboarding, admin-role-transfer, and private group reliability work. If the exact simulator scenario fails, later work that assumes demotion convergence or demoted-admin rejection should pause until the failing path is fixed and rerun.

## Execution Progress

- 2026-05-29 04:43:20 CEST | Contract extracted | Files inspected or touched: plan artifact and evidence files listed above | Command: none running | Decision/blocker: execution contract is concrete; first implementation step is simulator-wrapper test adjustment | Next action: spawn Executor.
- 2026-05-29 04:45:18 CEST | Executor running | Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/admin-demotion-enforcement-session-01-plan.md`, `integration_test/group_admin_metadata_convergence_simulator_test.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart` | Command: `git status --short`; `rg -n "runExactScenario4AdminDemotionEnforcementJourney|Admin Demotion|Scenario 4" ...` | Decision/blocker: worktree is already dirty with unrelated edits; executor will only touch the plan and simulator wrapper unless required tests expose an in-scope failure | Next action: add the Scenario 4 simulator `testWidgets` wrapper.
- 2026-05-29 04:45:54 CEST | Executor implementation completed | Files inspected or touched: `integration_test/group_admin_metadata_convergence_simulator_test.dart` | Command: `dart format integration_test/group_admin_metadata_convergence_simulator_test.dart` -> passed, formatted 1 file with 0 changed | Decision/blocker: simulator wrapper now includes `runExactScenario4AdminDemotionEnforcementJourney()`; no production code changed by this executor pass | Next action: run required direct tests sequentially.
- 2026-05-29 04:46:28 CEST | Direct test finished | Files inspected or touched: none | Command: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "exact Scenario 4 admin demotion enforcement journey passes"` -> passed, 1 test | Decision/blocker: host exact Scenario 4 remains green | Next action: run use-case authorization tests.
- 2026-05-29 04:46:47 CEST | Direct test finished | Files inspected or touched: none | Command: `flutter test test/features/groups/application/update_group_member_role_use_case_test.dart` -> passed, 15 tests | Decision/blocker: role update use-case coverage remains green | Next action: run metadata update use-case tests.
- 2026-05-29 04:47:03 CEST | Direct test finished | Files inspected or touched: none | Command: `flutter test test/features/groups/application/update_group_metadata_use_case_test.dart` -> passed, 6 tests | Decision/blocker: metadata edit authorization coverage remains green | Next action: run add-member use-case tests.
- 2026-05-29 04:47:17 CEST | Direct test finished | Files inspected or touched: none | Command: `flutter test test/features/groups/application/add_group_member_use_case_test.dart` -> passed, 29 tests | Decision/blocker: add-member authorization coverage remains green | Next action: run focused group message listener authorization tests.
- 2026-05-29 04:47:39 CEST | Direct test triage | Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart` | Command: `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "member_role_updated changes role and calls updateConfig" --plain-name "unauthorized group_metadata_updated is ignored" --plain-name "unauthorized members_added is ignored"` -> failed with 0 tests run; `rg` verified all three test names exist | Decision/blocker: classified as tooling/command-filter semantics because repeated `--plain-name` values were combined too narrowly; no product/test failure and no code fix indicated | Next action: run the same three listener cases individually.
- 2026-05-29 04:48:17 CEST | Direct listener tests finished | Files inspected or touched: none | Commands: `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "member_role_updated changes role and calls updateConfig"` -> passed, 1 test; `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "unauthorized group_metadata_updated is ignored"` -> passed, 1 test; `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "unauthorized members_added is ignored"` -> passed, 1 test | Decision/blocker: listener role update and unauthorized metadata/member-add cases are green; combined-filter failure remains tooling/command invocation only | Next action: run `git diff --check`.
- 2026-05-29 04:48:39 CEST | Diff check finished | Files inspected or touched: none | Command: `git diff --check` -> passed | Decision/blocker: no whitespace errors in current diff | Next action: record executor final verdict.
- 2026-05-29 04:48:39 CEST | Executor final verdict | Files inspected or touched: `integration_test/group_admin_metadata_convergence_simulator_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/admin-demotion-enforcement-session-01-plan.md` | Command: simulator/device commands not run in this executor pass | Decision/blocker: production group code was not changed by this executor, so `./scripts/run_test_gates.sh groups` was not run; leave simulator closure to controller/final gate with exact commands `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --list`, `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only 86`, and `flutter test -d <resolved-single-device-id> integration_test/group_admin_metadata_convergence_simulator_test.dart` | Next action: hand off to QA/controller.
- 2026-05-29 04:52:28 CEST | Local QA fallback completed | Files inspected or touched: `integration_test/group_admin_metadata_convergence_simulator_test.dart`, plan diff, `git diff --name-only` | Command: QA child closed after bounded wait with no review evidence; local review inspected exact diff and direct-test progress | Decision/blocker: no blocking issue in executor work; simulator wrapper adds exact Scenario 4, production code was not changed by this executor pass, direct evidence is sufficient so far, and required simulator/device closure remains pending | Next action: run final simulator/list gates.
- 2026-05-29 04:51:42 CEST | QA Reviewer completed | Files inspected or touched: `integration_test/group_admin_metadata_convergence_simulator_test.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/admin-demotion-enforcement-session-01-plan.md`; touched this progress entry only | Commands: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "exact Scenario 4 admin demotion enforcement journey passes"` -> passed, 1 test; `flutter test test/features/groups/application/update_group_member_role_use_case_test.dart` -> passed, 15 tests; `flutter test test/features/groups/application/update_group_metadata_use_case_test.dart` -> passed, 6 tests; `flutter test test/features/groups/application/add_group_member_use_case_test.dart` -> passed, 29 tests; listener cases run individually -> each passed, 1 test; `git diff --check` -> passed | Decision/blocker: scoped integration-test diff adds the exact Scenario 4 `testWidgets` wrapper and no Executor-attributed production code change is evident; the broader worktree still contains unrelated dirty production files, so final controller should keep relying on scoped files and required gates rather than global cleanliness | Next action: controller runs pending simulator/device evidence: `run_with_devices.sh group --list`, `run_with_devices.sh group --only 86`, and `flutter test -d <resolved-single-device-id> integration_test/group_admin_metadata_convergence_simulator_test.dart`.
- 2026-05-29 04:58:50 CEST | Simulator gate discovery completed | Files inspected or touched: none | Command: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --list` -> passed; command `#86` resolves to `private_admin_demotion_enforcement` with four devices | Decision/blocker: narrow Scenario 4 simulator command is available and device resolution is healthy | Next action: run the one-device wrapper and command `#86`.
- 2026-05-29 04:58:50 CEST | One-device simulator wrapper completed | Files inspected or touched: none | Command: `flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/group_admin_metadata_convergence_simulator_test.dart` -> passed, 3 tests | Decision/blocker: simulator wrapper now executes the exact Scenario 4 alongside the existing wrapper cases | Next action: run four-device `private_admin_demotion_enforcement`.
- 2026-05-29 04:58:50 CEST | Four-device reliability simulator completed | Files inspected or touched: none | Command: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only 86` -> passed; proof reported `private_admin_demotion_enforcement verdicts valid for alice, bob, charlie, dana`; logs: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_admin_demotion_enforcement_VTit5T` | Decision/blocker: required device-level proof for the reported admin-demotion journey is green | Next action: final diff check and verdict.
- 2026-05-29 04:58:50 CEST | Final verdict accepted | Files inspected or touched: `integration_test/group_admin_metadata_convergence_simulator_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/admin-demotion-enforcement-session-01-plan.md` | Commands: `git diff --check` -> passed; broad `./scripts/run_test_gates.sh groups` intentionally not run because production group code was not changed in this session | Decision/blocker: closure bar satisfied by direct host/use-case/listener tests, one-device simulator wrapper, and four-device Scenario 4 reliability proof; no blocking issues remain | Next action: none.
