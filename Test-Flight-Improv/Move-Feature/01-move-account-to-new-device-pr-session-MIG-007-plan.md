Status: closed (MIG-007 only; overall Move Account still open)

# MIG-007 Plan - Migration-Specific Encrypted Segmented Transfer

## Planning Progress

- `2026-06-07T15:31:50Z` - role: Arbiter completed by controller local plan fallback; files inspected: MIG-007 breakdown/source rows, local discovery/media code/tests, account-migration QR/export auth/manifest code/tests, bridge/Go blob helper evidence, transport gate definitions; decision/blocker: no structural blocker remains for a host-first implementation plan; next action: spawn fresh execution/QA for this plan.
- `2026-06-07T15:31:50Z` - role: Reviewer completed by controller local plan fallback; files inspected: `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md`, `go-mknoon/crypto/file_crypto.go`, `lib/core/bridge/bridge.dart`; decision/blocker: plan must include a device/relay profile, no MIG-006 group simulator, no whole-file blob helper reliance, and route-preservation tests for `/media/<id>`; next action: mark sufficient after adding those constraints.
- `2026-06-07T15:31:50Z` - role: Planner completed by controller local plan fallback; files inspected: `local_ws_server.dart`, `local_media_server.dart`, `local_media_sender.dart`, `local_p2p_service.dart`, account-migration manifests, migration pairing/export authorization tests; decision/blocker: implement a migration-only transfer service with per-segment crypto and verified checkpoint state rather than widening the media upload protocol; next action: reviewer pass.
- `2026-06-07T15:28:08Z` - role: Evidence Collector started; files inspected: `implementation-plan-orchestrator/SKILL.md`, `graphify/SKILL.md`, existing MIG-007 plan intake, targeted git status; decision/blocker: graphify graph exists and must be used first for transfer orientation; next action: run scoped graphify query, then inspect MIG-007 source row, proposal transfer sections, local transfer code/tests, and named gate definitions.
- `2026-06-07T15:26:15Z` - role: controller intake; files inspected: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`, `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`, graphify query for remaining Move Account sessions, git status; decision/blocker: MIG-006 is explicitly deferred-last by user override, not failed or closed, so MIG-007 is the next allowed dependency-satisfied session; next action: spawn a fresh `$implementation-plan-orchestrator` child with `model: gpt-5.5` and `reasoning_effort: xhigh` to complete this doc-scoped execution plan.

## Planning Fallback Note

The first fresh planner child wrote the Evidence Collector heartbeat but did not update this artifact again after bounded waits and a settle poll. The controller terminated only that MIG-007 child and used the pipeline's local plan fallback because the MIG-007 breakdown entry is execution-safe and dependency-satisfied under the explicit MIG-006 deferred-last override.

## Real Scope

Implement the migration-specific local transfer layer for the Move Account MVP.

In scope:

- Add migration transfer domain models for a transfer session, bundle manifest, segment manifest, verified segment checkpoint, resume request, and transfer result.
- Add a migration-only local transfer service or endpoint that is separate from the existing chat media `PUT /media/<id>` path.
- Bind the transfer session to MIG-002 pairing/export authorization material: session ID, new-phone ephemeral public key, old-phone peer ID, authenticated channel binding, and confirmation-code transcript material.
- Transfer an opaque account bundle made from prior-session outputs: database snapshot/manifest, secure-storage payload metadata, file/media manifest references, and group manifest references. MIG-007 may package these as a manifest-driven bundle envelope, but it must not redefine their validation contracts.
- Encrypt and authenticate each segment independently with unique nonces and associated data that includes at least session ID, bundle ID, segment index, byte range, plaintext length, manifest hash, and protocol version.
- Persist verified progress on the receiver before acknowledging each segment so restart/resume can request only missing or invalid segments.
- Reject incomplete, duplicate-conflicting, wrong-session, wrong-key, wrong-index, wrong-size, wrong-checksum, reused-nonce, malformed-manifest, and unsupported-version transfer states.
- Preserve existing local chat media behavior and tests: normal `media_offer`, `/media/<id>`, MIME allowlist, bearer token, SHA-256 verification, and local media sender semantics must keep working unchanged.
- Ensure no relay, cloud, iCloud, or ordinary media upload fallback is used for migration bundle data.
- Avoid logging account secrets, DB keys, segment plaintext, ciphertext bytes, secure-storage values, media keys, or migration auth tokens.

Out of scope:

- MIG-006 group simulator commands and group release evidence. MIG-006 remains deferred-last/evidence-gated.
- Durable cutover, server lease cleanup, old-phone runtime network gates, pending-work ownership, and user journey UI. Those belong to MIG-008 through MIG-011.
- Final iOS-to-iOS release acceptance and physical same-WiFi device-lab proof. MIG-012 owns final acceptance; this session should leave exact supporting evidence and any remaining device fixture notes.
- Replacing ordinary local media upload with migration transfer.
- Sending migration data through relay/cloud/iCloud or adding a fallback that can do so.

## Closure Bar

MIG-007 is ready to close when:

- The repo has a migration-specific transfer API that can send and receive a multi-segment account bundle over the local transport seam without using `/media/<id>`.
- Each segment is independently AEAD-protected or bridge-protected with unique nonces and authenticated associated data tied to the MIG-002 session/export authorization.
- Receiver-side verified progress survives interruption/restart and resumes from validated missing segment ranges only.
- The transfer rejects incomplete, tampered, wrong-session, replayed, reused-nonce, wrong-size, wrong-checksum, unsupported-version, and no-local-peer states without exposing partial account access.
- Existing chat media local transfer direct tests still pass and include at least one regression proving migration transfer does not weaken or replace the media route.
- Direct MIG-007 tests pass, the Baseline Gate passes with an explicit device target when needed, and the Startup / Transport Gate is run with an explicit `FLUTTER_DEVICE_ID` if integration-backed transport files are touched.
- The source proposal is updated with concrete MIG-007 evidence, while the overall doc remains open because MIG-006 and later sessions are not closed.

## Source Of Truth

- Product source: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`.
- Session source: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`, MIG-007 row plus the current sequencing override.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Current code wins over stale prose for implementation details.
- Existing MIG-002/MIG-004/MIG-005/MIG-006 artifacts may be consumed as dependency evidence, but MIG-006 is not closed and its remaining group simulator evidence must not run in this phase.

## Session Classification

`implementation-ready`.

MIG-007's formal dependencies are MIG-002, MIG-004, and MIG-005, all marked closed in the breakdown. MIG-006 is deliberately deferred-last/evidence-gated by user override and is not a dependency for this session.

## Exact Problem Statement

The proposal requires moving a full account bundle directly over same-WiFi with authenticated encryption, bounded memory, verified resume, and no relay/cloud fallback. The repo currently has useful local discovery and media transfer primitives, but the existing media path is a MIME-filtered single HTTP `PUT /media/<id>` flow and the Go `blob:encrypt`/`blob:decrypt` helpers read whole files into memory. That is insufficient for a sensitive migration bundle.

## Device/Relay Proof Profile

- Profile classification for MIG-007 closure: `single-device transport gate plus host loopback protocol proof`.
- Live availability check before integration-backed gates: run `flutter devices --machine`.
- Default single Flutter target if available: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`.
- Host fallback target for baseline only when simulator/device routing is not required: `FLUTTER_DEVICE_ID=macos`.
- Required closure evidence:
  - Host/direct tests prove manifest, per-segment crypto seam, resume checkpoints, route separation, tamper rejection, and no relay/cloud fallback calls.
  - `FLUTTER_DEVICE_ID=<available-device-id> ./scripts/run_test_gates.sh transport` is required if execution changes `lib/core/local_discovery/*`, `integration_test/*transport*`, or startup/transport wiring.
- Supporting release evidence, not default MIG-007 closure: paired physical/simulator same-WiFi proof and final full account migration acceptance. MIG-012 owns that final device acceptance.
- `run_with_devices.sh group`, full group simulator, `group-real-network-nightly`, and MIG-006 release evidence are explicitly forbidden in this session.
- A single `FLUTTER_DEVICE_ID` only selects the Flutter target for integration-backed transport gates; it does not by itself prove a physical two-phone same-WiFi migration journey.

## Files And Repos To Inspect Next

Production:

- `lib/features/account_migration/application/migration_export_authorization.dart`
- `lib/features/account_migration/application/migration_pairing_session_repository_impl.dart`
- `lib/features/account_migration/application/migration_qr_payload_use_case.dart`
- `lib/features/account_migration/domain/models/migration_qr_payload.dart`
- `lib/features/account_migration/domain/models/migration_database_manifest.dart`
- `lib/features/account_migration/domain/models/migration_file_manifest.dart`
- `lib/features/account_migration/domain/models/migration_group_manifest.dart`
- New `lib/features/account_migration/domain/models/migration_transfer_manifest.dart`
- New `lib/features/account_migration/application/migration_segment_crypto.dart`
- New `lib/features/account_migration/application/migration_segmented_transfer_service.dart`
- New `lib/features/account_migration/application/migration_transfer_checkpoint_store.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/local_discovery/local_media_server.dart`
- `lib/core/local_discovery/local_media_sender.dart`
- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `go-mknoon/crypto/file_crypto.go`
- `go-mknoon/bridge/bridge.go`

Tests:

- New `test/features/account_migration/application/migration_segment_crypto_test.dart`
- New `test/features/account_migration/application/migration_segmented_transfer_service_test.dart`
- New `test/features/account_migration/application/migration_transfer_checkpoint_store_test.dart`
- New `test/features/account_migration/application/migration_transfer_manifest_test.dart`
- `test/features/account_migration/application/migration_export_authorization_test.dart`
- `test/features/account_migration/application/migration_qr_payload_use_case_test.dart`
- `test/core/local_discovery/local_ws_server_test.dart`
- `test/core/local_discovery/local_media_server_test.dart`
- `test/core/local_discovery/local_media_sender_test.dart`
- `test/core/local_discovery/local_media_integration_test.dart`
- `test/core/bridge/bridge_helpers_test.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- Go tests under `go-mknoon` if bridge commands or Go crypto are added.

## Existing Tests Covering This Area

- `test/features/account_migration/application/migration_export_authorization_test.dart` proves consumed session authorization, exact key binding, reuse rejection, and confirmation-code transcript sensitivity.
- `test/features/account_migration/application/migration_qr_payload_use_case_test.dart` proves MIG-002 QR payload creation, expiry/skew parsing, persisted new-phone ephemeral key material, and fail-closed parsing.
- `test/features/account_migration/application/migration_database_*` tests prove DB manifest/snapshot/import staging from MIG-004.
- `test/features/account_migration/application/migration_file_*` tests prove file/media manifest and storage preflight from MIG-005.
- `test/core/local_discovery/local_media_server_test.dart`, `local_media_sender_test.dart`, and `local_media_integration_test.dart` prove the existing media offer plus `/media/<id>` upload path.
- `test/core/local_discovery/local_ws_server_test.dart` proves WS local messaging and media route behavior.
- `scripts/run_test_gates.sh transport` currently runs `background_reconnect`, `wifi_relay_fallback_smoke`, `transport_e2e`, and `media_stable_id_smoke` one integration file at a time.

Missing:

- No current test proves migration-specific transfer route separation.
- No current test proves per-segment migration AEAD metadata, unique nonces, verified resume, or incomplete segment rejection.
- No current test proves migration transfer cannot use relay/cloud/iCloud fallback.

## Regression/Tests To Add First

Add failing tests before production implementation:

- `migration_transfer_manifest_test.dart`: manifest requires protocol version, session ID, bundle ID, segment size, total bytes, manifest hash, ordered segment descriptors, unique nonces, segment checksums, and unsupported-version rejection.
- `migration_segment_crypto_test.dart`: encrypt/decrypt one bounded segment with associated data; reject wrong session ID, bundle ID, segment index, nonce, manifest hash, or ciphertext tag; prove no call to `blob:encrypt` or `blob:decrypt` for bundle transfer.
- `migration_transfer_checkpoint_store_test.dart`: records verified segment index/checksum only after validation, survives repository reload, rejects conflicting duplicate segment, and computes missing ranges after interruption.
- `migration_segmented_transfer_service_test.dart`: transfers a multi-segment bundle using a fake local channel, resumes after interruption from missing verified segments, rejects truncated final bundle, rejects wrong authorization, rejects no-local-peer with no relay fallback, and excludes sensitive material from emitted events/log details.
- Local discovery route regression in `local_ws_server_test.dart` or a new account-migration focused local-discovery test: migration endpoint is distinct from `/media/<id>`, and existing media offer/upload tests still pass unchanged.
- Bridge/Go tests if new segment crypto commands are added: command map allows only segment-sized payloads, requires associated data, rejects nonce reuse in the test harness, and does not route through whole-file blob helpers.

## Step-By-Step Implementation Plan

1. Add transfer manifest/domain types.
   - Define protocol version, bundle ID, session ID, transfer direction, segment size, total bytes, manifest hash, segment descriptors, nonce, byte range, plaintext SHA-256, ciphertext SHA-256, and status/result enums.
   - Keep database/file/group manifest validation owned by prior sessions; MIG-007 only references their manifest payloads.

2. Add a per-segment crypto seam.
   - Prefer a `MigrationSegmentCrypto` interface with a fake implementation for host tests and a bridge-backed implementation for production.
   - If bridge support is needed, add new segment-sized commands rather than using `blob:encrypt` or `blob:decrypt`.
   - Associated data must include protocol version, session ID, bundle ID, segment index, byte range, manifest hash, and direction.

3. Add receiver checkpoint storage.
   - Store verified segment descriptors and checksums outside the normal imported account DB state.
   - Persist only after decrypt/auth/checksum validation.
   - Provide missing-range calculation for resume and cleanup for cancel/failure.

4. Add migration-specific transfer service.
   - Expose a migration-only service or route under local transport, such as `/migration/<sessionId>/...`, not `/media/<id>`.
   - Bind every request to MIG-002 export authorization and channel transcript material.
   - Implement offer, manifest exchange, segment receive, checkpoint ack, resume request, and final manifest verification.
   - Reject relay/cloud fallback explicitly by depending only on local discovery/local peer resolution and returning a no-local-path failure.

5. Wire local discovery without weakening media.
   - Add a configuration point in `LocalWsServer` or a separate account-migration local server that can handle migration transfer requests.
   - Preserve `media_offer`, `LocalMediaServer`, `LocalMediaSender`, `/media/<id>`, MIME validation, token validation, and current media tests.

6. Add interruption/resume behavior.
   - Simulate network interruption mid-bundle.
   - On restart, reload checkpoint state and request only missing verified ranges.
   - Final success requires all segment descriptors verified and the assembled bundle checksum/manifest hash matched.

7. Add no-sensitive-log coverage.
   - Ensure emitted flow events and errors include safe IDs/statuses only, not keys, plaintext, ciphertext bytes, auth tokens, DB paths with secrets, secure-storage values, or media keys.

8. Update source proposal evidence after execution.
   - Record MIG-007 concrete files/tests/gates in `Existing Coverage And Gaps` and/or `Acceptance Evidence`.
   - Keep overall Move Account status open because MIG-006 is deferred-last and MIG-008 through MIG-012 remain unresolved.

## Risks And Edge Cases

- Large bundle memory use: tests must use a small segment size and prove streaming/segment iteration rather than full-file encryption helpers.
- Nonce uniqueness: manifest validation must reject duplicate nonces within a session/bundle.
- Wrong-session replay: associated data must make a segment from one session fail in another.
- Partial success: a verified segment is not a verified account import; no normal app access should be exposed by MIG-007.
- Race between duplicate segment uploads: checkpoint store must reject conflicting descriptors.
- Local transport ambiguity: migration transfer must never be accepted as normal chat media.
- Device proof limits: host/loopback transport can prove protocol and route behavior, but not physical same-WiFi Bonjour/mDNS acceptance.

## Exact Tests And Gates To Run

Minimum direct tests:

```bash
flutter test \
  test/features/account_migration/application/migration_transfer_manifest_test.dart \
  test/features/account_migration/application/migration_segment_crypto_test.dart \
  test/features/account_migration/application/migration_transfer_checkpoint_store_test.dart \
  test/features/account_migration/application/migration_segmented_transfer_service_test.dart \
  test/features/account_migration/application/migration_export_authorization_test.dart \
  test/features/account_migration/application/migration_qr_payload_use_case_test.dart \
  test/core/local_discovery/local_ws_server_test.dart \
  test/core/local_discovery/local_media_server_test.dart \
  test/core/local_discovery/local_media_sender_test.dart \
  test/core/local_discovery/local_media_integration_test.dart
```

Bridge/Go direct tests if bridge or Go crypto is touched:

```bash
flutter test test/core/bridge/bridge_helpers_test.dart test/core/bridge/go_bridge_client_test.dart
(cd go-mknoon && go test ./...)
```

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Use a different explicit `FLUTTER_DEVICE_ID` only if `flutter devices --machine` shows the default simulator is unavailable. Do not run group simulator or MIG-006 release commands.

## Known-Failure Interpretation

- A bare `./scripts/run_test_gates.sh baseline` can fail in this repo when multiple devices are attached and no `FLUTTER_DEVICE_ID` is selected. Use the explicit device target in this plan.
- If `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` is unavailable, record the live `flutter devices --machine` output and use another available target or classify only that integration-backed gate as fixture-blocked.
- MIG-006 commands 29-123 are intentionally deferred by user override and are not a MIG-007 failure.

## Done Criteria

- `Status: execution-ready` plan is executed by a fresh execution/QA child.
- All in-scope product/test changes are limited to account-migration transfer, local transport route integration, bridge/Go segment crypto only if required, and source/test documentation evidence.
- Direct tests listed above pass or have a concrete, current-session blocker.
- Required named gates pass or device availability is recorded exactly.
- Source proposal evidence is updated without closing the overall Move Account doc.
- Breakdown ledger marks MIG-007 closed only after execution and closure audit, not from this plan alone.

## Scope Guard

Do not:

- Run MIG-006 group simulator/release evidence.
- Use or extend ordinary `PUT /media/<id>` as the migration bundle protocol.
- Use whole-file `blob:encrypt`/`blob:decrypt` for migration bundle encryption.
- Implement cutover, migrated-out runtime gates, pending-work ownership, UI journey, erase/reset UX, or final acceptance.
- Add relay/cloud/iCloud fallback for migration data.
- Rewrite local discovery architecture beyond the minimum migration route hook.
- Reopen MIG-001 through MIG-005 closure unless current execution finds a real regression in their consumed contracts.

## Accepted Differences / Intentionally Out Of Scope

- Host and single-device transport gates can close the implementation contract for this session; physical two-phone same-WiFi release acceptance remains MIG-012 unless execution adds a ready non-interactive paired-device harness.
- MIG-007 may add a new bridge segment crypto command if Dart-side AES-GCM is not available. That is acceptable because existing Go blob helpers are whole-file and explicitly insufficient for this session.
- Group/NSE continuity stays evidence-gated in MIG-006; MIG-007 only transports opaque manifest payloads and does not prove migrated group rendering/decryption.

## Dependency Impact

- MIG-008 depends on MIG-007 for a verified local transfer result before durable cutover can activate the new phone.
- MIG-011 depends on MIG-007 for progress stage semantics and interruption/resume status.
- MIG-012 depends on MIG-007 evidence for final end-to-end iOS-to-iOS transfer acceptance.
- If MIG-007 cannot provide verified local transfer without external fixture support, MIG-008 through MIG-012 must treat transfer as blocked rather than inventing a fallback.

## Reviewer Findings

- Finding: The plan must not overclaim physical same-WiFi closure from host tests.
  Resolution: Device/Relay Proof Profile classifies physical paired same-WiFi proof as MIG-012/release evidence unless a fixture is added.
- Finding: The existing local media endpoint is unsafe to reuse for migration.
  Resolution: Scope requires a migration-only endpoint/service and route-preservation tests.
- Finding: Existing Go blob helpers are whole-file.
  Resolution: Scope forbids `blob:encrypt`/`blob:decrypt` for the migration bundle and allows only bounded segment crypto.
- Finding: MIG-006 override must stay visible.
  Resolution: Plan forbids MIG-006 simulator/release commands and keeps overall doc open.

## Arbiter Decision

No structural blockers remain. The plan is execution-safe for MIG-007 under the user sequencing override. Incremental details such as exact segment size and endpoint naming are left to execution as long as tests prove bounded memory, route separation, verified resume, and authenticated per-segment metadata.

## Execution Progress

- `2026-06-07T15:35:05Z` - phase: controller dirty-worktree snapshot before contract extraction; files inspected: `git status --short`, MIG-007 plan, session breakdown, graphify scoped query; command/result: `git status --short` showed existing dirty baseline from prior MIG sessions, including modified `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`, `Test-Flight-Improv/codebase-test-inventory.md`, `Test-Flight-Improv/test-gate-definitions.md`, multiple group/identity/QR files and tests, untracked MIG-001 through MIG-007 plan files, untracked session breakdown, untracked `lib/features/account_migration/`, and untracked `test/features/account_migration/`; decision/blocker: treat these as baseline and do not revert; next action: extract MIG-007 execution contract and spawn Executor.
- `2026-06-07T15:35:05Z` - phase: contract extracted; files inspected: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-007-plan.md`, `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`; contract: implement only migration-specific encrypted segmented transfer, route separation from `/media/<id>`, per-segment auth/crypto with session/export binding, checkpoint/resume, no relay/cloud fallback, sensitive-log exclusions, and required tests/docs; required direct tests: MIG-007 manifest/crypto/checkpoint/service tests, MIG-002 authorization/QR tests, and local media/ws route-preservation tests; required gates: explicit-device baseline, live device check before transport, transport when touched transport surfaces, completeness-check, and `git diff --check`; forbidden commands: MIG-006 group simulator/release evidence including `run_with_devices.sh group`, full group simulator, `group-real-network-nightly`; decision/blocker: no implementation-owned blocker before Executor; next action: spawn fresh Executor with requested model/reasoning settings.
- `2026-06-07T15:35:34Z` - phase: Executor spawned/running; files inspected: plan and breakdown contract; command/current action: spawning fresh Executor child for MIG-007 only with requested `model: gpt-5.5` and `reasoning_effort: xhigh`; decision/blocker: nested agent tooling is available; next action: wait for Executor completion evidence, then spawn QA Reviewer.
- `2026-06-07T15:36:48Z` - phase: Executor running/implementation intake; files inspected: `implementation-execution-qa-orchestrator/SKILL.md`, graphify scoped query, MIG-007 plan tail, `git status --short`, account-migration/local-discovery file list; command/result: graphify query returned generic media context, `git status --short` confirmed dirty prior-session baseline; decision/blocker: follow MIG-007 plan only, do not revert unrelated changes, do not run MIG-006 group/release commands; next action: inspect owner files and add required MIG-007 regressions before production implementation where practical.
- `2026-06-07T15:40:43Z` - phase: local execution fallback started after spawned execution no-progress; files inspected: plan execution progress, scoped account-migration/local-discovery status, `bridge.dart`, `fake_bridge.dart`; command/result: the fresh execution controller and nested Executor produced only intake heartbeats and no code/test/doc delta after bounded waits and settle poll, then were terminated by the parent controller; decision/blocker: use the pipeline's single local execution fallback for MIG-007, preserving the same scope guard and no MIG-006 commands; next action: add focused MIG-007 transfer models/crypto/checkpoint/service tests and implementation.
- `2026-06-07T15:47:39Z` - phase: local execution direct tests passed; files touched: `migration_transfer_manifest.dart`, `migration_segment_crypto.dart`, `migration_transfer_checkpoint_store.dart`, `migration_segmented_transfer_service.dart`, `local_ws_server.dart`, four new MIG-007 tests, and `local_ws_server_test.dart`; command/result: `flutter test test/features/account_migration/application/migration_transfer_manifest_test.dart test/features/account_migration/application/migration_segment_crypto_test.dart test/features/account_migration/application/migration_transfer_checkpoint_store_test.dart test/features/account_migration/application/migration_segmented_transfer_service_test.dart test/features/account_migration/application/migration_export_authorization_test.dart test/features/account_migration/application/migration_qr_payload_use_case_test.dart test/core/local_discovery/local_ws_server_test.dart test/core/local_discovery/local_media_server_test.dart test/core/local_discovery/local_media_sender_test.dart test/core/local_discovery/local_media_integration_test.dart` passed with `+74`; decision/blocker: direct MIG-007 and route-preservation proof is green; next action: run `git diff --check`, completeness-check, live device availability, and required gates.
- `2026-06-07T15:39:31Z` - phase: owner files inspected before edits; files inspected: `migration_export_authorization.dart`, existing database/file/group migration manifest models, `migration_pairing_session_repository_impl.dart`, `local_ws_server.dart`, `local_media_server.dart`, `local_media_sender.dart`, `local_discovery_service.dart`, local WS/media tests, account-migration authorization/file-manifest tests, `flow_event_emitter.dart`, `pubspec.yaml`, bridge blob command references; decision/blocker: implement new account-migration transfer manifest, AES-GCM segment crypto seam, checkpoint store, fake-channel transfer service, and additive `/migration/<sessionId>/...` route hook while leaving `/media/<id>` unchanged; next action: add MIG-007 regression tests and production files.
- `2026-06-07T15:52:25Z` - phase: host gates partially completed; commands/results: `git diff --check` passed clean, `flutter devices --machine` showed planned simulator `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` available as `iPhone Air`, `./scripts/run_test_gates.sh completeness-check` passed with `799/799` test files classified, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed including the host subset (`+105`) plus `loading_states_smoke_test.dart` and `posts_phase1_fake_test.dart` macOS integration slices; decision/blocker: no host-gate blocker; next action: run `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` without running MIG-006 group/release evidence.
- `2026-06-07T15:59:23Z` - phase: transport gate completed; command/result: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed; evidence details: `background_reconnect_test.dart` completed as skipped under this fixture, `wifi_relay_fallback_smoke_test.dart` passed self-contained with no CLI peer fixture, `transport_e2e_test.dart` passed self-contained scenarios (`4/4` orchestrated plus follow-on cases), and `media_stable_id_smoke_test.dart` passed with `+7`; decision/blocker: no transport blocker for MIG-007's single-device transport gate; next action: run closure review, update source proposal evidence, update breakdown ledger only if closure accepts, and keep MIG-006 deferred-last.
- `2026-06-07T16:02:15Z` - phase: closure review fix and post-fix direct proof; issue found: manifest compatibility sorted segment descriptors but did not explicitly require contiguous indexes starting at `0`, and non-final segment length used descriptor index rather than sorted position; fix: added `segmentIndexMismatch`, checked `segment.index == sortedPosition`, and added a non-contiguous-index regression; commands/results: `dart format` on touched manifest/test files reported `0 changed`, focused MIG-007/local-WS set passed with `+25`, and the full direct MIG-007 command from this plan passed after the fix with `+75`; decision/blocker: validation gap resolved; next action: rerun cheap post-fix checks, update docs, then close MIG-007 if audit accepts.
- `2026-06-07T16:04:14Z` - phase: post-fix cheap checks and doc closure evidence; commands/results: post-fix `git diff --check` passed clean, post-fix `./scripts/run_test_gates.sh completeness-check` passed with `799/799`, source proposal was updated with MIG-007 transfer evidence and remaining gaps, and the breakdown ledger was updated to close MIG-007 while preserving MIG-006 as deferred-last/evidence-gated; decision/blocker: no MIG-007 blocker remains; next action: continue pipeline with the next allowed session, MIG-008.
- `2026-06-07T16:07:22Z` - phase: graph refresh completed; command/result: `graphify update .` completed after code/doc changes, rebuilding `graphify-out` with `92391` nodes, `162847` edges, and `4057` communities; decision/blocker: no graph update blocker; next action: continue pipeline with MIG-008.

## Closure Progress

- `2026-06-07T16:04:14Z` - role: local QA/closure reviewer; files inspected: MIG-007 transfer model/crypto/checkpoint/service, `/migration/` route hook, MIG-007 tests, direct/gate output, source proposal evidence, and breakdown ledger; findings: one validation gap was found and fixed before closure (`segmentIndexMismatch` plus position-based non-final length checks), with regression coverage added; remaining findings/blockers: none inside MIG-007 scope.
- `2026-06-07T16:04:14Z` - accepted differences: host/direct tests and the single-device transport gate close this implementation seam; physical paired same-WiFi iOS-to-iOS migration, full bundle exporter/importer consumption, durable cutover, old-phone runtime shutdown, pending-work ownership, user journey UI, wake-lock behavior, MIG-006 remaining group evidence, and final release acceptance remain later sessions.
- `2026-06-07T16:07:22Z` - graph maintenance: `graphify update .` completed after the MIG-007 code/doc changes.

## Session Verdict

MIG-007 is closed for its own session scope.

The overall Move Account doc remains `still_open`: MIG-006 is deliberately deferred-last/evidence-gated with commands 29-123 plus final verification still required, and MIG-008 through MIG-012 remain pending. Do not treat this MIG-007 verdict as final program acceptance.
