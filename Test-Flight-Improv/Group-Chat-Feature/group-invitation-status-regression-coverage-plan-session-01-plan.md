# Group Invitation Status Regression Coverage Plan Session 01

Status: accepted_with_explicit_follow_up

Source doc: `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`

Breakdown artifact: `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-breakdown.md`

Session row: `01` | Group invitation status stale re-invite coverage, fix, and four-simulator proof | `evidence-gated`

## Planning Progress

- 2026-05-09T10:16:53Z - Evidence Collector started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-breakdown.md`, `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`, `git status --short`. Decision/blocker: target session and intended plan path confirmed; worktree already dirty and must be treated as pre-existing context. Next action: inspect gate docs and likely code/test entry points before drafting.
- 2026-05-09T10:25:00Z - Evidence Collector completed; Planner started. Files inspected since last update: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`, `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`, `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`, `lib/features/groups/domain/repositories/group_message_repository.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, `integration_test/scripts/run_group_multi_device_real.dart`, `integration_test/group_multi_device_real_harness.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/_current-test-map.md`, and relevant dirty diffs. Decision/blocker: current dirty work already adds a preliminary durable `member_joined` overlay and accepted-member tests, but not the stale re-invite guard, full label matrix, or four-simulator proof. Next action: write the execution-safe session plan.
- 2026-05-09T10:31:00Z - Planner completed. Files inspected since last update: `lib/features/groups/application/record_group_invite_delivery_attempts.dart`, `lib/features/groups/application/resend_group_invite_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`. Decision/blocker: existing invite attempts expose `attemptedAt` and `updatedAt`, so the production fix can stay in `GroupInfoWired` without a repository migration unless implementation evidence disproves that. Next action: reviewer sufficiency pass.
- 2026-05-09T10:34:00Z - Reviewer completed. Files inspected since last update: draft plan content against mandatory constraints. Decision/blocker: sufficient with adjustments to call out dirty-worktree ownership, simulator availability limits, runner creation fallback, and review expectations. Next action: arbiter classification.
- 2026-05-09T10:36:00Z - Arbiter completed. Files inspected since last update: reviewer findings and final plan. Decision/blocker: no structural blockers remain; incremental details are recorded as execution guidance. Next action: hand off this plan to execution.

## Execution Progress

- 2026-05-09T10:23:15Z - Contract extraction started. Files inspected or touched since last update: `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-01-plan.md`, `git status --short`, dirty diffs for `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `Test-Flight-Improv/_current-test-map.md`, and `pubspec.yaml`. Decision/blocker: execution contract is concrete; dirty worktree includes pre-existing owner-file edits and an unrelated `pubspec.yaml` version bump that must be preserved. Next action: extract exact scope, owner files, tests, gates, non-goals, and simulator proof requirements before spawning Executor.
- 2026-05-09T10:23:15Z - Contract extraction completed. Files inspected or touched since last update: same session plan and dirty diffs. Decision/blocker: scope is limited to `GroupInfoWired` invite-status resolution, `group_info_wired_test.dart` stale re-invite and six-label matrix coverage, optional repo-owned four-simulator runner/harness, and discoverability docs only if new coverage needs it; required gates are `flutter test test/features/groups/presentation/group_info_wired_test.dart`, `flutter test test/features/groups/application/group_message_listener_test.dart`, `./scripts/run_test_gates.sh groups`, `git diff --check`, plus the exact four-simulator runner after device availability checks if available. Next action: spawn isolated Executor.
- 2026-05-09T10:24:28Z - Executor local pass started. Files inspected or touched since last update: full plan contract, `git status --short`, dirty diffs for `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `Test-Flight-Improv/_current-test-map.md`, and `pubspec.yaml`. Decision/blocker: current environment exposes no child-agent spawn tool, and the user explicitly requested the Executor role for this bounded pass; proceeding sequentially in this Executor context. Existing dirty edits are preserved, including the unrelated `pubspec.yaml` version bump. Next action: inspect code-entry files, add the stale re-invite and six-label matrix tests, then narrow the invite status loader.
- 2026-05-09T10:26:35Z - Host regression stage in progress. Files inspected or touched since last update: `test/features/groups/presentation/group_info_wired_test.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/screens/group_info_screen.dart`, invite attempt/message repository interfaces and fakes. Decision/blocker: added stale removal/re-invite widget coverage and deterministic six-label matrix coverage on top of the pre-existing accepted-member tests. Next action: run the stale re-invite widget test against the current broad overlay before editing production logic.
- 2026-05-09T10:27:50Z - Host regression RED check completed. Files inspected or touched since last update: `test/features/groups/presentation/group_info_wired_test.dart`. Command: `flutter test test/features/groups/presentation/group_info_wired_test.dart --plain-name "does not let stale member_joined evidence override a current re-invite"`. Outcome: failed as expected before the production fix; `Invite sent` was absent because stale join overlay still won. Next action: update `GroupInfoWired` invite status loading to compare join evidence against removal and current invite attempt timestamps.
- 2026-05-09T10:28:31Z - Implementation stage completed. Files inspected or touched since last update: `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: `_loadInviteStatusesByPeerId` now reads timestamp-bearing attempts, overlays `Joined` only when `member_joined` evidence is after removal evidence and not older than a current non-joined attempt, and removes stale explicit joined rows invalidated by later removal; label text and UI widgets were not changed. Next action: run the focused stale re-invite widget test after the fix, then add/wire simulator runner files.
- 2026-05-09T10:28:56Z - Focused post-fix validation completed. Files inspected or touched since last update: `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`. Command: `flutter test test/features/groups/presentation/group_info_wired_test.dart --plain-name "does not let stale member_joined evidence override a current re-invite"`. Outcome: passed. Next action: add the scoped four-simulator matrix runner and harness, then run required gates.
- 2026-05-09T10:23:15Z - Executor spawned/running. Files inspected or touched since last update: this plan file. Decision/blocker: spawned isolated Executor `019e0c43-deb3-7003-ac6e-a6b441a78308` with required model `gpt-5.5` and reasoning effort `xhigh`; no implementation edits made by controller. Next action: wait bounded interval for Executor completion evidence.
- 2026-05-09T10:31:05Z - Executor bounded wait stopped by controller. Files inspected or touched since last update: `git diff --stat`, this plan file, `test/features/groups/presentation/group_info_wired_test.dart`, and `lib/features/groups/presentation/screens/group_info_wired.dart`. Decision/blocker: the first execution child produced scoped host tests, the production status-loader fix, and focused post-fix validation, then produced no runner/gate/final-verdict progress for several minutes; four-simulator runner/classification, required gates, QA review, and final execution verdict remain unfinished. Next action: spawn a fresh narrower execution child for the same session.
- 2026-05-09T10:32:44Z - Recovery contract extraction started. Files inspected or touched since last update: this plan file, current dirty diffs for `GroupInfoWired`, `group_info_wired_test.dart`, `_current-test-map.md`, `pubspec.yaml`, `integration_test/group_invite_status_matrix_harness.dart`, and `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: first child's host regression and production fix are present; `pubspec.yaml` remains unrelated pre-existing dirty state; the repo-owned four-simulator runner script is still missing while the harness exists untracked. Next action: spawn a narrower isolated Executor to add/verify the runner, run required gates, update discoverability docs, and record simulator classification.
- 2026-05-09T10:33:33Z - Recovery Executor spawned/running. Files inspected or touched since last update: this plan file. Decision/blocker: spawned isolated Executor `019e0c4c-a3e0-7a31-b842-e4829686f669` with required model `gpt-5.5` and reasoning effort `xhigh`; controller made no code/test changes. Next action: wait bounded interval for runner/doc/gate completion evidence.
- 2026-05-09T10:34:19Z - Recovery Executor runner/doc stage started. Files inspected or touched since last update: `git status --short`, `git diff --stat`, this plan file, `integration_test/group_invite_status_matrix_harness.dart`, `integration_test/scripts/run_group_multi_device_real.dart`, `integration_test/scripts/`, `Test-Flight-Improv/_current-test-map.md`, and `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: the harness exists untracked and is a seeded creator-side `GroupInfoWired` display proof; `integration_test/scripts/run_group_invite_status_matrix_sim.dart` is absent; no edits have been made to the unrelated `pubspec.yaml` version bump. Next action: add the narrow four-device runner script, update discoverability docs, then run required gates with plan entries before and after each attempt.
- 2026-05-09T10:37:25Z - Recovery Executor runner/doc stage completed. Files inspected or touched since last update: `integration_test/scripts/run_group_invite_status_matrix_sim.dart`, `integration_test/group_invite_status_matrix_harness.dart`, `Test-Flight-Improv/_current-test-map.md`, `Test-Flight-Improv/test-gate-definitions.md`, and this plan file. Command: `dart format integration_test/scripts/run_group_invite_status_matrix_sim.dart integration_test/group_invite_status_matrix_harness.dart`. Outcome: added a four-device runner that launches the seeded matrix harness for creator, two accepted-member roles, and one pending/unaccepted role; formatted the runner and harness; classified the runner as Nightly / Release Pool and Optional / Manual simulator evidence without widening named gates or claiming relay/testpeer lifecycle proof. Next action: run required host gate `flutter test test/features/groups/presentation/group_info_wired_test.dart`.
- 2026-05-09T10:37:48Z - Required host gate started. Files inspected or touched since last update: this plan file. Command: `flutter test test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: running the direct `GroupInfoWired` regression suite after runner/doc updates. Next action: record exact outcome.
- 2026-05-09T10:38:25Z - Required host gate completed. Files inspected or touched since last update: `test/features/groups/presentation/group_info_wired_test.dart` via test runner and this plan file. Command: `flutter test test/features/groups/presentation/group_info_wired_test.dart`. Outcome: passed, `00:03 +35: All tests passed!` after dependency resolution. Next action: run required host gate `flutter test test/features/groups/application/group_message_listener_test.dart`.
- 2026-05-09T10:38:40Z - Required host gate started. Files inspected or touched since last update: this plan file. Command: `flutter test test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: running listener-side durable join/status-marking regression suite to confirm the status-loader change did not require listener changes. Next action: record exact outcome.
- 2026-05-09T10:39:03Z - Required host gate completed. Files inspected or touched since last update: `test/features/groups/application/group_message_listener_test.dart` via test runner and this plan file. Command: `flutter test test/features/groups/application/group_message_listener_test.dart`. Outcome: passed, `00:06 +95: All tests passed!` after dependency resolution. Next action: run required named group gate `./scripts/run_test_gates.sh groups`.
- 2026-05-09T10:39:16Z - Required named gate started. Files inspected or touched since last update: this plan file. Command: `./scripts/run_test_gates.sh groups`. Decision/blocker: running the frozen group gate exactly as required. Next action: record exact outcome and classify any failure before fixes.
- 2026-05-09T10:39:45Z - Required named gate completed. Files inspected or touched since last update: group gate files via `./scripts/run_test_gates.sh groups` and this plan file. Command: `./scripts/run_test_gates.sh groups`. Outcome: passed, `00:10 +103: All tests passed!` after dependency resolution. Next action: run required whitespace gate `git diff --check`.
- 2026-05-09T10:39:55Z - Required diff gate started. Files inspected or touched since last update: this plan file. Command: `git diff --check`. Decision/blocker: checking all current dirty tracked and untracked patch content for whitespace errors. Next action: record exact outcome.
- 2026-05-09T10:40:09Z - Required diff gate completed. Files inspected or touched since last update: current diff via git and this plan file. Command: `git diff --check`. Outcome: passed with no output. Next action: run required device availability command `flutter devices --machine`.
- 2026-05-09T10:40:22Z - Required device availability check started. Files inspected or touched since last update: this plan file. Command: `flutter devices --machine`. Decision/blocker: checking whether Flutter sees the four required simulator IDs before the matrix runner. Next action: record exact outcome and observed device IDs.
- 2026-05-09T10:40:48Z - Required device availability check completed. Files inspected or touched since last update: Flutter device list and this plan file. Command: `flutter devices --machine`. Outcome: passed; Flutter reported the required supported iOS simulator IDs `38FECA55-03C1-4907-BD9D-8E64BF8E3469` (`iPhone 17 Pro`), `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`), `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`), and `1B098DFF-6294-407A-A209-BBF360893485` (`iPhone 16e`). Next action: run required `xcrun simctl list devices available` availability check.
- 2026-05-09T10:41:00Z - Required simulator availability check started. Files inspected or touched since last update: this plan file. Command: `xcrun simctl list devices available`. Decision/blocker: checking CoreSimulator availability and boot state for the required four simulator IDs. Next action: record exact outcome.
- 2026-05-09T10:41:17Z - Required simulator availability check completed. Files inspected or touched since last update: CoreSimulator device list and this plan file. Command: `xcrun simctl list devices available`. Outcome: passed; CoreSimulator reported the required iOS 26.1 simulator IDs as Booted: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `1B098DFF-6294-407A-A209-BBF360893485`. Next action: run required four-simulator matrix command.
- 2026-05-09T10:41:35Z - Required simulator matrix started. Files inspected or touched since last update: this plan file. Command: `dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`. Decision/blocker: running the repo-owned four-device seeded creator-side `GroupInfoWired` display proof; relay/testpeer lifecycle proof is intentionally not claimed by this harness. Next action: record exact outcome, logs, and classification.
- 2026-05-09T10:44:06Z - Required simulator matrix attempt completed with runner failure. Files inspected or touched since last update: simulator runner logs and this plan file. Command: `dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`. Outcome: failed before harness assertions; runner shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_invite_status_matrix_7S1A9H`; creator, accepted-one, and pending roles reached `Running Xcode build...`, then logged `Failed to build iOS app`, `Uncategorized (Xcode): Exited with status code 65`, `Could not build the application for the simulator`, and `Application failed to start. Will not run test. Quitting.` The runner then waited for missing verdict files and had to be terminated (`kill 21949 22023`), exposing a runner fail-fast issue. Classification: simulator proof not established; immediate session-caused runner issue is fail-fast behavior after role process exit, while the underlying app-start blocker is Xcode status 65 before product UI ran. Next action: fix the runner to fail fast when a role exits before writing a verdict, format it, then rerun the required simulator command.
- 2026-05-09T10:44:46Z - Simulator runner fix stage started. Files inspected or touched since last update: `integration_test/scripts/run_group_invite_status_matrix_sim.dart` and this plan file. Decision/blocker: fixing session-owned runner behavior exposed by the first simulator attempt by running roles sequentially and detecting process exit before verdict files, without changing product scope. Next action: patch and format the runner, then rerun the required simulator command.
- 2026-05-09T10:45:34Z - Simulator runner fix stage completed. Files inspected or touched since last update: `integration_test/scripts/run_group_invite_status_matrix_sim.dart` and this plan file. Command: `dart format integration_test/scripts/run_group_invite_status_matrix_sim.dart`. Outcome: runner now starts roles sequentially and uses verdict-or-process-exit detection so an app build/start failure exits cleanly with the role log path instead of waiting for missing verdict files. Next action: rerun the required simulator matrix command.
- 2026-05-09T10:45:55Z - Required simulator matrix rerun started. Files inspected or touched since last update: this plan file. Command: `dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`. Decision/blocker: rerunning exact required command after runner fail-fast fix; proof remains seeded creator-side display evidence only unless harness verdicts pass. Next action: record exact outcome and classification.
- 2026-05-09T10:52:56Z - Required simulator matrix rerun completed. Files inspected or touched since last update: simulator runner logs/verdicts and this plan file. Command: `dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`. Outcome: passed. Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_invite_status_matrix_eordpJ`. Creator role passed and wrote `creatorMatrixPass: true` with labels `Invite sent`, `Invite queued`, `Needs resend`, `Cannot send`, `Joined`, and `Invite unknown`; accepted-one, accepted-two, and pending-unaccepted roles passed with `roleAttachPass: true`; all verdicts reported `displayProof: seeded_group_info_wired` and `relayLifecycleProof: false`. Classification: simulator display proof passed for seeded creator-side Group Info UI on four requested simulators; real relay/testpeer lifecycle proof remains not claimed by this runner/harness. Next action: rerun `git diff --check` after post-diff runner and plan edits.
- 2026-05-09T10:53:51Z - Required final diff gate started. Files inspected or touched since last update: this plan file. Command: `git diff --check`. Decision/blocker: rerunning after the simulator runner fail-fast patch and execution-progress edits. Next action: record exact outcome.
- 2026-05-09T10:54:12Z - Required final diff gate completed. Files inspected or touched since last update: current diff via git and this plan file. Command: `git diff --check`. Outcome: passed with no output. Next action: inspect final diff/status and write Executor result summary.
- 2026-05-09T10:55:27Z - Executor final cleanup completed. Files inspected or touched since last update: `git status --short`, `git diff --stat`, `info.plist`, and this plan file. Decision/blocker: restored the Xcode-generated `info.plist` `LastAccessedDate` change from the simulator run; no matrix/flutter drive processes remained running; unrelated dirty `pubspec.yaml` version bump is preserved. Next action: hand off for QA review.
- 2026-05-09T10:56:24Z - Recovery Executor completed; QA handoff started. Files inspected or touched since last update: Executor final summary and this plan file. Decision/blocker: Executor reported required direct tests, group gate, `git diff --check`, live availability checks, and the four-simulator seeded UI matrix passing after fixing the runner wait behavior; simulator classification remains seeded creator-side `GroupInfoWired` display proof with `relayLifecycleProof: false`, not real relay/testpeer lifecycle proof. Next action: spawn isolated QA Reviewer to verify scope, evidence, docs, and final verdict sufficiency.
- 2026-05-09T10:56:47Z - QA Reviewer spawned/running. Files inspected or touched since last update: this plan file. Decision/blocker: spawned isolated QA Reviewer `019e0c61-edc1-7220-af8f-62005477a67d` with required model `gpt-5.5` and reasoning effort `xhigh`; QA is review-only and must classify blocking versus non-blocking findings. Next action: wait bounded interval for QA sufficiency verdict.
- 2026-05-09T11:00:07Z - QA Reviewer completed and final execution verdict written. Files inspected or touched since last update: QA reviewer result, this plan file, `git status --short`, and final diff inventory. Decision/blocker: QA found no blocking issues, confirmed host coverage, timestamp-aware status logic, discoverability docs, required command evidence, and truthful simulator proof language; remaining real relay/testpeer lifecycle proof is an explicit non-blocking follow-up because this scoped runner records `relayLifecycleProof: false`. Next action: return final session outcome.

## Executor Result Summary

Final Executor result: `accepted_with_explicit_follow_up`.

Files changed for this session now present in the worktree:

- `lib/features/groups/presentation/screens/group_info_wired.dart` - first executor's stale join/re-invite status-loader fix remains in place.
- `test/features/groups/presentation/group_info_wired_test.dart` - first executor's stale re-invite, accepted-member `Joined`, and six-label matrix coverage remains in place.
- `integration_test/group_invite_status_matrix_harness.dart` - added/verified seeded four-role `GroupInfoWired` matrix harness.
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart` - added four-device runner, then fixed it to run roles sequentially and fail fast if a role exits before writing a verdict.
- `Test-Flight-Improv/_current-test-map.md` - group invite-status direct host coverage and the simulator runner are discoverable.
- `Test-Flight-Improv/test-gate-definitions.md` - the simulator runner is classified as Optional / Manual simulator evidence outside named gates.
- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-01-plan.md` - execution evidence and this result summary.

Commands and outcomes:

- `flutter test test/features/groups/presentation/group_info_wired_test.dart` - passed, `00:03 +35: All tests passed!`.
- `flutter test test/features/groups/application/group_message_listener_test.dart` - passed, `00:06 +95: All tests passed!`.
- `./scripts/run_test_gates.sh groups` - passed, `00:10 +103: All tests passed!`.
- `git diff --check` - passed with no output before simulator proof and again after runner/plan updates.
- `flutter devices --machine` - passed; Flutter listed all four required supported iOS simulators.
- `xcrun simctl list devices available` - passed; CoreSimulator listed all four required IDs as Booted.
- First `dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485` attempt - failed before harness assertions with Xcode status 65 on concurrent role startup and exposed missing runner fail-fast handling; fixed in the runner.
- Rerun of the same simulator command - passed. Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_invite_status_matrix_eordpJ`.

Simulator classification:

- Passed: seeded creator-side `GroupInfoWired` display proof on the four requested simulators. Creator verdict included `creatorMatrixPass: true` and all six labels; accepted-one, accepted-two, and pending-unaccepted verdicts included `roleAttachPass: true`.
- Not claimed: real relay/testpeer lifecycle proof. Every simulator verdict reported `relayLifecycleProof: false`, by design for this scoped runner/harness.

Unresolved issues:

- No blocking issue remains for the session's required host gates, discoverability docs, or seeded four-simulator creator-side display proof.
- Non-blocking follow-up: a separate real relay/testpeer lifecycle simulator journey would be needed if future acceptance requires organic multi-device invite acceptance rather than seeded display proof.

## Final Execution Verdict

Verdict: `accepted_with_explicit_follow_up`.

QA result: no blocking issues. The session satisfies the required stale re-invite regression, accepted-member preservation coverage, six-label host matrix, timestamp-aware `GroupInfoWired` fix, required direct/named gates, `git diff --check`, live simulator availability checks, discoverability docs, and four-simulator seeded creator-side `GroupInfoWired` display proof.

Simulator proof classification: passed as seeded creator-side Members invite-status display proof on the four requested simulators. It does not claim real relay/testpeer lifecycle proof; the runner and verdict files intentionally report `relayLifecycleProof: false`.

Residual follow-up: real relay/testpeer invite lifecycle proof remains outside this session and should only be added if a future acceptance bar requires organic multi-device invite acceptance instead of seeded display proof.

## Final verdict

This plan is execution-safe as one evidence-gated implementation session.

The host regression and production fix are ready to implement. The four-simulator proof is runnable only if the runner exists after implementation and the four simulator IDs remain available; if either condition fails because of environment or a missing non-repo fixture, execution must record the exact blocker instead of claiming proof.

## final plan

Execute one session in this fixed internal order:

1. Host regressions.
2. Production stale join overlay fix.
3. Four-simulator display proof.

Do not split this into separate implementation sessions unless execution discovers a true prerequisite blocker, such as a missing external relay/testpeer fixture that cannot be created inside this repo.

## real scope

This session owns stale group-invite status display for the creator's Group Info Members list.

In scope:

- Add a stale re-invite regression showing an old `member_joined` event must not make a newly re-invited pending member display `Joined`.
- Add a deterministic host/widget matrix for all six visible invite status labels: `Invite sent`, `Invite queued`, `Needs resend`, `Cannot send`, `Joined`, and `Invite unknown`.
- Narrowly update `GroupInfoWired` status loading so durable join evidence is trusted only when it is current relative to removal evidence and current invite attempt timestamps.
- Preserve accepted-member `Joined` rendering, including the existing missing-attempt-row fallback.
- Add or wire a four-iOS-simulator runner and harness that proves creator-side Members UI display for accepted and failed, pending, or unaccepted invitees.
- Update only the relevant discoverability docs if execution adds or changes tests/runners.

Out of scope:

- Redesigning Group Info, Members rows, roles, labels, invite policy, transport retry, group key repair, group media delivery, push notifications, or database schema.
- Rewriting the existing two-device runner in place when a narrow new four-device runner is sufficient.
- Changing `pubspec.yaml` or app version as part of this session.

## closure bar

Good enough means all of these are true:

- The stale re-invite regression exists and proves current invite status wins over stale historical join evidence.
- Accepted members with current join evidence still render `Joined`, with and without an invite attempt row.
- One deterministic host/widget test covers all six visible labels.
- The production fix is limited to invite status resolution and does not alter visible copy or transport semantics.
- The four-simulator command either passes with creator-side UI evidence or fails with actionable logs and a truthful blocker classification.
- `Test-Flight-Improv/_current-test-map.md`, `Test-Flight-Improv/test-gate-definitions.md`, or relevant simulator docs are updated only when needed to keep the new coverage findable.

## source of truth

Current code and direct tests win over stale prose. If docs and test scripts disagree, `scripts/run_test_gates.sh` wins for named gates.

Primary source artifacts:

- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`

Primary code and tests:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`

## session classification

`evidence-gated`

The host regression and production fix are implementation-ready. Final acceptance is evidence-gated by four live iOS simulators and by the repo-local runner/harness being available after implementation. The plan stays safe because it requires explicit blocker evidence instead of silently downgrading the simulator proof.

## exact problem statement

The current dirty worktree already adds a preliminary `GroupInfoWired` overlay that maps any member with durable `member_joined` timeline evidence to `GroupInviteDeliveryStatus.joined`. That protects accepted members, but it is too broad for a remove and re-invite lifecycle.

If a member joined in the past, was removed, and was later re-invited, the old `member_joined` event must not make the current invite row display `Joined` before the member accepts the new invite. The creator-visible failure is a stale Members badge in Group Info, such as `Joined` instead of `Invite sent`.

The fix must keep the useful fallback: when a member has valid current `member_joined` evidence but no invite attempt row, Group Info should still show `Joined`.

## Owner files

Primary owner files for execution:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart`
- `integration_test/group_invite_status_matrix_harness.dart`
- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Conditional owner files:

- `test/features/groups/presentation/group_info_screen_test.dart` only if badge rendering or label mapping changes.
- `test/features/groups/application/group_message_listener_test.dart` only if listener-side `member_joined` persistence or invite status marking changes.
- `lib/features/groups/application/record_group_invite_delivery_attempts.dart` or `lib/features/groups/application/resend_group_invite_use_case.dart` only if implementation proves current invite attempts do not get fresh `attemptedAt` evidence.
- Relevant simulator journey docs only if the new runner is intentionally classified there.

Expected non-owner files:

- `pubspec.yaml` is already dirty before this plan and should not be changed for this session.
- Unrelated Test-Flight docs should not be rewritten.

## Dirty Worktree Handling

The dirty snapshot recorded before this plan existed was:

- `M Test-Flight-Improv/_current-test-map.md`
- `M lib/features/groups/presentation/screens/group_info_wired.dart`
- `M pubspec.yaml`
- `M test/features/groups/presentation/group_info_wired_test.dart`
- `?? Test-Flight-Improv/93-group-system-push-preview-sanitization-plan.md`
- `?? Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-breakdown.md`
- `?? Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`

Execution must treat those edits as pre-existing user or prior-agent work. Do not revert them. Before editing, inspect the current diff for every owner file, then layer the missing stale re-invite regression, matrix coverage, and simulator proof on top of the existing changes.

The existing dirty diff already appears to add:

- A `_loadInviteStatusesByPeerId` helper in `GroupInfoWired`.
- Durable `member_joined` overlay behavior.
- Accepted-member `Joined` tests and helper updates in `group_info_wired_test.dart`.
- A `_current-test-map.md` note for `group_info_wired_test.dart`.
- A `pubspec.yaml` version bump unrelated to this session.

If these pre-existing edits conflict with the stale re-invite fix, reconcile narrowly inside the owner files and document what was already present versus what execution added.

Pre-execution dirty snapshot recorded by the pipeline controller after planning:

- `M Test-Flight-Improv/_current-test-map.md`
- `M lib/features/groups/presentation/screens/group_info_wired.dart`
- `M pubspec.yaml`
- `M test/features/groups/presentation/group_info_wired_test.dart`
- `?? Test-Flight-Improv/93-group-system-push-preview-sanitization-plan.md`
- `?? Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-01-plan.md`
- `?? Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-breakdown.md`
- `?? Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`

## files and repos to inspect next

Inspect these before making any implementation edit:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/application/record_group_invite_delivery_attempts.dart`
- `lib/features/groups/application/resend_group_invite_use_case.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`
- `integration_test/group_multi_device_real_harness.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`

Do not inspect broad group transport or push subsystems unless a direct test failure points there.

## existing tests covering this area

Current meaningful coverage:

- `test/features/groups/presentation/group_info_wired_test.dart` already covers loading invite delivery statuses and, in the dirty worktree, accepted-member durable `member_joined` overlay behavior.
- `test/features/groups/application/group_message_listener_test.dart` covers `member_joined` saving a durable join event and marking invite delivery status `joined`.
- `test/features/groups/presentation/group_info_screen_test.dart` covers badge rendering for at least `Needs resend`.
- `./scripts/run_test_gates.sh groups` is the named group gate for group send, invite, resume, membership, and announcement-adjacent behavior.

Missing coverage this session must add:

- Stale re-invite after old join and later removal.
- Full six-label matrix in one deterministic host/widget test.
- Four-simulator creator-side Members UI proof.

## regression/tests to add first

Add host regressions before changing production behavior beyond the current dirty overlay.

Stale re-invite regression in `test/features/groups/presentation/group_info_wired_test.dart`:

- Arrange a current group with admin and a re-invited member.
- Save an old `member_joined` timeline message for that member.
- Save a later `member_removed` timeline message for the same member.
- Save a newer current invite attempt with status `sent`.
- Do not save a fresh `member_joined` after the current invite.
- Expect the member row to display `Invite sent`, not `Joined`.

Full status matrix in `test/features/groups/presentation/group_info_wired_test.dart`:

- Arrange one group with six non-self members.
- Persist statuses for `sent`, `queued`, `needsResend`, `cannotSend`, and `joined`.
- Leave one member without an invite attempt row and without valid join evidence.
- Expect exactly one visible label for each of `Invite sent`, `Invite queued`, `Needs resend`, `Cannot send`, `Joined`, and `Invite unknown`.

Preservation coverage:

- Keep or extend the accepted-member tests already in the dirty worktree so valid current join evidence still renders `Joined`.
- If the stale re-invite test unexpectedly passes before the production change because another dirty edit already fixed it, record that in execution notes and continue with the matrix, gates, and simulator proof.

## step-by-step implementation plan

Stage 1: host regressions.

1. Inspect the current dirty tests and keep the existing accepted-member overlay tests unless they are superseded by stronger equivalents.
2. Add the stale re-invite regression in `group_info_wired_test.dart` using `buildMemberJoinedTimelineMessage` and `buildMemberRemovedTimelineMessage`.
3. Add the six-label matrix test in `group_info_wired_test.dart`.
4. Confirm by code review that these tests pin display behavior and do not require transport, push, or database migration changes.

Stage 2: production stale join overlay fix.

1. Update `_loadInviteStatusesByPeerId` in `GroupInfoWired` to load invite attempts with timestamp metadata, preferably through the existing `getAttemptsForGroup` API.
2. Build both a status map and an attempt map keyed by `peerId`.
3. For each current member, query the latest `member_joined` and latest `member_removed` timestamps through `GroupMessageRepository.getLatestSystemEventTimestampForTarget`.
4. Overlay `Joined` only when join evidence is current: there is a `member_joined` timestamp, it is after the latest removal timestamp if one exists, and it is not older than the current non-joined invite attempt's `attemptedAt`.
5. Preserve the missing-attempt fallback by allowing `Joined` when there is current join evidence and no invite attempt row.
6. Preserve explicit `joined` attempt rows unless timestamp evidence proves they are stale relative to a later removal or newer non-joined attempt.
7. Keep label text and row UI unchanged.
8. Avoid changing repository interfaces unless implementation evidence proves the existing timestamp-bearing `getAttemptsForGroup` API cannot support the fix.

Stage 3: four-simulator display proof.

1. Check whether `integration_test/scripts/run_group_invite_status_matrix_sim.dart` exists after implementation begins.
2. If it does not exist, add it and a focused harness, likely `integration_test/group_invite_status_matrix_harness.dart`, borrowing orchestration patterns from `run_group_multi_device_real.dart` and `group_multi_device_real_harness.dart`.
3. The runner should require exactly four device IDs and label roles as creator/admin, accepted member one, accepted member two, and pending/failed/unaccepted invitee.
4. Prove real accepted lifecycle for at least two member simulators when the required relay/testpeer setup is available.
5. For hard-to-force display-only statuses, seeded creator-side repository rows are acceptable if the host tests already prove enum mapping and the simulator still opens the real creator Group Info UI.
6. Emit actionable logs and screenshot paths on failure where the existing integration framework supports screenshots.
7. Update `_current-test-map.md`, `test-gate-definitions.md`, or relevant simulator docs only to the extent needed to make the new runner discoverable.

## Device/Relay Proof Profile

The breakdown snapshot recorded live availability before planning:

- `flutter devices --machine` saw four booted supported iOS simulators:
  - `38FECA55-03C1-4907-BD9D-8E64BF8E3469`
  - `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
  - `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
  - `1B098DFF-6294-407A-A209-BBF360893485`
- `xcrun simctl list devices available` also saw those IDs as booted.

Execution must re-check availability immediately before simulator proof because device state can change. If any ID is unavailable, execution must record the unavailable ID and either use four currently booted supported replacements with the exact command recorded, or classify the simulator proof as blocked.

Required four-simulator command after implementation:

```bash
dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

If `integration_test/scripts/run_group_invite_status_matrix_sim.dart` exists after implementation, run that command. If it does not exist, execution must add the runner and harness as part of this session, or truthfully block/follow up if a non-repo fixture is missing and cannot be created locally.

Relay and fixture expectations:

- Follow the existing `run_group_multi_device_real.dart` pattern for `MKNOON_RELAY_ADDRESSES` and repo-local `go-mknoon/bin/testpeer` setup when real lifecycle proof needs relay-backed peers.
- If relay addresses, `testpeer`, or another external fixture is required and unavailable, record the missing fixture, the command attempted, and the reason proof cannot be claimed.
- Do not substitute host tests for the four-simulator proof in closure language; classify simulator proof separately.

## risks and edge cases

- Old `member_joined` events can outlive the current membership lifecycle.
- A later `member_removed` event must invalidate earlier join evidence until a fresh join occurs.
- A newer current invite attempt should win over older join evidence.
- Missing attempt rows with valid current join evidence must still show `Joined`.
- Existing dirty overlay tests may already depend on broad join overlay behavior, so the fix must update expectations only where stale evidence is intentionally rejected.
- Four simulator runs can fail because of device attach, relay, app build, or fixture setup before product behavior is tested.
- Seeded simulator rows are acceptable for display-only statuses, but real accepted-member lifecycle still needs simulator proof unless blocked by environment.

## exact tests and gates to run

Required host and diff gates:

```bash
flutter test test/features/groups/presentation/group_info_wired_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
./scripts/run_test_gates.sh groups
git diff --check
```

Required simulator proof if available after implementation:

```bash
dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

Conditional direct gate:

```bash
flutter test test/features/groups/presentation/group_info_screen_test.dart
```

Run the conditional direct gate only if implementation changes badge rendering, label mapping, row keys, or `GroupInfoScreen`/`group_member_row` behavior.

## known-failure interpretation

- The stale re-invite test should fail against the broad dirty overlay if the production fix is not already present. That is expected pre-fix evidence.
- If the stale re-invite test already passes before production edits, treat that as evidence of pre-existing work, not proof that the session is complete.
- If accepted-member `Joined` tests fail after the fix, the overlay is too strict.
- If the matrix test fails, inspect status mapping and setup before touching repository semantics.
- If `group_message_listener_test.dart` fails, check whether implementation accidentally changed listener-side durable join or status-marking behavior.
- If `./scripts/run_test_gates.sh groups` has pre-existing unrelated failures, record the failing tests and compare against direct test results before classifying as a session regression.
- If the simulator command fails before app launch or device attach, classify it as environment or runner setup until logs prove a product UI mismatch.
- If creator-side Group Info assertions fail after successful app setup, classify it as product behavior evidence.

## done criteria

- Stale re-invite displays current invite status, not stale `Joined`.
- Valid current accepted members still display `Joined`.
- The six visible invite status labels are covered in one deterministic host/widget matrix.
- The production diff is narrow and label-preserving.
- Required host gates and `git diff --check` have recorded results.
- Four-simulator proof has either passed with the exact command and device IDs, or is explicitly blocked with device, runner, relay, or fixture evidence.
- Discoverability docs are updated if, and only if, new or changed tests/runners need classification.

## scope guard

Do not:

- Rename visible labels.
- Redesign Members UI.
- Change group invite wire format.
- Change group membership event IDs or system message payloads.
- Add a database migration unless the existing timestamp APIs are proven insufficient.
- Convert this into transport retry, inbox durability, push routing, key repair, or group media work.
- Widen frozen named gates without an explicit `test-gate-definitions.md` classification reason.
- Revert or normalize unrelated dirty files.

Stop and record a blocker if:

- The only viable fix requires changing cross-feature invite semantics outside Group Info status display.
- The simulator runner needs a non-repo fixture that is unavailable and cannot be generated by existing scripts.
- The dirty worktree has conflicting edits that make the owner-file behavior ambiguous after inspection.

## accepted differences / intentionally out of scope

- Host/widget coverage may prove the full enum display matrix more deterministically than a real network simulator path.
- The four-simulator proof should prove creator-side real UI and accepted-member lifecycle, but it does not need to organically force every possible failure state through real networking.
- Transport retry, inbox durability, key repair, push notifications, group media, and contact bootstrap remain out of scope unless a required test failure directly implicates them.
- Existing two-device simulator journey docs stay untouched unless the new four-simulator proof is intentionally cataloged there.

## dependency impact

This session closes the source doc's only implementation session if the host gates pass and simulator proof is either passed or truthfully classified.

Later work depending on this plan:

- Any future group invite resend or member-list display changes can rely on the stale re-invite regression.
- Test-map and gate-definition updates should point future maintainers to `group_info_wired_test.dart` for admin Members invite-status display.
- Simulator runbooks can cite the four-simulator runner only after it exists and has recorded evidence.

If the production fix changes because repository timestamps are insufficient, revisit whether an invite-attempt repository helper or application-level resend timestamp fix is needed before adding broader simulator coverage.

## Reviewer/QA Expectations

Reviewer expectations:

- Confirm the stale re-invite regression was added before or independently of the production fix.
- Confirm the production logic compares join evidence against removal and current invite attempt timestamps.
- Confirm accepted-member missing-row `Joined` behavior still works.
- Confirm no visible label text changed.
- Confirm dirty pre-existing edits were preserved or intentionally reconciled.
- Confirm simulator proof language does not overclaim when device, runner, relay, or fixture setup fails.

QA expectations:

- Capture exact command results for all required host gates and `git diff --check`.
- Capture the exact simulator command, device IDs, relay/testpeer setup, and result.
- If simulator proof fails, keep logs and screenshot paths if produced, then classify the failure as environment, runner setup, fixture, or product UI mismatch.
- Re-run direct host tests after any reviewer-requested fix loop before re-running broader gates.

## Structural blockers remaining

None.

The simulator proof remains evidence-gated by live devices and fixture availability, but that is an execution condition rather than a planning blocker.

## Incremental details intentionally deferred

- Exact runner internals are deferred to implementation, but they should follow existing group multi-device orchestration patterns.
- Exact screenshot capture mechanism is deferred to the integration harness capabilities already present after implementation begins.
- Classification of the new runner in simulator docs is deferred until the runner exists.

## Accepted differences intentionally left unchanged

- The host matrix can use deterministic seeded rows for display-only states.
- The simulator proof can combine real accepted lifecycle with seeded display-only rows for difficult failure states.
- No generic invite-status abstraction is required unless implementation evidence shows repeated logic after the narrow fix.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/application/record_group_invite_delivery_attempts.dart`
- `lib/features/groups/application/resend_group_invite_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`
- `integration_test/group_multi_device_real_harness.dart`
- `git status --short`
- `git diff --stat`
- Dirty diffs for `GroupInfoWired`, `group_info_wired_test.dart`, `_current-test-map.md`, and `pubspec.yaml`

## Why the plan is safe or unsafe to implement now

The plan is safe to implement now because the code already exposes the needed evidence:

- Invite attempts include `attemptedAt` and `updatedAt`.
- The attempt repository exposes `getAttemptsForGroup`.
- The message repository exposes targeted `member_joined` and `member_removed` timestamp lookups.
- Existing fakes support those timestamp lookups.
- The named group gate and direct tests are already documented.

The plan is not safe to close automatically after host tests alone. Final closure must keep simulator proof separate and explicit because the four simulator IDs, runner existence, relay setup, and external fixtures are environment-dependent.
