# GM-022 Plan - Member list contains no duplicate peer IDs after re-add

Status: execution-ready

## Planning Progress

- 2026-05-11 09:18:37 CEST - Planner completed. Files inspected since last update: none beyond collected evidence. Decision/blocker: draft plan is implementation-ready if reviewer accepts the test/gate contract and the simulator build-state recovery rule. Next action: run reviewer pass.
- 2026-05-11 09:23:45 CEST - Reviewer started. Files inspected since last update: this GM-022 plan draft. Decision/blocker: review focus is proof specificity, exact gates, simulator-only constraints, and scope boundaries. Next action: record sufficiency findings and required adjustments.
- 2026-05-11 09:24:23 CEST - Reviewer completed. Files inspected since last update: this GM-022 plan draft. Decision/blocker: sufficient with adjustments; no structural blocker found, but criteria/harness proof field names needed tightening to avoid a weak simulator verdict. Next action: run arbiter pass.
- 2026-05-11 09:24:59 CEST - Arbiter started. Files inspected since last update: reviewer-pass plan with proof field tightening. Decision/blocker: classify reviewer adjustment and determine whether any structural blocker remains. Next action: record arbiter decision and final status.
- 2026-05-11 09:25:20 CEST - Arbiter completed. Files inspected since last update: final GM-022 plan. Decision/blocker: no structural blockers remain; proof field tightening is an incremental detail already applied, and accepted differences are documented. Next action: hand off execution-ready plan.

## Execution Progress

- 2026-05-11 09:27:48 CEST - Contract extracted. Files inspected: this GM-022 plan, GM-022 source matrix row, GM-022 breakdown row, `Test-Flight-Improv/test-gate-definitions.md`, and current dirty worktree status. Decision/blocker: scope is GM-022 only with RED-first host/Go/criteria/runner proof, exact simulator `--scenario gm022`, groups/completeness/diff-check gates, and no source matrix or breakdown edits. Next action: spawn isolated Executor with model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-05-11 09:29:12 CEST - Executor spawned/running. Files inspected/touched: this plan progress section only. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -c approval_policy="never" ...`. Decision/blocker: first spawn attempt failed immediately on unsupported `-a`; corrected spawn is running with session id `019e15f0-877b-7350-abde-e3188a033496`. Next action: bounded wait for Executor completion and repo evidence.
- 2026-05-11 09:29:27 CEST - Executor contract accepted locally. Files inspected/touched: this GM-022 plan progress section and dirty worktree status. Decision/blocker: proceeding as the isolated Executor for GM-022 only; source matrix and breakdown remain context-only and will not be edited. Next action: inspect current group config, Go validator, criteria, runner, harness, and GM-022-adjacent tests before RED-first selectors.
- 2026-05-11 09:39:39 CEST - RED proof added. Files touched: `go-mknoon/node/pubsub_test.go`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: added GM-022 row-owned Go, Dart host, criteria, and 20-cycle host proof expectations before product fixes; runner remains unsupported for RED observation. Next action: run focused RED selectors and record actual failures.
- 2026-05-11 09:41:37 CEST - RED observations captured. Files touched: none beyond RED tests. Commands: Go selector failed because `findMember` returned stale first duplicate, validator rejected fresh Charlie with `reject:unbound_device`, and cloned config preserved duplicate Charlie; Dart payload/listener selectors failed on two Charlie config entries; criteria selector failed because `gm022` is unsupported; exact runner command failed before launch with unsupported `gm022`; `member_removal_integration_test.dart --plain-name GM-022` passed pre-fix due local repository uniqueness; smoke selector exposed a test timestamp issue to fix before GREEN. Next action: implement scoped normalization and GM-022 criteria/runner/harness support.
- 2026-05-11 09:49:24 CEST - Scoped fixes implemented and formatted. Files touched: `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/application/group_message_listener.dart`, `go-mknoon/node/pubsub.go`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, plus GM-022 tests. Decision/blocker: Dart and Go now dedupe duplicate peer/device config entries preferring active/fresher entries; listener normalizes before apply/sync; criteria/runner/harness now know `gm022`; smoke timestamp fixture adjusted to avoid stale-event false red. Next action: rerun focused GREEN selectors.
- 2026-05-11 09:53:17 CEST - Focused smoke GREEN after timestamp correction. Files touched: `test/features/groups/integration/group_membership_smoke_test.dart` and this plan. Command: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-022'` passed. Decision/blocker: the host 20-cycle remove/re-add proof now uses live cycle/final-send timestamps and no longer fails from stale membership watermarks. Next action: run remaining focused criteria selector and adjacent host coverage.
- 2026-05-11 09:54:28 CEST - Remaining focused/adjacent host proof GREEN. Files touched: this plan only. Commands passed: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-022'`, `flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart`, and `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`. Decision/blocker: criteria now accepts full GM-022 proof and rejects duplicate Charlie/non-unique-recipient verdicts; adjacent membership/onboarding host coverage remains stable. Next action: run exact simulator-only `--scenario gm022` proof on the specified Alice/Bob/Charlie UDIDs.
- 2026-05-11 10:00:43 CEST - Exact simulator proof GREEN. Files touched: this plan only. Command passed with required relay profile and UDIDs: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm022 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Verdict path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm022_lTUTTe`; Alice/Bob/Charlie verdict JSON all report `removeReaddCycleCount: 20`, no duplicate member peer IDs, one active Charlie entry/device, active validator proof, stable post-cycle delivery, and unique durable recipients. Next action: run named `groups`, `completeness-check`, and `git diff --check` gates.
- 2026-05-11 10:01:55 CEST - Final Executor handoff. Files touched for GM-022: this plan; production `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/application/group_message_listener.dart`, `go-mknoon/node/pubsub.go`; tests/harness `go-mknoon/node/pubsub_test.go`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Commands passed: `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`. Decision/blocker: no executor blocker remains; source matrix and breakdown were left context-only despite pre-existing dirty changes. Final verdict: `accepted`.
- 2026-05-11 10:03:15 CEST - QA Reviewer spawned/running. Files touched: this plan progress section only. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -c approval_policy="never" ... -o /tmp/gm022_qa_result.txt`. Decision/blocker: independent QA review must verify GM-022 scope, exact proof, required gates, no source matrix/breakdown edits, and no remaining blocking issues before final acceptance. Next action: wait for QA result and run bounded fix loop only if QA reports blockers.
- 2026-05-11 10:08:01 CEST - QA Reviewer completed. Files touched: this plan progress section only. QA verdict: `PASS`; blocking issues: none. QA reviewed production paths, row-owned tests/proof, exact simulator artifact `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm022_lTUTTe`, reran the Go selector, all five focused GM-022 Flutter selectors, GM-022 criteria selector, and `git diff --check`; all passed after one QA-induced parallel Flutter startup race was rerun sequentially. Decision/blocker: no fix loop required; GM-022 execution is accepted with no non-blocking follow-ups.

## real scope

GM-022 owns exactly the repeated remove/re-add duplicate-member risk for private group membership config after Charlie is removed and re-added 20 times.

In scope:

- Prevent or normalize duplicate `peerId` entries in group config member lists produced locally and applied from authoritative membership snapshots.
- Ensure the active Charlie entry is the only stored/configured Charlie entry after 20 remove/re-add cycles on Alice, Bob, and Charlie.
- Ensure Go-side stored group configs and validator lookup cannot be shadowed by a stale duplicate Charlie entry.
- Ensure durable recipient lists and post-cycle sends remain stable and duplicate-free.
- Add row-owned RED-first host, Go, criteria, runner, and exact simulator proof for `gm022`.

Out of scope:

- Broad membership model redesign, new role policy, new key rotation policy, new transport abstraction, or source matrix/breakdown closure edits during implementation planning.
- `--scenario all`, physical devices, or external-device proof.
- Closing GM-023 or later stale inactive/shadow-member rows.

## closure bar

GM-022 is done only when row-owned proof shows all of the following:

- A 20-cycle remove/re-add sequence completes.
- Alice, Bob, and Charlie each report raw member/config peer IDs with no duplicates and exactly one active Charlie entry.
- The Go validator path uses the active re-add entry, not a stale first duplicate, when evaluating Charlie's post-cycle send.
- Alice, Bob, and Charlie post-cycle delivery remains exact and stable.
- Durable `recipientPeerIds` are unique and contain only expected recipients for each post-cycle send.
- Exact simulator-only `--scenario gm022` passes on the specified three iOS simulators with the required relay profile.

## source of truth

- Current code and tests win over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` is authoritative for named gates and test classification.
- The GM-022 source row in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` is authoritative for the row contract until a later closure session updates it.
- The GM-022 row in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is authoritative for current session classification and likely files.
- GM-010, GM-012, GM-014, and GM-021 are supporting context only. They do not close GM-022 because none proves 20 repeated remove/re-add cycles and no duplicate peer IDs across A/B/C configs.

## session classification

`implementation-ready`

This is not docs-only. The source row is Open, the breakdown says `needs_code_and_tests | implementation-ready | code changes + tests`, and the runner/criteria/harness currently have no `gm022` path.

## exact problem statement

GM-022 targets duplicate member shadows after repeated Charlie remove/re-add cycles. If a stale Charlie row remains before the active Charlie row in a config, Go's current `findMember` behavior can return the first match and bind validation to stale role/device/key-package data. User-visible impact is unstable group delivery after membership churn: Charlie can be incorrectly rejected, stale entries can be authorized, or recipient/config lists can drift.

Required improvement: after 20 remove/re-add cycles, all roles converge on one active Charlie member/config entry, validator lookup binds to that active entry, and A/B/C messaging remains stable.

Must stay unchanged: existing admin permission checks, removal cutoff behavior, fresh key-package semantics from GM-021, durable recipient exclusion windows from GM-019/GM-020, and current named gate definitions except for any required classification of newly added tests.

## files and repos to inspect next

Production and bridge/config seams:

- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/group_members_db_helpers.dart`
- `lib/core/database/migrations/017_groups_tables.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/group_inbox.go`

Tests and simulator proof support:

- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `integration_test/group_real_crypto_onboarding_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `Test-Flight-Improv/test-gate-definitions.md` if a new test file is added.

## existing tests covering this area

- `add_group_member_use_case_test.dart` already rejects conflicting duplicate adds before config sync and preserves the original row.
- `group_membership_smoke_test.dart` GM-010 proves a single duplicate re-add is idempotent, keeps one Charlie device binding, avoids duplicate topic joins/recipients, and preserves A/B/C delivery.
- `group_membership_smoke_test.dart` GM-012 proves stale remove-after-readd ordering does not strand Charlie and keeps one Charlie row/device binding.
- GM-014 tests prove delayed re-add/key behavior and duplicate topic/durable recipient checks for a simultaneous re-add/send race.
- GM-021 tests prove fresh re-add key-package binding and stale package rejection.
- `group_members` DB schema has primary key `(group_id, peer_id)`, `dbInsertGroupMember` uses `ConflictAlgorithm.replace`, and `InMemoryGroupRepository` stores members by peer ID, so local repo storage is already unique by peer ID.
- `buildGroupConfigPayload` currently maps the provided member list directly into `members`; it does not visibly normalize duplicate peer IDs if callers provide duplicates.
- `group_message_listener.dart` applies `groupConfig['members']` by iterating raw snapshot entries and syncing the original snapshot to Go; that can preserve duplicate entries from a remote authoritative config unless normalized before apply/sync.
- Go `cloneGroupConfig` currently deep-copies `Members` without deduping, `UpdateGroupConfig` stores the clone, and `findMember` scans in order and returns the first matching peer ID. There is an existing Go test documenting first-match duplicate behavior, which is the risk called out by GM-022.
- `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `integration_test/group_multi_party_device_real_harness.dart` currently enumerate scenarios only through `gm021`; `gm022` is unsupported today.

## regression/tests to add first

Add RED-first proof before product fixes:

- Dart host RED: add a `GM-022` selector that feeds duplicate Charlie entries into config-building or snapshot-application paths, then expects one final active Charlie entry and one Charlie config member. It should fail before normalization if duplicate input is preserved.
- Dart integration RED: add `GM-022` to `member_removal_integration_test.dart` and/or `group_membership_smoke_test.dart` to run 20 remove/re-add cycles, inspect raw member/config lists after every final sync, and send post-cycle messages. This should fail first if any duplicate config or recipient proof is missing; if repository uniqueness makes the local part pass, the missing row-owned criteria/simulator path still stays RED until implemented.
- Go RED: add `GM-022` tests proving duplicate config ingestion cannot shadow the active entry. A stale duplicate Charlie member placed before the active re-add member must not cause fresh Charlie validation to reject or stale Charlie validation to pass.
- Criteria RED: add `GM-022` accept/reject tests in `group_multi_party_device_criteria_test.dart` requiring `removeReaddCycleCount == 20`, exact one Charlie in raw member/config peer IDs per role, active Charlie count `1`, validator-active-entry proof, unique recipients, and exact delivery.
- Simulator RED: add `gm022` scenario support to the runner/harness/criteria and run it before the fix or before full harness fields are complete to prove the proof cannot pass with unsupported scenario or underspecified verdicts.

Minimum GM-022 verdict shape for criteria and harness:

- Top-level role verdicts keep existing `scenario`, `role`, `peerId`, `deviceId`, `memberPeerIds`, `sentMessages`, and received-message fields used by prior GM scenarios.
- Add `gm022RepeatedReaddDedupProof` to every Alice/Bob/Charlie verdict.
- Required proof fields: `removeReaddCycleCount`, `rawMemberPeerIds`, `configMemberPeerIds`, `duplicateMemberPeerIds`, `charlieMemberEntryCount`, `activeCharlieEntryCount`, `activeCharlieDeviceCount`, `validatorUsedActiveEntry`, `freshCharlieSendAccepted`, `staleShadowSendAccepted`, `postCycleDeliveryStable`, and `durableRecipientsUnique`.
- Criteria must reject cycle counts below `20`, any non-empty `duplicateMemberPeerIds`, Charlie counts other than `1`, active device count other than `1`, `validatorUsedActiveEntry != true`, `freshCharlieSendAccepted != true`, `staleShadowSendAccepted == true`, unstable delivery, or duplicate durable recipients.

## step-by-step implementation plan

1. Reconfirm current dirty status and avoid touching unrelated GM-008..GM-021 edits.
2. Add the RED tests and run the focused failing selectors first:
   - Go validator/config duplicate-shadow selector.
   - Dart duplicate config/member list selector.
   - GM-022 criteria selector.
   - GM-022 runner scenario support check.
3. Add a small shared Dart normalization path in `group_config_payload.dart` or an adjacent local helper:
   - Drop duplicate member entries by normalized `peerId`.
   - Prefer the active re-add entry, using later `joinedAt` or explicit active device data when comparing duplicate `GroupMember` records.
   - Deduplicate devices inside a member by active `deviceId`/`transportPeerId`, preferring active, non-revoked, later/fresher key-package data.
   - Preserve stable ordering for non-duplicates so unrelated config hashes and UI order do not churn.
4. Use that normalization in local config output:
   - `buildGroupConfigPayload`.
   - Any add/remove use-case path that builds a config from `getMembers`.
5. Normalize incoming authoritative config snapshots before local apply and Go sync:
   - In `group_message_listener.dart`, normalize `groupConfig['members']` before `_applyAuthoritativeGroupConfigSnapshot` and `_syncGroupConfig`.
   - Keep event watermark/order logic unchanged.
6. Inspect `group_key_update_listener.dart` only for active-device lookup regressions. Change it only if RED proof shows duplicate local/device state can bind a key update to a stale recipient/source device.
7. Add Go-side defensive normalization:
   - Normalize `GroupConfig.Members` in `JoinGroupTopic`/`UpdateGroupConfig` storage, likely inside `cloneGroupConfig` or a helper it calls.
   - Update or replace the duplicate-first `findMember` behavior so stored configs return the active re-add entry after duplicate input is normalized.
   - Keep validator rejection reasons stable unless the row-owned Go RED test proves a reason must change.
8. Inspect `group_inbox.go` recipient handling. Only change it if RED tests show Go-side callers can pass duplicate `recipientPeerIds`; otherwise leave it as an accepted non-change because Flutter send membership already dedupes recipients with a set.
9. Extend GM-022 proof support:
   - Add `_gm022Requirement` with Alice/Bob/Charlie roles in criteria.
   - Add `gm022` to supported scenario text, `_tryScenarioRequirement`, expected messages, evaluator, runner `_scenariosToRun`, and harness role map.
   - Add harness role flows for 20 remove/re-add cycles and post-cycle sends.
10. Run GREEN direct proof selectors, then adjacent host suites.
11. Run the exact simulator-only GM-022 proof on the specified devices and relay profile.
12. Run named gates and hygiene.
13. Stop. Do not broaden into `--scenario all`, source matrix closure, or GM-023+.

Stop early only if the RED tests prove current product behavior already satisfies the duplicate contract after 20 cycles. In that case, still complete row-owned GM-022 criteria/runner/harness proof support and run the exact simulator proof before calling the implementation sufficient.

## risks and edge cases

- Stale duplicate first entry in Go config can cause `findMember`/validator to bind to old role/device/key-package data.
- Remote membership snapshots can carry duplicates even if local DB primary keys prevent duplicate persisted rows.
- Multiple active devices or repeated key-package refreshes can make "active" ambiguous; comparison rules must be deterministic and tested.
- Deduping config members can affect state hashes; keep ordering stable for non-duplicates and update tests that intentionally hash config payloads only if their inputs now normalize duplicates.
- Race-sensitive listener ordering must keep existing membership watermark behavior from GM-011/GM-012/GM-014.
- Recipient dedupe must not accidentally omit a valid re-added Charlie after the final cycle.
- Simulator/Xcode build-state failures are repair/rerun infrastructure, not accepted final blockers.

## exact tests and gates to run

RED first, then GREEN after implementation:

```sh
(cd go-mknoon && go test ./node -run 'TestGM022|TestFindMember_DuplicatePeerId|TestGroupTopicValidator')
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-022'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-022'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-022'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-022'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-022'
```

Run this additional selector only if `group_key_update_listener.dart` is touched or duplicate active-device lookup proof is added there:

```sh
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'GM-022'
```

Adjacent host coverage:

```sh
flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test test/features/groups/integration/group_new_member_onboarding_test.dart
```

Conditional onboarding/crypto coverage:

```sh
flutter test --no-pub integration_test/group_real_crypto_onboarding_test.dart --plain-name 'Bob accepts a real encrypted invite, decrypts first-add and re-add group ciphertext'
```

Run the conditional onboarding/crypto command only if GM-022 touches invite acceptance, key package generation, onboarding, or crypto payload surfaces. It is supporting coverage, not a replacement for exact `gm022` simulator proof.

Exact simulator-only Device/Relay Proof Profile:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm022 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Simulator build-state recovery if the exact proof fails before app logic runs:

- Refresh device list with `flutter devices` and `xcrun simctl list devices`.
- Boot the exact simulators Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Uninstall the app and extensions from those simulators.
- Clear Runner/Pods DerivedData and `build/ios` if needed.
- Run `flutter pub get` or `flutter clean` only if dependency or build-state evidence requires it.
- Rerun the exact `--scenario gm022` command. Do not leave the session simulator/Xcode build-state blocked.

Named gates and hygiene:

```sh
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

If new test files are added, update `Test-Flight-Improv/test-gate-definitions.md` classification and keep completeness green. Do not update the source matrix or session breakdown as part of this planning task.

## known-failure interpretation

- The dirty worktree contains prior GM-008..GM-021 implementation and closure edits; do not revert or restage them.
- Initial `gm022` runner/criteria failures are expected RED until scenario support is added.
- Existing GM-010/GM-012/GM-014/GM-021 greens are supporting context only and must not be counted as GM-022 closure.
- Simulator/Xcode/app-install build-state failures require cleanup and rerun using the exact proof profile; they are not acceptable final blockers.
- Pre-existing warning noise outside GM-022 touched files can be recorded as residual only if direct GM-022 selectors and required gates pass.

## done criteria

- GM-022 RED selectors were observed failing for missing duplicate protection/proof, then passed after scoped changes.
- A/B/C host and simulator verdicts prove 20 remove/re-add cycles.
- Every final raw member/config peer ID list has no duplicates and exactly one Charlie entry.
- The final active Charlie entry has exactly one active device/key-package binding expected for the re-add.
- Go validator proof shows active re-add lookup, not stale duplicate shadowing.
- Post-cycle Alice/Bob/Charlie sends are delivered exactly once to expected recipients.
- Durable recipient lists contain no duplicates and no unexpected sender/self entries.
- Exact `--scenario gm022` simulator proof passes on the specified Alice/Bob/Charlie UDIDs with the required relay profile.
- `groups`, `completeness-check`, and `git diff --check` pass.

## scope guard

- Do not implement GM-023 or later rows.
- Do not run or require `--scenario all`.
- Do not require real external or physical devices.
- Do not redesign membership storage, event-log ordering, key rotation, invite acceptance, notification routing, or relay architecture.
- Do not turn this into a migration unless current DB evidence proves a persisted duplicate can exist despite `(group_id, peer_id)` primary key.
- Do not edit the source matrix or breakdown during planning.
- Do not paper over unsupported `gm022` simulator support by calling prior GM-010/GM-012/GM-021 proof sufficient.

## accepted differences / intentionally out of scope

- DB and in-memory repositories already enforce one member row per peer ID; GM-022 still needs config/listener/Go/harness proof because duplicates can appear in config lists before or outside repository persistence.
- GM-010 single duplicate re-add idempotence remains supporting proof only; GM-022 requires 20 cycles.
- GM-012 stale remove ordering and GM-014 delayed key behavior remain supporting proof only; GM-022 is about repeated-cycle duplicate peer ID shadowing.
- GM-021 fresh package binding remains supporting proof only; GM-022 additionally requires duplicate-free member/config lists and active-entry lookup after repeated churn.
- `group_inbox.go` should remain unchanged if direct proof shows Flutter recipient selection already dedupes all `recipientPeerIds`; add a Go test only if Go-side inbox request building is touched.

## dependency impact

- Later GM rows can rely on GM-022 only after the exact `gm022` proof records no duplicate member/config peer IDs after 20 cycles.
- If GM-022 changes shared config normalization, later membership rows should reuse the helper rather than invent row-specific duplicate filters.
- If GM-022 cannot establish deterministic active-entry selection, later stale-shadow rows such as GM-023 should remain blocked or be decomposed separately.

## reviewer questions to answer

- Sufficiency: sufficient with adjustments.
- Missing files/tests/gates: no structural omissions after adding explicit `gm022RepeatedReaddDedupProof` fields and making the key-update selector conditional on touching that file.
- Stale assumptions: none found. Current runner/criteria/harness really stop at `gm021`; Go `findMember` really returns first duplicate; local DB/repo uniqueness does not prove config uniqueness.
- Overengineering: no structural overengineering. Shared normalization is acceptable because duplicate member config can enter through more than one local path, but it must stay limited to membership/config entries and not become a broader membership redesign.
- Decomposition: sufficient. RED proof, Dart normalization, Go defensive normalization, criteria/harness scenario support, simulator proof, and gates are separable.
- Minimum to make sufficient: the proof field tightening above.

## arbiter stop rule

If reviewer finds no structural blocker, the plan may advance to `execution-ready`. If reviewer finds structural blockers, patch this plan once, run one final reviewer pass, then one final arbiter pass. Do not loop on incremental wording details.

## arbiter decision

Final verdict: `execution-ready`.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact helper/function names for Dart and Go normalization are left to implementation after RED tests are added.
- `group_key_update_listener.dart` remains inspect-first and only needs a GM-022 selector if implementation touches key-update active-device lookup.
- `group_inbox.go` remains inspect-first and should only change if direct RED evidence shows Go-side recipient duplication.

Accepted differences intentionally left unchanged:

- DB/repo uniqueness is accepted as supporting evidence, not closure.
- GM-010/GM-012/GM-014/GM-021 remain supporting context only.
- Simulator-only proof is required and sufficient for GM-022; physical/external devices and `--scenario all` are intentionally out of scope.

Why this plan is safe to implement now: it is scoped to GM-022, starts with RED-first proof, requires exact host/Go/criteria/simulator evidence, defines build-state recovery instead of accepting simulator blockage, and has explicit non-goals that prevent drift into later GM rows or broad architecture changes.
