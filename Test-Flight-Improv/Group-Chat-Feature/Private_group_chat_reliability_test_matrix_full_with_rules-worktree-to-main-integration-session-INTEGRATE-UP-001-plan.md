# INTEGRATE-UP-001 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-001-plan.md`
- Source row: `UP-001` / Member list, local DB, and Go config stay in sync after every operation
- Row-owned source anchors:
  - `test/features/groups/application/group_membership_config_sync_use_case_test.dart`: `create add remove and re-add keep local DB and Go config payloads aligned`
  - `test/features/groups/integration/group_membership_smoke_test.dart`: `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned`
  - `test/features/groups/presentation/group_info_wired_test.dart`: `UP-001 reloads visible member list from local DB after create add remove and re-add`
  - `go-mknoon/node/pubsub_test.go`: `TestUP001UpdateGroupConfigTracksAddRemoveReaddValidator`
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`: `up001MembershipConfigSyncProof` on `private_readd_current`

Imported delta:
- Added the row-owned application proof that create, add, remove, and re-add keep local DB member rows and generated `groupConfig` state hashes aligned.
- Added the row-owned fake-network/smoke proof that each membership operation updates DB state and the bridge `group:updateConfig` member/config snapshots in the same order.
- Added the row-owned widget proof that `GroupInfoWired` reloads and renders the current member list from local DB state after create, remove, and re-add.
- Added the row-owned native proof that `UpdateGroupConfig` drives validator membership acceptance/rejection through add, remove, and re-add transitions.
- Added the row-owned live criteria/harness proof fields for Alice, Bob, and Charlie on `private_readd_current`, requiring DB/config/UI convergence, operation snapshots, native validator host coverage, and live three-party evidence.

Out of scope:
- No original source worktree plan recreation or rerun.
- No production rewrite; current main already had the supporting membership/config sync behavior.
- No UP-002 timeline rendering, UP-003 compose gating, UP-004 unread counts, UP-005 invite state, UP-006 banner/system row, UP-007 transaction/bridge-call auditing, UP-008 pending outbound restart reconciliation, UP-009 identity rendering, media/reaction rows, notification rows, source-doc, COMPLETE_1 doc, Android, physical iOS, or unrelated residual repair.

Verification evidence:
- `cd go-mknoon && go test ./node -run 'TestUP001UpdateGroupConfigTracksAddRemoveReaddValidator|TestGroupTopicValidator_AcceptsNewMemberAfterConfigUpdate|TestGroupTopicValidator_RejectsRemovedMemberAfterConfigUpdate' -count=1` - pass.
- `flutter test --no-pub test/features/groups/application/group_membership_config_sync_use_case_test.dart --plain-name "create add remove and re-add keep local DB and Go config payloads aligned"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned"` - pass.
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "UP-001 reloads visible member list from local DB after create add remove and re-add"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "UP-001 rejects private_readd_current without membership/config sync proof"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "accepts private_readd_current RA-014 proof verdicts"` - pass.
- `gofmt -w go-mknoon/node/pubsub_test.go` - pass.
- `dart format --set-exit-if-changed test/features/groups/application/group_membership_config_sync_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/presentation/group_info_wired_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass with 0 changed after formatting.
- Scoped `dart analyze test/features/groups/application/group_membership_config_sync_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/presentation/group_info_wired_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass, `No issues found!`.
- Scoped `git diff --check` over the touched UP-001 code/test/harness files - pass.
- Live iOS 26.2 proof passed: `private_readd_current` run id `1779318063584`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_VnO3xx`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, orchestrator verdict `private_readd_current proof passed: private_readd_current verdicts valid for alice, bob, charlie`.

Controller acceptance evidence:
- Read-only scouts and controller disk checks found UP-001 production behavior already compatible with current main; the missing meaningful row-owned delta was proof coverage in application, fake-network, widget, native, criteria, harness, and criteria-test surfaces.
- The controller imported only UP-001-owned proof deltas and did not import UP-002+ timeline/UI state rows, notification rows, media/reaction rows, source docs, COMPLETE_1 docs, or unrelated worktree changes.
- All required focused row tests, affected `private_readd_current` criteria preservation, scoped hygiene, and iOS 26.2 live proof passed.
