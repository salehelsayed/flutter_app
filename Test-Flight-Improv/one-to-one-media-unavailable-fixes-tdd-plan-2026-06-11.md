# 1:1 Media Unavailable Fixes - TDD Plan

Status: execution-ready
Date: 2026-06-11
Source report: Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md

## Planning Progress

- 2026-06-11 15:16 - Evidence Collector started. Inspected debug report, graphify-arch queries, test gate definitions, and test inventory. Decision: plan must be simulator-gated because fixes touch 1:1 media delivery, relay transport, local discovery, and receiver recovery.
- 2026-06-11 15:27 - Evidence Collector completed. Confirmed the reported issues map to relay media storage, multi-relay download failover, local-WiFi media fallback, receiver orphan adoption, unavailable retry wiring, duplicate replay recovery, and thumbnail fallback.
- 2026-06-11 15:34 - Planner completed. Split the fix into five TDD sessions so each session has a narrow failing test, a contained implementation boundary, and a concrete gate.
- 2026-06-11 15:39 - Reviewer completed. Added a simulator closure requirement because unit/widget tests cannot prove the recorded-video A-to-B journey or restart/failover behavior by themselves.
- 2026-06-11 15:43 - Arbiter completed. Plan is executable as written; do not start broad architecture rewrites or group-media work while executing this plan.

## Real Scope

Fix the confirmed 1:1 media-unavailable findings from the source report:

- Relay media metadata is volatile while relay envelope state can be durable/shared.
- Multi-relay media download stops after the first reachable relay returns `not found`.
- Local-WiFi media success can skip relay upload even though the receiver only acknowledged temporary receipt.
- Receiver-side relay auto-delete can race Flutter local-path persistence and leave a valid canonical file orphaned.
- Direct 1:1 unavailable-media retry is not wired end to end.
- Duplicate envelope replay does not repair a failed or missing media attachment.
- Video thumbnail failure can visually mimic true media unavailability.

The first release target is reliable direct 1:1 image/video delivery, retry, and recovery. Group media, public posts media, and unrelated feed/media UX are out of scope unless a shared helper must be touched.

## Closure Bar

This plan is closed only when all of the following are true:

- Each listed test is added first and fails for the intended reason before implementation.
- Relay restart does not make already-uploaded 1:1 media undiscoverable.
- Client media download tries later eligible relays when one relay returns media `not found`, while still treating authorization failures as terminal.
- Local-WiFi transfer is no longer the only copy unless the receiver has a durable media-link acknowledgement.
- Receiver retry preserves or adopts an existing canonical media file instead of deleting it after a relay `not found`.
- Incoming failed/unavailable direct media exposes a retry path that actually attempts media recovery.
- Duplicate delivery of the same message can repair failed/pending media attachments without duplicating the message.
- A video thumbnail decode failure is rendered as a thumbnail/video placeholder state, not as true media unavailability.
- Host gates and the 1:1 simulator reliability gate pass, including a scenario that exercises 1:1 video or file-backed media after local/relay recovery.

## Source Of Truth

- Primary report: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`.
- Graph navigation: `graphify-arch graphify query "go-relay-server MediaStore NewMediaStore MediaDownload downloadMedia linkIncomingLocalMedia conversation_wired onRetryUnavailableMedia media unavailable tests"`.
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.
- Test inventory: `Test-Flight-Improv/codebase-test-inventory.md`.
- Production code remains authoritative over the report if source has moved since the report was written.

## Session Classification

Session A, relay media durability and relay failover: implementation-ready.

Session B, receiver local-path commit/orphan adoption: implementation-ready.

Session C, local-WiFi media durable fallback: implementation-ready with one product tradeoff. Prefer relay fallback after local transfer unless a durable receiver acknowledgement is added in the same session.

Session D, receiver retry and duplicate replay repair: implementation-ready.

Session E, video thumbnail fallback distinction: implementation-ready.

Simulator acceptance: evidence-gated until a 1:1 media scenario exists or an existing discovered scenario is extended to cover file/video media retry.

## Exact Problem Statement

The current 1:1 media path can deliver the control-plane message while losing or hiding the attachment data. The failure can happen because relay blob metadata is only process memory, because the client does not try another relay after `not found`, because local-WiFi temp receipt is treated as durable enough to skip relay upload, because a relay auto-delete can race the receiver database commit, or because receiver retry/replay UI paths do not trigger media repair. The visible symptom is a direct 1:1 media message that remains unavailable even though the sender completed the send flow.

## Files To Inspect Next

Production:

- `go-relay-server/media.go`
- `go-relay-server/main.go`
- `go-relay-server/server_bootstrap.go`
- `go-mknoon/node/media.go`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/link_incoming_local_media_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/core/media/video_thumbnail_cache.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_media_server.dart`

Tests:

- `go-relay-server/media_test.go`
- `go-mknoon/node/media_test.go`
- `go-mknoon/integration/media_test.go`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/application/link_incoming_local_media_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/shared/widgets/media/media_thumbnail_image_test.dart`
- `integration_test/media_message_journey_e2e_test.dart`

## Existing Tests Covering This Area

- `go-relay-server/media_test.go` covers upload/download, auto-delete, post-delete `not found`, unauthorized `not authorized`, peer pruning, and byte-cap pruning. It does not cover restart/index rebuild or same-ID replacement safety.
- `go-mknoon/node/media_test.go` covers upload progress, timeout behavior, and partial output cleanup. It does not cover trying a later relay after an application-level media miss.
- `go-mknoon/integration/media_test.go` covers direct relay happy path and current auto-delete behavior. It should remain green after the durability change, with expected post-delete behavior updated only if the product contract changes.
- `download_media_use_case_test.dart` covers failed bridge downloads, local-media linking during fallback, failed attachment repair when local files exist, partial retry cleanup, invalid/no-file failure, overlapping callers, and successful local-path persistence. It does not cover canonical orphan adoption after relay `not found`.
- `link_incoming_local_media_use_case_test.dart` covers pending-to-linked, unknown attachment skip, delayed row creation, failed row repair, done-row skip, and persist-failure leaving pending. It does not cover sender-side fallback after local temporary receipt.
- `letter_card_test.dart` and `media_grid_cell_test.dart` cover unavailable retry UI when a callback is supplied. They do not prove direct conversation wiring supplies the callback or that the callback starts recovery.
- Conversation presentation tests cover failed outgoing retry/delete. They do not cover incoming unavailable retry for direct 1:1 media.

## Unverified Findings Disposition Before Execution

- Stable-ID reupload truncation is promoted into Session A. The relay currently creates the final blob path before reading replacement bytes, so Session A must test same-ID incomplete replacement and use staging/rename for blob bytes as well as sidecars.
- Media cap/inbox cap mismatch is promoted into Session A for direct 1:1. The direct media count cap must not be lower than the direct inbox envelope count cap; TTL and byte-cap eviction remain explicit storage-policy residuals.
- Initial page load overwriting streamed media updates is handled in Session D. Add a focused check that a late `_loadInitialPage` result cannot replace a newer streamed media repair for the same message.
- Local media DB repair not invalidating an open direct conversation is handled in Session D through the direct retry refresh path and affected-message refresh tests.
- Non-mp4/quicktime video MIME variants are handled in Session E as a display-policy check. Defer only if no current production capture/send path can emit the variant being considered.

## Regression Tests To Add First

### Session A: Relay Durability And Failover

1. Add `TestMediaStoreSurvivesRestart` to `go-relay-server/media_test.go`.
   - Arrange a temp media dir, upload media with sender/recipient metadata, then construct a fresh `MediaStore` over the same directory.
   - Assert the recipient can download the uploaded media after the restart.
   - Assert unauthorized peers still cannot download the rebuilt media.

2. Add `TestMediaUploadSameIDIncompleteReplacementKeepsExistingBlob` to `go-relay-server/media_test.go`.
   - Arrange an existing uploaded blob, then start a second upload with the same ID that terminates before all bytes arrive.
   - Assert the original blob remains downloadable and its metadata is not replaced by the incomplete attempt.
   - This proves blob bytes are written through staging/rename, not directly through `os.Create` on the final path.

3. Add `TestDirectMediaCountCapDoesNotUndercutInboxRetention` to `go-relay-server/media_test.go`.
   - Assert the direct media count retention is at least `maxMessagesPerPeer`.
   - With byte caps raised for the test, upload enough small direct blobs to cover the direct inbox window and assert count pruning does not evict media before the corresponding envelope window.

4. Pin the relay error-string contract used by client failover.
   - Keep or extend relay-side assertions that a media miss returns exactly `not found` and authorization failure returns exactly `not authorized`.
   - If constants are introduced, update relay and client classifier tests in the same session; do not silently reword these errors.

5. Add `TestMediaDownloadTriesNextRelayOnNotFound` to `go-mknoon/node/media_test.go`.
   - Arrange two relay endpoints: the first is reachable and returns a media `not found`; the second returns the requested media bytes.
   - Assert `MediaDownload` succeeds with the second relay and writes exactly the expected bytes.
   - Add a companion assertion or table row that `not authorized` does not fall through to another relay.

6. If implementation changes the relay metadata format, add `TestMediaStoreIgnoresCorruptSidecarAndKeepsServingValidEntries`.
   - A single corrupt sidecar must not prevent the relay from starting or serving unrelated valid media.

### Session B: Receiver Commit And Orphan Adoption

1. Add `downloadMedia adopts canonical file before bridge download` to `download_media_use_case_test.dart`.
   - Arrange an incoming attachment with `localPath == null`, `status == pending` or `failed`, and an existing canonical media file with a valid hash/size.
   - Arrange the bridge download to return `not found`.
   - Assert the use case links the canonical file, marks the attachment done, and does not delete the file.

2. Add `downloadMedia does not delete pre-existing canonical file when bridge returns not found`.
   - Arrange a valid file at the target output path before the retry starts.
   - Assert failure cleanup only removes files created by this invocation.

3. Add `downloadMedia validation failure after bridge success does not delete a pre-existing canonical file`.
   - Arrange a valid canonical file before the retry starts, then make the bridge return success with bytes or metadata that fail hash/size validation.
   - Assert cleanup removes only files created by the current attempt and preserves the pre-existing canonical file for orphan adoption.
   - If no valid pre-existing file exists and relay auto-delete makes the failed validation unrecoverable, stop and re-evaluate relay delete/ack semantics instead of hiding the gap.

4. If using staging downloads, add `downloadMedia promotes staged file only after validation`.
   - Assert `.part` or staging files are not exposed as attachment `localPath` until hash/size validation passes.

### Session C: Local-WiFi Durable Fallback

1. Add `local WiFi media success still uploads relay fallback without durable receiver ack` to `conversation_wired_test.dart`.
   - Arrange direct 1:1 send where local peer discovery succeeds and local media transfer returns success.
   - Assert relay upload is still invoked, or assert the new durable receiver ACK is required before skipping relay upload.
   - Assert the outgoing message retains a relay-backed media reference for receiver retry.

2. Add `local WiFi durable ack can skip relay upload` only if a durable ACK protocol is implemented.
   - ACK must be emitted after receiver database/local-path persistence, not after temp-file receipt.
   - Assert temp receipt alone is insufficient.

3. Add a negative test around `link_incoming_local_media_use_case_test.dart`.
   - If receiver persistence fails, the sender-side flow must keep or create relay fallback instead of treating local transfer as final.

### Session D: Retry And Duplicate Replay Repair

1. Add `incoming unavailable media retry is wired for direct conversation` to `conversation_screen_test.dart`.
   - Arrange an incoming direct message with a failed media attachment.
   - Tap the unavailable retry affordance.
   - Assert the screen invokes the retry callback with message and attachment identifiers.

2. Add `direct unavailable retry downloads failed attachment` to `conversation_wired_test.dart`.
   - Arrange direct conversation state with a failed incoming attachment.
   - Invoke the retry callback.
   - Assert `DownloadMediaUseCase` runs for that attachment and the displayed message is refreshed.

3. Add duplicate replay repair coverage to `chat_message_listener_test.dart` or `handle_incoming_chat_message_use_case_test.dart`.
   - Arrange an existing message row with a failed or pending media attachment.
   - Deliver a duplicate envelope with the same message id and media descriptor.
   - Assert no duplicate message is inserted.
   - Assert media recovery is scheduled or the attachment is repaired when a valid local/canonical file is available.

4. Add `_loadInitialPage does not overwrite newer streamed media repair` to `conversation_wired_test.dart`.
   - Start an initial page load, deliver or repair a message attachment through the listener/retry path, then complete the page load with stale attachment state.
   - Assert the newer repaired attachment state remains visible and only the affected message is refreshed.

5. Add resume recovery coverage if there is already an app-resume media path.
   - Arrange failed/pending incoming direct media.
   - Trigger the existing resume handler.
   - Assert media retry is scheduled once and deduped against in-flight downloads.

### Session E: Thumbnail Failure Is Not Media Unavailable

1. Add `video thumbnail failure shows video fallback, not unavailable` to `media_grid_cell_test.dart` or `media_thumbnail_image_test.dart`.
   - Arrange a done video attachment with a valid local path and thumbnail generation failure.
   - Assert the UI shows the video fallback/play affordance and does not show unavailable-media retry.

2. Add `true failed media still shows unavailable retry`.
   - This guards against making every thumbnail failure look successful.

## Step-By-Step Implementation Plan

### Session A: Relay Media Durability And Failover

1. Write the failing Go relay restart, same-ID replacement, direct cap-alignment, and error-contract tests.
2. Add durable media metadata beside uploaded blobs in `go-relay-server/media.go`.
   - Persist sender, recipient/allowed peers, MIME/type metadata, byte size, content hash if available, expiration/delete policy, and storage path.
   - Write sidecars atomically: temp file, fsync where practical, then rename.
   - Write replacement blob bytes to a staging path first, then rename into the final blob path only after the full upload succeeds.
   - Do not replace metadata/index entries for an existing ID until the replacement blob has been fully written.
   - Load sidecars in `NewMediaStore` and rebuild `index`/`byPeer`.
   - Ignore corrupt sidecars with a clear log line; do not crash relay startup.
3. Preserve authorization behavior after rebuild and keep the relay/client media error contract stable.
   - Media miss remains `not found`.
   - Authorization failure remains `not authorized`.
   - If these move to constants, update relay tests and client classifier tests together.
4. Align direct media count retention with the direct inbox envelope retention window, while keeping TTL and byte-cap eviction as explicit storage-policy limits.
5. Write the failing multi-relay download test.
6. Refactor `go-mknoon/node/media.go` so media download can classify relay responses.
   - Retry later relays on `not found`, connection failure, and transient stream errors.
   - Do not retry on `not authorized` or local validation failures.
   - Keep partial-file cleanup behavior.
7. Run Go unit tests for relay and node.

### Session B: Receiver Commit And Orphan Adoption

1. Write the failing orphan-adoption tests in `download_media_use_case_test.dart`.
2. Add a pre-download adoption check in `DownloadMediaUseCase`.
   - Compute the deterministic canonical path for the attachment.
   - If a valid file already exists, verify expected hash/size when available, persist `localPath`, mark done, and skip bridge download.
3. Guard cleanup so a bridge `not found` does not delete a canonical file that existed before the attempt.
4. Guard cleanup after post-bridge validation failure.
   - Delete only the staging/current-attempt output.
   - Preserve any canonical file that existed before the attempt and is still hash/size-valid.
   - If the bridge can only write directly to the canonical path and validation failure leaves no recoverable local copy after relay auto-delete, stop and replan the relay delete/ack contract.
5. Prefer staged downloads if feasible in the current bridge contract.
   - Native download writes to a staging path.
   - Flutter validates, promotes to canonical path, and persists `localPath`.
   - Cleanup removes only staging files from the current attempt.
6. Run focused Flutter application tests.

### Session C: Local-WiFi Durable Fallback

1. Write the failing `conversation_wired_test.dart` local-WiFi fallback test.
2. Choose the smaller production fix unless product constraints require otherwise:
   - Default fix: keep relay upload as fallback even when local-WiFi media transfer succeeds.
   - Alternative: add a durable receiver ACK emitted only after `linkIncomingLocalMedia` persists the local path, then allow relay upload to be skipped only after that ACK.
3. Ensure outgoing media metadata still contains enough relay information for receiver retry.
4. Keep local transfer as an optimization for fast display, not the only copy of the media.
5. Run conversation wiring and local media use-case tests.

### Session D: Retry And Duplicate Replay Repair

1. Write the failing screen/widget wiring tests.
2. Thread `onRetryUnavailableMedia` through the direct 1:1 conversation path.
3. Implement a direct retry handler that:
   - Locates the message and target attachment.
   - Runs `DownloadMediaUseCase` for that attachment.
   - Refreshes only the affected message/attachment state.
   - Dedupes against an in-flight retry for the same attachment.
4. Write the duplicate replay repair test.
5. Update duplicate-message handling so a duplicate envelope with media descriptors can repair existing failed/pending media.
   - Keep message dedupe intact.
   - Schedule media recovery only for missing, failed, or pending attachments.
   - Do not overwrite a completed valid local path.
6. Make initial-load and targeted refresh paths merge by message ID so stale page results cannot overwrite newer streamed media repair state.
7. Add or extend resume recovery only if no existing path schedules this repair after app resume.
8. Run direct conversation application and presentation tests.

### Session E: Thumbnail Fallback Distinction

1. Write the failing thumbnail fallback test.
2. Separate thumbnail decode/generation failure from media availability.
   - Done video attachment with a valid file path should render a video fallback.
   - Failed/pending/no-file attachment should render unavailable or loading state as appropriate.
3. Keep retry controls tied to true media failure state, not thumbnail cache failure.
4. Run media widget tests and a focused conversation widget test.

### Simulator Acceptance

1. Before final closure, list available 1:1 simulator scenarios:
   - `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list`
2. Add or extend a 1:1 media journey scenario if no discovered scenario covers file/video media retry.
3. The scenario must cover at least one recovery path:
   - relay restart before receiver download,
   - first relay media miss with second relay success,
   - local-WiFi success followed by receiver retry using relay fallback,
   - canonical orphan adoption after retry.
4. Run the targeted scenario first, then the full 1:1 reliability gate.

## Risks And Edge Cases

- Relay restart rebuild must not grant access based only on directory names; authorization must come from persisted metadata.
- Metadata sidecars introduce compatibility questions for blobs already on disk. For rollout, missing sidecars can be ignored or treated as legacy-unservable; do not infer peer authorization from path alone unless separately reviewed.
- Same-ID retry must not truncate the existing final blob before the replacement upload completes.
- Retrying later relays on every error could hide authorization problems. Only retry classified media misses/transient transport failures.
- Direct media count retention must not be lower than direct inbox envelope retention. TTL and byte-cap eviction can still make old media unavailable and must be treated as explicit storage policy, not a hidden mismatch.
- Keeping relay fallback after local-WiFi success increases bandwidth. That is acceptable for correctness unless a durable receiver ACK is implemented.
- Auto-delete semantics may conflict with multi-device receiver retries and post-download validation failure. Keep current one-download delete behavior only if orphan adoption, staging, and validation-failure cleanup tests prove a recoverable local path is preserved when one exists.
- Staged download promotion must avoid exposing partial files to the UI.
- Duplicate replay repair must not reinsert messages or create duplicate attachments.
- Thumbnail fallback must not make genuinely missing media look playable.

## Exact Tests And Gates To Run

Focused Go tests:

```sh
go test ./go-relay-server
go test ./go-mknoon/node
go test -tags=integration ./go-mknoon/integration
```

Focused Flutter tests:

```sh
flutter test test/features/conversation/application/download_media_use_case_test.dart
flutter test test/features/conversation/application/link_incoming_local_media_use_case_test.dart
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
flutter test test/features/conversation/application/chat_message_listener_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
flutter test test/shared/widgets/media/media_grid_cell_test.dart
flutter test test/shared/widgets/media/media_thumbnail_image_test.dart
```

Named host gates:

```sh
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh completeness-check
```

Simulator gates:

```sh
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1
```

If a new simulator target is added but not discovered, update the simulator discovery script before claiming closure.

## Known-Failure Interpretation

- A newly added TDD test that passes before implementation is not valid evidence; tighten the test until it fails for the reported behavior.
- `go test -tags=integration ./go-mknoon/integration` can depend on local relay integration setup. If unavailable, record the setup failure and keep closure blocked until an equivalent relay-backed proof runs.
- If simulator devices are unavailable, host tests can prove implementation slices but cannot close this plan.
- Pre-existing unrelated red tests in the dirty worktree are not blockers for a focused session, but any red in the files changed by that session must be resolved or explicitly classified.

## Done Criteria

- All new tests fail first, then pass after the corresponding implementation.
- All focused tests listed above pass.
- `./scripts/run_test_gates.sh 1to1` passes.
- `./scripts/run_test_gates.sh transport` passes.
- `./scripts/run_test_gates.sh completeness-check` passes.
- The 1:1 simulator reliability run passes with media retry/recovery coverage.
- The relay/client media error contract for `not found` and `not authorized` is pinned by tests or shared constants.
- The five unverified source-report findings have explicit fixed/refuted/deferred status before closure.
- The source report findings are updated with fixed/refuted/deferred status, and deferred items have a concrete reason.
- `graphify update .` runs after code changes so the knowledge graph stays current.

## Scope Guard

Do not include these while executing this plan:

- Group media delivery or group inbox behavior.
- Public post media delivery.
- UI redesign beyond the unavailable/thumbnail distinction.
- Encryption protocol changes.
- Full local discovery protocol rewrite unless the durable ACK alternative is intentionally selected.
- Relay cluster/shared-state redesign beyond media metadata durability needed for this bug.
- Broad database migrations unrelated to media attachment local-path recovery.

## Accepted Differences And Intentional Out Of Scope

- It is acceptable for local-WiFi success to upload relay fallback for now, even if that duplicates bytes, because durable receiver persistence is the correctness boundary.
- It is acceptable to ignore legacy relay blobs without metadata after restart if they cannot be safely authorized.
- It is acceptable for TTL and byte-cap storage policy to evict old media even when envelopes remain, but the direct count cap must not be lower than direct inbox count retention.
- It is acceptable to keep relay auto-delete after a successful stream only if receiver-side orphan adoption, staged commit, and post-validation-failure cleanup tests pass.
- It is acceptable for simulator coverage to use a file fixture instead of a live camera recording, as long as it exercises the same message attachment pipeline.

## Dependency Impact

- Relay deployments need a writable media metadata location alongside blob storage.
- Relay restart behavior changes from "memory index lost" to "index rebuilt from persisted metadata".
- Mobile sender flow may upload relay fallback even after local-WiFi success, increasing transfer cost for direct 1:1 media.
- Mobile receiver flow becomes more conservative about deleting files and more aggressive about adopting valid local files.
- Conversation UI gains an incoming unavailable retry path for direct 1:1 media.
- Test and simulator discovery docs may need small updates if a new 1:1 media scenario is added.

## Reviewer Notes

- The plan directly covers every confirmed finding from the report except the already-refuted ciphertext hypothesis, and it now dispositions all five unverified findings before execution.
- The riskiest choice is Session C. The default fallback-upload fix is intentionally simpler than a durable ACK protocol and can be replaced later if bandwidth becomes a measured problem.
- The plan should be executed in order. Session A and B reduce data loss first; Session C prevents local-only delivery gaps; Session D repairs visible stuck states; Session E prevents false unavailable presentation.

## Arbiter Stop Rule

Stop and replan only if one of these becomes true:

- Relay media metadata cannot be persisted without changing the relay deployment contract.
- The node media download code cannot classify `not found` versus `not authorized` without changing the relay protocol.
- The validation-failure cleanup test proves current relay auto-delete leaves no recoverable local copy under the existing bridge contract.
- Direct 1:1 conversation retry cannot be wired without a broader state-management refactor.
- Simulator reliability cannot run after three clean attempts with resolved device selection.
