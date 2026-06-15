# MIG-002 Migration QR Pairing And Scanner Boundary Plan

Status: closed

## Planning Progress
- 2026-06-06 21:50:25 CEST - Evidence Collector started. Files inspected since last update: implementation-plan-orchestrator skill, graphify skill, graphify-out/graph.json presence, required-doc git status. Decision/blocker: required plan path confirmed; no blocker. Next action: run scoped graphify query before broad source browsing.
- 2026-06-06 21:54:10 CEST - Evidence Collector in progress. Files inspected since last update: graphify scoped QR/account-migration queries, source proposal QR/security rows, MIG-002 breakdown row, QR build/parse use cases, QR scanner wired/screen, codebase test inventory intro. Decision/blocker: contact parser and scanner side-effect risks confirmed; no blocker. Next action: inspect existing QR tests, account-migration files, bridge crypto seam, and named gate definitions.
- 2026-06-06 21:55:00 CEST - Evidence Collector completed. Files inspected since last update: QR application/domain/presentation tests, handle_scanned_qr use case, MIG-001 authority model/repository, bridge ML-KEM/sign/verify helpers, pubspec crypto/uuid deps, test gate definitions. Decision/blocker: MIG-001 dependency exists in repo; host tests can prove this session; no simulator closure gate required for MIG-002. Next action: draft execution contract.
- 2026-06-06 21:55:30 CEST - Planner completed. Files inspected since last update: drafted plan sections in this file. Decision/blocker: plan is limited to migration QR payload, parser/classifier, durable pairing session, export-authorization binding object, and scanner boundary. Next action: reviewer sufficiency pass.
- 2026-06-06 21:56:00 CEST - Reviewer and Arbiter completed. Files inspected since last update: this plan. Decision/blocker: no structural blockers remain; incremental details are recorded as execution choices, not wider scope. Next action: downstream execution-qa child may execute this plan.

## real scope
Implement only the MIG-002 security boundary for account-migration QR pairing:

- Add a migration-specific QR payload kind and version that are separate from contact QR payloads.
- Add migration QR build and parse/use-case code under `lib/features/account_migration/`, including new-phone ephemeral ML-KEM session key material, session ID, creation/expiry timestamps, and a strict parser.
- Add a QR scan classifier/dispatch boundary that recognizes migration payloads before `parseQRPayload`, `handleScannedQR`, contact-add, contact-request, or profile-picture-download side effects can run.
- Add durable single-use old-phone session consumption using storage outside the migrated DB bundle, preferably `SecureKeyStore` as already used by MIG-001 authority state.
- Add an export-authorization value/use case that binds authorization to the consumed session ID and the new-phone ephemeral public key. This session does not export data.
- Add confirmation-code derivation from an authenticated channel transcript object, not directly from raw QR fields. The transcript can be unit-tested without implementing the later local-network transfer.
- Preserve existing contact QR build/parse/scan behavior.

This session must not implement DB snapshot/import, secure-storage migration registry, file/media transfer, local-network migration transport, cutover, migrated-out runtime gates, user-facing full migration screens, final device acceptance, or any relay/cloud fallback.

## closure bar
MIG-002 is good enough when all listed source requirements are independently covered:

| Requirement | Required proof in this session |
| --- | --- |
| Migration QR type discrimination | Migration payloads include `kind` and `version`; parser rejects missing/wrong kind/version; contact payloads are not parsed as migration payloads. |
| Scanner boundary before contact side effects | Widget/use-case tests prove migration QR input never calls contact parser success handling, `addContact`, `sendContactRequest`, or profile/avatar download paths. |
| Contact QR behavior preserved | Existing contact QR parser/build/scanner tests still pass; add one preservation regression if scanner dispatch is refactored around contact flow. |
| Single-use session consumption | Durable repository records consumed session IDs before returning export authorization; reused IDs are rejected across repository reload/recreation. |
| Expiry and clock skew | Parser/session validator rejects expired, too-far-future, malformed timestamp, and stale session inputs with an explicit skew window. |
| New-phone ephemeral key material | Build use case generates and durably stores new-phone ephemeral public/secret material; QR contains only the public key, never the secret key. |
| Export-key binding | Authorization object carries and verifies the consumed session ID and exact new-phone ephemeral public key; mismatched key/session cannot authorize export. |
| Confirmation code from authenticated channel | Confirmation-code use case requires a channel transcript or signed/encrypted pairing proof and cannot derive from QR payload alone. |

Host tests are sufficient for MIG-002 because this session proves parser, storage, scanner-dispatch, and crypto-binding seams. Simulator/device migration acceptance is intentionally deferred to MIG-012 after transfer, import, cutover, and UI sessions exist.

## source of truth
- Active session contract: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`, MIG-002 row.
- Product/security source: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`, especially the QR/security requirements for explicit migration payload type, single-use expiry, scanner separation, and ephemeral-key binding.
- Named gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Current code and tests beat stale prose. Preserve existing dirty worktree changes and do not revert prior-session files.

## session classification
implementation-ready

MIG-001 authority-state dependency exists in `lib/features/account_migration/domain/models/account_migration_authority_state.dart`, `lib/features/account_migration/domain/repositories/account_migration_authority_repository.dart`, and `lib/features/account_migration/application/account_migration_authority_repository_impl.dart`. The executor should still stop before broad implementation if these files are removed or fail to compile.

## exact problem statement
The app currently treats QR scanning as contact scanning. `parseQRPayload` requires contact fields `pk`, `ns`, `rv`, `ts`, and `sig`; malformed contact timestamps emit `QR_PARSE_TIMESTAMP_ERROR` and continue to signature verification. `QRScannerWired` calls `parseQRPayload` directly and sends successful results into contact-add, contact-request, and profile-picture side effects. `handleScannedQR` has the same contact-only path.

Account migration QR pairing is a different security boundary. A migration QR, expired migration QR, reused migration QR, malformed migration timestamp, or contact QR must never authorize account export or trigger contact side effects.

## files and repos to inspect next
Production entry files:

- `lib/features/qr_code/application/build_qr_payload_use_case.dart`
- `lib/features/qr_code/application/parse_qr_payload_use_case.dart`
- `lib/features/qr_code/application/handle_scanned_qr_use_case.dart`
- `lib/features/qr_code/domain/models/qr_payload_model.dart`
- `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
- `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart`
- `lib/core/bridge/bridge.dart`
- `lib/features/account_migration/domain/models/account_migration_authority_state.dart`
- new `lib/features/account_migration/domain/models/` migration payload/session/authorization models
- new `lib/features/account_migration/domain/repositories/` migration session repository contract
- new `lib/features/account_migration/application/` build, parse, consume, authorize, confirmation-code, and repository implementation use cases

Tests and fakes:

- `test/features/qr_code/application/build_qr_payload_use_case_test.dart`
- `test/features/qr_code/application/parse_qr_payload_use_case_test.dart`
- `test/features/qr_code/application/handle_scanned_qr_use_case_test.dart`
- `test/features/qr_code/domain/models/qr_payload_model_test.dart`
- `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`
- new `test/features/account_migration/application/*pairing*_test.dart`
- new `test/features/account_migration/domain/models/*migration_qr*_test.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/core/secure_storage/fake_secure_key_store.dart`

Docs/gates:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
- `Test-Flight-Improv/codebase-test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area
- QR inventory lists 7 current QR tests and no QR integration tests in `Test-Flight-Improv/codebase-test-inventory.md`.
- `test/features/qr_code/application/build_qr_payload_use_case_test.dart` covers contact QR build shape and sorted keys.
- `test/features/qr_code/application/parse_qr_payload_use_case_test.dart` covers contact QR success, invalid JSON, missing fields, self-scan, expiry, invalid signature, ML-KEM field preservation, and non-expired timestamps.
- `test/features/qr_code/application/handle_scanned_qr_use_case_test.dart` covers contact QR dispatch into add-contact, contact-request, and profile-picture download behavior.
- `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart` covers contact scan success with share-intent/feed navigation and is part of the Baseline Gate.
- `test/features/account_migration/*authority*` tests cover MIG-001 state storage/precondition, not MIG-002 pairing.

Missing today: migration QR payload model/parser tests, migration scanner-dispatch tests, durable single-use pairing-session tests, skew/malformed-timestamp fail-closed tests, ephemeral-key persistence tests, export-authorization binding tests, and confirmation-code transcript tests.

## regression/tests to add first
Add RED tests before production changes. Required independent proofs:

- `test/features/account_migration/domain/models/migration_qr_payload_test.dart`
  - payload round-trips with explicit `kind: "account_migration_pairing"` and `version: 1`
  - contact-style payload without migration kind is rejected by migration parser
  - secret key material is not serialized into QR JSON
- `test/features/account_migration/application/migration_qr_payload_use_case_test.dart`
  - new-phone build creates session ID, expiry, and ephemeral ML-KEM key pair using `callMlKemKeygen`
  - malformed timestamp, expired timestamp, future timestamp beyond skew, missing key, wrong kind, and wrong version all fail closed
  - valid timestamp inside skew succeeds
- `test/features/account_migration/application/migration_pairing_session_repository_test.dart`
  - consume-before-authorize is durable across repository reload/recreation
  - reused session ID is rejected
  - stale consumed record remains rejected after restart-style reload
- `test/features/account_migration/application/migration_export_authorization_test.dart`
  - authorization is issued only for a consumed session ID and exact ephemeral public key
  - mismatched session ID or public key is rejected
  - confirmation code cannot be derived from QR payload alone and changes when authenticated channel transcript material changes
- `test/features/qr_code/application/handle_scanned_qr_use_case_test.dart`
  - migration QR does not add a contact, send contact request, or download profile picture
  - malformed migration QR fails before contact parsing/contact side effects
- `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`
  - migration QR dispatch goes to the migration handler path, if provided, with zero contact side effects
  - migration QR with no migration handler fails safely with zero contact side effects
  - valid contact QR still follows the existing contact success path

If the executor introduces a QR classifier abstraction, add focused tests for the classifier rather than relying only on widget tests.

## step-by-step implementation plan
1. Add domain constants/models for migration QR payloads under `lib/features/account_migration/domain/models/`, with explicit kind, version, session ID, created/expires timestamps, new-phone ephemeral public key, and optional challenge/channel nonce. Do not reuse `QRPayloadModel` for migration data.
2. Add a strict migration parser/use case under `lib/features/account_migration/application/` that decodes JSON once, checks migration kind/version, validates required fields and timestamp types, enforces TTL and skew using injectable clock values, and returns typed failure results. Do not call contact QR parser from this parser.
3. Add a new-phone build use case that generates session ID with injectable ID provider/`uuid`, calls existing `callMlKemKeygen`, stores the session secret material durably outside the migrated DB bundle, and returns QR JSON containing only public pairing fields.
4. Add a durable pairing-session repository backed by `SecureKeyStore` with narrowly named account-migration keys. It must support storing new-phone pending sessions and old-phone consumed session records. Use bounded serialized JSON records rather than scattered ad hoc keys when practical.
5. Add an old-phone consume/authorize use case. It must validate the parsed payload, record the session as consumed before returning authorization, reject any consumed/reused/stale session, and return an authorization object bound to the session ID plus exact ephemeral public key. The object is the only artifact later exporter sessions may accept.
6. Add confirmation-code derivation from an authenticated pairing transcript object. Use existing `crypto` package primitives such as HMAC/SHA-256 or SHA-256 over canonical transcript material. The API must require transcript material produced after the authenticated encrypted/signed pairing step; do not expose a helper that derives from raw QR fields alone.
7. Add a QR scan classifier/dispatch helper in `lib/features/qr_code/application/` or a narrow account-migration scan adapter. The dispatch must identify migration kind before invoking `parseQRPayload`, `handleScannedQR`, or contact side effects.
8. Update `QRScannerWired` to route migration payloads to an optional migration handler/use case before contact handling. Preserve constructor compatibility where feasible by making migration handler dependencies optional. Do not build the full migration UI in this session.
9. Update `handleScannedQR` or fence it with classifier logic so programmatic scanned-QR handling cannot treat migration QR payloads as contact QR payloads.
10. Update test fakes only as needed for the new seam, especially `FakeBridge` responses for `mlkem.keygen` if tests use the shared fake.
11. Run direct tests first, then the required baseline gate. If Flutter production code changes, run `graphify update .` after code changes to refresh the graph.
12. Update closure docs listed below after tests pass.

Stop and return blocked if implementing the scanner seam would require full migration UI, local-network transfer, DB import/export, or cutover behavior. Those are later sessions.

## risks and edge cases
- Migration QR must fail closed on malformed timestamps; contact QR behavior must remain unchanged unless a direct contact preservation test is deliberately updated.
- Future-clock skew must be explicit and injectable in tests; do not trust QR timestamps alone for export authorization.
- Single-use consumption must be durable before authorization is returned, so a crash/restart cannot allow reuse.
- Secret key material generated on the new phone must not be embedded in QR JSON or logs.
- Optional scanner migration handler must not create a nullable path where migration QR falls through to contact parsing.
- Confirmation code must bind channel transcript, session ID, old-phone authorization material, and new-phone ephemeral public key. A QR-only code is not acceptable.
- Fire-and-forget contact request/avatar download futures must not start for migration QR, including malformed migration QR.

## exact tests and gates to run
Direct tests required:

```bash
flutter test test/features/account_migration/domain/models/migration_qr_payload_test.dart
flutter test test/features/account_migration/application/migration_qr_payload_use_case_test.dart
flutter test test/features/account_migration/application/migration_pairing_session_repository_test.dart
flutter test test/features/account_migration/application/migration_export_authorization_test.dart
flutter test test/features/qr_code/application/build_qr_payload_use_case_test.dart test/features/qr_code/application/parse_qr_payload_use_case_test.dart test/features/qr_code/application/handle_scanned_qr_use_case_test.dart test/features/qr_code/domain/models/qr_payload_model_test.dart
flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart
```

Fast structural validation before QA handoff:

```bash
flutter test test/features/account_migration/application/migration_qr_payload_use_case_test.dart test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart
```

Named gate required after direct tests:

```bash
./scripts/run_test_gates.sh baseline
```

Graph maintenance after code edits:

```bash
graphify update .
```

No `$run-flutter-reliability-sims` command is required for MIG-002. This session does not prove multi-device transfer, import, cutover, runtime network behavior, notification opening, media/avatar migration, or final iOS-to-iOS acceptance.

## known-failure interpretation
- Treat failures in required direct tests as session-caused unless evidence shows the same tests failed before MIG-002 changes.
- Treat `./scripts/run_test_gates.sh baseline` according to `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`; do not remove red tests from gates.
- If baseline fails outside touched QR/account-migration paths, record the failing file/test, rerun the focused slice, and classify as pre-existing, unrelated-but-required, flaky, environment/tooling-related, or session-caused before any fix attempt.
- Missing simulator/device capacity is not a blocker for MIG-002 because no simulator gate is required here.

## done criteria
MIG-002 is done only when:

- Migration QR payload kind/version, parser, and build use case exist and are covered by direct tests.
- Scanner dispatch checks migration payloads before contact parser/contact side effects.
- Contact QR build/parse/scanner behavior remains covered and passing.
- Durable single-use session consumption rejects reuse across repository reload/recreation.
- Expired, future beyond skew, stale, malformed timestamp, wrong kind/version, contact QR, and malformed migration QR inputs fail closed.
- New-phone ephemeral public key is present in QR; secret key material is stored durably and never serialized into QR JSON.
- Export authorization is bound to consumed session ID and exact ephemeral public key, without exporting data.
- Confirmation-code derivation requires authenticated channel transcript material and is not derivable from QR payload alone.
- Required direct tests and `./scripts/run_test_gates.sh baseline` pass or have exact documented pre-existing/environment classifications.
- `graphify update .` has run after code changes.
- Source proposal rows and test inventory/gate docs listed below are updated if new tests/gate classifications are added.

Coverage ledger:

| User-listed MIG-002 item | Closure state required |
| --- | --- |
| migration-specific QR payload kind/version | Covered by domain/build/parser tests |
| parser and scanner dispatch before contact parser/side effects | Covered by classifier/use-case/widget tests |
| durable single-use session consumption | Covered by repository reload/reuse tests |
| expiry/skew handling | Covered by parser/session validator tests |
| new-phone ephemeral session key material | Covered by build/session persistence tests |
| old-phone export authorization binding | Covered by authorization binding tests |
| confirmation-code derivation from authenticated channel | Covered by transcript-only derivation tests |
| preserve contact QR behavior | Covered by existing plus preservation tests |

## scope guard
Non-goals:

- No DB snapshot/import or SQLCipher migration bundle work.
- No secure-storage key registry/enumeration for all app secrets.
- No media/file manifest or migration transfer implementation.
- No local-network endpoint, chunking/resume, or same-WiFi migration transport.
- No migrated-out cutover, push/rendezvous unregister, old-phone runtime network gates, or pending-work migration.
- No full migration UI beyond an optional scanner handler seam/error path needed to prevent contact side effects.
- No final simulator/device acceptance.
- No generic QR format rewrite unrelated to migration discrimination.
- No new Go bridge commands unless direct evidence shows existing bridge helpers cannot support the narrow pairing proof. If a new command becomes unavoidable, stop and replan.

Overengineering signals:

- Adding multi-device sync semantics.
- Adding generalized QR plugin architecture.
- Persisting migration sessions in the migrated application DB.
- Reusing contact request encryption as-is without an explicit migration-session API and tests.
- Making baseline pass by changing named gate definitions instead of fixing or classifying failures.

## accepted differences / intentionally out of scope
- Contact QR malformed timestamp behavior may remain as-is to preserve contact QR behavior; migration QR must fail closed.
- Confirmation-code derivation can be proved with a typed authenticated transcript model in host tests. The real local-network channel that produces that transcript is deferred to MIG-007.
- Export authorization in MIG-002 is a bound capability/value object, not a data exporter. DB/file export begins in later sessions.
- Simulator-backed iOS-to-iOS acceptance is deferred to MIG-012 because MIG-002 has no full transfer/import/cutover path to exercise.

## dependency impact
- MIG-007 local-network migration transport must consume the MIG-002 session ID, ephemeral public key, and authenticated transcript/confirmation-code contract instead of inventing a second pairing scheme.
- MIG-004/MIG-005 DB and file export/import work must require a MIG-002 export authorization before exposing account data.
- MIG-011 UI must use the MIG-002 scanner/build/session APIs for QR display/scan and must not call contact QR paths for migration.
- MIG-012 final acceptance must include rejected QR variants, no contact side effects, single-use rejection, and confirmation-code behavior as part of end-to-end coverage.

## docs to update when execution finishes
- Update `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md` rows/evidence for QR type discrimination, scanner boundary, single-use, expiry, clock skew, export authorization binding, confirmation code, and no contact side effects.
- Update `Test-Flight-Improv/codebase-test-inventory.md` if new QR/account-migration tests are added.
- Update `Test-Flight-Improv/test-gate-definitions.md` only if new integration/cross-feature/core-service/lifecycle/resilience tests are added or classification changes are required; do not widen named gates for ordinary feature-local unit tests.
- Leave `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md` unchanged unless execution discovers a real scope/dependency correction.

## reviewer findings
Plan sufficiency: sufficient as-is.

- Missing files/tests/gates: none structurally. The plan adds `handle_scanned_qr_use_case.dart` because evidence showed it is an alternate scanned-QR side-effect path.
- Simulator closure: not required for MIG-002 because this is parser/storage/scanner-boundary work, not multi-device transfer or OS/device-state proof.
- Stale assumptions: none found. Current code confirms contact-only QR parser and side-effect paths.
- Overengineering check: no later DB/import/transfer/cutover work is included.
- Minimum needed to make sufficient: already included closure bar, first regressions, direct tests, baseline gate, scope guard, docs update list, and dependency impact.

## arbiter decision
Final classification: execution-ready.

- Structural blockers: none.
- Incremental details intentionally deferred: exact user-facing copy for unsupported migration QR in contact scanner, final migration UI handler shape, and simulator acceptance scenario naming are deferred to MIG-011/MIG-012.
- Accepted differences: host-side transcript tests are accepted for MIG-002; real channel production and end-to-end confirmation-code acceptance are deferred to MIG-007/MIG-012.

## Execution Progress
- 2026-06-06 22:02:00 CEST - Controller contract extraction completed. Files inspected: MIG-002 plan, MIG-002 breakdown row, source proposal QR/security rows, test inventory/gate definitions references, graphify scoped query for QR scanner/contact side-effect boundary, dirty worktree status. Commands/results: `graphify query "MIG-002 account migration QR pairing scanner boundary parseQRPayload handleScannedQR QRScannerWired SecureKeyStore ML-KEM"` succeeded and surfaced `QRScannerWired`, `handleScannedQR`, `parse_qr_payload_use_case.dart`, contact add/request, and profile-picture download paths; `git status --short` showed pre-existing dirty MIG-001/account-migration changes. Decision/blocker: execution contract is sufficient; no blocker. Next action: spawn fresh Executor for MIG-002 implementation using model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-06-06 22:03:00 CEST - Executor spawned. Files inspected/touched: this plan only. Commands/results: spawned Executor agent `019e9e83-bccb-72b3-b12f-43c3441dd8f8` with requested model `gpt-5.5` and reasoning effort `xhigh` in the prompt, because the spawn tool exposes no separate model/reasoning fields. Decision/blocker: waiting for Executor implementation evidence; no blocker yet. Next action: bounded wait, then inspect Executor result and repo/plan progress.
- 2026-06-06 22:04:00 CEST - Executor implementation pass started. Files inspected/touched: MIG-002 plan, MIG-002 breakdown row, source proposal QR/security rows, test gate definitions references, dirty worktree status. Commands/results: `graphify query "MIG-002 account migration QR pairing scanner boundary parseQRPayload handleScannedQR QRScannerWired SecureKeyStore ML-KEM" --budget 2400` passed after a non-blocking graphify skill/package version warning and surfaced the scanner/contact side-effect path through `QRScannerWired`, `handleScannedQR`, and `parse_qr_payload_use_case.dart`. Decision/blocker: inherited executor context cannot set model fields directly; this does not affect execution because the parent spawned this pass. Next action: inspect existing QR/account-migration files and add RED tests before production changes.
- 2026-06-06 22:08:00 CEST - RED tests added and attempted before production code. Files inspected/touched: new account-migration payload/use-case/repository/authorization test files; QR handle-scanned and scanner widget tests. Commands/results: `flutter test test/features/account_migration/domain/models/migration_qr_payload_test.dart` failed RED on missing `migration_qr_payload.dart` and `migration_qr_payload_use_case.dart`; `flutter test test/features/account_migration/application/migration_qr_payload_use_case_test.dart` failed RED on missing pairing repository, payload, parser, and build APIs. The two other parallel RED attempts hit a native-assets `lipo` collision caused by concurrent Flutter startup, so they are not used as behavioral evidence and will be rerun serially after implementation. Decision/blocker: RED state established; no blocker. Next action: implement migration payload/session/authorization APIs and scanner classifier boundary.
- 2026-06-06 22:12:00 CEST - Implementation and direct tests completed. Files inspected/touched: migration QR payload/session/authorization models and use cases, SecureKeyStore pairing session repository, scanned QR classifier, `handle_scanned_qr_use_case.dart`, `qr_scanner_wired.dart`, new account-migration tests, updated QR tests, source proposal evidence, codebase test inventory. Commands/results: required direct tests passed: `flutter test test/features/account_migration/domain/models/migration_qr_payload_test.dart`; `flutter test test/features/account_migration/application/migration_qr_payload_use_case_test.dart`; `flutter test test/features/account_migration/application/migration_pairing_session_repository_test.dart`; `flutter test test/features/account_migration/application/migration_export_authorization_test.dart`; `flutter test test/features/qr_code/application/build_qr_payload_use_case_test.dart test/features/qr_code/application/parse_qr_payload_use_case_test.dart test/features/qr_code/application/handle_scanned_qr_use_case_test.dart test/features/qr_code/domain/models/qr_payload_model_test.dart`; `flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`. Fast structural validation also passed: `flutter test test/features/account_migration/application/migration_qr_payload_use_case_test.dart test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`. Decision/blocker: direct required evidence is green; no blocker. Next action: run required named gate `./scripts/run_test_gates.sh baseline`.
- 2026-06-06 22:14:00 CEST - Required gate failed and triage started. Files inspected/touched: this plan. Commands/results: `./scripts/run_test_gates.sh baseline` ran the Baseline Gate host tests to `All tests passed!`, then exited 1 when the next Flutter invocation saw multiple attached devices and no selected device. Failing gate command: `./scripts/run_test_gates.sh baseline`. Failing file/test: no Dart test failure identified; device-selection error listed multiple Android/iOS/macOS/Chrome targets. Log path: none, output was terminal. Focused triage command about to run: inspect baseline device handling with `sed -n '1,220p' scripts/run_test_gates.sh` and rerun the named gate with `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` if the script supports that documented environment selector. Classification state: pending_triage. Decision/blocker: likely environment/tooling-related device selection, not session-caused; pending confirmation. Next action: inspect script then rerun focused gate with explicit device if supported.
- 2026-06-06 22:17:00 CEST - Baseline gate triage completed. Files inspected/touched: `scripts/run_test_gates.sh`, this plan. Commands/results: script inspection confirmed `integration_test_args()` uses `FLUTTER_DEVICE_ID`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed. Classification: original `./scripts/run_test_gates.sh baseline` red was environment/tooling-related because multiple devices were attached and no target was selected after the host batch passed. Decision/blocker: required Baseline Gate evidence is green with documented device selector; no blocker. Next action: run `graphify update .` after code/doc changes.
- 2026-06-06 22:21:50 CEST - Executor finalization completed. Files inspected/touched: this plan; generated graph artifacts under `graphify-out/` were refreshed by graphify. Commands/results: `graphify update .` passed after the same non-blocking graphify skill/package version warning; AST extraction completed for 4880/4880 files, curated graph backup was written under `graphify-out/backups/2026-06-06/`, and `graphify-out/graph.json` / `graphify-out/GRAPH_REPORT.md` were rebuilt with 91382 nodes, 161609 edges, and 4007 communities. Decision/blocker: MIG-002 executor verdict is accepted and ready for QA handoff; no blockers. Next action: QA/reviewer pass should use the direct test and gate evidence recorded above.
- 2026-06-06 22:23:00 CEST - Controller received Executor result and inspected repo-backed evidence. Files inspected/touched: this plan, `git status --short`, `git diff --stat`, account-migration/QR test file list. Commands/results: Executor reported all required direct tests and fast structural validation passed; exact `./scripts/run_test_gates.sh baseline` failed after host tests due to multiple attached devices/no selected target, then `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; `graphify update .` passed. Decision/blocker: ready for isolated QA Reviewer; no blocker. Next action: spawn fresh QA Reviewer using model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-06-06 22:24:00 CEST - QA Reviewer spawned. Files inspected/touched: this plan only. Commands/results: spawned QA Reviewer agent `019e9e9a-8939-7e72-b4b3-8ab4d9d97455` with requested model `gpt-5.5` and reasoning effort `xhigh` in the prompt, because the spawn tool exposes no separate model/reasoning fields. Decision/blocker: waiting for QA sufficiency review; no blocker yet. Next action: bounded wait for QA result.
- 2026-06-06 22:30:32 CEST - QA Reviewer completed sufficiency review. Files inspected/touched: MIG-002 plan, MIG-002 breakdown row, source proposal evidence rows, `codebase-test-inventory.md`, `scripts/run_test_gates.sh`, account-migration QR/session/authorization files, QR classifier/handler/widget files, required account-migration and QR tests, dirty worktree status, graphify artifact timestamps. Commands/results: reran all required direct tests, reran fast structural validation, reproduced exact `./scripts/run_test_gates.sh baseline` environment failure after host tests passed due to multiple attached devices/no selected target, then reran `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` and it passed. Decision/blocker: accepted; no blocking issues. Next action: no fix pass required.

## QA Verdict
Final verdict: accepted.

- Blocking issues: none.
- Non-blocking follow-ups: none for MIG-002.
- Fix pass required: no.
- Dirty worktree note: MIG-001 identity/startup authority files remain dirty separately from the MIG-002 QR/account-migration pairing work; no unrelated changes were reverted or edited during QA.

## Final Execution Verdict
accepted

- Blockers: none.
- Spawned-agent isolation used: yes. Executor `019e9e83-bccb-72b3-b12f-43c3441dd8f8`, then QA Reviewer `019e9e9a-8939-7e72-b4b3-8ab4d9d97455`.
- Local sequential fallback used: no.
- Required direct tests: passed.
- Required named gate: exact `./scripts/run_test_gates.sh baseline` reproduced an environment/device-selection failure after host tests passed; focused supported rerun `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed and QA accepted the classification.
- Graph maintenance: `graphify update .` passed after code/doc changes, with graph rebuilt to 91382 nodes, 161609 edges, and 4007 communities.
- QA result: accepted with no blocking issues and no non-blocking follow-ups.

## Closure Progress
- 2026-06-06 22:39:09 CEST - Closure Writer completed. Files inspected: this MIG-002 plan, reusable session breakdown, source proposal MIG-002 evidence rows, `Test-Flight-Improv/codebase-test-inventory.md` MIG-002 notes, scoped graphify query result, and dirty worktree status. Decision/blocker: accepted execution and QA evidence still match the bounded MIG-002 security-boundary scope; session closure classification is `closed`; no blocker. Next action: none for MIG-002 closure. MIG-003 through MIG-012 remain pending and are not planned or executed by this pass.

## Closure Verdict
Session closure classification: `closed`.

- What is now closed: MIG-002's migration QR pairing and scanner boundary only. The closed scope includes migration QR kind/version discrimination, strict migration parser/build coverage, durable single-use pairing-session consumption, expiry/skew fail-closed behavior, new-phone ML-KEM ephemeral key handling with no QR secret serialization, old-phone export authorization binding to the consumed session ID and exact ephemeral public key, transcript-derived confirmation-code contract coverage, and scanner fencing before contact parser/contact-add/contact-request/profile-picture side effects.
- Residual-only items: none inside MIG-002.
- Still-open items: the overall Move Account program remains open. DB snapshot/import, secure-storage registry/staging/cleanup, media and app-owned file transfer, local-network migration transport, durable cutover, migrated-out runtime gates, pending-work migration, full UI journey, simulator/device acceptance, and final program closure remain deferred to MIG-003 through MIG-012.
- Accepted differences: host-side transcript-contract tests are accepted for MIG-002 while real authenticated local-network channel production remains deferred to MIG-007 and final end-to-end confirmation-code acceptance remains deferred to MIG-012. The exact `./scripts/run_test_gates.sh baseline` run failed only on multiple attached devices/no selected target after host tests passed; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed and QA accepted that environment/tooling classification.
- Reopen only on real regression: reopen MIG-002 only if the migration QR parser/build/session/authorization/scanner boundary or listed direct tests regress, or if later sessions prove the MIG-002 pairing contract cannot safely support transfer/export/import.
