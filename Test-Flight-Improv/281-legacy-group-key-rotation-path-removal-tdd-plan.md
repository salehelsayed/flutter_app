# 281 - Legacy group-key rotation path removal

Status: Plan-green
Type: Modification
Spec: free-text intent for `DTR-10` / `DTR08-COMP-008` in
`Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
Classification: implementation-complete
Closure tier: host
Roadmap ID / wave: `DTR-10` / Wave 3 — Compatibility-led groups cleanup
Date: 2026-07-26

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 | Evidence Collector / Planner | `rotate_group_key_use_case.dart`, `rotate_and_distribute_group_key_use_case.dart`, `bridge_group_helpers.dart`, `go_bridge_client.dart`, Dart tests, Android/iOS/macOS handlers, `go-mknoon/bridge/bridge.go`, live key-epoch tests, runtime-root manifest, gate scripts, DTR roadmap | The project owner explicitly authorized removal of the obsolete Dart use case, refusal helper, Dart command mapping, and SUT-only Dart tests. Current source also proves that native handlers and the public fail-closed Go export still exist, so this plan retains them and every live key/data boundary. No implementation blocker remains inside that leaf-only scope. | Add causal source/dispatch tests, remove only the authorized Dart leaf, then close host preservation gates. |
| 2026-07-26 | TDD-plan sufficiency cross-auditor | Review-profile Graphify context, current Dart/native/Go sources, exact Flutter/Go selectors, C4 ownership, and runtime-root implementation | PASS WITH FIXES: the removal boundary and host-only tier are sound. Tighten final-tree inventory execution, whole-owned-Dart/raw-command census, the then-proposed command-count sentinel, current-doc ownership, graph refresh, and the pre-MethodChannel closure rationale. | Apply the narrow plan corrections below; implementation remains not started. |
| 2026-07-27 | Independent `$tdd-review` counterexample audit | Review-profile Graphify context; current Dart/native/Go sources; command registry; owned-Dart roots; runtime-root implementation; ignored gomobile artifacts; current C4/test inventory | Initial verdict `plan-fixes-required`: the registry has 68 entries rather than the claimed 53, the Go epoch regex ran zero tests, two owned-Dart locations and the native-method bypass token were omitted, generated artifact bytes were not guarded, two persistence-contract files were outside the protected baseline, the live-order prose was inaccurate, and the isolated index rebuilt from `HEAD` could not represent accepted predecessor deletions. The leaf-removal bet and host-only boundary remain confirmed. | Apply only those source-backed deltas, rerun all five lenses, then execute. |
| 2026-07-27 | Executor | Reviewed plan, scoped Dart leaf/tests/bookkeeping, retained live/native/Go boundaries, generated artifacts, and final host evidence | Implemented the reviewed leaf-only removal. Both causal REDs and mutation re-reds were observed; focused preservation, bindings, exact Go tests, isolated runtime roots, completeness, stabilized `groups`, isolated `feature-host-all`, strict analysis, protected scope, and diff hygiene are green. | Complete; leave Wave 3 aggregate `host-all` to the wave owner. |

## Problem And Evidence

- Behavior to improve: remove a test-only, permanently refusing Dart rotation
  route so future group work has one production key-rotation architecture.
- Impact: the obsolete route duplicates the name and shape of the security-
  critical live rotation flow, retains a raw Dart-to-native command mapping,
  and makes tests/documentation imply that two rotation implementations are
  supported.
- Owner authorization: in the 2026-07-26 free-text request, the current project
  owner explicitly chose removal of the old group-key rotation path while
  requiring preservation of the live generate/distribute/promote/update flow
  and all existing encryption keys and generations. That authorization is
  recorded as `DTR10-AUTH-05`, is limited to the in-scope Dart leaf, and does
  not authorize native/Go ABI or protocol retirement.
- Confirmed current gap:
  - `rotateGroupKey` at
    `lib/features/groups/application/rotate_group_key_use_case.dart:11` calls
    only `callGroupRotateKey`, then contains now-unreachable save logic.
  - `callGroupRotateKey` at
    `lib/core/bridge/bridge_group_helpers.dart:740` always returns
    `LEGACY_ROTATE_KEY_UNSUPPORTED` without invoking the bridge.
  - `_cmdMap` at `lib/core/bridge/go_bridge_client.dart:182` nevertheless
    exposes `group:rotateKey -> groupRotateKey`.
  - Current-source census finds the use case imported only by
    `rotate_group_key_use_case_test.dart` and the first test in
    `group_edge_cases_smoke_test.dart`; the helper is otherwise called only by
    its own test.
- Confirmed live replacement:
  - `rotateAndDistributeGroupKey` at
    `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart:174`
    restores the persisted epoch, generates the next key, distributes it,
    promotes it through `group:updateKey`, and persists it.
  - Production wires that flow for remote member removal at
    `lib/main.dart:3874-3895`.
  - `rotate_and_distribute_group_key_use_case_test.dart:334-392` locks
    restore/generate/distribute/promote/persist order, while
    `group_repository_impl_test.dart:988-1029` locks the current bounded
    generation-retention policy.
- Existing obsolete-only coverage:
  - `rotate_group_key_use_case_test.dart:46-65`;
  - `group_edge_cases_smoke_test.dart:33-123`;
  - `bridge_group_helpers_test.dart:1483-1507`;
  - the `group:rotateKey` rows in
    `go_bridge_client_test.dart:201` and `:3283`.
  These assertions validate only the route being removed and must be deleted
  or retargeted atomically; they are not migrated into the live flow.
- Missing coverage: no test currently requires the old Dart artifacts to be
  absent, and no test requires a raw `group:rotateKey` Dart request to fail
  before a native method invocation.
- Confirmed caller/compatibility floor:
  - package publishing is disabled at `pubspec.yaml:5`;
  - no other app-owned Dart importer/caller was found;
  - Android, iOS, and macOS still dispatch `groupRotateKey` at
    `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt:167`,
    `ios/Runner/GoBridge.swift:357`, and
    `macos/Runner/MainFlutterWindow.swift:155`;
  - `go-mknoon/bridge/bridge.go:2356-2388` still exports a fail-closed
    `GroupRotateKey`.
- Refuted findings:
  - Refuted: the legacy Dart use case performs a usable rotation. Its helper
    always refuses before bridge send.
  - Refuted: leaf authorization permits deleting the native/Go command. Native
    handlers and a generated/public Go boundary remain, and no release-floor
    evidence authorizes their retirement.
  - Refuted: the first `group_edge_cases_smoke_test.dart` case is a live
    replacement sentinel. It directly imports and invokes only the obsolete
    use case; the remaining smoke cases in that file are live and stay.
- Unresolved findings: the installed-client/native ABI floor for
  `groupRotateKey` is unknown. This does not block Dart leaf removal because the
  native handlers, generated bindings, Go export, and their fail-closed tests
  remain protected by tracked-source comparison, exact tests, binding
  verification, and a pre/post checksum of ignored generated artifacts. It
  does block widening this plan.
- Affected production, test, gate, inventory, and current-architecture files:
  - delete
    `lib/features/groups/application/rotate_group_key_use_case.dart` and
    `test/features/groups/application/rotate_group_key_use_case_test.dart`;
  - edit only the legacy helper in `bridge_group_helpers.dart`, the old
    `_cmdMap` row in `go_bridge_client.dart`, exact SUT-only fragments in
    `bridge_group_helpers_test.dart`, `go_bridge_client_test.dart`, and
    `group_edge_cases_smoke_test.dart`;
  - add
    `test/features/groups/application/legacy_group_key_rotation_removal_contract_test.dart`;
  - update only the matching `runtime_roots.json`, `GROUP_TESTS`, current C4
    claims, and the stale key-rotation row in
    `Test-Flight-Improv/codebase-test-inventory.md`; update the DTR-10
    registry/decision/`DTR08-COMP-008` disposition and the plan index without
    rewriting historical execution evidence.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `0c2b989ba6d96ada`; `freshness=current`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "remove obsolete rotate_group_key_use_case.dart rotateGroupKey callGroupRotateKey mapping while preserving rotate_and_distribute_group_key_use_case.dart generate distribute promote update key epochs" --profile tdd --budget 700`.
- Anchors:
  - `rotateGroupKey` ->
    `lib/features/groups/application/rotate_group_key_use_case.dart:11`;
  - `RotateGroupKeyOutcome` ->
    `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart:134`;
  - `callGroupRotateKey` ->
    `lib/core/bridge/bridge_group_helpers.dart:740`.
- Surfaced proof/gate files:
  `rotate_group_key_use_case_test.dart`,
  `rotate_and_distribute_group_key_use_case_test.dart`,
  `bridge_group_helpers_test.dart`, and `run_test_gates.sh`.
- Graph gaps requiring source search: the compact architecture graph did not
  surface `_cmdMap`, platform MethodChannel handlers, the Go export, the
  runtime-root manifest, current C4 claims, or exact raw-token callers. Those
  were verified by targeted current-source searches.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Delete the obsolete `rotate_group_key_use_case.dart`.
- Delete its dedicated unit test and only the `KE-014 failed legacy rotation`
  case/import from `group_edge_cases_smoke_test.dart`.
- Remove only `callGroupRotateKey` and its exact test group.
- Remove only `_cmdMap['group:rotateKey']`, its parameterized routing row, its
  known-command-list row, and repair that previously incomplete list from its
  53-command subset to the exact 67 retained commands. The current map has 68
  unique entries; this plan removes exactly one.
- Add a source-removal/caller-floor contract and a retired-command dispatch
  test.
- Remove the deleted source's runtime-root declaration, register the new
  feature contract in `GROUP_TESTS`, and correct only current C4 claims that
  present the Dart legacy route as supported.
- In current C4 documentation, remove only the Dart
  `rotate_group_key_use_case.dart`/`rotateGroupKey` use-case claims,
  `callGroupRotateKey` helper claims, and `GoBridgeClient._cmdMap`
  `group:rotateKey` row. Keep native/Go compatibility descriptions, including
  the platform `groupRotateKey` handlers, generated `BridgeGroupRotateKey`
  export, and Go `GroupRotateKey`, explicit and fail-closed. Remove the stale
  `handleGroupRotateKey`/`Node.GroupRotateKey` behavior claims because neither
  is the current implementation seam.
- Replace only the obsolete key-rotation entry in
  `codebase-test-inventory.md` with the live rotation suite plus the new removal
  contract.
- Record the leaf-only result in the current DTR-10 registry, decision ledger,
  `DTR08-COMP-008`, and `00-INDEX.md`; do not alter completed historical
  receipts.

Must preserve:

- Live restore/generate/distribute/promote/persist ordering ->
  `KE-013 restores persisted current epoch before generate after restart memory loss`
  and `promotes generated key only after distribution completes`.
- Existing persisted generations and the current bounded offline-replay window
  -> `PGC-013 saveKey retains bounded offline replay key window and prunes only outside it`.
  The protected baseline also locks
  `group_key_retention_policy.dart` and
  `secret_storage_references.dart`, so a self-consistent test/helper mutation
  cannot silently change the retained width or secure-storage address.
- Live helper and Dart-native routes for `group:generateNextKey` and
  `group:updateKey` -> their exact bridge-helper and GoBridgeClient routing
  tests.
- Production remote-removal wiring through `rotateAndDistributeGroupKey`,
  negative assertions that live remove-member behavior never calls
  `group:rotateKey`, and every remaining test in
  `group_edge_cases_smoke_test.dart`.
- Android/iOS/macOS `groupRotateKey` compatibility handlers, generated
  gomobile artifacts, the fail-closed Go `GroupRotateKey` export/tests, live Go
  generate/update behavior, and Go key-epoch ring semantics.
- Current documentation of the retained native/Go export and v3/key-epoch
  behavior. A documentation cleanup must not turn Dart mapping retirement into
  a claim that `GroupRotateKey` or its platform handlers were removed.

Hard `Do not`:

- Do not edit any database schema, migration, `group_keys` row, secure key
  material, repository retention rule, or pending rotation draft.
- Do not edit `rotate_and_distribute_group_key_use_case.dart`,
  `group_message_listener.dart`, its `main.dart` wiring, or live generate,
  distribute, promote, update, repair, and deferred-distribution paths.
- Do not remove or change Android/iOS/macOS handlers, Go
  `GroupRotateKey`/`GroupGenerateNextKey`/`GroupUpdateKey`, generated bindings,
  Go key-ring logic, or integration/device harnesses.
- Do not delete the `group:rotateKey` negative assertions in
  `remove_group_member_use_case_test.dart`; they guard the live replacement.
- Do not rewrite historical TDD records. Current C4 corrections must clearly
  distinguish the retired Dart route from the retained compatibility export.

Deferred / accepted difference:

- Native/Go `groupRotateKey` retirement -> owner Groups + Crypto + Release in a
  separate plan, because supported-client/native ABI evidence is unknown.
- Real device/crypto rerun -> not required for this leaf-only deletion because
  the real crypto/native/Go boundary is protected unchanged. Any edit under
  that boundary stops this plan and requires a new availability-bounded
  simulator/device contract.

Dependencies:

- The owner's explicit 2026-07-26 leaf-only authorization,
  `DTR10-AUTH-05`, is satisfied by this plan. DTR-10's other
  join/hydrate/leave/payload/cursor/security decisions are independent and
  must not enter this change.

Stop-if:

- Stop and replan if pre-edit census finds a non-test app-owned caller, a Dart
  export facade, a dynamically constructed supported raw command call, a
  package consumer, or a need to edit native/Go/generated/database files.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-281-01 | The obsolete Dart use case, refusal helper, imports/calls, SUT-only test fragments, runtime-root declaration, and current-architecture claims are absent while the explicit native/Go compatibility allowlist remains. | `test/features/groups/application/legacy_group_key_rotation_removal_contract_test.dart::DTR10-ROT-01 removes only the Dart legacy rotation leaf` | Host source-contract test / real repository tree | Causal RED on HEAD because the source, helper, imports, tests, manifest row, and C4 claims exist -> GREEN when only the authorized Dart artifacts are absent and the retained handler/export allowlist is exact. | Restore the deleted file, helper, import/call, manifest row, or stale current C4 claim; or remove a retained platform/Go allowlist token -> TC-281-01 red. | `flutter test --no-pub test/features/groups/application/legacy_group_key_rotation_removal_contract_test.dart --plain-name 'DTR10-ROT-01 removes only the Dart legacy rotation leaf'`; add path to `GROUP_TESTS` and verify through `./scripts/run_test_gates.sh groups`. |
| TC-281-02 | A raw Dart `group:rotateKey` request is retired locally and cannot invoke `groupRotateKey`; all 67 unique retained registry commands remain recognized. | `test/core/bridge/go_bridge_client_test.dart::{DTR10-ROT-02 retired group:rotateKey returns UNKNOWN_COMMAND without invoking native, all 67 commands are covered}` | Core host unit / mocked MethodChannel | Causal RED on HEAD because `_cmdMap` routes the request to `groupRotateKey` -> GREEN with `ok:false`, `UNKNOWN_COMMAND`, the command named in the safe error, `lastCall == null`, a unique 67-command expected set, and every retained command still known. | Restore `_cmdMap['group:rotateKey']` -> native invocation occurs and the causal selector re-reds; remove or misspell a retained command key -> the 67-command sentinel reds. | Two exact `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name ...` commands below; AUTO (`test/core/**` enters wave/final `host-all`), run directly for this plan. |
| TC-281-03 | The live flow restores the persisted epoch, generates, distributes, and promotes in that order; it persists the resulting key and publishes only after promotion. Current source persists before publishing, and the protected-source comparison freezes that unedited relation. | `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart::{KE-013 restores persisted current epoch before generate after restart memory loss, promotes generated key only after distribution completes}` | Feature application host / fake bridge plus in-memory repository | GREEN sentinel on HEAD -> remains GREEN after legacy deletion with epoch 7 restored before epoch 8 generation and no epoch 2 artifact, with epoch 2 absent until distribution completes, publication after promotion, and epoch 8 persisted at completion. | Remove persisted restore, generate before restore, promote before distribution, publish before promotion, skip `group:updateKey`, or skip `saveKey` -> one of the named sentinels reds; editing the live source for any unobserved reorder fails the protected comparison. | Two exact `flutter test --no-pub ... --plain-name ...` commands below; AUTO (`test/features/**`), plus protected comparison and `feature-host-all`. |
| TC-281-04 | Existing key material/generations and the current bounded replay-retention policy are untouched. | `test/features/groups/domain/repositories/group_repository_impl_test.dart::PGC-013 saveKey retains bounded offline replay key window and prunes only outside it` | Repository host / SQLite FFI repository fixture and secure-store fakes | GREEN sentinel on HEAD -> remains GREEN after deletion; generations 2-9 and their secure/shared mirrors remain while only the contractually out-of-window generation is pruned. | Change schema, delete/migrate key rows, reduce the retained window, or remove secure/shared generation material -> TC-281-04 red or protected-scope comparison fails. | Exact `flutter test --no-pub ... --plain-name ...`; AUTO (`test/features/**`), plus protected baseline comparison and `feature-host-all`. |
| TC-281-05 | Live Dart/native/Go generate/update and retained fail-closed compatibility boundaries remain intact. | `test/core/bridge/bridge_group_helpers_test.dart::{sends group:generateNextKey and returns key info, BB-013 group:updateKey timeout rethrows TimeoutException}`; `test/core/bridge/go_bridge_client_test.dart::{group:generateNextKey calls groupGenerateNextKey with payload JSON, group:updateKey calls groupUpdateKey with payload JSON}`; `go-mknoon/bridge/bridge_test.go::{TestGroupRotateKey_KE014FailsClosedWithoutMutatingStoredKeyState, TestST010GroupBridgeRejectsMalformedPayloadsWithoutPanicOrStateMutation, TestGroupUpdateKey_UpdatesStoredKey}`; `go-mknoon/node/pubsub_key_rotation_grace_test.go::{TestGK016GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace, TestGK017GroupTopicValidatorAcceptsHeldPreviousEpochRegardlessOfGraceDeadline, TestGK018GroupTopicValidatorAcceptsCurrentEpochAfterGraceDeadline, TestGK019UpdateGroupKeyJumpFromEpoch0To2PreservesOnlyEpoch0AsPrevious, TestGK020UpdateGroupKeySequentialRotationsKeepsOnlyEpoch1AsPrevious, TestGK021GroupTopicValidatorRejectsRemovalEpochPackageAndAcceptsReaddEpoch}`; gomobile verifier and protected-source comparison | Host Dart boundary + generated-binding verifier + Go host implementation tests (preservation only; no end-to-end crypto claim) | GREEN sentinel on HEAD -> same handlers/exports bind, legacy Go command remains fail-closed without mutation, live generate/update work, and held/current/re-add epochs retain their established semantics after the Dart deletion. | Remove a generated export/handler, make Go legacy rotation mutate, break generate/update, or alter current/held/re-add epoch selection -> verifier, protected comparison, or a named test red. | Exact Dart/Go/verifier commands below; Dart tests AUTO, Go/verifier manual exact registration. No device registration because no real boundary is changed. |

### Test Notes

- TC-281-01 must scan exact identifiers/imports with word boundaries rather
  than banning the text `group:rotateKey` globally. Live negative assertions,
  retained platform handlers, the Go compatibility export/tests, and historical
  plans legitimately contain that string.
- TC-281-01 must fail closed on source-walk errors and must exclude only itself
  from its Dart token scan. Its retained compatibility allowlist is the three
  platform handlers plus `go-mknoon/bridge/bridge.go` and its exact Go tests.
- Its caller census covers every existing owned Dart root (`lib`, `test`,
  `integration_test`, `test_driver`, `scripts`, `tool`, and `packages`) plus
  top-level Dart files, not only `lib/test`. A separate production-only
  quoted-token census requires zero `group:rotateKey` and direct native-method
  `groupRotateKey` occurrences under `lib` after `_cmdMap` removal; test-side
  negative and retirement assertions remain allowed.
- TC-281-02 extends the existing unknown-command fixture and asserts the method
  channel was not called; an `UNKNOWN_COMMAND` assertion without `lastCall ==
  null` is insufficient.
- TC-281-02 expands the old 53-item subset with the four `migration.*`
  commands, two `relay:presence_*` commands, `peer:ping`, `lan:peer_found`,
  `inbox:register_wake_tokens`, `media:lan_send`, `group:sendReliable`, and
  four `bg:*` commands, removes only `group:rotateKey`, and asserts both list
  length and set length are 67 before routing them.
- The C4 portion of TC-281-01 is identity-aware: it removes Dart use-case,
  helper, and `_cmdMap` claims while positively requiring the retained native/Go
  compatibility descriptions. A global C4 token ban is forbidden.

## Implementation Steps

1. Snapshot `git status --short`. Capture the pre-existing `git diff HEAD` for
   every protected native/Go/database/live-rotation path so later comparison
   distinguishes concurrent user work from this plan.
2. Add TC-281-01 and TC-281-02. Add only TC-281-01 to `GROUP_TESTS`; TC-281-02
   remains auto-registered under `test/core/**` and is run directly.
3. Run both causal selectors before production edits. Record non-zero status:
   TC-281-01 must report the present legacy Dart artifacts; TC-281-02 must show
   that `groupRotateKey` was invoked instead of local unknown-command refusal.
   Any other failure is not the expected RED.
4. Delete `rotate_group_key_use_case.dart` and its dedicated test. Remove only
   the first `KE-014 failed legacy rotation` test and now-unused import from
   `group_edge_cases_smoke_test.dart`; preserve the rest of that file.
5. Remove `callGroupRotateKey` and only its exact test group. Remove only the
   `group:rotateKey` `_cmdMap` row and its two command-inventory entries. Repair
   the old 53-item subset by adding the 15 retained commands it omitted, then
   assert the post-removal list and set both contain exactly 67. Do not edit
   adjacent generate/update code.
6. Remove the deleted source's `runtime_roots.json` declaration. Correct only
   current C4 file/symbol/API claims so they identify
   `rotateAndDistributeGroupKey` as the live Dart flow and, where mentioned,
   the retained platform/generated/Go legacy export as
   compatibility-only/fail-closed. Correct the one stale key-rotation entry in
   `codebase-test-inventory.md`. Update the current DTR-10 registry, decision
   ledger, `DTR08-COMP-008`, and plan index to record only this leaf
   disposition.
7. Run focused GREEN, representative mutation re-red for TC-281-01 and
   TC-281-02, exact preservation tests, bindings/Go proof, runtime inventory,
   completeness, `groups`, and `feature-host-all`; refresh the architecture
   graph incrementally once after the coherent app-owned change.
8. Compare protected paths to their pre-edit baseline. Stop rather than absorb
   any native/Go/database/live-rotation delta.

## Risks And Blind Spots

- A hidden raw Dart caller could depend on the mapped command -> TC-281-01 uses
  a fail-closed exact-token/caller census; TC-281-02 deliberately defines the
  post-removal raw-command result. A separate `groupRotateKey` production-Dart
  census rejects a direct `MethodChannel.invokeMethod` bypass. Stop if a
  supported caller appears.
- Similar names could cause deletion of the live
  `rotateGroupKeyAfterRemoteRemoval` callback -> exact word-boundary contract,
  live application sentinels, and protected-source comparison guard it.
- Persisted epochs could be mistaken for dead artifacts -> TC-281-04 and the
  database/repository protected baseline forbid data/schema/retention edits.
- Native/generated/Go ABI compatibility could be retired accidentally ->
  TC-281-05 retains handlers/export, verifies generated bindings, and exercises
  the fail-closed Go command plus live epoch logic.
- A production bridge-registry edit could be overclaimed as device/native
  proof -> TC-281-02 causally exercises the complete changed behavior before the
  MethodChannel and proves `lastCall == null`; native/Go bytes are protected and
  tested only as unchanged preservation boundaries. No device result is
  claimed.
- Lifecycle / derived-state durability: TC-281-03's restart-memory-loss case
  proves reconstruction from persisted current key; no lifecycle code changes.
- Sibling-surface consistency: TC-281-03 covers the live rotation path and the
  full `groups` gate retains admin-removal, voluntary-leave, remote-removal,
  repair, send, and receive surfaces.
- Destructive-action side effects: TC-281-01 proves only named files/fragments
  disappear; TC-281-04 and protected comparisons prove keys/data stay.
- Invariant re-verification under new transitions: N/A — no new runtime
  transition is introduced; raw legacy dispatch is removed before native, and
  the live transition is unchanged.

## Gate Cadence

- Per-plan closure: two causal selectors, exact live rotation/key/native-Go
  sentinels, the isolated-final-tree `runtime-roots` gate,
  `completeness-check`, the curated `groups` gate, justified
  `feature-host-all`, binding verification, incremental Graphify refresh,
  strict analysis, and diff/protected-scope hygiene.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Wave 3 DTR-10 group
  legacy-cleanup batch is complete, and once at final DTR rollout/release
  closure.
- Shared tests outside feature/core globs: Go bridge/node tests and gomobile
  verification run by the exact direct commands below.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes.
git status --short

# Capture the protected baseline before edits. Both commands must exit 0.
DTR10_ROT_PROTECTED_PATCH_BASELINE="$(mktemp)"
DTR10_ROT_PROTECTED_STATUS_BASELINE="$(mktemp)"
git diff --no-ext-diff HEAD -- \
  android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt \
  ios/Runner/GoBridge.swift \
  macos/Runner/MainFlutterWindow.swift \
  go-mknoon \
  lib/main.dart \
  lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/domain/models/group_key_retention_policy.dart \
  lib/features/groups/domain/repositories \
  lib/core/secure_storage/secret_storage_references.dart \
  lib/core/database \
  integration_test \
  >"$DTR10_ROT_PROTECTED_PATCH_BASELINE"
git status --short -- \
  android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt \
  ios/Runner/GoBridge.swift \
  macos/Runner/MainFlutterWindow.swift \
  go-mknoon \
  lib/main.dart \
  lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/domain/models/group_key_retention_policy.dart \
  lib/features/groups/domain/repositories \
  lib/core/secure_storage/secret_storage_references.dart \
  lib/core/database \
  integration_test \
  >"$DTR10_ROT_PROTECTED_STATUS_BASELINE"

# Git ignores generated gomobile artifacts, so tracked diff/status cannot prove
# that their bytes stayed unchanged. Capture a deterministic file/link/tree
# manifest before edits. Missing artifacts fail closed.
DTR10_ROT_GENERATED_BASELINE="$(mktemp)"
dtr10_rot_generated_artifact_manifest() {
  local artifact
  for artifact in \
    android/app/libs/GoMknoon.aar \
    android/app/libs/GoMknoon-sources.jar \
    android/app/libs/GoMknoon.inputs.sha256 \
    ios/Runner/GoMknoon.xcframework \
    ios/Runner/GoMknoon.inputs.sha256 \
    macos/Runner/GoMknoon.xcframework
  do
    test -e "$artifact" || return 1
  done

  find \
    android/app/libs/GoMknoon.aar \
    android/app/libs/GoMknoon-sources.jar \
    android/app/libs/GoMknoon.inputs.sha256 \
    ios/Runner/GoMknoon.xcframework \
    ios/Runner/GoMknoon.inputs.sha256 \
    macos/Runner/GoMknoon.xcframework \
    \( -type d -o -type f -o -type l \) -print |
    LC_ALL=C sort |
    while IFS= read -r artifact; do
      if test -L "$artifact"; then
        printf 'link  %s -> %s\n' "$artifact" "$(readlink "$artifact")"
      elif test -d "$artifact"; then
        printf 'dir   %s\n' "$artifact"
      else
        shasum -a 256 "$artifact"
      fi
    done
}
dtr10_rot_generated_artifact_manifest \
  >"$DTR10_ROT_GENERATED_BASELINE"
test -s "$DTR10_ROT_GENERATED_BASELINE"

# Causal RED 1 before production edits: expect non-zero because authorized
# legacy Dart artifacts still exist.
flutter test --no-pub \
  test/features/groups/application/legacy_group_key_rotation_removal_contract_test.dart \
  --plain-name 'DTR10-ROT-01 removes only the Dart legacy rotation leaf'

# Causal RED 2 before mapping edit: expect non-zero because HEAD invokes
# groupRotateKey rather than returning UNKNOWN_COMMAND locally.
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart \
  --plain-name 'DTR10-ROT-02 retired group:rotateKey returns UNKNOWN_COMMAND without invoking native'

# Focused GREEN: both commands must exit 0 with zero failed tests.
flutter test --no-pub \
  test/features/groups/application/legacy_group_key_rotation_removal_contract_test.dart
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart \
  --plain-name 'DTR10-ROT-02 retired group:rotateKey returns UNKNOWN_COMMAND without invoking native'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart \
  --plain-name 'all 67 commands are covered'

# Fail-closed whole-owned-Dart token census. rg status 1 with an empty report
# is the only successful no-match outcome; status >1 is operational failure.
DTR10_ROT_CENSUS_REPORT="$(mktemp)"
DTR10_ROT_CENSUS_STATUS=0
rg -n \
  --glob '*.dart' \
  -e 'rotate_group_key_use_case\.dart' \
  -e '\bcallGroupRotateKey\b' \
  -e '\brotateGroupKey\b' \
  lib test integration_test test_driver scripts tool packages \
  ambient_background_standalone.dart \
  --glob '!test/features/groups/application/legacy_group_key_rotation_removal_contract_test.dart' \
  >"$DTR10_ROT_CENSUS_REPORT" || DTR10_ROT_CENSUS_STATUS=$?
test "$DTR10_ROT_CENSUS_STATUS" -eq 1
test ! -s "$DTR10_ROT_CENSUS_REPORT"

# Neither the retired raw command nor a direct native-method bypass may remain
# in production Dart. Test-side negative/retirement assertions are outside it.
DTR10_ROT_RAW_COMMAND_REPORT="$(mktemp)"
DTR10_ROT_RAW_COMMAND_STATUS=0
rg -n --glob '*.dart' \
  -e "['\"]group:rotateKey['\"]" \
  -e "['\"]groupRotateKey['\"]" \
  lib \
  >"$DTR10_ROT_RAW_COMMAND_REPORT" || DTR10_ROT_RAW_COMMAND_STATUS=$?
test "$DTR10_ROT_RAW_COMMAND_STATUS" -eq 1
test ! -s "$DTR10_ROT_RAW_COMMAND_REPORT"

# Live restore/generate/distribute/promote/persist preservation.
flutter test --no-pub \
  test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart \
  --plain-name 'KE-013 restores persisted current epoch before generate after restart memory loss'
flutter test --no-pub \
  test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart \
  --plain-name 'promotes generated key only after distribution completes'
flutter test --no-pub \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  --plain-name 'PGC-013 saveKey retains bounded offline replay key window and prunes only outside it'

# Live Dart bridge helpers and mappings remain.
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart \
  --plain-name 'sends group:generateNextKey and returns key info'
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart \
  --plain-name 'BB-013 group:updateKey timeout rethrows TimeoutException'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart \
  --plain-name 'group:generateNextKey calls groupGenerateNextKey with payload JSON'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart \
  --plain-name 'group:updateKey calls groupUpdateKey with payload JSON'

# Retained native/generated/Go compatibility and live key epochs.
./scripts/verify_gomobile_bindings.sh all
(
  cd go-mknoon
  GOTOOLCHAIN=go1.25.0 go test ./bridge \
    -run '^(TestGroupRotateKey_KE014FailsClosedWithoutMutatingStoredKeyState|TestST010GroupBridgeRejectsMalformedPayloadsWithoutPanicOrStateMutation|TestGroupUpdateKey_UpdatesStoredKey)$' \
    -count=1
)
(
  cd go-mknoon
  GOTOOLCHAIN=go1.25.0 go test ./node \
    -run '^(TestGK016GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace|TestGK017GroupTopicValidatorAcceptsHeldPreviousEpochRegardlessOfGraceDeadline|TestGK018GroupTopicValidatorAcceptsCurrentEpochAfterGraceDeadline|TestGK019UpdateGroupKeyJumpFromEpoch0To2PreservesOnlyEpoch0AsPrevious|TestGK020UpdateGroupKeySequentialRotationsKeepsOnlyEpoch1AsPrevious|TestGK021GroupTopicValidatorRejectsRemovalEpochPackageAndAcceptsReaddEpoch)$' \
    -count=1
)

# Real final-tree runtime-root gate. Preserve the user's staged Plan-286 slice
# by copying the real index, then stage current tracked lib deletions in only
# the copy so accepted Plans 277-280/286 are not reconstructed as phantom
# HEAD files. The exact pre-existing untracked Android harness is protected and
# unrelated to this host leaf, so hide only that path from this plan-isolated
# inventory instead of editing or registering it here.
DTR10_ROT_INDEX_DIR="$(
  mktemp -d "${TMPDIR:-/tmp}/dtr10-rotation-index.XXXXXX"
)"
trap 'rm -r -- "${DTR10_ROT_INDEX_DIR:?}"' EXIT
cp "$(git rev-parse --git-path index)" "$DTR10_ROT_INDEX_DIR/index"
printf '%s\n' \
  '/integration_test/group_multi_party_device_real_android_harness.dart' \
  >"$DTR10_ROT_INDEX_DIR/excludes"
GIT_INDEX_FILE="$DTR10_ROT_INDEX_DIR/index" git add -A -- \
  lib/features/groups/application/rotate_group_key_use_case.dart \
  lib/core/bridge/bridge_group_helpers.dart \
  lib/core/bridge/go_bridge_client.dart \
  test/features/groups/application/rotate_group_key_use_case_test.dart \
  test/features/groups/application/legacy_group_key_rotation_removal_contract_test.dart \
  test/features/groups/integration/group_edge_cases_smoke_test.dart \
  test/core/bridge/bridge_group_helpers_test.dart \
  test/core/bridge/go_bridge_client_test.dart \
  tool/runtime_roots/runtime_roots.json \
  scripts/run_test_gates.sh \
  C4/file-structure.md \
  C4/code.md \
  C4/components.md \
  C4/infrastructure.md \
  Test-Flight-Improv/codebase-test-inventory.md \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md \
  Test-Flight-Improv/00-INDEX.md
GIT_INDEX_FILE="$DTR10_ROT_INDEX_DIR/index" git add -u -- lib
GIT_CONFIG_COUNT=1 \
GIT_CONFIG_KEY_0=core.excludesFile \
GIT_CONFIG_VALUE_0="$DTR10_ROT_INDEX_DIR/excludes" \
GIT_INDEX_FILE="$DTR10_ROT_INDEX_DIR/index" \
  ./scripts/run_test_gates.sh runtime-roots

# Curated feature lane and changed feature surface.
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene and required architecture-graph refresh.
./scripts/check_flutter_analyze_strict.sh
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check

# Protected paths must be byte/status-identical to their pre-edit baseline.
DTR10_ROT_PROTECTED_PATCH_CURRENT="$(mktemp)"
DTR10_ROT_PROTECTED_STATUS_CURRENT="$(mktemp)"
git diff --no-ext-diff HEAD -- \
  android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt \
  ios/Runner/GoBridge.swift \
  macos/Runner/MainFlutterWindow.swift \
  go-mknoon \
  lib/main.dart \
  lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/domain/models/group_key_retention_policy.dart \
  lib/features/groups/domain/repositories \
  lib/core/secure_storage/secret_storage_references.dart \
  lib/core/database \
  integration_test \
  >"$DTR10_ROT_PROTECTED_PATCH_CURRENT"
git status --short -- \
  android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt \
  ios/Runner/GoBridge.swift \
  macos/Runner/MainFlutterWindow.swift \
  go-mknoon \
  lib/main.dart \
  lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/domain/models/group_key_retention_policy.dart \
  lib/features/groups/domain/repositories \
  lib/core/secure_storage/secret_storage_references.dart \
  lib/core/database \
  integration_test \
  >"$DTR10_ROT_PROTECTED_STATUS_CURRENT"
cmp "$DTR10_ROT_PROTECTED_PATCH_BASELINE" \
  "$DTR10_ROT_PROTECTED_PATCH_CURRENT"
cmp "$DTR10_ROT_PROTECTED_STATUS_BASELINE" \
  "$DTR10_ROT_PROTECTED_STATUS_CURRENT"
DTR10_ROT_GENERATED_CURRENT="$(mktemp)"
dtr10_rot_generated_artifact_manifest \
  >"$DTR10_ROT_GENERATED_CURRENT"
cmp "$DTR10_ROT_GENERATED_BASELINE" \
  "$DTR10_ROT_GENERATED_CURRENT"
```

The executor must capture and compare a pre-edit `git diff HEAD` for these
protected paths; the post-edit bytes must match that baseline exactly:

```text
android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt
ios/Runner/GoBridge.swift
macos/Runner/MainFlutterWindow.swift
go-mknoon/
lib/main.dart
lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart
lib/features/groups/application/group_message_listener.dart
lib/features/groups/domain/models/group_key_retention_policy.dart
lib/features/groups/domain/repositories/
lib/core/secure_storage/secret_storage_references.dart
lib/core/database/
integration_test/
```

The ignored Android AAR/source/hash and iOS/macOS xcframework trees are
protected separately by the pre/post SHA-256 manifest in the literal gate.

## Execution Interpretation And Done Criteria

- Expected RED:
  - TC-281-01 fails only because at least one authorized legacy Dart artifact
    or current C4 claim is present.
  - TC-281-02 fails only because `_cmdMap` invokes `groupRotateKey`.
- Green sentinels: TC-281-03 through TC-281-05.
- Pre-existing dirty tree / known failure: execution records the live
  `git status --short` and protected baseline; unrelated changes are preserved.
- Environment blocker: none expected; host Flutter, Go 1.25 toolchain, and
  checked-in binding artifacts are sufficient. A missing binding artifact is
  an environment blocker, not permission to regenerate or edit it in this
  plan.
- Scope drift: any required native/Go/generated/database/live-rotation change,
  or a supported non-test caller, blocks completion and requires a new plan.

- [x] Every behavior has its named automated test or exact source/binding proof.
- [x] Both causal REDs, focused GREEN, and representative mutation re-reds are
      recorded during execution.
- [x] Live ordering, persisted-generation, Dart bridge, native/Go, `groups`,
      and `feature-host-all` sentinels pass with zero failures.
- [x] TC-281-01 is registered in `GROUP_TESTS`; TC-281-02 remains AUTO under
      `test/core/**` and is run directly.
- [x] The unique 67-command inventory sentinel passes, and the
      whole-owned-Dart plus production raw/native-command censuses are empty
      with exact `rg` status `1`.
- [x] No migration, device, relay, or integration-test change was introduced.
- [x] Strict analysis has no new issues; `git diff --check` is clean.
- [x] The isolated-index runtime-root gate passes without changing the user's
      index, and the architecture graph is refreshed incrementally once.
- [x] Protected paths match the pre-edit baseline and the Scope Contract And
      Guard is respected; the ignored generated-artifact checksum manifest is
      also byte-identical.

## Handoff

- Plan path:
  `Test-Flight-Improv/281-legacy-group-key-rotation-path-removal-tdd-plan.md`.
- Classification / status: `implementation-complete` / `Plan-green`.
- Test Contract: five rows; two causal host REDs and three preservation groups.
- Tiers / fixtures: host-only; source tree, mocked MethodChannel, in-memory
  application repository, existing repository/database fixture, real Go unit
  implementation tests used as preservation sentinels, and checked-in gomobile
  binding verifier. No end-to-end crypto claim is made.
- First causal RED command:
  `flutter test --no-pub test/features/groups/application/legacy_group_key_rotation_removal_contract_test.dart --plain-name 'DTR10-ROT-01 removes only the Dart legacy rotation leaf'`.
- Preservation command:
  `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-013 restores persisted current epoch before generate after restart memory loss'`.
- Manual registration: TC-281-01 is registered in `GROUP_TESTS`; Go tests and
  binding verification ran as direct exact commands. TC-281-02 remains AUTO
  under `test/core/**` and also ran directly.
- Migration: none; schema/key-row/retention changes are forbidden.
- Boundary closure: host-only. The changed behavior ends in Dart before the
  MethodChannel and is causally locked by `lastCall == null`; real
  native/Go/crypto files are unchanged and protected. Editing those retained
  boundaries requires a separate availability-bounded simulator/device plan.
- Gate cadence: exact tests + isolated-final-tree `runtime-roots` +
  completeness + `groups` + justified `feature-host-all` + incremental
  Graphify refresh; Wave 3 DTR-10 batch and final DTR release each own one full
  `host-all`.
- Execution result: `runtime-roots` passed 20 tests with trustworthy inventory
  and no drift; completeness classified 1,348/1,348 test files; the stabilized
  `groups` host retry passed 3,235 tests plus all exact Go tails; the isolated
  815-path `feature-host-all` replay passed 8,485 tests with one expected skip;
  strict analysis reported no issues.
- Final handoff replay: TC-281-01, TC-281-02, and the unique 67-command
  inventory selector all passed on the finished tree; the owned-Dart and
  production raw/native-bypass censuses remained empty with exact `rg` status
  `1`, `git diff --check` remained clean, and no Plan 281 build cache remained
  in the repository.
- Scope integrity: the protected patch
  (`5283e5463c088fab82198c559873d82e293e094f261f5cd32b0ce70a2d37ef9`),
  protected status
  (`1f0859745598102c76d2dfc95c740dadefb83568e7dbbee2283174890c1c93a1`),
  and generated-artifact manifest
  (`32b27fd768d9d1d3fee4ec5a60d267b89bed9eafc49761de0fc0a14923ac37dc`)
  SHA-256 values exactly match their pre-edit baselines. The final independent
  scope audit found no blocking issue, stale active Plan 281 status, or
  unintended native/Go/live-rotation change.
- Confirmed: old Dart path is test-only/refusing; live
  `rotateAndDistributeGroupKey` is production-wired; native/Go compatibility
  route exists and remains protected under the limits of `DTR10-AUTH-05`.
- Refuted: authorization to remove the Dart leaf is not authorization to remove
  native/Go exports or persisted epochs.
- Unresolved evidence: supported-client/native ABI retirement floor; deferred
  to Groups + Crypto + Release and not blocking the leaf-only plan.
- The 2026-07-27 independent `$tdd-review` was completed before
  implementation. Its required bounded deltas are incorporated below.

## Reviewer Findings

- Review type/date: TDD-plan sufficiency cross-audit, 2026-07-26.
- Review-time verdict: PASS after narrow corrections; the plan was
  `execution-ready` and is now superseded by the `Plan-green` execution result.
- Confirmed from current source:
  - the removed helper refuses locally and sends no MethodChannel request;
  - the live `rotateAndDistributeGroupKey` production flow and persisted
    generation-retention policy are independent;
  - Android/iOS/macOS handlers and Go `GroupRotateKey` remain compatibility
    surfaces and must not be removed in this plan.
- Selector verification: both live Dart ordering selectors, the repository
  retention selector, four Dart bridge/mapping selectors, all three Go bridge
  selectors, and all six Go epoch selectors passed on the planning tree.
- Corrections applied:
  - added the then-proposed post-edit command-count sentinel, later corrected
    by the independent audit below from an incomplete 52-command claim to the
    full 67-command retained set;
  - expanded the caller census to all existing owned Dart roots and added a
    production raw-command census;
  - replaced the unusable ordinary runtime-root command with an isolated
    final-tree index;
  - anchored current C4/roadmap ownership so Dart retirement cannot erase
    retained native/Go compatibility documentation;
  - added the required incremental Graphify refresh and made the host-only
    pre-MethodChannel closure claim explicit.
- Remaining uncertainty: supported installed-client/native ABI retirement is
  still unknown and intentionally deferred; it does not block this Dart-only
  leaf removal.

### Independent counterexample audit — 2026-07-27

- Initial verdict: `plan-fixes-required`; disposition `apply-plan-fixes`.
- Core bet: confirmed. The obsolete Dart use case/helper remain test-only and
  fail closed before native dispatch; the live flow and retained native/Go
  boundary are independent.
- Required corrections applied in place:
  - replaced the false 52-command contract with the full unique 67-command
    post-removal set;
  - replaced the zero-test Go epoch regex with the exact six full names;
  - expanded owned-Dart/raw bypass coverage to `scripts`, top-level Dart, and
    direct `groupRotateKey` invocation tokens;
  - added the actual retention-policy and secure-reference files to protected
    comparison;
  - added deterministic checksums for ignored gomobile artifacts;
  - corrected the live-order claim and the stale current test-inventory row;
  - rebuilt the runtime proof from the copied current index plus accepted
    predecessor deletions instead of reconstructing the shared tree from
    `HEAD`;
  - staged the exact Plan 281 paths before the copied-index `git add -u -- lib`
    step so the already-deleted source remains a valid exact pathspec.
- Five-lens rerun: L1 `clear`; L2 `clear`; L3 `clear`; L4 `clear`; L5
  `clear`. Blind-spot hits B-2/B-3/B-4/B-8/B-9 are closed by those deltas;
  B-1/B-5/B-6/B-10 are N/A because no persisted format, migration, destructive
  state transition, device behavior, or cross-version ABI is changed.
- Final verdict after revision: `ready`; disposition `execute`. The unknown
  installed-client/native ABI retirement floor remains explicitly deferred and
  does not block this Dart-only leaf.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-27 | Review closure | Plan 281 plus current Dart/native/Go/test/gate evidence | Five-lens rerun: L1-L5 `clear`; final verdict `ready`, disposition `execute` | Corrected command count 68 -> 67, zero-test Go regex, owned-Dart/bypass censuses, protected sources/artifacts, live-order/C4 claims, and copied-index proof | No review blocker | Execute leaf-only contract |
| 2026-07-27 | Causal implementation | Obsolete Dart use case/helper/map, SUT-only fragments, removal contract, runtime/gate/C4/inventory bookkeeping | Both causal selectors RED before production edits; restoring either map row or source made its selector RED again | Retired source/test absent; `group:rotateKey` returns `UNKNOWN_COMMAND` before native; all 67 retained commands recognized | Native/Go/live rotation remained outside the edit boundary | Run preservation and family gates |
| 2026-07-27 | Preservation and family gates | Live Dart rotation/repository/bridge tests, bindings, Go bridge/node, runtime roots, groups, feature family | Exact sentinels, bindings, 3 Go bridge tests, 6 Go epoch tests, 20 runtime-root tests, 1,348/1,348 completeness, 3,235-test groups retry, and 8,485-pass/1-skip feature replay green | The initial shared feature attempts were invalidated by another task's removed temporary native-assets path; all four affected selectors and the isolated 815-path replay passed from a dedicated build directory | No product/code blocker; environment race closed | Close hygiene and scope |
| 2026-07-27 | Closure | Final affected smoke file, analyzer, graph, protected tracked/generated boundaries | Smoke file 8/8; strict analysis no issues; incremental Graphify refresh completed; protected patch/status and generated manifest unchanged | Analyzer-led removal of the now-orphaned local `waitUntil` test helper was the only post-family test-only cleanup | Plan-green; Wave 3 aggregate `host-all` remains deferred by cadence | Complete |
| 2026-07-27 | Final handoff audit | Final causal/registry selectors, owned-Dart and production-bypass censuses, protected manifests, plan/roadmap/index state | TC-281-01, TC-281-02, and all-67 replay passed; both censuses returned empty/status 1; protected patch/status/generated hashes matched; `git diff --check` clean | Independent read-only audit found no blocker, stale active Plan 281 state, or unintended native/Go/live-rotation edit | Plan-green remains final; no additional Plan 281 work | Complete |
