Status: reusable-breakdown

# Move Account To New Device Session Breakdown

## Decomposition Progress

- Phase: Evidence Collector
  - Source doc path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
  - Intended breakdown path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`
  - Current role or phase: completed
  - Docs/files inspected so far: source proposal; adjacent sufficiency/spec review docs; `Test-Flight-Improv/14-regression-test-strategy.md`; relevant sections of `Test-Flight-Improv/test-gate-definitions.md`; graphify query for the move-account feature; QR scanner/parser files; startup router/startup decision; secure-storage abstractions and secret migration; encrypted DB opener; identity and group repositories; local media transfer and local WebSocket server; Go file crypto; bridge command map; relay rendezvous/push unregister surfaces; media file manager and media/post-media helpers
  - Current next action or exact blocker: none
- Phase: Closure Mapper
  - Source doc path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
  - Intended breakdown path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`
  - Current role or phase: completed
  - Docs/files inspected so far: proposal scope, release-blocking safety tests, simulator acceptance scenarios, existing coverage/gaps, regression and gate strategy
  - Current next action or exact blocker: closure target mapped to one iOS-to-iOS account move with full staged import, local encrypted transfer, durable cutover, and no two active primary devices
- Phase: Session Splitter
  - Source doc path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
  - Intended breakdown path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`
  - Current role or phase: completed
  - Docs/files inspected so far: code-entry files and named gates listed below
  - Current next action or exact blocker: 12-session split selected by account authority, QR pairing, secure storage, DB snapshot, media/files, group/NSE continuity, transfer, cutover, runtime gates, pending work, UI, and final acceptance seams
- Phase: Reviewer
  - Source doc path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
  - Intended breakdown path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`
  - Current role or phase: completed
  - Docs/files inspected so far: session ledger, dependency order, named gate contract, matrix update contract
  - Current next action or exact blocker: split is sufficient; no missing acceptance/closure pass; no generic plan paths
- Phase: Arbiter
  - Source doc path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
  - Intended breakdown path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`
  - Current role or phase: completed
  - Docs/files inspected so far: final reusable breakdown
  - Current next action or exact blocker: no structural blockers remain; send artifact to downstream planning one session at a time

## recommended plan count

12 session plans.

## decomposition artifact

- Artifact path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code before execution.
- Intended plan path rule: every session uses `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-<session-id>-plan.md`. Shared generic plan paths are not allowed.

## Historical Run Mode Snapshot

- Last refreshed: `2026-06-07T18:07:49Z`
- Active mode: `standard`
- Degraded local continuation explicitly allowed: no
- Source proposal / closure doc path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
- Source status vocabulary: proposal prose sections, especially `Existing Coverage And Gaps`, `Release-Blocking Safety Tests`, `Simulator Acceptance Scenarios`, and `Acceptance Evidence`; no formal row-status matrix exists for this Move-Feature doc.
- Overall closure bar: all sessions must collectively satisfy the iOS-to-iOS account move MVP below, with per-session closure evidence recorded in the source proposal or test/gate inventory docs when new tests or classifications land.
- Final verdict policy: persist exactly one of `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; use `still_open` while any required session remains blocked, any required closure result is missing, or the overall closure bar is not met.
- Current sequencing override: MIG-006 is deliberately deferred-last with commands 29-123 and final group verification still required. This is not a failure and not a closure; do not run MIG-006 group simulator/release evidence while closing the remaining implementation sessions, select dependency-satisfied MIG-007 through MIG-011 first, and do not close the overall Move Account doc while MIG-006 remains deferred. MIG-012 is acceptance-only and cannot be closed or used to claim final acceptance until MIG-006 deferred evidence and final device acceptance are complete.

### Post-Ledger Plan-285 Host-Hardening Addendum — 2026-07-26

- Plan 285 is implemented and host-closed for bounded in-session cutover
  retry/replay, resumable runtime startup, retained-route activation/reset
  ownership, authority-aware blocked UI, and destination shared-store
  compatibility.
- It is a post-ledger hardening plan, not a new MIG session, and does not change
  the historical session verdicts or close the overall Move Account program.
- `DEFER-285-01/02/03`, MIG-006, MIG-012, optional device confidence, and final
  release acceptance remain open. Final cross-session closure remains owned by
  MIG-012.
- Recorded Plan-285 host evidence is 173/173 focused tests, all 50
  `move-feature` commands, startup wiring 4/4, l10n 4/4, completeness
  1,349/1,349, clean strict analysis/diff hygiene, and refreshed Graphify
  fingerprint `d3c748f7a3cdec3b`.

## Controller Progress

- `2026-06-07T13:47:04Z` - MIG-006 command-26 focused proof passed after the GE-011 direct-fixture joined-state fix: `run_with_devices.sh group --only 26` completed with `[ORCH] ge011 proof passed: ge011 verdicts valid for alice, bob, charlie`, `PASS: #26 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge011`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts are under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge011_bjquWa`, run id `1780839728693`. The remaining simulator resume started with `run_with_devices.sh group --start-at 27`. MIG-006 remains evidence-gated until commands 27-123 and final verification pass.
- `2026-06-07T13:52:02Z` - MIG-006 command-27 proof passed inside the remaining simulator resume: `[ORCH] ge012 proof passed: ge012 verdicts valid for alice, bob, charlie` and `PASS: #27 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge012`; logs/verdicts are under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge012_e2BLvc`, run id `1780840009700`. The same sweep advanced to command 28 (`ge013`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge013_DWWcoI`, run id `1780840291148`. MIG-006 remains evidence-gated while commands 28-123 are running.
- `2026-06-07T13:56:38Z` - MIG-006 command-28 proof passed inside the remaining simulator resume: `[ORCH] ge013 proof passed: ge013 verdicts valid for alice, bob, charlie` and `PASS: #28 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge013`; logs/verdicts are under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge013_DWWcoI`, run id `1780840291148`. The same sweep advanced to command 29 (`ge014`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge014_bVMRLa`, run id `1780840561232`. MIG-006 remains evidence-gated while commands 29-123 are running.
- `2026-06-07T16:07:22Z` - MIG-007 closure accepted by the controller after the local execution fallback, closure-review validation fix, direct tests, host gates, single-device transport gate, source proposal evidence update, breakdown ledger update, and `graphify update .`. MIG-007 is closed for its own transfer-seam scope only. The overall Move Account program remains open because MIG-006 is deliberately deferred-last/evidence-gated and MIG-008 through MIG-012 remain pending.
- `2026-06-07T16:07:22Z` - controller selection: MIG-008 is the next allowed dependency-satisfied session after applying the hard MIG-006 override. MIG-008 depends on MIG-001, MIG-004, and MIG-007, all closed for their own scopes; MIG-006 remains deferred-last, not failed and not closed. Next action: create or refresh only the doc-scoped MIG-008 plan at `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-008-plan.md`; no generic shared plan file is allowed.
- `2026-06-07T17:51:20Z` - MIG-008 closure accepted by the controller after fresh closure audit updated the source proposal, breakdown closure deltas, and MIG-008 plan verdict. MIG-008 is closed for its own durable cutover and server lease-cleanup primitive scope only. The overall Move Account program remains open because MIG-006 is deliberately deferred-last/evidence-gated and MIG-009 through MIG-012 remain pending.
- `2026-06-07T17:51:20Z` - controller selection: MIG-009 is the next allowed dependency-satisfied session after applying the hard MIG-006 override. MIG-009 depends on MIG-001 and MIG-008, both closed for their own scopes; MIG-006 remains deferred-last, not failed and not closed. Next action: create or refresh only the doc-scoped MIG-009 plan at `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-009-plan.md`; no generic shared plan file is allowed.
- `2026-06-07T18:07:49Z` - controller selection: MIG-009 execution is starting from the existing execution-ready doc-scoped plan `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-009-plan.md`. MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed; prohibited MIG-006 group simulator/release commands remain out of scope.
- `2026-06-07T19:31:08Z` - MIG-009 closure accepted by the controller after local fallback execution, local QA recovery, focused direct tests, affected push/background coverage, permitted host gates, source proposal evidence update, breakdown ledger update, and `graphify update .`. MIG-009 is closed for its own migrated-out runtime network gate scope only. The overall Move Account program remains open because MIG-010 through MIG-012 remain pending and MIG-006 is deliberately deferred-last/evidence-gated.
- `2026-06-07T19:31:08Z` - controller selection: MIG-010 is the next allowed dependency-satisfied session after applying the hard MIG-006 override. MIG-010 depends on MIG-004, MIG-005, MIG-008, and MIG-009, all closed for their own scopes; MIG-006 remains deferred-last, not failed and not closed. Next action: create or refresh only the doc-scoped MIG-010 plan at `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-010-plan.md`; no generic shared plan file is allowed.
- `2026-06-07T19:38:00Z` - MIG-010 doc-scoped plan created and accepted as execution-ready at `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-010-plan.md`. The plan narrows MIG-010 to pending-work manifest/validator and queue-ownership policy, with explicit host gates and no MIG-006 group simulator/release evidence. Next action: execute MIG-010 from this plan.
- `2026-06-07T19:38:00Z` - MIG-010 execution is starting from the execution-ready doc-scoped plan. MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed; prohibited MIG-006 group simulator/release commands remain out of scope.
- `2026-06-07T19:59:00Z` - MIG-010 controller verification found the initial local fallback implementation had a pending-work model/builder contract mismatch and direct tests failed at compile time. The controller repaired the manifest model contract to match the builder/tests before continuing verification; this was a local execution recovery, not a product-scope expansion.
- `2026-06-07T20:10:00Z` - MIG-010 closure accepted by the controller after local fallback execution, model-contract correction, direct pending-work builder/validator tests, affected direct tests, analyzer, required named host gates, source proposal update, breakdown ledger update, inventory update, and `git diff --check`. MIG-010 is closed for its own pending-work ownership manifest/validator scope only. The overall Move Account program remains open because MIG-011 and MIG-012 remain pending and MIG-006 is deliberately deferred-last/evidence-gated.
- `2026-06-07T20:19:00Z` - MIG-010 QA Reviewer completed read-only review. Verdict: no code/behavior blocker; docs correctly keep MIG-006 deferred-last and avoid final acceptance overclaim. The reviewer found one documentation blocker in `codebase-test-inventory.md` where the account_migration feature index still said 24 tests while the section listed 32; the controller fixed the index count and update note.
- `2026-06-07T20:10:00Z` - controller selection: MIG-011 is the next allowed dependency-satisfied session after applying the hard MIG-006 override. MIG-011 depends on MIG-001, MIG-002, MIG-007, MIG-008, MIG-009, and MIG-010, all closed for their own scopes; MIG-006 remains deferred-last, not failed and not closed. Next action: create or refresh only the doc-scoped MIG-011 plan at `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-011-plan.md`; no generic shared plan file is allowed.
- `2026-06-07T21:12:03Z` - MIG-011 fix-pass execution completed the host-side scanner/settings copy blockers and stale docs/inventory updates after direct/focused tests, affected QR/startup regressions, targeted analyzer, and completeness-check passed. MIG-011 is closed for its own host-side UI/coordinator scope only. The overall Move Account program remains open because MIG-012 remains pending and MIG-006 remains deliberately deferred-last/evidence-gated; no MIG-006 group simulator/release evidence was run.
- `2026-06-07T21:32:49Z` - MIG-011 final QA re-review passed with no blockers or non-blockers: migration scanner copy is Move Account-specific, contact scanner defaults remain intact, Settings copy matches old-phone scanning, and MIG-011 docs/inventory/gates close only the host/UI session scope. Verification cited by QA: focused scanner/settings/MIG-011 subset passed with `+42`, completeness-check passed with `805/805`, and `git diff --check` was clean. No MIG-006 simulator or release-evidence commands were run. Controller state: remaining implementation sessions through MIG-011 are closed for their own scopes; MIG-006 remains the final deferred group-evidence gate with commands 29-123 and final verification still required, and MIG-012 remains pending for final acceptance only after that evidence boundary is resolved.

## overall closure bar

After all sessions finish, the app supports the iOS-to-iOS "Move account to new phone" MVP from a no-account new phone and an active old phone. Pairing is migration-typed, single-use, expiring, authenticated, and separate from contact QR side effects. The account bundle is created from a consistent SQLCipher snapshot plus a complete manifest for DB state, primary and shared keychain secrets, media and app-owned files, group device/key state, posts, introductions, inbox staging, and pending work. Transfer is same-WiFi, migration-specific, streaming/chunked, resumable from verified progress, and never relay/cloud/iCloud backed. Import is staged until DB, secrets, files, versions, identity, media, groups, notification-preview secrets, and cutover are verified. Final success leaves exactly one active account holder: the new phone active and the old phone durably migrated out with no normal UI, P2P, push/rendezvous, inbox, retry, upload, group, or profile/avatar activity. Failed or cancelled migration leaves the old phone active and prevents partial account exposure on the new phone.

## source of truth

- Product intent: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`.
- Historical review context: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-spec-review.md` and `Test-Flight-Improv/Move-Feature/02-spec-sufficiency-review.md`. The current proposal is newer and already incorporates many review gaps; use the proposal as product truth unless live code disproves it.
- Regression strategy: `Test-Flight-Improv/14-regression-test-strategy.md`.
- Named gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`.
- Stable matrix/closure doc: no dedicated Move-Feature matrix exists next to the proposal. Do not invent one during planning. Treat the proposal's `Existing Coverage And Gaps`, `Release-Blocking Safety Tests`, `Simulator Acceptance Scenarios`, and this breakdown as the current closure source, and update `test-gate-definitions.md` or `codebase-test-inventory.md` only when new tests or gate classifications require it.
- Graphify evidence: `graphify query "How is move account to a new device implemented and tested in this Flutter repo? Include the source proposal docs, stable matrix or closure docs, likely code seams, direct tests, and named gates." --budget 2400`.
- Key code evidence: `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`, `lib/features/qr_code/application/parse_qr_payload_use_case.dart`, `lib/features/identity/presentation/startup_router.dart`, `lib/features/identity/application/startup_decision.dart`, `lib/core/secure_storage/secure_key_store.dart`, `lib/core/secure_storage/flutter_secure_key_store.dart`, `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`, `lib/core/secure_storage/secret_storage_references.dart`, `lib/core/database/encrypted_db_opener.dart`, `lib/main.dart`, `lib/features/identity/domain/repositories/identity_repository_impl.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/features/groups/domain/models/group_key_retention_policy.dart`, `lib/core/local_discovery/local_ws_server.dart`, `lib/core/local_discovery/local_media_server.dart`, `lib/core/local_discovery/local_media_sender.dart`, `go-mknoon/crypto/file_crypto.go`, `lib/core/bridge/go_bridge_client.dart`, `go-mknoon/node/rendezvous.go`, `go-relay-server/inbox.go`, `go-relay-server/push_token_store.go`, `go-relay-server/backend_memory.go`, `lib/core/media/media_file_manager.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/database/helpers/post_media_db_helpers.dart`.

## session ledger

| session id | title | classification | intended plan file | depends on | current status |
|---|---|---|---|---|---|
| MIG-001 | Account authority and migration state foundation | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-001-plan.md` | none | closed (MIG-001 only; program still open) |
| MIG-002 | Migration QR pairing and scanner boundary | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-002-plan.md` | MIG-001 | closed (MIG-002 only; program still open) |
| MIG-003 | Secure-storage registry, staging, and cleanup | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-003-plan.md` | MIG-001 | closed (MIG-003 only; program still open) |
| MIG-004 | SQLCipher snapshot, schema manifest, and DB import staging | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-004-plan.md` | MIG-001, MIG-003 | closed (MIG-004 only; program still open) |
| MIG-005 | Media, app-owned files, and storage preflight manifest | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-005-plan.md` | MIG-003, MIG-004 | closed (MIG-005 only; program still open) |
| MIG-006 | Group device identity, retained keys, and push-preview continuity | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-006-plan.md` | MIG-003, MIG-004 | deferred-last / evidence-gated by user override (host code complete; command 12 fixed and targeted rerun passed; commands 13-28 triaged/fixed/proven, including GE-013 run id `1780840291148`; commands 29-123 and final verification still required before closure; do not run during MIG-007 through MIG-012 pass) |
| MIG-007 | Migration-specific encrypted segmented transfer | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-007-plan.md` | MIG-002, MIG-004, MIG-005 | closed (MIG-007 only; program still open; MIG-006 deferred-last remains evidence-gated) |
| MIG-008 | Durable cutover and server lease cleanup | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-008-plan.md` | MIG-001, MIG-004, MIG-007 | closed (MIG-008 only; program still open; MIG-006 deferred-last remains evidence-gated) |
| MIG-009 | Migrated-out runtime network gates | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-009-plan.md` | MIG-001, MIG-008 | closed (MIG-009 only; program still open; MIG-006 deferred-last remains evidence-gated) |
| MIG-010 | Pending work ownership and queue migration | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-010-plan.md` | MIG-004, MIG-005, MIG-008, MIG-009 | closed (MIG-010 only; program still open; MIG-006 deferred-last remains evidence-gated) |
| MIG-011 | User journey, progress UI, wake lock, and migrated-out UX | implementation-ready | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-011-plan.md` | MIG-001, MIG-002, MIG-007, MIG-008, MIG-009, MIG-010 | closed (MIG-011 host/UI scope only; program still open; MIG-006 deferred-last remains evidence-gated) |
| MIG-012 | Device acceptance, release evidence, and closure | acceptance-only | `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-012-plan.md` | MIG-001 through MIG-011 | pending |

## session ledger closure deltas

- MIG-001 status delta: `pending` -> `closed` for the session only.
- MIG-001 closure evidence: accepted execution verdict, no blocking QA findings, direct authority/startup tests passed, Baseline Gate passed with `FLUTTER_DEVICE_ID=macos`, source proposal evidence updated, and `graphify update .` completed after code/doc modifications.
- MIG-001 accepted differences: no QR pairing, secure-storage registry, DB/file import/export, transfer, durable cutover, runtime network gates, pending-work migration, polished journey UI, erase/reset, bridge/P2P bootstrap internals, or final device acceptance landed in this session.
- MIG-001 residual-only items: none inside MIG-001. Later-session dependencies remain explicitly assigned to MIG-002 through MIG-012.
- Overall program status: still open/pending. No final program verdict is written here because the full Move Account closure bar is not met until the remaining sessions and final acceptance complete.
- MIG-002 status delta: `pending` -> `closed` for the session only.
- MIG-002 closure evidence: accepted final execution verdict, accepted QA verdict with no blockers and no non-blocking follow-ups, required direct account-migration pairing and QR scanner/contact-preservation tests passed and were rerun by QA, exact `./scripts/run_test_gates.sh baseline` failed only on multiple attached devices/no selected target after host tests passed, supported `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed, source proposal evidence rows were updated, `codebase-test-inventory.md` records the new host tests and later-session scope, and `graphify update .` completed after code/doc modifications.
- MIG-002 accepted differences: MIG-002 proves the host-side pairing/security boundary and transcript-derived confirmation-code contract only. Real local-network authenticated channel production, full export/import/transfer/cutover, UI journey, simulator/device acceptance, and final program closure remain deferred.
- MIG-002 residual-only items: none inside MIG-002. Later-session dependencies remain explicitly assigned to MIG-003 through MIG-012, especially secure-storage registry/staging/cleanup, SQLCipher snapshot/import, media/app-owned file transfer, group/NSE continuity, local-network transport, durable cutover, migrated-out runtime gates, pending-work migration, UI, and final acceptance.
- Overall program status after MIG-002: still open/pending. No final program verdict is written here because the full Move Account closure bar is not met until MIG-003 through MIG-012 and final acceptance complete.
- MIG-003 status delta: `pending` -> `closed` for the session only.
- MIG-003 closure evidence: accepted execution verdict and local QA verdict with no blockers; secure-storage model, registry, reference collector, staging, cleanup, and push-token storage policy landed; new MIG-003 direct tests passed; affected secure-storage/identity/group/settings/account-authority direct tests passed; `./scripts/run_test_gates.sh completeness-check` passed after classifying `test/features/push/infrastructure/push_token_store_impl_test.dart`; exact `./scripts/run_test_gates.sh baseline` failed only on multiple attached devices/no selected target after host tests passed; supported `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; source proposal evidence rows were updated; `codebase-test-inventory.md` records the new host tests and later-session scope; `test-gate-definitions.md` records the push infrastructure test as direct out-of-gate coverage; and `graphify update .` completed after code/doc modifications.
- MIG-003 accepted differences: MIG-003 uses an explicit fixed-key registry plus DB-discovered `secure:` references instead of platform keychain namespace enumeration; host fake stores prove dual-store logic but not real iOS Keychain lock/reboot/iCloud/app-restore behavior; push-token material is clear/regenerate instead of migrated active state; device-local account authority and pairing-session state are excluded from export/import but clearable by explicit local erase/reset; `secrets_migrated` promotion is guarded by required staged secret presence rather than full imported identity verification; and group notification-preview continuity is not closed beyond classifying shared mirror keys.
- MIG-003 residual-only items: none inside MIG-003's host-side registry, staging, promotion, cleanup, or push-token policy closure bar. Future work should reopen MIG-003 only for a real regression in those surfaces. Bundle exporter/importer consumption, imported secret-to-identity verification, real iOS Keychain lifecycle/device proof, DB snapshot/import, media/app-owned files, group/NSE continuity, local transfer, durable cutover, migrated-out runtime gates, pending work, UI, and final device acceptance remain explicitly assigned to MIG-004 through MIG-012.
- Overall program status after MIG-003: still open/pending. No final program verdict is written here because the full Move Account closure bar is not met until MIG-004 through MIG-012 and final acceptance complete.
- MIG-004 status delta: `execution-ready; execution pending` -> `closed` for the session only.
- MIG-004 closure evidence: accepted execution verdict and local QA/closure review with no blockers; schema inventory/hash, manifest compatibility, SQLCipher snapshot/export adapter, staged DB open with MIG-003 staged DB key, checksum/schema/integrity validation, identity null-secret and staged-secret checks, and staged artifact cleanup landed; six new direct MIG-004 tests passed as a combined host run with `+12 ~1`, where the skipped host SQLCipher capability case is covered by the macOS integration capability probe; affected DB opener, full migration-chain, secure-storage, identity, staging/cleanup, and import-precondition direct tests passed; `flutter test -d macos integration_test/migration_database_sqlcipher_capability_test.dart` passed as the plugin-registered SQLCipher capability proof; `dart format`, `git diff --check`, `./scripts/run_test_gates.sh completeness-check`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and `graphify update .` passed after code/doc changes.
- MIG-004 accepted differences: host/unit SQLCipher capability proof is skipped because `sqflite_sqlcipher` is plugin-registered; real capability is proven by the macOS integration probe. MIG-004 proves the DB snapshot/import staging boundary only; media/app-owned file manifests, group/NSE continuity, segmented transfer, durable cutover, migrated-out runtime gates, pending-work ownership, user journey UI, simulator/device final acceptance, and final program closure remain later sessions.
- MIG-004 residual-only items: none inside MIG-004's DB snapshot/schema manifest/import-staging closure bar. Future work should reopen MIG-004 only for a real regression in DB snapshot/export/import validation, staged DB key ordering, manifest compatibility, checksum/schema/integrity checks, identity null-secret/staged-secret verification, cleanup, or SQLCipher target capability. Bundle consumption, files/media, group device identity/NSE preview proof, transfer, cutover, runtime quieting, pending work, UI, and final acceptance remain explicitly assigned to MIG-005 through MIG-012.
- Overall program status after MIG-004: still open/pending. No final program verdict is written here because the full Move Account closure bar is not met until MIG-005 through MIG-012 and final acceptance complete.
- MIG-005 status delta: `pending` -> `closed` for the session only.
- MIG-005 closure evidence: accepted execution verdict with no blockers; app-owned file manifest model, builder, validator, storage preflight, and staged file-import cleanup landed; four new direct MIG-005 tests passed; affected media/avatar/post/group direct tests passed in the combined run with `+126`; `dart format`, `git diff --check`, `./scripts/run_test_gates.sh completeness-check`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and `graphify update .` passed after code/doc changes.
- MIG-005 accepted differences: MIG-005 proves host-side file manifesting, media metadata validation, provider-injected storage preflight, and session-scoped staged-file cleanup only. It does not implement or claim migration transfer, import rendering, durable cutover, old-phone runtime gates, pending-work ownership/resume semantics, UI, native OS free-space API proof, simulator/device final acceptance, or final program closure.
- MIG-005 residual-only items: none inside MIG-005's app-owned file manifest/storage-preflight/cleanup closure bar. Future work should reopen MIG-005 only for a real regression in relative app-owned path manifesting, file size/checksum capture, chat/post media metadata validation, transient-file classification, raw absolute path healing/flagging, storage preflight, or staged-file cleanup. Group/NSE continuity, segmented transfer, cutover, runtime quieting, pending work, UI, and final acceptance remain explicitly assigned to MIG-006 through MIG-012.
- Overall program status after MIG-005: still open/pending. No final program verdict is written here because the full Move Account closure bar is not met until MIG-006 through MIG-012 and final acceptance complete.
- MIG-006 status delta: `pending` -> `evidence-gated` for the session only.
- MIG-006 code-complete evidence: group migration manifest model, builder, and validator landed; follow-up coverage now includes pending key repairs, pending membership messages, welcome key-package tombstones, and group inbox cursors; focused MIG-006 tests passed with `+9`; affected direct account-migration/group/push bundle passed with `+385`; `./scripts/run_test_gates.sh groups` passed with `+324`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; and reliability simulator discovery passed after classifying the SQLCipher capability probe outside reliability simulation discovery.
- MIG-006 MD-004 triage evidence: the command-12 timeout root cause was that the primary same-account send excluded the sender account peer ID from durable group recipients, while the restored sibling drains durable inbox state under that same account peer ID. `sendGroupMessage` now has an explicit `includeSenderPeerIdInDurableRecipients` opt-in; ordinary production sends still exclude the sender account by default, and the MD-004 harness opts into same-account durable replay. Evidence: `flutter test test/features/groups/application/send_group_message_use_case_test.dart` passed with `+144`; `./scripts/run_test_gates.sh groups` passed with `+324`; targeted `run_with_devices.sh group --only 12` passed with `[ORCH] MD-004 proof completed successfully`; `git diff --check` passed.
- MIG-006 remaining blocking evidence: the known MD-004 command-12 blocker is fixed and targeted/resumed commands 13-28 have been triaged, fixed where needed, and proven green, including command-28 GE-013 run id `1780840291148`. The MIG-006 plan still requires the full group reliability simulator gate before closure, so the session remains evidence-gated until commands 29-123 and final verification pass.
- MIG-006 accepted differences: host tests prove retained group-key, pending draft, shared mirror, device-roster, moved-account single-active-device, sender/receipt/welcome metadata, pending repair, pending membership, welcome tombstone, inbox cursor, and no-raw-key/private-material serialization behavior only. MIG-006 does not prove full bundle export/import, final migrated group rendering/decryption, real iOS Keychain/NSE lifecycle, transfer, cutover, pending-work ownership, UI, or final device acceptance.
- MIG-006 residual-only items: none inside the implemented host manifest/validator contract. The session itself remains evidence-gated until the required group reliability simulator evidence passes or the plan is explicitly revised.
- Overall program status after MIG-006: still open/pending. No final program verdict is written here because MIG-006 is evidence-gated and MIG-007 through MIG-012 remain pending.
- MIG-007 status delta: `pending` -> `closed` for the session only, under the explicit override that MIG-006 remains deferred-last/evidence-gated rather than failed.
- MIG-007 closure evidence: accepted local execution and closure review with no remaining blockers; migration transfer manifest/model, bridge-backed segment crypto seam, verified checkpoint store, segmented transfer service, no-local-path/relay-cloud rejection, and additive `LocalWsServer` `/migration/` route hook landed; direct MIG-007/local-discovery proof passed after the closure-review validation fix with `+75`; `git diff --check` passed; `./scripts/run_test_gates.sh completeness-check` passed with `799/799`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed in the available single-device fixture; and `graphify update .` completed after code/doc changes.
- MIG-007 accepted differences: MIG-007 proves a migration-specific encrypted segmented transfer seam and host/loopback protocol behavior only. It does not wire the full database/secure-storage/files/group bundle exporter/importer, durable cutover, old-phone runtime shutdown, pending-work ownership, user journey UI, wake-lock journey, physical paired same-WiFi iOS-to-iOS migration, MIG-006 group release evidence, or final program acceptance.
- MIG-007 residual-only items: none inside MIG-007's transfer manifest/segment crypto/checkpoint/route separation closure bar. Future work should reopen MIG-007 only for a real regression in manifest compatibility, contiguous segment validation, per-segment associated-data binding, checksum/nonce validation, verified checkpoint/resume semantics, no relay/cloud fallback, or `/migration/` versus `/media/<id>` route isolation.
- Overall program status after MIG-007: still open/pending. No final program verdict is written here because MIG-006 remains deferred-last/evidence-gated and MIG-008 through MIG-012 remain pending.
- MIG-008 status delta: `implementation-ready` -> `closed` for the session only, under the explicit override that MIG-006 remains deferred-last/evidence-gated rather than failed.
- MIG-008 closure evidence: QA retry accepted with no remaining MIG-008 blocker; durable cutover record/model/repository/coordinator and bridge cleanup adapter landed; explicit Dart/Go/platform bridge helpers for `rendezvous:unregister` and `inbox:unregister_token` landed; Go node/relay idempotent unregister support/tests and stale push-token clear/ignore at the cutover primitive boundary landed; `commitNewActive` and `markOldMigratedOutAfterNewActive` now validate same `sessionId`, same `accountPeerId`, expected proof role, and durable proof getters before authority writes; focused Flutter QA retry passed `flutter test test/features/account_migration/application/migration_cutover_coordinator_test.dart test/core/bridge/p2p_bridge_client_test.dart test/core/bridge/go_bridge_client_test.dart` with `+158`; `git diff --check` passed; earlier executor/QA evidence included Go bridge/node/relay tests, completeness-check `800/800`, macOS baseline, and the allowed single-device transport gate.
- MIG-008 accepted differences: MIG-008 proves the durable cutover and server lease-cleanup primitive only. It does not implement or claim full migrated-out runtime gate fanout, pending-work ownership, user journey UI, physical paired iOS-to-iOS release acceptance, final program closure, or MIG-006 group release evidence. Android Kotlin/Go source routing exists, but the generated Android AAR was not regenerated or verified because this environment has no usable Android NDK.
- MIG-008 residual-only items: none inside MIG-008's cutover record, proof validation, bridge unregister, idempotent lease-cleanup, and stale-token boundary closure bar. Future work should reopen MIG-008 only for a real regression in old-block-before-new-active ordering, same-session/account/role proof validation, cutover recovery states, unregister bridge routing, idempotent relay cleanup, or stale push-token clearing.
- Overall program status after MIG-008: still open/pending. No final program verdict is written here because MIG-006 remains deferred-last/evidence-gated and MIG-009 through MIG-012 remain pending.
- MIG-009 status delta: `implementation-ready` -> `closed` for the session only, under the explicit override that MIG-006 remains deferred-last/evidence-gated rather than failed.
- MIG-009 closure evidence: local execution fallback and local QA recovery accepted with no remaining MIG-009 blocker; the authority-backed runtime network gate landed; P2P service/start/resume, push registration/coordinator/background fallback display, foreground and notification-open drains, app-shell live-service startup and callback wrappers, target-peer bridge operations, group dispatcher overflow recovery, and delayed key-exchange/post retriers now consult the gate before migrated-out account network side effects or migrated-out push surfacing. Direct evidence passed with focused MIG-009 bundle `+107`, affected push/background bundle `+46`, delayed retrier bundle `+20`, app-entry smoke `+7`, analyzer clean, `git diff --check` clean, completeness-check `801/801`, and post-wrapper baseline gate host `+105` plus loading smoke `+7` plus posts fake `+1`. Earlier permitted host gates in the same MIG-009 execution passed for `1to1`, host-side `groups`, and `transport`; the host-side `groups` gate is not MIG-006 group simulator/release evidence.
- MIG-009 accepted differences: MIG-009 proves runtime quieting only. It does not implement pending-work ownership and queue migration, user journey/progress/wake-lock/migrated-out UX, physical paired iOS-to-iOS final acceptance, full bundle export/import, or MIG-006 group release evidence. Background push handling is limited to suppressing local migrated-out fallback display/surfacing; broader migrated-out user education remains MIG-011.
- MIG-009 residual-only items: none inside MIG-009's runtime network gate closure bar. Future work should reopen MIG-009 only for a real regression where a migrated-out/non-active authority can restart normal account P2P, push/rendezvous registration, inbox drain, group rejoin/drain/recovery, local discovery/send/media send, listener/retrier network work, or background fallback display through a covered runtime path.
- Overall program status after MIG-009: still open/pending. No final program verdict is written here because MIG-010 through MIG-012 remain pending and MIG-006 remains deliberately deferred-last/evidence-gated with commands 29-123 and final verification still required.
- MIG-010 status delta: `implementation-ready; pending` -> `closed` for the session only, under the explicit override that MIG-006 remains deferred-last/evidence-gated rather than failed.
- MIG-010 closure evidence: local execution fallback and local QA recovery accepted with no remaining MIG-010 blocker after the inventory count note was fixed; pending-work manifest model, builder, and validator landed; valid committed pending work across 1:1 failed/sending/unacked rows, chat media upload rows, post media upload/delivery/follow-on rows, introduction outbox/pending-response rows, and group retry/inbox repair/key repair/membership/reaction replay rows is classified for `resumeOnNewPhoneAfterCommit`; unsafe rows produce explicit issues for missing ownership identity, missing payload/file context, unsupported pending paths, terminal retry contradictions, and sensitive-material leakage. Direct pending-work builder/validator tests passed with `+7`; affected retrier/repository/account-migration direct bundle passed with `+64`; targeted analyzer passed with no issues; required host gates passed for baseline (host `+105`, loading smoke `+7`, posts fake `+1`), `1to1` (`+74`), host-side `groups` (`+324`), `posts` (presence `+3` plus posts fake phases 1/2/4/5 green), `intro` (`+205`), completeness-check `803/803`, and `git diff --check`. The host-side `groups` gate is not MIG-006 group simulator/release evidence.
- MIG-010 accepted differences: MIG-010 proves the row-driven manifest/validator ownership contract only. It does not implement the full exporter/importer, actual imported queue resume on a new phone, user-facing paused/failed pending-work UI, final migrated database rendering, physical paired same-WiFi iOS-to-iOS release acceptance, or MIG-006 group release evidence. Pending drafts or composer-local unsent data outside the covered committed row surfaces remain explicit final-acceptance scope rather than silently claimed.
- MIG-010 residual-only items: none inside MIG-010's pending-work ownership manifest/validator closure bar. Future work should reopen MIG-010 only for a real regression where committed pending work is silently dropped, duplicated across old/new ownership, assigned old-phone resume policy, serialized with sensitive raw payload/private material, or accepted without required ownership/payload/file context through the covered manifest surfaces.
- Overall program status after MIG-010: still open/pending. No final program verdict is written here because MIG-011 and MIG-012 remain pending and MIG-006 remains deliberately deferred-last/evidence-gated with commands 29-123 and final verification still required.
- MIG-011 status delta: `pending` -> `closed` for the host-side UI/coordinator session only, under the explicit override that MIG-006 remains deferred-last/evidence-gated rather than failed.
- MIG-011 closure evidence: local execution and fix-pass accepted for host-side scope; QR scanner copy is now parameterized with contact defaults preserved, old-phone migration scanning passes migration-specific scan/paste copy, Settings copy says the old phone scans the migration QR shown on the new phone, and source proposal/breakdown/plan/inventory/gate docs were updated. Focused scanner/settings copy tests passed; direct MIG-011 bundle passed; affected QR/startup regression bundle passed; targeted analyzer passed with no issues; `flutter gen-l10n` passed; `./scripts/run_test_gates.sh completeness-check` passed with `805/805`; `git diff --check` and `graphify update .` are recorded in the MIG-011 plan execution ledger.
- MIG-011 accepted differences: MIG-011 proves host/widget UI and coordinator boundaries only. It does not implement or claim full exporter/importer transfer, physical paired iOS-to-iOS success, camera/local-network/storage/version permission proof on device, iOS lock/call/background lifecycle proof, final migrated database/media/group/post/intro rendering, final program closure, or MIG-006 group release evidence.
- MIG-011 residual-only items: none inside MIG-011's host-side first-launch/settings entry, scanner copy, QR/confirmation/progress, wake-lock, and migrated-out erase UX closure bar. Future work should reopen MIG-011 only for a real regression in those host-side presentation/coordinator contracts.
- Overall program status after MIG-011: still open/pending. No final program verdict is written here because MIG-012 remains pending and MIG-006 remains deliberately deferred-last/evidence-gated with commands 29-123 and final verification still required.

## ordered session breakdown

### MIG-001 - Account authority and migration state foundation

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-001-plan.md`
- Exact scope: Add the device-local account authority model and repository for the proposal's canonical new-phone and old-phone states. Store active, migrating, migrated-out, and staging/cutover state outside the migrated database bundle. Route startup through this state before normal account UI or P2P startup. Ensure import may start only with no active account or an explicit reset precondition. This session should not implement QR pairing, export/import, transfer, or UI polish beyond the minimum blocked/migration routing needed for tests.
- Why it is its own session: every later slice depends on a durable device-local authority state. Without it, export/import and cutover work can accidentally persist source-device active state into the moved database or allow two active devices.
- Likely code-entry files: `lib/features/identity/application/startup_decision.dart`, `lib/features/identity/presentation/startup_router.dart`, `lib/features/identity/presentation/screens/identity_choice_wired.dart`, `lib/features/identity/presentation/screens/identity_choice_screen.dart`, new `lib/features/account_migration/domain/` and `lib/features/account_migration/application/` files, `lib/core/secure_storage/secure_key_store.dart`.
- Likely direct tests/regressions: new account-migration state repository/use-case tests, `test/features/identity/application/startup_decision_test.dart`, `test/features/identity/presentation/screens/startup_router_test.dart`, `test/features/identity/presentation/screens/startup_router_recovery_test.dart`, `test/features/identity/presentation/screens/identity_choice_screen_test.dart`.
- Likely named gates: direct tests plus `./scripts/run_test_gates.sh baseline`. Run `./scripts/run_test_gates.sh transport` if startup/P2P bootstrap behavior changes beyond route gating.
- Matrix/closure docs to update when done: source proposal `Existing Coverage And Gaps` entries for canonical states, partial import, startup block, migrated-out old phone, and two-active prevention; `test-gate-definitions.md` or `codebase-test-inventory.md` only if new tests need classification.
- Dependency on earlier sessions: none.

### MIG-002 - Migration QR pairing and scanner boundary

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-002-plan.md`
- Exact scope: Add a migration-specific QR payload kind/version, parser, and scanner dispatch before any contact parser or contact-add side effect runs. Add durable single-use session consumption, expiry/skew handling, new-phone ephemeral session key material, old-phone export authorization binding to the consumed session ID and ephemeral public key, and confirmation-code derivation from the established authenticated channel. Preserve existing contact QR behavior.
- Why it is its own session: QR parsing currently assumes contact fields and continues after malformed timestamps. The migration pairing security boundary must land before any exporter can be safely exposed.
- Likely code-entry files: `lib/features/qr_code/application/build_qr_payload_use_case.dart`, `lib/features/qr_code/application/parse_qr_payload_use_case.dart`, `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`, `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart`, `lib/core/bridge/bridge.dart`, new `lib/features/account_migration/application/` pairing/session use cases, new `lib/features/account_migration/domain/models/` payload/session models.
- Likely direct tests/regressions: QR parser/build tests, `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`, pairing session unit tests for contact QR rejection, migration QR rejection, malformed timestamp fail-closed, reused QR rejection, future/stale/clock-skew behavior, and export-key binding to the new-phone ephemeral key.
- Likely named gates: direct tests plus `./scripts/run_test_gates.sh baseline`.
- Matrix/closure docs to update when done: source proposal rows for QR type discrimination, scanner boundary, single-use, expiry, clock skew, and no contact side effects; gate/test inventory if new QR tests are added.
- Dependency on earlier sessions: MIG-001.

### MIG-003 - Secure-storage registry, staging, and cleanup

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-003-plan.md`
- Exact scope: Build the complete migration key registry across the primary app keychain and iOS shared access group. Classify fixed keys, DB-discovered `secure:` references, app preferences, push-token material, identity secrets, group key references, and intentionally device-local authority state. Add staging namespace behavior, promotion rules, registry-driven erase/reset, success cleanup, cancellation cleanup, failed-import cleanup, and sentinel ordering so `secrets_migrated` is never set against an import whose secure secrets are not ready.
- Why it is its own session: secure-storage enumeration and cleanup are cross-cutting and safety-critical, but can be verified independently from DB snapshot, media manifest, and transfer protocol.
- Likely code-entry files: `lib/core/secure_storage/secure_key_store.dart`, `lib/core/secure_storage/flutter_secure_key_store.dart`, `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`, `lib/core/secure_storage/secret_storage_references.dart`, `lib/features/identity/domain/repositories/identity_repository_impl.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/features/push/infrastructure/push_token_store_impl.dart`, settings preference use cases/models, new account-migration secure-storage registry files.
- Likely direct tests/regressions: `test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart`, `test/core/secure_storage/flutter_secure_key_store_test.dart`, `test/features/identity/domain/repositories/identity_repository_impl_test.dart`, settings preference tests, push-token store tests, new registry completeness and cleanup tests covering primary and shared access-group mirrors.
- Likely named gates: direct tests plus `./scripts/run_test_gates.sh baseline`. Add push decrypt simulator dry-run only if this session touches simulator/NSE fixture scripts.
- Matrix/closure docs to update when done: source proposal rows for primary/shared keychain completeness, staging, erase/reset, cleanup, iCloud/keychain behavior, and sentinel ordering; gate/test inventory if new tests are added.
- Dependency on earlier sessions: MIG-001.

### MIG-004 - SQLCipher snapshot, schema manifest, and DB import staging

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-004-plan.md`
- Exact scope: Implement the migration DB export/import core: consistent SQLCipher snapshot using `sqlcipher_export` or an equivalently proven primitive, schema/app/protocol compatibility manifest, current database version 74 inventory from migrations 001 through 074, cipher parameter capture or migration policy, DB checksum verification, staging DB open before commit, DB encryption key import ordering, and controlled rejection of unsupported or torn snapshots. This session should prove DB rows survive across the full schema, but not yet copy app-owned files or perform network transfer.
- Why it is its own session: database snapshot correctness has a different blast radius and direct regression family from keychain enumeration, file manifests, and transfer. It must be stable before downstream file/group/pending-work slices can verify complete account state.
- Likely code-entry files: `lib/core/database/encrypted_db_opener.dart`, `lib/main.dart`, `lib/core/database/migrations/`, `lib/core/database/helpers/`, new account-migration DB export/import and manifest files.
- Likely direct tests/regressions: `test/core/database/encrypted_db_opener_test.dart`, database helper tests, new migration DB snapshot/import tests for schema version 74, SQLCipher parameter compatibility, DB key before open, unsupported version rejection, torn snapshot rejection, and table/column inventory coverage.
- Likely named gates: direct DB tests plus `./scripts/run_test_gates.sh baseline`. Run `./scripts/run_test_gates.sh completeness-check` after classifying new tests.
- Matrix/closure docs to update when done: source proposal rows for SQLCipher export, schema inventory, compatibility, DB key/open/sentinel ordering, and full-table survival; gate/test inventory if new tests are added.
- Dependency on earlier sessions: MIG-001 and MIG-003.

### MIG-005 - Media, app-owned files, and storage preflight manifest

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-005-plan.md`
- Exact scope: Add the file/media manifest and verification layer for app documents and media roots. Cover chat media, post media, pending uploads, contact avatars, group avatars, generated thumbnails, required vs non-critical cache classification, transient artifact exclusion, file size/checksum verification, raw absolute local path healing or fail/flag behavior, chat-media key/nonce/scheme atomicity, DB-resident post-media crypto fields, and native writable-space preflight with staging footprint and headroom. This session should not implement network transfer.
- Why it is its own session: file/media preservation needs media, posts, avatar, storage, and path tests that are independent from DB snapshot and transfer. It also owns native storage preflight, which is a separate feasibility gate from QR and secure storage.
- Likely code-entry files: `lib/core/media/media_file_manager.dart`, `lib/core/media/video_thumbnail_cache.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/core/database/helpers/media_attachments_db_helpers.dart`, `lib/core/database/helpers/post_media_db_helpers.dart`, `lib/features/conversation/application/upload_media_use_case.dart`, `lib/features/posts/phase2` or current posts media use cases, `lib/features/groups/application/group_avatar_storage.dart`, native platform channel files if storage preflight is added.
- Likely direct tests/regressions: `test/core/media/media_file_manager_test.dart`, `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`, `test/core/database/helpers/media_attachments_db_helpers_test.dart`, `test/core/database/helpers/posts_db_helpers_test.dart`, posts media tests, new file-manifest/storage-preflight tests, non-portable-path tests, temp-artifact exclusion tests.
- Likely named gates: direct tests plus `./scripts/run_test_gates.sh baseline`, `./scripts/run_test_gates.sh 1to1`, `./scripts/run_test_gates.sh posts`, and `./scripts/run_test_gates.sh groups` if group avatars are touched.
- Matrix/closure docs to update when done: source proposal rows for media/app-owned files, storage insufficient, chat/post media crypto, avatars, thumbnails, temp artifacts, and raw path handling; gate/test inventory if new tests are added.
- Dependency on earlier sessions: MIG-003 and MIG-004.

### MIG-006 - Group device identity, retained keys, and push-preview continuity

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-006-plan.md`
- Exact scope: Add group-specific migration inventory and verification: all committed retained group-key generations within the eight-generation policy, primary-store pending key-rotation drafts, shared access-group mirrors for committed group keys, group member `devices_json`, sender `transportPeerId` and `senderDeviceId`, welcome key-package state, pending membership/repair state, sync receipts, `logical_delivery_id`, and the moved-account device-identity policy. Prove migrated 1:1 and group push preview secrets are available to the iOS notification service extension before success.
- Why it is its own session: group device identity and NSE preview continuity have their own model invariants, fixture needs, and named gates. They should not be hidden inside a generic manifest session.
- Likely code-entry files: `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/features/groups/domain/models/group_key_retention_policy.dart`, `lib/features/groups/domain/models/group_member.dart`, `lib/features/groups/domain/models/group_welcome_key_package.dart`, `lib/features/groups/application/group_sender_device_binding.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `ios/NotificationService/NotificationPreviewResolver.swift`, `lib/features/push/application/push_decrypt_preview.dart`, account-migration group manifest files.
- Likely direct tests/regressions: group key retention/import tests, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/push/application/push_decrypt_preview_test.dart`, new NSE/shared-key migration tests, push decrypt simulator dry-run/full simulator proof when fixture support exists.
- Likely named gates: direct tests plus `./scripts/run_test_gates.sh baseline`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh runtime-telemetry` if telemetry exclusions change, and the Push Decrypt Simulator Smoke when NSE fixture shape or shared-key proof changes. Heavier group real-network coverage stays Nightly / Release Pool unless the session plan elevates it.
- Matrix/closure docs to update when done: source proposal rows for retained group-key generations, pending drafts, device identity, group member/device fields, NSE preview decryption, and no second active group device entry; gate/test inventory if new tests are added.
- Dependency on earlier sessions: MIG-003 and MIG-004.

### MIG-007 - Migration-specific encrypted segmented transfer

- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-007-plan.md`
- Exact scope: Implement the local-network migration transport: same-WiFi discovery/session binding, migration-specific endpoint or service separate from `PUT /media/<id>`, authenticated channel binding to MIG-002 session data, streaming/chunked AEAD with per-segment nonces, segment manifest, verified progress checkpoints, range/resume semantics, interruption/restart/suspension handling, no whole-file AES helper reliance, no relay/cloud/iCloud fallback, and sensitive-log exclusions. Existing chat media local transfer behavior must remain unchanged.
- Why it is its own session: the existing local media path is a MIME-filtered single HTTP PUT and the Go AES helpers read whole files into memory. A bundle-scale transfer protocol has a different blast radius and test strategy from manifest generation.
- Likely code-entry files: `lib/core/local_discovery/local_ws_server.dart`, `lib/core/local_discovery/local_media_server.dart`, `lib/core/local_discovery/local_media_sender.dart`, `lib/core/local_discovery/local_p2p_service.dart`, new account-migration transfer files, possibly `go-mknoon/crypto/file_crypto.go` only if new streaming helpers are added rather than reusing whole-file helpers.
- Likely direct tests/regressions: `test/core/local_discovery/local_ws_server_test.dart`, `test/core/local_discovery/local_media_server_test.dart`, `test/core/local_discovery/local_media_sender_test.dart`, `test/core/local_discovery/local_media_integration_test.dart`, new migration transfer chunk/resume/security tests, interruption/resume tests.
- Likely named gates: direct tests plus `./scripts/run_test_gates.sh baseline` and `./scripts/run_test_gates.sh transport` with a device id when integration-backed. Nightly / Release Pool transport tests are supporting release evidence, not default PR gates.
- Matrix/closure docs to update when done: source proposal rows for same-WiFi/no-relay transfer, streaming/chunked AEAD, resume, lifecycle interruption, local media regression preservation, and sensitive material exclusion; gate/test inventory if new tests are added.
- Dependency on earlier sessions: MIG-002, MIG-004, and MIG-005.

### MIG-008 - Durable cutover and server lease cleanup

- Session classification: closed for session scope only; MIG-010 through MIG-012 and deferred-last MIG-006 remain open
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-008-plan.md`
- Closed scope: Durable cutover records and bridge/server lease cleanup primitive. Covered `old_network_blocked`, `old_block_proof_received`, `new_active_committed`, old-phone durable migrated-out or network-blocked proof before new-phone activation, server-side personal `RendezvousUnregister`, `inbox:unregister_token`, stale push-token clear/ignore policy, and recovery branches that never produce two active devices. This session exposed the primitive; full runtime gate rollout is now closed in MIG-009.
- Why it is its own session: cutover spans Flutter state, Dart bridge command surface, Go node/relay behavior, and server leases. It needs Go and transport tests that are independent from UI and broad runtime gating.
- Closed code-entry files: `lib/core/bridge/go_bridge_client.dart`, `lib/core/bridge/p2p_bridge_client.dart`, account-migration cutover model/repository/coordinator/bridge-cleanup files, `go-mknoon/node/inbox.go`, `go-mknoon/bridge/bridge.go`, platform Go bridge handlers, and relay unregister test surfaces.
- Closure evidence: QA retry accepted after the proof-identity fix; focused Flutter QA retry passed with `+158`; prior focused Go bridge/node/relay unregister evidence, `git diff --check`, completeness-check `800/800`, macOS baseline, and allowed single-device transport gate passed. Android generated AAR regeneration remains an environment caveat due missing usable Android NDK.
- Residual/open scope: MIG-010 owns pending work, MIG-011 owns UI/wake-lock/migrated-out UX, MIG-012 owns final device acceptance, and MIG-006 remains deferred-last/evidence-gated.
- Dependency on earlier sessions: MIG-001, MIG-004, and MIG-007.

### MIG-009 - Migrated-out runtime network gates

- Session classification: closed for session scope only; MIG-010 through MIG-012 and deferred-last MIG-006 remain open
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-009-plan.md`
- Closed scope: Threaded the account-authority runtime network gate through migrated-out runtime side-effect boundaries so a migrated-out account cannot restart normal activity through P2P service/start, app resume, push registration/coordinator/background fallback display, foreground and notification-open drains, app-shell live-service startup and retry callbacks, group dispatcher overflow recovery, target-peer bridge operations, or delayed key-exchange/post retriers. Missing legacy authority, `active`, and `migrationFailedActiveRestored` preserve existing behavior.
- Why it is its own session: this is the cross-cutting "old phone stays quiet" runtime safety layer. It is separate from cutover primitives and pending-work ownership because its direct regressions are network/listener gates rather than job migration semantics.
- Closed code-entry files: `lib/features/account_migration/application/account_migration_runtime_network_gate.dart`, `lib/main.dart`, `lib/features/identity/presentation/startup_router.dart`, `lib/features/p2p/application/start_node_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `lib/core/services/p2p_service_impl.dart`, push registration/coordinator/background/route-target files, and delayed key-exchange/post retrier files.
- Closure evidence: focused MIG-009 bundle passed with `+107`; affected push/background bundle passed with `+46`; delayed retrier bundle passed with `+20`; app-entry smoke passed with `+7`; post-wrapper baseline gate passed with host `+105`, loading smoke `+7`, and posts fake `+1`; permitted `1to1`, host-side `groups`, `transport`, and `completeness-check` gates passed; analyzer, `git diff --check`, and `graphify update .` completed after the final code delta.
- Residual/open scope: MIG-010 owns pending work ownership and queue migration, MIG-011 owns user journey/progress/wake-lock/migrated-out UX, MIG-012 owns final device/release acceptance, and MIG-006 remains deferred-last/evidence-gated with commands 29-123 and final group verification still required.
- Dependency on earlier sessions: MIG-001 and MIG-008.

### MIG-010 - Pending work ownership and queue migration

- Session classification: closed for session scope only; MIG-011, MIG-012, and deferred-last MIG-006 remain open
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-010-plan.md`
- Closed scope: Defined and implemented the host-side row-driven pending-work ownership manifest and validator for committed pending sends/retries/uploads/media work/post jobs/introduction jobs/group repair and replay jobs. Valid covered rows receive new-phone-only resume policy after commit; unsafe rows emit explicit blocking, pause, or fail issues; no manifest item assigns copied work back to the old phone after migrated-out.
- Why it is its own session: pending work is data/queue semantics rather than runtime network gating. It touches DB manifest rows, file manifest entries, and subsystem retriers, and needs duplicate/loss regression tests.
- Closed code-entry files: `lib/features/account_migration/domain/models/migration_pending_work_manifest.dart`, `lib/features/account_migration/application/migration_pending_work_manifest_builder.dart`, `lib/features/account_migration/application/migration_pending_work_manifest_validator.dart`, and their direct builder/validator tests.
- Closure evidence: direct pending-work builder/validator tests passed with `+7`; affected retrier/repository/account-migration direct bundle passed with `+64`; targeted analyzer passed; required host gates passed for baseline, `1to1`, host-side `groups`, `posts`, `intro`, completeness-check `803/803`, and `git diff --check`.
- Residual/open scope: full exporter/importer consumption of the pending-work manifest, actual new-phone queue resume after import/commit, user-facing pending-work progress/failure UI, final physical-device acceptance, and deferred-last MIG-006 group release evidence remain open.
- Dependency on earlier sessions: MIG-004, MIG-005, MIG-008, and MIG-009.

### MIG-011 - User journey, progress UI, wake lock, and migrated-out UX

- Session classification: closed for session scope only; MIG-012 and deferred-last MIG-006 remain open
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-011-plan.md`
- Closed scope: Added the host-side user-facing journey: new-phone first-launch `Move from old phone`, old-phone settings `Move account to new phone`, migration QR display/scan, transcript-derived confirmation code display, progress stages, foreground wake-lock usage while active, retryable failure/cancellation states, migrated-out old-phone screen with explicit erase action, and preservation of `I'm new here` and `Restore with recovery words` as distinct choices. The old-phone scan route now passes migration-specific `QRScannerScreen` title/instruction/subtitle/paste copy while preserving default contact/friend scanner copy for normal scanner callers. This session wires existing lower-level APIs rather than redefining their contracts.
- Why it is its own session: UI has a separate closure bar and widget/simulator tests. It should come after the backend seams are available so the UI does not invent placeholder behavior that downstream code later invalidates.
- Closed code-entry files: identity onboarding screens/wired/startup router, settings screen/wired/move-account card, `QRScannerScreen` copy parameterization, account-migration journey/blocking presentation and wired widgets, localization ARBs/generated files, and matching direct/widget tests.
- Closure evidence: focused scanner/settings copy tests passed; direct MIG-011 bundle passed; affected QR/startup regression bundle passed; targeted analyzer passed with no issues; `flutter gen-l10n` passed; completeness-check passed with `805/805`; `git diff --check` passed; and `graphify update .` completed after code/doc changes. No MIG-006 group simulator/release-evidence commands were run.
- Accepted differences: host/widget tests prove UI and coordinator behavior only. Camera permission, local-network permission, same-WiFi transfer behavior, iOS lock/call/background lifecycle, physical paired-device acceptance, full exporter/importer, and final program closure remain MIG-012 or later acceptance scope. MIG-006 remains deliberately deferred-last/evidence-gated.
- Dependency on earlier sessions: MIG-001, MIG-002, MIG-007, MIG-008, MIG-009, and MIG-010.

### MIG-012 - Device acceptance, release evidence, and closure

- Session classification: acceptance-only
- Intended plan file: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-012-plan.md`
- Exact scope: Run final end-to-end acceptance for the full iOS-to-iOS account move after all implementation sessions land. Verify happy path, rejected QR variants, permission/storage/version failures, interrupted transfer and cutover recovery, full export/import data completeness, NSE push-preview continuity, old-phone migrated-out behavior, no relay/cloud fallback, no two active devices, and preservation of existing non-migration flows. Update closure evidence in the source proposal and any test/gate inventory docs touched by new tests.
- Why it is its own session: release evidence depends on multiple earlier slices and requires device/simulator proof that should not block individual implementation sessions from landing with focused regressions.
- Likely code-entry files: no product-code entry expected unless acceptance exposes a defect. Closure/doc updates may touch `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`, this breakdown, `Test-Flight-Improv/test-gate-definitions.md`, and `Test-Flight-Improv/codebase-test-inventory.md`.
- Likely direct tests/regressions: full migration simulator/device acceptance tests, paired-device iOS runs, direct feature tests added by earlier sessions, regression checks for onboarding, contact QR, local media, startup/P2P, push, groups, posts, introductions, pending work, and cleanup.
- Likely named gates: `./scripts/run_test_gates.sh baseline`, `./scripts/run_test_gates.sh 1to1`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh posts`, `./scripts/run_test_gates.sh intro`, `./scripts/run_test_gates.sh transport` with explicit device id, `./scripts/run_test_gates.sh runtime-telemetry` when telemetry changes, Push Decrypt Simulator Smoke for NSE proof, `./scripts/run_test_gates.sh completeness-check`, `(cd go-mknoon && go test ./...)`, `(cd go-relay-server && go test ./...)`, and selected Nightly / Release Pool device tests as required by the final plan.
- Matrix/closure docs to update when done: source proposal acceptance and existing gap sections; this breakdown ledger/final verdict if run through the pipeline; `test-gate-definitions.md` and `codebase-test-inventory.md` if new tests or classifications landed.
- Dependency on earlier sessions: MIG-001 through MIG-011.

## why this is not fewer sessions

Fewer than 12 sessions would bundle unrelated risk. Account authority, QR pairing, secure-storage registry, DB snapshot, media/files, group/NSE continuity, transfer, cutover, runtime gates, pending-work ownership, UI, and final device acceptance each have different owner files, tests, and failure modes. Combining them would invite broad plans that either skip release-blocking tests or make closure depend on a single giant change touching Flutter storage, UI, Go bridge/server code, media, push, groups, posts, and transport at once.

The two most tempting merges are intentionally rejected:

- Secure storage plus DB snapshot: unsafe, because keychain staging/cleanup and SQLCipher snapshot compatibility have different direct tests and distinct data-loss hazards.
- Cutover plus runtime gates plus pending work: unsafe, because server lease cleanup, old-phone network suppression, and pending job ownership have separate invariants and named gate coverage.

## why this is not more sessions

The split does not create one session per test case or per subsystem row. For example, media paths, avatars, thumbnails, and storage preflight stay together because they all feed the file manifest and storage-footprint closure bar. Group device identity and NSE continuity stay together because retained group keys, shared access-group mirrors, and notification-preview proof are one decryptability seam. Pending 1:1, group, posts, and introduction work stays together because the closure bar is ownership after migration, not the individual retrier implementation. More sessions would mostly create bookkeeping, stale dependency edges, and plans that cannot leave a meaningful verified state.

## regression and gate contract

- The regression strategy for a new feature requires direct unit/use-case tests, at least one happy-path integration test, at least one boundary/failure-path test, the Baseline Gate, and every relevant subsystem gate touched by the session.
- Baseline Gate applies across the rollout because onboarding, QR, offline inbox, posts, and group smoke are all nearby.
- `1to1` applies when 1:1 send, retry, upload, listener, inbox, media, or pending work changes.
- `feed` applies only if feed cards/composer/handoff are directly changed. For account migration, posts coverage usually uses the `posts` gate instead.
- `intro` applies when introduction send/resend/accept/listener/outbox or retry ownership changes.
- `groups` applies when group keys, messages, invites, rejoin, recovery, membership, avatars, or device identity changes.
- `posts` applies when posts/social-feed state, post media, pending post uploads, or post delivery/retry changes.
- `transport` applies when bridge, resume, reconnect, local discovery, local transfer, startup transport, or device-backed transport flows change. Device id must be explicit for integration-backed runs.
- `runtime-telemetry` applies when push decrypt telemetry, migration-pending exclusions, or flow-event acceptance changes.
- Push Decrypt Simulator Smoke applies when iOS NSE payload, shared access-group key migration, simulator injection scripts, or notification-preview proof changes.
- Go tests apply to sessions that touch `go-mknoon` or `go-relay-server`.
- `completeness-check` applies after new test files or gate classifications are added.
- No tests or gates were run during this decomposition task.

## matrix update contract

- There is no existing stable Move-Feature matrix file next to this proposal. Do not create a new matrix solely for this rollout unless a later planning session proves one is necessary.
- For session closure, update the source proposal's `Existing Coverage And Gaps`, `Release-Blocking Safety Tests`, `Simulator Acceptance Scenarios`, or `Acceptance Evidence` sections with concrete file-and-test evidence when a gap is closed.
- Update `Test-Flight-Improv/test-gate-definitions.md` when new tests need named gate, optional/manual, nightly/release, or out-of-gate classification.
- Update `Test-Flight-Improv/codebase-test-inventory.md` only if this repo's current doc-sync expectations require it for new tests.
- MIG-012 owns the final cross-session closure pass and should verify that earlier per-session evidence did not leave stale open gaps.

## downstream execution path

Each session should next go through the same downstream sequence:

| session id | downstream path |
|---|---|
| MIG-001 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-002 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-003 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-004 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-005 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-006 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-007 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-008 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-009 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-010 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-011 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| MIG-012 | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |

## reviewer sufficiency check

- Recommended session count: sufficient.
- Too coarse: no. The only broad sessions are intentionally grouped by a shared closure bar and direct regression family.
- Too fragmented: no. The split avoids one session per test case and keeps closely coupled media, group/NSE, runtime, and pending-work concerns together.
- Merge candidates: none.
- Required splits: none after separating cutover, runtime gates, and pending-work ownership.
- Missing tests or named gates: none at decomposition time. Each session still needs its downstream plan to name exact direct test files and device/relay proof profile when simulator or device evidence is required.
- Meaningful verified states: yes. Each implementation session can leave a stable seam with direct tests and named gates; MIG-012 then verifies the whole journey.
- Matrix-update responsibility: per-session closure updates source proposal evidence; MIG-012 owns final cross-session closure.
- Minimum safe session set: 12.

## structural blockers remaining

None.

## accepted differences intentionally left unchanged

- Android and cross-platform migration remain out of MVP scope.
- Local device authentication is explicitly not applicable unless a later implementation adds or detects a supported device-auth path. If it is added, the relevant session must add release-blocking coverage.
- The exact post-success erase behavior remains a later product-detail decision, bounded by the proposal's requirement for a migrated-out old-phone screen with an erase action.
- The older adjacent review docs contain gaps that the current proposal appears to have incorporated. They are evidence, not the current product contract.
- No new matrix doc is created in this decomposition because no stable Move-Feature matrix exists.

## exact docs/files used as evidence

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-spec-review.md`
- `Test-Flight-Improv/Move-Feature/02-spec-sufficiency-review.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
- `lib/features/qr_code/application/parse_qr_payload_use_case.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/identity/application/startup_decision.dart`
- `lib/core/secure_storage/secure_key_store.dart`
- `lib/core/secure_storage/flutter_secure_key_store.dart`
- `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`
- `lib/core/secure_storage/secret_storage_references.dart`
- `lib/core/database/encrypted_db_opener.dart`
- `lib/main.dart`
- `lib/features/identity/domain/repositories/identity_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/features/groups/domain/models/group_key_retention_policy.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_media_server.dart`
- `lib/core/local_discovery/local_media_sender.dart`
- `go-mknoon/crypto/file_crypto.go`
- `lib/core/bridge/go_bridge_client.dart`
- `go-mknoon/node/rendezvous.go`
- `go-relay-server/inbox.go`
- `go-relay-server/push_token_store.go`
- `go-relay-server/backend_memory.go`
- `lib/core/media/media_file_manager.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/post_media_db_helpers.dart`

## why the decomposition is safe to send into downstream planning/execution

The artifact has all mandatory reusable sections, a concrete 12-session ledger, doc-scoped intended plan paths only, explicit dependencies, named regression gates, and a final acceptance session. It does not implement code, does not create a new matrix, and does not rely on generic shared plan paths. Downstream planners can prepare one session at a time and refresh later sessions against landed code before execution.
