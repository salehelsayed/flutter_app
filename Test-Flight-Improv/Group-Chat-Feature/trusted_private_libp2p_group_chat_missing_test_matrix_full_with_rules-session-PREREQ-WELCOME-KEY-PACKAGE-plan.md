Status: qa_passed

# PREREQ-WELCOME-KEY-PACKAGE Execution Plan

## Planning Progress

- 2026-05-01 18:37:26 CEST - Role: Recovery Planner completed - Files inspected since last update: implementation-session-pipeline-orchestrator skill, implementation-plan-orchestrator skill, this plan, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/main.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `test/shared/fakes/group_test_user.dart`, focused listener/UI pending-invite tests. - Decision/blocker: QA blocker is a same-session implementation-owned recovery item; next execution must wire a trusted local `ownKeyPackageId` source through production listener and pending-accept seams without weakening package validation or using the payload recipient id as local identity. - Next action: run fresh Execution+QA against the Recovery Execution Contract below.
- 2026-05-01 17:50:00 CEST - Role: Arbiter completed - Files inspected since last update: reviewer-adjusted plan content, source rows EK-011/EK-012/DB-012, pending invite repository/migration seams, invite payload/policy/send/handle/accept code, direct invite tests, current DB version. - Decision/blocker: no structural blockers remain; a narrow repo-owned implementation is safe now. - Next action: run isolated Execution+QA for this plan.
- 2026-05-01 17:48:00 CEST - Role: Reviewer completed - Files inspected since last update: draft plan, existing accepted PREREQ plans, invite replay/consumption tests, pending-invite persistence helpers. - Decision/blocker: plan is sufficient with adjustments; it must require durable key-package tombstones, a current migration-number check, and explicit EK-012 residual handling. - Next action: patch plan and run Arbiter classification.
- 2026-05-01 17:45:00 CEST - Role: Planner completed - Files inspected since last update: `group_invite_payload.dart`, `group_invite_policy.dart`, `send_group_invite_use_case.dart`, `handle_incoming_group_invite_use_case.dart`, `accept_pending_group_invite_use_case.dart`, pending invite repository/helper/migrations, direct invite tests. - Decision/blocker: implement first-class welcome/key-package admission inside the existing signed encrypted invite contract, plus a durable replay/freshness tombstone owner. - Next action: run Reviewer pass.
- 2026-05-01 17:40:00 CEST - Role: Evidence Collector completed - Files inspected since last update: breakdown rows for PREREQ-WELCOME-KEY-PACKAGE, EK-011, EK-012, DB-012; source matrix rows EK-011/EK-012; inventory entries; prior PREREQ accepted plans; migration list through 063. - Decision/blocker: current repo has device-bound metadata and signed inline group-key invites, but no first-class welcome/key-package model, package freshness validator, or package-level replay tombstone. - Next action: draft plan.

## Execution Progress

- 2026-05-01 18:55:51 CEST - Phase: Final QA Reviewer completed - Files inspected: this plan, the breakdown, source matrix/inventory EK-011/EK-012/DB-012 entries, `lib/features/groups/domain/models/group_welcome_key_package.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_invite_policy.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/main.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, tombstone model/helper/migration/repository seams, and focused listener/UI/domain/application tests. - Command/evidence: targeted `dart analyze lib/features/groups/domain/models/group_welcome_key_package.dart lib/features/groups/presentation/screens/group_list_wired.dart lib/features/orbit/presentation/screens/orbit_wired.dart test/features/groups/domain/models/group_welcome_key_package_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/presentation/group_list_wired_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart` passed with `No issues found!`. Focused recovery tests passed: `flutter test --no-pub test/features/groups/domain/models/group_welcome_key_package_test.dart test/features/groups/application/group_invite_listener_test.dart --name 'EK011|derives default package ids'` (`3` tests), `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --name 'EK011 accepts a key-package-bound pending invite through wired local package id'` (`1` test), and `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --name 'EK011 accepts a key-package-bound pending group invite from Intros'` (`1` test). The focused owner suite passed (`120` tests), `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`117` tests), `./scripts/run_test_gates.sh groups` passed (`101` tests), `./scripts/run_test_gates.sh completeness-check` passed (`706/706`), and `git diff --check` passed. `dart analyze lib/main.dart` still fails on the unrelated pending-key-repair `groupPendingKeyRepairRepository` named-parameter mismatch and reports unrelated broad-main unused-import/style diagnostics; no welcome/key-package analyzer issue was found. - Decision/blocker: pass/no_blocking. Strict package validation is preserved: local `ownKeyPackageId` is derived from local device/transport id via `defaultGroupWelcomeKeyPackageIdForDevice`, not copied from the payload; package id/material checks still reject stale, malformed, weak, wrong-recipient/device/transport/package, tampered, and replayed packages before state mutation; v2 cleartext invite envelopes still contain only routing/preview fields plus encrypted payload. Production seams are covered through `main.dart`, `GroupInviteListener`, `GroupListWired`, and `OrbitWired`. EK-011 stays `Covered`; EK-012 and DB-012 remain `Partial` with only key-package replay/tombstone blockers narrowed. - Final QA verdict: accepted/qa_passed.
- 2026-05-01 18:48:00 CEST - Phase: Executor recovery wiring/gates/docs completed - Files inspected or touched: `lib/features/groups/domain/models/group_welcome_key_package.dart`, `lib/main.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `test/features/groups/domain/models/group_welcome_key_package_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`, `test/features/groups/presentation/group_list_wired_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart`, source matrix, test inventory, this plan, and the breakdown. - Command/evidence: targeted `dart analyze lib/features/groups/domain/models/group_welcome_key_package.dart lib/features/groups/presentation/screens/group_list_wired.dart lib/features/orbit/presentation/screens/orbit_wired.dart test/features/groups/domain/models/group_welcome_key_package_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/presentation/group_list_wired_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart` passed with `No issues found!`. Focused recovery tests passed: `flutter test --no-pub test/features/groups/domain/models/group_welcome_key_package_test.dart test/features/groups/application/group_invite_listener_test.dart --name 'EK011|derives default package ids'` (`3` tests), `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --name 'EK011 accepts a key-package-bound pending invite through wired local package id'` (`1` test), and `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --name 'EK011 accepts a key-package-bound pending group invite from Intros'` (`1` test). Broader gates passed: focused owner suite (`120` tests), `flutter test --no-pub test/features/groups/application/*invite*_test.dart` (`117` tests), `./scripts/run_test_gates.sh groups` (`101` tests), `./scripts/run_test_gates.sh completeness-check` (`706/706 test files classified`), and `git diff --check`. Broad `dart analyze lib/main.dart` still has the previously classified unrelated pending-key-repair constructor mismatch (`groupPendingKeyRepairRepository` passed to `GroupListWired`). - Decision/blocker: the same-session QA blocker is fixed. Local key-package ids now derive from the trimmed local device/transport id (`key-package-$deviceId`) and are wired through `main.dart`, `GroupListWired`, and `OrbitWired`; listener and UI/caller regressions prove valid first-class package invites store/accept through production wiring while wrong local package ids still reject. EK-011 remains `Covered` pending final isolated QA; EK-012 and DB-012 remain `Partial` with only the key-package replay/tombstone and wiring blockers narrowed. - Next action: hand off to controller-spawned final QA for this prerequisite.
- 2026-05-01 18:32:55 CEST - Phase: Executor fix-pass intake/contract extracted - Files inspected or touched: this plan, `git status --short`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_member.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/main.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `test/features/groups/application/group_invite_listener_test.dart`, `test/features/groups/presentation/group_list_wired_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart`. - Command/evidence: inspected QA finding and cited lines; confirmed `GroupInvitePayload.isBoundToRecipientDevice` requires matching `ownKeyPackageId` when `recipientKeyPackageId` is present; `GroupInviteListener` has an optional `getOwnKeyPackageId` callback but production `main.dart` does not wire it; both wired pending accept paths pass local device/transport/ML-KEM/package material without `ownKeyPackageId`. - Decision/blocker: bounded fix-pass scope is only first-class package invite admission through listener/main and both wired pending-accept caller seams; keep strict validation and derive local package id from the repo's device identity fallback pattern instead of making recipient package id optional. - Next action: add focused regressions for valid first-class package store/accept, then wire the local package id source.
- 2026-05-01 17:45:26 CEST - Phase: Executor intake/contract extracted - Files inspected or touched: this plan, `git status --short`, `lib/main.dart`, `lib/core/database/migrations/`. - Command/evidence: `git status --short` showed a broadly dirty tree with many pre-existing docs, Go, Flutter production, and test changes including owner files; `lib/main.dart` imports migrations through `063_group_pending_key_repairs` and sets `version: 63`; migration directory contains `001` through `063` only. - Decision/blocker: execute the existing plan without replanning; `064` is available if a durable key-package tombstone migration is needed; do not revert or overwrite unrelated dirty work. - Contract: scope is first-class welcome/key-package validation in the existing signed encrypted group invite flow plus durable package replay/freshness tombstones; closure requires signed canonical coverage, valid-device admission, stale/malformed/weak/wrong/tampered/replayed rejection before state mutation, close/reopen tombstone proof, existing invite semantics preserved, and no new cleartext leakage; source of truth is the source matrix, inventory, breakdown, this plan, and current code/tests; owner files are invite payload/policy/pending invite models, send/handle/accept use cases, pending invite repository/helpers, DB migration/main wiring, fakes, and focused invite/repository/migration tests; required gates are the plan's focused direct `flutter test` commands, `flutter test --no-pub test/features/groups/application/*invite*_test.dart`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` as feasible; EK-011 can move `Covered` only after closure evidence, while EK-012/DB-012 stay `Partial` unless non-key-package blockers close. - Next action: inspect owner code and add focused RED tests where practical.
- 2026-05-01 17:50:24 CEST - Phase: Executor RED tests added/started - Files inspected or touched: `test/features/groups/domain/models/group_welcome_key_package_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/application/send_group_invite_use_case_test.dart`, `test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart`. - Command/evidence: `flutter test --no-pub test/features/groups/domain/models/group_welcome_key_package_test.dart test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart --name 'EK011|welcome key package|weak recipient key-package|package tombstone'` failed as expected because `GroupWelcomeKeyPackage`, `welcomeKeyPackage`, policy key-package join refs, tombstone model/helper/migration, and repository methods do not exist yet. - Decision/blocker: RED evidence captured; continue with scoped production implementation. - Next action: add package model, payload/policy binding, tombstone persistence, repository/fake wiring, and use-case validation.
- 2026-05-01 18:10:37 CEST - Phase: Executor fix-pass focused proof completed - Files inspected or touched: this plan, `git status --short`, owner diff for welcome-package model/tombstone/migration/helper, invite payload/policy, send/handle/accept use cases, pending invite repository and in-memory fake. - Command/evidence: `flutter test --no-pub test/features/groups/domain/models/group_welcome_key_package_test.dart test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart test/core/database/integration/full_migration_chain_test.dart` passed with `116` tests. - Decision/blocker: inherited partial implementation compiles and passes the controller-required starting proof; continue inspecting wider seam and named gates before handoff. - Next action: check listener/main/fake wiring, run invite wildcard and groups/completeness/diff gates as feasible.
- 2026-05-01 18:17:03 CEST - Phase: Executor fix-pass wiring/gates/docs completed - Files inspected or touched: `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, source matrix, test inventory, session breakdown, this plan. - Command/evidence: targeted `dart analyze lib/features/groups/application/group_invite_listener.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/presentation/screens/group_list_wired.dart lib/features/orbit/presentation/screens/orbit_wired.dart` initially found one unused `dart:convert` import; removed it and reran with `No issues found!`. `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart test/core/database/migrations/064_group_welcome_key_package_tombstones_test.dart test/core/database/helpers/group_welcome_key_package_tombstones_db_helpers_test.dart` passed with `17` tests. `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed with `115` tests. `./scripts/run_test_gates.sh groups` passed with `101` tests. `./scripts/run_test_gates.sh completeness-check` passed with `706/706 test files classified`. `git diff --check` passed. - Decision/blocker: no in-scope compile, focused-test, named-gate, completeness, or diff-hygiene blocker remains. EK-011 moved to `Covered` in source docs from concrete evidence; EK-012 and DB-012 remain `Partial` with only key-package replay/tombstone blockers narrowed. Prerequisite is marked executor-green/awaiting QA in the breakdown, not `qa_passed`. - Next action: hand off to controller-spawned QA.
- 2026-05-01 18:26:48 CEST - Phase: QA Reviewer completed - Files inspected or touched: this plan, `lib/features/groups/domain/models/group_welcome_key_package.dart`, `lib/features/groups/domain/models/group_welcome_key_package_tombstone.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_invite_policy.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/groups/domain/repositories/pending_group_invite_repository.dart`, `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart`, `test/shared/fakes/in_memory_pending_group_invite_repository.dart`, `lib/core/database/helpers/group_welcome_key_package_tombstones_db_helpers.dart`, `lib/core/database/migrations/064_group_welcome_key_package_tombstones.dart`, `lib/main.dart`, focused tests, source matrix, inventory, and breakdown. - Command/evidence: `flutter test --no-pub test/features/groups/domain/models/group_welcome_key_package_test.dart test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart test/core/database/migrations/064_group_welcome_key_package_tombstones_test.dart test/core/database/helpers/group_welcome_key_package_tombstones_db_helpers_test.dart test/core/database/integration/full_migration_chain_test.dart` passed with `119` tests. `dart analyze` on welcome/key-package owner files excluding broad `main.dart` returned exit code `0` with two pre-existing style/info diagnostics only. The same analyzer including `lib/main.dart` failed on an unrelated pending-key-repair constructor mismatch (`groupPendingKeyRepairRepository` passed to `GroupListWired`, which does not define that named parameter). `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed with `115` tests. `./scripts/run_test_gates.sh groups` passed with `101` tests. `./scripts/run_test_gates.sh completeness-check` passed with `706/706 test files classified`. `git diff --check` passed. - Decision/blocker: QA found one in-scope blocking issue. The domain/use-case validation matrix and docs are mostly supported, but production listener and wired accept paths do not supply `ownKeyPackageId` while `GroupInvitePayload.isBoundToRecipientDevice` requires it whenever a first-class invite carries `recipientKeyPackageId`. `GroupInviteListener` obtains `ownKeyPackageId` only from an optional callback, but `lib/main.dart` does not wire that callback; `GroupListWired` and `OrbitWired` pass local device, transport, ML-KEM public key, and package material but omit `ownKeyPackageId`. As a result, valid first-class package invites produced by the new send path can be rejected before pending-store or pending-accept in production routes, so the closure bar item "valid packages admit only the intended current recipient device" is not met end-to-end. - Final QA verdict: blocked (`qa_blocking_issue`). - Next action: add a concrete local key-package-id source/wiring for listener and wired accept paths, add focused listener/UI or caller tests proving valid first-class package invites store and accept through production wiring, rerun the focused owner tests/gates, then return for final QA.

## Recovery Input

- Blocker class: current-session implementation-owned `qa_blocking_issue`.
- Blocker signature: `PREREQ-WELCOME-KEY-PACKAGE|implementation-owned|missing-production-ownKeyPackageId-wiring-for-first-class-key-package-invites|lib/main.dart,lib/features/groups/application/group_invite_listener.dart,lib/features/groups/presentation/screens/group_list_wired.dart,lib/features/orbit/presentation/screens/orbit_wired.dart,test/features/groups/application/group_invite_listener_test.dart,test/features/groups/presentation/group_list_wired_test.dart,test/features/orbit/presentation/screens/orbit_wired_test.dart`.
- Missing contract: `GroupInvitePayload.isBoundToRecipientDevice` correctly requires `ownKeyPackageId` to match `recipientKeyPackageId`, but production listener and pending-accept routes do not supply the local key-package id. Valid first-class package invites can therefore fail before pending-store or accept.
- Required recovery: wire `ownKeyPackageId` from a trusted local source through `GroupInviteListener` in `lib/main.dart` and through `acceptPendingGroupInvite` calls in `GroupListWired` and `OrbitWired`. Prefer an existing local identity/device key-package id if current code exposes one; otherwise use the repo's existing derivation pattern from `GroupTestUser`: `key-package-$deviceId`, where `deviceId` is the trimmed local device/transport id already used by these seams.
- Forbidden recovery: do not weaken `_optionalMatches`, do not make package-id validation optional for first-class package invites, do not pass `payload.recipientKeyPackageId` as `ownKeyPackageId`, do not expose key-package material in cleartext envelopes/logs/flow events, and do not broaden into identity-schema, device-registry, or MLS work.

## Recovery Execution Contract

Owner production files for this recovery pass:

- `lib/main.dart`
- `lib/features/groups/application/group_invite_listener.dart` only if constructor/callback naming or docs need a narrow adjustment
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`

Owner test files for this recovery pass:

- `test/features/groups/application/group_invite_listener_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- existing focused package-admission tests only as needed to keep signatures aligned

Execution steps:

1. Add focused failing coverage showing a valid first-class key-package invite with `recipientKeyPackageId: key-package-<localDeviceId>` is stored by `GroupInviteListener` when production-style local identity callbacks are wired, and is rejected when the local derived id does not match.
2. Add focused pending-accept UI/caller coverage proving `GroupListWired` and `OrbitWired` pass `ownKeyPackageId` for first-class package pending invites and can accept the valid local package path.
3. Implement the smallest local key-package-id source. If no persisted identity field exists, derive from the same local device/transport id these routes already pass as `ownDeviceId`/`ownTransportPeerId`; return `null` for missing/blank local device id rather than fabricating a global fallback.
4. Wire that source into `GroupInviteListener.getOwnKeyPackageId` in `main.dart` and into both pending accept calls as `ownKeyPackageId`.
5. Keep all domain/use-case validation strict. Any test that passes only by relaxing `GroupInvitePayload.isBoundToRecipientDevice`, skipping `welcome.matchesInviteAndRecipient`, or copying the payload recipient package id into local identity fails this recovery contract.

Expected direct tests and gates:

```sh
flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart
flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart --name 'pending.*invite|key.package|accept'
flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart
flutter test --no-pub test/features/groups/application/*invite*_test.dart
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Analyzer expectation: run targeted analysis over edited owner files. If `dart analyze lib/main.dart` still reports only the previously observed unrelated pending-key-repair constructor mismatch, isolate and record it rather than expanding this recovery pass.

Closure decision after recovery QA:

- EK-011 may remain or move to `Covered` only after QA verifies valid first-class package invites store and accept through production listener and UI pending-accept routes, with strict wrong-package rejection still intact.
- EK-012 remains `Partial`; this recovery may only remove/narrow the production key-package-id wiring blocker and must not claim all replay families, bans, deletes, receipts, commit transitions, or cross-surface diagnostics.
- DB-012 remains `Partial`; this recovery does not change the all-event-family idempotency matrix and may only preserve the already implemented key-package tombstone/idempotency evidence.

## real scope

This prerequisite owns only the welcome/key-package admission and replay blockers that remain after `PREREQ-DEVICE-IDENTITY`, `PREREQ-SIGNED-COMMIT-AUDIT`, and `PREREQ-FUTURE-EPOCH-KEY-REPAIR`.

Implement a first-class welcome/key-package contract inside the current signed, encrypted group invite flow:

- a domain model for the welcome/key-package metadata that binds recipient member, recipient device, transport peer, ML-KEM/key-package material, invite id, group id, key epoch, issued time, expiry, and package id
- send-side construction of that model from the active recipient device and inclusion in the canonical signed invite payload
- receive/store/accept validation before any pending invite, group, member, group key, mailbox drain, join publish, event-log, notification, or bridge side effect
- durable package replay/freshness tombstones so a consumed package id cannot be replayed under a new invite id or modified metadata
- direct evidence for valid, stale, malformed, wrong-recipient/device, weak-material, tampered-signature, and replayed-package cases

This session must not invent MLS commit protocol support, external key package services, sibling-device approval, account-level device registry UX, or broad remote event-family idempotency. The current shipped invite still carries the group key inline as join material; this plan makes that join material package-bound, signed, freshness-checked, and replay-protected.

## closure bar

`PREREQ-WELCOME-KEY-PACKAGE` can be accepted only when direct tests prove all of the following together:

- send-side invites contain a first-class welcome/key-package object whose canonical fields are covered by the invite signature
- valid packages admit only the intended current recipient device and still complete the existing group materialization flow
- stale, expired, malformed, weak, wrong-recipient, wrong-device, wrong-transport, wrong key-package id/material, and tampered signed-package payloads fail before local state mutation
- package replay is durable and idempotent: a consumed package id/tombstone blocks later pending-store or accept attempts even if the invite id or unrelated metadata changes
- freshness/tombstone state survives repository close/reopen or a file-backed DB test
- accepted invitations preserve existing single-use/multi-use invite semantics where those semantics are not package replay guarantees
- privacy is preserved: no new cleartext envelope field exposes group key, package material, signatures, member list, or sensitive addresses

EK-011 may move to `Covered` only if the source matrix and inventory record concrete file/test evidence for the full validation matrix above.

EK-012 must not move to `Covered` from this prerequisite unless execution also proves the row's remaining non-key-package replay families. Expected closure is narrower: remove or narrow only the key-package replay/freshness/tombstone blocker. EK-012 should remain `Partial` if `PREREQ-REMOTE-EVENT-FAMILIES` is still required for bans, deletes, receipts, commit transitions, or cross-surface replay diagnostics.

DB-012 may be narrowed only for key-package transition/tombstone idempotency. It must remain `Partial` unless the complete all-event-family idempotency matrix is implemented and proven.

## source of truth

Authoritative docs:

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- accepted prerequisite plans for `PREREQ-DEVICE-IDENTITY`, `PREREQ-SIGNED-COMMIT-AUDIT`, and `PREREQ-FUTURE-EPOCH-KEY-REPAIR`

Authoritative implementation files:

- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/domain/models/group_invite_policy.dart`
- `lib/features/groups/domain/models/pending_group_invite.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/domain/repositories/pending_group_invite_repository.dart`
- `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart`
- `lib/core/database/helpers/pending_group_invites_db_helpers.dart`
- `lib/main.dart`

If docs and code disagree, current code plus passing direct tests win. If named-gate prose and `scripts/run_test_gates.sh` disagree, the script wins for runnable gate membership.

## session classification

`implementation-ready`.

The gaps are repo-owned. Current code already has signed invite payloads, device-bound recipient fields, pending invite consumption/revocation tombstones, and migration-backed pending-invite storage. Missing pieces are first-class welcome/key-package validation and package-level replay/freshness tombstones.

## exact problem statement

Current behavior is safer than the original matrix but still incomplete:

- invite payloads carry `recipientKeyPackageId` and `recipientKeyPackagePublicMaterial` as optional device metadata, not as a first-class validated welcome/key-package object
- `GroupInvitePolicy.joinMaterialRef` only records `inlineGroupKey` and epoch; it does not bind a package id/material hash, issued time, expiry, or recipient device package into admission
- send/handle/accept code validates recipient device identity but does not reject weak package material as a package validation failure
- replay protection is invite-id based through consumed invite tombstones, so the same recipient package can be replayed under a different invite id unless another guard happens to catch it
- stale package and package tombstone state are not modeled durably

User-visible behavior required: a join attempt with bad, stale, wrong-device, weak, or replayed welcome/key-package material must fail clearly before the app creates an unusable group or leaks key material. Valid invites must continue to join normally.

Security behavior that must stay unchanged: the invite remains encrypted to the recipient, signatures are verified before admission, pending invite repair behavior stays available for repairable join-material failures, single-use invite tombstones still work, and no package material is exposed in cleartext routing envelopes or flow-event details.

## files and repos to inspect next

Production files expected in scope:

- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/domain/models/group_invite_policy.dart`
- new narrow model if needed: `lib/features/groups/domain/models/group_welcome_key_package.dart`
- `lib/features/groups/domain/models/pending_group_invite.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/domain/repositories/pending_group_invite_repository.dart`
- `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart`
- `lib/core/database/helpers/pending_group_invites_db_helpers.dart`
- `lib/main.dart`

Likely persistence additions:

- `lib/core/database/migrations/064_group_welcome_key_package_tombstones.dart`
- `lib/core/database/helpers/group_welcome_key_package_tombstones_db_helpers.dart`
- `lib/features/groups/domain/models/group_welcome_key_package_tombstone.dart`

Stop and renumber before schema edits if database version `63` or migration `064` is no longer current in the dirty worktree.

Test files expected in scope:

- `test/features/groups/domain/models/group_invite_payload_test.dart`
- new narrow model test if added: `test/features/groups/domain/models/group_welcome_key_package_test.dart`
- `test/features/groups/application/send_group_invite_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart`
- migration/helper/full-chain tests if a tombstone table is added

## existing tests covering this area

Current positive evidence:

- `group_invite_payload_test.dart` proves signed invite payloads include policy and device-bound recipient fields, and that signature canonicalization catches mismatched signed payloads.
- `send_group_invite_use_case_test.dart` proves device-bound invites send to registered recipient device transport and reject unregistered requested devices before encryption.
- `handle_incoming_group_invite_use_case_test.dart` proves direct handling rejects wrong or missing local device identity before group/key/join side effects.
- `accept_pending_group_invite_use_case_test.dart` proves pending accept rejects wrong transport, wrong key package id, or missing local device before state, and preserves repair-pending join-material behavior.
- `invite_round_trip_test.dart` proves normal valid invite flows, future-only onboarding history, and existing invite replay semantics.
- `pending_group_invite_repository_impl_test.dart` proves pending, revoked, and consumed invite persistence.

Missing coverage:

- no first-class package object that validates package id/material, recipient binding, issue/expiry, and policy binding as one model
- no signed welcome/package canonicalization test showing tampered package metadata fails
- no weak package material rejection before send/store/accept side effects
- no durable package-level tombstone keyed independently from invite id
- no stale package replay test where an attacker changes invite id or unrelated metadata while reusing old package identity/material
- no file-backed close/reopen proof for package tombstones

## regression/tests to add first

Add failing tests before production edits:

- Domain model/payload: valid welcome key package round-trips inside `GroupInvitePayload`, is included in the canonical signed payload, binds `joinMaterialRef`, and rejects stale, malformed, wrong-recipient, wrong-device, mismatched material hash/package id, and weak material.
- Send use case: device-bound invite builds a signed welcome/key-package object from the active recipient device and rejects missing or weak recipient package material before encryption or send/inbox side effects.
- Store/handle use case: incoming signed invites with wrong recipient device, stale package time, weak package material, or tampered signed package metadata return invalid payload before pending/group/key/join state.
- Accept use case: pending invite revalidates package freshness and recipient local package identity before materialization, keeps repair-pending behavior for repairable join-material failures, and rejects package replay tombstones before group/member/key/message/join side effects.
- Repository/helper: package tombstone save/load/delete-expired round-trip, duplicate save idempotency, and file-backed close/reopen survival.
- Integration: valid invite round trip succeeds with package validation enabled; replaying the same package id/material under a changed invite id is rejected before duplicate group or new state claims.

If the durable tombstone table is added, add the migration and full-chain tests before application code depends on it.

## step-by-step implementation plan

1. Dirty-worktree and migration intake: record `git status --short`, `lib/main.dart` DB version, latest migration files, and target owner file status. Do not revert unrelated changes. Stop and renumber if migration `064` is already claimed.
2. Add the first-class welcome/key-package domain model. Keep it narrow: fields should be package id, public material or public-material hash, recipient peer id, recipient device id, recipient transport peer id, recipient ML-KEM public key, key epoch, invite id, group id, issued at, expires at, and schema version. Implement `toJson`, `fromJson`, canonical validation, freshness checks, weak-material checks, and recipient-device matching helpers.
3. Extend `GroupInvitePolicy.joinMaterialRef` and `GroupInvitePayload` to bind the welcome/key-package object into the signed canonical payload. Preserve backward-compatible parsing only where tests require existing legacy inline invites, but production `sendGroupInvite` should emit the first-class package contract for device-bound invites.
4. Add durable package tombstones if not already present. Prefer a small `group_welcome_key_package_tombstones` table keyed by package id plus recipient device id/group id, with consumed/replayed timestamps and expiry. Add helper, model, repository wiring through `PendingGroupInviteRepository`, `PendingGroupInviteRepositoryImpl`, `main.dart`, and in-memory fake support.
5. Change send-side validation to require active recipient package material for device-bound invites, reject weak/malformed material before `message.encrypt`, and include the signed package model in the encrypted inner invite only. The v2 cleartext envelope must not gain package material.
6. Change incoming store/direct handle validation to reject malformed, stale, weak, wrong-recipient, wrong-device, and tampered package metadata before pending invite save or group materialization.
7. Change pending accept validation to recheck package freshness, local recipient package identity, signature, revocation/consumption, and package tombstone before materialization. Record the package tombstone only after successful admission, and keep existing repair-pending behavior for repairable join-material bridge failures.
8. Add replay handling: if an active package tombstone exists, store and accept paths must fail closed before group/member/key/message/join side effects. Exact duplicate pending saves should stay idempotent where current semantics allow it, but changed invite id or changed metadata with the same package must not bypass the package tombstone.
9. Preserve current valid invite behavior and existing IJ/IJ-014/IJ-005 semantics. Update tests only where they now need explicit package data because production sends first-class package invites.
10. After tests pass, update source matrix, inventory, breakdown, and this plan only with evidence that exists. EK-011 can move to `Covered` if the closure bar is met. EK-012 and DB-012 should be narrowed but remain `Partial` unless their non-key-package blockers are also closed.

## risks and edge cases

- Fake key material in existing tests is short. The implementation should avoid a broad cryptographic length requirement that breaks unrelated legacy fixtures, while still rejecting clearly weak first-class package material in package-specific validation tests.
- Legacy inline invite parsing may still be needed for older pending rows. Do not silently mark legacy rows as covered for EK-011; either treat them as repair pending/invalid where appropriate or keep compatibility only outside the new first-class package closure proof.
- Package tombstones must not consume a package before a successful admission; otherwise a transient bridge failure could permanently block a valid retry.
- Multi-use invite policy and package single-use semantics can differ. Multi-use invite replay may be allowed as a credential policy, but a consumed device package must still not be reused to admit the same package again.
- Pending invite expiry, revocation, consumed invite tombstones, and package tombstones must have deterministic ordering so a row does not create partial group state before a later replay/freshness rejection.
- The DB is already dirty through migration 063. Check migration numbering immediately before adding 064.

## exact tests and gates to run

Initial focused RED command should include the new tests once added, for example:

```sh
flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart --name 'PREREQ-WELCOME-KEY-PACKAGE|EK011|EK012'
```

Required post-implementation direct tests:

```sh
flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart
```

If a new model/helper/migration is added:

```sh
flutter test --no-pub test/features/groups/domain/models/group_welcome_key_package_test.dart test/core/database/migrations/064_group_welcome_key_package_tombstones_test.dart test/core/database/helpers/group_welcome_key_package_tombstones_db_helpers_test.dart test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart test/core/database/integration/full_migration_chain_test.dart
```

Regression gates:

```sh
flutter test --no-pub test/features/groups/application/*invite*_test.dart
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

No Go test is required unless execution changes Go bridge/node behavior. Host/fake-network proof is primary; device/relay proof is supporting only for this prerequisite. If a supporting device gate is chosen, use the verified inline env values:

```sh
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly
```

Run that only if the executor determines real-device package proof is necessary; do not make it blocking for host-owned model/admission closure.

## known-failure interpretation

- The broad worktree is dirty from prior sessions. Do not classify unrelated dirty files as this session's regression.
- If broad application or integration suites expose a pre-existing MD-011/future-media style failure unrelated to invite welcome/key-package admission, isolate it with a focused rerun and record it as unrelated instead of changing this plan's scope.
- If migration 064 is unavailable because another local session already claimed it, renumber consistently and update all migration/full-chain tests before continuing.
- If a real-device gate is unconfigured or Android paired proof remains unavailable due missing `adb`/`emulator-5556`, record it as supporting fixture evidence only; host/fake-network proof is enough unless the implementation adds a device-only surface.

## done criteria

- Plan status remains `execution-ready` or is updated by execution with concrete blocker/recovery notes.
- New package model, validation, tombstone persistence, send/store/accept integration, and tests are implemented or a precise repo-owned blocker is recorded.
- Direct tests and required gates pass, with any unrelated known failures isolated.
- Source matrix and inventory are updated only after evidence exists.
- Breakdown ledger marks `PREREQ-WELCOME-KEY-PACKAGE` as accepted/qa_passed only after isolated QA accepts it.
- EK-011 is `Covered` only if the closure bar is met. EK-012/DB-012 remain `Partial` unless their non-key-package blockers are also closed.

## scope guard

Do not:

- invent MLS commit semantics, server-side key-package directories, account/device enrollment UX, sibling-device approval, or new relay protocols
- expose welcome/key-package material in v2 cleartext invite envelopes, logs, flow events, or diagnostics
- weaken existing invite signature, revocation, single-use/multi-use, device-bound admission, or repair-pending behavior
- touch history gap repair, receipts, secret-storage wrapping, remote bans/deletes, remote event-family idempotency, or inviter freshness except for doc residual notes after evidence
- mark EK-012 or DB-012 `Covered` from key-package-only evidence

Overengineering includes adding a general-purpose key transparency service, global device registry, broad event CRDT, or Go transport change for a Flutter-domain admission model.

## accepted differences / intentionally out of scope

- The implementation may model welcome/key-package validation within the existing signed encrypted invite architecture rather than implementing full MLS welcome messages. That is acceptable for this repo's shipped group invite surface if the source docs clearly describe the scope.
- Legacy inline group-key invites may remain parseable for compatibility, but they do not count as EK-011 closure evidence.
- Real relay/device proof is supporting, not required, unless execution adds a behavior that can only be proven on a device.
- EK-012 cross-surface replay diagnostics and DB-012 all-event-family idempotency remain owned by later prerequisites.

## dependency impact

If this prerequisite succeeds:

- revisit EK-011 and move it to `Covered` only with concrete validation/tombstone evidence
- revisit EK-012 and remove or narrow the key-package replay/freshness blocker, but keep it `Partial` if `PREREQ-REMOTE-EVENT-FAMILIES` remains open
- revisit DB-012 and narrow key-package transition/tombstone idempotency only; keep bans/deletes/receipts/all-family matrix blockers open
- continue to `PREREQ-HISTORY-GAP-REPAIR` next

If this prerequisite blocks:

- keep EK-011 and EK-012 `Partial`
- record the exact blocker as implementation-owned, prerequisite-owned, or external-fixture-only
- continue with later independent reopened prerequisites if safe under the pipeline rules
