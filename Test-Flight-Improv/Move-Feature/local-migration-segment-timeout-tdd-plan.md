Status: implemented (host-proven; simulator/device gates evidence-gated)

# Move Account Local Segment Timeout TDD Plan

## Planning Progress

- 2026-06-10 14:55 CEST - role: Executor completed TDD implementation. RED tests added first (13 runtime, 6 bundle-receiver, 4 segment-crypto, 5 journey) and proven failing, then implemented: typed `localTransferTimedOut`/`transferTimedOut` classification across all six `_postJson` call paths with phase attribution (connect/bodyWrite/closeAwaitResponse/responseBodyDrain) and payload/manifest-scaled command budgets (`transferBytesPerSecondFloor`, `maxCommandTimeout`); source `POST_START/RESPONSE/FAILED` + `SEGMENT_PROGRESS` telemetry incl. old-block-proof `authorityRisk`; receiver `REQUEST_START/REJECTED/DONE/FAILED` + per-command accepted/rejected telemetry with body-read/decode/accept/write timing and runtime-tracked `verifiedCount`; receiver `complete()`/`acceptOldBlockProof()` stage telemetry replacing silent `on Object` swallows; dedicated `ACCOUNT_MIGRATION_SEGMENT_DECRYPT_*` events (generic MLKEM events confirmed non-correlatable — correlationId is bridge-internal); new non-terminal `receivingSegment`/`importingBundle` receiver events mounting `AccountMigrationProgressWakeLock` before `importVerified` with monotonic stage guards; `ACCOUNT_MIGRATION_TRANSFER_FAILED` enriched with failureCode/sessionId/stage. local_ws_server.dart unchanged (plan test 8 not needed). Evidence: 183 host tests green ×2 (`test/features/account_migration/`), discovery + completeness + runtime-telemetry gates PASS, `git diff --check` clean, graphify updated, simulator target `integration_test/account_migration_local_transfer_timeout_simulator_test.dart` classified (group scope) and analyze-clean. Evidence-gated remainder: reliability-sim run of the new simulator target and the device transport gate (no simulator/device executed this session).

- 2026-06-10 12:41 CEST - role: Arbiter completed amendment review. Files inspected since last update: receiver event model, wake-lock wrapper, wired receiver event handling, `_postJson` call-site count, segment crypto bridge path, and current plan. Decision/blocker: include narrow receiver wake-lock/progress mounting, all `_postJson` call paths, C3 async-ack stop rule, and ML-KEM decrypt correlation check; keep platform background service and protocol redesign out of this session. Next action: execute this revised plan with TDD.
- 2026-06-10 12:39 CEST - role: Reviewer completed amendment review. Files inspected since last update: proposed four amendments, `account_migration_transfer_flow.dart`, `account_migration_journey_wired.dart`, `account_migration_journey_screen.dart`, `migration_segment_crypto.dart`, and `bridge.dart`. Decision/blocker: points 1/3/4 add value if bounded; point 2 is already mostly covered but should mention all six `_postJson` call paths. Next action: Arbiter classification.
- 2026-06-10 12:37 CEST - role: Evidence Collector completed amendment review. Files inspected since last update: graphify scoped query, receiver progress event types, wake-lock mounting condition, and `_postJson` direct call sites. Decision/blocker: current receiver emits only importVerified/activated/failed, so there is no receiver-side progress stage before import completion. Next action: patch plan.
- 2026-06-10 12:36 CEST - role: Arbiter completed relay-free audit review. Files inspected since last update: `03-relay-free-move-gap-audit.md`, local transfer complete/old-block-proof code, receiver `complete()`/`acceptOldBlockProof()` catches, wake-lock placement, active importer loop, and current plan. Decision/blocker: no structural blocker; add command-wide `_postJson` and receiver completion/proof telemetry coverage, keep memory/quiesce/cutover/media hard-blockers as separate workstreams. Next action: execute this revised plan with TDD.
- 2026-06-10 12:34 CEST - role: Reviewer completed relay-free audit review. Files inspected since last update: audit recommended fix order, KNOWN-2 interactions, transport establishment findings, and existing closure guard. Decision/blocker: sufficient with adjustments; a segment-only timeout fix would miss same-wrapper transcript/manifest/complete/proof failures. Next action: Arbiter classification.

## real scope

Fix the Move Account local segmented transfer failure mode where a slow or late migration segment POST can throw `TimeoutException`, bubble into the old-phone UI catch-all, and be misreported as "stopped unexpectedly before final handoff" / `bundleSourceFailed`.

This session changes only the local Move Account transfer path, its diagnostics, and its tests:

- classify local transfer timeouts/socket failures as typed transfer failures after bundle assembly, not bundle-source failures;
- make the shared `_postJson` diagnostics and exception mapping apply to every migration command, not only the segment loop: `transcript`, `manifest`, `segment`, `complete`, and `old-block-proof`;
- add source-side per-command/per-segment transfer telemetry with enough fields to identify command, segment index, total segment count, bytes, post subphase, elapsed time, status code, and timeout/socket failure phase;
- add receiver-side request/manifest/segment/complete/old-block-proof telemetry with body-read timing, decode/accept/write-response timing, segment index, accepted/rejected reason, verified count, and handler timeout outcome;
- add a narrow new-phone receiver progress event/state so receiving segments or import work mounts the existing `AccountMigrationProgressWakeLock` from receiver start/first segment progress until terminal receiver state;
- harden transfer behavior narrowly so a normal 8-9 MB / 34 segment bundle is not aborted by one segment whose receiver work completes slightly after the current 10s budget.

This session does not redesign account migration, does not change QR pairing, does not change bundle payload format unless a red test proves telemetry-only and timeout handling are insufficient, and does not touch the earlier group-media local-durability fix except as regression coverage.
This session also does not solve the broad relay-free audit findings around monolithic bundle memory use, old-phone quiesce, cutover recovery, persistent plaintext residue, platform background services, or manifest hard-blockers.

## closure bar

The fix is good enough when a slow segment response or other local migration command timeout no longer escapes as an untyped exception or `bundleSourceFailed`, and the logs can pinpoint the exact transfer command/segment/phase that failed or succeeded.

Coverage ledger:

| Required behavior from finding | Planned proof |
| --- | --- |
| Pixel bundle assembly succeeds before failure | Existing/source telemetry remains `ACCOUNT_MIGRATION_BUNDLE_SOURCE_BUILT`; new tests assert transfer timeout happens after this and is not classified as bundle source. |
| Transfer failure is mid-segment, not final handoff | New direct runtime test delays a receiver segment beyond the old budget and asserts result code/safe message identify local transfer timeout before `checking`/`finishing`. |
| Exact segment/await is currently unknown | Per-segment tests and telemetry must record every segment POST start/outcome and the `_postJson` subphase (`connect`, `bodyWrite`, `closeAwaitResponse`, `responseBodyDrain`, or equivalent). Tests must not assume segment 0 unless telemetry proves it. |
| Shared `_postJson` failures are not segment-only | Add command-stage tests for transcript/connect failure, complete timeout, and old-block-proof timeout so none escape to the UI catch or get mislabeled `bundleSourceFailed`. |
| All `_postJson` call paths are covered | Tests must cover the six direct call paths: transcript, manifest, plaintext-segment sender path, prepared-segment sender path, complete, and old-block-proof. |
| Missing iPhone receiver visibility | New receiver telemetry tests assert request start/done, manifest accepted, segment accepted/rejected, verified count, body bytes, elapsed ms, and response outcome events. |
| Receiver can sleep before importVerified | Add a receiver progress event/state that moves the new-phone UI into a non-terminal progress stage during segment receive/import, and a widget test proving the existing wake-lock wrapper mounts before terminal receiver events. |
| Receiver completion/proof errors are currently black boxes | Add receiver tests that `complete()` and `acceptOldBlockProof()` failures emit sanitized reason/error/stage telemetry before returning failure/null. |
| Existing ML-KEM decrypt logs need correlation | Implementation must verify whether `MigrationSegmentCrypto.decryptSegment -> callDecryptMessage` produces the `MLKEM_FL_BRIDGE_DECRYPT_*` events seen in `iphone-13.log`; if yes, correlate them with segment telemetry, and if not, add dedicated migration segment decrypt telemetry. |
| Receiver handler can be a hidden hang site | Receiver tests must prove body-read, decode, `acceptSegment`, and response-write telemetry; if `LocalWsServer` migration-handler tracking/deadline changes, add a direct `LocalWsServer` test and prove media routes are unaffected. |
| Need to diagnose future blind spots | New telemetry contract includes command, sessionId, bundleId where available, segmentIndex, segmentCount, payloadBytes/bodyBytes, phase, elapsedMs, statusCode/reason, peer host/port redaction policy, and timeout/socket error type. |
| Normal Pixel-sized transfer should not regress | Add a deterministic host proof for at least 34 logical segments with one near-budget receiver delay, using injected short timeouts/delays rather than long real sleeps; simulator/device closure must prove the normal large-transfer success path. |
| Avoid over-broad product change | Existing bundle format, import/cutover semantics, relay-free policy, and group-media durability behavior remain unchanged. |
| Multi-device local-transfer timing confidence | Add or extend a reliability simulator scenario for account migration local transfer large/slow bundle and require `$run-flutter-reliability-sims` group/target closure. |

## source of truth

- `pixel.log` and `iphone-13.log` from the failed manual run are the reproduction evidence.
- `Test-Flight-Improv/Move-Feature/move-transfer-timeout-before-handoff-triage.md` is accepted as secondary triage evidence only where it is backed by code/log facts. Its defensible claim is "segment phase after manifest, before checking"; its "first segment" and sender-vs-receiver stall explanations remain hypotheses until telemetry proves them.
- `Test-Flight-Improv/Move-Feature/03-relay-free-move-gap-audit.md` is accepted only for overlap with this timeout plan: command-wide `_postJson` blackout, receiver `complete()`/`acceptOldBlockProof()` exception blackout, and receiver wake/suspension risk as a separate suspected contributor. Its memory, quiesce, cutover, cleanup, and manifest-blocker findings require separate plans.
- Current code and tests win over older MIG prose if they disagree.
- `Test-Flight-Improv/test-gate-definitions.md` is the source of truth for named host/device gates.
- `scripts/check_reliability_simulation_discovery.sh` is the source of truth for whether new integration targets are discoverable by reliability simulator gates.
- Existing account migration direct tests under `test/features/account_migration/application/` define current host-side transfer contracts.

## session classification

implementation-ready

Simulator-backed closure is required before calling the device behavior closed. If simulators/devices are unavailable, classify execution as evidence-gated rather than complete.

## exact problem statement

Manual Pixel -> iPhone-13 Move Account failed after Pixel built a valid bundle with all chat media. Pixel logged `ACCOUNT_MIGRATION_BUNDLE_SOURCE_BUILT` with `segmentCount:34` and then entered `transferringDatabase`. The `checking` stage was never logged, so the failure localizes to segment transfer between manifest acceptance and complete verification. iPhone logged only receiver start plus generic ML-KEM decrypts; only 24 decrypts were visible. Pixel then logged `ACCOUNT_MIGRATION_TRANSFER_ERROR` with `TimeoutException` and `reason:"bundleSourceFailed"`.

The exact timed-out segment and exact await site are not known from current logs. The 38.855s gap must not be treated as "four stacked timeouts" or proof that segment 0 failed; several segments may have succeeded before one hung, or an uninstrumented sender/receiver path may have consumed most of the wall time.

Broken behavior:

- local segment transfer timeout escapes the transfer runner instead of returning a typed result;
- UI reports a final-handoff-style catch-all even though final handoff never started;
- logs do not identify the stuck command, segment index, body read, receiver accept, response write, or verified count.
- logs do not identify whether the stall was sender connect/body flush/response read, receiver body drain/decrypt/write, or server handler dispatch.
- the same `_postJson` exception path can misclassify transcript, manifest, complete, and old-block-proof failures unless the wrapper is fixed at the shared command layer.
- receiver `complete()` and `acceptOldBlockProof()` currently fail closed without enough telemetry to diagnose payload decode, secure staging, staged DB open, active DB import, secure promotion, or cutover proof failures.
- the new phone does not currently receive a progress stage during segment receive, so the existing wake-lock wrapper does not mount until `importVerified`; this leaves a plausible sleep/suspension gap during the actual receive window.

User-visible improvement:

- failed transfers should tell the user the local transfer stalled and to keep both phones open/on same Wi-Fi, not imply final handoff or old-phone bundle assembly failure;
- TestFlight logs should be sufficient to tell whether future failures are source connect, manifest reject, segment N timeout, receiver decrypt/write, complete/import, or cutover.

Must stay unchanged:

- Move Account remains relay-free;
- bundle source does not fetch missing media from relay;
- import writes only bundle-provided media;
- cutover authority semantics remain MIG-008/MIG-009 behavior.

## files and repos to inspect next

Production:

- `lib/features/account_migration/application/account_migration_local_transfer_runtime.dart`
- `lib/features/account_migration/application/account_migration_transfer_flow.dart`
- `lib/features/account_migration/application/account_migration_bundle_transfer.dart`
- `lib/features/account_migration/application/migration_segmented_transfer_service.dart`
- `lib/features/account_migration/presentation/screens/account_migration_journey_wired.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/bonsoir_discovery_service.dart` only if fresh evidence shows stale mDNS peer/port caused the timeout
- `lib/core/utils/flow_event_emitter.dart` only if telemetry shape needs helper support

Tests/docs:

- `test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart`
- `test/features/account_migration/application/migration_segmented_transfer_service_test.dart`
- `test/features/account_migration/presentation/account_migration_journey_screen_test.dart`
- `test/features/account_migration/presentation/account_migration_journey_wired_test.dart` or the existing journey screen test if it already exercises receiver events/wake-lock mounting
- `test/core/local_discovery/local_ws_server_test.dart` if migration-handler tracking/deadline behavior changes
- `integration_test/account_migration_group_media_durability_simulator_test.dart` or a new `integration_test/account_migration_local_transfer_timeout_simulator_test.dart`
- `scripts/check_reliability_simulation_discovery.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/codebase-test-inventory.md`

## existing tests covering this area

- `account_migration_local_transfer_runtime_test.dart` covers local route pairing, exporter gap, bundle source exception classification, manifest/segment happy path, pre-encrypted segment happy path, cutover proof exchange, no-cutover receiver rejection, and transcript mismatch.
- `migration_transfer_manifest_test.dart`, `migration_segment_crypto_test.dart`, `migration_transfer_checkpoint_store_test.dart`, and `migration_segmented_transfer_service_test.dart` carry MIG-007 manifest/crypto/checkpoint transfer proof.
- `account_migration_bundle_transfer_test.dart` covers production source/receiver payload/import/media behavior.
- `account_migration_journey_screen_test.dart` covers host-side presentation progress/error copy, but does not prove real local transfer timing.
- Existing simulator `integration_test/account_migration_group_media_durability_simulator_test.dart` proves group media durability and bundleability, not slow local segment transfer.

Missing:

- no test for a slow receiver segment causing old-phone HTTP timeout;
- no test that timeout becomes `transferRejected`/local-transfer-stalled instead of UI catch-all;
- no test for per-segment telemetry emitted on source and receiver;
- no test for `_postJson` phase attribution such as connect timeout, request close/response-header timeout, or response-body-drain timeout;
- no test that transcript, manifest, complete, and old-block-proof `_postJson` exceptions are typed by command/stage instead of routed through the bundle-source catch-all;
- no test for receiver body-drain/decode/accept/write-response telemetry or migration-handler deadline behavior;
- no test that receiver segment progress drives a new-phone progress stage and mounts the existing wake-lock wrapper before `importVerified`;
- no receiver-side test that `complete()` and `acceptOldBlockProof()` catch blocks emit sanitized diagnostic telemetry;
- no verification that generic `MLKEM_FL_BRIDGE_DECRYPT_*` events can be attributed to migration segment decrypts, or a migration-specific substitute if they cannot;
- no simulator scenario for large/slow Move Account local transfer.

## regression/tests to add first

Add these RED tests before implementation:

1. `account_migration_local_transfer_runtime_test.dart`: slow segment response is typed.
   - Arrange a receiver whose `acceptSegment` intentionally delays longer than a short injected `httpTimeout`.
   - Assert `runOldPhoneTransfer` returns a failure result instead of throwing.
   - Assert failure code is transfer-local, safe message says local transfer stalled/timed out, and no `ACCOUNT_MIGRATION_TRANSFER_BUNDLE_SOURCE_FAILED` event is emitted.

2. `account_migration_local_transfer_runtime_test.dart`: source telemetry pinpoints timeout phase.
   - Capture flow events.
   - Assert events include source POST start and failure with `command:"segment"`, `segmentIndex`, `segmentCount`, `phase`/`timeoutPhase` (`connect`, `bodyWrite`, `closeAwaitResponse`, `responseBodyDrain`, or equivalent), `elapsedMs`, `errorType:"TimeoutException"`, and `reason:"timeout"`.
   - Add at least one fake-server mode that delays response headers/body long enough to prove phase attribution without relying on the full device stack.

3. `account_migration_local_transfer_runtime_test.dart`: receiver telemetry pinpoints progress.
   - For successful multi-segment transfer, assert receiver emits manifest accepted, segment accepted for each index, verified count increments, and complete/import verified event.
   - For rejected/late segment, assert receiver emits rejected/failed reason without sensitive ciphertext.
   - Assert body-read/decode/accept/write-response start and done/failure timing are observable for segment commands.

4. `account_migration_journey_screen_test.dart`: UI does not show final-handoff catch-all for typed transfer timeout.
   - Inject a runner returning the new typed transfer timeout result.
   - Assert the failure copy is local-transfer-specific and `ACCOUNT_MIGRATION_TRANSFER_FAILED` reason is typed.

5. Receiver progress/wake-lock widget test.
   - Add a receiver progress event such as `receivingSegment` or `importingBundle` carrying `sessionId`, `segmentIndex`, `segmentCount`, and `verifiedCount` when available.
   - Inject receiver events into the new-phone journey and assert the UI enters a non-terminal progress stage, causing `AccountMigrationProgressWakeLock` to mount before `importVerified`.
   - Assert terminal receiver events release/stop the progress path as today.

6. Simulator target:
   - Add or extend an integration test that creates a large enough migration bundle and injects deterministic local receiver delay/large payload pressure.
   - Assert transfer either succeeds with the new budget/backpressure behavior or fails typed with full segment diagnostics; closure preference is success for the Pixel -> iPhone-sized bundle.

7. Large logical-segment host proof:
   - Use small deterministic segment size or generated payload fixtures to produce at least 34 logical segments without slow wall-clock sleeps.
   - Assert the normal near-budget case succeeds and emits monotonically increasing segment progress telemetry.

8. `local_ws_server_test.dart` if server handler tracking/deadline behavior changes:
   - Arrange a `/migration/` handler that never completes or deliberately exceeds a short injected deadline.
   - Assert migration request timeout/failed telemetry is emitted and existing `/media/` local upload behavior is unchanged.

9. `account_migration_local_transfer_runtime_test.dart`: command-wide `_postJson` exceptions are typed.
   - Arrange deterministic failures for transcript/connect, manifest, both segment sender paths, complete, and old-block-proof commands using short injected timeouts or a fake server.
   - Assert each returns a stage-appropriate failure result with command/stage telemetry, not an uncaught exception and not `bundleSourceFailed`.
   - For old-block-proof timeout, assert telemetry makes the post-`markOldNetworkBlocked` authority risk explicit; cutover recovery itself remains a separate plan.

10. `account_migration_bundle_transfer_test.dart`: receiver completion/proof exceptions are diagnosable.
   - Force `complete()` failures in payload decode/secure staging/staged DB open/import-file setup and assert sanitized telemetry with `stage:"complete"` or equivalent.
   - Force `acceptOldBlockProof()` failures in active DB import, secure promotion, and new-active commit and assert sanitized telemetry with `stage:"oldBlockProof"` or equivalent.

11. Segment decrypt-log correlation check.
   - Verify in code or a focused test whether migration `acceptSegment` decrypts produce the existing `MLKEM_FL_BRIDGE_DECRYPT_REQUEST/RESPONSE` events.
   - If they do, ensure new segment telemetry has enough correlation fields and timing to compare bridge decrypt count with accepted segment count.
   - If they do not, add dedicated `ACCOUNT_MIGRATION_RECEIVER_SEGMENT_DECRYPT_*` telemetry around migration segment decrypt.

## step-by-step implementation plan

1. Add a transfer-local failure classification without changing bundle assembly.
   - Prefer explicit new failure codes: `AccountMigrationTransferFailureCode.localTransferTimedOut` for presentation/error reporting and `MigrationTransferResultCode.transferTimedOut` for runtime result mapping.
   - Reuse an existing code only if implementation discovers a concrete enum compatibility constraint; if reused, record it as an accepted difference and keep `safeMessage`, telemetry `reason`, and UI copy transfer-timeout-specific.
   - Catch `TimeoutException`, `SocketException`, and `HttpException` around `_postJson` calls in transcript, manifest, segment, complete, and old-block-proof paths and convert to typed command/stage results where possible.
   - Keep old-block-proof timeout handling diagnostic/typed only in this plan; do not silently mark the old phone migrated-out or attempt full cutover recovery here.

2. Add source-side transfer operation telemetry.
   - Add events such as `ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START`, `...POST_RESPONSE`, `...POST_FAILED`, and `...SEGMENT_PROGRESS`.
   - Include: `sessionId`, `command`, `segmentIndex` when applicable, `segmentCount`, `bundleId`, `payloadBytes`/encoded JSON bytes, `elapsedMs`, `phase`, `timeoutPhase`, `statusCode`, `reason`, `errorType`, `hostKind`/`port` if safe, and `httpTimeoutMs`/overall deadline.
   - Distinguish `_postJson` substeps enough to separate connect failure, body encode/write duration, `request.close()`/response-header wait, and response-body drain.
   - Include `commandStage` or equivalent for transcript pairing, manifest acceptance, segment transfer, complete verification, and old-block-proof cutover.
   - Do not log ciphertext, keys, nonce bodies, peer IDs, DB bytes, or file contents.

3. Add receiver-side request telemetry.
   - In `handleMigrationTransferRequest` and handlers, emit request start/parsed/session-found and request done/failure.
   - In `_handleManifest`, `_handleSegment`, `_handleComplete`, and `_handleOldBlockProof`, emit accepted/rejected events with reason and counts.
   - Track `verifiedIndexes.length` on `_ReceiverSession` for segment progress telemetry.
   - Add guarded telemetry around `_readJsonMap`, segment decode, `acceptSegment`, and `_writeJson` timing.
   - Add sanitized telemetry inside `bundleReceiver.complete()` and `bundleReceiver.acceptOldBlockProof()` catch paths so receiver-side payload decode, staging, active import, promotion, and cutover-proof errors are visible.
   - Emit receiver progress events during segment acceptance/decrypt/write and import verification so the new phone has non-terminal progress before `importVerified`.
   - Correlate segment decrypt timing with existing `MLKEM_FL_BRIDGE_DECRYPT_*` events if those events are confirmed to come from `callDecryptMessage` in migration segment decrypt.
   - If `local_ws_server.dart` needs to await/track migration handler futures or enforce a server-side request deadline, keep that change scoped to `/migration/` and prove `/media/` routes still behave as before.

4. Wire narrow receiver wake/progress behavior.
   - Extend `AccountMigrationReceiverEventType` with a non-terminal progress event, or map receiver-side segment/import progress into an existing non-terminal `AccountMigrationProgressStage`.
   - The new-phone screen should mount `AccountMigrationProgressWakeLock` from receiver start or first receiver progress through terminal `activated`/`failed`/cancel/stop.
   - Keep this to the existing foreground wake-lock path. Do not add iOS background-task, Android foreground-service, or platform lifecycle redesign in this session.

5. Harden transfer timing narrowly.
   - Avoid one new `HttpClient` per segment if tests show that contributes to delay; otherwise leave transport architecture intact.
   - Prefer a bounded per-POST deadline or explicitly named phase deadlines for migration transfer; do not leave logs implying that one wall-clock gap is explained by stacked independent timeouts.
   - Increase or split timeout budgets by phase only for migration transfer, e.g. connect timeout remains short but request/response timeout scales with payload/segment size or uses a larger migration segment budget.
   - For complete/import and old-block-proof, do not solve repeated size-scaling failures by only raising the timeout. If telemetry proves O(account) import work exceeds the request budget, stop and split a follow-up for async acknowledgement (`202` + poll/push status) or streaming import; a bounded manifest-size-scaled budget is acceptable only as an interim, tested behavior with import-progress telemetry.
   - Do not pretend synchronous `request.write` has an awaitable timeout; if implementation replaces it with streamed writes for backpressure, add a direct test for streaming timeout/cancellation and keep the payload format unchanged.
   - Do not add retry by default. If a RED test proves retry is necessary, allow at most a bounded same-segment retry with idempotency proof for duplicate/late segment arrival.
   - Keep tests deterministic by injecting short timeout/delay values; do not add real 10-30 second sleeps to host tests.
   - Do not add relay/cloud fallback or change bundle payload schema unless the red tests prove the current POST/JSON shape cannot meet the closure bar.

6. Fix UI classification.
   - Ensure typed transfer failures flow through normal result handling, not the catch block.
   - Reserve `"The account move stopped unexpectedly before final handoff."` for truly unexpected exceptions.
   - Add event details to `ACCOUNT_MIGRATION_TRANSFER_FAILED` such as `failureCode`, `stage`, and optional `transferReason`.

7. Add/extend simulator coverage.
   - Prefer a new focused `integration_test/account_migration_local_transfer_timeout_simulator_test.dart`.
   - Add it to `scripts/check_reliability_simulation_discovery.sh` under the narrowest appropriate scope and update `Test-Flight-Improv/test-gate-definitions.md` if gate docs enumerate the target list.
   - Because this is local transfer/multi-device behavior, use reliability-sim closure even if the test internally uses deterministic fakes.

8. Update docs only after implementation/tests pass.
   - Update `Test-Flight-Improv/codebase-test-inventory.md` account migration count/description.
   - Update `Test-Flight-Improv/test-gate-definitions.md` if a new direct or simulator target is added.

Stop early if the first RED test proves the timeout is caused by a stale mDNS peer/port rather than segment processing. In that case, switch the implementation to stale peer/port resolution diagnostics and keep segment telemetry only as necessary to prove no mid-transfer stall.

Stop and split a new plan if RED tests show the dominant failure is monolithic source/receiver bundle memory, old-phone quiesce/data loss, cutover recovery, or manifest hard-block reconciliation. Those are real relay-free readiness blockers from the audit, but they are not safe to fold into this timeout session.
Stop and split a new plan if complete/import telemetry shows request/response is the wrong shape for O(account) import work. The follow-up should be async ack/poll or streaming import, not just a larger timeout.

## risks and edge cases

- Receiver accepts a segment after the old phone has timed out; retry must not corrupt verified segment state.
- If a retry is introduced, duplicate or late arrival of the same segment must be idempotent and explicitly tested.
- Complete/import might be the slow phase after all segments, so telemetry must distinguish segment transfer from complete verification/import.
- Complete and old-block-proof can exceed the current timeout for larger accounts; this plan may classify and diagnose that safely, but async `202`/polling or streaming import is the follow-up if telemetry proves O(account) work is exceeding request budgets.
- Increasing timeouts blindly could hide a dead receiver; prefer typed phase telemetry plus bounded budgets.
- Receiver sleep/suspension can look like a transfer timeout; use the existing foreground wake-lock via receiver progress in this plan, but keep platform background-task/foreground-service work as a separate follow-up.
- Fire-and-forget server handler dispatch can hide receiver stalls; any `/migration/` timeout/tracking change must not disturb local media upload routes.
- Stale mDNS records can point old phone at an old iPhone port; do not change discovery unless evidence points there.
- Multiple receiver sessions or retry after failure must not reuse stale `_ReceiverSession` verified indexes incorrectly.
- Sensitive logs must not leak ciphertext, keys, raw QR payloads, DB contents, media paths beyond already-sanitized relative path policy, or peer IDs.
- Existing cutover safety must not regress: old phone must not mark migrated-out unless new active proof is accepted.

## exact tests and gates to run

Direct RED/GREEN tests:

```bash
flutter test test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart
flutter test test/features/account_migration/application/migration_segmented_transfer_service_test.dart
flutter test test/features/account_migration/application/account_migration_bundle_transfer_test.dart
flutter test test/features/account_migration/presentation/account_migration_journey_screen_test.dart
flutter test test/features/account_migration/presentation/account_migration_journey_wired_test.dart
```

If `LocalWsServer` migration-handler tracking or deadlines change:

```bash
flutter test test/core/local_discovery/local_ws_server_test.dart
```

Telemetry/gate docs:

```bash
./scripts/run_test_gates.sh runtime-telemetry
./scripts/run_test_gates.sh completeness-check
./scripts/check_reliability_simulation_discovery.sh
git diff --check
```

Transport named gate because local transfer/WS/discovery behavior changes:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

Reliability simulator closure, required before full closure:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --repo /Users/I560101/Project-Sat/mknoon-2/flutter_app --only integration_test/account_migration_local_transfer_timeout_simulator_test.dart
```

If the implementation extends the existing simulator instead of adding a new file, run:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --repo /Users/I560101/Project-Sat/mknoon-2/flutter_app --only integration_test/account_migration_group_media_durability_simulator_test.dart
```

After code changes:

```bash
graphify update .
```

## known-failure interpretation

- Existing dirty worktree is expected; do not revert unrelated user/agent changes.
- SQLCipher device capability issues from earlier MIG-004 work are not this session's failure unless the new/extended simulator directly opens production SQLCipher on device and fails for the same plugin-registration reason.
- Android generated binding/NDK caveats from earlier MIG-008 docs are not this session's blocker unless Android-specific transfer code is changed.
- Push token registration failures in iPhone logs are noise for this bug unless new evidence ties them to local transfer receiver stop.
- Go `netlinkrib: permission denied` logs are existing Android noise for this run unless transport gate introduces a direct regression.
- Do not interpret the 38.855s blackout as proof of stacked timeouts or proof that segment 0 failed. Current evidence proves segment phase after manifest and before checking; exact segment and await site require new telemetry.
- The broad relay-free audit is static analysis. Treat its memory ceilings, 100-300 MB timeout threshold, and multi-hour throughput estimates as serious planning inputs, not as measured failures for this timeout plan.

## done criteria

- RED tests are added first and fail for the current behavior.
- Implementation makes the RED tests pass without broadening product scope.
- Source-side telemetry identifies command, segment index/count, bundle/session, body size, elapsed time, timeout/socket phase, and status/reason.
- Source-side telemetry distinguishes connect, body encode/write, `request.close()`/response-header wait, and response-body drain closely enough to diagnose the next timeout.
- Receiver-side telemetry identifies manifest/segment/complete acceptance, body-read/decode/accept/write-response timing, rejected reason, verified count, and response outcome.
- Receiver segment/import progress drives a non-terminal new-phone progress stage and mounts the existing foreground wake lock before `importVerified`.
- Transcript, manifest, complete, and old-block-proof `_postJson` failures are typed by command/stage and no longer fall through as `bundleSourceFailed`.
- Both segment `_postJson` sender paths are covered by typed timeout tests and telemetry.
- Receiver `complete()` and `acceptOldBlockProof()` catch paths emit sanitized diagnostic telemetry before returning failure/null.
- Migration segment decrypt telemetry is either correlated with existing `MLKEM_FL_BRIDGE_DECRYPT_*` events or covered by dedicated migration segment decrypt events.
- If `/migration/` handler tracking/deadlines change, direct `LocalWsServer` tests prove timeout telemetry and unchanged `/media/` behavior.
- A slow segment does not throw through to the UI catch-all and is not labeled `bundleSourceFailed`.
- A deterministic host test proves at least 34 logical segments can complete with a near-budget segment delay and monotonic progress telemetry.
- Any new or extended simulator target is discoverable by `scripts/check_reliability_simulation_discovery.sh`.
- For a Pixel -> iPhone-sized bundle, simulator/device proof either succeeds or, if intentionally forced to fail, produces complete typed diagnostics; full closure requires the success path for normal large transfer.
- Required direct tests, named gates, simulator command, `git diff --check`, and `graphify update .` complete or any blocker is recorded as evidence-gated.

## scope guard

Do not:

- fetch migration media from relay;
- change QR pairing/auth transcript semantics;
- change cutover authority states or migrated-out network gates;
- replace the whole local transfer protocol with a new architecture unless the RED tests prove the current bounded change cannot work;
- change chat media local `/media/<id>` transfer behavior;
- add broad retry/resume/product UX flows beyond typed failure and diagnostics;
- add segment retry unless a RED test proves it is required and duplicate/late segment idempotency is covered;
- implement streaming bundle assembly/import, `202` polling, platform receiver background service, old-phone quiesce, cutover recovery, secret cleanup, or manifest hard-block reconciliation in this session;
- solve stale mDNS globally unless this investigation produces direct proof that stale peer resolution is the cause.

Overengineering in this session includes building a general streaming framework, adding cloud fallback, adding encrypted archive formats, or refactoring unrelated transport code just to share telemetry helpers.

## reviewer findings

Verdict: sufficient with adjustments.

- Missing/weak items found: the first draft allowed reusing `transferRejected` too casually, referenced a new simulator path without requiring discovery-script/docs updates, and did not require a deterministic 34-segment host proof.
- Adjustments made: typed timeout failure is now the default plan, simulator discoverability is explicit, the closure bar includes 34 logical segments, and host tests must use injected short delays instead of long sleeps.
- Stale assumptions: none found. Current code/test evidence still points to local segment POST/response timeout after bundle source success, not relay, media durability, import, or final handoff.
- Overengineering check: plan remains bounded to local transfer classification, telemetry, and timing; no relay fallback, protocol replacement, or global discovery rewrite is planned unless a RED test proves stale peer resolution.
- Minimum to implement safely: add the RED tests first, keep all telemetry sanitized, run direct tests plus the named telemetry/completeness/transport gates and the reliability simulator target.

## arbiter decision

Structural blockers remaining: none.

Incremental details intentionally deferred:

- The exact final enum names may differ if the implementation discovers a compile-time compatibility constraint, but the behavior must remain typed as local transfer timeout in result, telemetry, and UI copy.
- Whether to create a new simulator file or extend the existing group media durability simulator is left to implementation; either path must be discoverable by `scripts/check_reliability_simulation_discovery.sh` and runnable through `$run-flutter-reliability-sims`.

Accepted differences:

- This plan does not fix group media file disappearance before migration; it only preserves that finding through regression coverage and avoids confusing it with local transfer failure.
- This plan does not redesign the segmented transfer protocol. It adds bounded timing resilience and diagnostics to the existing route unless RED tests prove the current POST path cannot meet the closure bar.

Final verdict: execution-ready. The plan has a scoped problem statement, regression-first tests, simulator-backed closure, telemetry fields for remaining blind spots, and an explicit stop rule against relay/media/cutover scope drift.

## triage report review findings

Valuable findings added to this plan:

- The report correctly tightens localization to the segment-send window after manifest success and before `checking`.
- It usefully calls out the lack of `_postJson` subphase attribution and the receiver-side body-read/accept/write-response blind spot.
- It identifies `local_ws_server.dart` fire-and-forget migration handler dispatch as a plausible hidden stall site that should be tested if changed.
- It corrects the 38.855s arithmetic: current evidence does not prove stacked timeouts, a specific await, or segment 0.

Findings treated as hypotheses, not implementation scope:

- Sender large-body flush/backpressure, receiver decrypt/write stall, and Wi-Fi/interface instability remain plausible but unproven until new telemetry or packet evidence exists.
- Keep-alive reuse, streaming writes, and retries are not default fixes. They are allowed only behind RED tests and the scope guard above.

## relay-free gap audit review findings

Valuable findings added to this plan:

- The audit correctly warns that `_postJson` timeout/mislabeling is command-wide, not only segment-loop behavior. The plan now requires transcript, manifest, segment, complete, and old-block-proof command-stage coverage.
- The audit identifies receiver `complete()` and `acceptOldBlockProof()` catch blocks as diagnosability black holes. The plan now requires sanitized receiver-side telemetry for those paths.
- The audit's receiver wake/suspension concern is recorded as a risk and simulator interpretation point, but not as default scope because the failed manual run still localized to segment phase and receiver activity was visible near the sender error.

Findings accepted as valuable but intentionally left out of this timeout plan:

- Monolithic source/receiver bundle memory, async complete/proof protocol redesign, old-phone quiesce, cutover recovery, plaintext/staging cleanup, media/post/avatar hard-block reconciliation, dual-stack discovery, and cryptographic channel binding all need separate plans.
- The current plan must not be used as a relay-free readiness signoff. It closes the local transfer timeout diagnostics/classification slice only.

## amendment review findings

Included:

- Receiver wake lock/progress: include the narrow version. Add receiver progress events and mount the existing foreground `AccountMigrationProgressWakeLock` during segment receive/import. Do not include platform background tasks or foreground services here.
- All `_postJson` call paths: already mostly covered; tightened the plan to cover transcript, manifest, both segment sender paths, complete, and old-block-proof.
- C3 complete/import stop rule: include. If telemetry shows complete/import exceeds request budget because of O(account) work, split async ack/poll or streaming import rather than hiding it with a larger timeout.
- ML-KEM decrypt event correlation: include as a diagnostic check. Existing `MigrationSegmentCrypto.decryptSegment` calls `callDecryptMessage`, which emits generic `MLKEM_FL_BRIDGE_DECRYPT_*`; the plan must confirm whether those events map cleanly to migration segments before treating 24/34 as proof.

Not included:

- iOS background task / Android foreground service work remains a separate follow-up because it crosses into platform lifecycle behavior beyond this timeout diagnostics slice.

## accepted differences / intentionally out of scope

- This plan improves Move Account local transfer reliability and observability; it does not close all Move Account TestFlight acceptance.
- The earlier group media local durability bug remains a separate plan unless regression tests fail because of this work.
- The broad relay-free gap audit remains open. This plan does not fix memory ceilings, data-loss quiesce gaps, cutover bricking/recovery, secret residue, or pre-export hard-blockers.
- Existing mDNS duplicate/stale-port risk is documented but out of scope unless a RED test points to stale peer selection as the active cause.
- Android-specific generated Go bindings are out of scope unless touched.

## dependency impact

- Later Move Account TestFlight acceptance depends on this because media durability fixes cannot help if the bundle cannot complete local transfer.
- MIG-012 relay-independent media closure should rerun after this if transfer telemetry changes audit expectations.
- The broad relay-free audit should be decomposed into separate implementation sessions before any real-sized account TestFlight run: startable/export hard-blockers, cutover recovery, old-phone quiesce, transport scalability/async complete-proof, cleanup/security, and pairing hardening.
- If this plan changes failure codes or UI copy, account migration presentation tests/docs must be updated before any release-gate evidence is trusted.
