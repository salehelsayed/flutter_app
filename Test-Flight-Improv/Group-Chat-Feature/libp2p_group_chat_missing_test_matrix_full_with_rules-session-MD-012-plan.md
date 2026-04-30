# MD-012 Session Plan - Unsafe Media Quarantine And Retry UI

Session id: `MD-012`  
Source row id: `MD-012`  
Order: `44`  
Source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`  
Breakdown: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`  
Plan output: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-MD-012-plan.md`

## Final verdict

Session classification: `implementation-ready`.

`MD-012` is not covered by current repo evidence. Prior media rows already enforce the lower-level contracts: MD-001 MIME/type rejection, MD-002 size limits, MD-003 content-hash display gating with `integrity_failed`, MD-004 per-object encryption/decrypt checks, and MD-011 removed-member future-media access. What remains for MD-012 is user-facing behavior: unsafe or unavailable group media must render as an explicit unavailable/quarantined row, expose a safe per-attachment retry control when a repaired descriptor/blob can be retried, and never render or open untrusted local bytes.

The safe implementation path is Flutter-side only unless RED tests prove otherwise. Do not change Go media protocol, relay storage, chunk resume, generic files, thumbnail privacy, or device-matrix scope in this session.

## Evidence collector summary

- Source matrix row `MD-012` is P0/Open and requires failing media variants, message-row UI inspection, retry after repair, safe retry controls, and no untrusted rendering.
- Breakdown order `44` classifies `MD-012` as `needs_code_and_tests` / `implementation-ready`.
- `test-inventory.md` records MD-001 through MD-004 as covered and MD-011 as covered; those rows must be reused, not reopened.
- `MediaAttachment.downloadStatus` is documented as `pending`, `downloading`, `done`, `failed`, but current code also uses `upload_pending`, `upload_failed`, `upload_cancelled`, and `integrity_failed`.
- `lib/core/media/group_media_integrity_policy.dart` defines `kMediaDownloadStatusIntegrityFailed = 'integrity_failed'` and `canDisplayVerifiedGroupMedia(...)`, which requires `done`, local path, valid content hash, and encryption metadata.
- `downloadMedia(enforceGroupMediaPolicy: true)` blocks invalid MIME/size/hash/encryption and verifies encrypted hash before decrypt plus plaintext MIME/size after decrypt. It currently marks hash failures as `integrity_failed`, but several unsafe validation/decrypt/local-safety failures still use generic `failed`.
- `GroupConversationWired._resolveAttachmentsForDisplay(...)` marks legacy hashless or mismatched `done` group media as `integrity_failed` and deletes mismatched local files when detected. `_shouldRecoverVisibleAttachment(...)` auto-recovers `pending`, `downloading`, and `failed`, but not `integrity_failed`.
- `MediaGridCell` and `AudioPlayerWidget` do not render media unless verification passes when `requireVerifiedContentHash` is true. The visual result for unsafe media is currently a generic broken icon or disabled audio, not a user-facing quarantine/unavailable surface with retry controls.
- `GroupConversationScreen` passes `requireVerifiedContentHash: true` and gates full-screen open through `GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(...)`, but it only shows retry/delete controls for a sent message with `message.status == 'failed'` and media. Incoming/download failures and `integrity_failed` rows have no explicit retry control.
- Existing tests cover data-level integrity and display blocking: `group_media_integrity_policy_test.dart`, `download_media_use_case_test.dart`, `group_conversation_screen_test.dart`, `group_conversation_wired_test.dart`, `media_grid_cell_test.dart`, `audio_player_widget_test.dart`, `group_media_fanout_test.dart`, and `foreground_group_push_drain_test.dart`. They do not prove the MD-012 unavailable/quarantine UI plus safe retry flow.

## Final plan

### real scope

Implement exactly the `MD-012` user-facing quarantine and retry contract for group media.

In scope:

- Define the current status vocabulary in code-level constants or a small helper so UI and retry logic do not keep scattering raw strings.
- Treat `integrity_failed` as the quarantine status for unsafe group media in this session. Use `failed` for transient download failures only.
- Normalize unsafe group download/display failures so invalid descriptor, hash mismatch, decrypt failure, plaintext safety failure, and local display integrity failure cannot become displayable and are surfaced as unavailable/quarantined.
- Add a visible unavailable/quarantined placeholder for image, video, GIF, and voice media in group message rows.
- Add a safe per-attachment retry control for unavailable downloaded media. This retry is a download/verification retry, not a message resend.
- Preserve the existing outgoing failed-media resend/delete controls for failed sent messages.
- Add direct RED tests first, then production code only where the tests prove the gap.

Out of scope:

- Media protocol redesign, chunk resume, relay storage changes, generic file support, encrypted thumbnail/privacy expansion, autoplay policy, media expiration, removed-member access, device-matrix expansion, or Go/relay code unless a direct RED test proves Flutter cannot meet the row contract without it.
- Reopening MD-001, MD-002, MD-003, MD-004, or MD-011.
- Updating the source matrix, inventory, or breakdown during planning. Execution/closure must update them only after concrete tests and gates pass.

### closure bar

`MD-012` can become `Covered` only when tests prove all of the following:

- Unsafe group media states render an explicit unavailable/quarantined UI, not a raw broken icon alone.
- The UI never builds `Image.file`, generated thumbnails, full-screen viewer routes, or playable audio controls for media whose status is `failed`, `integrity_failed`, `upload_failed`, `upload_cancelled`, or whose verified-display predicate fails.
- `integrity_failed` is used for unsafe/quarantined media; `failed` remains available for transient download failure.
- A per-attachment retry control is available for visible unavailable downloaded media, including read-only announcement-reader surfaces, because download retry is not a write/send action.
- Tapping retry reloads the current persisted attachment descriptor, deletes or ignores unsafe local files, calls `downloadMedia(... enforceGroupMediaPolicy: true)`, and updates only that attachment in the row.
- Retry never calls `retryFailedGroupMessage`, `retryIncompleteGroupUploads`, `group:publish`, or `group:inboxStore` for incoming/download-only media repair.
- Retry after a repaired blob/descriptor marks media `done` and displayable only after MD-001 through MD-004 checks pass.
- Retry after an unrepaired or still-unsafe blob keeps the row unavailable/quarantined and leaves no displayable local file.
- Existing valid group image/video/GIF/voice media still sends, drains, downloads, and displays.

The row cannot be accepted until the source row is moved to `Covered`/closed and `test-inventory.md` records exact MD-012 tests and gate evidence.

### source of truth

- Current code and tests win over stale prose.
- Primary source row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`, row `MD-012`.
- Current session row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, order `44`.
- Current inventory and prior-row evidence: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Gate source: `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md` is explanatory and says the script wins on disagreement.
- `SMOKE-GAP-05` is a matrix evidence label, not a shell command.

### session classification

`implementation-ready`.

Reason: repo evidence shows a concrete user-facing gap with known Flutter seams and direct tests. No external proof or product-scope prerequisite is needed to start.

### exact problem statement

The app already blocks many unsafe group media bytes from rendering, but the user-facing state is incomplete. A quarantined or unavailable group media item can appear as a generic broken icon or disabled audio with no row-local explanation and no safe repair retry. Existing retry controls are tied to failed outgoing message resend, so they are not available for incoming/download-only media failures or read-only group surfaces.

User-visible behavior must improve so a recipient can tell that the media is unavailable/quarantined, can explicitly retry after the descriptor/blob has been repaired, and never opens or plays untrusted content while retry is pending or failing.

What must stay unchanged: valid group media display, prior MIME/size/hash/encryption checks, outgoing failed-message retry/delete behavior, group send/inbox retry ownership, and removed-member media isolation.

### files and repos to inspect next

Production files:

- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/core/media/group_media_integrity_policy.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_grid.dart`
- `lib/shared/widgets/media/audio_player_widget.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` only to keep upload retry ownership separate from download retry.

Test files:

- `test/core/media/group_media_integrity_policy_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/shared/widgets/media/audio_player_widget_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`

Docs/gates for closure:

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

### existing tests covering this area

Already covered:

- `group_media_integrity_policy_test.dart` proves verified-display eligibility rejects non-`done`, hashless, and missing-encryption media.
- `download_media_use_case_test.dart` proves group download rejects MIME mismatch, oversized declared size, spoofed bytes, content-hash mismatch, missing content hash, missing encryption metadata, and wrong-key decrypt attempts before `done`.
- `group_conversation_wired_test.dart` proves startup display recovery marks hashless/mismatched `done` group media as `integrity_failed` and keeps normal failed outgoing media retry targeted.
- `group_conversation_screen_test.dart` proves failed media shows a broken-image placeholder and outgoing failed-media message rows expose retry/delete controls only when the sender can write.
- `media_grid_cell_test.dart` and `audio_player_widget_test.dart` cover display blocking for unverified media in shared widgets.
- `group_media_fanout_test.dart` and `foreground_group_push_drain_test.dart` cover valid media fan-out/drain and lower-level invalid/tampered media rejection.

Missing:

- No direct test proves a user-visible "Media unavailable" or quarantine state in group rows.
- No direct test proves a per-attachment retry control for incoming/download-only unavailable media.
- No direct test proves read-only group readers can retry a failed download without write/send permission.
- No direct test proves retry after repair is download-only and never republishes or resends the group message.
- No direct test proves retry failure keeps `integrity_failed`/unavailable state and leaves no displayable local file.
- No direct test unifies the status vocabulary so unsafe failures are not split between generic `failed` and `integrity_failed` in ways that invite automatic recovery or misleading UI.

### regression/tests to add first

Add RED tests before production edits.

1. `test/features/groups/presentation/group_conversation_screen_test.dart`
   - Add `MD-012 quarantined visual media shows unavailable placeholder and retry control`.
   - Seed an incoming group image with `downloadStatus: integrity_failed`, a local path, valid hash metadata, and encryption metadata.
   - Expect visible unavailable/quarantine copy such as `Media unavailable`, a stable retry control key such as `unavailable-media-retry-<messageId>-<attachmentId>`, and semantics `Retry unavailable media`.
   - Expect no full-screen open when the media cell itself is tapped.

2. `test/features/groups/presentation/group_conversation_screen_test.dart`
   - Add `MD-012 read-only group rows can retry unavailable incoming media without resend controls`.
   - Set `canWrite: false`, seed incoming `failed` and `integrity_failed` media, and provide the new download-retry callback.
   - Expect per-attachment retry controls to exist, while existing `failed-media-retry-*` and `failed-media-delete-*` outgoing resend/delete controls remain absent.

3. `test/shared/widgets/media/media_grid_cell_test.dart`
   - Add `MD-012 integrity-failed image and video cells render unavailable UI and do not build MediaThumbnailImage`.
   - Cover `failed`, `integrity_failed`, missing hash, and missing encryption metadata with `requireVerifiedContentHash: true`.
   - Assert a retry callback is exposed only when supplied and `_canOpen` stays false.

4. `test/shared/widgets/media/audio_player_widget_test.dart`
   - Add `MD-012 quarantined audio disables playback and exposes unavailable retry semantics`.
   - Assert the player never calls `setFilePath` or allows play while the attachment is not verified-display eligible.

5. `test/features/conversation/presentation/widgets/letter_card_test.dart`
   - Add `MD-012 unavailable media actions are separate from failed-message resend`.
   - Prove per-attachment unavailable-media retry can coexist with existing failed-message retry/delete buttons without invoking the wrong callback.

6. `test/features/conversation/application/download_media_use_case_test.dart`
   - Add `MD-012 unsafe group decrypt and plaintext safety failures quarantine instead of generic failed`.
   - Update or add cases for decrypt failure, missing decrypted file, plaintext size mismatch, plaintext MIME/signature rejection, and relay MIME mismatch.
   - Expected status for unsafe content is `integrity_failed`; expected local path updates are absent; any downloaded/decrypted temp file is deleted.
   - Keep transient bridge download failure as `failed`.

7. `test/features/groups/presentation/group_conversation_wired_test.dart`
   - Add `MD-012 retrying quarantined incoming media downloads only the targeted attachment`.
   - Seed a stored incoming message with one `integrity_failed` attachment and one untouched attachment.
   - Tap the new retry control.
   - With repaired fake bridge bytes, assert `media:download` and `blob:decrypt` run, the target attachment becomes `done`, the sibling stays unchanged, message status stays `delivered`, and there are no `group:publish`, `group:inboxStore`, or `retryFailedGroupMessage` effects.

8. `test/features/groups/presentation/group_conversation_wired_test.dart`
   - Add `MD-012 failed repair keeps media quarantined and clears unsafe file`.
   - Make retry return a hash mismatch or decrypt failure.
   - Assert the target row remains unavailable/`integrity_failed`, no displayable local path remains, the unsafe file is deleted, and no full-screen route opens.

9. `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
   - Add `MD-012 quarantined download failures are not picked up by incomplete upload retry`.
   - Seed `integrity_failed` and `failed` incoming/download rows plus an unrelated `upload_pending` outgoing row.
   - Assert only `upload_pending` is retried by `retryIncompleteGroupUploads`; download repair stays owned by the UI retry path.

10. `test/features/groups/integration/group_media_fanout_test.dart`
    - Add `MD-012 tampered recipient media renders unavailable and repaired retry displays verified media`.
    - Use the existing fake-network/media fan-out harness to tamper recipient download bytes, open the group row, verify unavailable/quarantine UI, repair the fake blob/descriptor, retry, and assert verified media displays only after `downloadStatus: done`.

Recommended but not required for first host-side closure:

- Add or extend `integration_test/foreground_group_push_drain_test.dart` with a representative foreground-drain unsafe media case if the executor changes foreground drain or notification/media-drain behavior.

### step-by-step implementation plan

1. Add the RED tests above in the smallest focused batches. Confirm they fail for the intended missing UI/retry/status behavior before production edits.
2. Add or centralize media status constants. The vocabulary for this session should be:
   - `pending`: download needed or retry scheduled.
   - `downloading`: active download/verification.
   - `done`: verified and displayable only if `GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(...)` is true for group media.
   - `failed`: transient download failure; retryable but not displayable.
   - `integrity_failed`: quarantined unsafe media; not auto-recovered, not displayable, retryable only by explicit user action after repair.
   - `upload_pending`: outgoing upload retry owner.
   - `upload_failed`: outgoing upload exhausted/terminal owner.
   - `upload_cancelled`: user-cancelled outgoing upload owner.
3. Add a small helper in `group_media_integrity_policy.dart` or a nearby media-status helper for `isQuarantinedGroupMedia`, `isUnavailableMedia`, and `isRetryableDownloadFailure`. Do not add a new DB enum.
4. Add a way to clear unsafe local paths when quarantining if the existing model/repo cannot do that safely. Prefer a narrow `clearLocalPath` support in `MediaAttachment.copyWith` plus either `saveAttachment(...)` or a focused repository helper; do not redesign the media table.
5. Normalize `downloadMedia(enforceGroupMediaPolicy: true)` outcomes:
   - Keep bridge-level download failure as `failed`.
   - Mark invalid descriptor, relay MIME mismatch, missing/malformed hash, hash mismatch, missing/invalid encryption metadata, decrypt failure, missing decrypted file, plaintext size mismatch, and plaintext MIME/signature failure as `integrity_failed`.
   - Delete encrypted/decrypted/temp/local files before returning failure.
   - Never call `updateLocalPath` unless all policy checks pass.
6. Harden display hydration in `GroupConversationWired._resolveAttachmentsForDisplay(...)`:
   - Preserve `integrity_failed` as non-auto-recovered.
   - Delete and clear unsafe local file references when local verification fails.
   - Keep `failed` eligible for existing transient retry if that behavior is still intentional.
7. Add per-attachment unavailable-media retry plumbing:
   - Extend `LetterCard` with a callback that identifies the message id and attachment id, separate from `onRetryFailedMedia`.
   - Extend `MediaGrid`, `MediaGridCell`, and `AudioPlayerWidget` to show unavailable/quarantine UI and an optional retry control for non-displayable media.
   - Use stable keys and semantics so tests can target the control.
8. Wire group UI retry in `GroupConversationScreen` and `GroupConversationWired`:
   - The retry must be available for incoming/read-only media download failures when repository, bridge, and file manager dependencies exist.
   - It must not require `canWrite`.
   - It must not expose outgoing resend/delete controls for incoming rows.
9. Implement `_onRetryUnavailableMedia(messageId, attachmentId)` or equivalent in `GroupConversationWired`:
   - Load the latest persisted attachment so a repaired descriptor can be used.
   - Delete or ignore any quarantined local file.
   - Set only the target attachment into a retrying state in the row.
   - Call `downloadMedia(... enforceGroupMediaPolicy: true)`.
   - Refresh only the target message's media map from repository state.
   - On success, display only if verified-display eligible.
   - On failure, keep the row unavailable/quarantined and show a safe snackbar if needed.
10. Keep outgoing failed-message media retry unchanged:
    - `onRetryFailedMedia` continues to call `retryFailedGroupMessage`.
    - `retryIncompleteGroupUploads` continues to own `upload_pending`.
    - New unavailable-media retry must not change message status or publish/inbox payloads.
11. Run focused tests, then broad group gates. If all RED tests pass on current code except UI text/keys, make only the missing UI/retry edits; do not manufacture protocol changes.
12. After implementation and gates pass, update the source matrix row, `test-inventory.md`, and breakdown ledger with exact MD-012 evidence. That closure-doc update belongs to execution/closure, not this planning-only turn.

### risks and edge cases

- A repaired descriptor may arrive through duplicate replay after the UI first marked the old descriptor quarantined; retry must reload current persisted state, not reuse stale widget state.
- `failed` currently auto-recovers on visible load. Unsafe failures must move to `integrity_failed` to avoid automatic retry loops and misleading UI.
- Read-only group/announcement readers still need download retry; do not tie this control to send permission.
- Local file paths may point at deleted or unsafe bytes. Display gating is necessary but not sufficient; quarantine should delete or clear unsafe paths when possible.
- Multi-attachment rows must retry only the tapped attachment and leave siblings untouched.
- Retry success must not reorder messages, mutate message status, clear reactions, or change quote context.
- Transient download failures should remain retryable without being mislabeled as malicious or integrity failures.
- Shared media widgets are used outside group chat; keep group verification behavior explicit through the existing `requireVerifiedContentHash` flag.
- Full-screen viewer and audio player must stay unreachable until the attachment is verified-display eligible.

### exact tests and gates to run

Focused direct tests:

```bash
flutter test --no-pub test/core/media/group_media_integrity_policy_test.dart
flutter test --no-pub test/features/conversation/application/download_media_use_case_test.dart
flutter test --no-pub test/shared/widgets/media/media_grid_cell_test.dart
flutter test --no-pub test/shared/widgets/media/audio_player_widget_test.dart
flutter test --no-pub test/features/conversation/presentation/widgets/letter_card_test.dart
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart
flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
```

Broad row-required gates:

```bash
flutter test --no-pub test/features/groups
flutter test --no-pub test/features/groups/integration
./scripts/run_test_gates.sh groups
git diff --check
```

Run only if execution changes gate classification docs, adds new integration files outside existing classifications, or updates inventory/matrix rows during closure:

```bash
./scripts/run_test_gates.sh completeness-check
```

Recommended device/simulator proof when fixtures are available or if foreground drain is touched:

```bash
flutter test --no-pub -d <device-id> integration_test/foreground_group_push_drain_test.dart
FLUTTER_DEVICE_ID=<device-id> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly
```

Go/relay tests are not required unless the executor changes Go or relay media behavior. If that happens, run the affected package-local media tests named by the diff.

### known-failure interpretation

- `SMOKE-GAP-05` is an evidence bundle label for media safety rows, not a runnable shell target.
- Missing `FLUTTER_DEVICE_ID` or `MKNOON_RELAY_ADDRESSES` blocks supplemental device/real-network proof; it is not an MD-012 product failure.
- A multiple-device error for `foreground_group_push_drain_test.dart` should be retried with `-d <device-id>` and treated as environment selection noise.
- Existing unrelated dirty-tree or aggregate failures must be recorded by exact file/test/error and separated from MD-012. Do not call MD-012 covered unless the direct MD-012 tests pass.
- A failure in existing MD-001 through MD-004 tests is a regression only if MD-012 changes touched the same media policy/display path.
- Passing data-level safety tests alone does not close MD-012 without the user-facing unavailable/quarantine UI and retry proof.

### done criteria

Implementation is done only when:

- RED tests for the MD-012 UI/retry/status contract fail before the production change or are documented as already passing with exact assertions.
- Focused tests pass after implementation.
- Unsafe media rows visibly show unavailable/quarantined state.
- Safe retry succeeds only after repaired media passes MIME, size, encrypted hash, decrypt, plaintext safety, and verified-display checks.
- Failed retry leaves media unavailable/quarantined and no local untrusted file is displayable.
- Incoming/read-only media retry is download-only and does not require write permission.
- Outgoing failed-message resend/delete behavior still passes.
- Broad group gates pass, or unrelated pre-existing failures are documented exactly.
- Source matrix row `MD-012` and `test-inventory.md` are updated with concrete test/gate evidence by the execution/closure step.

Planning is done when this file exists with verdict, evidence, tests, gates, closure bar, and scope guard.

### scope guard

Do not:

- redesign media protocol, chunk manifests, relay storage, or Go media paths;
- implement generic file attachments;
- add encrypted thumbnail/privacy product work;
- expand autoplay, retention, dedupe, removed-member, or simulator-matrix rows;
- tie download retry to group write permission;
- close MD-012 with a broken icon alone;
- mark the row covered without source matrix and inventory evidence updates after tests pass;
- use `retryFailedGroupMessage` or `retryIncompleteGroupUploads` for incoming/download-only media repair.

### accepted differences / intentionally out of scope

- `integrity_failed` is accepted as the quarantine status for this session. A new literal `quarantined` status is intentionally out of scope unless implementation evidence shows `integrity_failed` cannot express the needed UI and retry behavior.
- Device/real-relay proof is recommended supplemental evidence, not a prerequisite for first host-side closure unless execution touches foreground drain, real transport, or OS notification behavior.
- Existing group download retry can stay Flutter-owned. Go/relay media ACL and storage semantics are unchanged.
- Generic file support remains `MD-013`; chunk resume remains `MD-005`; thumbnail privacy remains `MD-007`; full simulator matrix remains `MD-014`.

### dependency impact

- `MD-014` simulator media/recovery matrix can reuse the final MD-012 unavailable/retry UI as part of its device proof.
- Future media retry or retention rows must preserve the distinction between outgoing upload resend, transient download retry, and unsafe media quarantine retry.
- Any later new media status must update the MD-012 tests so unsafe media cannot become displayable by falling through an unknown string branch.

## Reviewer pass

Reviewer verdict: sufficient as-is.

Checks:

- Required files and tests are named.
- RED tests lead before production changes.
- Status vocabulary is explicit and preserves prior rows.
- UI expectations are concrete: visible unavailable/quarantine text, stable retry key/semantics, no full-screen/audio/image render until verified.
- Retry behavior is bounded: per-attachment download retry only, no publish/inbox/resend.
- Gates and known-failure handling are explicit.
- Scope guard blocks protocol/chunk/generic-file/device-matrix drift.

No structural blocker was found.

## Arbiter pass

Structural blockers: none.

Incremental details:

- Exact UI copy can be adjusted during implementation, but tests must assert a stable unavailable/quarantine affordance and semantics.
- The implementation may choose a helper file name for media status constants, but the vocabulary must remain the one listed above.

Accepted differences:

- Reusing `integrity_failed` as quarantine status is accepted because it already exists and is already used by MD-003 display gating.
- Device/real-network proof remains supplemental for this row unless touched code requires it.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Final copy polish for the unavailable placeholder.
- Optional foreground/device proof if no foreground drain behavior changes.
- Row-named Go media tests unless Go/relay code is touched.

## Accepted differences intentionally left unchanged

- Existing outgoing failed-message resend and upload retry ownership stay unchanged.
- Existing group media protocol and relay storage stay unchanged.
- Prior media safety rows remain closed on their existing evidence and are not reopened.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/core/media/group_media_integrity_policy.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/audio_player_widget.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/core/media/group_media_integrity_policy_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/integration/group_media_fanout_test.dart`

## Why the plan is safe to implement now

The plan is safe because it targets the missing user-facing MD-012 contract at existing Flutter seams that already gate verified group media display. It keeps lower-level media safety rows intact, separates download retry from outgoing message resend/upload retry, names RED tests before code changes, and blocks unrelated media protocol, chunk, generic-file, thumbnail, Go/relay, and device-matrix work.

## Execution evidence

Execution fallback: local controller completed execution after the spawned implementation agent timed out during the focused UI batch. The controller reviewed the landed delta, fixed only MD-012-scoped regressions, and reran the row-required gates.

Implemented behavior:

- `integrity_failed` is the quarantine status for unsafe group media; transient bridge-level download failures remain `failed`.
- Unsafe group download validation paths quarantine descriptor, relay MIME, content hash, encryption/decrypt, missing decrypted file, plaintext size, and plaintext MIME/signature failures without leaving displayable local bytes.
- Group media rows show an explicit `Media unavailable` surface with stable `Retry unavailable media` semantics and per-attachment retry keys for visual and voice media.
- Incoming/read-only unavailable media retry is a download-only path through `downloadMedia(... enforceGroupMediaPolicy: true)`. The retry path refreshes the target attachment only and does not call outgoing message resend, `group:publish`, or `group:inboxStore`.
- Existing valid group video metadata rows still show the video overlay while local thumbnail/open behavior remains blocked until verified media is displayable.
- Existing outgoing failed-message resend/delete and incomplete-upload retry ownership remain separate from download repair.

Controller fixes after implementation-agent timeout:

- Adjusted MD-012 download test expectations so unsafe group media validation maps to `integrity_failed`, while bridge-level blob-not-found remains `failed`.
- Tightened `MediaGridCell` so video metadata overlays remain visible for safe descriptors, but thumbnails/taps still require verified display eligibility.
- Added encryption metadata to existing valid-media group screen fixtures.
- Replaced one async file write in the MD-012 wired failure test with synchronous setup I/O to avoid Flutter fake-async hangs.

Verification run after fixes:

```bash
flutter test --no-pub test/features/conversation/application/download_media_use_case_test.dart
flutter test --no-pub test/core/media/group_media_integrity_policy_test.dart test/features/conversation/application/download_media_use_case_test.dart test/shared/widgets/media/media_grid_cell_test.dart test/shared/widgets/media/audio_player_widget_test.dart
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "MD-012 failed repair keeps media quarantined and clears unsafe file"
flutter test --no-pub test/features/conversation/presentation/widgets/letter_card_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
flutter test --no-pub test/features/groups/integration
flutter test --no-pub test/features/groups
./scripts/run_test_gates.sh groups
git diff --check
```

All commands above passed. `./scripts/run_test_gates.sh groups` ran successfully after dependency resolution and package-version advisories. No Go or relay code was changed for MD-012, and no device/real-relay proof was available in this host-side session.
