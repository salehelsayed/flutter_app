# GM-023 Plan - Inactive Shadow Member Cannot Break Active Charlie

Status: execution-ready

## Planning Progress

- 2026-05-11T08:20:58Z - Planner completed. Files inspected since last update: this GM-023 plan draft. Decision/blocker: draft is implementation-ready if reviewer accepts the row-owned proof contract, the active-or-reject closure bar, and the simulator build-state recovery rule. Next action: Reviewer pass.
- 2026-05-11T08:24:26Z - Reviewer started. Files inspected since last update: this GM-023 plan draft. Decision/blocker: review focus is proof sufficiency, exact simulator constraints, no-docs-only posture, and avoiding source-matrix/breakdown edits. Next action: record sufficiency findings.
- 2026-05-11T08:24:26Z - Reviewer completed. Files inspected since last update: this GM-023 plan draft. Decision/blocker: sufficient with adjustments; no structural blocker found, but the plan must keep product-code changes conditional on RED evidence while making GM-023 proof support mandatory. Next action: Arbiter pass.
- 2026-05-11T08:25:05Z - Arbiter started. Files inspected since last update: reviewer findings and this GM-023 plan. Decision/blocker: classify findings as structural blockers, incremental details, or accepted differences. Next action: final arbiter decision.
- 2026-05-11T08:25:05Z - Arbiter completed. Files inspected since last update: final GM-023 plan. Decision/blocker: no structural blockers remain; proof-support mandate and conditional product-code posture are already captured. Next action: hand off execution-ready plan.

## real scope

GM-023 owns exactly the stale inactive/tombstone Charlie shadow risk for private group membership configs where an inactive Charlie entry appears before an active Charlie entry.

In scope:

- Add row-owned RED-first proof for a config/list containing inactive Charlie before active Charlie.
- Ensure authorization uses the active Charlie record or rejects the duplicate config fail-closed; an inactive shadow must not cause active Charlie delivery to fail.
- Ensure discovery/dial expectations use active configured Charlie identity, or fail closed before stale inactive identity can be used.
- Add `gm023` criteria, runner, harness, and exact simulator proof on Alice/Bob/Charlie.
- Inspect the likely shared seams from the breakdown: `add_group_member_use_case.dart`, `remove_group_member_use_case.dart`, `group_message_listener.dart`, `group_key_update_listener.dart`, `group_config_payload.dart`, `go-mknoon/node/pubsub.go`, and `go-mknoon/node/group_inbox.go`.

Out of scope:

- Closing or editing GM-024+ rows.
- Source matrix or session-breakdown edits during this planning task.
- Broad membership schema redesign, key-rotation redesign, relay architecture changes, notification changes, or new external-device requirements.
- `--scenario all`, physical devices, or real external devices.

## closure bar

GM-023 is done only when row-owned proof shows all of the following:

- The RED fixture places inactive/tombstone Charlie before active Charlie in the member/config list.
- Either the duplicate/inactive-shadow config is rejected fail-closed, or the active Charlie entry is selected for config output, Go lookup, authorization, and discovery/dial expectations.
- Fresh active Charlie send is accepted and reaches Alice/Bob exactly once.
- A stale inactive Charlie shadow send is rejected and produces no plaintext on Alice/Bob.
- Discovery/dial proof cannot use the inactive/tombstone Charlie identity to count, dial, or satisfy active Charlie reachability.
- Durable `recipientPeerIds` are unique and contain only expected active recipients.
- Exact simulator-only `--scenario gm023` passes on the specified three iOS simulators with the required relay profile.
- `groups`, `completeness-check`, and `git diff --check` pass.

## source of truth

- Current code and tests win over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` is authoritative for named gates and test classification.
- The GM-023 source row in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` is authoritative for the row contract until closure updates it.
- The GM-023 row in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is authoritative for session classification and likely files.
- GM-022 closure is supporting context only. It proves duplicate-member normalization and stale-shadow rejection for `gm022`, but it explicitly leaves GM-023 open and does not provide row-owned inactive-shadow proof.

## session classification

`implementation-ready`

This is not docs-only. The source row is Open, the breakdown says `needs_code_and_tests | implementation-ready | code changes + tests`, and there is no `GM-023` host/Go/criteria proof or `gm023` simulator scenario. If new RED tests prove the current GM-022 code already satisfies the product seam, implementation may stop product-code changes, but it must still add GM-023-owned proof support and exact simulator evidence before closure.

## exact problem statement

GM-023 targets the case where implementation keeps inactive or tombstoned Charlie rows and an inactive Charlie entry appears before the active Charlie entry. The missing proof is that this inactive first entry cannot shadow active Charlie in authorization, validator lookup, discovery/dial, or durable delivery.

Current code after GM-022 appears to normalize duplicate member/config entries and make Go `findMember` prefer active/fresher entries. That is useful evidence, but it is not GM-023 closure because the row requires an inactive/tombstone-before-active Charlie proof and exact `gm023` simulator evidence.

Required improvement: active Charlie must be able to send and be discovered/dialed after an inactive shadow is present before the active record, or the duplicate config must be rejected before stale state can affect delivery.

Must stay unchanged: existing admin/invite/remove permission checks, membership event watermark ordering, GM-021 fresh key-package binding, GM-020 post-removal recipient exclusion, group encryption/decryption semantics, and named gate definitions except when classifying any newly added test file.

## files and repos to inspect next

Production and bridge/config seams:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/group_members_db_helpers.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/group_inbox.go`

Tests and simulator proof support:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/group_inbox_test.go` if `group_inbox.go` is touched or recipient request behavior changes.
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart` only if key-update recipient binding is touched.
- `test/features/groups/application/send_group_message_use_case_test.dart` only if recipient selection is touched.
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `integration_test/group_real_crypto_onboarding_test.dart` only if invite/key-package/onboarding/crypto surfaces change.
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `Test-Flight-Improv/test-gate-definitions.md` if a new test file is added.

## existing tests covering this area

- GM-022 code already added normalization in `group_config_payload.dart`, `group_message_listener.dart`, and `go-mknoon/node/pubsub.go`.
- `go-mknoon/node/pubsub_test.go::TestGM022GroupTopicValidatorUsesActiveReaddEntryOverStaleDuplicate` uses a revoked Charlie device before an active Charlie device and proves active send acceptance plus stale shadow rejection under GM-022 naming.
- `go-mknoon/node/pubsub_test.go::TestFindMember_DuplicatePeerId_ReturnsActiveReaddEntry` and `TestGM022CloneGroupConfigDedupesRepeatedReaddShadow` prove Go lookup/clone behavior for duplicate Charlie entries.
- `test/features/groups/application/add_group_member_use_case_test.dart` has a GM-022 config payload test that emits one active Charlie after a revoked Charlie shadow.
- `test/features/groups/application/group_message_listener_test.dart` has a GM-022 listener test that normalizes a duplicate config snapshot before bridge sync and local persistence.
- `test/features/groups/application/member_removal_integration_test.dart` and `test/features/groups/integration/group_membership_smoke_test.dart` contain GM-022 repeated remove/re-add proof and stable delivery.
- `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart` currently support scenarios through `gm022`; `gm023` is unsupported and should be a RED proof point.
- Missing: GM-023-owned inactive/tombstone-before-active selectors, explicit discovery/dial proof, criteria rejection/acceptance tests for `gm023InactiveShadowProof`, and exact simulator-only `--scenario gm023`.

## regression/tests to add first

Add RED-first proof before product fixes:

- Go RED: add `GM-023` tests where inactive/tombstoned Charlie appears before active Charlie. The tests must cover validator authorization, `findMember`/config clone or fail-closed duplicate handling, stale shadow rejection, and discovery/dial member selection.
- Dart host RED: add a `GM-023` selector for config payload/listener application that feeds inactive Charlie before active Charlie and expects either one active Charlie config entry or a rejected duplicate config path with no stale sync.
- Dart integration RED: add `GM-023` to `member_removal_integration_test.dart` and/or `group_membership_smoke_test.dart` to prove active Charlie can send after the inactive shadow fixture and durable recipients remain unique.
- Criteria RED: add `GM-023` accept/reject tests in `group_multi_party_device_criteria_test.dart`; reject missing proof, inactive-before-active not asserted, fresh active send not accepted, stale inactive shadow accepted, discovery/dial not active-safe, duplicate recipients, or missing exact receiver delivery.
- Simulator RED: add `gm023` scenario support to runner/harness/criteria and show the unsupported or underspecified path fails before the proof is implemented.

Minimum `gm023InactiveShadowProof` shape for criteria and harness:

- Top-level role verdicts keep existing `scenario`, `role`, `peerId`, `deviceId`, `memberPeerIds`, `sentMessages`, and received-message fields used by prior GM scenarios.
- Add `gm023InactiveShadowProof` to every Alice/Bob/Charlie verdict.
- Required proof fields: `inactiveShadowBeforeActive`, `duplicateConfigRejected`, `activeEntrySelected`, `freshCharlieSendAccepted`, `staleInactiveShadowSendAccepted`, `discoveryUsedActiveEntry`, `inactiveShadowDialedOrCounted`, `postShadowDeliveryStable`, `durableRecipientsUnique`, `charlieMemberEntryCount`, `activeCharlieEntryCount`, `activeCharlieDeviceCount`, `rawMemberPeerIds`, and `configMemberPeerIds`.
- Criteria must accept either `duplicateConfigRejected == true` with fail-closed delivery semantics, or `duplicateConfigRejected == false` with `activeEntrySelected == true`, `freshCharlieSendAccepted == true`, `staleInactiveShadowSendAccepted == false`, `discoveryUsedActiveEntry == true`, `inactiveShadowDialedOrCounted == false`, stable exact delivery, and unique durable recipients.

## step-by-step implementation plan

1. Reconfirm dirty status and avoid reverting or modifying unrelated GM-008..GM-022 edits.
2. Add RED tests and run focused failing selectors first:
   - Go GM-023 validator/config/discovery selector.
   - Dart GM-023 config/listener selector.
   - GM-023 member-removal or membership-smoke host selector.
   - GM-023 criteria selector.
   - GM-023 runner scenario support check.
3. If the RED tests show the current GM-022 product code already satisfies active-or-reject behavior, stop product-code changes and move to proof support. Do not call this docs-only; row-owned criteria, runner, harness, simulator, and gates still need implementation.
4. If Dart config/listener proof fails, tighten `group_config_payload.dart` normalization so inactive/revoked devices cannot outrank an active Charlie record. Keep stable ordering for unrelated members and update state hash expectations only as needed.
5. If listener proof fails, normalize incoming authoritative `groupConfig['members']` before local apply and bridge `group:updateConfig` sync in `group_message_listener.dart`. Keep event watermark, signed audit, and duplicate event behavior unchanged.
6. If add/remove use-case proof fails, ensure they build bridge configs through the shared normalizer. Do not add a separate row-specific filter.
7. If Go authorization proof fails, tighten Go normalization and lookup in `go-mknoon/node/pubsub.go`:
   - Store normalized configs through `JoinGroupTopic` and `UpdateGroupConfig`.
   - Keep `findMember` active/fresher-preferred, or reject duplicate configs fail-closed if deterministic active selection is impossible.
   - Preserve existing validator rejection reasons unless the RED test proves a reason change is required.
8. If discovery/dial proof fails, introduce a small helper for active group dial/discovery peer identities:
   - Use active device `TransportPeerId` when first-class devices exist.
   - Fall back to legacy `member.PeerId` only when no devices exist.
   - Use the helper in `discoverAndConnectGroupPeers`, `dialKnownGroupMembers`, `dialKnownGroupMembersDirectOnly`, `countConnectedGroupMembers`, `expectedConnectedGroupMembers`, and `countRemoteGroupMembers` only to the extent RED proof requires.
9. Inspect `group_key_update_listener.dart` only if key-update recipient binding can still bind to an inactive device. Add and run a GM-023 selector if touched.
10. Inspect `send_group_message_use_case.dart` and `group_inbox.go` only if durable recipient proof shows inactive shadow recipients or duplicate recipients can be emitted. Leave them unchanged if existing set-based recipient selection and inbox request building are sufficient.
11. Extend GM-023 proof support:
    - Add `_gm023Requirement` with Alice/Bob/Charlie roles in criteria.
    - Add `gm023` to supported scenario text, `_tryScenarioRequirement`, expected messages, evaluator routing, runner `_scenariosToRun`, and harness role map.
    - Add harness role flows that create or inject inactive Charlie before active Charlie, prove active Charlie delivery, stale shadow rejection, active-safe discovery/dial, and unique durable recipients.
12. Run GREEN direct proof selectors, then adjacent host suites.
13. Run exact simulator-only `gm023` proof on the specified simulators and relay profile.
14. Run named gates and hygiene.
15. Stop. Do not broaden into `--scenario all`, physical devices, source matrix closure, or GM-024+.

## risks and edge cases

- GM-022 may already fix much of the seam; GM-023 still needs row-owned inactive-shadow proof and exact `gm023` simulator evidence.
- Inactive can mean a revoked device in current code, while there is no member-level inactive enum. Do not invent a schema migration unless RED evidence proves device-level status is insufficient.
- Removing inactive entries from wire/config normalization must not delete historical event-log evidence or membership audit history.
- Discovery/dial paths currently iterate config members in several places; active-device transport identity handling must preserve legacy no-device behavior.
- Duplicate config normalization can change state hashes; keep unrelated member ordering stable.
- If active/inactive entries tie on freshness, deterministic selection must not depend on accidental map/list ordering unless the plan explicitly keeps later active entries winning.
- Simulator/Xcode build-state failures are repair/rerun infrastructure, not accepted final blockers.

## exact tests and gates to run

RED first, then GREEN after implementation:

```sh
(cd go-mknoon && go test ./node -run 'TestGM023|TestFindMember_DuplicatePeerId|TestGroupTopicValidator|TestGroupPeerDiscovery')
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-023'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-023'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-023'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-023'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-023'
```

Run these only if the corresponding files are touched:

```sh
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'GM-023'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-023'
(cd go-mknoon && go test ./node -run 'TestGroupInbox|TestGM023')
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

Run the conditional onboarding/crypto command only if GM-023 touches invite acceptance, key package generation, onboarding, or crypto payload surfaces. It is supporting coverage, not a replacement for exact `gm023` simulator proof.

Exact simulator-only Device/Relay Proof Profile:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm023 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Simulator build-state recovery if the exact proof fails before app logic runs:

- Refresh device list with `flutter devices` and `xcrun simctl list devices`.
- Boot the exact simulators: Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Uninstall the Runner app and extensions from those simulators.
- Clear Runner/Pods DerivedData and `build/ios` if needed.
- Run `flutter pub get` or `flutter clean` only if dependency or build-state evidence requires it.
- Rerun the exact `--scenario gm023` command. Do not leave the session simulator/Xcode build-state blocked.

Named gates and hygiene:

```sh
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

If a new test file is added, update `Test-Flight-Improv/test-gate-definitions.md` classification and keep completeness green. Do not update the source matrix or session breakdown as part of this planning task.

## known-failure interpretation

- The dirty worktree contains prior GM-008..GM-022 implementation and closure edits; do not revert them.
- Initial `gm023` runner/criteria failures are expected RED until scenario support is added.
- Existing GM-010/GM-012/GM-014/GM-021/GM-022 greens are supporting context only and must not be counted as GM-023 closure.
- If new direct GM-023 tests pass before product changes, record that as current-code evidence and continue with row-owned proof support instead of forcing a redundant product edit.
- Simulator/Xcode/app-install build-state failures require cleanup and rerun using the exact proof profile; they are not acceptable final blockers.
- Pre-existing warning noise outside GM-023 touched files can be recorded as residual only if direct GM-023 selectors and required gates pass.

## done criteria

- GM-023 RED selectors were observed failing for missing proof/scenario support or product behavior, then passed after scoped changes.
- The fixture explicitly places inactive/tombstone Charlie before active Charlie.
- Active Charlie is selected for authorization/discovery/dial, or duplicate config is rejected fail-closed before stale state can affect delivery.
- Fresh active Charlie send is accepted and delivered exactly once to Alice/Bob.
- Stale inactive Charlie shadow send is rejected and produces zero Alice/Bob plaintext.
- Discovery/dial proof shows inactive shadow was not dialed, counted, or used as active Charlie reachability.
- Durable recipient lists contain only expected recipients and no duplicates.
- Exact `--scenario gm023` simulator proof passes on the specified Alice/Bob/Charlie UDIDs with the required relay profile.
- `groups`, `completeness-check`, and `git diff --check` pass.

## scope guard

- Do not edit product/test code during this planning task.
- Do not edit the source matrix or session breakdown during this planning task.
- Do not implement GM-024 or later rows.
- Do not run or require `--scenario all`.
- Do not require physical or real external devices.
- Do not redesign membership storage, event-log ordering, key rotation, invite acceptance, notification routing, or relay architecture.
- Do not introduce a member-level inactive schema or migration unless direct RED evidence proves current device-level inactive/revoked handling cannot satisfy GM-023.
- Do not treat GM-022 proof as GM-023 closure without GM-023-specific inactive-shadow proof.

## accepted differences / intentionally out of scope

- GM-022 duplicate-member normalization is accepted as supporting evidence, not closure.
- Repository and DB uniqueness by `(group_id, peer_id)` is accepted as supporting evidence, not closure, because configs and remote snapshots can still carry duplicate or inactive-before-active entries.
- Conditional real-crypto onboarding is required only if onboarding, invite, key-package generation, or crypto payload surfaces change.
- `group_inbox.go` should remain unchanged if direct proof shows Flutter already emits unique active recipient IDs.
- Simulator-only proof is required and sufficient for this row; physical/external devices and `--scenario all` are intentionally out of scope.

## dependency impact

- Later membership rows can rely on GM-023 only after exact `gm023` proof records active-or-reject behavior for inactive-before-active Charlie.
- If GM-023 introduces an active dial/discovery identity helper, later group connectivity work should reuse it instead of adding row-specific dial filters.
- If GM-023 cannot prove deterministic active selection or fail-closed rejection, later stale-state rows must remain open or be decomposed separately.

## reviewer questions to answer

- Sufficiency: sufficient with adjustments.
- Missing files/tests/gates: no structural omissions after including RED-first Go, Dart host, criteria, runner/harness, exact simulator `gm023`, adjacent host suites, named gates, and build-state recovery.
- Stale assumptions: the source row's "findMember first-match" risk is partly stale after GM-022, but the GM-023 proof gap remains current because there is no row-owned inactive-shadow evidence or `gm023` scenario.
- Overengineering: the plan is narrow if product changes remain conditional on RED evidence. The active dial/discovery helper is acceptable only if discovery/dial RED tests fail.
- Decomposition: sufficient. Direct tests, optional product fixes, proof support, simulator proof, and gates are separable.
- Minimum needed to make sufficient: keep row-owned proof support mandatory even if direct product tests pass pre-fix, and keep source matrix/breakdown closure out of this planning task.

## arbiter stop rule

If reviewer finds no structural blocker, the plan may advance to `execution-ready`. If reviewer finds structural blockers, patch this plan once, run one final reviewer pass, then one final arbiter pass. Do not loop on incremental wording details.

## arbiter decision

Final verdict: `execution-ready`.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact helper/function names for any active dial/discovery identity helper are left to implementation after RED tests.
- Exact `gm023InactiveShadowProof` field names can be tightened in implementation if criteria and harness stay semantically equivalent.
- `group_key_update_listener.dart`, `send_group_message_use_case.dart`, and `group_inbox.go` remain inspect-first and should only change if direct GM-023 proof fails there.

Accepted differences intentionally left unchanged:

- GM-022 stays supporting evidence only; it does not close GM-023.
- Product-code edits are conditional on RED evidence, but GM-023 proof support is mandatory because the source row is Open and no row-owned proof exists.
- Simulator-only proof is required and sufficient; physical/external devices and `--scenario all` are intentionally out of scope.
- Real-crypto onboarding remains conditional on touching onboarding, invite, key-package, or crypto payload surfaces.

Why this plan is safe to implement now: it is scoped to GM-023, starts with RED-first host/Go/criteria/simulator proof, requires exact simulator-only `gm023` evidence on the specified UDIDs, defines build-state repair/rerun rather than accepting simulator blockage, and keeps source matrix/breakdown closure out of this planning task.

## Execution Progress

- 2026-05-11T08:27:19Z - Contract extracted. Files inspected/touched: this GM-023 plan and `git status --short`. Decision/blocker: execute GM-023 only; source matrix and session breakdown are dirty but off-limits for this session; GM-022 support is context only and cannot close GM-023. Required proof includes RED-first inactive-shadow tests, exact `--scenario gm023` simulator run on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, plus `groups`, `completeness-check`, and `git diff --check`. Next action: spawn isolated Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-11T08:28:08Z - Executor spawn retry. Files inspected/touched: this GM-023 plan. Decision/blocker: initial `codex exec` command failed before child materialization because `-a` is not supported by this CLI's `exec` subcommand; no child work or repo code changes occurred. Next action: respawn Executor with supported CLI options.
- 2026-05-11T08:29:12Z - Executor started. Files inspected/touched: this GM-023 plan and `git status --short`. Decision/blocker: role is Executor only; execute GM-023 without touching source matrix/session breakdown and without counting GM-022 as closure. Next action: inspect GM-022 code/test seams and add GM-023 RED proof selectors.
- 2026-05-11T08:32:40Z - RED proof edit started. Files inspected/touched: `group_config_payload.dart`, `group_message_listener.dart`, `go-mknoon/node/pubsub.go`, GM-022 tests/harness/criteria/runner seams. Decision/blocker: current config/validator normalization appears active-preferred, but Go discovery/dial/count paths still need GM-023 inactive-shadow proof because they iterate configured member IDs in several places. Next action: add GM-023 RED selectors before product changes.
- 2026-05-11T08:41:25Z - RED observed. Files touched: `go-mknoon/node/pubsub_test.go`, `add_group_member_use_case_test.dart`, `group_message_listener_test.dart`, `member_removal_integration_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_criteria_test.dart`. Commands/results: Go focused selector failed at `TestGM023GroupPeerDiscoveryUsesActiveDeviceAfterInactiveShadow` because `countRemoteGroupMembers` returned 2 instead of 1; `gm023` criteria selector failed because scenario support is missing; exact runner command failed fast with unsupported `gm023`. Dart config/listener/member-removal/smoke GM-023 selectors passed, so product changes should stay limited to Go discovery/dial/count plus criteria/runner/harness proof support. Next action: implement smallest active-device discovery/dial helper and GM-023 criteria/runner/harness support.
- 2026-05-11T08:51:48Z - GREEN focused host proof completed. Files touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, GM-023 Dart host tests, criteria, runner, and real-device harness. Commands/results: Go focused selector passed; all exact GM-023 Flutter host selectors passed (`add_group_member_use_case_test.dart`, `group_message_listener_test.dart`, `member_removal_integration_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_criteria_test.dart`). Decision/blocker: product code changed only in Go discovery/dial/count target selection; Flutter product config/listener/send behavior needed proof only. Next action: run adjacent host suites, exact simulator proof, named gates, and hygiene.
- 2026-05-11T08:59:29Z - Exact simulator proof cleanup path entered. Files inspected/touched: simulator orchestrator output only. Commands/results: exact `--scenario gm023` run launched Alice and Bob, then failed before Charlie app logic while installing Runner on Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` with `IXErrorDomain code=19` / failed to acquire termination assertion; stale Alice/Bob child processes were terminated after the failed orchestrator stayed alive. Decision/blocker: this is pre-app simulator/Xcode install state, not GM-023 app logic. Next action: refresh device inventory, boot exact simulators as needed, uninstall app/extension bundles, clear stale iOS build state if needed, then rerun exact proof.
- 2026-05-11T09:04:27Z - Exact simulator proof rerun still blocked before app logic. Files inspected/touched: simulator orchestrator output only. Commands/results: after device inventory refresh and uninstalling `com.mknoon.app`, `com.mknoon.app.ShareExtension`, and `com.mknoon.app.NotificationService` from all three exact simulators, the rerun again launched Alice and Bob, then Charlie failed during Runner install with the same `IXErrorDomain code=19` termination assertion error. Decision/blocker: still simulator/CoreSimulator/Xcode install state, not GM-023 app behavior. Next action: stop stale child processes, clear stale Runner/Pods DerivedData and `build/ios`, reboot exact simulator state, run package/build cleanup only as needed, then rerun exact proof once more.
- 2026-05-11T09:14:17Z - Exact simulator GM-023 proof passed after full cleanup. Files inspected/touched: simulator orchestrator output only; no additional code edits. Commands/results: after clearing `build/ios`, stale Runner/Pods DerivedData, rebooting the exact simulator set, and uninstalling app/extension bundles again, the exact `--scenario gm023` run passed on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Verdict directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm023_Ct6xrV`; orchestrator verdict: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm023_Ct6xrV/gmp_1778490465751_gm023_orchestrator_verdict.json`; role verdict files: `gmp_1778490465751_alice_verdict.json`, `gmp_1778490465751_bob_verdict.json`, `gmp_1778490465751_charlie_verdict.json`. Decision/blocker: GM-023 simulator proof is green; earlier Charlie failures were simulator install state only. Next action: run required named gates and hygiene.
- 2026-05-11T09:16:21Z - Executor verification completed. Files inspected/touched: this plan and command outputs. Commands/results: `./scripts/run_test_gates.sh groups` PASS; `./scripts/run_test_gates.sh completeness-check` PASS (`731/731` classified); `git diff --check` PASS; `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart` PASS. Adjacent pair `flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart` still FAILS only at non-GM023 `GM-019 durable recipients exclude Charlie during removal and include Charlie after re-add` (`member_removal_integration_test.dart:1235`, expected `['peer-bob']`, actual `['peer-charlie', 'peer-bob']`); the GM-023 selector in that same run passed. Decision/blocker: GM-023 proof is complete; residual adjacent failure belongs to existing GM-019/dirty prior-work surface and should be reviewed by QA, not closed by this GM-023 executor.
- 2026-05-11T09:24:43Z - QA Reviewer completed. Files inspected/touched: QA artifact `/tmp/gm023-qa-final.md` and this plan. Commands/results: QA reran `go test ./node -run 'TestGM023|TestFindMember_DuplicatePeerId|TestGroupTopicValidator|TestGroupPeerDiscovery'` PASS, focused GM-023 Flutter selectors PASS (7 tests), `./scripts/run_test_gates.sh groups` PASS (128 tests), `./scripts/run_test_gates.sh completeness-check` PASS (`731/731` classified), `git diff --check` PASS, and `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-019'` FAIL at the known non-GM023 adjacent assertion. QA directly inspected the exact simulator orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm023_Ct6xrV/gmp_1778490465751_gm023_orchestrator_verdict.json` and all three role verdicts; `gm023InactiveShadowProof` fields pass and role devices match the required simulator UDIDs. Decision/blocker: QA verdict PASS for GM-023 with no blocking findings and no fix pass needed; GM-019 failure is non-blocking residual dirty-worktree risk.
