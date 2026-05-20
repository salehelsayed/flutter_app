# INTEGRATE-BB-005 Standard Integration Contract Plan

Status: accepted

Run mode: standard integration, not gap-closure.

## Planning Progress

- 2026-05-17T00:58:13Z - Arbiter completed. Files inspected since last update: final draft plan. Decision/blocker: no structural blockers remain; the contract is execution-ready as standard integration. Next action: hand off to execution for only `INTEGRATE-BB-005`.
- 2026-05-17T00:58:13Z - Reviewer completed. Files inspected since last update: draft plan and requested constraints. Decision/blocker: sufficient with safeguards; no production edits or source-doc rewrites authorized. Next action: arbiter classification.
- 2026-05-17T00:58:13Z - Planner completed. Files inspected since last update: source BB-005 diffs, main absence checks, adjacent GL-005/COMPLETE_1 overlap checks, and current create-path code. Decision/blocker: tests-only row import with conflict stop rule. Next action: reviewer pass.
- 2026-05-17T00:56:35Z - Evidence Collector completed. Files inspected since last update: integration breakdown, source matrix/breakdown, historical BB-005 plan, COMPLETE_1 breakdown/matrix, main/source BB-005 test diffs, and main/source create-path code. Decision/blocker: BB-005 is missing as row-owned proof in main but the underlying guard is present. Next action: planner draft.
- 2026-05-17T00:53:14Z - Evidence Collector started. Files inspected since last update: none yet. Decision/blocker: intake artifact created for the requested single-row standard integration plan. Next action: inspect BB-005 entries, historical evidence, git diffs, and main overlap.

## Execution Progress

- 2026-05-17T01:00:29Z - Executor imported only the three BB-005 row-owned test hunks into main: `test/core/bridge/bridge_group_helpers_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, and `go-mknoon/bridge/bridge_test.go`. Production files were not edited for BB-005.
- 2026-05-17T01:00:32Z - Focused selectors passed: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart --plain-name "BB-005"` (`+2`) and `cd go-mknoon && go test ./bridge -run 'TestBB005' -count=1` (`ok github.com/mknoon/go-mknoon/bridge 0.563s`).
- 2026-05-17T01:00:46Z - Affected adjacent checks passed: full Flutter helper/create test files (`+83`), Go adjacent create selector `TestGroupCreate_GL005RejectsUnsupportedPublicOrOpenGroupTypes|TestBB005|TestGroupCreate_BB003|TestGroupCreate_BB004` (`ok github.com/mknoon/go-mknoon/bridge 0.367s`), Dart format, gofmt, and scoped `git diff --check`.

## Final verdict

Accepted for `INTEGRATE-BB-005` only. Main now has the row-owned BB-005 helper, application, and native Go proofs; focused and affected tests passed; no production files changed for BB-005; no COMPLETE_1 conflict was found; no source closure docs or adjacent source-worktree rows were imported. Next allowed session after ledger closure is `INTEGRATE-BB-006`.

## real scope

Import or reconcile only the meaningful BB-005 row-owned proof from the source worktree into the main checkout. The historical BB-005 worktree row is accepted and test-only; this standard-integration pass must not recreate its rollout, expand its behavior, or touch production code unless the imported BB-005 tests expose a direct compile/test incompatibility that must be stopped and reported rather than fixed here.

Row-owned import candidates are limited to these test hunks:

- `test/core/bridge/bridge_group_helpers_test.dart`: add only `BB-005 callGroupCreate preserves unsupported group type rejection`.
- `test/features/groups/application/create_group_use_case_test.dart`: add only `BB-005 unsupported group type rejection leaves no local group member key or event state`.
- `go-mknoon/bridge/bridge_test.go`: add only `TestBB005GroupCreateRejectsUnsupportedTypesWithoutPartialState`.

No source worktree files, source worktree docs, production code, COMPLETE_1 docs, or unrelated rows are in scope for this plan.

## closure bar

BB-005 integration is good enough when main has row-labeled BB-005 helper, application, and native Go proofs matching the historical contract; focused BB-005 Flutter and Go selectors pass in main; duplicate/adjoining coverage remains separate; and the integration breakdown can truthfully mark `INTEGRATE-BB-005` as `accepted` or `skipped_already_present` with exact evidence.

## source of truth

Authoritative inputs for this planning pass:

- Integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`, row `INTEGRATE-BB-005` pending.
- Source worktree matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`, row `BB-005` covered.
- Source worktree breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`, session `BB-005` accepted.
- Historical plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-005-plan.md`, `Status: accepted`.
- Main checkout code/tests win over stale prose if there is a conflict. Existing dirty main changes are presumed to belong to prior integration sessions and must be preserved.

## session classification

`implementation-ready`

This is implementation-ready only as a standard integration import contract. It is not gap-closure and not a new BB-005 implementation rollout.

## exact problem statement

Main currently has the unsupported group type guard in `go-mknoon/bridge/bridge.go`, and nearby non-row-owned tests exist, but main does not contain row-labeled BB-005 proof in the three historical BB-005 test files. The missing integration risk is traceability: future closure cannot prove that unsupported `group:create` types reject as `INVALID_INPUT` without partial native response artifacts or local Flutter side effects under the BB-005 row contract.

User-visible behavior must stay unchanged: unsupported create types fail before any local group, member, key, topic, invite, keygen, signed event, or payload-sign side effect; supported `chat`, `announcement`, and `qa` create types remain accepted by native bridge tests.

## files and repos to inspect next

Before any execution edits, inspect these exact main files and preserve existing dirty edits:

- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/bridge/bridge.go` only for verification, not editing
- `lib/features/groups/application/create_group_use_case.dart` only for verification, not editing
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md` only when execution later updates the ledger

Do not inspect or edit unrelated source, UI, media, notification, relay, recovery, or membership rows unless a direct BB-005 compile error points to a missing local test helper.

## existing tests covering this area

Main already has adjacent coverage, but not a BB-005 row-owned contract:

- `go-mknoon/bridge/bridge_test.go::TestGroupCreate_GL005RejectsUnsupportedPublicOrOpenGroupTypes` rejects `public`, `private`, `broadcast`, `discoverable`, and `openJoin` as `INVALID_INPUT`, but it does not assert no partial response artifacts or supported-type preservation under `BB-005`.
- `test/features/groups/application/create_group_use_case_test.dart::GL-005 create payloads use only supported private group variants and no public route flags` proves typed app create payloads avoid public/open route fields, but it does not prove bridge rejection leaves no local state.
- Main `go-mknoon/bridge/bridge.go::GroupCreate` already rejects unsupported `groupType` through `isSupportedBridgeGroupType`; no BB-005 production delta is expected.

## regression/tests to add first

Add or import tests first, without production edits:

- Flutter helper: prove raw `callGroupCreate(... type: 'public')` sends `groupType: public`, preserves `INVALID_INPUT`, omits `groupId`, `topicName`, `groupKey`, `keyEpoch`, and `groupConfig`, and calls only `group:create`.
- Flutter application: prove a bridge `INVALID_INPUT` create failure throws and leaves no local group, member, key, signed event, `group.keygen`, or `payload.sign` side effect.
- Go bridge: prove native `GroupCreate` rejects unsupported types without partial artifacts, while `chat`, `announcement`, and `qa` still produce a coherent config.

If all three exact BB-005 tests are already present before editing, classify the session as `skipped_already_present` after focused selectors pass.

## step-by-step implementation plan

1. Recheck `git status --short` in main and note pre-existing dirty files. Do not revert them.
2. Search main for `BB-005` and `TestBB005` in the three row-owned test files.
3. If exact BB-005 selectors are already present in all three files, run the focused selectors and skip code edits.
4. If missing, import only the three row-owned BB-005 test hunks from the source worktree:
   - In `bridge_group_helpers_test.dart`, place the helper test near existing `callGroupCreate` failure tests. Do not import adjacent BB-013, BB-015, BB-016, OB, or other source worktree hunks.
   - In `create_group_use_case_test.dart`, place the application no-side-effect test near create failure/no-state tests. Adapt only formatting or local helper names required by current main; preserve BB-004 and GL-005 tests already in main.
   - In `bridge_test.go`, place `TestBB005GroupCreateRejectsUnsupportedTypesWithoutPartialState` immediately after `TestGroupCreate_GL005RejectsUnsupportedPublicOrOpenGroupTypes`.
5. Run formatting on only edited files.
6. Run focused BB-005 Flutter and Go selectors.
7. If focused selectors fail because production behavior differs from the historical contract, stop with `blocked_conflict`; do not implement production changes under this integration plan.
8. If focused selectors pass, run affected nearby suites listed below.
9. Update only the integration breakdown ledger in a later execution/closure pass, not during this planning pass, with accepted/skipped/blocker status and exact changed files/tests.

## risks and edge cases

- Main is dirty from prior integration rows; do not overwrite local BB-001 through BB-004 edits while importing adjacent test hunks.
- Source worktree test files contain later rows (`BB-013`, `BB-015`, `BB-016`, `KE-001`, and others). Copying broad hunks would duplicate or pre-import unrelated sessions.
- Main and source have different line ordering in `create_group_use_case_test.dart`; import by selector body, not by raw file replacement.
- Existing GL-005 coverage can look similar to BB-005 but is not sufficient row-owned evidence.
- If the Go test compiles but supported `announcement` or `qa` creates fail in main, stop as `blocked_conflict` because that would imply a real behavior mismatch outside a tests-only import.

## exact tests and gates to run

Focused BB-005 selectors:

```sh
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart --plain-name "BB-005"
cd go-mknoon && go test ./bridge -run 'TestBB005' -count=1
```

Formatting and hygiene:

```sh
dart format --set-exit-if-changed test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart
gofmt -w go-mknoon/bridge/bridge_test.go
git diff --check -- test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart go-mknoon/bridge/bridge_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-005-plan.md
```

Affected main/COMPLETE_1-adjacent checks:

```sh
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart
cd go-mknoon && go test ./bridge -run 'TestGroupCreate_GL005RejectsUnsupportedPublicOrOpenGroupTypes|TestBB005|TestGroupCreate_BB003|TestGroupCreate_BB004' -count=1
```

Optional only if the executor/closure policy requires broader evidence and the focused tests are green:

```sh
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

## known-failure interpretation

Historical BB-005 evidence recorded broader red gates outside BB-005: `groups` ended `+191 -34` in unrelated group smoke/membership/recovery contexts and `completeness-check` reported `738/739` with unmatched `test/shared/fakes/seeded_group_reproduction_log_test.dart`; BB-005 focused selectors reran green afterward. If those or equivalent unrelated failures still occur in main, record exact failure context, rerun BB-005 focused selectors green, and do not classify unrelated red gates as BB-005 blockers.

Any failure in a BB-005 focused selector, the GL-005 create unsupported-type backstop, or a compile error caused by the imported BB-005 hunk is a BB-005 blocker until resolved or classified.

## done criteria

- The plan remains a standard-integration contract and does not reopen original worktree implementation.
- Main contains exactly the missing meaningful BB-005 row-owned test deltas, or all three are proven already present.
- No production files are edited for BB-005.
- Focused BB-005 Flutter and Go selectors pass.
- Affected helper/create and Go bridge checks either pass or have unrelated failures documented under known-failure policy.
- Later closure ledger entry for `INTEGRATE-BB-005` records `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture` and names exact files/tests.

## scope guard

Do not import source worktree docs as closure docs. Do not edit the source worktree. Do not update `Private_group_chat_reliability_test_matrix_full_with_rules.md`, `test-inventory.md`, COMPLETE_1 artifacts, production create paths, bridge command maps, malformed-response handling, metadata/description handling, timeout handling, creator-identity validation, join/recovery logic, relay/device harnesses, or UI.

Overengineering for this session includes adding new helpers, refactoring bridge create code, changing `GroupType`, broad-copying source worktree test files, or trying to make named gates green outside BB-005.

## accepted differences / intentionally out of scope

- COMPLETE_1 `GL-005` is a join-state atomicity row, not the BB-005 create unsupported-type row. It is non-overlapping.
- Main has non-row-owned GL-005 create tests in the same BB-005 files; they stay as supporting context and must not be renamed or folded into BB-005.
- Source worktree includes later BB-013, BB-015, BB-016, KE, and other tests in the same files; those remain out of scope for this row.
- Historical source docs remain the source-of-truth evidence, but this plan does not copy their closure text into main.

## dependency impact

Successful BB-005 integration lets the integration pipeline advance to `INTEGRATE-BB-006` with row traceability intact. If BB-005 is `skipped_already_present`, later rows can still proceed after ledger evidence records the exact already-present selectors. If BB-005 is `blocked_conflict`, do not advance past it until the conflict is resolved or a supervising integration controller explicitly reorders work.

## duplicate-avoidance checks

Run these before editing:

```sh
rg -n "BB-005|TestBB005" test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart go-mknoon/bridge/bridge_test.go
rg -n "BB-013|BB-014|BB-015|BB-016|KE-001|ML-010" test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart go-mknoon/bridge/bridge_test.go
```

If `BB-005` exists in only some files, import only the missing selectors. If adjacent future-row labels appear, verify they pre-existed before this session or stop before touching them.

## conflict stop rule

Stop and record `blocked_conflict` if:

- A BB-005 hunk cannot be imported without overwriting prior dirty main edits.
- The imported BB-005 tests require production behavior absent from main.
- Main already has a different BB-005 test with conflicting expectations.
- Formatting or focused selector failures point to unrelated source-worktree rows that would need to be imported first.

Stop and record `blocked_external_fixture` only if a required external fixture blocks verification. BB-005 should not normally use that status because its required proof is host Flutter plus Go bridge.

## ledger update requirements

After execution, update only the integration breakdown row and closure ledger for `INTEGRATE-BB-005`:

- Set integration ledger status to one terminal result: `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.
- Record this plan path.
- Record exact changed files. Expected accepted import changes are only the three test files plus this plan and later integration ledger doc.
- Record exact tests run and known-failure classification.
- Record duplicate-avoidance outcome: no source closure docs copied, no COMPLETE_1 overlap, no adjacent row imported.
- Set next session to `INTEGRATE-BB-006` only for `accepted` or `skipped_already_present`.

## reviewer pass

Sufficiency review result: sufficient with the safeguards above. The plan names the exact row-owned files, distinguishes historical evidence from main import work, avoids gap-closure behavior, defines focused selectors, and gives a conflict stop rule before any production edit.

Missing or deferred: no live device or simulator proof is required because source row `BB-005` has 3-Party E2E `N/A`. Broader `groups` and `completeness-check` gates are optional for this standard integration import unless the controller requires them after focused proof passes.

## arbiter decision

Structural blockers remaining: none.

Incremental details intentionally deferred: exact insertion line numbers can be chosen by the executor after re-reading the current dirty main files.

Accepted differences intentionally left unchanged: existing GL-005 coverage remains adjacent evidence; BB-005 must still have row-named proof if missing.

## terminal acceptance contract

The executor must end with exactly one terminal classification:

- `accepted`: missing BB-005 row-owned tests were imported, focused selectors passed, no production files changed, and ledger evidence is ready.
- `skipped_already_present`: all three BB-005 row-owned tests were already present in main and focused selectors passed.
- `blocked_conflict`: import or focused verification requires overwriting unrelated dirty edits, changing production behavior, or importing adjacent rows.
- `blocked_external_fixture`: a required external fixture blocks verification; expected to be unused for BB-005.
