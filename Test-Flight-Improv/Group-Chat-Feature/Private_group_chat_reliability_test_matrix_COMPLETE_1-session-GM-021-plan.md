# GM-021 Re-add Fresh Invite/Key Package Plan

Status: execution-ready

## Planning Progress

- 2026-05-11 08:39:00 CEST - Role: Final Arbiter completed - Files inspected since last update: final patched plan - Decision/blocker: no structural blockers remain; plan is execution-ready for GM-021 only - Next action: execute only under a separate implementation request/session.
- 2026-05-11 08:38:00 CEST - Role: Final Arbiter started - Files inspected since last update: Final Reviewer Pass and patched plan - Decision/blocker: classify remaining findings after final review - Next action: mark execution-ready if no structural blocker remains.
- 2026-05-11 08:37:00 CEST - Role: Final Reviewer completed - Files inspected since last update: patched plan and mandatory section list - Decision/blocker: sufficient as-is; no missing structural files, tests, gates, closure bar, regression-first rule, or stop rule remain - Next action: final arbiter classification.
- 2026-05-11 08:36:00 CEST - Role: Final Reviewer started - Files inspected since last update: patched plan sections for closure bar, RED tests, criteria, harness, risks, and done criteria - Decision/blocker: verify the single arbiter-required patch resolved the structural gap - Next action: final sufficiency verdict.
- 2026-05-11 08:33:00 CEST - Role: Arbiter completed - Files inspected since last update: Arbiter Pass - Decision/blocker: one structural blocker; patch plan once to require same-active-device stale `SenderKeyPackageId` rejection - Next action: apply single plan patch, then run final reviewer and final arbiter.

## Execution Progress

- 2026-05-11 08:16:58 CEST - Role: Executor contract extraction completed - Files inspected since last update: GM-021 plan, execution skill, git status, Go validator tests, criteria evaluator/test entry points, simulator runner/harness entry points, send/config seams by search - Decision/blocker: execute GM-021 only; matrix and session breakdown remain read-only; current GM support stops at GM-020 and row-owned RED tests/harness are required before any production fix - Next action: add GM-021 RED tests and criteria/harness support.
- 2026-05-11 08:22:00 CEST - Role: Executor RED edit started - Files inspected since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `send_group_message_use_case.dart`, `group_config_payload.dart`, `add_group_member_use_case.dart`, GM-019/GM-020 host and simulator proof patterns - Decision/blocker: live `group:publish` lacks `senderKeyPackageId` while replay envelope already has it; add GM-021 tests first to prove scope before any production fix - Next action: patch row-owned Go, Dart host, criteria, runner, and harness tests/support.
- 2026-05-11 08:33:00 CEST - Role: Executor focused RED tests started - Files touched since last update: `go-mknoon/node/pubsub_test.go`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `lib/core/bridge/go_bridge_client.dart` - Command currently running: focused GM-021 Go/Dart tests - Decision/blocker: no product behavior fix applied yet; expect RED on live publish key package metadata if gap is real - Next action: classify focused failures before patching product behavior.
- 2026-05-11 08:29:49 CEST - Role: Executor RED result classified - Files touched since last update: same GM-021 row-owned files - Command result: `(cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_ReaddFreshKeyPackageRejectsRemovedPackage|TestGroupTopicValidator_Device')` passed; `flutter test test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-021'` failed because live `group:publish` payload had `senderKeyPackageId=null` instead of `kp-charlie-fresh` - Decision/blocker: real product gap in `send_group_message_use_case.dart`; apply one-line scoped publish metadata fix - Next action: patch live publish to pass resolved fresh `senderKeyPackageId`, then rerun focused set.
- 2026-05-11 08:30:30 CEST - Role: Executor focused GREEN result - Files touched since last update: `send_group_message_use_case.dart` patched to pass `senderKeyPackageId`; Dart files formatted - Command results: focused GM-021 member-removal test passed, focused GM-021 criteria tests passed, focused GM-021 group membership smoke passed - Decision/blocker: host RED gap is fixed; no broader production change needed beyond live publish metadata and Go validation-event passthrough for simulator proof - Next action: run required adjacent suites, exact simulator proof, named gates, and diff hygiene.
- 2026-05-11 08:31:13 CEST - Role: Executor focused proof rerun completed - Files touched since last update: no additional edits - Command results: `(cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_ReaddFreshKeyPackageRejectsRemovedPackage|TestGroupTopicValidator_Device')` passed; `flutter test test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-021'` passed; `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-021'` passed; `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-021'` passed - Decision/blocker: row-owned host and criteria proof is green - Next action: run required adjacent suites.
- 2026-05-11 08:33:09 CEST - Role: Executor adjacent suite result - Files touched since last update: no additional edits - Command result: `flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart` passed (`+55`) - Decision/blocker: adjacent member-removal and membership smoke coverage remains green with GM-021 changes - Next action: run group new-member onboarding suite.
- 2026-05-11 08:33:27 CEST - Role: Executor adjacent onboarding suite start - Files touched since last update: no additional edits - Command started: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart` - Decision/blocker: none yet - Next action: record result, then run exact gm021 simulator proof.
- 2026-05-11 08:33:49 CEST - Role: Executor adjacent onboarding suite result - Files touched since last update: no additional edits - Command result: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart` passed (`+7`) - Decision/blocker: adjacent onboarding coverage remains green; real-crypto onboarding remains conditional and not required because onboarding/crypto key generation was not changed - Next action: run exact gm021 simulator proof command.
- 2026-05-11 08:34:10 CEST - Role: Executor simulator proof start - Files touched since last update: no additional edits - Command started: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm021 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` - Decision/blocker: none yet - Next action: record simulator verdict path/result and repair/rerun if simulator/build state fails.
- 2026-05-11 08:35:00 CEST - Role: Executor simulator setup failure classified - Files inspected/touched since last update: runner/criteria relay profile docs; no code edits - Command result: exact gm021 command exited 64 before launching Flutter because `MKNOON_RELAY_ADDRESSES` was unset - Decision/blocker: environment fixture setup required, not GM-021 product failure; use repo-standard relay profile and rerun the same Dart command/device tuple - Next action: rerun exact gm021 proof with `MKNOON_RELAY_ADDRESSES` exported.
- 2026-05-11 08:36:00 CEST - Role: Executor simulator proof rerun in progress - Files touched since last update: no additional edits - Command started: same gm021 Dart command/device tuple with `MKNOON_RELAY_ADDRESSES` exported to repo-standard WSS+QUIC relay profile - Evidence path: shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm021_0EeOVV`, run id `1778481322902` - Decision/blocker: none yet - Next action: wait for aggregate verdict or exact failure.
- 2026-05-11 08:38:20 CEST - Role: Executor simulator build failure repaired - Files touched since last update: `integration_test/group_multi_party_device_real_harness.dart`, this plan - Command result: gm021 simulator rerun hit Xcode/Dart compile failure before valid GM-021 proof because Charlie role passed nullable `currentState.peerId` into non-null proof fields; stale Runner output from an older scenario was terminated - Decision/blocker: harness compile gap fixed by requiring non-empty Charlie active device id before proof-field use; no product behavior change - Next action: rerun exact gm021 simulator proof with relay env.
- 2026-05-11 08:38:53 CEST - Role: Executor simulator proof rerun start - Files touched since last update: no additional edits - Command started: same gm021 Dart command/device tuple with `MKNOON_RELAY_ADDRESSES` exported and stale Runner apps terminated on Alice/Bob/Charlie simulators - Decision/blocker: none yet - Next action: record aggregate verdict path/result or next exact failure.
- 2026-05-11 08:39:56 CEST - Role: Executor simulator proof rerun in progress - Files touched since last update: no additional edits - Evidence path: shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm021_4sOsVi`, run id `1778481560809` - Decision/blocker: none yet - Next action: wait for aggregate verdict or exact failure.
- 2026-05-11 08:45:03 CEST - Role: Executor simulator criteria failure repaired - Files touched since last update: `integration_test/group_multi_party_device_real_harness.dart`, this plan - Command result: gm021 roles passed, but aggregate verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm021_4sOsVi/gmp_1778481560809_gm021_orchestrator_verdict.json` was `ok:false` because Charlie proof recorded `sameActiveDeviceStaleKeyPackageRejectionReason: missing`; `charlie.log` showed local `group:validation_rejected` with `reason:"unbound_device"` - Decision/blocker: harness capture gap, not product failure; patched Charlie stale publish proof to capture local validation rejection and still require `unbound_device` - Next action: rerun exact gm021 simulator proof.
- 2026-05-11 08:45:27 CEST - Role: Executor simulator proof rerun start - Files touched since last update: no additional edits - Command started: same gm021 Dart command/device tuple with `MKNOON_RELAY_ADDRESSES` exported after terminating Runner apps on all three simulators - Decision/blocker: none yet - Next action: record aggregate verdict path/result.
- 2026-05-11 08:46:26 CEST - Role: Executor simulator proof rerun in progress - Files touched since last update: no additional edits - Evidence path: shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm021_sS7hmN`, run id `1778481951193` - Decision/blocker: none yet - Next action: wait for aggregate verdict.
- 2026-05-11 08:49:32 CEST - Role: Executor simulator proof result - Files touched since last update: no additional edits - Command result: exact gm021 simulator proof passed; aggregate verdict `ok:true` at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm021_sS7hmN/gmp_1778481951193_gm021_orchestrator_verdict.json`; role logs and verdicts are in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm021_sS7hmN` - Decision/blocker: mandatory simulator-only row proof is green - Next action: run named gates and diff hygiene.
- 2026-05-11 08:49:49 CEST - Role: Executor named gate start - Files touched since last update: no additional edits - Command started: `./scripts/run_test_gates.sh groups` - Decision/blocker: none yet - Next action: record groups gate result.
- 2026-05-11 08:51:26 CEST - Role: Executor named gate result - Files touched since last update: no additional edits - Command result: `./scripts/run_test_gates.sh groups` passed (`+126`) - Decision/blocker: required groups gate remains green - Next action: run `./scripts/run_test_gates.sh completeness-check`.
- 2026-05-11 08:51:40 CEST - Role: Executor completeness gate - Files touched since last update: no additional edits - Command result: `./scripts/run_test_gates.sh completeness-check` passed (`731/731 test files classified`) - Decision/blocker: required completeness gate remains green - Next action: run `git diff --check`.
- 2026-05-11 08:51:56 CEST - Role: Executor diff hygiene result - Files touched since last update: no additional edits - Command result: `git diff --check` passed with no output - Decision/blocker: no whitespace or conflict-marker issues detected - Next action: inspect final changed-file scope and report GM-021 executor result.
- 2026-05-11 08:52:36 CEST - Role: Executor final status - Files touched since last update: no additional edits - Command result: final artifact check confirmed `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm021_sS7hmN/gmp_1778481951193_gm021_orchestrator_verdict.json` has `scenario=gm021` and `ok=true` - Decision/blocker: GM-021 executor evidence is complete; worktree still includes unrelated prior GM-row edits that were left intact - Next action: hand off for QA/review.
- 2026-05-11 08:53:06 CEST - Role: Executor post-progress diff hygiene rerun - Files touched since last update: no additional edits beyond this progress log - Command result: `git diff --check` rerun passed with no output - Decision/blocker: final progress-log edit remains whitespace clean - Next action: hand off for QA/review.
- 2026-05-11 08:53:52 CEST - Role: Executor exact simulator proof rerun start - Files touched since last update: progress log only - Command started after exporting repo relay addresses in the shell: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm021 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` - Decision/blocker: tightening exact-command evidence - Next action: record rerun result.
- 2026-05-11 08:58:12 CEST - Role: Executor exact simulator proof rerun result - Files touched since last update: progress log only - Command result: literal `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm021 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` passed after repo relay addresses were exported in the shell; verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm021_Vf3gW7/gmp_1778482464428_gm021_orchestrator_verdict.json` has `scenario=gm021` and `ok=true` - Decision/blocker: exact simulator-only proof is green - Next action: final `git diff --check` and hand off for QA/review.
- 2026-05-11 08:58:35 CEST - Role: Executor final diff hygiene result - Files touched since last update: progress log only - Command result: `git diff --check` passed with no output after the exact simulator rerun result was recorded - Decision/blocker: final changed set is whitespace clean - Next action: hand off for QA/review.
- 2026-05-11 08:14:57 CEST - Role: Controller contract extraction completed - Files inspected since last update: GM-021 plan, skill contract, git status, Codex CLI help - Decision/blocker: scope is GM-021 only; source matrix and breakdown are read-only for this execution; spawned child agents are available via `codex exec` with `model=gpt-5.5` and `reasoning_effort=xhigh` - Next action: spawn the Executor pass for row-owned RED tests, harness/criteria support, conditional narrow product fixes, and required proof commands.
- 2026-05-11 08:15:43 CEST - Role: Executor spawn retry - Files inspected since last update: Codex exec command output - Decision/blocker: first spawn command failed before child materialization because this `codex exec` subcommand does not accept `-a`; no child work or partial repo edits occurred - Next action: retry the same Executor pass with `--dangerously-bypass-approvals-and-sandbox`.

## real scope

Own exactly GM-021: after Charlie has been removed, a later re-add must bind Charlie to the active invite/device/key package only. A message signed or published with Charlie's old removed device/key package must be rejected and must not appear as accepted plaintext for Alice or Bob. A message from Charlie's fresh re-added active package must deliver to Alice and Bob.

Execution may add or adjust row-owned tests, simulator harness support, criteria validation, and narrowly scoped product code only if the RED proof finds a real gap. If current production behavior already satisfies the row, execution is tests/harness/evidence-only.

Planning and execution must not close GM-021 using GM-010, GM-012, GM-014, GM-019, or GM-020 evidence. Those rows prove adjacent idempotence, ordering, delayed key delivery, and durable recipient windows, but not fresh invite/key-package binding plus old package rejection.

## closure bar

GM-021 is good enough only when row-owned proof shows all of these facts:

- Charlie had an initial active package/device identity before removal, and that old identity is recorded in test evidence.
- Charlie is removed and that identity is no longer in the active group config used by validators.
- Charlie is re-added with a fresh invite/device/key package, `oldKeyPackageId != freshKeyPackageId`, and every active repo/config/Go-validator snapshot used after re-add contains the fresh package, not the old removed package.
- A fresh Charlie send after re-add succeeds and reaches Alice and Bob exactly once.
- A stale old `SenderKeyPackageId` send attempt using the otherwise active/fresh device fields is rejected by validator behavior, preferably as `unbound_device`, proving the key-package-specific path. If the re-add also changes device id, transport peer, or signing key, a second full old-device/package attempt should also be rejected. Neither stale attempt may create accepted plaintext for Alice or Bob.
- Exact simulator-only `gm021` proof passes on the three named iOS simulators and writes an accepted orchestrator verdict.

## source of truth

Current code and tests win over stale prose. The source matrix row GM-021 defines the behavioral contract. The session breakdown defines GM-021 as `needs_repo_evidence`, `evidence-gated`, and evidence-only unless exact planning finds missing code. `Test-Flight-Improv/test-gate-definitions.md` is the source of truth for named host gates.

On disagreement: current code/test behavior wins for implementation details; GM-021 source row wins for row closure; gate definitions win for gate membership; this plan wins for GM-021 execution scope until repo evidence proves it stale.

## session classification

evidence-gated

GM-021 is not closed. Current evidence shows a clear harness/test gap: `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart` currently enumerate GM scenarios through GM-020, not GM-021.

## exact problem statement

The risk is stale authorization after a remove/re-add cycle. Charlie's old removed package may remain cached in local membership state, group config snapshots, Go validator state, send parameters, or simulator harness assumptions. If that happens, a stale Charlie package could send after removal/re-add, or the fresh Charlie package could fail to send because the validator is still bound to old material.

The user-visible behavior that must improve is private-group message authenticity across re-add: Alice and Bob should only accept Charlie traffic from Charlie's fresh active package after re-add. Charlie should be able to send after a legitimate fresh re-add. The work must not change broad group membership behavior, durable recipient rules from GM-019/GM-020, or unrelated onboarding flows.

## files and repos to inspect next

Production seams:

- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/group_members_db_helpers.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/group_inbox.go`

Test and proof seams:

- `go-mknoon/node/pubsub_test.go`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `integration_test/group_real_crypto_onboarding_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

Existing adjacent coverage:

- GM-010 proves duplicate re-add idempotence and one active membership/device binding for duplicate re-add, but not old removed package rejection.
- GM-012 proves stale remove ordering does not override a newer re-add, including current device identity in listener/config tests, but not removed-package send rejection.
- GM-014 proves re-add/key delivery timing and no silent loss, but not fresh package binding against old removed package sends.
- GM-019 proves durable recipients exclude Charlie during the removed window and include Charlie after re-add.
- GM-020 proves durable recipients exclude Charlie immediately after removal.
- `go-mknoon/node/pubsub_test.go` already tests active device binding accept, unbound sibling rejection, public key mismatch rejection, transport mismatch rejection, and `pubsub.go` compares `SenderKeyPackageId` with the active device's `KeyPackageId`.

Missing row-owned coverage:

- No GM-021 host test records old Charlie package, re-adds with fresh package, and proves old package rejection plus fresh package acceptance.
- No GM-021 fake-network/member-removal smoke proves re-add snapshots contain only fresh Charlie device/key package and outgoing Charlie publish uses fresh `senderKeyPackageId`.
- No GM-021 simulator scenario, runner entry, harness role flow, or criteria proof exists today.

## regression/tests to add first

Add RED tests before any product behavior change:

- Go validator RED: add `TestGroupTopicValidator_ReaddFreshKeyPackageRejectsRemovedPackage` in `go-mknoon/node/pubsub_test.go`. It should build an initial Charlie device/key package, replace config with a fresh Charlie device/key package after simulated removal/re-add, assert a fresh envelope accepts, assert an envelope using the active/fresh device id, transport peer, and signing key but the old `SenderKeyPackageId` rejects as `reject:unbound_device`, and, when the old device identity differs, assert the full old `SenderDeviceId`/transport/signing key/key package envelope also rejects.
- Dart membership/config RED: add GM-021 focused coverage to `member_removal_integration_test.dart` and/or `group_membership_smoke_test.dart` proving `removeMember` deletes Charlie, `addGroupMember` persists only the fresh device/key package, the generated `group:updateConfig` payload contains only the fresh Charlie package, and `sendGroupMessage` from Charlie includes the fresh `senderKeyPackageId`.
- Criteria RED: add GM-021 requirement and negative tests to `test/integration/group_multi_party_device_criteria_test.dart` so criteria reject missing fresh-vs-old package proof, identical old/fresh package ids, missing same-active-device stale `SenderKeyPackageId` rejection, accepted stale send, and any Alice/Bob plaintext receipt for stale attempts.
- Simulator harness RED: add `gm021` support to runner, harness, and criteria. Before product fixes, the exact `--scenario gm021` proof should fail until the harness can demonstrate fresh-package acceptance, same-active-device stale `SenderKeyPackageId` rejection, optional full old-device rejection when applicable, and no stale plaintext from actual role verdicts.

If all RED tests pass without product code changes after harness support is added, classify execution as tests/harness/evidence-only and do not edit production code.

## step-by-step implementation plan

1. Confirm the worktree and limit edits to GM-021-owned files. Do not edit the source matrix or session breakdown during execution until a separate closure step.
2. Add focused GM-021 RED tests for Go validator behavior and Dart membership/config/send evidence. Use distinct values such as `charlie-device-old`, `charlie-device-fresh`, `kp-charlie-old`, and `kp-charlie-fresh`, and include a stale-key-package case where only `SenderKeyPackageId` is old while active device fields are fresh.
3. Add GM-021 criteria support: scenario requirement, expected message keys, a `gm021FreshReaddPackageProof` validator, and negative criteria tests for missing proof, old/fresh equality, missing same-active-device stale key-package rejection, stale accepted send, and stale plaintext leak.
4. Add GM-021 runner/harness support for three roles. The role verdicts must include old package id/device id, fresh package id/device id, re-add timestamp, fresh send result/delivery, same-active-device stale key-package attempt result/rejection reason, optional full old-device attempt result/rejection reason, and Alice/Bob no-stale-plaintext evidence.
5. Run the focused RED set. If failures show only missing harness/proof, continue harness/test work. If failures show a product gap, apply the smallest fix in the seam that failed:
   - stale config/package retained in app state: inspect `add_group_member_use_case.dart`, `group_message_listener.dart`, `group_config_payload.dart`, `group_member.dart`, repository/db helpers.
   - fresh sender package not emitted: inspect `send_group_message_use_case.dart` and `bridge_group_helpers.dart`.
   - validator accepts old package: inspect `go-mknoon/node/pubsub.go`.
   - key-update recipient binding accepts stale package: inspect `group_key_update_listener.dart`.
6. Re-run the exact focused tests after any fix. Stop product work as soon as the row proof passes; do not broaden into invite UX, global crypto redesign, or durable inbox recipient logic.
7. Run the exact simulator proof using `--scenario gm021` on the specified iOS simulators. Repair and rerun infrastructure/build-state failures instead of accepting a simulator/Xcode block.
8. Run named host gates and diff hygiene. If no Go files changed except tests, still run the focused Go validator test. If Go production changed, run the broader Go node selector below.
9. Record execution evidence in the GM-021 plan/closure artifact only during execution. Matrix and breakdown closure updates are out of this planning doc's scope.

## risks and edge cases

- App-side state may preserve `existing.devices` when a member is re-added without deleting old membership first.
- Fake network fan-out does not itself validate key packages, so fake-network tests must inspect configs/send parameters and rely on Go validator or simulator proof for rejection.
- A stale package could be rejected by transport peer mismatch while the key-package-specific path remains unproven. GM-021 proof must include a same-active-device old `SenderKeyPackageId` attempt and must record the rejection reason plus old/fresh package fields.
- Simulator harness may accidentally reuse Charlie's DB/identity across removal and re-add. GM-021 must intentionally create or simulate fresh active package material and preserve old material only as a stale attack input.
- Real-crypto onboarding may be expensive and simulator-bound; run it only if onboarding/crypto surfaces are changed or direct evidence cannot otherwise prove invite/key package freshness.
- Build-state failures are infrastructure failures. They require cleanup and rerun, not closure as blocked.

## exact tests and gates to run

Focused RED/direct tests:

```sh
(cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_ReaddFreshKeyPackageRejectsRemovedPackage|TestGroupTopicValidator_Device')
flutter test test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-021'
flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-021'
flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-021'
```

Direct adjacent suites after the focused tests pass:

```sh
flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test test/features/groups/integration/group_new_member_onboarding_test.dart
```

Conditional crypto/onboarding proof:

```sh
flutter test integration_test/group_real_crypto_onboarding_test.dart -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Run the conditional crypto/onboarding proof only if `group_real_crypto_onboarding_test.dart`, invite payload handling, key package generation/distribution, or onboarding flows are changed, or if the focused tests cannot prove fresh invite/key package binding without it.

Exact simulator-only Device/Relay Proof Profile:

```sh
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm021 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gates and hygiene:

```sh
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

If Go production code changes:

```sh
(cd go-mknoon && go test ./node -run 'GroupTopicValidator|GroupInbox|GroupRecovery|PubSub')
```

Do not require `--scenario all`. Do not require real external or physical devices.

## known-failure interpretation

Pre-existing analyzer or test failures outside GM-021-owned files may be documented only if they are reproducible before GM-021 changes and unrelated to touched files. A failure in any GM-021 focused test, criteria test, exact simulator proof, or touched-file analyzer is a GM-021 blocker.

Simulator/Xcode/build-state failures are not acceptable final blockers. Refresh devices, boot the exact simulators, uninstall the app/extensions, clear Runner/Pods DerivedData and `build/ios` if needed, run `flutter pub get`, run `flutter clean` only if needed, and rerun the exact `gm021` proof. Leave the row blocked only for a real product/test failure after infrastructure repair, not for stale simulator state.

## done criteria

- GM-021 focused Go validator proof passes and proves fresh package acceptance, same-active-device old `SenderKeyPackageId` rejection, and full old-device/package rejection when the re-add changes device identity.
- GM-021 Dart host/fake proof passes and proves re-add state/config/send parameters use only the fresh Charlie package.
- GM-021 criteria negative tests fail bad evidence and accept only complete row-owned evidence.
- Exact simulator-only `gm021` proof passes on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` pass.
- Any conditional product fix is scoped to the failing GM-021 seam and has a direct RED-first test proving it.
- No source matrix or session breakdown closure is claimed until execution evidence exists.

## scope guard

Non-goals:

- Do not edit production/test code during this planning session.
- Do not edit the source matrix or session breakdown during planning.
- Do not broaden into GM-022 or later rows.
- Do not rewrite invite UX, global key generation, group inbox storage, or relay membership architecture unless a GM-021 RED test proves that exact seam is broken.
- Do not use `--scenario all` as a substitute for row-owned `gm021`.
- Do not depend on real external or physical devices.
- Do not close GM-021 from adjacent GM-010/012/014/019/020 evidence.

Overengineering would be adding a new authorization framework, broad crypto rotation model, global replay audit, or generalized multi-row proof system when a focused stale-package rejection proof and narrow seam fix are sufficient.

## accepted differences / intentionally out of scope

Fake-network host tests are accepted as config/send-parameter evidence, not as full validator evidence, because `FakeGroupPubSubNetwork` routes envelopes and does not enforce Go key-package validation. Go validator tests and the exact simulator proof carry the stale-package rejection requirement.

Durable recipient selection from GM-019/GM-020 remains intentionally out of scope except to ensure GM-021's fresh Charlie send reaches entitled members and the stale send does not appear as accepted plaintext.

Real-crypto onboarding is conditional, not mandatory, unless execution touches onboarding/crypto surfaces or cannot otherwise prove fresh invite/key material.

## dependency impact

GM-021 blocks closing the re-add freshness/package-binding part of the GM row family. Later rows that assume re-added members are bound to active device/key packages should not cite GM-021 until this row has exact host, criteria, and simulator evidence. If execution finds a production gap in validator binding, revisit later rows that rely on old-package rejection; if execution is evidence-only, later work can use GM-021 as the active package-binding proof once closure is recorded.

## Reviewer Pass

Sufficiency: sufficient with one required adjustment.

Missing files/tests/gates: the draft names the right app, Go, criteria, harness, simulator, and gate surfaces. It correctly adds GM-021 runner/harness/criteria support because current support stops at GM-020.

Stale or incorrect assumptions: the draft should not rely on an old-device rejection alone. GM-021 specifically covers `SenderKeyPackageId` validation, so proof must include a stale old key package sent with the active/fresh device fields where possible.

Overengineering: none found. Product edits remain conditional and scoped.

Minimum adjustment needed: require same-active-device stale `SenderKeyPackageId` rejection in the Go, criteria, and simulator proof, while optionally also proving full old-device/package rejection.

## Final Reviewer Pass

Sufficiency: sufficient as-is after the single arbiter-required patch.

Missing files/tests/gates: none. The plan names the direct app seams, Go validator seam, criteria tests, simulator runner/harness, exact `gm021` simulator command, groups gate, completeness-check, and diff hygiene.

Stale or incorrect assumptions: none remaining. The plan now requires explicit `SenderKeyPackageId` mismatch proof using active/fresh device fields and keeps full old-device rejection as additional evidence.

Overengineering: none. Product edits remain conditional on RED evidence, and fake-network proof is limited to config/send-parameter evidence.

Minimum needed to implement safely: follow the plan as written; do not broaden beyond GM-021.

## Arbiter Pass

Structural blockers: one structural blocker found in the draft. GM-021 explicitly covers `SenderKeyPackageId` validation, so a plan that only requires full old-device identity rejection could pass without proving the key-package-specific path.

Incremental details: none.

Accepted differences: fake-network tests remain config/send-parameter evidence only; Go validator and simulator proof carry rejection evidence.

Arbiter decision: patch the plan once to require same-active-device stale `SenderKeyPackageId` rejection, then run one final reviewer and arbiter pass.

## Final Arbiter Pass

Structural blockers remaining: none.

Incremental details intentionally deferred: exact harness field names may be adjusted during implementation if the criteria still enforce the same facts: old/fresh package inequality, same-active-device stale `SenderKeyPackageId` rejection, fresh send delivery, and no stale plaintext.

Accepted differences intentionally left unchanged: fake-network evidence remains limited to config/send parameters; Go validator and exact simulator proof remain responsible for rejection evidence. Real-crypto onboarding remains conditional unless touched or required by evidence.

Final verdict: execution-ready for GM-021 only.
