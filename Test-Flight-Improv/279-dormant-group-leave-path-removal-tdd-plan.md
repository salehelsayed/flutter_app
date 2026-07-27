# 279 - Dormant group leave path removal

Status: Plan-green
Type: Modification
Spec: free-text intent for `DTR-10` / the old `leaveGroup` function and
default-disabled active branch in
`Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
Classification: implemented-and-verified
Closure tier: device
Roadmap ID / wave: `DTR-10` / Wave 3 — Compatibility-led groups cleanup
Date: 2026-07-26

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 | Evidence Collector / Planner | `leave_group_use_case.dart`, `delete_group_and_messages_use_case.dart`, all production callers/importers, direct host/device test callers, durable group-exit production graph, last-admin UI surfaces, native leave tests, v103/v104 tests, group gates and multi-device runner | Every production delete caller selects strict dissolved-local cleanup; the default-false branch is dormant. The live UI exits through durable intent coordination. Old host/device proofs still call the function directly, so they must be migrated to the production-shaped durable driver established by Plan 280 before source deletion. | Wait for Plan 280 Plan-green, add causal absence contract, migrate proof callers, remove only the old path, and close host/device preservation. |
| 2026-07-26 | Prerequisite closure sync | Plan 280 status, retired coordinator/fixture, generalized durable harness, migrated Group Info/Orbit proof, roadmap and index | Plan 280 is Plan-green and its accepted durable fixture is present; the sole planning prerequisite is satisfied without expanding Plan 279's authorization | Execution-ready: rerun the source census and live device matrix, then begin TC-279-01 RED |
| 2026-07-26 | Independent TDD Review | Current caller census, Plan-280 FFI surface harness, production SQL cleanup, `GroupTestUser`, H-01/GM-015 payloads and evaluator, runner relay preflight, gates, and live device matrix | `plan-fixes-required`: the removal bet is confirmed, but a renamed manual host path could pass; the FFI/copy surface harness is not the real SQLCipher device boundary; H-01/GM-015 did not measure durable/native cardinality; the old leaver-local-history assertion contradicts production cleanup; and device commands omitted the mandatory relay environment. | Tighten only the driver seam, causal host/device proof, obsolete history expectation, evaluator gate, and literal device commands; then rerun the five lenses. |
| 2026-07-26 | Independent TDD Review / Recheck | Revised scope, TC-279-01/06/07/08, driver adapters, evaluator mutations, relay command, cleanup preservation, and gate cadence | `ready`: all five lenses are clear after the bounded corrections. The plan now requires one injected-repository driver shared by host and device adapters, production-equivalent leaver cleanup, exact durable/native device evidence, and copy-pasteable relay commands. | Execute the revised causal RED, migrations, exact retirement, and proportionate closure gates. |
| 2026-07-26 | Execution amendment | First strict-Android H-01 launches, per-role logs, app-private signal broker, and runtime-config transport | The product path completed, but the generic Android runner first used unstaged defaults and later let a completed role uninstall before its app-private verdict was host-captured. This was a causal runner-boundary RED, not acceptable device evidence. | Bound the existing runner to atomic Documents config staging, exact framed ADB reads, app-private per-run signals, and an all-verdict terminal capture barrier; prove the boundary with focused tests before rerunning H-01/GM-015. |

## Authorization Receipt

- Receipt: `DTR10-AUTH-03`.
- Authority/date: current authenticated project owner, 2026-07-26.
- Authorized action: remove the unused old `leaveGroup` function and the
  default-disabled active branch that calls it.
- Required preservation: the live user-facing last-admin rule/message, native
  `group:leave`, existing database records, diagnostics, and the modern durable
  exit flow.
- Guard: authorization does not permit deleting valid host/device behavior
  coverage merely because it currently calls the obsolete helper.

## Problem And Evidence

- Behavior to improve: remove a dormant, non-durable leave route so active
  group exit has one implementation and dissolved-shell deletion remains a
  separate strict local action.
- Impact: `leaveGroup` performs native leave followed by direct destructive
  cleanup without durable intent, signed-notice phase tracking, restart
  recovery, typed diagnostics, or membership-generation-safe SQL cleanup.
  Keeping it invites accidental reconnection to production.
- Confirmed root cause/current gap:
  - `leaveGroup` at
    `lib/features/groups/application/leave_group_use_case.dart:12` is called in
    production only from the default-false branch of
    `deleteGroupAndMessages` at
    `lib/features/groups/application/delete_group_and_messages_use_case.dart:95`.
  - The boolean defaults to false at line 28, but all three production callers
    explicitly pass `deleteLocallyIfDissolved: true`:
    `lib/main.dart:2855-2861`,
    `group_info_wired.dart:1089-1095`, and
    `orbit_wired.dart:3480-3486`.
  - Therefore the active/native branch, its `Bridge` parameter, and its
    `leaveGroup` import are unreachable from the production call graph.
- Confirmed live replacement:
  - Group Info and Orbit call
    `requestGroupExitIntentLeave`, not `leaveGroup`.
  - `lib/main.dart:4027-4315` wires the durable repository, coordinator,
    runner, typed native leave, diagnostics, and startup/rejoin/resume/manual
    recovery.
  - Plan 280 migrates remaining UI proof off the superseded transient
    coordinator onto that same production-shaped boundary.
- Live symbol hidden in the old file:
  `lastAdminLeaveBlockedMessage` is still imported by both live UI surfaces.
  They already import `group_exit_policy.dart`, so move the compatibility copy
  there atomically; do not delete or rewrite it.
- Stale production documentation:
  `group_message_listener.dart` imports the old file only so comments can link
  to `[leaveGroup]`. Current self-removal retention uses
  `_retainSelfRemovedLocalHistory`; update those comments to name the durable
  exit/retention behavior and remove the import.
- Valuable test/proof callers still rooted in the old function:
  - `group_test_user.dart` and host smoke/integration tests for membership,
    startup rejoin, and member-removal convergence;
  - `group_multi_party_device_real_harness.dart` in H-01
    `private_voluntary_leave_convergence` and GM-015 last-admin policy.
  These must invoke a production-shaped durable coordinator/runner driver after
  Plan 280; their semantic assertions stay.
- Obsolete-only coverage:
  `leave_group_use_case_test.dart` directly tests only the function being
  deleted. The active/default-false cases inside
  `delete_group_and_messages_use_case_test.dart` test only the branch being
  deleted. Remove those assertions atomically, while retaining all strict
  dissolved-local cases and PB266 diagnostics.
- Existing preservation coverage:
  - strict dissolved cleanup has fail-closed/retry/diagnostic tests;
  - modern coordinator/runner suites cover last-admin, durable notice, native
    retry, cleanup, diagnostics, and lifecycle recovery;
  - bridge and Go tests cover actual `group:leave`;
  - H-01 and GM-015 close real three-party success and refusal behavior.
- Missing coverage: no causal contract requires the old source/import/boolean
  branch/direct proof callers to disappear while retaining the last-admin
  constant, strict local deletion, durable graph, and native/database floors.
- Refuted findings:
  - Refuted: the false branch is a supported fallback. No production caller
    selects it.
  - Refuted: `deleteGroupAndMessages` should be removed wholesale. Its strict
    dissolved-shell local cleanup is live in three production surfaces.
  - Refuted: the old helper tests can all be deleted. Several host/device
    scenarios prove live user and convergence outcomes and must be retargeted.
- Unresolved findings: none at planning time. Plan 280 is Plan-green. Its
  FFI/copy surface harness supplies the accepted host behavior, but it is not a
  device boundary; this plan generalizes its runner composition around injected
  repositories and adds a real-SQLCipher adapter to the existing device stack.
  There is no product-policy ambiguity. Relay reachability and the
  availability-bounded Android topology must be resolved again when the
  three-party proof runs.
- Affected production, test, and gate files:
  - delete `leave_group_use_case.dart` and its dedicated unit test;
  - simplify `delete_group_and_messages_use_case.dart` to strict dissolved-local
    semantics and update its three production callers plus every retained
    strict-call test;
  - move the compatibility message to `group_exit_policy.dart`;
  - update `group_message_listener.dart` comments/import;
  - generalize the Plan-280 runner composition for injected repositories,
    retaining its FFI/detached host adapter and adding a no-copy real-SQLCipher
    adapter to `GroupMultiDeviceTestStack`;
  - migrate exact host/device callers through that one driver;
  - update H-01/GM-015 verdict payloads, evaluator, and evaluator tests so the
    old manual path and duplicate/omitted notice/native work cannot pass;
  - add the causal source contract to
    `test/unit/runtime_root_inventory_test.dart`.

### Exact Caller-Migration Inventory

- The mandatory-local signature migration has 14 current `true`-branch call
  sites: three production callers (`main.dart`, `group_info_wired.dart`, and
  `orbit_wired.dart`) plus eleven retained test calls (eight in
  `delete_group_and_messages_use_case_test.dart`, two in
  `group_delete_preserves_friends_and_dms_test.dart`, and the GM-032 call in
  `group_membership_smoke_test.dart`). All 14 lose `Bridge` and the boolean;
  none of the retained test calls is deleted.
- The six default/active-branch tests to delete from
  `delete_group_and_messages_use_case_test.dart` are exactly:
  `leaves group then deletes its messages`,
  `LP003 active delete dispatches one group leave`,
  `preserves messages when leave is blocked`,
  `BB-010 active delete preserves group messages when native leave fails`,
  `does not delete messages for other groups`, and
  `propagates errors from message deletion`.
- Every other old-helper consumer is migrated, not deleted:
  `group_test_user.dart`, the named membership/startup/member-removal host
  proofs, and the H-01/GM-015 device harness branches.

## Graph Grounding Snapshot

- Final graph fingerprint / freshness after implementation:
  `776163ea2b77684f`; `freshness=current`.
- Planning query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-10 dormant leaveGroup function default-disabled branch last-admin rule native group:leave DB v103 v104 diagnostics modern durable group exit flow" --profile tdd --budget 700`.
- Closure query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-10 leaveGroup deletion deleteGroupAndMessages mandatory strict local cleanup durable driver H-01 GM-015 Android verdict host capture terminal barrier" --profile general --budget 600`, followed by the affected-file query recorded in Execution Progress.
- Anchors:
  `leaveGroup` ->
  `test/shared/fakes/group_test_user.dart:507`
  (`test_shared_fakes_group_test_user_leavegroup`).
- Surfaced proof/gate files: group resume recovery, group listener, group
  repository, and integration/smoke tests.
- Graph gaps requiring source search: the graph anchored the test helper rather
  than the production declaration and did not prove boolean call-site values,
  UI constant imports, device-harness calls, or native/DB floors. Targeted
  current-source searches established those facts.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- With Plan 280 green, delete
  `lib/features/groups/application/leave_group_use_case.dart`.
- Move `lastAdminLeaveBlockedMessage` unchanged into
  `group_exit_policy.dart`; remove old-file imports from Group Info, Orbit, and
  `group_message_listener.dart`; correct the listener's stale links.
- Make `deleteGroupAndMessages` strict dissolved-local cleanup only: remove its
  `Bridge` argument, `deleteLocallyIfDissolved` boolean/default, native phase,
  `leaveGroup` call, and branch-only EX99 mapping. Update all three live callers
  and retained tests to the simpler exact signature.
- Delete `leave_group_use_case_test.dart` and only the active/default-false
  cases in `delete_group_and_messages_use_case_test.dart`.
- Retarget every remaining direct test/harness caller to the Plan-280
  production-shaped durable exit driver. Generalize one shared runner builder
  around injected repositories/callbacks: the existing FFI/detached adapter
  remains for host fakes, while the existing device stack supplies its real
  SQLCipher database, complete cleanup-capable `GroupRepositoryImpl`, bridge,
  identity, and P2P callbacks without copying or projecting state. For H-01 and
  GM-015, replace the separate pre-broadcast-plus-old-cleanup sequence with one
  real durable coordinator/runner action so notice is never duplicated.
- Update the existing voluntary-leave host sentinel to the production cleanup
  contract: the receiver retains one leave timeline event and later traffic,
  while the leaver's target group/history are absent. The obsolete old-helper
  expectation that the leaver retains its own leave timeline is not preserved.
- Extend the H-01/GM-015 verdict schema/evaluator and its host tests with exact
  durable action identity, phase cardinality, terminal state, and bridge-command
  assertions.
- Repair only the existing generic Android multi-party proof transport required
  to collect that evidence: atomically stage the exact per-role Documents
  config, keep signals in the role's app-private per-run directory, frame ADB
  reads so missing/error output cannot masquerade as data, and hold every strict
  Android role until all verdicts are captured and terminal acknowledgements
  are delivered target-only. Legacy and iOS launch behavior stays non-waiting.

Must preserve:

- Exact last-admin compatibility copy on Group Info and Orbit ->
  TC-279-03.
- Strict local deletion only for a twice-revalidated dissolved group, including
  retry after non-cascading cleanup failure and PB266 EX10 diagnostics ->
  TC-279-02.
- Durable signed notice, intent identity, native-only retry, exact cleanup,
  startup/rejoin/resume/manual recovery, and diagnostics -> TC-279-04.
- Dart/native/Go `group:leave` and topic/validator behavior -> TC-279-05.
- All existing database schemas/migrations/rows, group encryption keys and
  generations, pending broadcasts, release diagnostics, and unrelated
  group/1:1 history.
- H-01 successful writer leave convergence and GM-015 sole-admin refusal ->
  TC-279-07 and TC-279-08.

Hard `Do not`:

- Do not edit or delete modern group-exit coordinator/runner/sink/repository,
  diagnostics, startup/rejoin/resume wiring, or native/platform/Go leave code.
- Do not change database version/schema/migrations or perform a data cleanup.
- Do not weaken the strict dissolved re-read, cleanup ordering, retry marker,
  pending-broadcast discard ordering, or typed state-race exception.
- Do not rewrite last-admin copy or route UI back to a raw bridge command.
- Do not delete H-01, GM-015, membership, startup-rejoin, or member-removal
  proof just to achieve a zero-call census.
- Do not introduce a second exit algorithm. Reuse one injected-repository
  runner builder; host FFI projection and device SQLCipher are storage adapters
  around it. Never use the detached FFI copy as device evidence.
- Do not place secrets or per-run identity/config values in new Dart defines,
  copy a device database into host evidence, acknowledge a role before all
  verdicts are captured, or revisit/read back a target after its terminal
  acknowledgement.

Deferred / accepted difference:

- Plan 280 completed first. This plan still does not absorb or partially remove
  old callers outside its own separately authorized execution.
- No behavior is deferred after that prerequisite; environment-unavailable
  device legs use the repository's availability-bounded policy, not a weakened
  host substitute.

Dependencies:

- Satisfied prerequisite: Plan 280 is Plan-green, its generalized durable
  fixture is accepted, and no migrated UI test uses
  `LeaveGroupAndDeleteLocalHistoryUseCase`.
- `DTR10-AUTH-03` authorizes the exact removal once that prerequisite is met.

Stop-if:

- Stop and replan if any production caller is found selecting the false/native
  branch, if the compatibility message has another public owner, if a proof
  scenario cannot be expressed through the durable runner without changing its
  outcome, or if schema/native/protocol edits appear necessary.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-279-01 | The old source, `leaveGroup` declaration/imports/direct callers, boolean branch/default, obsolete unit test, and branch-only assertions are absent; migrated host/device wrappers invoke the shared durable driver rather than direct broadcast/native/delete; the message, strict local action, modern graph, and valid proof scenarios remain. | `test/unit/runtime_root_inventory_test.dart::DTR-10 retires dormant leaveGroup and default-false active-delete branch` | Host source/caller contract / real repository tree | Causal RED on HEAD because the old source/function/branch/imports/direct proof callers exist -> GREEN after exact retirement, driver anchors, and retained allowlist checks. | Restore the function/boolean/import/call, replace a migrated wrapper with manual broadcast/native/delete, delete the compatibility constant/strict function/modern source, or drop H-01/GM-015 registration -> TC-279-01 red. | Exact command below; existing `runtime-roots` gate and later wave `host-all`. |
| TC-279-02 | `deleteGroupAndMessages` remains a fail-closed, twice-revalidated, retryable dissolved-local purge; target cleanup preserves unrelated groups, friends, and 1:1 history. | `delete_group_and_messages_use_case_test.dart::{strict local-only cleanup refuses active state and clears dissolved local state, strict local-only cleanup remains retryable across non-cascading cleanup failures, dissolved local cleanup deletes group state without publishing group leave, LP003 dissolved local cleanup does not publish a second group leave, PB266-12 diagnosing dissolved local action preserves throw and records once}`; `group_delete_preserves_friends_and_dms_test.dart::{B deletes the dissolved group: B keeps friends + DMs; A and C local group state untouched, B has multiple groups: deleting one dissolved group does not touch the others}`; `group_membership_smoke_test.dart::GM-032 offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others` | Feature host / repository and pending-broadcast fakes with destructive-boundary mutation | GREEN sentinels on HEAD after selecting `true` -> remain GREEN through the simplified mandatory-local signature, with active/missing rows refused, dissolved target purged in order, failure retryable, EX10 once, and unrelated rows preserved. | Remove either re-read, reorder queue discard before group delete, swallow cleanup error, broaden target deletion, or classify state race as EX10 -> a named test red; reintroducing native leave is caught by TC-279-01's source contract. | Exact files/selectors below; delete-use-case file is in `GROUP_TESTS`, while the two integration files run directly and through `feature-host-all`. |
| TC-279-03 | Both live surfaces retain the exact sole-admin refusal/recovery behavior and compatibility message after its rehome. | New Orbit preservation selector `orbit_wired_test.dart::DTR-10 recovery-sheet retry last-admin keeps compatibility message`; existing Group Info selector `group_info_wired_test.dart::sole admin leave stays on screen and shows an error`; TC-279-01 source allowlist | Host widget / Plan-280 durable surface fixture and exact localized text | GREEN sentinel to add/run before production deletion because current surfaces already use the exact text -> remains GREEN after rehome; zero native/cleanup and group remains. | Alter/remove the constant, hard-code divergent copy, treat refusal as success, pop route, or invoke native cleanup -> one surface test red. | Two exact UI commands; files already in `GROUP_TESTS` and `feature-host-all`. |
| TC-279-04 | Production-shaped durable exit still creates one exact intent/notice, retries only unfinished phases, finalizes exact membership cleanup, records diagnostics, and shares startup/rejoin/resume/manual recovery. | `group_exit_intent_coordinator_test.dart::PB264-14 existing intent result mapping never starts a second exit`; `group_exit_intent_runner_test.dart::{PB264-10 native ambiguity retries only native after process recreation, PB264-12 confirmed cleanup is atomic and membership-generation safe, PB264-18 enqueue, startup, rejoin, resume, and manual retry share one processor}`; `group_exit_diagnostic_wiring_test.dart::PB266-03 disjoint observers cover snapshot pre-intent and every processor path once`; `handle_app_resumed_group_recovery_test.dart::PB264-18 resume recovery drains all before processing all and isolates errors` | Host application/core / deterministic repositories plus real SQLite cleanup | GREEN sentinels on HEAD -> remain GREEN after old path deletion and proof-caller migration. | Remint/repeat, use group ID without membership identity, cleanup before confirmed native leave, bypass shared recovery, or drop diagnostic observer -> named red. | Exact files/selectors; existing `GROUP_TESTS`/AUTO registration, `groups` and `feature-host-all`. |
| TC-279-05 | The modern runner and migrated proof driver still call the real Dart/native/Go leave command exactly where authorized. | `bridge_group_helpers_test.dart::sends group:leave with groupId`; `go_bridge_client_test.dart::group:leave calls groupLeaveTopic with payload JSON`; Go bridge `::{TestGroupLeaveTopic_NodeNotInitialized, TestGroupLeaveTopic_InvalidJSON, TestGroupLeaveTopic_MissingGroupId, TestGroupLeaveTopic_BB009RemovesNativeTopicAndBlocksPublish}`; Go node `::TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey` | Host Dart mocked MethodChannel plus Go host implementation | GREEN sentinels on HEAD -> remain GREEN after removing only the obsolete wrapper. | Rename/drop payload, bypass typed native adapter, fail to remove topic/validator, or corrupt rejoin config -> a named proof red. | Exact Dart/Go commands below; Dart AUTO, Go manual exact commands. |
| TC-279-06 | Host membership/startup/member-removal proofs no longer import or call the old helper and retain production-valid outcomes through the shared durable driver. | `group_membership_smoke_test.dart::{sole admin cannot leave while only writer members remain, GM-015 creator/admin self-removal and leave are blocked with healthy writers, multi-admin leave keeps remaining admin healthy and synchronized, writer leave emits a durable left-the-group event for remaining members}`; `group_startup_rejoin_smoke_test.dart::GM-016 deleted removed-member state is not rejoined from stale pubsub state`; `member_removal_integration_test.dart::{GM-015 blocked creator leave keeps remaining-member sends healthy, voluntary leave rotation excludes leaver and remaining members send on rotated epoch}`; `group_edge_cases_smoke_test.dart::DTR-10 durable voluntary leave stops delivery and cleans leaver history`; TC-279-01 direct-caller census | Host integration-style / in-memory network plus generalized Plan-280 driver and FFI durable adapter | Existing semantic tests are GREEN except the old leaver-history assertion, which intentionally changes to the production cleanup contract. Removing the old source before caller migration is compile-RED -> GREEN after every caller uses one stable durable intent/notice, one native leave when allowed, terminal target cleanup, receiver timeline preservation, and exact last-admin refusal. | Route one caller to manual native+delete, omit or duplicate durable intent/notice/native work, retain leaver target history, or delete a valid receiver scenario -> the named driver evidence assertion, semantic test, or TC-279-01 red. | Exact four-file command; existing group registration/AUTO and `groups`. |
| TC-279-07 | A real writer voluntarily leaves a private three-party group through the durable path; peers converge on removal/timeline/key epoch while the leaver performs exact local cleanup. | Device scenario `private_voluntary_leave_convergence` (H-01); `group_multi_party_device_criteria_test.dart::{accepts H-01 exact durable exit evidence, rejects H-01 missing or duplicate durable exit phases}` | Three-party/device-lab / physical Android + two Android emulators, real relay, SQLCipher, Go bridge, crypto, and no-copy real-stack driver adapter | Existing scenario is GREEN through separate pre-broadcast + old cleanup but the new evaluator is RED for missing durable evidence -> GREEN after one durable action records one stable action/source/pending identity, prepare=1, notice attempt=1, native `group:leave`=1, terminal intent/pending absence, one receiver timeline row, target cleanup, and an unrelated local marker preserved. | Bypass durable intent, send notice/native twice, skip native leave, leave intent/pending work behind, delete unrelated data, or prevent peer re-key/convergence -> evaluator/scenario red. | Existing orchestrator scenario plus exact host evaluator command below. |
| TC-279-08 | A sole admin cannot leave through the durable path; no intent, notice, rotation, native leave, or mutation occurs, the group remains usable, and exact policy evidence is emitted. | Device scenario `gm015`; `group_multi_party_device_criteria_test.dart::{accepts GM-015 durable last-admin refusal evidence, rejects GM-015 post-authority durable or native work}` | Three-party/device-lab / same pinned Android topology, real relay, SQLCipher, and no-copy real-stack driver adapter | Existing scenario is GREEN through direct old guard but the new evaluator is RED for obsolete fields -> GREEN after coordinator status `blockedLastAdmin`, zero intent/pending/timeline rows, prepare/attempt/rotation/native counts all zero relative to pre-attempt baselines, unchanged epoch/roster, and post-refusal messages delivered. | Remove last-admin claim, enqueue an intent, prepare/attempt a notice, rotate/invoke native leave, mutate group/key/roster, or make messaging unusable -> evaluator/scenario red. | Existing orchestrator scenario plus exact host evaluator command below. |
| TC-279-09 | Strict Android proof roles load the exact promoted runtime config, exchange app-private signals without copying databases, and cannot uninstall until every verdict is host-captured; terminal acknowledgements never revisit an exited role. | `group_multi_party_runtime_config_test.dart`; `group_multi_party_launch_spec_test.dart::{keeps the harness alive until its role acknowledgement arrives, quiesces after all verdicts, then never revisits an acked role, leaves legacy and iOS verdict publication non-waiting}` | Host runner boundary / fake ADB transport plus the same live H-01/GM-015 runs | Live causal RED used defaults or lost a completed role's verdict -> GREEN after atomic config promotion, framed missing/present/error reads, all-verdict capture, held-role final sync, broker quiescence, and target-only terminal release. | Treat `run-as` error text as a file, consume a pending config, acknowledge one role early, perform ordinary fanout/read-back after release, or reuse stale signals -> focused runner test or live proof red. | Exact two-file runner command plus both required device scenarios. |

### Test Notes

- TC-279-01 must ban the exact declaration/import/call shape, not every method
  named `leaveGroup`; a test-domain convenience method may keep that name only
  if runtime evidence demonstrates one durable action and the source contract
  excludes manual broadcast/native/delete inside that wrapper.
- The new TC-279-03 Orbit test is a preservation sentinel: add and run it before
  the production edit, record that it passes against current behavior, then
  keep it and the existing Group Info selector green through the constant move.
- The H-01 durable driver must return/expose stable intent/source/pending
  identity, phase counters, and the rotation outcome required by the verdict.
  Receiver timeline delivery is preserved; leaver-local target history is
  deleted by the production cleanup contract. Do not pre-call
  `broadcastVoluntaryLeaveAndRotateKey`, because that would duplicate the live
  runner's notice phase.
- GM-015 must assert coordinator status `blockedLastAdmin`, zero native
  `group:leave`, and absence of any durable post-authority mutation; retire the
  old direct-broadcast/throw result fields.
- Strict Android `_writeVerdict` waits up to 20 minutes for its role-specific
  host-capture acknowledgement, exceeding the 15-minute host verdict barrier.
  The runner captures every verdict first, completes one held-role sync, stops
  and awaits the broker, then atomically releases roles target-only with no
  read-back. Legacy and iOS paths do not wait.

## Implementation Steps

1. Confirm Plan 280 remains Plan-green. Snapshot `git status --short` and record
   protected modern/native/database/device-harness baselines.
2. Add TC-279-01 and the TC-279-03 Orbit preservation selector. Run the source
   contract RED and both UI sentinels GREEN before production edits.
3. Extract/generalize the Plan-280 runner composition around injected
   repositories/callbacks. Keep its FFI/detached host adapter; add a no-copy
   adapter to `GroupMultiDeviceTestStack` using `stack.db`, fully bind strict
   cleanup dependencies, and migrate `GroupTestUser`, direct
   membership/startup/member-removal calls, and H-01/GM-015.
4. Add the positive/mutation-negative H-01/GM-015 evaluator tests and update
   the voluntary-leave host sentinel to require receiver timeline preservation
   plus empty leaver target history. Run the host migrations before deleting
   the old source.
5. Move `lastAdminLeaveBlockedMessage` unchanged to
   `group_exit_policy.dart`; remove obsolete imports and update only stale
   `group_message_listener.dart` documentation links.
6. Simplify `deleteGroupAndMessages` to mandatory strict dissolved-local
   semantics. Remove `Bridge`, the boolean/default, native branch, and branch
   conditionals in flow-event details. Update the exact 14 retained call sites
   inventoried above.
7. Delete `leave_group_use_case.dart`, its dedicated SUT test, and only
   the six named default-false/active branch tests from the delete-use-case
   test. Do not delete retargeted behavior proofs.
8. Run TC-279-01 GREEN, temporarily restore one exact forbidden import/call to
   demonstrate mutation re-red, revert it, and rerun.
9. Treat the first strict-Android H-01 transport/lifecycle failures as causal
   runner REDs. Add TC-279-09, make the bounded generic transport repair, and
   keep the product/evaluator evidence fail-closed until the exact verdicts
   survive host capture.
10. Run focused strict-delete/UI/durable/native/Go tests, all migrated host
   proofs, both pinned three-party scenarios, `runtime-roots`, `groups`, and
   justified `feature-host-all`; compare protected paths with their baselines.

## Risks And Blind Spots

- Hidden production selection of the default branch -> TC-279-01 repeats an
  exact call-site census and Stop-if prevents deletion if one appears.
- Last-admin copy could disappear with the source -> TC-279-03 locks both
  surfaces and exact behavior.
- Tests could be “fixed” by bypassing durable work -> TC-279-01/06 require no
  direct helper import/call or manual replacement, while TC-279-06/07/08
  measure stable durable identity, phase cardinality, and terminal state.
- Lifecycle / derived-state durability: TC-279-04 and device SQL-backed
  scenarios cover durable identity/retry/recovery.
- Sibling-surface consistency: TC-279-03 covers Group Info and Orbit.
- Destructive-action side effects: TC-279-02, TC-279-06, H-01, and GM-015
  preserve production-equivalent target cleanup, unrelated state, keys, and
  refusal safety; leaver-local target history is intentionally removed.
- Invariant re-verification under new transitions: TC-279-04/08 enforce exact
  membership and last-admin authority at the durable claim/native boundary.
- Android app-private lifecycle could erase evidence on test-process exit ->
  TC-279-09 holds all roles through host capture, quiesces the broker before
  terminal target-only acknowledgements, and the live runs require all three
  capture markers.

## Gate Cadence

- Per-plan closure: causal runtime-root contract; strict-delete, UI,
  durable/recovery/diagnostic, native/Go, and migrated host proofs;
  Android runner/config boundary; `runtime-roots`; `groups`;
  `feature-host-all`; H-01 and GM-015 on the pinned three-Android matrix.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the DTR Wave-3
  DTR-09/DTR-10/DTR-11 batch is complete or terminal, and once at final
  rollout/release closure.
- Shared tests outside feature/core globs:
  `test/unit/runtime_root_inventory_test.dart`,
  `test/integration/group_multi_party_device_criteria_test.dart`, and the two
  orchestrated `integration_test` scenarios use the exact commands below.

## Acceptance Gates

```bash
# Prerequisite and snapshot.
rg -n '^Status: Plan-green$' \
  Test-Flight-Improv/280-superseded-leave-local-history-coordinator-removal-tdd-plan.md
test ! -e \
  lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart
test ! -e test/shared/helpers/legacy_group_exit_coordinator_fixture.dart
git status --short

# Causal RED before production edits; expect non-zero for old artifacts/callers.
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR-10 retires dormant leaveGroup and default-false active-delete branch'

# Strict dissolved-local behavior.
flutter test --no-pub \
  test/features/groups/application/delete_group_and_messages_use_case_test.dart
flutter test --no-pub \
  test/features/groups/integration/group_delete_preserves_friends_and_dms_test.dart

# Last-admin copy and the two live surfaces.
flutter test --no-pub \
  test/features/groups/presentation/group_info_wired_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart

# Durable replacement, diagnostics, and recovery.
flutter test --no-pub \
  test/features/groups/application/group_exit_intent_coordinator_test.dart \
  test/features/groups/application/group_exit_intent_runner_test.dart \
  test/features/groups/application/group_exit_diagnostic_wiring_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart

# Retargeted host behavior proofs.
flutter test --no-pub \
  test/features/groups/integration/group_membership_smoke_test.dart \
  test/features/groups/integration/group_startup_rejoin_smoke_test.dart \
  test/features/groups/application/member_removal_integration_test.dart \
  test/features/groups/integration/group_edge_cases_smoke_test.dart
flutter test --no-pub \
  test/integration/group_multi_party_device_criteria_test.dart \
  --plain-name 'DTR-10 durable group exit criteria'

# Strict Android config, app-private broker, and terminal verdict capture.
flutter test --no-pub \
  test/integration/group_multi_party_launch_spec_test.dart \
  test/integration/group_multi_party_runtime_config_test.dart

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

# Registration/discovery and affected host lanes. The temporary index includes
# the coherent prerequisite-plan source removals without staging or mutating the
# user's shared dirty worktree.
DTR10_RUNTIME_ROOT_INDEX_DIR="$(
  mktemp -d "${TMPDIR:-/tmp}/dtr10-runtime-roots.XXXXXX"
)"
DTR10_REAL_INDEX="$(git rev-parse --git-path index)"
cp -- "$DTR10_REAL_INDEX" "$DTR10_RUNTIME_ROOT_INDEX_DIR/index"
GIT_INDEX_FILE="$DTR10_RUNTIME_ROOT_INDEX_DIR/index" git add -A -- \
  lib/features/groups/application/hydrate_groups_from_peers_use_case.dart \
  lib/features/groups/application/join_group_use_case.dart \
  lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart \
  lib/features/groups/application/leave_group_use_case.dart
GIT_INDEX_FILE="$DTR10_RUNTIME_ROOT_INDEX_DIR/index" \
  ./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --list-scenarios | rg -x 'private_voluntary_leave_convergence|gm015'

# Real three-party closure, fully automated and pinned to available Androids.
# Re-run the live matrix immediately before these commands; if IDs changed,
# replace all three IDs with explicitly discovered Android targets and record
# the resolved topology.
flutter devices --machine
adb devices
xcrun simctl list devices available
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario private_voluntary_leave_convergence \
  -d 21071FDF600CSC,emulator-5554,emulator-5556
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm015 \
  -d 21071FDF600CSC,emulator-5554,emulator-5556

# Hygiene.
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

## Device/Relay Proof Profile

- Profile: three-party/device-lab.
- Boundary being proven: real native leave, signed private-group notice,
  encrypted group traffic, recipient convergence/re-key, exact local cleanup,
  and sole-admin refusal/continued usability cannot be closed by host fakes.
- Live availability check:
  `flutter devices --machine; adb devices; xcrun simctl list devices available`
  -> physical Android Pixel 6 `21071FDF600CSC` (API 36), Android emulators
  `emulator-5554` (API 35) and `emulator-5556` (API 37), plus iOS targets.
- Required setup: pin
  `21071FDF600CSC,emulator-5554,emulator-5556`; use the existing automated
  multi-party runner, exact required `MKNOON_RELAY_ADDRESSES` value in the
  closure commands, isolated app/db state, and machine-read verdict files; no
  user taps.
- Two-peer default: expanded to three Android peers because both H-01 and
  GM-015 require creator/admin plus two members. iOS is not used because the
  behavior is not iOS-specific and the Android matrix is available.
- Closure role: required closure evidence.
- `FLUTTER_DEVICE_ID`: host selector only; all three explicit runner IDs remain
  required.
- Registration: existing orchestrator scenarios
  `private_voluntary_leave_convergence` and `gm015`; no new scenario or
  classifier row.
- Discovery command:
  `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios | rg -x 'private_voluntary_leave_convergence|gm015'`
  -> both names must be listed.
- Closure result: H-01 run `1785084448478` and GM-015 run `1785084590123`
  both passed on the pinned matrix with all three role verdicts and terminal
  host-capture markers. H-01 recorded one durable request/notice/native leave,
  receiver epoch `1 -> 2`, exact one-row leave timelines, terminal leaver
  cleanup, and unrelated identity preservation. GM-015 recorded
  `blockedLastAdmin`, unchanged epoch/roster, zero post-authority durable/native
  work, and successful post-refusal messages from both remaining writers.
- Deferred device work: relay endpoint availability is resolved at execution
  through the exact required environment value in the closure command. The
  displayed IDs are the planning snapshot, not immutable hardware requirements:
  execution must
  rediscover and explicitly pin an available Android three-peer topology. Only
  when that required topology is unavailable is the leg
  `N/A (target unavailable by project policy)`; do not substitute an iPhone or
  require manual interaction.

## Execution Interpretation And Done Criteria

- Expected RED: TC-279-01 fails because the old source/function/imports,
  default-false branch, dedicated test, and direct proof callers exist.
- Green sentinel: strict dissolved-local tests, both last-admin surfaces,
  durable restart/cleanup/diagnostic tests, H-01, and GM-015 remain semantically
  green through the new driver.
- Pre-existing dirty tree / known failure: snapshot and preserve unrelated
  changes; no failure is accepted without before/after reproduction outside
  this plan's diff.
- Environment blocker: none. Plan 280's prerequisite and the live pinned
  Android/relay matrix were both resolved during execution.
- Scope drift: any live false-branch caller, modern/native/schema change, lost
  valid proof, or need for a second fixture blocks completion.

- [x] Plan 280 is Plan-green before this plan starts.
- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] All old direct proof callers are migrated; valid host/device scenarios
      remain.
- [x] Exact last-admin copy and behavior pass on both UI surfaces.
- [x] Strict dissolved cleanup, modern durability/diagnostics, native/Go, H-01,
      and GM-015 gates pass.
- [x] Existing harness registration/discovery is verified.
- [x] No schema, migration, data, key-generation, native, or protocol change
      occurred.
- [x] `./scripts/check_flutter_analyze_strict.sh` has no new issues;
      `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/unit/runtime_root_inventory_test.dart --plain-name 'DTR-10 retires dormant leaveGroup and default-false active-delete branch'`
  with the Plan 280 prerequisite already satisfied.
- Preservation command:
  `./scripts/run_test_gates.sh groups`.
- Manual registration: the source test uses existing `runtime-roots`, host
  files are AUTO under `feature-host-all`; the curated files remain in
  `GROUP_TESTS`, while `group_delete_preserves_friends_and_dms_test.dart` and
  `member_removal_integration_test.dart` run by their exact direct commands.
  Both device scenarios already exist in the orchestrator. The post-run strict
  Android wrapper
  `integration_test/group_multi_party_device_real_android_harness.dart` is now
  registered as a `DTR-10 / QA` external runtime root, and the fully staged
  copied-index repository-manifest selector passed with `+1`. The final
  repository-wide `runtime-roots` rerun then passed all 20 tests under a fully
  staged temporary index. This closes the bookkeeping gap without reopening
  the accepted device verdicts or Plan-green status.
- Migration: none. DB v103/v104, existing rows, keys, and generations are
  protected unchanged.
- Boundary closure: host durable/UI/native/Go proof plus H-01 and GM-015 on
  pinned physical-Android + two-emulator topology.
- Unresolved evidence: none. The final matrix, relay, per-role SQLCipher
  verdicts, and terminal host-capture markers are recorded above.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-26 | prerequisite closure | Plan 280 status; durable surface harness; roadmap/index | Plan 280 is Plan-green; its obsolete coordinator and legacy fixture are absent, and its durable proof migration is recorded | The authorized Plan 279 boundary remains unchanged and is now execution-ready | none | rerun source census and live device matrix, then execute TC-279-01 RED |
| 2026-07-26 | review and causal contract | Plan 279; `runtime_root_inventory_test.dart`; Group Info/Orbit sentinels | Independent review moved from `plan-fixes-required` to `ready`; TC-279-01 failed on the old source/callers, then passed after retirement; a restored forbidden import re-failed before the GREEN restoration | Removal and preservation bets are causally locked; both UI sentinels passed before and after the copy rehome | none | migrate callers and retire the old branch/source |
| 2026-07-26 | implementation | old leave source/test; mandatory local delete; policy/listener/UI callers; shared durable driver; host/device adapters and evaluators | Old source/test and six branch-only tests removed; mandatory strict-local signature migrated; host driver uses the production coordinator/runner and device adapter uses the live SQLCipher repositories | No old import/boolean/direct manual path remains; last-admin copy has one byte-identical owner | none | run focused and lane gates |
| 2026-07-26 | focused host preservation | strict delete/preservation, Group Info/Orbit, durable/recovery/diagnostics, migrated host proofs, evaluator, Dart/native/Go | Strict delete/preservation `7/7`; UI `198/198`; durable/recovery `59/59`; migrated host proofs `133/133`; evaluator full suite `569/569` and DTR-10 mutation subset `4/4`; exact Dart/Go leave tests passed | Strict cleanup, durable identity/cardinality, refusal behavior, native leave, and unrelated-data floors are green | none | run curated lanes and device proofs |
| 2026-07-26 | curated lanes | isolated `runtime-roots`; `groups`; `feature-host-all` | `runtime-roots` passed 19 tests with trustworthy inventory/no drift; `groups` passed 3,234 Flutter tests plus Go/relay gates; `feature-host-all` passed 815/815 selectors | Required per-plan cadence is green; full `host-all` intentionally deferred to the wave/release cadence | none | execute live H-01/GM-015 |
| 2026-07-26 | Android runner causal repair | Documents runtime config; ADB framed file transport; app-private broker; verdict terminal barrier; launch/runtime tests | Early live runs rejected defaults, malformed/missing reads, and a role uninstall before host capture; bounded repair passed launch/broker `25/25`, runtime-config `7/7`, focused analysis, and counterexample review | Exact per-role config and verdicts now survive without DB copies, early ACK, read-back, or legacy/iOS behavior change | none | rerun both live scenarios from clean installs |
| 2026-07-26 | live device closure | H-01 run `1785084448478`; GM-015 run `1785084590123`; Pixel 6 + API 35/API 37 emulators | Both orchestrator verdicts `ok: true`; all six role tests and all six host-capture markers passed | H-01: exact one request/prepare/notice/native leave, receiver epoch `1 -> 2`, terminal cleanup and unrelated identity preserved. GM-015: `blockedLastAdmin`, zero post-authority work, unchanged epoch/roster, and continued two-writer delivery | none | final hygiene and graph impact |
| 2026-07-26 | closure hygiene and graph | all Plan-279-owned Dart files; protected paths; `graphify-arch` | Strict analyzer: no issues; format 33 files/0 changed; `git diff --check` clean; protected modern exit/DB/native/platform/Go paths diff-clean; incremental graph refresh and affected query completed at fingerprint `776163ea2b77684f` | Scope guard is respected and the graph is current | none | Plan-green |
| 2026-07-27 | post-run bookkeeping closure | strict Android wrapper runtime-root registration; repository-wide aggregate `runtime-roots` | Wrapper registered as `DTR-10 / QA`; copied-index repository-manifest selector passed `+1`; final fully staged temporary-index `runtime-roots` passed `20/20` | The registration and aggregate inventory are green; device and Plan-green evidence remain accepted | none | Complete |
