# PGC-KEYS-1 Execution-Safe Plan: Retain Group Keys For Offline Replay Backlog

Status: execution-ready

Source row: `PGC-013`

## Planning Progress

- `2026-05-23 23:19:10 CEST` - Role: Arbiter completed. Files inspected since last update: reviewer pass, scope guard, closure bar, test/gate contract, final output requirements. Decision/blocker: no structural blocker; incremental adjustments are already applied; plan is execution-ready. Next action: executor may implement row `PGC-013` only.
- `2026-05-23 23:18:39 CEST` - Role: Reviewer completed / Arbiter started. Files inspected since last update: reviewer-adjusted plan, mandatory-section list, source row/scope constraints. Decision/blocker: sufficient with incremental adjustments; no structural blocker found. Next action: classify reviewer findings and finalize execution-ready status if arbiter finds no structural blocker.
- `2026-05-23 23:17:45 CEST` - Role: Planner completed / Reviewer started. Files inspected since last update: draft plan sections and mandatory-section search for the requested plan file. Decision/blocker: draft has all mandatory sections and stays Dart-only; reviewer is checking ambiguity around the retention-policy file and pruning guard. Next action: patch incremental sufficiency adjustments, then record reviewer findings.
- `2026-05-23 23:15:34 CEST` - Role: Evidence Collector completed / Planner started. Files inspected since last update: `lib/features/groups/domain/repositories/group_repository_impl.dart`, `test/shared/fakes/in_memory_group_repository.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/domain/repositories/group_pending_key_repair_repository.dart`, `test/features/groups/domain/repositories/group_repository_impl_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `scripts/run_test_gates.sh`. Decision/blocker: row `PGC-013` remains real in Dart; no evidence requires Go key-rotation changes. Next action: draft the smallest Dart-only retention/stale-replay implementation plan with direct regressions and gate contract.
- `2026-05-23 23:11:46 CEST` - Role: Evidence Collector started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`, `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`, scoped `git status --short`. Decision/blocker: source row and intended plan path confirmed; worktree is dirty, so this plan must not overwrite unrelated edits or touch product/test code. Next action: inspect only direct Dart key-retention, stale-replay, and focused-test seams for row `PGC-013`.

## Execution Progress

- `2026-05-24 00:14:33 CEST` - Phase: contract extracted / local execution started. Files inspected or scoped: `git status --short`, current diffs for row-owned files, `GroupRepositoryImpl._pruneObsoleteKeys`, `InMemoryGroupRepository._pruneObsoleteKeys`, `_resolveStaleReplayEpoch`, repository key tests, drain PGC-013/GI-023/future-key tests. Decision/blocker: fresh sub-agent spawning is not available in this environment, so execution is proceeding locally against the existing execution-safe plan while preserving unrelated dirty-worktree edits. Next action: add PGC-013 RED assertions, shared retention policy, and narrow caller wiring.

## real scope

Session `PGC-KEYS-1` owns row `PGC-013` only: Dart-side committed group key retention and Dart stale offline replay classification.

Implementation scope:

- Add a single shared Dart retention policy for committed group keys used by both production repository pruning and stale replay classification.
- Replace latest-plus-previous retention with a bounded multi-generation window. Use `8` committed generations as the initial execution constant: latest plus seven historical generations. This mirrors the existing seven-day backlog concept without introducing a time-based or unbounded key scan.
- Update `GroupRepositoryImpl._pruneObsoleteKeys` so it prunes only generations older than the shared minimum retained generation and still deletes matching secure-store material and shared push mirrors for pruned generations.
- Update `test/shared/fakes/in_memory_group_repository.dart` to match the production retention policy so app-layer replay tests do not prove fake-only behavior.
- Update `_resolveStaleReplayEpoch` in `drain_group_offline_inbox_use_case.dart` so it treats only epochs older than the same retained-generation threshold as stale. Missing keys inside the retention window must continue to create pending-key repair or undecryptable placeholder evidence instead of being silently skipped as stale.
- Add/adjust focused Dart tests proving repository retention, stale replay skip threshold, and retained historical replay across multiple rotations.

Non-scope:

- No Go key rotation, Go validator, Go bridge, relay, protocol/AAD, or active-key grace-period changes.
- No DB schema or migration unless current code evidence proves the existing `group_keys` table cannot support a bounded generation window. Current evidence says it can.
- No change to group membership, recipient entitlement, removed-member replay rules, repair request transport, send status, or inbox cursor behavior.
- No broad cleanup of dirty worktree changes.

## closure bar

This session is good enough when Dart keeps enough committed group key material to decrypt replay messages across several missed rotations while still bounding stored key growth, and when Dart stale-replay handling uses the same retention threshold as repository pruning.

Concrete closure requires:

- A shared retention helper/constant with exactly one minimum-generation formula.
- `GroupRepositoryImpl`, `InMemoryGroupRepository`, and `_resolveStaleReplayEpoch` all using that shared formula.
- Direct regressions proving generation `latest - 7` is retained/decryptable and generation `latest - 8` is pruned/stale-skipped.
- Existing future-key repair behavior still queues missing future epochs instead of classifying them as stale.
- Existing historical key-update behavior still saves older non-conflicting keys without promoting them.
- No Go file changes unless Dart evidence is disproven and the plan is explicitly reopened.

## source of truth

Authoritative for this session:

- Source matrix row `PGC-013` in `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`.
- Session breakdown entry `PGC-KEYS-1` in `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`.
- Current Dart code in `lib/features/groups/domain/repositories/group_repository_impl.dart`, `test/shared/fakes/in_memory_group_repository.dart`, and `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` for named gates; if they disagree, the script wins.

Disagreement rule:

- Current code/tests beat stale prose.
- The source matrix/breakdown define row ownership and non-goals.
- If another in-flight dirty-worktree change has already replaced latest-plus-previous retention before execution starts, stop and reclassify this plan as `stale/already-covered` with evidence instead of layering another policy.

## session classification

`implementation-ready`

Reason: current Dart evidence directly matches row `PGC-013`: repository pruning and in-memory fake pruning use `latestGeneration - 1`, and drain stale replay uses `latestKeyGeneration - 1`. The existing DB helper already deletes keys below a caller-supplied generation threshold, so the change can be narrow and regression-tested without schema work.

## exact problem statement

Current Dart key retention keeps only the latest committed group key and the immediately previous generation. Offline replay also treats any replay epoch older than `latest - 1` as stale. A member who was offline through more than one group key rotation can still have valid retained backlog messages, but the receiver may have already pruned the key needed to decrypt those messages and will classify that replay as stale instead of decrypting it or preserving missing-key repair evidence.

User-visible improvement:

- A returning group member can recover valid retained offline backlog after multiple missed rotations, not only one missed rotation.

Must stay unchanged:

- Latest key selection remains highest generation.
- Older accepted key material must never promote over the current generation.
- Same-generation conflicting material remains rejected by the listener path.
- Future missing-key replay remains pending-key repair/placeholder behavior.
- Removed members still cannot decrypt post-removal/future-epoch replay with stale local key material.

## files and repos to inspect next

Production files:

- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart` inspection only unless missing-key error semantics need a narrow adjustment
- `lib/features/groups/application/group_key_update_listener.dart` inspection only for historical-key save behavior
- `lib/features/groups/application/group_pending_key_repair_service.dart` inspection only for pending-key repair behavior
- `lib/features/groups/domain/models/group_key_retention_policy.dart` for the shared retention policy
- `test/shared/fakes/in_memory_group_repository.dart`
- `lib/core/database/helpers/group_keys_db_helpers.dart` inspection only; current `dbDeleteGroupKeysBeforeGeneration` already supports the planned threshold

Test files:

- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/core/database/helpers/group_keys_db_helpers_test.dart` only if helper semantics change, which should not be necessary

Docs to update only after implementation evidence exists:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`
- This plan file's execution evidence section, if the executor records run results here

## existing tests covering this area

- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
  - `saveKey prunes obsolete generations from DB and shared push storage` currently pins the problematic latest-plus-previous behavior and must be replaced or renamed for `PGC-013`.
  - `saveKey and getLatestKey round-trip` and `getKeyByGeneration returns correct key` cover basic key lookup.
  - secure-storage wrapping tests prove SQL stores references and hydrated key material returns through `getLatestKey`/`getKeyByGeneration`.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `drains mixed epoch encrypted replay out of order without rewriting epochs` proves two retained epochs can decrypt out of order.
  - `GI-023 replay uses previous-epoch grace but skips expired replay epoch` currently pins the stale latest-plus-previous behavior and must be rewritten around the new bounded window.
  - `PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival` proves missing future epochs queue for repair and must keep passing.
  - `GK-022 removed member with old key cannot decrypt post-removal inbox replay`, `KE-021 future group inbox replay excludes removed member and stale key cannot decrypt`, and `PL-006 MD-011 removed member cannot decode future media replay with only the old epoch` guard removed-member/stale-key safety.
- `test/features/groups/application/group_key_update_listener_test.dart`
  - `delayed older key update after newer generation does not promote active key`
  - `RA-006 KE-011 delayed old key after re-add stays historical and current delivery remains on re-add epoch`
  - `KE-005 conflicting same-generation key updates keep first accepted material`
  - `KE-004 duplicate same-generation key update with same material is idempotent`
- `test/core/database/helpers/group_keys_db_helpers_test.dart` covers DB load/delete primitives, not retention policy.

Missing today:

- No test proves retention across more than two committed generations.
- No test proves replay for `latest - 7` decrypts while `latest - 8` is stale-skipped.
- No test proves the shared in-memory fake follows the production retention window.

## regression/tests to add first

Add regressions before changing implementation:

1. In `test/features/groups/domain/repositories/group_repository_impl_test.dart`, add or replace with:
   - `PGC-013 saveKey retains bounded offline replay key window and prunes only outside it`
   - Setup: save generations `1` through `9`.
   - Expected: generation `1` is gone; generations `2` through `9` remain queryable; shared push mirror and secure material for generation `1` are deleted; mirror/material for retained generations still hydrate.
   - Why it proves the seam: it fails against current latest-plus-previous pruning because generations `2` through `7` are deleted.
2. In `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, add or rewrite around:
   - `PGC-013 offline replay decrypts retained historical epochs and skips only outside key retention window`
   - Setup: save committed keys `1` through `9`, enqueue signed replay for generation `2` and generation `1`.
   - Expected: generation `2` replay decrypts and persists with `keyGeneration == 2`; generation `1` replay is not visible, creates no pending repair, and emits `GROUP_DRAIN_OFFLINE_INBOX_STALE_REPLAY_EPOCH_SKIPPED` with `minAcceptedKeyGeneration == 2`.
   - Why it proves the seam: it fails today because generation `2` is already pruned and/or classified stale under latest-plus-previous policy.
3. Keep or add a future-key repair assertion in `drain_group_offline_inbox_use_case_test.dart`:
   - `PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival`
   - Expected: unchanged. Future key epochs greater than latest must not be stale-skipped.
4. Keep key-update safety selectors in `group_key_update_listener_test.dart`:
   - `delayed older key update after newer generation does not promote active key`
   - `KE-005 conflicting same-generation key updates keep first accepted material`

Do not add a Go regression for this session unless the Dart regressions prove the stale classification is coming from Go, which current evidence does not show.

## step-by-step implementation plan

1. Reconfirm the dirty worktree state before editing:
   - Inspect `git status --short`.
   - Inspect current `GroupRepositoryImpl._pruneObsoleteKeys`, `InMemoryGroupRepository._pruneObsoleteKeys`, and `_resolveStaleReplayEpoch`.
   - Stop if another session has already replaced the latest-plus-previous policy and the new tests pass without product changes.
2. Add the failing Dart regressions first:
   - Repository retention test in `group_repository_impl_test.dart`.
   - Offline replay retained/stale boundary test in `drain_group_offline_inbox_use_case_test.dart`.
   - Adjust the existing `GI-023` stale test so it no longer asserts latest-plus-previous as intentional behavior.
3. Add a shared Dart retention policy:
   - Create `lib/features/groups/domain/models/group_key_retention_policy.dart`.
   - Define `const int groupKeyReplayRetentionGenerationCount = 8;`.
   - Define a helper equivalent to `minRetainedGroupKeyGeneration(int latestGeneration)`, returning `1` for latest generations inside the window and `latestGeneration - groupKeyReplayRetentionGenerationCount + 1` otherwise.
4. Update `GroupRepositoryImpl._pruneObsoleteKeys`:
   - Use the shared helper instead of `latestGeneration - 1`.
   - Replace the current `rows.length <= 2` early return with `rows.length <= groupKeyReplayRetentionGenerationCount`.
   - Keep existing `dbLoadAllGroupKeys`, `dbDeleteGroupKeysBeforeGeneration`, `_deleteGroupKeyMirror`, and `_deleteGroupKeyMaterial` behavior.
   - Preserve no-op behavior when optional helper functions are absent.
5. Update `InMemoryGroupRepository._pruneObsoleteKeys`:
   - Use the same shared helper and constant.
   - Replace the current `groupKeys.length <= 2` early return with `groupKeys.length <= groupKeyReplayRetentionGenerationCount`.
   - Keep same-generation replacement behavior unchanged.
6. Update `_resolveStaleReplayEpoch`:
   - Use the shared helper to compute `minAcceptedKeyGeneration`.
   - Return stale only when `keyEpoch < minAcceptedKeyGeneration`.
   - Keep future/missing-key repair behavior unchanged for `keyEpoch >= minAcceptedKeyGeneration` and for `keyEpoch > latestKeyGeneration`.
7. Run focused format and tests.
8. If all focused tests pass, run the Group Messaging Gate and diff checks.
9. After implementation evidence exists, update only row `PGC-013` in the source matrix and only `PGC-KEYS-1` in the session breakdown ledger.

Stop conditions:

- Stop and re-plan if implementing the retention helper requires a DB schema change.
- Stop and re-plan if a current repository already exposes a pending-repair minimum epoch and pruning would delete keys referenced by pending repairs. In that case, extend the plan to include that exact existing horizon; do not invent a broad new repair API in this session.
- Stop and re-plan if a test failure points to Go active-key state rather than Dart persisted-key lookup or stale replay classification.

## risks and edge cases

- Dirty worktree overlap: `drain_group_offline_inbox_use_case.dart` is already modified in the workspace. The executor must work with current content and avoid overwriting unrelated PGC-DRAIN or user edits.
- Retention boundary off-by-one: generation `latest - 7` must remain accepted with an `8`-generation window; generation `latest - 8` must be pruned/stale.
- Secure store and push mirror cleanup: pruned keys must be removed from SQL, secure material, and shared push mirror storage.
- Future missing-key replay: a replay with `keyEpoch > latest` must still queue pending repair instead of becoming stale.
- Within-window missing material: if SQL or secure storage is missing for a retained epoch, it should create pending repair/placeholder evidence rather than stale-skip.
- Removed-member safety: retaining more keys on an active member's device must not let a removed member decrypt post-removal traffic or make future-epoch ciphertext readable with old material.
- Historical key update order: delayed older keys can be stored for replay but must not become latest.
- Storage growth: `8` generations bounds growth; do not switch to "keep all keys for seven days" because frequent rotations could become unbounded.

## exact tests and gates to run

Regression-first commands expected to fail before implementation and pass after:

```bash
flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'PGC-013 saveKey retains bounded offline replay key window and prunes only outside it'
```

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-013 offline replay decrypts retained historical epochs and skips only outside key retention window'
```

Existing safety selectors to rerun:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival'
```

```bash
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'
```

```bash
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-005 conflicting same-generation key updates keep first accepted material'
```

Focused direct files:

```bash
flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

Use this exact device-pinned variant only if the local Flutter setup requires an explicit device:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Formatting and diff checks:

```bash
dart format lib/features/groups/domain/models/group_key_retention_policy.dart lib/features/groups/domain/repositories/group_repository_impl.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/shared/fakes/in_memory_group_repository.dart test/features/groups/domain/repositories/group_repository_impl_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
```

```bash
git diff --check
```

No Go command is required for this session under current evidence.

## known-failure interpretation

- Capture a focused baseline before implementation for the two new `PGC-013` regressions; they should fail before code changes and pass after.
- If full `drain_group_offline_inbox_use_case_test.dart` or `./scripts/run_test_gates.sh groups` has unrelated pre-existing failures in this dirty worktree, rerun the exact failing selectors and classify only failures whose assertion path crosses `GroupRepositoryImpl._pruneObsoleteKeys`, `InMemoryGroupRepository._pruneObsoleteKeys`, or `_resolveStaleReplayEpoch` as PGC-013 regressions.
- Do not classify failures from concurrently modified Go files, DB message upsert work, drain sender/receipt/reaction/concurrency work, or UI presentation files as PGC-013 unless a focused reproduction points back to Dart key retention or stale replay threshold.
- Do not mark the session closed on "known failures" alone; the new PGC-013 focused regressions and the existing safety selectors must pass.

## done criteria

- `PGC-013` repository regression passes and proves generations `2` through `9` survive while generation `1` is pruned when latest is `9`.
- `PGC-013` drain regression passes and proves generation `2` replay decrypts while generation `1` stale-skips with `minAcceptedKeyGeneration == 2`.
- Future-key repair selector still passes.
- Historical key update non-promotion and same-generation conflict selectors still pass.
- Focused direct files pass.
- `./scripts/run_test_gates.sh groups` passes, or any failure is documented as pre-existing and unrelated with exact focused rerun evidence.
- `git diff --check` passes.
- Source matrix row `PGC-013` and breakdown session `PGC-KEYS-1` are updated only after test evidence exists.
- No Go files are changed.

## scope guard

Explicit non-goals:

- Do not touch `go-mknoon/**`, `go-relay-server/**`, platform bridge files, or Go key-rotation grace logic for this row.
- Do not change group encryption protocol, signatures, AAD, envelope schema, relay payload shape, or key distribution.
- Do not change membership authorization, removed-member snapshot behavior, sender/device binding, receipt handling, message dedupe, inbox cursor persistence, or drain concurrency.
- Do not add a new database migration for `group_keys`; current `key_generation` and `created_at` fields are sufficient for this plan.
- Do not add unbounded retention based on age alone.
- Do not couple `GroupRepositoryImpl` to pending repair repositories unless current code already exposes a minimal pending-epoch horizon before implementation starts.
- Do not rewrite or normalize unrelated tests in the large drain suite.
- Do not revert, overwrite, or restyle unrelated dirty-worktree edits.

Overengineering signs:

- A configurable runtime preference for key-retention count.
- A protocol-version negotiation for replay envelopes.
- A new key escrow or repair transport.
- Go active-key grace changes without a failing Dart evidence path proving Go is the source.
- Broad matrix closure claims beyond row `PGC-013`.

## accepted differences / intentionally out of scope

- Dart may retain several historical committed keys for offline replay while Go keeps only current/previous active key state for live pubsub behavior. That is accepted because Dart historical retention is local replay material and must not promote active send/decrypt state.
- The planned policy is generation-bounded, not a complete guarantee for arbitrary numbers of rotations during the seven-day backlog window. Covering arbitrary high-frequency rotations would require a larger product/security decision and possibly time-plus-count policy, which is outside row `PGC-013`.
- Pending repair repositories expose exact pending repairs by group/epoch, not a group-level "minimum key epoch to preserve" horizon in the inspected code. This plan does not invent that cross-repository dependency.
- Existing removed-member local history behavior remains governed by current removed-member and stale-key tests.

## dependency impact

- `PGC-DRAIN-1` also touches `drain_group_offline_inbox_use_case.dart`; do not run PGC-KEYS-1 and PGC-DRAIN-1 as parallel write sessions against the same file. Whichever session executes second must re-read the current file and preserve the first session's changes.
- Later private-group reliability closure depends on row `PGC-013` being either `Closed` with focused retention/replay evidence or `Blocked` with an exact blocker.
- If this plan is changed from generation-bounded to time-bounded retention, rerun this plan's reviewer/arbiter because storage-growth and stale-skip semantics change.
- If Go key rotation evidence emerges, split that into a separate Go-owned plan instead of expanding PGC-KEYS-1.

## Reviewer Pass

Verdict: sufficient with adjustments.

Reviewer questions:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient with the applied adjustments that make `group_key_retention_policy.dart` exact and update both pruning early-return guards to the new retention count.
- What files, tests, regressions, or gates are missing? No structural omissions. The plan names production, fake, direct tests, existing safety selectors, Group Messaging Gate, formatting, and diff checks.
- What assumptions are stale or incorrect? None found in current inspected code. The plan correctly treats current latest-plus-previous behavior as the source of the gap.
- What is overengineered? No overengineering remains; the plan rejects runtime preferences, protocol migration, and Go changes.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. The work is one Dart policy plus two callers and direct tests.
- What is the minimum needed to make the plan sufficient? The already-applied wording tightening around the exact shared policy file and pruning guard.

## Arbiter Pass

Structural blockers: none.

Incremental details:

- Exact shared policy file and pruning early-return guard wording were already applied before final arbitration.

Accepted differences:

- Dart historical replay retention can intentionally differ from Go active-key grace behavior.
- Generation-bounded retention is accepted for this session; arbitrary high-frequency rotation coverage is out of scope.
- Pending-repair horizon coupling is left out because inspected repositories do not expose a group-level minimum retained key epoch.

Decision: stop. No second reviewer loop is required because the arbiter found no structural blocker.

## Final Planning Output

Final verdict: execution-ready for `PGC-KEYS-1` / row `PGC-013`.

Final plan: implement one Dart-only, generation-bounded group key retention policy; wire it into `GroupRepositoryImpl`, `InMemoryGroupRepository`, and `_resolveStaleReplayEpoch`; add regression-first repository and offline replay tests; rerun focused key/replay safety selectors plus the Group Messaging Gate.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- The exact product value can be revisited later if telemetry or product policy wants a retention count other than `8`, but this session needs a concrete bounded policy now.
- A broader pending-repair minimum-epoch API is not added in this row.

Accepted differences intentionally left unchanged:

- Go key rotation and active-key grace are not touched.
- Protocol/AAD/key-envelope hardening is not reopened.
- Removed-member local history behavior stays governed by existing tests.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository.dart`
- `lib/core/database/helpers/group_keys_db_helpers.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`

Why the plan is safe to implement now: the gap is localized to Dart key retention and stale replay classification, existing DB helpers already support a wider generation threshold, the plan starts with failing focused regressions, and the scope guard prevents Go/protocol/database migration drift unless new evidence proves this classification wrong.

## Execution Result

Final verdict: accepted for row `PGC-013` focused implementation; broader drain file remains red from unrelated in-flight drain work, so `./scripts/run_test_gates.sh groups` was not run.

Files changed for this row:

- `lib/features/groups/domain/models/group_key_retention_policy.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-KEYS-1-plan.md`

Implementation notes:

- Added shared `groupKeyReplayRetentionGenerationCount = 8` and `minRetainedGroupKeyGeneration`.
- Clamped the minimum generation to `0` because current app creation flows still use initial group key generation `0`; latest `9` still produces the required minimum retained generation `2`.
- Wired repository pruning, in-memory fake pruning, and stale replay classification to the shared helper.
- Kept secure-store material and shared push mirror deletion for pruned generations.
- Replaced the old latest-plus-previous drain stale replay test with the row-owned `PGC-013` boundary regression.
- Did not edit Go, relay, listener, send path, DB message helpers, matrix, or breakdown closure docs.

Regression-first baseline:

- `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'PGC-013 saveKey retains bounded offline replay key window and prunes only outside it'` failed before product wiring because generation `2` was already pruned.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-013 offline replay decrypts retained historical epochs and skips only outside key retention window'` failed before product wiring because retained generation `2` was unavailable.

Passing focused evidence:

- `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'PGC-013 saveKey retains bounded offline replay key window and prunes only outside it'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-013 offline replay decrypts retained historical epochs and skips only outside key retention window'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-005 conflicting same-generation key updates keep first accepted material'`
- `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `dart format lib/features/groups/domain/models/group_key_retention_policy.dart lib/features/groups/domain/repositories/group_repository_impl.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/shared/fakes/in_memory_group_repository.dart test/features/groups/domain/repositories/group_repository_impl_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `git diff --check`

Focused direct-file result:

- `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` remained red in `drain_group_offline_inbox_use_case_test.dart` while the `PGC-013` selector passed.
- Exact unrelated drain failures captured from the drain file run:
  - `GE-018 seeded offline replay envelope tampering rejects before plaintext render`
  - `ML-008 deferred unknown sender group replay is skipped without blocking cursor progress`
  - `ML-008 cursorless final page stores timestamp high-water instead of clearing progress`
  - `PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor and advances only after page apply`
  - `IR-009 persistence failure retries same page before cursor or ack commit`
  - `GI-018 removed member offline replay keeps pre-removal message and stops at removal cutoff`
  - `GM-033 replay resume rejects removed-window messages after self re-add`
  - `GK-023 re-added member skips removed-window replay and renders post-readd replay`
  - `GI-019 re-added member replay keeps pre-remove skips removed-window and renders post-readd`
  - `GI-021 inbox replay rejects non-member sender without rendering`
  - `GI-022 revoked-device replay is rejected while active-device replay continues`
  - `GK-024 late-joining member skips pre-join replay and renders post-join replay`
  - `beyond-window backlog is skipped and records the expired timestamp`
  - `mixed old and new cursor pages keep retained backlog and record both boundaries`
  - `repeated drains do not resurrect expired backlog`
  - `NW-012 long offline replay applies final re-add interval and rejects stale removed-window epochs`
  - `GI-024 duplicate replay is idempotent without status rollback or notification spam`
  - `GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once`
  - `drainGroupOfflineInbox use case GI-017 offline member drains 120 entitled messages across pages exactly once`

Gate decision:

- Groups gate skipped because the focused direct drain file was not green and the user/plan required the groups gate only after direct focused evidence is green.
