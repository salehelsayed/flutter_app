Status: accepted

# INTEGRATE-BB-006 Plan - Legacy Topic-Name Join Helper Main Integration

Run mode: `standard integration`, explicitly not gap-closure.

This plan owns only integration session `INTEGRATE-BB-006` in the main checkout at `/Users/I560101/Project-Sat/mknoon-2/flutter_app`. It must reuse the source worktree BB-006 closure evidence and must not recreate, rewrite, or rerun the original worktree rollout plan.

## Planning Progress

- 2026-05-17 03:04:20 CEST - Evidence Collector started. Files inspected since last update: integration breakdown BB-006 row references, source worktree matrix/breakdown BB-006 references, historical BB-006 plan reference list, main git status. Decision/blocker: target plan file did not exist; main checkout has unrelated dirty files, so this pass must remain read-only except for this plan. Next action: inspect row details, worktree diffs, and main overlap.
- 2026-05-17 03:08:27 CEST - Evidence Collector completed / Planner started. Files inspected since last update: source commit `6ad632f6`, BB-006 historical plan evidence, source/current helper and join-use-case code, source/current BB-006 tests, COMPLETE_1 overlap rows GL-003 through GL-007, GL-018, GR-006/GR-016. Decision/blocker: source commit is row-owned evidence; main still has the legacy Dart join path and lacks BB-006 direct tests, while native Go already rejects missing `groupKey`. Next action: draft minimal import/reconcile contract.
- 2026-05-17 03:09:03 CEST - Planner completed / Reviewer started. Files inspected since last update: main dirty diff for row-owned files, source commit patch, COMPLETE_1 join/recovery rows, closure searches. Decision/blocker: minimal import is source BB-006 code/test delta only; no source closure docs copied. Next action: review for scope drift, duplicate checks, and test contract.
- 2026-05-17 03:09:03 CEST - Reviewer completed / Arbiter started. Files inspected since last update: drafted plan sections. Decision/blocker: no structural blocker; tightened conflict stop rule for currently dirty main row-owned test files and adjusted Go selector to main's existing `MissingFields` name unless execution chooses a safe rename. Next action: final arbiter decision.
- 2026-05-17 03:09:03 CEST - Arbiter completed. Files inspected since last update: final plan. Decision/blocker: execution-ready standard-integration plan; import is allowed only if duplicate and conflict checks stay clean. Next action: stop after writing this plan file.

## Execution Progress

- 2026-05-17 03:13:20 CEST - Executor imported only the BB-006 row-owned production/test delta into main: `lib/core/bridge/bridge_group_helpers.dart`, `lib/features/groups/application/join_group_use_case.dart`, `test/core/bridge/bridge_group_helpers_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, and `go-mknoon/bridge/bridge_test.go`. Source docs were not copied; no COMPLETE_1 docs were edited.
- 2026-05-17 03:13:27 CEST - Required direct proof passed: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart test/core/bridge/go_bridge_client_test.dart` (`+137`), `flutter test --no-pub test/features/groups/application/join_group_use_case_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart` (`+55`), and `cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_(BB006RejectsLegacyTopicNameOnlyPayload|MissingFields|WithInviteData)' -count=1` (`ok github.com/mknoon/go-mknoon/bridge 0.510s`).
- 2026-05-17 03:13:41 CEST - Required host integration preservation passed: `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart` (`+20`).
- 2026-05-17 03:14:58 CEST - Closure searches and smoke passed: `rg -n "callGroupJoin\\(" lib test --glob '*.dart'` showed only the helper stub plus row-owned tests; scoped `topicName` search found only the existing create-response doc comment; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed (`+164`); Dart format, gofmt, and scoped `git diff --check` passed.

## Final Execution Result

Final execution verdict: accepted.

BB-006 is accepted in main as a standard integration import. The legacy topic-name-only `callGroupJoin` path now fails locally with `LEGACY_JOIN_UNSUPPORTED` before `bridge.send`; `joinGroup` requires full config/key/epoch material and calls `callGroupJoinWithConfig` before local persistence; row-owned helper/application/native tests and preservation suites passed. No source worktree closure docs, COMPLETE_1 docs, or adjacent BB/SV rows were imported. Next allowed session after ledger closure is `INTEGRATE-BB-007`.

## real scope

Import or reconcile only the missing meaningful BB-006 work from the source worktree into main:

- Retire the legacy Dart `callGroupJoin` topic-name-only helper so it deterministically fails before `bridge.send`.
- Move the remaining production `joinGroup` seam from `callGroupJoin(... topicName ...)` to `callGroupJoinWithConfig` with full `groupConfig`, `groupKey`, and positive `keyEpoch` before any group/member/key persistence.
- Add BB-006 direct tests proving fake bridge success and invalid full-config material cannot create false local joined state.
- Add the native bridge backstop test for legacy `{"groupId", "topicName"}` payload rejection if it is still missing in main.

Do not copy the source worktree matrix, source worktree session breakdown, source `test-inventory.md`, or historical BB-006 plan into main. Do not import BB-007, BB-008, SV-009, or later source-worktree behavior.

## closure bar

`INTEGRATE-BB-006` is closed when main has the BB-006 private-group join contract, focused proof, and integration ledger evidence:

- No production private-group onboarding or recovery caller can successfully use a topic-name-only join.
- `callGroupJoin` is removed, private, or kept only as a deprecated `LEGACY_JOIN_UNSUPPORTED` local failure before bridge send.
- `joinGroup` requires full config/key/epoch material and persists group/member/key state only after `callGroupJoinWithConfig` succeeds.
- Go bridge has a BB-006-named test proving legacy topic-name-only payloads reject as `INVALID_INPUT`.
- Direct Flutter and Go tests plus the host integration preservation tests pass or produce a documented non-BB-006 pre-existing failure.

## source of truth

- Active integration contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`, row `INTEGRATE-BB-006`.
- Source worktree closure truth: commit `6ad632f6fa2e87b94ed06fcae3345db727166a6c` (`BB-006: retire legacy group join helper`), source matrix row `BB-006`, source breakdown session `BB-006`, and historical plan `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-006-plan.md`.
- Main code and tests win over stale prose during integration.
- COMPLETE_1 is compatibility context only. It is not the source row being integrated.

## session classification

`implementation-ready`.

Reason: main is missing meaningful BB-006 Dart behavior and BB-006 direct proof. The work is a standard integration import/reconcile session, not a new gap-closure rollout.

## exact problem statement

Main still has `lib/core/bridge/bridge_group_helpers.dart::callGroupJoin` sending `group:join` with only `groupId` and `topicName`. Main also has `lib/features/groups/application/join_group_use_case.dart::joinGroup` calling that helper before saving group/member/key state.

That leaves a false-join risk in Dart tests or permissive/fake bridge paths: a fake `{"ok": true}` topic-name-only join can mark a member as locally joined without native full private-group config/key material. Native Go in main already rejects missing `groupKey`, but the Dart seam and direct tests still allow the unsafe shape.

What must stay unchanged: valid invite and recovery paths that already use `callGroupJoinWithConfig`, create-group topic storage, `group:join` command naming, and COMPLETE_1 join/recovery semantics.

## source BB-006 changed files

Git evidence from source worktree commit `6ad632f6`:

- Historical plan/doc evidence:
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-006-plan.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Row-owned production/test files:
  - `lib/core/bridge/bridge_group_helpers.dart`
  - `lib/features/groups/application/join_group_use_case.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
  - `test/features/groups/application/join_group_use_case_test.dart`
  - `go-mknoon/bridge/bridge_test.go`

Only the row-owned production/test files are candidates for import. The source docs are evidence only and must not be copied.

## files and repos to inspect next

Before editing, execution must inspect the current main working tree for these paths:

- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/join_group_use_case.dart`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/join_group_use_case_test.dart`
- `go-mknoon/bridge/bridge_test.go`
- `test/core/bridge/go_bridge_client_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`

## existing tests covering this area

Main currently has supporting but insufficient coverage:

- `test/core/bridge/bridge_group_helpers_test.dart` still expects `callGroupJoin` to send `topicName`, complete on fake success, and timeout on a slow bridge. These are stale for BB-006 and must become legacy-failure expectations.
- `test/features/groups/application/join_group_use_case_test.dart` currently proves success, persistence, bridge command use, and BB-002 `NOT_INITIALIZED` no-persistence, but it does not require `groupConfig` or prove absence of `topicName`.
- `go-mknoon/bridge/bridge.go::GroupJoinTopic` already rejects missing `groupKey`, so a legacy topic-name-only payload should already fail, but main lacks the BB-006-named backstop test.
- `rejoin_group_topics_use_case_test.dart`, `handle_incoming_group_invite_use_case_test.dart`, `invite_round_trip_test.dart`, and `group_startup_rejoin_smoke_test.dart` are preservation tests for config-join paths.

## overlapping COMPLETE_1/main compatibility

No COMPLETE_1 row directly owns "legacy topic-name Dart join helper." Relevant overlap to protect:

- GL-003/GL-004: native join failure cleanup and retry behavior. Do not alter Go node join lifecycle in this session.
- GL-005: successful native join stores config and key atomically. BB-006 must preserve full-config join shape.
- GL-006/GL-007: native join with nil key/config fails explicitly. BB-006 should not weaken native nil-material behavior.
- GL-018: app startup rejoin emits one `group:join` per persisted group with current config/key/epoch and receives after rejoin. Preserve `rejoinGroupTopics`.
- GR-006/GR-016: recovery acknowledgment and watchdog rejoin rely on full config/key rejoin behavior. Preserve those tests.
- IJ-009 inventory context already treats `join_group_use_case_test.dart` as a preservation suite; update it narrowly for BB-006.

## regression/tests to add first

Add or reconcile these tests before or with the code delta:

- `test/core/bridge/bridge_group_helpers_test.dart`
  - Change the `callGroupJoin` group so fake success throws `LEGACY_JOIN_UNSUPPORTED` and does not call `bridge.send`.
  - Change the slow bridge test so legacy join fails locally instead of timing out.
  - Change the ok:false bridge error test for legacy join to expect `LEGACY_JOIN_UNSUPPORTED` and no send.
  - Adjust the BB-002 `group:join` helper test so plain legacy join failure is `LEGACY_JOIN_UNSUPPORTED`, while `callGroupJoinWithConfig` still preserves `NOT_INITIALIZED`.
- `test/features/groups/application/join_group_use_case_test.dart`
  - Add `fullGroupConfig`, update existing `joinGroup` calls to pass it, and use positive `keyEpoch`.
  - Replace "calls bridge join command" with `BB-006 joins with full config payload and no topicName`.
  - Add `BB-006 invalid full-config material fails before bridge send or persistence`.
- `go-mknoon/bridge/bridge_test.go`
  - Add `TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload`.
  - Keep main's existing `TestGroupJoinTopic_MissingFields` name unless execution deliberately renames it and updates selectors safely. The rename in source commit is not required for BB-006 behavior.

Do not import source tests added by later rows, including BB-013 timeout tests or SV-009 key-material validation.

## step-by-step implementation plan

1. Snapshot current main state with `git status --short` and `git diff --stat -- <row-owned paths>`. The main checkout is currently dirty; treat existing edits as user/other-agent work.
2. Run duplicate checks:
   - `rg -n "LEGACY_JOIN_UNSUPPORTED|BB-006|TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload" lib test go-mknoon/bridge`
   - `rg -n "callGroupJoin\\(" lib test --glob '*.dart'`
3. If main already has the complete BB-006 contract and tests, do not edit production/tests. Mark the future execution outcome `skipped_already_present` after running focused proof and updating the integration ledger.
4. Patch `lib/core/bridge/bridge_group_helpers.dart` so `callGroupJoin` is a deprecated local failure stub. Preserve flow events, but emit a failed join response with `LEGACY_JOIN_UNSUPPORTED` and throw `BridgeCommandException` before building/sending a `topicName` payload.
5. Patch `lib/features/groups/application/join_group_use_case.dart` to require `groupConfig`, validate the minimal source BB-006 material (`groupKey` non-empty, `keyEpoch > 0`, group metadata match, creation metadata present, optional valid state hash, members non-empty, self member present, role/public key match), call `callGroupJoinWithConfig`, then persist group/member/key. Use main's current `group_config_payload.dart` APIs; do not import later source-only validation from SV-009.
6. Patch the three direct test files listed above using source commit `6ad632f6` as a guide, but keep the smallest current-main-compatible hunks.
7. Run format and focused tests.
8. Run closure searches to prove only allowed `callGroupJoin` references remain.
9. Update this plan file with execution evidence and update only the integration breakdown ledger for `INTEGRATE-BB-006`. Do not update source worktree docs or COMPLETE_1 docs during execution unless the user separately asks.

## duplicate-avoidance checks

Treat any of these as duplicate evidence:

- `callGroupJoin` already throws `BridgeCommandException('group:join', 'LEGACY_JOIN_UNSUPPORTED', ...)` before `bridge.send`.
- `joinGroup` already takes `groupConfig` and calls `callGroupJoinWithConfig` before persistence.
- `test/core/bridge/bridge_group_helpers_test.dart` already has `BB-006 rejects topic-name-only helper before bridge send`.
- `test/features/groups/application/join_group_use_case_test.dart` already has `BB-006 joins with full config payload and no topicName`.
- `go-mknoon/bridge/bridge_test.go` already has `TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload`.

If all are present and focused tests pass, classify execution as `skipped_already_present`, not `accepted`.

## conflict stop rule

Stop and classify execution as `blocked_conflict` if:

- Any row-owned file has same-hunk edits that cannot be cleanly reconciled with the BB-006 source contract.
- A production caller outside `join_group_use_case.dart` uses `callGroupJoin(...)` and requires product/API design beyond the source BB-006 row.
- Updating `joinGroup` to require `groupConfig` would break current main call sites that are not test-only or cannot provide full config without broader onboarding design.
- The import would require copying BB-007, BB-008, SV-009, or later-row source behavior to make BB-006 compile.

No external device, relay, or simulator fixture is required. Use `blocked_external_fixture` only if the repo's existing host test harness unexpectedly cannot run and there is no host-side substitute for direct BB-006 proof.

## risks and edge cases

- Current main already has dirty row-owned tests from prior integration sessions. Preserve those changes and layer BB-006 narrowly.
- Main's `go-mknoon/bridge/bridge_test.go` currently names the missing-material test `TestGroupJoinTopic_MissingFields`; source renamed it to `MissingParams`. Avoid rename churn unless needed.
- Existing `topicName` fields remain valid group model/create metadata. BB-006 forbids using `topicName` as sufficient join material, not storing or displaying topic names.
- `joinGroup` may be a rarely used production seam, but it lives under `lib/` and must not retain a false-success path.
- `groupConfig` validation must remain minimal to BB-006. Do not import later key-material policy checks from SV-009.

## exact tests and gates to run

Required format/checks:

```bash
dart format --set-exit-if-changed lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/join_group_use_case.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/join_group_use_case_test.dart
gofmt -w go-mknoon/bridge/bridge_test.go
```

Required direct Flutter proof:

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart test/core/bridge/go_bridge_client_test.dart
flutter test --no-pub test/features/groups/application/join_group_use_case_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart
```

Required Go proof:

```bash
cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_(BB006RejectsLegacyTopicNameOnlyPayload|MissingFields|WithInviteData)' -count=1
```

If execution renames `MissingFields` to `MissingParams`, update the selector to `MissingParams` and record the rename as compatibility-neutral.

Required host integration preservation:

```bash
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Recommended smoke/backstop:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
git diff --check -- lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/join_group_use_case.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/join_group_use_case_test.dart go-mknoon/bridge/bridge_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-006-plan.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md
```

Closure searches:

```bash
rg -n "callGroupJoin\\(" lib test --glob '*.dart'
rg -n '"topicName"' lib/core/bridge lib/features/groups/application test/core/bridge test/features/groups/application --glob '*.dart'
```

Allowed closure-search results: the helper declaration/stub, BB-006 legacy-failure tests, normal group model/create/topic metadata, and no production onboarding caller using `callGroupJoin`.

## known-failure interpretation

Treat failures in required direct Flutter tests, required Go selector, closure searches, or scoped `git diff --check` as BB-006 blockers unless conclusively caused by unrelated pre-existing dirty work outside the row-owned files.

If the recommended `groups` smoke fails outside join/onboarding/recovery paths, record exact failing tests and keep the required direct/host integration proof as the BB-006 acceptance basis. Do not claim `accepted` if a failure is in `bridge_group_helpers`, `join_group_use_case`, invite config join, recovery rejoin, or Go `GroupJoinTopic`.

## done criteria

- Main contains the BB-006 Dart contract and BB-006 direct tests.
- Main native bridge backstop has `TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload` or an equivalent named test.
- Required direct Flutter proof passes.
- Required Go proof passes.
- Required host integration preservation passes.
- Closure searches prove no production topic-only join path remains.
- The integration breakdown ledger row for `INTEGRATE-BB-006` is updated with status, plan path, changed files, tests passed, docs touched, duplicate work skipped, blockers, and next session `INTEGRATE-BB-007`.
- This plan records final execution outcome and evidence if execution happens later.

## scope guard

Do not:

- Implement BB-007 full-config publish/decrypt round-trip proof.
- Implement BB-008 already-joined refresh semantics.
- Change Go node join lifecycle, validator cleanup, nil key/config policy, discovery, recovery ack, leave, media, push, UI, relay, or device harness behavior.
- Copy source worktree closure docs into main.
- Re-run the original source worktree plan.
- Touch unrelated dirty files.

## accepted differences / intentionally out of scope

- Main already has native Go behavior that rejects missing `groupKey`; BB-006 still needs a named bridge test and Dart false-join prevention.
- Main may keep the existing `TestGroupJoinTopic_MissingFields` test name instead of source's `MissingParams` rename.
- Device, relay, simulator, 3-party E2E, and BB-007 decryptability are not required for this deterministic host-side join payload/persistence contract.

## dependency impact

BB-007 should build on the preserved `callGroupJoinWithConfig` path and must not reintroduce topic-name-only onboarding. BB-008, GL-018, GR-006, and GR-016 rely on full-config rejoin semantics remaining intact. If this integration blocks on a real conflict, keep later `INTEGRATE-BB-007+` sessions from assuming BB-006 is closed in main.

## reviewer pass

Review result: sufficient as-is.

- Missing files/tests/gates: none structural. The plan names the exact source commit, source changed files, current-main missing behavior, direct tests, host preservation tests, and ledger update.
- Stale assumptions: main has a dirty worktree, so the plan requires reinspection and same-hunk conflict stopping before edits.
- Overengineering: avoided by not importing source docs, later BB/SV rows, or device/relay proof.
- Minimum sufficient import: two Dart production files plus three test files, with Go production untouched unless a direct selector unexpectedly proves otherwise.

## arbiter pass

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact `joinGroup` call-site migration details if a non-test production caller appears during duplicate checks.
- Whether to rename `TestGroupJoinTopic_MissingFields` to `MissingParams`; not required for BB-006.

Accepted differences intentionally left unchanged:

- Main COMPLETE_1 docs stay untouched.
- Source worktree BB-006 closure docs are evidence, not import targets.

Terminal acceptance contract: accepted
