# 280 - Superseded leave-and-delete-local-history coordinator removal

Status: Plan-green
Type: Modification
Spec: free-text intent for `DTR-10` / the superseded “leave and delete local
history” coordinator in
`Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
Classification: implementation-complete
Closure tier: host
Roadmap ID / wave: `DTR-10` / Wave 3 — Compatibility-led groups cleanup
Date: 2026-07-26

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 | Evidence Collector / Planner | `leave_group_and_delete_local_history_use_case.dart`, its direct tests and legacy UI fixture, `group_exit_intent_{coordinator,runner}.dart`, production wiring, v103/v104 repositories/migrations, lifecycle recovery, diagnostics, UI callers, bridge/native tests, runtime-root inventory, gate/discovery scripts | Current source proves the old coordinator has no production importer. The live app uses the durable intent coordinator/runner/recovery graph, but 11 valuable UI tests still install the old implementation behind the new sink. Migrate those tests to one production-shaped durable fixture before deleting the old coordinator and only its SUT-exclusive tests. | Add causal retirement contract, generalize the durable fixture, migrate valuable tests, delete the obsolete island, and close focused host preservation. |
| 2026-07-26 | Independent TDD Review | Current coordinator/runner mapping, both legacy native-failure selectors, rapid-duplicate coverage, production cleanup, migration/device proofs, platform handlers, and gate registration | `plan-fixes-required`: the removal bet is confirmed, but both native-failure selectors asserted obsolete UI semantics; rapid fresh-request dedupe lacked a modern replacement; TC-280-05 overclaimed byte/all-row proof; platform handler preservation and the production SQL-last sentinel were unnamed; device and feature-family campaigns were not causal to this hard-scoped removal. | Apply only these source-backed contract corrections, rerun the five review lenses, then execute. |
| 2026-07-26 | Independent TDD Review / Recheck | Updated scope guard, TC-280-01 through TC-280-07, gate cadence, host/device boundary, execution sequence, and done criteria | `ready`: all five lenses are now clear. The plan keeps the confirmed removal boundary, corrects both stale native-failure contracts, adds simultaneous-fresh-request and production-cleanup sentinels, narrows migration claims to exact seeded rows and protected hashes, preserves platform handlers, and defers unaffected device/full-host campaigns to their aggregate owners. | Execute the causal RED, production-shaped fixture migration, exact retirement, and focused preservation gates. |
| 2026-07-26 | Implementation Counterexample Audit | Generalized harness, migrated wired selectors, rapid-request sentinel, retirement contract, current index, and Plan 286 closure | The removal remained correct, but the first implementation still let the runner use the detached surface fake, did not force duplicate-request overlap, checked seeded history only in the fake, allowed projection to overwrite a committed result/newer membership, omitted owned Dart roots from the residue guard, and did not state the already-Plan-green Plan 286 land-order dependency. | Harden only those causal boundaries, use an isolated copied index for the shared runtime-root deletion set, then rerun focused closure. |

## Authorization Receipt

- Receipt: `DTR10-AUTH-04`.
- Authority/date: current authenticated project owner, 2026-07-26.
- Authorized action: prove that the modern group-exit system replaces
  `LeaveGroupAndDeleteLocalHistoryUseCase`, then remove that coordinator and
  only its obsolete tests.
- Guard: the receipt does not authorize deleting live UI behavior, durable
  intent/diagnostic records, native leave, database state, or tests that still
  prove observable behavior through a production-shaped boundary.

## Problem And Evidence

This section preserves the pre-implementation baseline that justified the
retirement. Current-tree results are recorded under *Execution Progress*.

- Behavior to improve: remove a second, test-only active-group exit coordinator
  so production and tests describe one durable leave architecture.
- Impact: the old class keeps in-memory `_inFlight` and
  `_nativeLeaveCommittedGroups` state, manually snapshots and rolls back key and
  timeline artifacts, and presents behavior that production no longer runs.
  Tests installed through that class can therefore pass while the actual
  durable coordinator/runner is broken.
- Confirmed root cause/current gap:
  - `LeaveGroupAndDeleteLocalHistoryUseCase` at
    `lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart:48`
    has no importer under `lib/`.
  - Its only runtime-root classification is the test/integration explained-root
    declaration at `tool/runtime_roots/runtime_roots.json:655`.
  - `test/shared/helpers/legacy_group_exit_coordinator_fixture.dart:27`
    constructs the old class and adapts its transient status to the modern
    process-wide sink.
  - `group_exit_actions_test.dart:2035-2741` contains eleven direct SUT blocks
    for the obsolete class.
- Confirmed production replacement:
  - `lib/main.dart:4027-4315` constructs
    `GroupExitIntentRepositoryImpl`, `GroupExitIntentRunner`,
    `GroupExitIntentCoordinator`, diagnostic decoration, action/access sinks,
    and recovery callbacks.
  - The runner performs stable signed-notice handoff, bounded phase advancement,
    typed native leave, membership-generation-safe cleanup, and durable retry.
  - startup, rejoin, resume, and manual retry converge on the same processor;
    `handle_app_resumed_group_recovery_test.dart` verifies drain-before-process
    ordering and error isolation.
- Existing replacement coverage:
  - `group_exit_intent_coordinator_test.dart` covers unavailable authority,
    exact last-admin policy, queued role work, durable enqueue, duplicate
    suppression, retry, rejoin identity, and mandatory presentation sinks.
  - `group_exit_intent_runner_test.dart` covers stable notice identity,
    atomic handoff, restart at every phase, native ambiguity, bounded
    diagnostics, atomic/membership-safe cleanup, and shared recovery.
  - v103/v104 migration tests and the two SQLCipher proofs cover the durable
    intent and release-diagnostic storage boundaries.
  - Dart bridge and Go tests preserve the actual `group:leave` native command.
- Valuable coverage still coupled to the obsolete fixture:
  - Group Info: `GCA-009`, sole-admin refusal, the corrected `BB-010` and
    `GCA-010` durable-retry semantics, deferred writer leave, multi-admin
    rotation/leave, and durable leave-timeline order.
  - Orbit: the ordinary-leave control, first sole-admin recovery, preservation
    of other groups/friends, and both 1:1 threads in the user-B scenario.
  These tests must be migrated, not deleted.
- Two additional legacy-fixture consumers existed on clean `HEAD` in
  `group_list_wired_test.dart`; Plan 286 has already retired that unreachable
  Group List island under its separate authorization. The 11-call migration
  count is therefore correct only after Plan 286 and establishes a required
  land order rather than permission to absorb those two tests into this plan.
- Missing coverage: no causal test currently requires the old source, legacy
  fixture, direct SUT import, runtime-root declaration, and obsolete flow-event
  inventory rows to disappear while retaining the modern graph and all valuable
  UI selectors.
- Refuted findings:
  - Refuted: the old coordinator is production fallback. There is no `lib/`
    importer or production construction.
  - Refuted: all tests importing it are obsolete. The eleven direct SUT blocks
    are obsolete, but the 11 UI fixture call sites prove current user-facing
    behavior and must cross the durable boundary instead.
  - Refuted: old rollback or stay-on-Info failure UI is required production
    behavior. A newly enqueued native retry maps to `started`, so Group Info
    pops while the exact intent, notice identity, local group, and history
    remain durable for retry. Once `nativeLeavePending` is durable, retry
    repeats only native leave and confirmed cleanup.
- Unresolved findings: N/A — source, production wiring, storage, tests, and
  runtime inventory agree on the replacement.
- Affected production, test, gate, inventory, and current-document files:
  - delete
    `lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart`
    and `test/shared/helpers/legacy_group_exit_coordinator_fixture.dart`;
  - edit
    `test/shared/helpers/durable_group_exit_surface_harness.dart`,
    `group_exit_actions_test.dart`,
    `group_exit_intent_coordinator_test.dart`, the two wired UI test files,
    `flow_event_emitter_test.dart`, `runtime_root_inventory_test.dart`, and
    `runtime_roots.json`;
  - reconcile only current inventory/architecture prose that claims the deleted
    class is an available implementation. Do not rewrite historical plan
    evidence.

### Exact Obsolete-Test Deletion Inventory

The removable island is eleven `test(...)` blocks containing sixteen
constructor expressions. Count and delete the blocks by these exact names, not
by constructor count or line range:

1. `active exit completes durable prework before native leave and target cleanup`
2. `active exit distinguishes degraded notice native and post-commit cleanup outcomes`
3. `completed cleanup does not skip native leave after a later rejoin`
4. `incomplete cleanup marker is scoped to the membership that left`
5. `cleanup retry never deletes a current group with unresolved membership`
6. `rapid active exit calls coalesce before publish and native leave`
7. `active exit blocks while an exact role transition is pending`
8. `active exit rechecks pending role sync at the native leave boundary`
9. `last-admin race rolls back its exact tentative leave timeline`
10. `leave rollback deletes only its own timeline when a later event arrives`
11. `snapshot and rollback repository errors remain typed failures`

Only seven helpers are currently exclusive to those blocks and may leave after
a fresh zero-reference check:
`_HangingLeaveBridge`, `_CleanupFailingGroupRepository`,
`_CleanupFailsOnceGroupRepository`, `_DeleteGroupFailsOnceRepository`,
`_ConcurrentRemovalMessageRepository`, `_SnapshotFailingGroupRepository`, and
`_RollbackFailingGroupRepository`. `_AfterFirstSignBridge` has modern consumers
outside the island and must remain. Every other test in
`group_exit_actions_test.dart` is protected.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `0c2b989ba6d96ada`; `freshness=current`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "leave_group_and_delete_local_history_use_case.dart superseded coordinator modern durable group exit replacement SUT-only tests" --profile tdd --budget 700`.
- Anchors:
  `package:flutter_app/features/groups/application/leave_group_and_delete_local_history_use_case.dart`
  ->
  `lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart`.
- Surfaced proof/gate files:
  `group_exit_policy.dart`, `group_exit_intent_coordinator.dart`,
  `group_exit_actions_test.dart`, and wired UI tests.
- Graph gaps requiring source search: the compact graph did not enumerate the
  legacy fixture's 11 retained call sites, the eleven direct SUT blocks, exclusive
  helper-class ownership, v103/v104 SQLCipher proofs, flow-event source
  inventory, or the runtime-root declaration. Targeted current-source searches
  resolved each gap.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Generalize the existing `DurableGroupExitSurfaceHarness` into the one shared
  production-shaped test fixture for normal leave, last-admin refusal, typed
  native refusal/uncertainty, degraded notice/rotation, cleanup fault/retry, and
  the already-covered pending-role race.
- Keep the fixture on real SQLite v103+ helpers,
  `GroupRepositoryImpl`, durable intent/pending repositories, and real
  `GroupExitIntentCoordinator`/`GroupExitIntentRunner`; inject only external
  bridge/network outcomes and deterministic time/IDs. Because the existing
  widget suites keep detached in-memory surface repositories, a thin
  harness-only projection may mirror a successfully committed SQL cleanup into
  those fakes. It must run only after the durable intent and durable group are
  absent, must recheck the exact surface membership generation, and must not
  choose, skip, synthesize, or overwrite a runner phase or result.
- Migrate all 11 current legacy-fixture UI call sites to that fixture without
  weakening their observable assertions except for the accepted native-retry
  correction below.
- Rewrite both `BB-010` and `GCA-010` to the live durable contract: the first
  request starts durably and pops Group Info, preserves the group and a seeded
  pre-existing history row, retains the exact `nativeLeavePending`
  intent/source/event and durable timeline for retry, and makes one initial
  native attempt. `GCA-010` must then prove an explicit retry adds exactly one
  native attempt, repeats no prepare/notice/rotation work, and cleans up only
  after native confirmation.
- Delete the old coordinator, old fixture, its runtime-root declaration, its
  five obsolete flow-event inventory rows, its import, the eleven direct
  SUT-only test blocks, and helper classes proven exclusive to those blocks.
- Preserve `_AfterFirstSignBridge`, which also supports modern tests outside the
  obsolete block.

Must preserve:

- Group Info and Orbit success/refusal/navigation behavior plus
  the already-live started-and-pop native-retry behavior -> all 11 migrated
  selectors plus the existing `PB264-16` durable UI tests.
- Durable queue identity, exact-membership authority, stable signed notice,
  restart idempotency, and cleanup ordering -> the named coordinator/runner
  sentinels in TC-280-03 and TC-280-04.
- Native `group:leave` invocation and Go topic cleanup -> TC-280-06.
- v103 intent rows, v104 diagnostic rows, current migration registry, existing
  group/message/key data, and encrypted reopen -> TC-280-05.
- Modern diagnostics and Settings visibility -> TC-280-07.
- Every non-obsolete test in `group_exit_actions_test.dart`, including tests
  that use `_AfterFirstSignBridge`.

Hard `Do not`:

- Do not edit production
  `group_exit_intent_{coordinator,runner,sink}.dart`,
  `group_exit_policy.dart`, `group_exit_terminal_diagnostics.dart`,
  startup/resume/rejoin wiring, or `main.dart` merely to make tests pass.
- Do not delete or migrate any `group_exit_intents`,
  `group_exit_diagnostics`, group, member, message, pending-broadcast, or key
  row, and do not change database version, schema, or migration.
- Do not remove native/platform/Go `group:leave` handlers or change leave-topic
  semantics.
- Do not delete a UI test because its fixture is inconvenient. A selector may
  be renamed only when it records the accepted durable semantic correction.
- Do not preserve the old class under a new name or recreate its in-memory
  commit/rollback markers inside the replacement fixture.

Deferred / accepted difference:

- A negative native acknowledgement no longer rolls back/remints the tentative
  leave timeline as the obsolete `GCA-010` fixture did. The modern system keeps
  the exact signed notice and durable intent for retry, because restart-safe
  monotonic progress is the production contract. For a newly enqueued request,
  `waitingForNativeRetry` maps to `started`, so Group Info pops instead of
  showing the obsolete failure snackbar. Both migrated native-failure selectors
  must state that difference; `GCA-010` must also prove native-only retry.
- Plan 279 removes the simpler dormant `leaveGroup` path only after this plan is
  Plan-green, because its host/device proof callers need the durable test driver
  established here.

Dependencies:

- `DTR10-AUTH-04` authorizes this exact retirement.
- Plan 286 is an already-Plan-green land-order prerequisite because its
  separately authorized Group List retirement removes two former
  legacy-fixture consumers. Plan 280 must not land or roll back ahead of that
  deletion.
- No other upstream code change is required. This plan is the execution
  prerequisite for Plan 279.

Stop-if:

- Stop and replan if a pre-edit census finds any production importer, if a UI
  behavior cannot be expressed through the live coordinator/runner, if the
  durable fixture requires production-only bypasses, or if satisfying a test
  requires schema/native/protocol changes. Also stop if Plan 286 is not landing
  first or atomically; restoring its two Group List consumers is outside this
  authorization.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-280-01 | The superseded coordinator, legacy fixture, direct imports/symbols, runtime-root declaration, obsolete flow-event inventory, eleven SUT-only blocks, and exclusive helpers are absent while the durable graph, valuable UI selectors, `_AfterFirstSignBridge`, and Android/iOS/macOS `groupLeaveTopic` handler mappings remain. | `test/unit/runtime_root_inventory_test.dart::DTR-10 retires superseded leave-local-history coordinator after durable fixture migration` | Host source/inventory contract / real repository tree | Causal RED on HEAD because the source, fixture, declaration, imports, event rows, and direct SUT blocks exist -> GREEN only after their exact removal and retained allowlist verification. | Restore any retired artifact; remove a retained durable source/test/UI selector, `_AfterFirstSignBridge`, or a platform `groupLeaveTopic` handler token -> TC-280-01 red. | `flutter test --no-pub test/unit/runtime_root_inventory_test.dart --plain-name 'DTR-10 retires superseded leave-local-history coordinator after durable fixture migration'`; existing `runtime-roots` gate and later wave `host-all`. |
| TC-280-02 | Both live surfaces exercise normal leave, sole-admin refusal, first-request native retry, cleanup, and unrelated-data preservation through real durable repositories/coordinator/runner rather than the legacy adapter. | `group_info_wired_test.dart::{GCA-009 leave group deletes local messages and pops to first route, sole admin leave stays on screen and shows an error, BB-010 native leave failure starts durable retry and pops from info, GCA-010 native leave failure retains exact durable intent and local history for native-only retry, writer Leave tears down local membership even when rotation is deferred, multi-admin leave broadcasts self-removal, rotates key, and pops to first route, writer leave broadcasts a durable left-the-group event before local cleanup}`; `orbit_wired_test.dart::{removed-member stuck row uses guarded local delete while ordinary stuck leave is preserved, first sole-admin Leave opens recovery without destructive work, leaving one Orbit group preserves friends and other groups, user-B scenario: leaving one Orbit group keeps both 1:1 chat threads with friends intact}` | Host widget / generalized `DurableGroupExitSurfaceHarness`, one SQLite-backed `GroupRepositoryImpl` plus durable intent/pending/timeline repositories, real durable coordinator/runner, and the bounded exact-membership post-commit fake-surface projection; fake bridge/network only | Existing non-native-failure selectors are GREEN sentinels on HEAD. The two corrected native-failure assertions are semantic RED against the legacy fixture because it rolls back, has no v103 intent, and stays on Info -> GREEN when all 11 selectors cross the real runner and assert runner side effects/intent phase without a raw fallback. | Route one surface back to a direct callback, no-op processor, detached-fake runner repository, or memory-only status adapter; let projection delete a newer surface membership or replace a committed result -> a named selector red. | Two exact UI-file commands; files already occur once in `GROUP_TESTS` and are covered by the `groups` lane. |
| TC-280-03 | A typed native refusal/uncertainty keeps the exact durable action for retry, never remints or rolls back live history, and repeats only the phase whose durable completion is unresolved. Notice-completion failure may re-attempt the same signed notice without reminting; after `nativeLeavePending`, retry repeats only native. | Rewritten Group Info `GCA-010 native leave failure retains exact durable intent and local history for native-only retry`; `group_exit_intent_runner_test.dart::{PB264-09 completion fault and restart reuse the exact durable notice without reminting, PB264-10 native ambiguity retries only native after process recreation}` | Host widget/application / real SQLite surface fixture plus deterministic runner repositories | Accepted semantic RED against the old fixture because it rolls back and has no v103 intent -> GREEN with the same exact intent/source/event/timeline identity, the typed `nativeRejected` fact, a seeded pre-existing SQLite history row preserved before confirmed cleanup, one initial native attempt, and exactly one additional native-only retry. | Delete the intent early, remint the notice, misclassify rejection as uncertainty, lose the seeded SQLite row, repeat prepare/notice/rotation after `nativeLeavePending`, or omit the second native attempt -> a named test red. | Focused runner and UI file commands below; both files already occur in `GROUP_TESTS`. |
| TC-280-04 | The durable replacement covers authority, simultaneous fresh duplicate requests, process recreation, later rejoin identity, cleanup fault/retry, and membership-safe finalization that the old in-memory markers attempted to cover. | `group_exit_intent_coordinator_test.dart::{DTR-10 rapid fresh leave requests converge on one durable action and side-effect sequence, PB264-14 existing intent result mapping never starts a second exit, PB264-11 runtime rejoin authority binds early exit work to its account}`; `group_exit_intent_runner_test.dart::{PB264-10 process recreation at every durable phase never repeats an earlier side effect, PB264-12 external cleanup fault retains the intent and restart finalizes SQL last, PB264-12 confirmed cleanup is atomic and membership-generation safe, PB264-18 enqueue, startup, rejoin, resume, and manual retry share one processor}`; `group_repository_impl_test.dart::PB264-12 exact exit keeps SQL retry addresses until strict external cleanup and finalizes last`; `handle_app_resumed_group_recovery_test.dart::PB264-18 resume recovery drains all before processing all and isolates errors` | Host application/core / real runner and SQLite repositories with a test-only initial-read/native barrier for the fresh-duplicate case, deterministic repositories, production repository sentinel, lifecycle callbacks | Add the fresh-duplicate preservation sentinel before removal; both callers must first observe no intent, overlap before native completion, and return the same durable action while one side-effect sequence runs. It and the existing GREEN sentinels must remain GREEN after obsolete-class removal and UI fixture migration. | Let one request finish before the other initial read, return a null/different action, remint on overlap, remove exact-intent dedupe, scope only by group ID, repeat an earlier phase, finalize SQL before external cleanup, or bypass the shared processor -> a named sentinel red. | Focused file commands below; coordinator/runner/repository files already occur in `GROUP_TESTS`; lifecycle runs directly and through `groups`. |
| TC-280-05 | Existing v103 intent and v104 diagnostic schemas, registry entries, and explicitly seeded predecessor rows remain row-equivalent, registered, idempotent, and reopenable. | `103_group_exit_intents_test.dart::PB264-04 v103 schema, empty backfill, constraints, registry, and rerun are exact`; `104_group_exit_diagnostics_test.dart::PB266-05 v104 diagnostic schema constraints registry and empty rerun are exact`; protected pre/post hashes for `app_database_version.dart`, `production_migration_registry.dart`, and migrations `103_group_exit_intents.dart` / `104_group_exit_diagnostics.dart` | Host SQLite migration/reopen preservation; live SQLCipher proofs remain registered for Wave-3/final aggregate closure | GREEN sentinels on HEAD -> remain GREEN; no protected database source, schema, registry, or seeded predecessor-row delta is allowed. | Change a protected database source/version/constraint/registry entry, delete a specifically seeded predecessor row, or omit host reopen/rerun -> hash or named proof red. Broad target/unrelated-data cleanup stays owned by TC-280-02/03. | Host files already occur in `GROUP_TESTS`/AUTO core; device paths remain discoverable for Wave-3/final aggregate proof. |
| TC-280-06 | The retained modern runner still issues the real Dart `group:leave` command, Android/iOS/macOS still map it to `groupLeaveTopic`, and native Go removes the topic/validator with rejoin semantics intact. | `bridge_group_helpers_test.dart::sends group:leave with groupId`; `go_bridge_client_test.dart::group:leave calls groupLeaveTopic with payload JSON`; TC-280-01 platform-handler source guard; Go bridge `::{TestGroupLeaveTopic_NodeNotInitialized, TestGroupLeaveTopic_InvalidJSON, TestGroupLeaveTopic_MissingGroupId, TestGroupLeaveTopic_BB009RemovesNativeTopicAndBlocksPublish}`; Go node `::TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey` | Host Dart mocked MethodChannel, platform source guard, and Go host implementation | GREEN sentinels/guard on HEAD -> remain GREEN after deletion. | Remove/rename the Dart command, platform handler mapping, payload, Go topic removal, or validator cleanup -> source guard, Dart, or Go proof red. | Exact Dart/Go commands below; Dart AUTO, Go manual exact commands. |
| TC-280-07 | Release diagnostics remain produced once for every modern snapshot/processor path, preserve typed native uncertainty, and remain visible without relying on the deleted flow events. | `group_exit_diagnostic_wiring_test.dart::PB266-03 disjoint observers cover snapshot pre-intent and every processor path once`; `group_exit_release_diagnostics_test.dart::{PB266-01 arbitrary cause is unexpected before dispatch and uncertain after dispatch, PB266-02 not initialized is diagnostic only and never reinitializes or retries leave}`; `flow_event_emitter_test.dart` full file | Host application/core / typed diagnostic facts and source-event inventory | GREEN sentinels on HEAD -> remain GREEN after removing only the five obsolete source/event rows. | Drop a modern observer, duplicate a record, misclassify native ambiguity, retry initialization/leave, or remove a retained flow-event row -> named test red. | Exact focused command below; application files occur in `GROUP_TESTS`, core file AUTO; `groups`. |

### Test Notes

- TC-280-01 must identify the eleven old blocks by their direct construction of
  `LeaveGroupAndDeleteLocalHistoryUseCase`, not by deleting a line-number range.
  Line positions are unstable, and `group_exit_actions_test.dart` has extensive
  modern coverage before and after the island.
- Its residue census covers owned Dart roots under `lib`, `test`,
  `integration_test`, `test_driver`, `scripts`, and `tool`, plus root-level
  Dart files. The absent Plan 286 suite is a declared prerequisite, not an
  omitted Plan 280 consumer.
- Before deleting each helper class after the old blocks, perform a current
  word-boundary reference count. `_AfterFirstSignBridge` is known to have
  modern consumers and must remain.
- The generalized durable fixture must expose intent/phase/source identity and
  side-effect counters. Widget assertions alone are insufficient proof that the
  production-shaped runner was used.
- The migrated native-failure test must distinguish a negative acknowledgement
  from arbitrary/timeout ambiguity, but both outcomes retain durable work. It
  must not recreate the obsolete rollback behavior.
- `GCA-010` must seed at least one pre-existing target-group history row and
  assert that exact row plus the durable leave timeline and intent identity
  survive native refusal; a zero-row message-count assertion is vacuous.

## Implementation Steps

1. Snapshot `git status --short`; record the pre-edit hash/diff of every
   protected modern exit, database, native, and Go file.
2. Add TC-280-01 to `runtime_root_inventory_test.dart` and run it alone before
   production edits. Record non-zero status caused by the present old source,
   fixture, imports, manifest row, event rows, and SUT blocks.
3. Generalize `DurableGroupExitSurfaceHarness` without weakening its existing
   PB264-16 pending-role race. Use one real v103+ SQLite
   `GroupRepositoryImpl`, durable repositories, and the real
   coordinator/runner; expose deterministic external-outcome controls and
   intent/side-effect observations. Keep the detached fake only as an
   exact-membership, post-commit UI projection, and never let projection
   fabricate or overwrite runner status.
4. Replace all 11 `installLegacyGroupExitCoordinatorFixture` calls in Group
   Info and Orbit. Run each migrated selector before deleting the
   old fixture. Rewrite both BB-010 and GCA-010 to the accepted started/pop
   durable-retry contract; make GCA-010 prove native-only retry.
5. Add the modern simultaneous-fresh-request sentinel to
   `group_exit_intent_coordinator_test.dart` using the real runner, an
   initial-read barrier plus held native call, and exact
   intent/source/event/side-effect observations.
6. Delete the eleven direct old-SUT tests from
   `group_exit_actions_test.dart`. Remove only imports/helpers with zero
   remaining references. Run the whole file so adjacent modern tests remain
   intact.
7. Delete the old coordinator and legacy fixture; remove the exact
   `runtime_roots.json` declaration and five obsolete event inventory rows.
   Reconcile only present-tense inventory/architecture prose.
8. Run TC-280-01 GREEN, then temporarily restore one forbidden import/token to
   demonstrate representative mutation re-red; revert the mutation and rerun.
9. Run focused durable, UI, diagnostic, migration, Dart/Go native-preservation
   tests, then `runtime-roots` and `groups`. Compare protected database,
   platform, modern-exit, native, and Go files with their captured baselines.

## Risks And Blind Spots

- A test-only adapter could hide a broken durable phase -> TC-280-02 requires
  real repositories/coordinator/runner and intent/side-effect assertions.
- A detached UI projection could erase a newer membership or replace a
  committed result -> it must recheck the exact surface generation, remain
  post-commit, and record rather than rethrow projection failure.
- Deleting a broad test range could remove live coverage or
  `_AfterFirstSignBridge` -> TC-280-01 allowlists retained selectors/symbols and
  Step 6 requires current reference counts.
- The old rollback expectation conflicts with monotonic durable progress ->
  TC-280-02/03 correct both stale UI selectors and prove exact retry.
- Sequential existing-intent tests do not replace simultaneous fresh-request
  proof -> TC-280-04 adds one real-runner convergence sentinel before deleting
  the old coalescing test.
- Lifecycle / derived-state durability: TC-280-03 through TC-280-05 cover
  process recreation, SQL-last cleanup, membership generation, resume, and host
  reopen without claiming an unaffected device boundary.
- Sibling-surface consistency: TC-280-02 migrates Group Info and Orbit together.
- Destructive-action side effects: TC-280-02/03 preserve unrelated groups,
  friends, 1:1 threads, current group/history on failure, and target-only
  cleanup after confirmed leave.
- Invariant re-verification under new transitions: TC-280-04 rechecks exact
  membership/last-admin authority and later-rejoin identity at durable phase
  boundaries.

## Gate Cadence

- Per-plan closure: causal runtime-root contract; focused durable coordinator,
  runner, action, UI, diagnostics, lifecycle, migration, bridge, and Go
  sentinels; protected-source hashes; `runtime-roots`; and `groups`.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the DTR Wave-3
  DTR-09/DTR-10/DTR-11 batch is complete or terminal, and once at final
  rollout/release closure.
- Shared tests outside feature/core globs:
  `test/unit/runtime_root_inventory_test.dart` runs directly and through
  `runtime-roots`; Go tests run by exact package commands. The registered v103
  SQLCipher and v104 release-diagnostic device proofs run at the named Wave-3
  and final aggregate closures, not for this unaffected individual slice.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes.
git status --short

# Causal RED before any removal; expect non-zero only because old artifacts exist.
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR-10 retires superseded leave-local-history coordinator after durable fixture migration'

# Focused durable replacement and obsolete-island adjacency.
flutter test --no-pub \
  test/features/groups/application/group_exit_actions_test.dart \
  test/features/groups/application/group_exit_intent_coordinator_test.dart \
  test/features/groups/application/group_exit_intent_runner_test.dart
flutter test --no-pub \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  --plain-name 'PB264-12 exact exit keeps SQL retry addresses until strict external cleanup and finalizes last'

# All migrated user-facing consumers.
flutter test --no-pub \
  test/features/groups/presentation/group_info_wired_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart

# Diagnostics and lifecycle preservation.
flutter test --no-pub \
  test/features/groups/application/group_exit_diagnostic_wiring_test.dart \
  test/features/groups/application/group_exit_release_diagnostics_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/core/utils/flow_event_emitter_test.dart

# Schema/registry preservation; no migration is authored by this plan.
flutter test --no-pub \
  test/core/database/migrations/103_group_exit_intents_test.dart \
  test/core/database/migrations/104_group_exit_diagnostics_test.dart

# Dart/native and Go leave preservation.
flutter test --no-pub \
  test/core/bridge/bridge_group_helpers_test.dart \
  --plain-name 'sends group:leave with groupId'
flutter test --no-pub \
  test/core/bridge/go_bridge_client_test.dart \
  --plain-name 'group:leave calls groupLeaveTopic with payload JSON'
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge \
  -run '^TestGroupLeaveTopic_' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey$' \
  -count=1)

# Existing registration/discovery and affected lanes. The shared real index
# intentionally leaves the Plan 277/278/280 lib deletions unstaged. Copy it,
# stage only those accepted predecessor/current deletions in the copy, and
# leave the user's real index untouched.
DTR280_INDEX_DIR=$(mktemp -d)
DTR280_INDEX_PATH="$DTR280_INDEX_DIR/index"
cp "$(git rev-parse --git-path index)" "$DTR280_INDEX_PATH"
GIT_INDEX_FILE="$DTR280_INDEX_PATH" git add -u -- \
  lib/features/groups/application/join_group_use_case.dart \
  lib/features/groups/application/hydrate_groups_from_peers_use_case.dart \
  lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart
GIT_INDEX_FILE="$DTR280_INDEX_PATH" \
  ./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh groups
./scripts/check_reliability_simulation_discovery.sh --records-tsv | \
  rg '^group\ttest\tintegration_test/group_exit_(intents|release_diagnostics)_sqlcipher_proof_test\.dart\t'

# Hygiene.
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

## Device/Relay Proof Profile

- Profile: N/A for individual Plan 280 closure.
- Reason: this plan deletes a source with no production importer and hard-freezes
  schema/version/migrations, the live runner, platform handlers, and native/Go
  implementation. The existing SQLCipher/release proofs do not import or
  execute the deleted class or migrated host fixture, so they are not causal
  per-plan gates.
- Registration preservation: both device paths must still classify exactly
  once as `group`; TC-280-05 keeps the discovery command.
- Aggregate owner: rerun the explicitly rediscovered and pinned v103 SQLCipher
  and v104 release-diagnostic proofs after the DTR Wave-3
  DTR-09/DTR-10/DTR-11 batch and at final rollout/release closure. Apply the
  repository device policy there: physical Android preferred, available
  emulator fallback, and `N/A (target unavailable by project policy)` only
  when no compatible Android target exists.

## Execution Interpretation And Done Criteria

- Expected RED: TC-280-01 fails because the old source, fixture, manifest/event
  rows, imports, and direct SUT tests are present.
- Green sentinel: the migrated UI selectors and named durable restart/cleanup
  tests pass with real intent rows and no legacy adapter.
- Pre-existing dirty tree / known failure: snapshot and preserve all unrelated
  current changes; no known failure is accepted without a before/after
  reproduction outside this plan's diff.
- Environment blocker: none; individual closure is host-only.
- Scope drift: any production caller, schema/native edit, lost UI selector, or
  need to re-create transient commit/rollback state blocks completion.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] All 11 valuable UI fixture call sites use the durable harness and preserve
      semantic outcomes.
- [x] Only the eleven direct old-SUT blocks and proven-exclusive helpers are
      removed; the rest of `group_exit_actions_test.dart` remains green.
- [x] Durable restart, membership, cleanup, diagnostics, and Dart/Go native
      preservation gates pass.
- [x] Existing harness registration/discovery is verified.
- [x] No migration/schema/data change occurred.
- [x] `./scripts/check_flutter_analyze_strict.sh` has no new issues;
      `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/unit/runtime_root_inventory_test.dart --plain-name 'DTR-10 retires superseded leave-local-history coordinator after durable fixture migration'`.
- Preservation command:
  `./scripts/run_test_gates.sh groups`.
- Manual registration: none; the source contract uses the existing
  `runtime-roots` gate, feature/core files are already AUTO or in `GROUP_TESTS`,
  and both deferred aggregate device proofs retain `group` classifier records.
- Migration: none. DB v103/v104 host tests and protected-source hashes are
  per-plan preservation; device proofs remain Wave-3/final aggregate evidence.
- Boundary closure: focused host durable/UI/migration/Dart/Go proof,
  `runtime-roots`, and `groups`.
- Unresolved evidence: none.

## Reviewer Findings

- `$tdd-review` initially returned `plan-fixes-required` while confirming the
  removal bet. The plan corrected only the stale native-failure semantics,
  simultaneous-fresh-request gap, overbroad migration claim, unnamed platform
  preservation, and non-causal per-plan gate/device obligations.
- The review recheck returned `ready`, classification
  `implementation-ready`, and disposition `execute`. Evidence truth, causal
  Test Contract, bypass/scope safety, gate integrity, and reversibility were
  clear after those bounded corrections.
- The implementation counterexample audit then found five fixture/proof
  weaknesses plus the missing Plan 286 land-order declaration. The final
  fixture uses one real SQLite `GroupRepositoryImpl`, forces duplicate-request
  overlap, checks durable history and exact phase identity, scans every owned
  Dart root, and declares Plan 286 as a prerequisite rather than absorbing it.
- A final audit found one remaining race in the detached fake-surface
  projection. It is resolved by a no-await exact-membership CAS spanning the
  in-memory group and message surfaces; a boundary-interleaving test proves a
  newer same-peer membership, group, and history survive without replacing the
  committed runner result.
- Final verdict: `Plan-green`; implementation and closure evidence are
  sufficient. Device execution remains N/A for this unaffected,
  host-only retirement, and Plan 279 is unblocked only for its separate
  authorized execution.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-26 | Causal RED / preservation baseline | `runtime_root_inventory_test.dart`; protected modern-exit, v103/v104, platform, Dart/native, and Go sources | Exact TC-280-01 command failed as required, listing both obsolete files, manifest/event rows, eleven blocks, seven helpers, and the two intentionally renamed selectors; SHA-256 baseline captured for all protected sources. | The removal contract is causal and the protected boundary is immutable for this execution. | None. | Land the production-shaped harness, corrected UI selectors, fresh-duplicate sentinel, and exact retirement; then run GREEN. |
| 2026-07-26 | Exact retirement / mutation | Deleted coordinator and legacy fixture; action tests; runtime-root manifest; obsolete flow inventory; TC-280-01 | TC-280-01 GREEN; temporary obsolete flow-event mutation made only the expected contract fail, then GREEN after removal; owned-root census is zero | Eleven direct SUT-only blocks and seven exclusive helpers retired; all 11 valuable UI consumers and `_AfterFirstSignBridge` remain | None | Harden the durable surface and run preservation |
| 2026-07-26 | Durable fixture / counterexample closure | Durable surface harness; in-memory surface fakes; Group Info; Orbit; coordinator tests | Full coordinator + Group Info + Orbit batch `210/210`; rapid fresh requests converge on one exact action/side-effect sequence; newer-membership projection sentinel GREEN | Runner phases use one SQLite-backed production repository; native refusal retains exact retry identity/history; fake projection is an atomic membership-generation CAS and cannot replace a committed result | None | Run registered and curated closure gates |
| 2026-07-26 | Preservation / closure | Runtime roots; diagnostics/lifecycle; v103/v104; Dart/Go/native; discovery; analyzer; Graphify | Isolated copied-index `runtime-roots` `18/18`; current-tree `groups` `3239/3239` plus Go bridge/node/relay legs; both SQLCipher proofs rediscovered; strict analysis and `git diff --check` clean; incremental Graphify refresh completed | Protected modern-exit, schema/migration, platform, native, and Go sources have no Plan 280 delta; `lib/main.dart` drift is unrelated concurrent account-migration work; device leg is N/A by policy | `Plan-green`; no unresolved evidence | Keep Plan 279 as a separate authorized implementation |
