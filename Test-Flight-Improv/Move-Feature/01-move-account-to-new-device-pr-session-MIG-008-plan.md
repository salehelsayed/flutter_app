Status: session_closed - MIG-008 session scope only; QA retry accepted; MIG-009 through MIG-012 plus deferred-last MIG-006 remain open.

# MIG-008 Plan - Durable Cutover And Server Lease Cleanup

## Planning Progress

- `2026-06-07T16:16:58Z` - role: Planner/Reviewer/Arbiter completed by controller fallback; files inspected: stalled child output, this plan artifact, source proposal durable cutover and runtime acceptance rows, breakdown MIG-008/MIG-009 ledger rows, bridge/server unregister surfaces, and gate definitions from `scripts/run_test_gates.sh`; decision/blocker: no MIG-008 planning blocker. The spawned planning child persisted evidence collection but stalled before writing the full contract, so the controller stopped it and completed this doc-scoped plan locally. Plan is execution-ready for MIG-008 only and must not run MIG-006 group simulator or release evidence.
- `2026-06-07T16:13:05Z` - role: Evidence Collector completed; files inspected: source proposal cutover rows, MIG-008/MIG-009 breakdown rows, `test-gate-definitions.md`, `scripts/run_test_gates.sh`, account-migration authority model/repository/tests, startup-router recovery tests, Dart bridge clients/tests, Go bridge/node/rendezvous/inbox files, relay rendezvous/inbox/push-token files/tests, platform bridge method handlers, graphify query results; decision/blocker: no planning blocker, but MIG-008 must be narrow to durable cutover primitives and unregister/lease cleanup while leaving full runtime entry-point gates to MIG-009; next action: Planner drafts execution-ready contract and checklist mapping.
- `2026-06-07T16:10:13Z` - role: Evidence Collector started; files inspected: existing MIG-008 plan stub, `graphify-out/graph.json` via `graphify query`, local `graphify` skill instructions; decision/blocker: planning surface confirmed and repo graph available, but the first graph query was broad and must be supplemented with source docs and targeted code/test evidence; next action: inspect source proposal, reusable breakdown, gate definitions, and direct migration/bridge/server seams.
- `2026-06-07T16:07:22Z` - role: controller intake; files inspected: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`, MIG-008 breakdown row, MIG-007 closure artifacts, source proposal cutover/runtime acceptance rows; decision/blocker: MIG-008 is the next allowed dependency-satisfied session because MIG-001, MIG-004, and MIG-007 are closed for their own scopes; MIG-006 is deliberately deferred-last/evidence-gated by user override and must not be treated as failed or closed; next action: spawn a fresh `$implementation-plan-orchestrator` child with `model: gpt-5.5` and `reasoning_effort: xhigh` to produce an execution-safe plan.

## Execution Progress

- `2026-06-07T17:39:37Z` - phase: QA retry start after Executor fix-pass 1; files inspected or touched so far: this plan progress section and `graphify-out/graph.json` via required pre-inspection query; last completed command/result: `graphify query "MIG-008 migration cutover coordinator commitNewActive markOldMigratedOutAfterNewActive durable proof sessionId accountPeerId oldPhone newPhone active migratedOut authority"` completed with BFS depth 2 and surfaced `migration_cutover_coordinator.dart`, `commitNewActive`, `markOldMigratedOutAfterNewActive`, proof helpers, cutover record/repository, and authority repository; current command/log being inspected: none; decision/blocker: `pending_triage` for retry validation of same-session/account/role proof checks and no unauthorized `active`/`migratedOut` authority writes; next action: inspect only `/tmp/mig008_qa_last.txt`, `/tmp/mig008_fix1_executor_last.txt`, the MIG-008 plan contract, and scoped coordinator/test/bridge files as needed, then run focused non-group verification. Prohibited group/release commands remain out of scope; MIG-006 stays deferred-last/evidence-gated and overall Move Account doc closure will not be claimed.
- `2026-06-07T17:40:59Z` - phase: QA retry focused verification start; files inspected or touched: this plan, `/tmp/mig008_qa_last.txt`, `/tmp/mig008_fix1_executor_last.txt`, `lib/features/account_migration/application/migration_cutover_coordinator.dart`, `test/features/account_migration/application/migration_cutover_coordinator_test.dart`, and the cutover record proof getters needed to validate durable proof semantics; last completed command/result: scoped inspection confirmed proof guards now require matching `sessionId`, matching `accountPeerId`, expected proof role, and proof getters requiring durable timestamps before `active`/`migratedOut` writes; current command/log being inspected: about to run `flutter test test/features/account_migration/application/migration_cutover_coordinator_test.dart test/core/bridge/p2p_bridge_client_test.dart test/core/bridge/go_bridge_client_test.dart` followed by `git diff --check`; decision/blocker: `pending_verification`; next action: capture focused command results and account for the untracked-file caveat, since the scoped MIG-008 plan/coordinator/test files are not known to git and therefore produce no tracked patch body for `git diff --check`.
- `2026-06-07T17:42:48Z` - phase: QA retry final verdict; files inspected or touched: this plan, `/tmp/mig008_qa_last.txt`, `/tmp/mig008_fix1_executor_last.txt`, `lib/features/account_migration/application/migration_cutover_coordinator.dart`, `test/features/account_migration/application/migration_cutover_coordinator_test.dart`, and the cutover record proof getters; last completed command/result: `flutter test test/features/account_migration/application/migration_cutover_coordinator_test.dart test/core/bridge/p2p_bridge_client_test.dart test/core/bridge/go_bridge_client_test.dart` passed with `+158`; `git diff --check` passed with no output; supplemental `git diff --no-index --check /dev/null` checks on the untracked MIG-008 plan/coordinator/test files produced no whitespace-warning output, with exit code `1` interpreted as the no-index file-difference signal; current command/log being inspected: none; decision/blocker: `qa_accepted` for MIG-008 session scope only. The prior blocker is fixed: `commitNewActive` validates same `sessionId`, same `accountPeerId`, expected `oldPhone` role, and durable old-block proof before saving `active`; `markOldMigratedOutAfterNewActive` validates same `sessionId`, same `accountPeerId`, expected `newPhone` role, and durable new-active proof before saving `migratedOut` or invoking lease cleanup; regressions cover mismatched session/account/role with no unauthorized authority writes or cleanup calls. No prohibited group/release commands were run. MIG-009 through MIG-012 plus deferred-last MIG-006 remain open, and this does not claim final acceptance for the overall Move Account doc.
- `2026-06-07T17:37:20Z` - phase: Executor fix-pass 1 complete; files touched: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-008-plan.md`, `lib/features/account_migration/application/migration_cutover_coordinator.dart`, `test/features/account_migration/application/migration_cutover_coordinator_test.dart`; files inspected but not changed: `/tmp/mig008_qa_last.txt`, `lib/features/account_migration/domain/models/migration_cutover_record.dart`; generated graph outputs reported by command: `graphify-out/graph.json` and `graphify-out/GRAPH_REPORT.md`; commands/results: `dart format lib/features/account_migration/application/migration_cutover_coordinator.dart test/features/account_migration/application/migration_cutover_coordinator_test.dart` passed and formatted the test file; `flutter test test/features/account_migration/application/migration_cutover_coordinator_test.dart test/core/bridge/p2p_bridge_client_test.dart test/core/bridge/go_bridge_client_test.dart` passed with `+158`; `git diff --check` passed with no output before and after graph update, with caveat that the scoped MIG-008 files are currently untracked in this worktree so the command has no tracked diff for those files; `graphify update .` passed after AST extraction of `4938/4938` files and rebuilt `92532` nodes, `163050` edges, and `4020` communities, with only the existing graphify skill/package version warning and HTML-viz size skip; decision/blocker: QA blocker addressed by requiring same `sessionId`, same `accountPeerId`, expected proof role, and durable proof timestamp before writing `active` or `migratedOut`; remaining caveats: MIG-006 remains deliberately deferred-last/evidence-gated, MIG-009 runtime entry-point gates remain out of scope, Android AAR regeneration remains the prior non-blocking environment caveat, and this does not close or claim final acceptance for the overall Move Account doc; status: `fix-pass-1-complete-pending-qa`.
- `2026-06-07T17:30:09Z` - phase: Executor fix-pass 1 start; files inspected or touched: this plan progress section and `graphify-out/graph.json` via required pre-inspection query; last completed command/result: `graphify query "How does MigrationCutoverCoordinator validate cutover proofs and write active or migratedOut account migration states?" --budget 1800` completed with BFS depth 2 and surfaced `migration_cutover_coordinator.dart`, cutover record/repository, authority repository, `commitNewActive`, `markOldMigratedOutAfterNewActive`, `recordOldBlockProofReceived`, and recovery helpers; current command/log being inspected: none; decision/blocker: `pending_triage` for QA blocker requiring same-session/account/role proof validation before writing `active` or `migratedOut`; next action: inspect only `/tmp/mig008_qa_last.txt`, the scoped coordinator/model files as needed, and the scoped cutover coordinator tests, then implement bounded validation regressions and rerun the required focused commands. No MIG-006 group simulator, `reliability-sim group`, full group simulator, release acceptance evidence, or overall Move Account closure will be run or claimed.
- `2026-06-07T17:28:29Z` - phase: parent-controller fix-pass routing; files inspected or touched: this plan and `/tmp/mig008_qa_last.txt`; last completed command/result: fresh QA Reviewer returned `qa_blocking_issue` after focused Flutter `+156`, Go bridge unregister slice, Go relay unregister slice, and `git diff --check` all passed; current command/log being inspected: none; decision/blocker: implementation-owned blocker inside MIG-008 cutover coordinator proof validation; no prohibited MIG-006 group/release command has been run and MIG-006 remains deferred-last/evidence-gated; next action: spawn fresh Executor fix pass 1 to add proof-identity validation and stale/mismatched proof regressions, then rerun focused non-group tests before a fresh QA retry.
- `2026-06-07T17:21:24Z` - phase: QA Reviewer start; files inspected or touched: this plan progress section and `graphify-out/graph.json` via required pre-inspection query; last completed command/result: `graphify query "MIG-008 Move Account new device cutover old block proof active authority database migration rendezvous inbox unregister push token Go relay" --budget 1800` completed with BFS depth 2 and 69 scoped nodes, surfacing account-migration authority/import-precondition, rendezvous unregister, and relay/node unregister surfaces; current command/log being inspected: none; decision/blocker: `pending_triage`, no QA verdict yet, MIG-006 remains deliberately deferred-last/evidence-gated and prohibited group/release commands will not be run; next action: inspect the MIG-008 contract, executor handoff, scoped diffs, and focused test/gate evidence for session-only QA.
- `2026-06-07T17:25:20Z` - phase: QA focused command start; files inspected or touched: cutover coordinator/model/repository tests, Dart bridge helpers/tests, platform bridge method handlers, Go bridge/node/relay unregister surfaces, source/breakdown status rows; last completed command/result: static QA inspection found old-block-before-new-active ordering, explicit unregister bridge routing, idempotent relay unregister behavior, and no MIG-009/MIG-006 overclaim in scoped docs; current command/log being inspected: `flutter test test/features/account_migration/application/migration_cutover_coordinator_test.dart test/core/bridge/p2p_bridge_client_test.dart test/core/bridge/go_bridge_client_test.dart`, `(cd go-mknoon && go test ./bridge -run 'RendezvousUnregister|InboxUnregister' -count=1)`, `(cd go-relay-server && go test ./... -run 'Unregister|PushTokenStore_UnregisterIsIdempotent|RedisPushTokenBackend_SurvivesAcrossClients' -count=1)`, and `git diff --check`; decision/blocker: `pending_triage`, no current QA blocker; next action: capture the focused command results and write the MIG-008-only QA verdict.
- `2026-06-07T17:26:46Z` - phase: QA final verdict; files inspected or touched: `lib/features/account_migration/application/migration_cutover_coordinator.dart`, `test/features/account_migration/application/migration_cutover_coordinator_test.dart`, `lib/features/account_migration/domain/models/migration_cutover_record.dart`, secure-store authority/cutover repositories, Dart bridge helpers/tests, iOS/macOS/Android method handlers, Go bridge/node inbox unregister surfaces, relay rendezvous/push-token unregister tests, source proposal and breakdown status rows; last completed command/result: QA rerun `flutter test test/features/account_migration/application/migration_cutover_coordinator_test.dart test/core/bridge/p2p_bridge_client_test.dart test/core/bridge/go_bridge_client_test.dart` passed with `+156`, `(cd go-mknoon && go test ./bridge -run 'RendezvousUnregister|InboxUnregister' -count=1)` passed, `(cd go-relay-server && go test ./... -run 'Unregister|PushTokenStore_UnregisterIsIdempotent|RedisPushTokenBackend_SurvivesAcrossClients' -count=1)` passed, and `git diff --check` passed; current command/log being inspected: none; decision/blocker: `qa_blocking_issue` - `commitNewActive` accepts any `MigrationCutoverRecord` where `provesOldNetworkBlocked` is true and can write `AccountMigrationAuthorityState.active` without validating that the old-block proof belongs to the same `sessionId`, `accountPeerId`, and old-phone role. Existing tests cover an unproved record and a matching proof, but not stale/mismatched proof reuse. This leaves a code path where a stale proof from another account/session can activate the new phone while the current old-phone block proof is absent. Related old-phone `markOldMigratedOutAfterNewActive` has the same proof-identity gap for new-active proof. No prohibited MIG-006 group simulator/release commands were run; MIG-009 remains open; Android AAR regeneration/verification remains a non-blocking environment caveat under the current MIG-008 gate list, but cannot change this blocking verdict. Next action: bounded fix pass should add proof-identity validation and regression tests before QA retry.
- `2026-06-07T17:20:04Z` - phase: parent-controller checkpoint before QA; files inspected or touched: this plan, source proposal path, reusable breakdown path, executor handoff summary in `/tmp/mig008_executor_last.txt`; last completed command/result: MIG-008 Executor reported implementation complete with focused Flutter tests, Go bridge/node/relay tests, `git diff --check`, completeness-check, macOS baseline after binding refresh, and allowed transport gate passing; current command/log being inspected: none; decision/blocker: no current MIG-008 blocker recorded, Android generated AAR refresh remains an environment-limited QA caveat because the Android SDK path has no usable NDK; MIG-006 remains deliberately deferred-last/evidence-gated, not failed or closed, and no group simulator/release evidence will be run; next action: spawn a fresh MIG-008 QA Reviewer with `model: gpt-5.5` and `reasoning_effort: xhigh` to validate the landed cutover/lease-cleanup scope before closure.
- `2026-06-07T16:18:33Z` - phase: Executor spawn requested; files inspected or touched: this plan, source proposal, reusable breakdown, execution skill instructions; command currently running: none yet; decision/blocker: no execution blocker, plan is execution-ready and MIG-006 remains deferred-last; next action: spawn a fresh Executor agent with `model: gpt-5.5` and `reasoning_effort: xhigh` for the first MIG-008 implementation pass.
- `2026-06-07T16:22:23Z` - phase: Executor intake and scoped inspection; files inspected: local graphify skill, this plan, repo DB/test skill references, source proposal cutover rows, reusable breakdown MIG-008 row, account-migration authority model/repository/tests, startup decision, Dart bridge helpers/tests, Go bridge/node rendezvous/inbox surfaces, relay rendezvous/inbox/push-token stores/tests, iOS/macOS/Android method-channel handlers; commands run: `graphify query "MIG-008 durable account migration cutover authority repository bridge unregister rendezvous push-token relay node surfaces tests" --budget 2500`, `graphify query "p2p_bridge_client go_bridge_client callP2P register discover push token inbox unregister command method channels bridge.go" --budget 3000`, targeted `rg`/`sed` inspection commands, `git status --short`; decision/blocker: no execution blocker. Existing Go node/relay already contain `RendezvousUnregister` and idempotent push-token unregister storage behavior, but Dart/platform/Go bridge command routing and the account-migration cutover coordinator/retry records are missing; next action: implement narrow secure-store-backed cutover records/coordinator plus explicit rendezvous/push-token unregister bridge surfaces.
- `2026-06-07T16:57:17Z` - phase: implementation and focused verification; files touched: secure-store-backed migration cutover model/repository/coordinator/bridge cleanup adapter, account-migration cutover tests, Dart P2P/Go bridge helpers/tests, iOS/macOS/Android method-channel routing, Go bridge/node inbox unregister export, relay push-token idempotency tests; commands run: `dart format ...` on changed Dart files, `gofmt -w ...` on changed Go files, `flutter test test/features/account_migration/application/migration_cutover_coordinator_test.dart test/features/account_migration/domain/account_migration_authority_state_test.dart test/features/account_migration/application/account_migration_authority_repository_test.dart test/features/identity/application/startup_decision_test.dart test/features/identity/presentation/screens/startup_router_recovery_test.dart test/core/bridge/p2p_bridge_client_test.dart test/core/bridge/go_bridge_client_test.dart` passed with `+184`; first `(cd go-mknoon && go test ./...)` passed bridge/cmd/crypto/identity/internal then failed in `github.com/mknoon/go-mknoon/node` after a long noisy run without a captured test-name failure in visible output; follow-up `(cd go-mknoon && go test ./node -failfast -count=1)` passed in `431.473s`; rerun `(cd go-mknoon && go test ./...)` passed, including `github.com/mknoon/go-mknoon/node 435.933s`; `(cd go-relay-server && go test ./...)` passed in `10.000s`; decision/blocker: no code blocker. The initial Go node full-sweep failure did not reproduce on fail-fast package rerun or full rerun; next action: run diff/completeness/baseline/device/transport gates allowed by MIG-008 sequencing.
- `2026-06-07T16:35:20Z` - phase: Executor implementation checkpoint; files touched: new cutover record/repository/coordinator and bridge-cleanup Dart files, Dart bridge helpers and GoBridge command maps, Android/iOS/macOS bridge dispatchers, Go bridge/node inbox unregister surfaces, relay push-token unregister tests, focused account-migration and bridge tests; commands run: `dart format ...`, `gofmt -w ...`, focused `flutter test` bundle from Required Tests; decision/blocker: no current blocker. The first focused Flutter run exposed an updated command-count assertion still expecting 51 bridge commands; the executor corrected it to 53 and reran the focused bundle successfully before starting Go package verification. Command currently running: `(cd go-mknoon && go test ./...)` inside the MIG-008 executor session. MIG-006 remains deliberately deferred-last and no group simulator or release evidence has been run; next action: wait for Go/relay/repo-gate results, then spawn MIG-008 QA if execution passes.
- `2026-06-07T16:55:41Z` - phase: Executor Go gate isolation checkpoint; files touched since last checkpoint: same MIG-008 implementation/test set, no MIG-006 artifacts; commands observed: initial `(cd go-mknoon && go test ./...)`, isolated `go test ./node -failfast -count=1`, then a second full `(cd go-mknoon && go test ./...)`; decision/blocker: no final blocker yet. The bridge and smaller Go packages passed, while the long `go-mknoon/node` package is still running quietly in the second full sweep. No group simulator, group reliability gate, or release acceptance evidence has been run; next action: capture the node package pass/failure/timeout as the concrete Go gate result before allowing relay/repo gates or QA.
- `2026-06-07T17:13:34Z` - phase: repo gates, generated binding refresh, and Executor handoff; files touched: MIG-008 implementation/test files plus regenerated iOS/macOS `GoMknoon.xcframework` artifacts and this plan; commands run: `git diff --check` passed; `flutter devices --machine` passed and confirmed simulator `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` available; `./scripts/run_test_gates.sh completeness-check` passed with `800/800 test files classified`; first `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` failed during the macOS integration build because the generated GoMknoon framework did not yet expose `BridgeRendezvousUnregister` and `BridgeInboxUnregisterToken`; `./scripts/ensure_go_macos_bindings.sh` passed, `./scripts/ensure_go_ios_bindings.sh` regenerated iOS bindings, and `./scripts/verify_gomobile_bindings.sh macos` plus `./scripts/verify_gomobile_bindings.sh ios` passed; rerun `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed, including host tests `+105`, loading states smoke `+7`, and posts phase fake `+1`; `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed, with background reconnect skipped by its test guard, WiFi/relay fallback smoke passing self-contained, transport E2E passing self-contained (`4/4`, `30/30` concurrent custody), and media stable-ID smoke passing `+7`. Android generated binding refresh was attempted but remains environment-limited: `./scripts/ensure_go_android_bindings.sh` exited `126` because the script is not executable, and `bash scripts/ensure_go_android_bindings.sh` failed because `/Users/I560101/Library/Android/sdk` has no usable NDK; the Android Kotlin/Go source surfaces are implemented, but `android/app/libs/GoMknoon.aar` was not regenerated or verified in this environment. Decision/blocker: no MIG-008 Executor code blocker for the required focused tests and allowed gates. Android generated artifact verification is a QA caveat if Android build evidence is requested. No group simulator, `reliability-sim group`, `run_with_devices.sh group`, MIG-006 release evidence, or overall Move Account closure was run or claimed; next action: QA reviewer validates MIG-008 only while MIG-009, MIG-010, MIG-011, MIG-012, and deferred MIG-006 remain open.

## Recovery Input

- `2026-06-07T17:28:29Z` - blocker class: implementation-owned same-session QA blocker; blocker signature: `MIG-008/proof-identity-validation/lib/features/account_migration/application/migration_cutover_coordinator.dart/test/features/account_migration/application/migration_cutover_coordinator_test.dart`; failing contract: `commitNewActive` must not accept a stale or mismatched old-block proof and `markOldMigratedOutAfterNewActive` must not accept a stale or mismatched new-active proof. QA found that current checks rely on durable booleans/timestamps but do not verify same `sessionId`, same `accountPeerId`, or expected proof role. Required fix scope: add narrow proof-identity validation in the cutover coordinator, add regression tests for mismatched session/account/role that prove no `active` or `migratedOut` authority is written, run focused cutover/bridge tests plus `git diff --check`, and keep MIG-006 group/release evidence deferred.

## Sequencing Override

MIG-006 remains deferred-last with commands 29-123 and final group verification still required. Do not run `run_with_devices.sh group`, the full group simulator, or MIG-006 release evidence while planning or executing MIG-008. Do not close the overall Move Account doc while MIG-006 remains deferred.

## Session Objective

Implement durable cutover and server lease cleanup primitives for the Move Account flow. MIG-008 owns the state machine and command surfaces that prove the old phone is durably network-blocked or migrated out before the new phone can become active, plus explicit personal rendezvous and push-token lease cleanup for the migrated-out peer ID.

This session must expose the primitives that later sessions consume. It must not implement the full runtime gate fanout assigned to MIG-009, pending work ownership assigned to MIG-010, user journey UI assigned to MIG-011, final acceptance assigned to MIG-012, or deferred MIG-006 group release evidence.

## Evidence Baseline

- Source proposal requires new-phone activation only after database, secure storage, media, manifest, identity, and durable cutover pass; old-phone network-blocked or migrated-out state must be durable before new-phone normal startup.
- Durable records named by the source proposal: `old_network_blocked`, `old_block_proof_received`, and `new_active_committed`.
- Device-local authority state must stay outside the migrated database bundle: the old phone writes local `migrated_out`; the new phone writes local `active` only after commit.
- Existing bridge/server evidence says server-side unregister primitives exist below Dart, but Dart bridge command surfaces expose register/discover and push-token register without matching migration cutover commands.
- MIG-001 already provides typed account authority states and startup gating; MIG-004/MIG-005 provide staging foundations; MIG-007 provides the encrypted segmented transfer seam. MIG-008 consumes these but does not need MIG-006 evidence because MIG-006 is deferred-last by explicit override.

## Scope

- Add or extend durable cutover domain models that represent old-phone and new-phone cutover records, commit phases, timestamps, peer/account identity, retryable failure state, and recovery decisions.
- Add helper-backed persistence for cutover records, preferably in the account-migration repository layer and outside exported database bundles.
- Add a cutover coordinator/use case that enforces old-network-blocked before new-active commit and resolves interrupted states without ever producing two active devices.
- Add explicit bridge command helpers for personal rendezvous unregister and inbox push-token unregister.
- Wire the bridge/server command path far enough that Dart can invoke the unregister primitives deterministically in tests.
- Add stale old-device push-token clear/ignore behavior at the cutover primitive boundary; full runtime prevention of future registration belongs to MIG-009.
- Add recovery rules for interruption before old block, after old block but before new active, after new active, and after lease-cleanup failure.
- Update this plan, the source proposal evidence/gaps, and the reusable breakdown ledger during closure.

## Out Of Scope

- MIG-006 group simulator or release evidence.
- Full migrated-out runtime network gate fanout across every startup/resume/watchdog/listener/queue entry point; that is MIG-009.
- Pending send/retry/upload queue migration and ownership; that is MIG-010.
- Pairing/transfer UX, progress UI, wake lock, migrated-out old-phone screen, and final user journey; that is MIG-011.
- Physical paired iOS-to-iOS release acceptance and final doc closure; that is MIG-012 plus deferred MIG-006.
- Reworking account identity policy or adding sibling multi-device support.

## Implementation Checklist

1. Inspect current authority state and repository files:
   - `lib/features/account_migration/domain/models/account_migration_authority_state.dart`
   - `lib/features/account_migration/domain/repositories/account_migration_authority_repository.dart`
   - `lib/features/account_migration/application/account_migration_authority_repository_impl.dart`
   - existing migration staging helpers in `lib/features/account_migration/application/`
2. Add cutover state/record types and persistence with explicit account ID, peer ID, device role, phase, durable proof flags, timestamps, and sanitized failure details.
3. Add a cutover coordinator/use case that:
   - writes old-phone `migration_cutover_pending_blocked` or equivalent old-network-blocked record before any new-phone active commit,
   - treats missing old block proof as retryable/staged, not active,
   - commits new-phone active only after import verification input and old block proof,
   - writes old-phone migrated-out after successful commit,
   - preserves zero-active retry/cleanup states instead of allowing two active states,
   - is idempotent across retries and duplicate acknowledgements.
4. Inspect and extend bridge command surfaces:
   - `lib/core/bridge/p2p_bridge_client.dart`
   - `lib/core/bridge/go_bridge_client.dart`
   - platform bridge handlers under `macos/Runner/`, `ios/Runner/`, and `android/app/src/main/kotlin/com/mknoon/app/`
   - `go-mknoon/bridge/bridge.go`
   - `go-mknoon/node/rendezvous.go`
   - `go-mknoon/node/inbox.go`
   - `go-relay-server/inbox.go`
5. Add Dart helpers such as `callP2PRendezvousUnregister` and `callP2PInboxUnregisterToken` if no equivalent exists. Keep logs sanitized.
6. Add missing Go node/bridge handlers if needed so `RendezvousUnregister` and `inbox:unregister_token` can be invoked from Flutter.
7. Confirm relay unregister-token behavior is idempotent and tested for memory and Redis-backed stores where applicable.
8. Add recovery tests proving interrupted cutover branches and lease-cleanup retry behavior.
9. Keep all public APIs narrow and local to account migration or existing bridge helper patterns.

## Required Tests And Gates

Run focused tests after implementation, adding files as needed:

```bash
flutter test test/features/account_migration/application/migration_cutover_coordinator_test.dart test/features/account_migration/domain/account_migration_authority_state_test.dart test/features/account_migration/application/account_migration_authority_repository_test.dart test/features/identity/application/startup_decision_test.dart test/features/identity/presentation/screens/startup_router_recovery_test.dart test/core/bridge/p2p_bridge_client_test.dart test/core/bridge/go_bridge_client_test.dart
```

Run Go coverage for changed bridge/node/relay surfaces:

```bash
(cd go-mknoon && go test ./...)
(cd go-relay-server && go test ./...)
```

Run repo gates:

```bash
git diff --check
./scripts/run_test_gates.sh completeness-check
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
flutter devices --machine
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport
```

Use the simulator ID above only if it is still present from `flutter devices --machine`; otherwise choose a currently available non-group target. Do not run `run_with_devices.sh group`, `./scripts/run_test_gates.sh reliability-sim group`, or any MIG-006 release acceptance evidence.

## Acceptance Bar

- Old-phone network-blocked or migrated-out proof is durable before new-phone active commit.
- Missing old block proof cannot promote the new phone to active.
- Crashes before old block, between old block and new active, after new active, and during server lease cleanup resolve to retry/cleanup/new-active-old-migrated-out states without two active devices.
- Personal `RendezvousUnregister` and `inbox:unregister_token` are explicitly issued by the migration cutover primitive or scheduled as retryable lease cleanup, rather than assuming `node:stop` is enough.
- Stale old-device push-token material is cleared or ignored at the migration cutover boundary.
- Lease cleanup is idempotent and retry-safe; exact best-effort versus blocking behavior is documented in code/tests and the source proposal update.
- Tests and gates above pass, or a concrete blocker with command output and artifact paths is recorded.

## Reviewer Contract

The QA reviewer must verify:

- No code path can mark the new phone active while old block proof is absent.
- Imported database rows cannot carry source-device active/migrated-out authority.
- Unregister commands are present at every affected bridge layer and covered by tests.
- Go relay/node unregister behavior is idempotent and does not treat missing leases as fatal.
- Runtime gate rollout has not been silently claimed; MIG-009 remains open for runtime entry points.
- MIG-006 remains deferred-last/evidence-gated, not failed and not closed.

## Closure Instructions

When execution and QA finish, update:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md` with MIG-008 evidence and remaining acceptance gaps.
- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md` ledger row for MIG-008 and closure deltas.
- This plan with `Execution Progress`, `Closure Progress`, and a session verdict.

Do not write a final overall Move Account verdict while MIG-006 is deferred or MIG-009 through MIG-012 remain pending.

## Closure Progress

- `2026-06-07T18:08:00Z` - role: Completion Auditor completed; files inspected: this plan, `/tmp/mig008_executor_last.txt`, `/tmp/mig008_qa_last.txt`, `/tmp/mig008_fix1_executor_last.txt`, `/tmp/mig008_qa2_last.txt`, source proposal cutover/runtime/evidence sections, breakdown MIG-008 row and closure deltas, `migration_cutover_coordinator.dart`, `migration_cutover_record.dart`, coordinator regressions, and bridge unregister evidence; command/result: required scoped `graphify query "MIG-008 durable cutover server lease cleanup account migration cutover coordinator unregister rendezvous inbox token tests"` completed before code inspection; decision/blocker: `closed` for MIG-008 session scope only. QA retry accepted the proof-identity fix, and no evidence shows prohibited MIG-006 group/release commands were run.
- `2026-06-07T18:08:00Z` - role: Closure Writer completed; files updated: source proposal evidence/gap section, reusable breakdown MIG-008 closure delta and ledger row, and this plan's closure progress/session verdict; decision/blocker: no MIG-008 closure blocker. The docs explicitly leave MIG-009 through MIG-012 and deferred-last MIG-006 open and do not write a final program verdict.
- `2026-06-07T18:08:00Z` - role: Closure Reviewer completed; files re-read: updated source proposal, breakdown, and this plan; decision/blocker: no accidental overall Move Account closure, no MIG-006 failure/closure, and no claim that runtime gates, pending work, UI, final device acceptance, Android generated AAR verification, or full iOS-to-iOS release acceptance are complete.

## Session Verdict

Verdict: `closed` for MIG-008 session scope only.

What is closed:

- Durable cutover records, secure-store persistence, recovery decisions, and the cutover coordinator primitive are accepted for session scope.
- `commitNewActive` requires a matching same-session, same-account, old-phone durable old-block proof before writing `active`; mismatched session/account/role regressions prove no unauthorized active authority write.
- `markOldMigratedOutAfterNewActive` requires a matching same-session, same-account, new-phone durable active proof before writing `migrated_out` or invoking lease cleanup; mismatched session/account/role regressions prove no unauthorized migrated-out authority write or cleanup call.
- Personal rendezvous unregister and inbox push-token unregister commands are exposed through Dart/Go/platform bridge surfaces, and stale old-device push-token material is cleared or ignored at the cutover primitive boundary.

Accepted differences and residual-only items:

- Android Kotlin/Go source routing exists, but the generated Android AAR was not regenerated or verified because the local Android SDK has no usable NDK. This remains an environment caveat, not a MIG-008 session blocker under the accepted gate list.
- The allowed transport evidence was single-device fixture evidence, not final migration acceptance.
- Reopen MIG-008 only for a real regression in cutover ordering, same-session/account/role proof validation, durable proof timestamps, lease-cleanup retry/idempotency, bridge unregister routing, or stale-token clearing.

Still open:

- MIG-009 migrated-out runtime network gates.
- MIG-010 pending work ownership and queue migration.
- MIG-011 user journey, progress UI, wake lock, and migrated-out UX.
- MIG-012 final device acceptance and overall closure.
- MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed.
