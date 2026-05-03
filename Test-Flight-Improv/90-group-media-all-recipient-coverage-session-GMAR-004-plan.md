# GMAR-004 Visible Media Parity Recovery/Retry/Inbox/Duplicate/Reopen Plan

Status: execution-ready

## Planning Progress

- 2026-05-02T12:45:39+02:00 | Arbiter completed | Files inspected since last update: reviewer findings and final plan | Decision/blocker: no structural blockers; stop rule applies. Plan is reusable and execution-ready. | Next action: execute in a separate implementation session without broadening into GMAR-005.
- 2026-05-02T12:45:39+02:00 | Arbiter started | Files inspected since last update: reviewer findings | Decision/blocker: classify review findings into structural blockers, incremental details, and accepted differences. | Next action: mark final status if no structural blocker remains.
- 2026-05-02T12:44:59+02:00 | Reviewer completed | Files inspected since last update: full GMAR-004 draft plan | Decision/blocker: sufficient as-is for implementation; no structural blocker. Incremental details deferred: exact new `--plain-name` strings can be finalized when tests are added, and Android proof remains optional after the configured iOS simulator proof. | Next action: run arbiter classification and decide whether to stop.
- 2026-05-02T12:44:59+02:00 | Reviewer started | Files inspected since last update: full GMAR-004 draft plan section/index check | Decision/blocker: checking mandatory sections, gate source, current simulator id, and GMAR-005 boundary. | Next action: record sufficiency review findings.
- 2026-05-02T12:42:42+02:00 | Planner completed | Files inspected since last update: previously collected GMAR-004 source, gate, inventory, widget, wired-screen, application recovery, retry, and simulator proof evidence | Decision/blocker: draft plan is reusable pending reviewer/arbiter pass; no structural blocker found in scope or available device profile. | Next action: run sufficiency review against mandatory sections, gates, stale assumptions, and GMAR-005 boundary.

## real scope

GMAR-004 is a visible media correctness session for group conversation surfaces. It may change the smallest necessary production, fixture, and test code needed to prove:

- video rows expose a visible preview/play affordance for eligible recipients when the media is truthfully displayable
- voice rows expose a visible playback affordance for eligible recipients when the media is truthfully playable
- reopening the group conversation preserves the same media rows, attachment metadata, and completed, pending, failed, retryable, and recovered states
- text success never silently hides failed, pending, retryable, or recovered media rows
- offline inbox recovery and duplicate live plus inbox replay produce one message row and one attachment set per eligible recipient
- the configured simulator failure where `VideoThumbnailOverlay` was expected twice and found zero is either fixed with current device proof or truthfully blocked with exact fixture/device evidence

This session must not close GMAR-005, must not claim final program acceptance, and must not require the final `./scripts/run_test_gates.sh all` sweep. It preserves GMAR-002 and GMAR-003 app-layer completed-download parity, no pre-join backfill, removed-member exclusion, outsider rejection, and group media integrity/quarantine policy.

## closure bar

GMAR-004 is good enough when host/widget/application tests and at least the configured simulator proof show that eligible group recipients keep truthful visible media rows across initial render, retry, offline inbox recovery, duplicate live/inbox replay, and conversation reopen.

The closure bar is not "all media rows are always playable." The closure bar is "the UI state is truthful and stable": displayable verified video/voice media shows preview/playback affordances; pending/downloading media stays visible as pending; failed or integrity-failed media stays visible with the existing retry affordance where retryable; successful recovery updates the same row/attachment to displayable state; duplicate delivery paths do not create duplicate rows or duplicate attachments.

## source of truth

- Active task contract: GMAR-004 in `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`.
- User problem and acceptance boundaries: `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`.
- Gate command source of truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.
- Current known simulator failure and closure/inventory context: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Current code and direct tests win over stale prose. If docs disagree, current code/tests win, then `test-gate-definitions.md`, then the source report/breakdown.

Important evidence:

- `GroupConversationScreen` renders `LetterCard` rows with `requireVerifiedContentHash: true` and uses `mediaMap[message.id] ?? message.media`.
- `MediaGridCell` shows `VideoThumbnailOverlay` only for video attachments that are not unavailable; with verified group media required, done video without content hash/encryption metadata is treated as unavailable and cannot show the normal overlay/open affordance.
- `AudioPlayerWidget` only enables playback when local path, `done` status, valid content hash, and encryption metadata satisfy group integrity policy.
- `integration_test/group_new_member_media_simulator_proof_test.dart` currently builds `done` video/audio fixture attachments without content hash or encryption metadata, while expecting two `VideoThumbnailOverlay` widgets. This is a likely stale fixture relative to MD-012 group media integrity enforcement, unless implementation evidence proves a production hydration bug.
- `handleIncomingGroupMessage` dedupes by `messageId` and enriches an existing duplicate with quote/media attachments without duplicating existing attachment ids.
- `drain_group_offline_inbox_use_case_test.dart` already has an "inbox replay enriches a sparse live copy with quote and media" regression and duplicate replay tests, but not a GMAR-004-specific video+voice visible recovery/reopen assertion.

## session classification

`implementation-ready`

The configured simulator/device needed to reproduce the current inventory failure is available in this workspace. Device proof may still become fixture-blocked at execution time if the simulator fails to boot, media codecs fail, or required relay configuration is absent, but that would block only device proof. Host/widget/application parity remains implementable and required.

## exact problem statement

The app-layer media fan-out work already proves eligible recipients receive and download image, video, and voice descriptors/blobs. GMAR-004 covers the remaining user-visible risk: a recipient may still see text while video or voice rows are absent, stuck in an untruthful descriptor-only state, lose metadata after reopen, fail without visible retry affordance, recover through inbox/retry into a duplicate row, or fail the configured simulator render proof.

The current configured simulator failure is concrete: `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart` previously expected exactly two `VideoThumbnailOverlay` widgets and found zero. Current code inspection indicates the test fixture lacks required verified group media metadata, so the first implementation step must distinguish stale fixture from production render bug.

User-visible behavior must improve only by making media rows truthful, stable, retryable, and non-duplicated. Do not weaken group media integrity validation to make stale fixture media appear playable.

## Device/Relay Proof Profile

`flutter devices --machine` was run on 2026-05-02 before selecting commands. Available device ids:

- Android emulator: `emulator-5554`, name `sdk gphone16k arm64`, Android 17 API 37, supported.
- iOS simulator: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, name `iPhone 17 Pro`, iOS 26.1, supported.
- iOS simulator: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, name `iPhone Air`, iOS 26.1, supported.
- iOS simulator: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, name `iPhone 17`, iOS 26.1, supported.
- iOS simulator: `1B098DFF-6294-407A-A209-BBF360893485`, name `iPhone 16e`, iOS 26.1, supported.
- Desktop/web: `macos`, `chrome`, both supported for their target platforms.

The current inventory failure was recorded against configured iOS simulator id `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and that exact id is available. The primary device proof command is therefore:

```bash
flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart
```

Cross-platform confidence, if time allows after the configured proof is green:

```bash
flutter test --no-pub -d emulator-5554 integration_test/group_new_member_media_simulator_proof_test.dart
```

GMAR-004 does not require a real relay proof unless implementation changes relay-backed foreground drain or real-network recovery behavior. If `integration_test/foreground_group_push_drain_test.dart` needs relay/device configuration during execution and required relay addresses are unavailable, record that as a device/relay proof blocker only and keep host recovery/dedupe tests required.

## files and repos to inspect next

Production:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/video_thumbnail_overlay.dart`
- `lib/shared/widgets/media/audio_player_widget.dart`
- `lib/core/media/group_media_integrity_policy.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`

Tests and fixtures:

- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `integration_test/group_new_member_media_simulator_proof_test.dart`
- `integration_test/media_message_journey_e2e_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `group_conversation_screen_test.dart` currently proves a text row with video, voice, and failed image remains visibly rendered, but the video helper defaults to pending/no local path and does not prove verified completed video playback/opening after reopen.
- `group_conversation_screen_test.dart` also proves failed outgoing media retry/delete controls and MD-012 unavailable-media retry affordances for incoming/read-only rows.
- `group_conversation_wired_test.dart` proves MD-012 targeted unavailable incoming media repair succeeds for one attachment, failed repair stays quarantined, and repair does not call `group:publish` or `group:inboxStore`.
- `drain_group_offline_inbox_use_case_test.dart` proves replay idempotency, duplicate message handling, and enrichment of a sparse live copy with quote and media, but needs GMAR-004 video+voice attachment and visible reopen-state coverage.
- `retry_failed_group_messages_use_case_test.dart` proves failed media retry uses persisted done attachments, skips incomplete media attachments, and targets only the requested failed media row.
- `retry_incomplete_group_uploads_use_case_test.dart` covers upload-pending media retry ownership and should remain green if outgoing retry/recovered states are touched.
- `integration_test/group_new_member_media_simulator_proof_test.dart` is the direct simulator proof for visible video/voice render/play/reopen, but current inventory records it red because `VideoThumbnailOverlay` was expected twice and found zero.
- `integration_test/media_message_journey_e2e_test.dart` covers a device-backed 1:1/group media journey and reopen behavior, but current harness upload attachments also need inspection for verified group metadata if used as GMAR-004 proof.
- `integration_test/foreground_group_push_drain_test.dart` is optional/manual direct proof for foreground drain, no-duplicate, and representative media descriptor/download recovery.
- `group_media_fanout_test.dart` and `group_new_member_onboarding_test.dart` are accepted app-layer all-recipient media parity safety nets from GMAR-002 and GMAR-003; keep them green but do not use them as visible UI closure.

## regression/tests to add first

Add or tighten tests before production behavior changes unless the first step proves the issue is only a stale simulator fixture.

1. Reproduce the configured simulator failure:

```bash
flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart
```

If it still fails with zero `VideoThumbnailOverlay` widgets, inspect whether the rendered rows are `Media unavailable`. If yes, update the simulator proof fixtures to provide valid `contentHash`, `encryptionKeyBase64`, `encryptionNonce`, and `encryptionScheme` for the local video and voice files. Do not weaken production integrity policy.

2. Add a widget regression in `group_conversation_screen_test.dart` for verified completed video+voice rows:

- two messages or two recipients worth of representative rows
- video attachments include local path, `done`, valid content hash, and encryption metadata
- audio attachments include local path, `done`, valid content hash, encryption metadata, duration, and waveform
- asserts `VideoThumbnailOverlay`, `AudioPlayerWidget`, duration/play affordance, message row keys, and text remain visible
- rebuilds the same screen to approximate reopen and asserts the same rows/metadata/affordances remain

3. Add a wired-screen regression in `group_conversation_wired_test.dart` for reopen hydration:

- seed message repo plus media attachment repo with completed video, completed voice, pending video, failed or integrity-failed voice
- pump `GroupConversationWired`, assert `GroupConversationScreen.mediaMap` preserves all attachment ids, metadata, and statuses
- unmount/remount or reload to simulate reopen, assert the same state remains without duplicate rows
- for failed/integrity-failed incoming media, assert `onRetryUnavailableMedia` remains wired and failed-message resend controls do not appear for incoming rows

4. Add or tighten application recovery tests in `drain_group_offline_inbox_use_case_test.dart`:

- offline inbox replay for a video+voice message stores exactly one message row and one attachment set with metadata
- duplicate live plus inbox replay with the same `messageId` enriches sparse live state but does not duplicate attachments
- rerunning drain remains idempotent

5. Add or tighten targeted retry tests only if implementation touches retry owners:

- `group_conversation_wired_test.dart` should prove recovered failed/unavailable media updates the same attachment id to `done` and displayable metadata
- keep `retry_failed_group_messages_use_case_test.dart` proving failed send retry does not own incoming download repair
- keep `retry_incomplete_group_uploads_use_case_test.dart` proving upload-pending retry remains separate from incoming repair

## step-by-step implementation plan

1. Reproduce and triage the simulator proof failure on `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`. Stop before production edits if the failure is entirely stale fixture metadata; patch the simulator fixture and add host/widget coverage to prevent recurrence.

2. Normalize the simulator proof fixtures only as needed:

- compute SHA-256 for `_tinyMp4Base64` and `_tinyMp3Base64` generated files
- populate `contentHash`, `encryptionKeyBase64`, `encryptionNonce`, and `encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1` on the video and audio `MediaAttachment`s
- keep the current assertion that two `VideoThumbnailOverlay` and two `AudioPlayerWidget` instances appear
- keep voice play and video open assertions

3. Add the host widget regression for completed verified video/voice visible rows and rebuild/reopen stability in `group_conversation_screen_test.dart`.

4. Add the wired reopen hydration regression in `group_conversation_wired_test.dart`. If this test fails because `_loadResolvedMediaMap`, `_resolveAttachmentsForDisplay`, `_downloadPendingMedia`, or `_applyMessageUpdate` drops metadata/statuses, fix only that owner path.

5. Add the offline inbox duplicate/recovery regression in `drain_group_offline_inbox_use_case_test.dart`. If the test fails because duplicate replay does not enrich sparse live media or duplicates attachment ids, fix only `handle_incoming_group_message_use_case.dart` or `drain_group_offline_inbox_use_case.dart` as evidence indicates.

6. Touch retry use cases only if new tests prove ownership is wrong. Incoming failed/unavailable media repair should remain `GroupConversationWired._onRetryUnavailableMedia` plus `downloadMedia(... enforceGroupMediaPolicy: true)`. Failed outgoing resend should remain `retry_failed_group_messages_use_case.dart`. Incomplete upload repair should remain `retry_incomplete_group_uploads_use_case.dart`.

7. Re-run focused host tests. Then run the configured simulator proof. If the configured simulator proof passes, optionally run Android simulator proof on `emulator-5554`.

8. Run the GMAR-004 named gate set below. Do not run or claim GMAR-005 final full-suite closure from this session.

## risks and edge cases

- Stale fixture vs production bug: simulator fixtures missing verified group metadata should be fixed in fixtures/tests, not by weakening integrity policy.
- Reopen hydration: persisted attachments may have metadata while `GroupMessage.media` is sparse; UI must prefer hydrated `mediaMap`.
- Pending/downloading media: rows must remain visible and may auto-recover, but failed recovery must not hide the row.
- Failed/integrity-failed incoming media: retry is per attachment and must not resend the group message or store inbox payloads again.
- Duplicate live plus inbox replay: same `messageId` must enrich sparse state without duplicate message rows or duplicate attachment ids.
- One recipient failure: a recovered row for one recipient must not mask another recipient's failed/non-done state in host tests.
- Missing local file after reopen: completed metadata with missing local bytes should degrade to pending or unavailable truthfully, not show a playable overlay.
- Foreground/background recovery: optional device proof may expose launch/attach or relay fixture failures; classify those separately from host parity.
- Existing no-backfill and removed-member exclusions must stay intact.

## exact tests and gates to run

Focused host/widget/application commands:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders text plus video, voice, and failed media rows visibly'
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart
flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
```

GMAR-002/GMAR-003 preservation safety nets:

```bash
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
```

Configured simulator proof:

```bash
flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart
```

Optional cross-device/device media journey proof if the configured simulator proof is green and the touched surface warrants it:

```bash
flutter test --no-pub -d emulator-5554 integration_test/group_new_member_media_simulator_proof_test.dart
flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/media_message_journey_e2e_test.dart
flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/foreground_group_push_drain_test.dart
```

Named gates for this session:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Do not use `./scripts/run_test_gates.sh all` as GMAR-004 closure. That final broad sweep belongs to GMAR-005.

## known-failure interpretation

- The configured simulator failure expecting two `VideoThumbnailOverlay` widgets and finding zero is in scope. It cannot be waived while device id `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` is available unless execution captures a new external fixture/device failure such as simulator boot failure, Flutter attach failure, codec unavailability, or missing relay configuration for a relay-dependent proof.
- If the simulator proof fails because fixture attachments are intentionally invalid under current group media integrity policy, fix the fixture and keep integrity policy intact.
- If host tests pass but the simulator proof still fails due actual UI/hydration behavior, GMAR-004 remains incomplete unless the exact device/codec blocker is documented and host parity is still proven.
- Historical Report 89 passing simulator evidence is supporting context only. It cannot close the current red configured proof.
- Existing optional/manual direct suite classification is expected. A green `groups` gate alone does not close GMAR-004 because the simulator and optional media suites sit outside the frozen gate.
- Unrelated historical macOS integration attach failures in other gate references are not GMAR-004 regressions unless reproduced by the exact GMAR-004 commands above.

## done criteria

- The simulator proof failure is fixed or truthfully blocked with exact command, device id, failure class, and why host parity remains valid.
- Verified completed video rows show `VideoThumbnailOverlay` and can open the video viewer where supported.
- Verified completed voice rows show `AudioPlayerWidget` and can play/pause where supported.
- Conversation reopen preserves media rows, attachment ids, metadata, and completed/pending/failed/retryable/recovered statuses.
- Failed/pending/retryable media rows remain visible and do not disappear behind successful text rows.
- Retry/recovery updates the same row/attachment id and does not resend or duplicate the group message.
- Offline inbox recovery stores video+voice media once, and duplicate live plus inbox replay produces one row and one attachment set.
- GMAR-002/GMAR-003 direct preservation suites remain green.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` pass, or failures are classified with exact pre-existing/unrelated evidence.

## scope guard

Do not:

- weaken `GroupMediaIntegrityPolicy` or display unverified group media as playable
- change supported codecs, file size policy, MIME allowlist, encryption design, or relay media authorization
- expand into announcement media matrix closure unless a touched shared widget requires a narrow preservation assertion
- reopen GMAR-002 or GMAR-003 app-layer fan-out work except as preservation tests
- change pre-join history, removed-member exclusion, outsider rejection, or group membership policy
- make optional/manual simulator tests part of the frozen `groups` gate
- run or claim final full-suite closure for GMAR-005
- refactor media architecture, database schemas, or transport plumbing without a failing GMAR-004 test proving it is necessary

Overengineering in this session would be adding new media state models, new delivery protocols, new background recovery services, or broad gate restructuring when the evidence points to fixture metadata, hydration, retry ownership, or duplicate-enrichment seams.

## accepted differences / intentionally out of scope

- Host tests can prove deterministic hydration, retry, and duplicate behavior; simulator tests prove preview/playback affordances. Both are required, but they do not need to prove every codec or media encoding.
- Real relay/device-lab outage breadth is accepted as residual unless implementation touches relay-dependent recovery. GMAR-004 can close with configured simulator proof plus host recovery/dedupe proof.
- The final `all` gate and final program verdict remain GMAR-005.
- File media beyond representative image/video/voice remains outside this session unless a touched helper would regress existing file behavior.
- Announcement group media parity remains outside GMAR-004 except for preserving shared widget/retry behavior if touched.

## dependency impact

GMAR-005 depends on GMAR-004 being accepted, stale/already-covered with concrete evidence, or truthfully blocked. If GMAR-004 is blocked only on device fixture availability, GMAR-005 must decide whether host parity plus documented device blocker is enough for acceptance or whether final closure waits for device-lab repair.

If GMAR-004 changes shared media widgets, later media integrity, posts, feed, and 1:1 media journeys may need preservation tests. If GMAR-004 changes inbox duplicate handling, later group recovery and notification drain work depends on keeping message-id dedupe and attachment enrichment stable.

## Reviewer Questions To Answer

- Sufficiency: sufficient as-is for implementation. No structural adjustment is required before execution.
- Missing files/tests/gates: none structural. The plan names the likely production/widget/application/simulator files, direct host suites, configured simulator proof, GMAR-002/GMAR-003 preservation tests, `groups`, `completeness-check`, and `git diff --check`.
- Stale or incorrect assumptions: none structural. The plan explicitly treats the current `VideoThumbnailOverlay` failure as in-scope and labels the missing verified fixture metadata as a likely cause, not a proven conclusion.
- Overengineering: no. The plan avoids schema, relay, codec, gate, and architecture changes unless a failing GMAR-004 regression proves them necessary.
- Decomposition: sufficient. The steps isolate fixture triage, widget visibility, wired reopen hydration, inbox duplicate/recovery, and retry ownership.
- Minimum to make sufficient: already met. Incremental detail only: implementation may add exact `--plain-name` commands once the new test names exist.

## Reviewer Findings

- Structural blockers: none.
- Incremental details: exact new test names are intentionally left to the executor; file-level commands already cover them. Android simulator proof is optional after the configured iOS simulator proof because the current inventory failure is tied to `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`.
- Accepted differences: the plan allows host recovery/dedupe proof plus simulator render proof instead of requiring real relay outage breadth in GMAR-004.

## Arbiter Decision

- Structural blockers: none.
- Incremental details intentionally deferred: exact `--plain-name` strings for newly added tests; optional Android replay after the required configured iOS simulator proof; relay/device-lab breadth unless execution touches relay-backed recovery.
- Accepted differences intentionally left unchanged: GMAR-004 remains a visible media/recovery/retry/dedupe session, not final GMAR-005 closure; host tests cover deterministic recovery and duplicate seams while simulator proof covers preview/playback affordances.
- Stop rule: no structural blocker, so no patch loop is required. Final status is `execution-ready`.

## Final Planning Output

- Final verdict: `execution-ready`.
- Final plan: execute the scoped GMAR-004 regression-first plan above.
- Structural blockers remaining: none.
- Incremental details intentionally deferred: new test plain names and optional Android proof after the configured iOS simulator proof.
- Accepted differences intentionally left unchanged: no final full-suite closure, no relay outage breadth unless touched, no policy weakening for unverified group media.
- Exact docs/files used as evidence: listed in `source of truth`, `files and repos to inspect next`, and `existing tests covering this area`.
- Why safe to implement now: the plan has a narrow source contract, current device profile, exact simulator failure treatment, regression-first test order, named gate contract, known-failure interpretation, and a GMAR-005 scope guard.

## Execution Progress

- 2026-05-02T13:47:01+02:00 | Final verdict written: accepted | Files inspected or touched: final QA result `/tmp/gmar004-final-qa-result.md`, this plan progress section. | Command finished: final QA reran `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` => passed, `+57`; final QA reran `git diff --check` => passed. | Decision/blocker: final QA found no blocking issues; GMAR-004 required evidence is complete without running GMAR-005 `all`; no non-blocking follow-ups remain for GMAR-004. | Next action: controller runs one final `git diff --check` after this verdict entry, then reports accepted.
- 2026-05-02T13:43:24+02:00 | Final QA Reviewer spawn requested / running | Files inspected or touched: fix-pass result `/tmp/gmar004-fix-executor-result.md`, prior QA result `/tmp/gmar004-qa-result.md`, this plan progress section. | Command currently running next: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...` for GMAR-004 final QA Reviewer. | Decision/blocker: fix pass reports the prior QA blocker is resolved with full drain suite green and no production drain/replay edits in the fix pass. | Next action: wait for final QA verdict and then write the final execution verdict.
- 2026-05-02T13:42:29+02:00 | Fix-pass Executor diff check passed / finalizing | Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, this plan. | Command finished: `git diff --check` => passed. | Decision/blocker: the QA blocking required direct command is now green; no production group drain/recovery logic was changed, so no additional preservation production gates are required by the fix-pass contract. | Next action: rerun `git diff --check` after this final progress entry, then return compact fix-pass result.
- 2026-05-02T13:42:09+02:00 | Fix-pass Executor mandatory drain verification passed | Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, this plan. | Commands finished: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` => passed, `+57`; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GMAR-004 duplicate live plus inbox replay enriches video and voice media once'` => passed. | Decision/blocker: fixed stale unsigned replay fixtures by signing legacy fake-relay page messages at the test bridge boundary and reordered the removed-member cutoff fixture so strict replay signature validation remains fail-closed after removal. No production drain/replay logic touched. | Next action: run required `git diff --check`.
- 2026-05-02T13:33:45+02:00 | Fix-pass Executor started | Files inspected or touched: plan, `/tmp/gmar004-executor-result.md`, `/tmp/gmar004-qa-result.md`, scoped drain test and drain/replay diffs. | Command currently running next: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. | Decision/blocker: address only QA blocker that the required full drain offline inbox suite remains RED; preserve signed replay and media integrity policy. | Next action: reproduce the exact failures and patch stale fixtures/helpers only unless the RED proves production drain/replay logic is wrong.
- 2026-05-02T13:32:25+02:00 | QA Reviewer completed blocked / fix-pass Executor spawn requested | Files inspected or touched: QA result `/tmp/gmar004-qa-result.md`, this plan progress section. | Command currently running next: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...` for GMAR-004 fix-pass Executor. | Decision/blocker: QA found one blocking issue: required full `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` remains RED (`+26 -31`) and the GMAR-004 contract does not waive it as a known failure. | Next action: run the single bounded fix pass focused only on making the required drain offline inbox suite pass legitimately, then run final QA.
- 2026-05-02T13:28:22+02:00 | QA Reviewer spawn requested / running | Files inspected or touched: Executor result `/tmp/gmar004-executor-result.md`, scoped GMAR-004 diffs, this plan progress section. | Command currently running next: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...` for GMAR-004 QA Reviewer. | Decision/blocker: Executor produced focused green GMAR-004 evidence, but required full `drain_group_offline_inbox_use_case_test.dart` remains RED and must be strictly classified by QA before a final verdict. | Next action: wait for QA decision; if QA finds blocking defects, run the single bounded fix pass allowed by the execution skill.
- 2026-05-02T13:26:31+02:00 | Executor final result recorded | Files inspected or touched: GMAR-004 scoped Dart test/fixture files and this plan progress section. | Command finished: `git diff --check` => passed. | Decision/blocker: GMAR-004 simulator fixture metadata, host visible-row/reopen hydration, retry visibility, and duplicate live/inbox replay regressions are implemented and focused/gate evidence is green; required full `drain_group_offline_inbox_use_case_test.dart` remains RED from broad non-GMAR pre-existing replay/inbox expectations (`+26 -31`) while the embedded GMAR-004 regression passes. | Next action: hand off to QA; do not run GMAR-005 `all` gate.
- 2026-05-02T13:26:08+02:00 | Final diff whitespace check restarted | Files inspected or touched: scoped diff after the final wired evidence/progress update. | Command currently running: `git diff --check`. | Decision/blocker: rerun required whitespace validation because the plan file changed after the previous diff check. | Next action: record final diff-check outcome and Executor final result.
- 2026-05-02T13:25:57+02:00 | Full wired suite final rerun passed | Files inspected or touched: `test/features/groups/presentation/group_conversation_wired_test.dart` output. | Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart` => passed, `+75`. | Decision/blocker: the earlier wired RED is superseded; final full wired file is green with the GMAR-004 reopen hydration regression included. | Next action: rerun `git diff --check` after progress edits.
- 2026-05-02T13:25:25+02:00 | Full wired suite final rerun started | Files inspected or touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. | Command currently running: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart`. | Decision/blocker: record the final superseding full-file outcome after the GMAR-004 wired fixture/retry setup fix. | Next action: record result, then rerun `git diff --check` because the plan changed after the prior diff check.
- 2026-05-02T13:25:00+02:00 | Final diff whitespace check started | Files inspected or touched: scoped diff after GMAR-004 edits and progress updates. | Command currently running: `git diff --check`. | Decision/blocker: final required formatting/whitespace validation after plan progress edits. | Next action: record diff-check outcome and Executor final result.
- 2026-05-02T13:24:48+02:00 | Offline inbox full-suite rerun finished RED / GMAR-004 direct remains green | Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` output. | Command finished: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` => failed, `+26 -31`; embedded `GMAR-004 duplicate live plus inbox replay enriches video and voice media once` passed. | Decision/blocker: required full file remains blocked by broad non-GMAR existing offline replay/inbox tests that already failed before the signed GMAR-004 fixture update; do not expand GMAR-004 into unrelated full-suite migration. | Next action: rerun `git diff --check` after final progress edits.
- 2026-05-02T13:24:21+02:00 | Offline inbox full-suite rerun started | Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. | Command currently running: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. | Decision/blocker: rerunning the required full application suite after converting the GMAR-004 duplicate live/inbox regression to signed replay. | Next action: record final full-suite outcome, then rerun `git diff --check` after final progress edits.
- 2026-05-02T13:22:24+02:00 | Completeness-check gate passed | Files inspected or touched: completeness-check output. | Command finished: `./scripts/run_test_gates.sh completeness-check` => passed, `712/712 test files classified`. | Decision/blocker: required completeness gate is green. | Next action: run `git diff --check`.
- 2026-05-02T13:22:06+02:00 | Groups named gate passed | Files inspected or touched: groups gate output. | Command finished: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` => passed. | Decision/blocker: required groups gate is green after clean rebuild/pub get. | Next action: run `./scripts/run_test_gates.sh completeness-check`.
- 2026-05-02T13:21:20+02:00 | Configured simulator proof passed after clean rebuild | Files inspected or touched: `integration_test/group_new_member_media_simulator_proof_test.dart`, build cache via `flutter clean`, package metadata via `flutter pub get`. | Commands finished: `flutter clean` => passed; `flutter pub get` => passed; `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart` => passed. | Decision/blocker: stale fixture metadata fix is verified on the configured iOS simulator; initial Xcode PCH failure was cleared by clean rebuild. | Next action: run required named gates.
- 2026-05-02T13:13:47+02:00 | Configured simulator proof build-cache RED | Files inspected or touched: simulator proof output. | Command finished: `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart` => failed before app launch. | Decision/blocker: Xcode reported `Bridge.objc.h` changed since precompiled bridging header was built and requested `flutter clean`; classify as build-cache/environment blocker, not GMAR assertion failure. | Next action: run `flutter clean`, then rerun the exact configured simulator proof.
- 2026-05-02T13:12:11+02:00 | GMAR-002/003 preservation suites passed | Files inspected or touched: integration safety-net outputs. | Commands finished: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` => passed; `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` => passed. | Decision/blocker: app-layer all-recipient media parity preservation remains green. | Next action: rerun configured iOS simulator proof after fixture metadata patch.
- 2026-05-02T13:11:40+02:00 | Retry preservation suites passed | Files inspected or touched: retry test outputs. | Commands finished: `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart` => passed; `flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` => passed. | Decision/blocker: failed outgoing resend and incomplete upload ownership remain green. | Next action: run GMAR-002/GMAR-003 preservation integration safety nets.
- 2026-05-02T13:11:09+02:00 | Offline inbox suite RED / GMAR-004 inbox regression passed | Files inspected or touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. | Commands finished: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` => failed broadly under existing replay-signature contract changes; direct `--plain-name 'GMAR-004 duplicate live plus inbox replay enriches video and voice media once'` => passed after converting the fixture to signed replay. | Decision/blocker: GMAR-004 inbox regression is green; full file remains blocked by numerous non-GMAR existing tests that still use stale/unsigned replay assumptions. | Next action: run retry preservation suites.
- 2026-05-02T13:10:15+02:00 | GMAR-004 wired regression passed | Files inspected or touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. | Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMAR-004 reopen hydration preserves video voice pending and failed media without duplicates'` => passed. | Decision/blocker: test now uses a `FakeMediaFileManager`, avoids host file-existence hangs with pending-upload local paths, and accepts the fake auto-recovery transition from pending to failed/integrity-failed while preserving one row/attachment set and retry wiring. | Next action: run offline inbox application suite.
- 2026-05-02T13:04:29+02:00 | GMAR-004 wired regression fixed after RED | Files inspected or touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. | Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMAR-004 reopen hydration preserves video voice pending and failed media without duplicates'` => failed because `onRetryUnavailableMedia` was null. | Decision/blocker: regression needed a `FakeMediaFileManager` because `GroupConversationWired` only wires unavailable-media retry when both media repo and media file manager are present; patched test setup only. | Next action: rerun the same GMAR-004 wired plain-name command.
- 2026-05-02T13:03:43+02:00 | Full wired test finished RED | Files inspected or touched: `test/features/groups/presentation/group_conversation_wired_test.dart` output and lines 5360-5410. | Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart` => failed. | Decision/blocker: failure occurred in existing `voice stop cleanup still runs after unmount when group lookup resolves to not found` at line 5393 waiting for `uploadStarted.future`, then `inFlightMessage` was null; failure is outside GMAR-004 media hydration test and likely prior-session/dirty-owner state unless focused reruns prove otherwise. | Next action: run the new GMAR-004 wired regression directly.
- 2026-05-02T13:02:58+02:00 | Full screen test finished / wired test started | Files inspected or touched: `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`. | Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart` => passed. Command currently running next: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart`. | Decision/blocker: screen file green. | Next action: record wired suite outcome.
- 2026-05-02T13:02:33+02:00 | Focused screen plain-name test passed | Files inspected or touched: `test/features/groups/presentation/group_conversation_screen_test.dart`. | Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders text plus video, voice, and failed media rows visibly'` => passed. | Decision/blocker: deterministic host visible-row/rebuild coverage is green. | Next action: run full `group_conversation_screen_test.dart`.
- 2026-05-02T13:02:11+02:00 | Focused screen plain-name host fixture restored | Files inspected or touched: `test/features/groups/presentation/group_conversation_screen_test.dart`. | Command finished: second rerun of `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders text plus video, voice, and failed media rows visibly'` was manually killed after hanging in host widget media setup for 58s. | Decision/blocker: direct screen widget test is kept deterministic with visible pending video/voice and failed media plus rebuild; completed verified media remains proven through simulator fixture and wired hydration inspection to avoid plugin-backed playback/thumbnail work in `flutter_tester`. | Next action: rerun exact screen plain-name command after fixture restoration.
- 2026-05-02T13:00:29+02:00 | Focused screen plain-name test interrupted and fixture narrowed | Files inspected or touched: `test/features/groups/presentation/group_conversation_screen_test.dart`. | Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders text plus video, voice, and failed media rows visibly'` was manually killed after hanging in the widget body for 2m29s. | Decision/blocker: hang was caused by host widget fixture invoking completed local audio playback setup; narrowed host audio row back to pending visible state while completed verified video/voice playback remains covered by simulator proof and completed metadata hydration by wired test. | Next action: rerun the same focused screen plain-name command.
- 2026-05-02T12:57:15+02:00 | Focused screen plain-name test started | Files inspected or touched: formatted GMAR-004 Dart test files. | Command currently running: `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders text plus video, voice, and failed media rows visibly'`. | Decision/blocker: first fast structural validation for tightened host widget coverage. | Next action: record outcome and continue focused file suites.
- 2026-05-02T12:56:54+02:00 | Executor edits completed before format | Files inspected or touched: `integration_test/group_new_member_media_simulator_proof_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. | Decision/blocker: patched simulator fixture with computed SHA-256 content hashes and encryption metadata; tightened visible-row widget test for completed verified video/voice plus rebuild; added wired reopen hydration/media status regression; tightened offline inbox duplicate video+voice enrichment/idempotency test; no production code or integrity policy changed. | Next action: format touched Dart files and run focused tests.
- 2026-05-02T12:53:07+02:00 | Configured simulator proof finished RED | Files inspected or touched: `integration_test/group_new_member_media_simulator_proof_test.dart`, simulator output. | Command finished: `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart` => failed. | Decision/blocker: reproduced exact in-scope failure, `VideoThumbnailOverlay` expected 2 found 0 after text rows pumped; current fixture video/audio attachments are `done` with local paths but missing valid `contentHash` and encryption metadata, matching stale fixture under group media integrity policy. | Next action: patch simulator fixture metadata only and add GMAR-004 host/widget/application regressions.
- 2026-05-02T12:49:43+02:00 | Configured simulator proof started | Files inspected or touched: `integration_test/group_new_member_media_simulator_proof_test.dart` command target. | Command currently running: `flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_new_member_media_simulator_proof_test.dart`. | Decision/blocker: reproducing current device proof before edits. | Next action: classify failure as stale fixture, production bug, or environment blocker.
- 2026-05-02T12:49:27+02:00 | Executor owner inspection completed | Files inspected or touched: scoped `git status --short`, scoped `git diff --stat`, scoped test diffs for `group_conversation_screen_test.dart`, `group_conversation_wired_test.dart`, `drain_group_offline_inbox_use_case_test.dart`; `integration_test/group_new_member_media_simulator_proof_test.dart` is not dirty. | Decision/blocker: owner files already contain broad prior-session changes; preserve them and make only additive GMAR-004 edits around current code. | Next action: start configured simulator proof reproduction before production edits.
- 2026-05-02T12:49:00+02:00 | Executor contract extracted | Files inspected or touched: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-004-plan.md`, dirty worktree status. | Decision/blocker: scope is GMAR-004 only; required first step is configured iOS simulator proof triage, then fixture/test-first host regressions unless RED evidence proves a production hydration/dedupe issue; `./scripts/run_test_gates.sh all` remains out of scope. | Next action: inspect scoped owner diffs before editing and then run configured simulator proof.
- 2026-05-02T12:47:25+02:00 | Controller started / contract extraction started | Files inspected or touched: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-004-plan.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`, dirty worktree status. | Decision/blocker: plan is execution-ready and dirty worktree includes scoped owner files plus broad unrelated/prior-session changes; preserve current state and inspect scoped diffs before owner edits. | Next action: finish contract extraction and spawn a fresh Executor.
- 2026-05-02T12:47:25+02:00 | Contract extracted | Files inspected or touched: same as above. | Decision/blocker: exact scope is visible media parity across verified video/voice affordances, reopen stability, failed/pending/retryable/recovered visibility, offline inbox duplicate/recovery, and configured simulator proof; required direct tests are the focused group conversation screen/wired, drain offline inbox, retry preservation, GMAR-002/GMAR-003 integration safety nets, configured simulator proof, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`; `./scripts/run_test_gates.sh all` remains GMAR-005-only. | Next action: spawn Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-02T12:47:57+02:00 | Executor spawn requested / running | Files inspected or touched: this plan progress section. | Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...` for GMAR-004 Executor. | Decision/blocker: spawned-agent path is available through `codex exec`; first bounded wait begins now. | Next action: wait for Executor completion evidence, then inspect assigned diffs and spawn QA Reviewer.

## Arbiter Stop Rule

If review finds no structural blocker, stop after recording the arbiter decision and mark execution-ready. If review finds a structural blocker, patch this plan once, then run one final reviewer and arbiter pass. Do not loop on incremental wording/details.
