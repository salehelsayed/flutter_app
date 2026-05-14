# GE-017 Property Random Membership Operations Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 17:53 CEST | Role: Arbiter completed | Files inspected since last update: reviewer sufficiency review, full plan, arbiter classifications. Decision/blocker: no structural blockers remain; GE-017 plan is safely reusable and execution-ready. Next action: execute only this GE-017 plan when implementation is requested.
- 2026-05-13 17:53 CEST | Role: Arbiter started | Files inspected since last update: reviewer sufficiency review and full plan. Decision/blocker: classify reviewer findings into structural blockers, incremental details, and accepted differences. Next action: record final arbiter decision.
- 2026-05-13 17:52 CEST | Role: Reviewer completed | Files inspected since last update: full draft plan and mandatory-section checklist. Decision/blocker: sufficient as-is; no structural blocker found. Incremental details are limited to implementation-time naming/import choices and should not broaden scope. Next action: Arbiter classification.
- 2026-05-13 17:52 CEST | Role: Reviewer started | Files inspected since last update: full draft plan. Decision/blocker: review will check mandatory sections, deterministic regression contract, host-vs-device proof choice, and stop rule. Next action: record sufficiency findings and required adjustments.
- 2026-05-13 17:50 CEST | Role: Planner completed | Files inspected since last update: Evidence Collector findings and current plan draft. Decision/blocker: drafted a narrow `implementation-ready` GE-017 plan with deterministic seeds, explicit invariants, host proof as required row proof, and conditional production/Go escalation only after a red invariant. Next action: run Reviewer sufficiency pass.

## Execution Progress

- 2026-05-13 18:18 CEST | Phase: Local execution fallback completed | Files inspected/touched since last update: `test/features/groups/integration/group_messaging_smoke_test.dart` and this GE-017 plan. Decision/blocker: no blocker remains; GE-017 closed as tests-only host property proof with no production, Go, device-harness, or simulator changes. Evidence: final `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart` passed, final `dart analyze test/features/groups/integration/group_messaging_smoke_test.dart` passed with no issues, final `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-017'` passed (`+1`), and final `./scripts/run_test_gates.sh groups` passed (`+157`). Next action: closure audit must update source matrix row GE-017, breakdown ledgers, and test inventory with this concrete evidence.
- 2026-05-13 18:15 CEST | Phase: Local QA review completed | Files inspected/touched since last update: GE-017 helper region in `test/features/groups/integration/group_messaging_smoke_test.dart`. Decision/blocker: tightened duplicate-delivery operation to reset `network.duplicateOnDeliver` in `try/finally`; no model or product invariant gap found. Next action: rerun focused selector and named group gate on final code.
- 2026-05-13 18:14 CEST | Phase: Local proof green | Files inspected/touched since last update: `test/features/groups/integration/group_messaging_smoke_test.dart`. Command/status: first post-implementation GE-017 focused selector passed (`+1`); scoped analyzer, format, `git diff --check`, full `group_messaging_smoke_test.dart` (`+32`), and `./scripts/run_test_gates.sh groups` (`+157`) passed before the final duplicate-mode cleanup guard. Decision/blocker: proof shape is correct; run final checks after the guard.
- 2026-05-13 18:11 CEST | Phase: Local implementation completed | Files inspected/touched since last update: `test/features/groups/integration/group_messaging_smoke_test.dart`. Decision/blocker: added deterministic GE-017 property proof with seeds `17017`, `17018`, and `17019`; A/B/C/D model state; add/remove/readd/send/offline/online/rotate/restart/duplicate-send operations; seed/step/operation failure context; member/device uniqueness, entitlement, duplicate-message, inactive-send, convergence, and final-recovery invariants. Next action: run focused selector and supporting gates.
- 2026-05-13 18:01 CEST | Phase: Local fallback Executor started | Files inspected/touched since last update: this GE-017 plan, `git status --short`, `test/features/groups/integration/group_messaging_smoke_test.dart`, target fake helper diffs. Command/status: no separate spawn tool is exposed in this session and prior spawned Executor `019e220d-438e-7141-b99a-f30fbcb9a877` already closed as `spawn_or_tool_failure`; using the skill's bounded local sequential fallback instead of relaunching the same no-progress child. Decision/blocker: concrete plan remains executable and no partial child code exists for GE-017. Next action: add the GE-017 host fake-network property proof in the allowed integration test file only, escalating to helper/production files only if required by a focused failure.
- 2026-05-13 17:59 CEST | Phase: Executor no-progress closed | Files inspected/touched since last update: this GE-017 plan, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `test/shared/fakes/in_memory_group_repository.dart`, and `test/shared/fakes/in_memory_group_message_repository.dart`. Command/status: spawned Executor `019e220d-438e-7141-b99a-f30fbcb9a877` remained running through two bounded waits and was closed; `rg -n "GE-017 seeded|Ge017|ge017|GE-017"` found no assigned GE-017 implementation outside this plan. Decision/blocker: classify first Executor attempt as `spawn_or_tool_failure`; no code/test delta from that child is available to review. Next action: start a fresh execution/QA worker with the same concrete plan rather than relaunching the exact same no-progress executor step.
- 2026-05-13 17:55 CEST | Phase: Controller contract extracted | Files inspected/touched since last update: this GE-017 plan, execution-orchestrator skill, `git status --short`, GE-017 red selector output, and current dirty diffs for likely target files. Command run: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-017'` failed with exit 79, `No tests ran. No tests match "GE-017"`. Decision/blocker: expected red/missing-proof baseline; no blocker. Next action: spawn fresh Executor for GE-017 implementation only.

## Final Verdict

GE-017 is accepted/closed as a tests-only gap-closure session. The repo now has exact deterministic host fake-network property proof for random private-group membership operations, with no production, Go, simulator, or device-harness changes required. Closure updated the source matrix, session breakdown ledgers, and test inventory with the concrete file/test/gate evidence below; residual-only none for GE-017.

## Execution Evidence

Implementation evidence:

- Added `test/features/groups/integration/group_messaging_smoke_test.dart::GE-017 seeded random membership operations preserve invariants`.
- Added local helper `_runGe017Seed(...)` in `test/features/groups/integration/group_messaging_smoke_test.dart`, using fixed seeds `17017`, `17018`, and `17019`, 30 operations per seed, deterministic timestamps, and A/B/C/D model state.
- The proof generates bounded add/remove/readd/send/offline/online/rotate/restart/duplicate-send paths and records seed, step, active set, online set, and operation log in failure context.
- The invariant oracle checks duplicate active member/device rows, no non-entitled plaintext, exact-once message persistence, inactive-send no-publish/no-local-mutation behavior, active key/member convergence, held-delivery recovery, final recovery, and no uncaught operation panic.
- No production Dart, Go, simulator, runner, or device-harness file changed for GE-017; the source-row contract is host fake-network/model proof and simulator proof is N/A.

Validation evidence:

- Red/missing baseline: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-017'` failed with exit 79, `No tests ran. No tests match "GE-017"`.
- Final format: `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart` passed.
- Final analyzer: `dart analyze test/features/groups/integration/group_messaging_smoke_test.dart` passed with no issues.
- Final focused proof: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-017'` passed (`+1`).
- Final named group gate: `./scripts/run_test_gates.sh groups` passed (`+157`).

## Evidence Collector Findings

- Source matrix row GE-017 is P0/Open and requires `Property test random membership operations preserve invariants` with a model containing A/B/C/D, random add/remove/readd/send/offline/online/rotate steps, and expected invariants: no unauthorized decrypt, no entitled message loss after recovery, no duplicate active membership, and no panics.
- Breakdown row 175 and detailed row 2059 classify GE-017 as `needs_code_and_tests` / `implementation-ready`, with row-owned missing proof and likely files in fake-network helpers, group integration tests, application seams, and Go pubsub/inbox seams.
- `rg -n "GE-017|ge017|Property test random membership operations"` found no current GE-017 runtime/test/harness implementation outside docs and this plan. The gap is repo-owned, not docs-only and not already covered.
- Nearby GE-005 through GE-015 closures show the accepted pattern: add exact fake-network host proof first, add criteria/device proof only when the row is scenario-specific device relay behavior, then run focused selectors and the Group Messaging Gate. GE-014 was accepted tests-only; GE-015 needed code/tests. GE-017 should start host-side and only touch production after the deterministic property proof exposes a concrete bug.
- `test/features/groups/integration/group_messaging_smoke_test.dart` already contains exact GE-005 through GE-015 host proofs and helper patterns for A/B/C setup, remove/re-add, offline/partition, restart, key rotation, durable inbox recipient inspection, duplicate live delivery, and same-user duplicate membership checks.
- `test/shared/fakes/fake_group_pubsub_network.dart` supports subscribe/unsubscribe, held deliveries, release in original or reverse order, duplicate delivery, delivery failure, delivery delays, and a random drop hook. The current random drop hook uses an unseeded `Random()`, so GE-017 should not rely on that hook for deterministic property proof unless the helper is extended to accept a seed.
- `test/shared/fakes/group_test_user.dart` supports create/add/remove/broadcast member events, bridge-backed sends, same-user devices, restart with persisted state, subscribe/unsubscribe, and repository-backed state inspection. These seams are enough to build a deterministic random operation driver without simulator proof.
- Direct application seams relevant to invariants include `send_group_message_use_case.dart` sender membership/device authorization and durable recipient calculation, `group_message_listener.dart` membership system-message application and removed-member handling, `rotate_and_distribute_group_key_use_case.dart` fail-closed recipient key distribution, `drain_group_offline_inbox_use_case.dart` replay authorization/dedupe, repository message/member dedupe behavior, and Go `pubsub.go` / `group_inbox.go` validation and recipient metadata if a red proof points below Flutter.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define `./scripts/run_test_gates.sh groups` as the named host gate for group send/receive/retry/resume/invite behavior. `integration_test/group_recovery_e2e_test.dart` is nightly/simulator-bound; `group_multi_device_convergence_test.dart` is optional/manual host proof. GE-017's source row says N/A for simulator proof, so host fake-network proof is the required row proof unless implementation changes real bridge/Go behavior.

## Reviewer Sufficiency Review

- Sufficiency: sufficient as-is for implementation.
- Missing files/tests/gates: none structurally. The plan names the exact source row, fake-network helpers, direct group integration tests, direct application seams, optional Go seams, focused selector, supporting host suites, Group Messaging Gate, format, analyzer, and Go escalation command.
- Stale or incorrect assumptions: none found. The plan correctly treats current code/tests as authoritative and keeps existing GE-005 through GE-015 rows as patterns, not closure evidence.
- Overengineering: no structural overengineering. The bounded fixed-seed property proof is appropriate for GE-017; it avoids unbounded fuzzing, long soak, and simulator orchestration.
- Decomposition: sufficient. The first implementation step is a red/missing focused selector, followed by one model-backed host test and conditional narrow fixes only if the proof exposes a concrete invariant violation.
- Minimum needed to make sufficient: no plan patch required before arbitration. Implementation-time details such as helper class names, `dart:math` imports, and exact seed count can be handled within the stated guardrails.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: helper class names, exact import placement, and final operation-count tuning can be decided during implementation without changing the plan.
- Accepted differences: no simulator/device proof is required for GE-017 unless implementation touches real bridge/device/Go behavior; GE-018, GE-019, GE-020, and concurrent-admin behavior stay out of scope; source matrix, breakdown ledger, and test inventory updates stay out of this plan session.
- Stop rule: no structural blocker was found, so planning stops here.

## Final Planning Output

- Final verdict: execution-ready.
- Final plan: add a bounded deterministic seeded GE-017 host property proof first, then make only the smallest production or Go fix if that proof exposes a concrete invariant violation.
- Structural blockers remaining: none.
- Incremental details intentionally deferred: exact helper names, exact seed operation count if runtime forces tuning, and precise production file selection after red proof.
- Accepted differences intentionally left unchanged: host fake-network proof is the required row proof; no real-device relay scenario, no envelope tampering fuzzer, no key-rotation-only campaign, no long soak, and no closure-doc update.
- Exact docs/files used as evidence: GE-017 source matrix row, breakdown rows 175/2059, nearby GE-005 through GE-015 closure notes/plans, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `test/shared/fakes/group_test_user.dart`, direct group application seams, `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_multi_device_real_harness.dart`, `go-mknoon/node/pubsub.go`, and `go-mknoon/node/group_inbox.go`.
- Why safe to implement now: the scope is one row, the regression-first contract is explicit, the required invariants and failure interpretation are concrete, tests/gates are named, production/Go escalation is conditional, and later property/soak rows remain explicitly out of scope.

## real scope

GE-017 owns one deterministic property-style host proof for random private-group membership operations on a four-user model A/B/C/D.

In scope:

- Add or verify an exact GE-017 regression named `GE-017 seeded random membership operations preserve invariants`, preferably in `test/features/groups/integration/group_messaging_smoke_test.dart` so it stays inside the existing Baseline and Group Messaging gates.
- Implement the smallest test-support code needed for a deterministic operation driver, model oracle, and invariant assertions. Keep helper code local to the test unless `GroupTestUser` or `FakeGroupPubSubNetwork` needs a small reusable seam.
- Exercise generated add/remove/readd/send/offline/online/rotate steps with fixed seeds and record the seed, step index, operation, active-membership model, and expected delivery set in failure messages.
- Touch production Dart or Go only if the new GE-017 red proof exposes a concrete invariant violation in current behavior.

Out of scope:

- Do not close GE-016, GE-018, GE-019, GE-020, broad soak rows, envelope tampering fuzzing, concurrent admin conflict resolution, or real-network relay harness parity.
- Do not update the source matrix, breakdown ledger, test inventory, closure docs, or unrelated implementation files in this plan session.

## closure bar

GE-017 is good enough when a reusable implementation session can prove, with deterministic seeds, that randomized membership churn preserves these invariants:

- `No unauthorized decrypt`: a user who is inactive at a send step never persists that message after live delivery, held delivery release, durable replay, restart, or final recovery. If an inactive sender attempts to send, `sendGroupMessageViaBridge` returns `unauthorized`, does not publish, and does not create durable inbox custody.
- `No entitled message loss after recovery`: for every successful send, the expected recipients are exactly the active members at send time excluding the sender. Offline/held recipients may miss live delivery, but after online recovery, held-delivery release, topic rejoin, and inbox drain, each expected recipient has exactly one copy.
- `No duplicate active membership`: every local repo has at most one active row per peer, D can be re-added without duplicate active rows, same logical member devices remain under one member row, and active device IDs are unique within a member.
- `No panics`: the property driver catches no uncaught exception from add/remove/readd/send/offline/online/rotate/recovery paths. Any exception fails the test with seed and operation context.
- `Key/membership convergence`: after successful rotate and final recovery, active members converge on the model active set and latest key epoch; inactive users do not regain group access from stale local state.

The property must be deterministic and replayable. Minimum proof is three fixed seeds, for example `17017`, `17018`, and `17019`, with at least 30 operations per seed. A future implementer may reduce only if runtime is prohibitive and the failure logs still include a replayable seed and operation list.

## source of truth

- Current code and tests win over stale docs.
- Source matrix row GE-017 defines the row behavior and expected invariants.
- Breakdown row 175 and detailed row 2059 define this session as `needs_code_and_tests` / `implementation-ready` and point to this plan.
- `scripts/run_test_gates.sh` is the execution source of truth for named gates; `Test-Flight-Improv/test-gate-definitions.md` documents the intent.
- Existing GE-005 through GE-015 proofs are implementation patterns only. They do not close GE-017 because none performs seeded random membership operations against an explicit model oracle.

## session classification

`implementation-ready`

The exact GE-017 property proof is absent, and the missing random-operation proof is repo-owned. The first deliverable is test/test-helper code; product code changes are conditional on the new proof finding a real invariant failure.

## exact problem statement

The repo has many fixed-path group membership tests, but it lacks a model-backed randomized proof that arbitrary sequences of add, remove, re-add, send, offline, online, and rotate operations preserve membership and message-delivery invariants. Fixed examples can miss state-machine bugs where stale local state, duplicate member rows, key-epoch drift, duplicate delivery, or replay order causes an unauthorized peer to see plaintext or an entitled peer to miss a message after recovery.

User-visible behavior that must improve: private group chat must remain reliable and access-controlled under churn, not only under the scripted GE-005 through GE-015 paths.

Behavior that must stay unchanged: existing exact GE proofs, durable inbox fallback behavior, key-promotion fail-closed behavior, same-user device handling, removed-member exclusion, and dedupe semantics.

## files and repos to inspect next

Primary implementation/test files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_multi_device_convergence_test.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`

Production Dart seams, only if GE-017 proof fails for a product reason:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`

Go seams, only if the failure is below Flutter bridge/app logic:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/group_inbox_test.go`

Gate definitions:

- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- GE-005 through GE-008 in `group_messaging_smoke_test.dart` cover remove/re-add loops, offline removed member catch-up, offline observer catch-up, and send storms.
- GE-009 through GE-011 cover partition recovery and durable inbox fallback for zero/partial live topic peers.
- GE-012 and `group_multi_device_convergence_test.dart` cover same-user multi-device duplicate-membership and transport binding behavior.
- GE-013 covers device revocation send authorization.
- GE-014 covers restarted re-added member invite/key recovery.
- GE-015 covers admin restart during mutation fanout and honest retry status.
- `group_membership_smoke_test.dart` covers fixed membership mutation and replay cases, including remove/offline/restart scenarios.
- `group_resume_recovery_test.dart` covers restart/rejoin, inbox drain, cursor replay, and partition-heal recovery paths.
- Go `pubsub.go` / node tests cover validator membership, active-device uniqueness, stale config/key rejection, and no-panic validator behavior.

Missing: no existing test generates seeded random operation sequences, maintains an independent membership/message model, and checks GE-017 invariants after every step and after final recovery.

## regression/tests to add first

Add the regression before product changes:

```bash
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-017'
```

Expected first red result before implementation: no matching test. After adding the property test, failures must include seed and step context and are interpreted as either a test-model bug or a real invariant violation.

Recommended test shape:

- Test name: `GE-017 seeded random membership operations preserve invariants`.
- Users: A/Alice, B/Bob, C/Charlie, D/Dana.
- Initial state: A/B/C active in one private chat with epoch 1; D is known to the driver but inactive until an add/re-add operation.
- Seeds: at least `17017`, `17018`, `17019`.
- Operations: randomly choose from add D, remove active non-admin, re-add inactive member, active send, stale/inactive send attempt, offline active member, online inactive/offline member, release held deliveries, drain inbox, restart one user, and rotate key.
- Oracle state: track active peers, offline peers, current key epoch, sent message expectations, removed windows, per-user persisted messages, and per-user local member rows.
- Check invariants after each operation and again after final recovery.

Host fake-network proof is the required proof for this property row because the source matrix marks simulator proof as N/A and the row asks for a model/fake-network random operation property. Device proof would be weaker for this row if it is non-deterministic or not seed-replayable.

## step-by-step implementation plan

1. Reconfirm the red/missing selector with `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-017'`.
2. Add a local GE-017 helper region in `group_messaging_smoke_test.dart`: `Ge017Model`, `Ge017Operation`, `Ge017MessageExpectation`, and assertion helpers. Keep it local unless it becomes unreadable.
3. If the existing fake network needs deterministic random drop behavior, add a seedable constructor or setter to `FakeGroupPubSubNetwork`; otherwise avoid the unseeded `dropRate` hook and use explicit subscribe/unsubscribe/hold/release operations.
4. Build the initial A/B/C group with epoch 1 using existing GE setup patterns. Keep D created but inactive until the operation stream adds or re-adds D.
5. Generate deterministic operation lists per seed. Log each operation as a compact string so a failure can be replayed without re-running all seeds.
6. Implement operations using existing helper seams:
   - `add/readd`: save member state, broadcast `member_added` / `members_added`, subscribe the user if online, and save current key only when model says the member is entitled.
   - `remove`: call `removeMember`, remove from active model, unsubscribe or hold removed user, and rotate key when the operation includes rotate.
   - `send`: call `sendGroupMessageViaBridge`; expected recipients are active peers at send time excluding sender.
   - `inactive send`: intentionally attempt a send from inactive local state and assert `unauthorized` with no publish/inbox mutation.
   - `offline/online`: use `unsubscribeFromGroup`, `subscribeToGroup`, held deliveries, and `drainGroupOfflineInbox` where needed to model live loss plus durable recovery.
   - `restart`: use `restartWithPersistedState`, restart the listener, and re-subscribe only if the model says the user is online and active.
   - `rotate`: use `rotateAndDistributeGroupKey` with deterministic bridge responses; save/apply the resulting key only to active entitled peers and assert active peers converge.
7. After every operation, assert model invariants: unique active members, no inactive plaintext for GE-017 message IDs, no duplicate message IDs per repo, expected durable recipients, no unauthorized send side effects, and latest-key convergence for active online peers when applicable.
8. At the end of each seed, bring all model-active users online, release held deliveries, drain durable inboxes, restart one active peer, and assert each successful message is present exactly once for entitled peers and absent for non-entitled peers.
9. If the GE-017 property fails because the test model does not match established product rules, adjust the model and document the product rule in test comments only where needed.
10. If the property exposes a real product bug, make the smallest fix in the direct seam named by the failure. Do not add broad architecture or a new queue unless a concrete invariant requires it.
11. If Dart changes cross into Go bridge/pubsub behavior, add or update focused Go tests in `go-mknoon/node` before changing `pubsub.go` or `group_inbox.go`.
12. Run focused selector, direct supporting suites, scoped analyzer/format, and the named group gate. Stop after GE-017 code/test evidence; closure docs are not part of this session.

Stop early if the new property proof passes with test/test-helper code only. In that case, GE-017 closes as tests/harness code without production runtime changes.

## risks and edge cases

- Randomized tests can become flaky if they depend on wall-clock timing or unseeded randomness. Use fixed seeds, deterministic timestamps, and explicit waits with failure context.
- A test-model bug can misclassify valid product behavior as a failure. Cross-check each failed operation against GE-005 through GE-015 rules before changing production code.
- Offline users must not be treated as inactive members. Offline active users are still entitled and must recover via held delivery or inbox drain.
- Removed users can retain stale local state. The invariant is that stale state cannot send successfully or render post-removal plaintext.
- Re-adding D or Charlie must not create duplicate active rows or duplicate active devices.
- Duplicate live delivery should dedupe by message ID; use `network.duplicateOnDeliver = true` for at least one deterministic seed segment if runtime permits.
- Key rotation during offline windows can create false failures unless the test explicitly models key distribution or durable repair.
- The repo is currently dirty in many related files. Implementation must inspect diffs before editing and preserve unrelated changes.

## exact tests and gates to run

Minimum direct proof:

```bash
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-017'
```

Direct supporting host suites for the touched area:

```bash
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/integration/group_multi_device_convergence_test.dart
```

Named gate required if group behavior or helper code changes:

```bash
./scripts/run_test_gates.sh groups
```

Formatting and analysis, adjusted to actual touched files:

```bash
dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/group_test_user.dart
dart analyze test/features/groups/integration/group_messaging_smoke_test.dart test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/group_test_user.dart
```

If production Dart files change, add those exact paths to format/analyze and run their direct tests, for example:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart
```

If Go `pubsub.go` or `group_inbox.go` changes, run:

```bash
cd go-mknoon && go test ./node
```

Device/simulator proof is not required for GE-017 because the row is a deterministic model/fake-network property and simulator proof is N/A in the matrix. Only add a simulator command if implementation changes `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_multi_device_real_harness.dart`, or real bridge/Go behavior in a way the host property cannot exercise.

## known-failure interpretation

- The initial `--plain-name 'GE-017'` selector may fail with "No tests ran" before implementation; that is expected red/missing-proof evidence.
- After the GE-017 test exists, any GE-017 failure is not a known failure. Classify it by seed and operation: model bug, helper nondeterminism, or product invariant violation.
- Existing unrelated dirty-worktree failures in broad gates must not be counted as GE-017 regressions. Re-run the direct GE-017 selector and the touched-file tests to isolate.
- If `./scripts/run_test_gates.sh groups` fails outside GE-017, capture the failing file/test name, inspect whether GE-017 touched that behavior, and do not mark GE-017 done unless the focused selector and all touched-area tests pass.
- Non-deterministic pass/fail means the property harness is insufficient. Fix determinism before treating any product change as validated.

## done criteria

- `GE-017 seeded random membership operations preserve invariants` exists and is deterministic by seed.
- The test executes add/remove/readd/send/offline/online/rotate operations against A/B/C/D and an independent model oracle.
- Failure output includes seed, step, operation, active set, online/offline set, and message expectation context.
- All GE-017 invariants pass after each operation and after final recovery.
- Direct focused GE-017 selector passes.
- Direct supporting host suites and `./scripts/run_test_gates.sh groups` pass, or any unrelated pre-existing failures are explicitly isolated with direct GE-017 proof still green.
- Production or Go changes, if any, have focused tests and scoped analyzer/Go proof.
- No source matrix, breakdown ledger, test inventory, or unrelated files are changed as part of this plan-writing session.

## scope guard

Do not turn GE-017 into a general fuzzer framework, long soak, simulator orchestration task, envelope tampering task, concurrent-admin conflict resolver, or broad key-rotation campaign. Keep one deterministic property test and the smallest fixes it forces.

Do not use unbounded random seeds in CI. Do not let a passing real-device scenario substitute for the seed-replayable host property. Do not update docs/ledgers during implementation unless a separate closure task asks for it.

## accepted differences / intentionally out of scope

- GE-018 envelope tampering remains separate; GE-017 may observe unauthorized plaintext but does not mutate cryptographic envelopes.
- GE-019 random key-rotation access-window proof remains separate; GE-017 includes rotate operations only enough to preserve membership-operation invariants.
- GE-020 long soak remains separate; GE-017 uses bounded fixed seeds and operation counts.
- GE-016 concurrent admin mutation remains separate; GE-017 should use one admin actor unless a generated operation explicitly promotes/demotes within existing product rules.
- Real relay/device proof is intentionally not required for this row unless host proof exposes a lower-level bridge/Go issue.

## dependency impact

GE-017 gives later property and soak rows a deterministic oracle pattern. GE-018, GE-019, and GE-020 should reuse the seed logging, operation model, and invariant assertion style, but they must remain separate sessions with their own source-row contracts.

If GE-017 changes production authorization, membership application, key rotation, or replay behavior, later GE rows must re-check their assumptions against the new invariant proof. If GE-017 lands tests-only, later work can treat the property harness as a guardrail without assuming new runtime behavior.
