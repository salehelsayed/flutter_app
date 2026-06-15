Status: execution-ready

# MIG-001 - Account Authority and Migration State Foundation Plan

## Planning Progress

- 2026-06-06T18:48:02Z - Evidence Collector started. Files inspected since last update: implementation-plan-orchestrator skill, graphify skill, graphify-out/graph.json presence. Decision/blocker: intended doc-scoped plan path confirmed; no blocker. Next action: inspect source docs, scoped gate docs, graphify query results, and likely MIG-001 code/tests.
- 2026-06-06T18:50:30Z - Evidence Collector completed; Planner started. Files inspected since last update: source proposal, session breakdown, spec reviews, gate docs, startup decision/router, identity choice screens, secure key store, main wiring, direct identity startup/onboarding tests, graphify queries. Decision/blocker: no dedicated account-migration authority implementation exists; MIG-001 must plan a new device-local authority model and startup gate. Next action: draft mandatory plan sections and regression-first contract.
- 2026-06-06T18:51:32Z - Planner completed; Reviewer started. Files inspected since last update: no new files; draft synthesized from collected evidence. Decision/blocker: draft scope is host-testable and does not require simulator-backed closure for MIG-001. Next action: review for missing tests, hidden later-session scope, and gate sufficiency.
- 2026-06-06T18:53:31Z - Reviewer completed; Arbiter started. Files inspected since last update: plan draft only. Decision/blocker: sufficient with wording adjustment; no structural blocker. Next action: arbitrate reviewer findings and move to execution-ready if no blocker remains.
- 2026-06-06T18:53:56Z - Arbiter completed. Files inspected since last update: reviewed plan and reviewer findings. Decision/blocker: no structural blockers remain; accepted deferrals are assigned to later MIG sessions. Next action: hand the execution-ready plan to the controller.

## Real Scope

MIG-001 adds the account-migration authority foundation only:

- Add a new `lib/features/account_migration/` domain/application slice with canonical migration-authority states from the proposal: `no_account`, `migration_pairing`, `migration_import_staging`, `migration_verified_waiting_for_cutover`, `active`, `migration_failed_cleanup_required`, `migration_exporting_network_paused`, `migration_cutover_pending_blocked`, `migrated_out`, and `migration_failed_active_restored`.
- Persist the authority record as device-local state outside the SQLCipher database bundle, using the existing `SecureKeyStore` point-read/write abstraction with a dedicated migration authority key/prefix and explicit JSON/version parsing.
- Add repository/use-case rules that let later sessions ask whether migration import can start, whether normal account startup may proceed, and whether a state is a non-active/staging/blocking state.
- Thread the authority read into startup decision/routing before normal main-app/FTE/P2P startup so migrated-out or cutover-blocked states cannot reach normal UI or call `_startP2PInBackground`.
- Preserve current normal behavior when no authority record exists or when the record is `active`: identity/contact routing, new-account generation, mnemonic restore, and returning-user P2P startup remain unchanged.
- Add only the minimum blocked/migration-holding surface needed for host widget tests if `StartupRouter` needs a concrete destination for blocked states.

MIG-001 does not implement QR pairing, export/import, manifest generation, secure-storage registry enumeration, SQLCipher snapshotting, media/file transfer, segmented transport, server lease cleanup, push/rendezvous unregister, runtime listener/retrier gates beyond startup routing, pending-work migration, full migrated-out UX, erase/reset implementation, or final iOS acceptance.

## Closure Bar

This session is good enough when host-side tests prove:

- The canonical authority states are represented by a typed model with deterministic serialization/deserialization, version handling, and fail-closed invalid-state behavior.
- Authority state is stored through `SecureKeyStore`, not in the migrated SQLCipher database.
- Missing authority state is backward-compatible: no identity still routes to onboarding, and an existing identity behaves as `active`.
- `migrated_out`, `migration_cutover_pending_blocked`, `migration_exporting_network_paused`, `migration_import_staging`, and `migration_failed_cleanup_required` do not enter normal account UI or start P2P from startup.
- `active` preserves current startup behavior for both returning users with contacts and users with identity/no contacts.
- A new-phone migration import precondition use case rejects import start when an active account exists unless a later explicit reset/erase precondition is provided; the actual reset/erase implementation stays out of scope.
- Source proposal rows for canonical states, device-local authority storage, partial import/startup block, migrated-out old-phone startup block, and two-active prevention are updated or marked as newly covered by the direct tests added in this session.

## Source of Truth

- Product/session contract: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`, especially canonical states, device-local authority, startup block, regressions to preserve, release-blocking safety tests, and acceptance evidence.
- Session boundary: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`, MIG-001 section. This wins over broader proposal items for what belongs in this session.
- Historical risk context: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-spec-review.md` G3 and `Test-Flight-Improv/Move-Feature/02-spec-sufficiency-review.md` P0-6. These explain why the state must be device-local and observable by later gates.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Regression strategy: `Test-Flight-Improv/14-regression-test-strategy.md`.
- Current code/tests win over stale prose: `lib/features/identity/application/startup_decision.dart`, `lib/features/identity/presentation/startup_router.dart`, `lib/features/identity/presentation/screens/identity_choice_wired.dart`, `lib/features/identity/presentation/screens/identity_choice_screen.dart`, `lib/core/secure_storage/secure_key_store.dart`, `lib/core/secure_storage/flutter_secure_key_store.dart`, `lib/main.dart`, and the direct identity startup/onboarding tests.

## Session Classification

`implementation-ready`

The session has no dependency on earlier migration implementation. Existing code lacks a dedicated authority model/gate, but the repo already has the `SecureKeyStore`, startup decision, startup router, fake secure store, and direct tests needed to implement the foundation safely.

## Exact Problem Statement

The app currently routes startup from identity/contact presence only. There is no persisted per-account active/migrated-out authority state in `lib/`, so an old phone that has been migrated out would still be able to load identity, enter normal startup, and start P2P from `StartupRouter`. If authority state were stored in the migrated database, the new phone could import the old phone's local active/migrated-out flag and boot into the wrong authority state. MIG-001 must create a device-local authority foundation and make startup observe it before normal UI/P2P entry, while leaving all non-migration startup behavior unchanged.

## Files and Repos to Inspect Next

Production files for implementation:

- `lib/features/account_migration/domain/models/account_migration_authority_state.dart` - new typed enum/model.
- `lib/features/account_migration/domain/repositories/account_migration_authority_repository.dart` - new repository contract.
- `lib/features/account_migration/application/account_migration_authority_repository_impl.dart` or matching repo-local naming - new `SecureKeyStore`-backed implementation.
- `lib/features/account_migration/application/account_migration_authority_use_cases.dart` - new precondition/gating helpers if the repo pattern favors use cases over model methods.
- `lib/features/account_migration/presentation/screens/account_migration_blocked_screen.dart` - only if a concrete minimal route widget is needed for blocked startup states.
- `lib/features/identity/application/startup_decision.dart` - extend the decision model and inject/read migration authority.
- `lib/features/identity/presentation/startup_router.dart` - pass/read authority and route blocked/staging states before Feed/FTE/P2P.
- `lib/features/identity/presentation/screens/identity_choice_wired.dart` and `lib/features/identity/presentation/screens/identity_choice_screen.dart` - inspect only if the implementation chooses a minimal new-phone migration-entry callback; full journey UI stays MIG-011.
- `lib/main.dart` - wire the new repository into `StartupRouter` using the existing `secureKeyStore`.
- `lib/core/secure_storage/secure_key_store.dart` and `lib/core/secure_storage/flutter_secure_key_store.dart` - should not need interface changes for MIG-001.

Direct tests to inspect/update:

- `test/features/account_migration/domain/` and `test/features/account_migration/application/` - new tests.
- `test/features/identity/application/startup_decision_test.dart`.
- `test/features/identity/presentation/screens/startup_router_test.dart`.
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart`.
- `test/features/identity/presentation/screens/identity_choice_screen_test.dart` and `test/features/identity/presentation/screens/identity_choice_wired_test.dart` only if a minimal migration entry callback is added.
- `test/core/secure_storage/fake_secure_key_store.dart`.

Docs to update after implementation:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`.
- `Test-Flight-Improv/test-gate-definitions.md` or `Test-Flight-Improv/codebase-test-inventory.md` only if new tests need explicit gate classification beyond direct feature-local coverage.

## Existing Tests Covering This Area

- `test/features/identity/application/startup_decision_test.dart` covers the current three outcomes: `needsIdentity`, `hasIdentityNoContacts`, and `hasIdentityWithContacts`.
- `test/features/identity/presentation/screens/startup_router_test.dart` documents that returning users route from local state before network warmup and later start P2P in background.
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart` proves a missing DB identity stays on onboarding even if secure-store mnemonic material survives, and that P2P is not started for `needsIdentity`.
- `test/features/identity/presentation/screens/identity_choice_screen_test.dart` and `identity_choice_wired_test.dart` cover the current two-choice onboarding UI and generation/restore wiring.
- `test/core/secure_storage/fake_secure_key_store.dart` is the existing in-memory test double for point reads/writes/deletes.
- `Test-Flight-Improv/test-gate-definitions.md` puts `startup_router_recovery_test.dart` in the Baseline Gate.

Missing today:

- No account-migration model/repository tests.
- No test proves the canonical migration states exist as typed values.
- No test proves authority state is outside the database.
- No startup decision/router test proves migrated-out or staging states block normal startup and P2P.
- No test proves an active existing account blocks new-phone import start.

## Regression/Tests to Add First

Add these tests before production changes:

- `test/features/account_migration/domain/account_migration_authority_state_test.dart`
  - Covers canonical state list, JSON wire names, invalid-state rejection, version mismatch handling, and classification helpers such as `allowsNormalStartup`, `isBlocked`, and `isImportStaging`.
- `test/features/account_migration/application/account_migration_authority_repository_test.dart`
  - Uses `FakeSecureKeyStore` to prove writes/readbacks are device-local secure-store values, records are scoped by account/peer where applicable, missing records default safely, malformed JSON fails closed to a cleanup/blocking result rather than active, and deleting/clearing the authority record restores missing-record behavior.
- `test/features/account_migration/application/account_migration_import_precondition_test.dart`
  - Proves import can start only when there is no active local identity/authority or when a later explicit reset precondition is supplied; active identity plus active authority is rejected.
- Update `test/features/identity/application/startup_decision_test.dart`
  - Add cases for missing authority with no identity, missing authority with identity, explicit active authority, migrated-out authority, export/network-paused authority, cutover-pending authority, import-staging authority, and failed-cleanup authority.
- Update `test/features/identity/presentation/screens/startup_router_recovery_test.dart` or `startup_router_test.dart`
  - Add widget cases proving a migrated-out identity routes to the blocked/migration-holding screen, does not render `FeedWired`, `FirstTimeExperienceWired`, or `IdentityChoiceWired`, and leaves `p2pService.startNodeCallCount == 0`.
  - Add preservation cases proving active/missing authority still routes as before and starts P2P only on the existing normal paths.
- Update onboarding tests only if the production change adds a minimal `Move from old phone` callback in MIG-001. Otherwise leave third-choice UX to MIG-011 and record that as an accepted difference.

## Step-by-Step Implementation Plan

1. Add failing account-migration model tests for the canonical state enum/model and helper classifications.
2. Add failing repository/precondition tests using `FakeSecureKeyStore`; do not introduce database helpers or migrations.
3. Add failing startup-decision tests for active, missing, migrated-out, blocked, staging, and cleanup states.
4. Add failing startup-router widget tests proving migrated-out/blocked states do not start P2P or normal UI, and active/missing states remain unchanged.
5. Implement the account-migration domain model with explicit wire names, versioned JSON, and fail-closed parse behavior for malformed persisted records.
6. Implement a `SecureKeyStore`-backed repository. Keep the storage key documented as device-local and intentionally excluded from future migration manifests; use point reads/writes only.
7. Implement import-start/precondition helpers that later QR/import sessions can call. Return typed results rather than booleans if needed to make failure reasons testable.
8. Extend `StartupDecision` with migration-aware blocked/staging decisions, or introduce a wrapper result if that better preserves current enum semantics. Default missing authority to active for identities and no-account for missing identities.
9. Update `StartupRouter` to read the authority state before normal Feed/FTE/P2P routing and navigate blocked/staging decisions to the minimal safe holding surface without calling `_ensureMlKemKeys` or `_startP2PInBackground`.
10. Wire the repository into `StartupRouter` from `main.dart` using the existing `secureKeyStore`; update widget-test builders with a fake/default repository.
11. If a minimal new-phone migration entry callback is added, keep it non-polished and route only to a placeholder/pairing pending state; otherwise defer all user journey UI to MIG-011.
12. Update the source proposal's coverage/gap text for MIG-001 evidence. Update gate inventory docs only if the added tests are cross-feature/integration/core-service tests needing explicit classification.
13. Run exact direct tests and the Baseline Gate. Run the Transport Gate only if implementation changes bridge/P2P bootstrap behavior outside startup route gating.
14. Stop if evidence shows the authority state cannot be represented without a broader secure-storage registry, DB migration, QR session, or cutover primitive; that would be a scope error and should be handed to MIG-003/MIG-008 rather than absorbed here.

## Risks and Edge Cases

- Malformed secure-store authority JSON must not be treated as `active`, or corrupted local state could re-enable an old phone.
- Missing authority state must remain backward-compatible for existing users, or startup could strand current installs.
- Authority state must not live in the migrated database, or import can copy source-device authority to the new phone.
- `no_account` and import-staging states are tricky because the new phone may not yet have an identity/peer ID. The model should support a device-local staging record without pretending it is a fully active per-peer account.
- Startup must not call `_ensureMlKemKeys`, P2P startup, share-intent settlement, nearby refresh, push-preparation, or FTE/feed routing for blocked/staging states.
- A minimal blocked screen must not imply final migrated-out UX or erase behavior; MIG-011 owns the real UI.
- Flow events and logs must not include secrets or raw stored JSON. Coarse state names are acceptable.

## Exact Tests and Gates to Run

Direct tests:

```bash
flutter test test/features/account_migration/domain/account_migration_authority_state_test.dart
flutter test test/features/account_migration/application/account_migration_authority_repository_test.dart
flutter test test/features/account_migration/application/account_migration_import_precondition_test.dart
flutter test test/features/identity/application/startup_decision_test.dart
flutter test test/features/identity/presentation/screens/startup_router_test.dart
flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart
```

Conditional direct tests if onboarding code changes in MIG-001:

```bash
flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart
flutter test test/features/identity/presentation/screens/identity_choice_wired_test.dart
```

Named gate:

```bash
./scripts/run_test_gates.sh baseline
```

Conditional named gate only if the implementation changes bridge/P2P bootstrap behavior beyond reading authority and skipping startup routes:

```bash
./scripts/run_test_gates.sh transport
```

No simulator-backed closure is required to close MIG-001 because this session's behavior is a host-testable repository and startup-routing foundation. Later sessions own durable cutover/server leases, runtime network gates, user journey UX, and final end-to-end acceptance.

## Known-Failure Interpretation

- No current known failures were identified for the direct tests above during planning.
- New MIG-001 tests must pass; failures in those files are session-blocking.
- If `./scripts/run_test_gates.sh baseline` fails in a pre-existing unrelated test, the executor must capture the failing file/test name and compare it to the same command on the pre-change base or existing known-failure documentation before classifying it as unrelated. Do not mark MIG-001 complete with a red baseline unless the failure is proven pre-existing and unrelated.
- If the conditional Transport Gate is not run, the closure note must state why: implementation only altered route gating and did not change bridge/P2P bootstrap behavior.

## Done Criteria

- Account-migration authority model/repository/use-case tests exist and pass.
- Startup decision tests cover active, missing, migrated-out, migration-paused, cutover-blocked, import-staging, and failed-cleanup authority states.
- Startup router tests prove blocked/staging states do not start P2P or normal UI, while active/missing authority preserves current paths.
- The authority record is persisted only through `SecureKeyStore` and has no DB migration/table/row.
- `main.dart` and widget-test builders wire the new dependency without changing normal app startup behavior.
- Source proposal coverage/gap notes are updated for MIG-001 evidence, or a closure note records why no doc update was needed.
- Direct tests and `./scripts/run_test_gates.sh baseline` pass, or any baseline failure is documented as pre-existing/unrelated with evidence.
- No broad migration feature work from later sessions is implemented.

## Scope Guard

Do not implement:

- QR payloads, scanners, pairing sessions, session expiry, or confirmation codes.
- Migration export/import, SQLCipher snapshot, bundle manifests, secure-storage registry enumeration, staging secret promotion, DB key import, media manifests, file checksums, or transfer protocols.
- Server lease cleanup, `RendezvousUnregister`, `inbox:unregister_token`, push-token ownership, Go bridge/server changes, or relay behavior.
- Cross-entry runtime gates for resume, push handlers, retriers, avatar/profile downloads, group topic rejoin, group discovery loops, or pending queues beyond startup route blocking.
- Full migrated-out screen UX, erase action implementation, settings entry point, progress UI, wake lock, permission/storage UI, or final iOS journey.
- Android/cross-platform migration behavior.

Overengineering for MIG-001 includes adding a database migration, adding secure-storage enumeration, building a generic state-machine framework, adding transport/device acceptance, or changing P2P startup internals when a startup-route gate is sufficient.

## Accepted Differences / Intentionally Out of Scope

- The dedicated secure-storage authority key is intentionally device-local and should later be classified by MIG-003's registry, but MIG-001 does not build that registry.
- A minimal blocked/holding screen can satisfy startup safety tests, but the real migrated-out UX with erase action is intentionally deferred to MIG-011.
- `Move from old phone` full onboarding UX can remain out of MIG-001 unless implementation needs a minimal callback to prove import-start preconditions. MIG-011 owns the polished three-choice journey.
- Startup route gating is not the final runtime shutdown guarantee. MIG-009 must still thread the authority gate through resume, push, retriers, local discovery, group topics, profile/avatar downloads, and other network side effects.
- Durable cutover record ordering is represented only as state names/helpers in this foundation. MIG-008 owns `old_network_blocked`, `old_block_proof_received`, `new_active_committed`, server unregister, and recovery ordering.

## Dependency Impact

- MIG-002 depends on the import-start and authority precondition helpers so QR pairing cannot authorize export/import for an already active new phone.
- MIG-003 must classify the authority key as intentionally device-local and excluded from migration export while using the same policy for erase/reset cleanup.
- MIG-004/MIG-005/MIG-006 must not persist source-device authority in exported DB/file/group manifests.
- MIG-008 depends on this foundation for durable cutover state transitions.
- MIG-009 depends on this foundation for runtime network gates.
- MIG-011 depends on the blocked/staging decisions and any minimal holding surface when building the real user journey.
- MIG-012 depends on all earlier sessions to prove the full two-device journey; MIG-001 alone is only host-side foundation evidence.

## Execution Progress

- 2026-06-06T18:54:45Z - Parent controller dirty-worktree snapshot before execution. Files inspected or touched: `git status --short`. Command/result: `?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-001-plan.md`; `?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`. Decision/blocker: only rollout-scoped doc artifacts are dirty before execution; no blocker. Next action: spawn fresh execution/QA child for MIG-001.
- 2026-06-06T18:56:00Z - Before contract extraction. Files inspected or touched: plan file, implementation-execution-qa-orchestrator skill, graphify skill, `git status --short`; graph query command `graphify query "MIG-001 account migration authority foundation StartupRouter SecureKeyStore startup decision tests" --budget 2200`. Decision/blocker: graph exists and scoped context points to `StartupRouter` plus startup recovery tests; no blocker. Next action: extract exact MIG-001 scope, tests, gates, and non-goals for the Executor.
- 2026-06-06T18:56:00Z - Contract extracted. Files inspected or touched: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-001-plan.md`. Command/result: contract requires new account-migration authority model/repository/precondition tests, migration-aware startup decision/router tests, source proposal coverage update, direct tests listed in this plan, and `./scripts/run_test_gates.sh baseline`; Transport Gate is conditional only if bridge/P2P bootstrap behavior changes beyond authority reads and startup route skipping. Decision/blocker: execution contract is explicit and safe to execute without replanning; MIG-002+ scope is excluded. Next action: spawn fresh Executor for MIG-001.
- 2026-06-06T18:57:13Z - Executor started. Files inspected or touched: plan file, graphify skill, `git status --short`. Command/result: `git status --short` showed only the expected untracked MIG-001 plan and session-breakdown docs; graphify skill read succeeded; first implementation-skill read used an environment-mismatched `.system` path and failed before any source work. Decision/blocker: no blocker; use the listed local implementation skill path and execute only MIG-001. Next action: read the correct executor workflow notes, run scoped graphify queries, then add regression tests first.
- 2026-06-06T18:57:59Z - Scoped graph context collected. Files inspected or touched: implementation-execution-qa-orchestrator skill, graphify-out presence checks, graphify queries for startup/secure-store context. Command/result: `graphify-out/graph.json` exists; `graphify-out/wiki/index.md` is absent; queries identified `lib/features/identity/application/startup_decision.dart`, `lib/features/identity/presentation/startup_router.dart`, `lib/core/secure_storage/secure_key_store.dart`, and related startup tests as the relevant bounded source surface. Decision/blocker: no blocker; graphify package warning is non-blocking for query output. Next action: inspect exact code-entry files and add required red tests first.
- 2026-06-06T18:59:33Z - Code-entry inspection completed. Files inspected or touched: startup decision/router, `main.dart` startup wiring, secure key store/fake secure store, startup decision/router tests, proposal coverage/gap sections, session breakdown MIG-001 entry. Command/result: `rg StartupRouter` found constructor call sites in `main.dart`, startup notification/recovery/nearby tests, and share smoke tests; existing router already requires `SecureKeyStore`, so MIG-001 can derive the authority repository from that without adding a broad constructor seam. Decision/blocker: no blocker; leave onboarding third-choice UX out of scope. Next action: add new account-migration tests and focused startup regressions first.
- 2026-06-06T19:03:39Z - Regression tests added before production implementation. Files inspected or touched: new `test/features/account_migration/domain/account_migration_authority_state_test.dart`, new `test/features/account_migration/application/account_migration_authority_repository_test.dart`, new `test/features/account_migration/application/account_migration_import_precondition_test.dart`, updated `test/features/identity/application/startup_decision_test.dart`, updated `test/features/identity/presentation/screens/startup_router_recovery_test.dart`. Command/result: no test command run yet; tests intentionally reference the MIG-001 API that production code will now implement. Decision/blocker: no blocker; constructor seam can stay limited because router already has secure-store access. Next action: implement model, repository, precondition helper, blocked screen, and startup decision/router gating.
- 2026-06-06T19:05:59Z - Implementation completed before direct tests. Files inspected or touched: new `lib/features/account_migration/domain/models/account_migration_authority_state.dart`, new `lib/features/account_migration/domain/repositories/account_migration_authority_repository.dart`, new `lib/features/account_migration/application/account_migration_authority_repository_impl.dart`, new `lib/features/account_migration/application/account_migration_import_precondition.dart`, new `lib/features/account_migration/presentation/screens/account_migration_blocked_screen.dart`, updated `lib/features/identity/application/startup_decision.dart`, updated `lib/features/identity/presentation/startup_router.dart`, formatted touched Dart files. Command/result: `dart format ...` completed successfully. Decision/blocker: no bridge/P2P bootstrap internals changed; only authority read and startup route skipping were added. Next action: run required direct tests one by one, starting with account-migration domain model tests.
- 2026-06-06T19:06:18Z - Before direct test 1/6. Files inspected or touched: account-migration domain model and test. Command/result: starting `flutter test test/features/account_migration/domain/account_migration_authority_state_test.dart`. Decision/blocker: pending. Next action: record result and continue to repository direct test if green.
- 2026-06-06T19:07:28Z - After direct test 1/6 and before direct test 2/6. Files inspected or touched: account-migration domain model/test and repository test. Command/result: `flutter test test/features/account_migration/domain/account_migration_authority_state_test.dart` passed (`+6: All tests passed!`); starting `flutter test test/features/account_migration/application/account_migration_authority_repository_test.dart`. Decision/blocker: no blocker. Next action: record repository test result and continue to import-precondition direct test if green.
- 2026-06-06T19:07:57Z - After direct test 2/6 and before direct test 3/6. Files inspected or touched: account-migration repository/precondition tests. Command/result: `flutter test test/features/account_migration/application/account_migration_authority_repository_test.dart` passed (`+5: All tests passed!`); starting `flutter test test/features/account_migration/application/account_migration_import_precondition_test.dart`. Decision/blocker: no blocker. Next action: record import-precondition test result and continue to startup decision direct test if green.
- 2026-06-06T19:08:21Z - After direct test 3/6 and before direct test 4/6. Files inspected or touched: account-migration import-precondition test and startup decision test. Command/result: `flutter test test/features/account_migration/application/account_migration_import_precondition_test.dart` passed (`+6: All tests passed!`); starting `flutter test test/features/identity/application/startup_decision_test.dart`. Decision/blocker: no blocker. Next action: record startup decision test result and continue to startup router direct test if green.
- 2026-06-06T19:08:51Z - After direct test 4/6 and before direct test 5/6. Files inspected or touched: startup decision/router tests. Command/result: `flutter test test/features/identity/application/startup_decision_test.dart` passed (`+10: All tests passed!`); starting `flutter test test/features/identity/presentation/screens/startup_router_test.dart`. Decision/blocker: no blocker. Next action: record startup router test result and continue to startup router recovery direct test if green.
- 2026-06-06T19:09:19Z - After direct test 5/6 and before direct test 6/6. Files inspected or touched: startup router tests and recovery widget tests. Command/result: `flutter test test/features/identity/presentation/screens/startup_router_test.dart` passed (`+4: All tests passed!`); starting `flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart`. Decision/blocker: no blocker. Next action: record recovery widget test result and then run the Baseline Gate if green.
- 2026-06-06T19:09:59Z - After direct test 6/6 and before Baseline Gate. Files inspected or touched: startup router recovery widget test and baseline gate script. Command/result: `flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart` passed (`+5: All tests passed!`); starting `./scripts/run_test_gates.sh baseline`. Decision/blocker: no direct-test blockers remain. Next action: record baseline result or triage immediately if it fails.
- 2026-06-06T19:11:56Z - Baseline Gate failed, pending triage. Files inspected or touched: baseline gate output. Command/result: `./scripts/run_test_gates.sh baseline` ran host Flutter tests to `+103: All tests passed!`, then exited `1` after Flutter device resolution reported multiple connected devices and no `-d` choice (`Pixel 6`, several iOS simulators, `macOS`, `Chrome`) followed by `No devices are connected`. Decision/blocker: pending_triage; failure appears environmental/device-selection after host baseline tests, but script command source must be inspected before classification. Next action: inspect `scripts/run_test_gates.sh` baseline branch with `rg -n "baseline|flutter devices|wireless|device" scripts/run_test_gates.sh` and focused `sed` to identify the failing device check.
- 2026-06-06T19:12:41Z - Baseline Gate triage completed; retry starting with explicit device. Files inspected or touched: `scripts/run_test_gates.sh`. Command/result: script shows `BASELINE_TESTS` contains host tests plus `integration_test/loading_states_smoke_test.dart` and `integration_test/posts_phase1_fake_test.dart`; `run_gate_command` runs integration paths with `flutter test` and adds `-d "$FLUTTER_DEVICE_ID"` only when that environment variable is set. Decision/blocker: first baseline failure is an environment device-selection issue, not a MIG-001 test failure; use `macOS` from the available device list for a focused gate retry. Next action: run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- 2026-06-06T19:17:43Z - Baseline Gate retry completed. Files inspected or touched: baseline gate output. Command/result: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; host baseline tests reached `+103: All tests passed!`, `integration_test/loading_states_smoke_test.dart` reached `+7: All tests passed!`, and `integration_test/posts_phase1_fake_test.dart` reached `+1: All tests passed!`. Decision/blocker: no baseline blocker remains; Transport Gate is skipped because MIG-001 changed only secure-store authority reads and startup route gating, not bridge/P2P bootstrap internals or transport behavior. Next action: update source proposal coverage/gap notes for MIG-001 evidence, then run graphify update.
- 2026-06-06T19:18:34Z - Proposal evidence updated; graph update starting. Files inspected or touched: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`. Command/result: proposal coverage/gap notes now mark MIG-001 evidence for canonical typed states, device-local secure-store authority, import-staging/migrated-out startup block, active/missing preservation, active-account import rejection, and residual two-active/cutover/runtime gaps. Decision/blocker: no blocker. Next action: run `graphify update .` after code/doc modifications.
- 2026-06-06T18:56:47Z - Executor spawned/running. Files inspected or touched: plan execution progress. Command/result: spawned fresh Executor agent `019e9e4b-61e8-7be1-8c49-5184fbf992fa` with requested context `model: gpt-5.5`, `reasoning_effort: xhigh`. Decision/blocker: no blocker; controller will not overlap implementation. Next action: wait for Executor completion evidence.
- 2026-06-06T19:07:22Z - Executor bounded wait extended. Files inspected or touched: `git status --short`, `git diff --stat`, account-migration file list, plan execution progress. Command/result: first `wait_agent` timed out without final result, but assigned-step progress exists: new account-migration code/tests, startup decision/router changes, and direct test 1/6 started in plan. Decision/blocker: no spawn/tool blocker yet; one additional bounded wait is justified by real progress. Next action: wait once more for Executor final result.
- 2026-06-06T19:23:11Z - Executor child closed; local verification recovery starting. Files inspected or touched: `wait_agent`, `git status --short`, `git diff --stat`, plan execution progress, account-migration file list. Command/result: second bounded wait timed out without final Executor message; agent `019e9e4b-61e8-7be1-8c49-5184fbf992fa` was closed with previous status `running`. On-disk evidence shows a coherent MIG-001 landing, all direct tests recorded as passed by the child, baseline recorded as passed on retry with `FLUTTER_DEVICE_ID=macos`, and source proposal evidence updated. Decision/blocker: classify nested Executor final-message loss as `spawn_or_tool_failure` recovery, not a substantive implementation blocker yet; local verification will inspect diff and rerun required evidence before QA. Next action: inspect landed code/doc diff, then rerun direct tests and baseline exactly.
- 2026-06-06T19:24:22Z - Local Executor verification diff inspection completed; before direct test rerun 1/6. Files inspected or touched: account-migration model/repository/precondition code, blocked screen, startup decision/router, account-migration tests, startup decision/router recovery tests, source proposal diff. Command/result: diff is within MIG-001 scope; authority persists via `SecureKeyStore`, malformed records fail closed, blocked startup returns before normal UI/P2P paths, and proposal evidence notes are updated. Starting `flutter test test/features/account_migration/domain/account_migration_authority_state_test.dart`. Decision/blocker: no implementation blocker found during focused inspection; direct evidence pending. Next action: record direct test 1/6 result and continue.
- 2026-06-06T19:25:34Z - After direct test rerun 1/6; before direct test rerun 2/6. Files inspected or touched: account-migration domain model/test and repository test. Command/result: `flutter test test/features/account_migration/domain/account_migration_authority_state_test.dart` passed (`+6: All tests passed!`). Starting `flutter test test/features/account_migration/application/account_migration_authority_repository_test.dart`. Decision/blocker: no blocker. Next action: record repository test result and continue.
- 2026-06-06T19:26:02Z - After direct test rerun 2/6; before direct test rerun 3/6. Files inspected or touched: account-migration repository/precondition tests. Command/result: `flutter test test/features/account_migration/application/account_migration_authority_repository_test.dart` passed (`+5: All tests passed!`). Starting `flutter test test/features/account_migration/application/account_migration_import_precondition_test.dart`. Decision/blocker: no blocker. Next action: record import-precondition result and continue.
- 2026-06-06T19:26:28Z - After direct test rerun 3/6; before direct test rerun 4/6. Files inspected or touched: account-migration import-precondition test and startup decision test. Command/result: `flutter test test/features/account_migration/application/account_migration_import_precondition_test.dart` passed (`+6: All tests passed!`). Starting `flutter test test/features/identity/application/startup_decision_test.dart`. Decision/blocker: no blocker. Next action: record startup decision result and continue.
- 2026-06-06T19:26:51Z - After direct test rerun 4/6; before direct test rerun 5/6. Files inspected or touched: startup decision/router tests. Command/result: `flutter test test/features/identity/application/startup_decision_test.dart` passed (`+10: All tests passed!`). Starting `flutter test test/features/identity/presentation/screens/startup_router_test.dart`. Decision/blocker: no blocker. Next action: record startup router result and continue.
- 2026-06-06T19:27:16Z - After direct test rerun 5/6; before direct test rerun 6/6. Files inspected or touched: startup router tests and startup router recovery test. Command/result: `flutter test test/features/identity/presentation/screens/startup_router_test.dart` passed (`+4: All tests passed!`). Starting `flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart`. Decision/blocker: no blocker. Next action: record startup router recovery result and continue to Baseline Gate.
- 2026-06-06T19:27:58Z - After direct test rerun 6/6; before Baseline Gate rerun. Files inspected or touched: startup router recovery test and baseline gate evidence. Command/result: `flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart` passed (`+5: All tests passed!`). Prior Executor evidence already recorded the plain `./scripts/run_test_gates.sh baseline` environment/device-selection failure and focused retry path; starting `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. Decision/blocker: no direct-test blockers; baseline gate pending. Next action: record baseline result or triage if red.
- 2026-06-06T19:30:58Z - After Baseline Gate rerun; before graph update. Files inspected or touched: baseline gate output and graphify state. Command/result: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; host baseline tests reached `+103: All tests passed!`, `integration_test/loading_states_smoke_test.dart` reached `+7: All tests passed!`, and `integration_test/posts_phase1_fake_test.dart` reached `+1: All tests passed!`. Decision/blocker: no required test/gate blockers remain; Transport Gate is skipped because the implementation changed only authority reads and startup route gating, not bridge/P2P bootstrap internals. Next action: run `graphify update .` before QA.
- 2026-06-06T19:34:01Z - Local Executor verification completed; before QA Reviewer spawn. Files inspected or touched: `graphify update .`, `git status --short`, `git diff --stat`. Command/result: `graphify update .` completed with graph warning only and rebuilt `graphify-out/graph.json` plus `GRAPH_REPORT.md`; status shows MIG-001 source/test/doc changes plus the initial rollout docs and new account-migration files. Direct tests and Baseline Gate passed in local recovery. Decision/blocker: nested Executor final-message loss remains a recovered `spawn_or_tool_failure`; implementation evidence is sufficient to hand to QA. Next action: spawn fresh QA Reviewer for strict sufficiency review.
- 2026-06-06T19:34:47Z - QA Reviewer spawned/running. Files inspected or touched: plan execution progress. Command/result: spawned fresh QA Reviewer agent `019e9e6e-2ac3-7311-90e9-ea9b283b7cfb` with requested context `model: gpt-5.5`, `reasoning_effort: xhigh`. Decision/blocker: no blocker; fix pass pending QA findings. Next action: wait for QA completion evidence.
- 2026-06-06T19:35:23Z - QA Reviewer started local sufficiency review. Files inspected or touched: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-001-plan.md`, implementation-execution-qa-orchestrator skill, graphify skill, graph existence check. Command/result: plan contract, execution evidence, direct tests, baseline recovery, transport skip rationale, and Executor final-message recovery notes inspected; `graphify-out/graph.json` exists. Decision/blocker: review pending; no blocker identified before diff inspection. Next action: run scoped graphify query, inspect landed diffs/new files, verify required test/gate evidence, then record final QA decision.
- 2026-06-06T19:38:31Z - QA Reviewer completed local sufficiency review. Files inspected or touched: `git status --short`, `git diff --stat`, `git diff --name-only`, scoped `graphify query`, MIG-001 plan, source proposal diff, `lib/features/account_migration/**`, `lib/features/identity/application/startup_decision.dart`, `lib/features/identity/presentation/startup_router.dart`, `lib/main.dart` startup-router wiring, `lib/core/secure_storage/secure_key_store.dart`, `test/core/secure_storage/fake_secure_key_store.dart`, account-migration tests, startup decision/router tests, and `scripts/run_test_gates.sh`. Command/result: landed diff is confined to MIG-001 source/test/proposal docs; authority records use the `SecureKeyStore` point API and no DB migration/table; blocked decisions reach `AccountMigrationBlockedScreen` before normal UI, ML-KEM, nearby refresh, or P2P startup; plan records all six direct test reruns passing, the plain baseline environmental device-selection failure triaged, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passing, Transport Gate skipped with the required route-gating-only rationale, and `graphify update .` completed. Decision/blocker: no blocking issues; no fix pass required. Next action: controller may accept MIG-001 and proceed to closure/next session.
- 2026-06-06T19:39:32Z - Before final verdict work. Files inspected or touched: `git status --short`, execution progress, account-migration file list, touched-file diff stat, QA Reviewer final output. Command/result: QA found no blocking issues; only expected MIG-001 source/test/proposal changes and initial rollout docs are dirty. Decision/blocker: no blocker; final verdict can be `accepted`. Next action: write final execution verdict.
- 2026-06-06T19:39:32Z - Final verdict written. Files inspected or touched: MIG-001 plan. Command/result: final verdict `accepted`; no fix pass required; no blocking issues remain. Decision/blocker: MIG-001 is safe to consider complete for the named plan. Next action: parent controller can verify artifacts and move to its next session decision.

## Execution Verdict

- Final verdict: `accepted`
- Blocker class: none
- Spawned-agent isolation used: yes. Executor agent `019e9e4b-61e8-7be1-8c49-5184fbf992fa` was spawned, then closed after two bounded waits without a final message; QA Reviewer agent `019e9e6e-2ac3-7311-90e9-ea9b283b7cfb` completed.
- Local sequential fallback used: yes, only for Executor verification recovery after child final-message loss. The controller inspected the landed diff, reran all required direct tests, reran the Baseline Gate, updated graphify, and then used a fresh QA Reviewer.
- Files changed: account-migration authority model/repository/precondition/blocked-screen files under `lib/features/account_migration/`; startup decision/router updates under `lib/features/identity/`; direct account-migration and startup regression tests; source proposal MIG-001 coverage/gap notes; this plan's execution-progress/verdict notes.
- Tests added or updated: `test/features/account_migration/domain/account_migration_authority_state_test.dart`; `test/features/account_migration/application/account_migration_authority_repository_test.dart`; `test/features/account_migration/application/account_migration_import_precondition_test.dart`; `test/features/identity/application/startup_decision_test.dart`; `test/features/identity/presentation/screens/startup_router_recovery_test.dart`.
- Exact tests and gates run: all six required direct `flutter test` commands passed; `./scripts/run_test_gates.sh baseline` was attempted and failed only on environment device selection after host tests passed; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed with host `+103`, loading-states integration `+7`, and posts fake integration `+1`.
- Conditional gates: Transport Gate skipped because the implementation only added secure-store authority reads and startup route gating, with no bridge/P2P bootstrap internals or transport behavior changed.
- Blocking issues remaining: none.
- Non-blocking follow-ups deferred: none for MIG-001. Later sessions still own runtime network gates, durable cutover, secure-storage registry, full migrated-out UX, erase/reset, and end-to-end migration acceptance.
- Why safe to consider complete: the MIG-001 closure bar is covered by typed fail-closed authority state, `SecureKeyStore`-only persistence, import-start precondition gating, startup blocking before normal UI/P2P, active/missing behavior preservation, proposal evidence updates, required test/gate evidence, and QA acceptance with no blocking findings.

## Closure Audit

- Closure workflow: Completion Auditor completed; Closure Writer completed; Closure Reviewer completed.
- Closure verdict: `closed` for MIG-001 only.
- Completed-plan evidence: execution verdict is `accepted`; QA Reviewer found no blocking issues; all six required direct tests passed; the plain Baseline Gate failed only on environment device selection after host tests passed; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed with host `+103`, loading-states integration `+7`, and posts fake integration `+1`.
- What is now closed: the account-migration authority state foundation, device-local secure-store authority repository, import-start precondition gate, migration-aware startup decision, and startup-router blocked path that avoids normal UI/P2P for blocked/staging/migrated-out authority states.
- Residual-only items for MIG-001: none. The dedicated authority key still needs registry classification and erase/reset cleanup in MIG-003, but that is a later-session responsibility rather than a MIG-001 follow-up.
- Still-open program items: MIG-002 through MIG-012 remain pending, including QR pairing, secure-storage registry, DB/file export/import, transfer, cutover, runtime network gates, pending-work ownership, user journey UX, and final device acceptance.
- Accepted differences: no onboarding `Move from old phone` journey was added; no database migration/table, secure-storage enumeration, QR/session security, transfer, bridge/P2P bootstrap internals, server cleanup, full migrated-out UX, erase/reset, or simulator acceptance was implemented in MIG-001.
- Maintenance-time safety gates: the six direct `flutter test` commands listed in this plan and the Baseline Gate remain the session's safety reference. The Transport Gate remains out of scope unless future work changes bridge/P2P bootstrap internals or transport behavior.
- Closure reviewer result: doc wording now distinguishes completed MIG-001 scope from still-open program scope and preserves the planning reviewer/arbiter notes as historical pre-execution context.
- Why this doc is safe as a closure reference: it records the exact landed scope, accepted evidence, environment-only baseline retry, Transport Gate skip rationale, accepted deferrals, and the boundary that the overall Move Account program is still open.

## Planning Reviewer Findings (Historical)

- Verdict: sufficient with one wording adjustment, now applied.
- Missing files/tests/gates: none structurally. The plan names the new model/repository/precondition tests, startup decision/router regressions, direct commands, and Baseline Gate.
- Stale assumptions at planning time: none found. At that point, current code still had identity/contact-only startup decisions and no `lib/` account-migration authority gate; MIG-001 implementation has since added that gate.
- Overengineering check: acceptable. The plan explicitly forbids DB migrations, secure-storage enumeration, QR pairing, transfer, cutover, runtime gates, and full UX.
- Decomposition check: sufficient. MIG-001 stays a foundation slice and leaves MIG-008/MIG-009/MIG-011/MIG-012 evidence to later sessions.
- Minimum needed for sufficiency: no additional structural work.

## Planning Arbiter Decision (Historical)

- Final classification: `execution-ready`.
- Structural blockers: none.
- Incremental details deferred: exact class/file naming for the new repository can follow local implementation style during execution; no need to replan for that.
- Accepted differences: full migration entry UI, migrated-out erase UX, QR/session security, secure-storage registry, DB import/export, cutover/server cleanup, runtime network gates, pending-work ownership, and final acceptance remain assigned to later sessions.
- Stop rule: reviewer found no structural blocker after the wording adjustment, so the plan stops here.
