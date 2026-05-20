# INTEGRATE-BB-007 Standard Integration Plan

Status: accepted

Run mode: standard integration, not gap-closure.

## Planning Progress

- 2026-05-17 03:18:46 CEST - Evidence Collector started. Files inspected since last update: main checkout status, source worktree status, output plan path existence. Decision/blocker: output plan did not exist; main and source worktree both contain unrelated dirty state that must not be reverted. Next action: inspect BB-007 rows, historical plan/evidence, COMPLETE_1 overlap, and git diff evidence for row-owned files.
- 2026-05-17 03:31:00 CEST - Evidence Collector completed. Files inspected since last update: integration breakdown BB-007 ledger row, source matrix BB-007 row, source breakdown BB-007 session block, historical BB-007 plan/evidence, source commit `833fa2c9`, current main candidate files, and COMPLETE_1 overlap searches. Decision/blocker: BB-007 is absent from main and the four row-owned test-file patch applies cleanly with offsets; no production-code import is planned. Next action: draft minimal row-owned import contract.
- 2026-05-17 03:34:00 CEST - Planner completed. Files inspected since last update: source row-owned patch applicability output and main duplicate searches. Decision/blocker: plan should import only four missing BB-007 test selectors and ignore source closure docs; ledger updates occur only after execution evidence. Next action: reviewer checks conflict stop rules, duplicate checks, and test contract.
- 2026-05-17 03:36:00 CEST - Reviewer completed. Files inspected since last update: complete draft plan sections, current dirty-state constraints, COMPLETE_1 overlap list, and test/gate commands. Decision/blocker: sufficient as standard integration plan; add explicit stop if any candidate file has unrelated unresolved edits that make the four selector imports non-mechanical. Next action: arbiter finalizes terminal contract.
- 2026-05-17 03:38:00 CEST - Arbiter completed. Files inspected since last update: reviewer finding and final plan. Decision/blocker: no structural blocker remains; execution is allowed only as import/reconcile/verify work. Final terminal contract target: accepted.

## real scope

Import or reconcile exactly source row `BB-007`: "Full-config join payload round-trips exactly through Dart and Go."

Allowed execution delta is limited to missing meaningful BB-007 test proof in main:

- `test/core/bridge/go_bridge_client_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`

Do not change production Dart, Go, database, relay, UI, notification, media, harness, or device code. Do not recreate, rerun, or rewrite the original worktree implementation plan. Reuse the historical BB-007 plan and commit evidence as source-of-truth.

## closure bar

BB-007 is integrated when main has the row-owned BB-007 tests proving:

- Dart `callGroupJoinWithConfig` forwards exact `groupId`, nested `groupConfig`, `groupKey`, and non-default `keyEpoch` through `GoBridgeClient` to native `groupJoinTopic`, with no `topicName`.
- Flutter pending-invite acceptance stores and joins with exact invite material and app-layer replay stores a recovered message under epoch `7`.
- Go bridge `GroupJoinTopic` accepts the full config/key/epoch payload and can publish after the first join.
- Go node live two-node delivery decrypts at the joined epoch and emits no decryption failure.

## source of truth

- Active integration contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`, row `INTEGRATE-BB-007`.
- Source worktree row contract: `Private_group_chat_reliability_test_matrix_full_with_rules.md`, row `BB-007`.
- Source worktree session evidence: `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`, `### Session BB-007`.
- Historical plan/evidence: `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-007-plan.md`.
- Git evidence: source commit `833fa2c9 BB-007: prove full config group join round trip`, which changed the four test files above plus source closure docs.
- Current main code/tests win over stale prose. Existing uncommitted main changes must be preserved.

## session classification

`implementation-ready` as a standard integration import.

Reason: the row is covered in the source worktree, pending integration in main, absent from main by selector search, and the row-owned four-test patch passed `git apply --check` against the current main worktree.

## exact problem statement

Main has BB-001 through BB-006 integration work, but does not yet contain BB-007 selectors. Without importing BB-007 proof, main still lacks row-owned evidence that a valid full-config private-group join payload survives Dart helper construction, MethodChannel forwarding, Go bridge parsing, Go node storage, live decrypt, and app replay under the accepted epoch.

What must stay unchanged: BB-008 already-joined refresh semantics, leave/unsubscribe rows, recovery ordering, key rotation, device/relay proof, UI, notification, media, observability, and broad security rows remain separate.

## files and repos to inspect next

Inspect before editing:

- `git status --short`
- `git show --stat --oneline 833fa2c9`
- `rg -n "BB-007|TestBB007|TestGroupJoinTopic_BB007|grp-bb007|bb007" test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/invite_round_trip_test.dart go-mknoon/bridge/bridge_test.go go-mknoon/node/pubsub_delivery_test.go`
- `git diff --check -- test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/invite_round_trip_test.dart go-mknoon/bridge/bridge_test.go go-mknoon/node/pubsub_delivery_test.go`

Row-owned source files to import from commit `833fa2c9`:

- `test/core/bridge/go_bridge_client_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`

Historical source closure docs changed by BB-007, for evidence only and not to copy into main:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-007-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## existing tests covering this area

Main already has nearby but non-closing coverage:

- `test/core/bridge/go_bridge_client_test.dart` maps generic `group:join` to `groupJoinTopic`, but has no BB-007 exact full-config helper test.
- `test/features/groups/integration/invite_round_trip_test.dart` has invite/replay integration coverage and all needed imports/seams, but no BB-007 exact accepted-material test.
- `go-mknoon/bridge/bridge_test.go` has `TestGroupJoinTopic_WithInviteData` and BB-006 legacy rejection, but no BB-007 publish-after-full-config-join test.
- `go-mknoon/node/pubsub_delivery_test.go` has join/delivery helpers and duplicate-join delivery coverage, but no BB-007 live decrypt selector.

COMPLETE_1 overlapping rows are adjacent, not duplicates:

- `GL-002` duplicate join preserves existing state and delivery; BB-007 owns first valid full-config join, not duplicate join.
- `GL-005` successful join stores config/key atomically; BB-007 adds Dart/Go round-trip and exact invite material proof.
- `GL-018`, `GR-004`, and `GR-005` cover restart/recovery/rejoin behavior, not initial accepted invite material.
- `GI-023` covers replay key-epoch grace; BB-007 only proves accepted-epoch replay after join.
- `GP-021`, `GP-022`, and `GO-004` cover event fields and decryption-failure diagnostics; BB-007 only asserts no decryption failure for the valid joined epoch.

## regression/tests to add first

No new tests should be invented. Import the existing source row-owned tests from `833fa2c9` only:

- `BB-007 callGroupJoinWithConfig forwards exact full config payload to groupJoinTopic`
- `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`
- `TestGroupJoinTopic_BB007RoundTripsFullConfigAndAcceptsPublish`
- `TestBB007FullConfigJoinDeliversLiveMessageAtJoinedEpoch`

If any of those selectors already exists in main before execution, compare it structurally against `833fa2c9`. If all four are already present and equivalent, stop as `skipped_already_present`; otherwise import only the missing assertions.

## step-by-step implementation plan

1. Reconfirm dirty state and do not revert unrelated edits.
2. Run duplicate search for `BB-007`, `BB007`, `TestGroupJoinTopic_BB007`, `TestBB007`, and `bb007` across the four target files.
3. If no duplicates exist, import only the four test-file hunks from `833fa2c9`. A non-mutating check already passed:
   - `go-mknoon/bridge/bridge_test.go` hunk applies at offset `+55`.
   - `go-mknoon/node/pubsub_delivery_test.go` hunk applies at offset `+3310`.
   - `test/core/bridge/go_bridge_client_test.dart` applies.
   - `test/features/groups/integration/invite_round_trip_test.dart` applies.
4. Do not copy the source matrix, source breakdown, source test-inventory, or historical source plan into main. Those are evidence, not integration payload.
5. Format only touched files:
   - `dart format test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/invite_round_trip_test.dart`
   - `gofmt -w go-mknoon/bridge/bridge_test.go go-mknoon/node/pubsub_delivery_test.go`
6. Run direct BB-007 tests and adjacent preservation tests listed below.
7. If all evidence passes, update only this integration plan execution log and the main integration breakdown closure ledger for `INTEGRATE-BB-007`. Do not update COMPLETE_1 docs or source worktree docs.

## duplicate-avoidance checks

Before importing, require `rg` to show no current main BB-007 selectors in the four target files. The planning pass found none.

After importing, require exactly one occurrence of each row-owned selector:

- `BB-007 callGroupJoinWithConfig forwards exact full config payload to groupJoinTopic`
- `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`
- `TestGroupJoinTopic_BB007RoundTripsFullConfigAndAcceptsPublish`
- `TestBB007FullConfigJoinDeliversLiveMessageAtJoinedEpoch`

Do not import source closure-doc rows or source test-inventory entries as duplicates of main integration ledger work.

## conflict stop rule

Stop as `blocked_conflict` without code edits if any of these happen:

- A target file has unrelated unresolved edits that make the BB-007 hunk non-mechanical to place.
- A BB-007 selector already exists but differs materially from `833fa2c9`, and the difference cannot be classified as harmless local formatting or context offset.
- Applying the tests would require production changes, new fixtures, new harness code, or merging BB-008/later-row behavior.
- Direct BB-007 tests fail for product behavior rather than a clear test fixture/import mismatch.

Stop as `blocked_external_fixture` only for an environment/tooling fixture outage that prevents required verification while the row-owned code import itself is conflict-free.

## risks and edge cases

- Main is dirty with unrelated sessions; preserve all existing edits and do not normalize files beyond the row-owned hunks.
- `go-mknoon/bridge/bridge_test.go` is already modified in main by earlier BB integrations; use patch context around `TestGroupJoinTopic_WithInviteData`.
- `go-mknoon/node/pubsub_delivery_test.go` has many COMPLETE_1-era tests in main; use the existing helper functions and place BB-007 near duplicate-join delivery context.
- JSON payload comparisons in Dart must remain structural map comparisons, not raw string order checks.
- BB-007 must not prove or change already-joined refresh behavior; that belongs to BB-008.

## exact tests and gates to run

Direct BB-007 proof:

```bash
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'BB-007'
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'BB-007'
cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_BB007' -count=1
cd go-mknoon && go test ./node -run 'TestBB007' -count=1
```

Adjacent preservation proof:

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupJoinWithConfig'
flutter test --no-pub test/features/groups/application/join_group_use_case_test.dart --plain-name 'BB-006 joins with full config payload and no topicName'
cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_(WithInviteData|BB006RejectsLegacyTopicNameOnlyPayload|BB007)' -count=1
```

Affected main/COMPLETE_1 compatibility checks:

```bash
cd go-mknoon && go test ./node -run 'TestJoinGroupTopic_DuplicateJoinPreservesDelivery|TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey|TestGP021|TestGP022' -count=1
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'remove -> rotate -> re-invite round-trip gives the rejoined member the rotated epoch'
```

Required smoke and hygiene:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
git diff --check -- test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/invite_round_trip_test.dart go-mknoon/bridge/bridge_test.go go-mknoon/node/pubsub_delivery_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-007-plan.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md
```

## known-failure interpretation

- A direct BB-007 failure is a row blocker unless isolated to a mechanical import or fixture typo.
- A failure in BB-006 join preservation, `WithInviteData`, or duplicate-join delivery is a conflict with existing main behavior and must stop for review.
- If the broad `groups` gate fails in unrelated already-dirty surfaces, rerun direct BB-007 proof and record the unrelated failing tests exactly before closure.
- Do not claim simulator, relay, real-network, or 3-party proof for BB-007; the source row marks 3-Party E2E recommended and non-closing.

## done criteria

- Exactly four BB-007 row-owned selectors exist in main, one per target test file.
- All direct BB-007 proof commands pass.
- Preservation and affected compatibility checks pass, or unrelated failures are explicitly classified with direct BB-007 proof green.
- Formatting and scoped `git diff --check` pass for touched files and integration docs.
- No production files are changed for BB-007.
- Integration closure ledger records `INTEGRATE-BB-007` with row-owned files/tests, skipped duplicate work, and next session `INTEGRATE-BB-008`.

## scope guard

Non-goals:

- No gap-closure, new implementation rollout, or production fix.
- No source worktree doc copying.
- No COMPLETE_1 doc edits.
- No BB-008 already-joined stale refresh import.
- No BB-009+ leave/recovery/key/device/relay/UI/notification/media/observability/security imports.
- No new multi-device or relay fixture.

## accepted differences / intentionally out of scope

- Source closure docs are used as evidence only; main integration has its own plan and ledger.
- Host-side Dart/Go proof is enough for BB-007 required Unit/Integration/Smoke evidence; 3-Party E2E remains recommended and unclaimed.
- COMPLETE_1 rows that touch join, replay, delivery, or decrypt are adjacent compatibility evidence, not duplicate closure for BB-007.

## dependency impact

`INTEGRATE-BB-008` may rely on BB-007 only for first valid full-config join round-trip/decrypt proof. It must not assume BB-007 refreshed already-joined state or proved recovery/rejoin semantics.

If BB-007 blocks, keep `INTEGRATE-BB-008` pending until the blocker is resolved or explicitly accepted by the integration controller.

## ledger update requirements

After successful execution only, update:

- this plan's execution/final evidence section
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md` row `INTEGRATE-BB-007`

The ledger row must include:

- status `accepted`, or the terminal skip/block status if execution stops
- this plan path
- the four row-owned test files imported
- exact direct/preservation/gate evidence
- docs touched limited to this plan and the integration breakdown
- duplicate-avoidance note that source docs, COMPLETE_1 docs, BB-008, and later rows were not imported
- blocker `none` if accepted
- next session `INTEGRATE-BB-008`

## Execution Progress

- 2026-05-17 03:29 CEST - Imported the four missing BB-007 row-owned test selectors into main only: `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `go-mknoon/bridge/bridge_test.go`, and `go-mknoon/node/pubsub_delivery_test.go`. No production files, source worktree docs, COMPLETE_1 docs, BB-008 selectors, or later rows were imported.
- 2026-05-17 03:29 CEST - Formatting completed: `dart format test/core/bridge/go_bridge_client_test.dart test/features/groups/integration/invite_round_trip_test.dart` PASS; `gofmt -w go-mknoon/bridge/bridge_test.go go-mknoon/node/pubsub_delivery_test.go` PASS.
- 2026-05-17 03:29 CEST - Direct BB-007 proof passed: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'BB-007'` PASS (`+1`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'BB-007'` PASS (`+1`); `cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_BB007' -count=1` PASS (`ok github.com/mknoon/go-mknoon/bridge 0.538s`); `cd go-mknoon && go test ./node -run 'TestBB007' -count=1` PASS (`ok github.com/mknoon/go-mknoon/node 1.211s`).
- 2026-05-17 03:29 CEST - Adjacent preservation passed: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupJoinWithConfig'` PASS (`+3`); `flutter test --no-pub test/features/groups/application/join_group_use_case_test.dart --plain-name 'BB-006 joins with full config payload and no topicName'` PASS (`+1`); `cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_(WithInviteData|BB006RejectsLegacyTopicNameOnlyPayload|BB007)' -count=1` PASS (`ok github.com/mknoon/go-mknoon/bridge 0.357s`).
- 2026-05-17 03:30 CEST - Affected COMPLETE_1/main compatibility passed: `cd go-mknoon && go test ./node -run 'TestJoinGroupTopic_DuplicateJoinPreservesDelivery|TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey|TestGP021|TestGP022' -count=1` PASS (`ok github.com/mknoon/go-mknoon/node 5.642s`); `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'remove -> rotate -> re-invite round-trip gives the rejoined member the rotated epoch'` PASS (`+1`).
- 2026-05-17 03:30 CEST - Smoke and hygiene passed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` PASS (`+165`); scoped `git diff --check -- ... INTEGRATE-BB-007-plan.md ... session-breakdown.md` PASS.

## Final Execution Result

Terminal status: `accepted`.

Accepted row-owned delta: four BB-007 tests proving exact full-config join payload forwarding, pending-invite acceptance/replay at epoch `7`, Go bridge publish after full-config join, and Go node live delivery/decrypt at the joined epoch.

Skipped duplicate/unrelated work: source closure docs were used as evidence only and not copied; COMPLETE_1 docs were not edited; no BB-008 or later row selectors were imported; no production files were changed for BB-007.

Blocker: none.

Next session: `INTEGRATE-BB-008`.

## reviewer pass

Sufficiency: sufficient as-is for standard integration execution.

Missing files/tests/gates: none structurally. The plan names the four source test files, source evidence docs, direct tests, preservation tests, affected COMPLETE_1/main compatibility checks, smoke gate, and scoped diff hygiene.

Stale assumptions: the source row was originally `Partial` during planning, then closed by commit `833fa2c9`; current source breakdown and source matrix now mark BB-007 covered/accepted. Main still lacks BB-007 selectors.

Overengineering: no new tests are invented and no production code is planned.

Minimum needed: import four source test hunks, run the named proof, and update only main integration ledger docs after evidence.

## arbiter pass

Structural blockers: none.

Incremental details intentionally deferred: broader `groups` failures outside BB-007 may be recorded rather than fixed in this row.

Accepted differences intentionally left unchanged: source closure docs and COMPLETE_1 docs remain untouched; 3-Party E2E remains unclaimed.

## Terminal Acceptance Contract

Primary terminal contract: `accepted`.

Alternative terminal contracts if evidence changes during execution: `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.
