# GEK-001 Key Update Monotonicity and Same-Epoch Conflict Handling Plan

Status: execution-ready

## Planning Progress

- `2026-05-09T19:13:45Z` - Planner completed. Files inspected since last update: none. Decision/blocker: draft is implementation-ready pending reviewer sufficiency checks; direct listener tests should go red on current same-epoch conflict behavior, while Go monotonic tests should document the existing boundary. Next action: run the Reviewer pass against scope, gates, and stop rules.
- `2026-05-09T19:16:15Z` - Reviewer started. Files inspected since last update: current GEK-001 plan draft, `test/features/groups/application/group_key_update_listener_test.dart` listener setup. Decision/blocker: review will check mandatory sections, audit ordering, test measurability, gate scope, and whether the plan accidentally broadens into GEK-002/003/004. Next action: record sufficiency findings and required adjustments.
- `2026-05-09T19:16:37Z` - Reviewer completed. Files inspected since last update: none. Decision/blocker: plan is sufficient with adjustments; no structural blocker found, but audit-verification ordering and retry-callback test measurability need clearer wording before final. Next action: Arbiter classification and final patch if accepted as incremental detail.
- `2026-05-09T19:17:20Z` - Arbiter started. Files inspected since last update: reviewer-adjusted GEK-001 plan sections. Decision/blocker: classify review findings as structural blockers, incremental details, or accepted differences. Next action: finalize verdict and set execution readiness only if no structural blockers remain.
- `2026-05-09T19:17:46Z` - Arbiter completed. Files inspected since last update: none. Decision/blocker: no structural blockers remain; reviewer adjustments were incremental and are patched into durable sections; accepted differences are documented. Next action: hand off the `Status: execution-ready` plan for implementation.

## Execution Progress

- `2026-05-09T19:19:43Z` - Controller contract extraction started. Files inspected or touched: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md`, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`. Command running: none. Decision/blocker: extracting exact GEK-001 scope, closure bar, source of truth, owner files, direct tests, named gates, known-failure interpretation, done criteria, and scope guard before coding. Next action: finish contract extraction and check spawned Executor/QA availability.
- `2026-05-09T19:19:43Z` - Controller contract extraction completed. Files inspected or touched: same plan, breakdown orientation artifact, current `test-gate-definitions.md`. Command running: none. Decision/blocker: GEK-001 is concrete and execution-safe; required regressions are the listener stale-older, same-generation conflict, duplicate-idempotent tests plus Go `UpdateGroupKey` monotonic tests; required gates are focused Flutter tests, full listener file, focused Go command, `./scripts/run_test_gates.sh groups`, and `git diff --check`; conditional persistence sweep only if persistence files change. Next action: spawn fresh Executor agent with this contract.
- `2026-05-09T19:20:25Z` - Executor spawned/running. Files inspected or touched: plan progress only. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app --sandbox danger-full-access -a never`. Decision/blocker: fresh Executor child will implement only GEK-001, update this progress log, and run required tests/gates as feasible. Next action: wait bounded interval for Executor result and inspect repo evidence.
- `2026-05-09T19:21:04Z` - Executor spawn command corrected. Files inspected or touched: plan progress only. Command running: none. Decision/blocker: first child command exited before materializing because approval policy was placed after `exec`; this is a CLI invocation error, not Executor work or repo evidence. Next action: relaunch fresh Executor with top-level approval/sandbox options.
- `2026-05-09T19:21:50Z` - Executor owner-file inspection started. Files inspected or touched: plan progress only so far. Command running: none. Decision/blocker: executing GEK-001 only, with dirty worktree preserved and owner files limited to listener, focused Flutter test, and Go boundary test unless plan evidence requires adjacent helpers. Next action: inspect owner files and direct helper surfaces before adding regressions.
- `2026-05-09T19:22:37Z` - Executor owner-file inspection completed. Files inspected or touched: `lib/features/groups/application/group_key_update_listener.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `test/core/bridge/fake_bridge.dart`, `test/shared/fakes/in_memory_group_repository.dart`, `lib/features/groups/domain/repositories/group_repository.dart`, `go-mknoon/node/pubsub.go`. Command running: none. Decision/blocker: listener currently validates then appends accepted audit, calls `group:updateKey`, saves/replaces local material, and retries repair; Go already returns for same-or-lower epochs; repository replacement risk can be guarded listener-locally. Next action: add GEK-001 Flutter regressions and Go boundary tests before production changes.
- `2026-05-09T19:22:54Z` - Controller progress response while Executor remains running. Files inspected or touched: controller touched this plan progress section; Executor has inspected/touched the owner/helper files listed in the previous entry. Command running: `codex ... exec` session `019e0e30-0104-7541-bc09-fd35eb5204c4` for the spawned Executor. Decision/blocker: no blocker; child produced real progress and is currently preparing regression-first test changes. Next action: continue bounded wait for Executor completion, then spawn a separate QA Reviewer.
- `2026-05-09T19:24:16Z` - Executor focused red test phase started. Files inspected or touched: added GEK-001 regressions in `test/features/groups/application/group_key_update_listener_test.dart` and Go boundary tests in `go-mknoon/node/pubsub_key_rotation_grace_test.go`; production listener unchanged. Command running: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'`. Decision/blocker: expecting Flutter regressions to fail against current listener and Go monotonic boundary to pass; if Go fails, fix Go before Dart. Next action: run required focused red commands and record results.
- `2026-05-09T19:25:10Z` - Executor focused red test phase completed. Files inspected or touched: same test files; production listener unchanged. Commands/results: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'` failed as expected because `group:updateKey` count was `2` instead of `1`; `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates keep first accepted material'` failed as expected because stored generation-2 material became `key-epoch-2b` instead of `key-epoch-2a`; `cd go-mknoon && go test ./node -run 'TestUpdateGroupKey_(PreservesPreviousKeyAndGraceDeadline|IgnoresSameEpochDifferentMaterial|IgnoresOlderEpochAfterCurrent)' -count=1` passed. Decision/blocker: Go monotonic boundary is sound; continue with listener-local guard only. Next action: implement monotonic/conflict handling before audit append, bridge update, save replacement, and pending repair retry.
- `2026-05-09T19:28:07Z` - Executor focused green test phase started. Files inspected or touched: `lib/features/groups/application/group_key_update_listener.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`; formatted touched Dart and Go files. Command running: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'`. Decision/blocker: listener now serializes direct key-update handling, verifies audit before acceptance, rejects/ignores same-generation conflicts before append/update/save/retry, and stores missing older historical material without promoting active Go state. Next action: run exact focused green commands and record results.
- `2026-05-09T19:28:44Z` - Executor focused green test phase completed and listener sweep started. Files inspected or touched: same owner files. Commands/results: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'` passed; `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates keep first accepted material'` passed; `cd go-mknoon && go test ./node -run 'TestUpdateGroupKey_(PreservesPreviousKeyAndGraceDeadline|IgnoresSameEpochDifferentMaterial|IgnoresOlderEpochAfterCurrent)' -count=1` passed. Command running: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart`. Decision/blocker: focused GEK-001 behavior is green; verify existing listener coverage remains intact. Next action: run full listener file and record result.
- `2026-05-09T19:29:10Z` - Executor listener sweep completed and named groups gate started. Files inspected or touched: same owner files. Commands/results: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart` passed. Command running: `./scripts/run_test_gates.sh groups`. Decision/blocker: focused owner sweep is green with 31 tests; now verifying the named group gate required by the plan. Next action: run groups gate and record result.
- `2026-05-09T19:29:44Z` - Executor named groups gate completed and hygiene phase started. Files inspected or touched: same owner files plus plan progress. Commands/results: `./scripts/run_test_gates.sh groups` passed. Command running: `git diff --check`. Decision/blocker: no persistence files changed, so conditional persistence sweep is not required. Next action: run diff hygiene and record final Executor verdict.
- `2026-05-09T19:30:07Z` - Executor completed. Files inspected or touched: `lib/features/groups/application/group_key_update_listener.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, plan progress only; unrelated dirty worktree files were left untouched. Commands/results: `git diff --check` passed. Decision/blocker: GEK-001 Executor scope is implemented and required focused tests/gates passed; conditional persistence sweep skipped because no persistence files changed. Next action: hand off for QA Reviewer role without performing QA locally.
- `2026-05-09T19:31:17Z` - QA Reviewer spawned/running. Files inspected or touched: controller inspected plan progress and owner-file status; touched plan progress only. Command running: `codex exec` QA Reviewer with `model: gpt-5.5`, `reasoning_effort: xhigh`. Decision/blocker: Executor finished with required evidence; separate QA will review scope adherence, behavior, required tests/gates, and done criteria without editing code. Next action: wait bounded interval for QA result.
- `2026-05-09T19:33:22Z` - QA Reviewer started. Files inspected or touched: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md`, owner-file diff for `lib/features/groups/application/group_key_update_listener.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, and `go-mknoon/node/pubsub_key_rotation_grace_test.go`; touched plan progress only. Command running: none. Decision/blocker: reviewing only GEK-001 owner files for scope adherence, behavior, required red/green evidence, required direct tests/gates, and GEK-002/003/004/005 scope bleed. Next action: run fresh QA verification commands and record blocking/non-blocking findings.
- `2026-05-09T19:34:28Z` - QA Reviewer completed. Files inspected or touched: same GEK-001 owner files and plan progress only. Commands/results accepted: Executor-recorded red-before-fix Flutter focused tests failed for expected stale/same-generation reasons; `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'` passed; `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates keep first accepted material'` passed; `cd go-mknoon && go test ./node -run 'TestUpdateGroupKey_(PreservesPreviousKeyAndGraceDeadline|IgnoresSameEpochDifferentMaterial|IgnoresOlderEpochAfterCurrent)' -count=1` passed; `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart` passed; `./scripts/run_test_gates.sh groups` passed; `git diff --check` passed. Decision/blocker: blocking issues: none; non-blocking follow-ups: none; conditional persistence sweep correctly skipped because no persistence files changed; no GEK-002/003/004/005 scope bleed found in owner-file diff. Next action: final QA verdict accepted.
- `2026-05-09T19:35:15Z` - Final execution verdict recorded. Files inspected or touched: GEK-001 owner files plus this plan progress section; unrelated dirty worktree files were left untouched. Command running: none. Decision/blocker: verdict accepted, no fix loop required, no blockers remain. Next action: report final verdict, files changed, commands/results, and blockers to the user.

## real scope

GEK-001 owns only direct group key-update acceptance semantics for:

- delayed older key updates arriving after a newer key generation is already accepted locally
- same-generation updates carrying different key material for the same group epoch
- the Flutter-to-Go boundary where `group:updateKey` may promote Go's active key state
- local persistence behavior only to the extent needed to keep direct key-update handling from replacing already accepted same-generation material

The intended code change is expected to be in `lib/features/groups/application/group_key_update_listener.dart`, with focused tests in `test/features/groups/application/group_key_update_listener_test.dart` and Go boundary proof in `go-mknoon/node/pubsub_key_rotation_grace_test.go`.

This session does not implement GEK-002 live decrypt placeholder repair, GEK-003 partial delivery rotation races, GEK-004 membership/config propagation, or GEK-005 final simulator/relay acceptance.

## closure bar

GEK-001 is good enough when direct host and Go-boundary tests prove:

- an incoming key update with `keyGeneration` lower than the latest accepted generation cannot call `group:updateKey` and cannot make Go or Dart choose that older generation as the active/latest key
- a delayed older key may be persisted only as historical material for its own generation when it is absent or matches already stored material, so replay repair remains possible without active rollback
- an incoming key update with the same generation and different key material is rejected or ignored before `group:updateKey`, before replacing stored key material, and before triggering pending repair on the conflicting material
- same-generation duplicate material remains idempotent and does not create a conflict
- existing sequential epoch 2 then epoch 3 acceptance, bridge-failure rollback, pending receive-side send behavior, event-log/audit validation, no-backfill, removed-member exclusion, and group message gates remain unchanged

## source of truth

On disagreement, current code and focused tests win over stale prose. `Test-Flight-Improv/test-gate-definitions.md` wins for named gate commands. The active session contract is `GEK-001` in `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md` unless code evidence proves it stale.

Authoritative evidence for this plan:

- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/pubsub.go`
- `test/features/groups/application/group_key_update_listener_test.dart`

## session classification

`implementation-ready`

The evidence shows a concrete host/app-layer mismatch: Go `UpdateGroupKey` already ignores same-or-lower epochs, but the Dart listener currently saves the incoming key after the bridge returns success. Because SQL and fake persistence can replace a row for the same `(group_id, key_generation)`, same-epoch conflicting key material can leave Dart persistence on different material than Go's active key.

## exact problem statement

The direct key-update listener accepts validated P2P key updates, calls `group:updateKey`, then saves the key locally. Existing tests intentionally prove epoch 2 then epoch 3 convergence, but the same-generation test currently expects two different generation-2 materials to converge to the later stored key. That is unsafe for the reported trust failure: users can split on same-epoch key material, and the app may silently keep Dart and Go key state inconsistent.

Delayed older key updates are also under-specified at the Flutter boundary. Go ignores same-or-lower epoch promotion, but the listener should not rely on a no-op bridge result to prove active monotonicity. Older material can be retained for historical replay only when it does not conflict with already stored material; it must not promote active Go state or replace a same-generation key.

User-visible behavior that must improve: current and future group messages must not become unreadable because a stale or conflicting direct key update overwrote active local key expectations.

Behavior that must stay unchanged: valid higher-epoch key updates still promote Go and Dart state, retry pending repairs for that epoch, and keep existing validation/audit/device-binding checks.

## files and repos to inspect next

Production files:

- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/bridge/bridge.go`

Direct tests:

- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/core/bridge/fake_bridge.dart`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`

Conditional files only if the listener seam cannot close the issue without persistence changes:

- `lib/core/database/helpers/group_keys_db_helpers.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/core/database/helpers/group_keys_db_helpers_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`

## existing tests covering this area

Existing `group_key_update_listener_test.dart` covers successful decrypt/save, bridge update ordering, missing encrypted/secret/decrypt guards, `group:updateKey` payload shape, sequential epoch 2 then epoch 3 acceptance, bridge failure preserving the old active key, direct key-update audit/tamper validation, unauthorized sender rejection, source device binding, and recipient device binding.

Existing `group_key_update_listener_test.dart` currently records unsafe same-generation behavior: `conflicting same-generation key updates converge to one final stored key` expects the second generation-2 key to replace the first and expects two `group:updateKey` calls.

Existing `send_group_message_use_case_test.dart`, `rotate_and_distribute_group_key_use_case_test.dart`, and `drain_group_offline_inbox_use_case_test.dart` already cover MS-018 send-time epoch snapshots, local rotation commit ordering, mixed old/new encrypted replay, and future-epoch pending/undecryptable placeholder behavior. Those are supporting evidence, not GEK-001 implementation scope.

Existing Go `pubsub_key_rotation_grace_test.go` covers previous-key grace state after a higher-epoch update, future-epoch rejection, and old/current epoch validation during grace. `go-mknoon/node/pubsub.go` already returns early for `keyInfo.KeyEpoch <= current.KeyEpoch`, but there is no focused test for same-epoch different material or older-epoch no-op.

## regression/tests to add first

Add or update tests before production changes:

- In `test/features/groups/application/group_key_update_listener_test.dart`, replace the current same-generation convergence expectation with a regression proving a second same-generation update carrying different `encryptedKey` does not replace the first accepted material, does not call `group:updateKey` a second time, and does not retry pending repairs for the conflicting material. Inject a `retryPendingGroupKeyRepairs` callback counter in that test if needed so the assertion is measurable.
- In `test/features/groups/application/group_key_update_listener_test.dart`, add a delayed older-key regression: accept a newer generation first, then deliver an older generation. Assert the listener does not call `group:updateKey` for the older generation, the latest key remains the newer generation, and any older persisted key is stored only for its own generation without replacing conflicting existing material.
- In `test/features/groups/application/group_key_update_listener_test.dart`, add an idempotent duplicate proof for the same generation and same key material if it is not naturally covered by the conflict test setup.
- In `go-mknoon/node/pubsub_key_rotation_grace_test.go`, add focused boundary tests proving `Node.UpdateGroupKey` ignores same-epoch different material and older-epoch updates while preserving the current key and previous-key grace state.

Expected red/green shape:

- Flutter same-generation conflict and delayed older-key listener tests should fail before the Dart implementation.
- Go monotonic boundary tests should pass against current Go code. If they fail, GEK-001 must stop and fix the Go boundary before relying on Dart listener rules.

## step-by-step implementation plan

1. Add the focused Flutter listener regressions and Go boundary tests listed above.
2. Run the focused red commands for the new Flutter tests. Record that the same-generation conflict and delayed older-key listener tests fail for the expected reason.
3. Run the focused Go command. If the Go monotonic tests fail, stop the Dart implementation and fix `go-mknoon/node/pubsub.go` first; do not mask a Go active-key rollback with Dart-only tests.
4. In `GroupKeyUpdateListener`, after decrypt/signature/sender/device/recipient validation and required signed-audit validation, but before event-log append, `callGroupUpdateKey`, local save, or repair retry, inspect the latest key and the same-generation stored key through `GroupRepository`. If the current code couples audit verification and append, refactor that block so verification can run without recording a rejected stale/conflicting update as an accepted transition.
5. For incoming `keyGeneration` lower than the latest accepted generation, do not call `group:updateKey`. Persist the older key only if no key for that generation exists, or if the existing material is identical. If an existing same-generation historical key has different material, reject/ignore the incoming material and leave stored state unchanged.
6. For incoming `keyGeneration` equal to an already stored generation, return idempotently if material is identical. If material differs, emit a flow event such as `GROUP_KEY_UPDATE_LISTENER_SAME_EPOCH_CONFLICT` and return before bridge update, event-log append, save, or pending-repair retry.
7. For incoming `keyGeneration` higher than the latest accepted generation, keep the existing path: append audit when configured, call `group:updateKey`, save the new key, emit saved, and retry pending repairs for that epoch.
8. Keep `GroupRepository.saveKey`, `dbInsertGroupKey`, and `InMemoryGroupRepository.saveKey` unchanged unless the direct listener tests cannot distinguish safe historical persistence from unsafe replacement. If persistence changes become unavoidable, add a narrow helper or listener-local guard rather than changing the global `saveKey` contract used by create, invite, join, and local rotation flows.
9. Re-run the focused Flutter tests, the full listener file, the Go boundary command, and the group gate.
10. Stop the session after GEK-001 tests and gates are green. Do not add live decrypt repair journeys, partial-recipient simulator scenarios, membership/config propagation tests, or final closure-doc verdicts in this session.

## risks and edge cases

- A delayed older key can be useful for decrypting historical durable replay. Do not discard non-conflicting historical material solely because it is older than the latest active generation.
- Same-generation different material is the risky split-brain case. It must not replace existing material even if the sender is authorized and the signature is valid.
- Reordering must not bypass existing validation. The monotonic/conflict decision should run only after decrypt, sender authorization, source-device binding, signature verification, recipient binding, and required signed-audit verification checks. Rejected stale/conflicting updates should not be appended as accepted audit-log transitions.
- Event-log append order matters. Rejected stale/conflicting updates should not be appended as accepted `group_key_update` events.
- `group:updateKey` bridge failures for genuinely newer updates must still preserve the old key and avoid local save.
- Secure-storage hydration can return `null` for missing key material. Treat that as existing test behavior unless a focused GEK-001 test proves it blocks conflict detection; do not broaden into secure-storage repair.
- `GroupRepository.saveKey` has many owners. Global save semantics changes can accidentally affect create, invite accept, local rotation, rejoin, and test fixtures.

## exact tests and gates to run

Focused red/green tests:

```bash
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates keep first accepted material'
cd go-mknoon && go test ./node -run 'TestUpdateGroupKey_(PreservesPreviousKeyAndGraceDeadline|IgnoresSameEpochDifferentMaterial|IgnoresOlderEpochAfterCurrent)' -count=1
```

Focused owner sweep:

```bash
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart
```

Conditional persistence sweep if `group_repository_impl.dart`, `group_keys_db_helpers.dart`, or `InMemoryGroupRepository` changes:

```bash
flutter test --no-pub test/core/database/helpers/group_keys_db_helpers_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart
```

Named gate and hygiene:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

No simulator, device, or relay command is required for GEK-001 unless implementation evidence changes the scope from direct key-update acceptance into live multi-recipient transport behavior.

## known-failure interpretation

Failures in `test/features/groups/application/group_key_update_listener_test.dart` or the new Go `TestUpdateGroupKey_*` tests are GEK-001 blockers.

`./scripts/run_test_gates.sh groups` failures are GEK-001 blockers unless the failing test is clearly unrelated to key update acceptance and already documented as pre-existing in the current worktree. In that case, record the exact failing test and why the focused GEK-001 tests still passed.

Do not use broad `flutter test --no-pub test/features/groups/application` as the closure gate for GEK-001; the inventory records unrelated broad-suite caveats such as prior MD-011/future-media issues. If a broad suite is run opportunistically and fails outside the focused listener path, classify it as non-blocking only with exact evidence.

Known broad Go owner failures around peer-count/topic-peer mismatches are not GEK-001 blockers if the focused `go test ./node -run 'TestUpdateGroupKey_...'` command passes. Any failure in `pubsub_key_rotation_grace_test.go` is a blocker.

Dirty worktree changes outside `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md` are not evidence of GEK-001 implementation and must not be reverted or claimed.

## done criteria

- The plan's Flutter regressions exist and prove stale older updates do not promote active key state.
- Same-generation conflicting key material is rejected/ignored without replacing stored material and without a second `group:updateKey`.
- Non-conflicting historical older material remains available for its generation when needed for replay, without changing the latest active generation.
- Higher-generation key updates still pass existing listener tests and still trigger Go update, local save, and pending repair retry.
- Focused Flutter listener tests pass.
- Focused Go `UpdateGroupKey` monotonic tests pass.
- `./scripts/run_test_gates.sh groups` and `git diff --check` pass, or any unrelated pre-existing failure is recorded with exact evidence.
- No GEK-002/003/004/005 behavior is implemented or claimed.

## scope guard

Do not implement live `group:decryption_failed` placeholder repair, durable replay journeys, pending repair UI, multi-recipient partial delivery simulator proof, membership/config propagation, invite eligibility truth, or final rollout verdicts.

Do not change group membership policy, removed-member exclusion, no-backfill semantics, send-time epoch snapshotting, event-log audit requirements, or bridge command payload shape except to avoid unsafe stale/conflicting key promotion.

Do not replace the global `GroupRepository.saveKey` contract unless the listener-local approach cannot make the regressions pass. A global save-key rewrite would be overengineering for GEK-001 because create, invite, join, local rotation, test setup, and historical replay all rely on direct key saves.

Do not add a device, simulator, relay, or real-network gate for this session. That work belongs to later sessions only if the code change moves beyond host/app-layer key-update acceptance.

## accepted differences / intentionally out of scope

Go and Flutter have different responsibilities here. Go owns active topic-validator key monotonicity and already treats same-or-lower epoch `UpdateGroupKey` as no-op. Flutter owns whether a validated direct key update should call that boundary and whether local persisted material should be replaced.

Historical older key material can exist in Dart persistence for replay while Go remains on the latest active key. That is an accepted difference, not a split-brain bug, as long as the older key cannot become active/latest and cannot replace different same-generation material.

Device/relay proof is intentionally out of scope for GEK-001 because the targeted failure is reproducible at the host listener and Go node boundary. GEK-003/GEK-005 own partial-recipient and real-network acceptance.

Closure docs and source spec updates are not part of this planning-only task. The implementation/closure sessions may update the source spec, inventory, closure reference, and breakdown ledger after code and tests land.

## dependency impact

GEK-002 and GEK-003 may rely on this session's key acceptance contract when repairing pending messages after later key arrival. If GEK-001 changes conflict semantics differently than this plan, those sessions must refresh their assumptions before execution.

GEK-004 is independent unless it starts using direct key-update conflict semantics for membership/config catch-up.

GEK-005 final acceptance must not mark the whole source spec closed until GEK-001 through GEK-004 are accepted, stale/already-covered with evidence, or truthfully blocked. GEK-001 can close only the delayed older key update and same-epoch conflicting key material slice.

## Reviewer Findings

- Sufficiency: sufficient with adjustments.
- Missing files, tests, regressions, or gates: add `test/core/bridge/fake_bridge.dart` as a direct helper file to inspect while implementing measurable command-log assertions; no missing named gate found.
- Stale or incorrect assumptions: the draft was directionally correct that audit validation must precede monotonic decisions, but needed clearer wording because current listener code couples audit verification and event-log append.
- Overengineering: no device/relay profile, repository-wide save rewrite, or GEK-002/003/004 scope is needed.
- Decomposition: sufficiently narrow for implementation; the stop rule correctly prevents broad persistence rewrites unless listener-local tests cannot close the gap.
- Minimum needed to make sufficient: clarify audit verification versus accepted event-log append, and make the pending-repair assertion measurable with an injected callback counter.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: patched reviewer wording for audit verification/event-log append order, measurable pending-repair assertions, and helper-file inspection.
- Accepted differences: Go active-key monotonicity and Dart historical-key persistence remain separate responsibilities; no device/relay proof is required for this host/Go-boundary session; repository-wide save semantics stay unchanged unless listener-local implementation evidence proves otherwise.
- Stop rule result: no new structural blocker, so planning stops after this arbiter pass.

## Final verdict

GEK-001 is execution-ready.

## Final plan

Implement the listener-local monotonic/conflict acceptance rule with regression-first Flutter tests and Go `UpdateGroupKey` boundary proof. Preserve non-conflicting historical older material for replay, reject conflicting same-generation material before active promotion or persistence replacement, and leave GEK-002/003/004/005 scope untouched.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Exact flow-event names may be chosen during implementation, but they must distinguish stale older update handling from same-epoch conflict rejection.
- If the executor chooses different test names, update the focused `--plain-name` commands in the implementation evidence.

## Accepted differences intentionally left unchanged

- Dart may store historical older key material while Go remains on the latest active key.
- `GroupRepository.saveKey` remains replace-capable for existing create, invite, join, rotation, fixture, and replay owners unless focused listener tests prove a global guard is necessary.
- Device, simulator, relay, live decrypt repair, and multi-recipient partial-delivery proof are deferred to later GEK sessions.

## Exact docs/files used as evidence

- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`
- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`
- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/database/helpers/group_keys_db_helpers.dart`
- `lib/core/database/migrations/018_group_messages_tables.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/core/database/helpers/group_keys_db_helpers_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`

## Why the plan is safe or unsafe to implement now

Safe to implement now. The plan is bounded to the direct key-update listener and Go monotonic boundary, has regression-first tests, names exact gates, preserves existing validation and replay needs, and includes a stop rule before any repository-wide or later-session expansion.
