# New Group Members Can Send And Receive Group Text, Media, And Voice

## 1. Title and Type

- **Title:** New group members can send and receive group text, media, and voice
- **Issue type:** bug
- **Output doc path:** `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`

## 2. Problem Statement

A user added to a group should become a full participant for the supported group message types. After the add takes effect, they should be able to receive and send text, images, videos, and voice messages in the same way as other eligible group members.

The reported failure is narrower and high risk: a newly-added group member can see text messages, but cannot see a video shared in the group. From the user's perspective, the group appears joined and functional because text works, while media silently fails or disappears for that same conversation.

This spec treats that complaint as a regression class: membership, message delivery, media descriptor persistence, media download, and visible conversation rendering must all agree for newly-added members. Text-only success is not enough evidence that group media participation works.

## 3. Impact Analysis

- **Affected users:** people newly added to discussion groups, existing group members who share media after adding someone, and admins posting media to newly-added announcement readers under the current admin-only announcement contract.
- **When it appears:** after a membership change, especially when an existing member shares video, image, or voice content after the new member can already see text.
- **Severity:** high for group trust. A text message proving "you are in the group" conflicts with missing video or voice content from the same group.
- **Frequency:** not measurable from repo evidence alone. Existing coverage proves some app-layer media paths, but the current group simulator media matrix is still documented as partial, so this can escape if only descriptor-level tests pass.
- **Visible cost:** the receiver may assume the sender never shared the video, the sender may believe everyone received it, and retry or restart behavior may not clarify whether media is still pending, failed, or unavailable.

## 4. Current State

- `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md` records the named new-member onboarding scenarios as covered at the fake-network/app layer for post-join text, image, video, and voice. It also records the full group media simulator matrix as partial, especially for non-image media, retry, and restart visibility.
- `test/features/groups/integration/group_new_member_onboarding_test.dart` has direct app-layer coverage where Alice sends pre-join text, adds Bob, then sends post-join text, image, video, and voice. Bob receives only post-join messages, receives image/video/audio attachment descriptors, and triggers three media downloads.
- `test/features/groups/integration/group_membership_smoke_test.dart` proves a newly-added member can participate by sending text after bootstrap completes, and existing members receive that text. Report 89 extends the media side through `group_media_fanout_test.dart`.
- `test/features/groups/integration/group_media_fanout_test.dart` covers existing discussion members receiving image, video, and voice descriptors, including sender message-id preservation and receiver download behavior. GMAR-003 now tightens the reused Report 89 newly-added sender path so Bob's image, video, and voice reach Alice and Charlie with completed downloads, key epoch, attachment metadata, and exact per-recipient download calls.
- `test/features/groups/integration/announcement_new_reader_onboarding_test.dart` covers a newly-added announcement reader receiving post-join admin image, video, and voice media, while preserving no-backfill for pre-join announcement content. Report 89 now also proves that same reader cannot send text, image, video, or voice while read-only.
- Host-side retry and failed-media row behavior is covered by `retry_incomplete_group_uploads_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, `foreground_group_push_drain_test.dart`, and `group_conversation_screen_test.dart`, including a visible text-plus-video/voice/failed-media row assertion. This is not the same as a full user-visible simulator playback and restart matrix.
- Simulator evidence now includes `integration_test/group_new_member_media_simulator_proof_test.dart`, which passed on Android emulator `emulator-5554` and iPhone 17 simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` on `2026-04-29`. The proof covers newly-added-member incoming/outgoing text-plus-video/voice rows rendering, video opening in the full-screen viewer, voice reaching play/pause, and the same rows surviving a conversation-surface reopen.
- Likely affected current behavior spans the group send path, group listener, offline inbox drain, media attachment persistence, retry handling, and group conversation rendering. Relevant evidence areas include `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, and `lib/features/conversation/domain/models/media_attachment.dart`.
- Existing constraints that must remain true: newly-added members should not receive pre-join history unless product policy changes, removed or dissolved group access must stay blocked, duplicate live/inbox delivery must not create duplicate rows, and announcement readers should receive eligible admin media without gaining compose permissions they do not have.

## 4a. Report 89 Rollout Result

- **Status on 2026-04-29:** `accepted_with_explicit_follow_up`.
- Host-side app-layer coverage now proves newly-added discussion members receive post-join text, image, video, and voice without pre-join backfill, and a newly-added discussion member can send image, video, and voice to every eligible existing member after bootstrap. GMAR-003 strengthens this with completed-download assertions for each eligible recipient rather than descriptor-only or one-recipient completion.
- Host-side visible/recovery coverage now proves the group conversation surface renders text plus video, voice, and failed media states, while inbox drain, retry, foreground push drain, and duplicate suppression keep representative media rows durable and non-duplicated.
- Announcement coverage now proves newly-added readers receive post-join admin image, video, and voice while remaining read-only for text, image, video, and voice sends. Current production code is admin-only for announcement sends; no writer-role media claim is made.
- Verification passed on 2026-04-29: focused direct suites for new-member onboarding, media fan-out, announcement new-reader onboarding, group conversation rendering, inbox/retry recovery, foreground group push drain on macOS, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, and `./scripts/run_test_gates.sh completeness-check`.
- Simulator proof passed on 2026-04-29 using Android emulator `emulator-5554`: `flutter test -d emulator-5554 integration_test/group_new_member_media_simulator_proof_test.dart`, `flutter test -d emulator-5554 integration_test/media_message_journey_e2e_test.dart`, `flutter test -d emulator-5554 integration_test/media_stable_id_smoke_test.dart`, and `flutter test -d emulator-5554 integration_test/foreground_group_push_drain_test.dart`.
- iOS simulator proof passed on 2026-04-29 using iPhone 17 simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`: `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/group_new_member_media_simulator_proof_test.dart`, `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/media_message_journey_e2e_test.dart`, `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/media_stable_id_smoke_test.dart`, and `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/foreground_group_push_drain_test.dart`.
- Explicit follow-up: true process-kill restart persistence, broader paired-simulator real-stack coverage, and real-device/TestFlight device-lab playback remain residual evidence. The current rollout closes the host-side regression class and adds Android plus iPhone 17 simulator render/play/reopen proof without claiming the broader TestFlight matrix.

## 5. Scope Clarification

In scope:

- Newly-added discussion group members can receive post-join text, image, video, and voice messages from existing eligible members.
- Newly-added discussion group members can send text, image, video, and voice messages after their membership is active, and existing eligible members receive them.
- Sender and receiver conversation surfaces show truthful message rows, media descriptors, download state, render/playback affordances, and retry state for the supported media types.
- The reported bug shape is covered directly: a new member who can see post-join text must also see a post-join video sent through the same group.
- Multiple newly-added members in the same group add sequence receive the same post-join media behavior. GMAR-003 now proves Bob and Charlie independently download the same post-join image, video, and voice while pre-join text/media remains excluded at the host/app layer.
- Announcement groups remain covered where role rules allow it: newly-added readers receive eligible admin media under the current product contract, and read-only users cannot send. No writer-role announcement media claim is made unless the product policy changes.
- Foreground/background, notification-open, offline inbox, retry, and restart behavior are in scope when they affect whether the new member visibly receives or can recover group media.

Non-goals:

- No requirement to backfill text, images, videos, or voice messages sent before the user joined.
- No new product decision about unsupported media types, maximum media sizes, codecs, file conversion, compression, or transcoding.
- No change to announcement read/write role policy.
- No requirement to alter cryptographic design, transport architecture, storage architecture, or media upload architecture.
- No manual-only acceptance path as the primary proof.

Accepted ambiguities for later work:

- The exact supported video codecs and container variants are whatever the product already claims to support.
- GIFs and generic file attachments are not included unless they are already treated as supported group media in the existing product contract.
- Simulator acceptance should prove the visible user outcome with representative supported media: row appears, media state is truthful, and media can be rendered or played through the app surface.
- OS-level push coverage can stay narrower than the full media matrix if foreground/background notification behavior is already proven by an adjacent group-message acceptance path.

## 6. Test Cases

### Happy Path

- **NGM-001: Newly-added member receives post-join text.** After an existing member sends text before the add, the new member joins and receives only text sent after their membership is active. Existing coverage: `group_new_member_onboarding_test.dart` and Report 85 already cover this at the app layer.
- **NGM-002: Newly-added member receives post-join image.** The image row is visible to the new member, includes the expected attachment identity and image metadata, downloads successfully, and remains visible when the group conversation is reopened. Existing coverage: app-layer descriptor and download trigger exist; simulator visibility remains part of the broader media gap.
- **NGM-003: Newly-added member receives post-join video.** The video row is visible to the new member, includes video MIME type, size, width, height, and duration, downloads successfully, exposes the expected video playback affordance, and remains visible after reopening the conversation. Existing coverage: app-layer descriptor/download trigger plus Android and iPhone 17 simulator render/play/reopen proof now exist; process-kill restart remains residual.
- **NGM-004: Newly-added member receives post-join voice.** The voice row is visible to the new member, includes audio MIME type, duration, and waveform when available, downloads successfully, exposes the expected playback affordance, and remains visible after reopening the conversation. Existing coverage: app-layer descriptor/download trigger plus Android and iPhone 17 simulator playback/reopen proof now exist; process-kill restart remains residual.
- **NGM-005: Newly-added member sends text after joining.** Existing group members receive the new member's post-join text exactly once, with the correct sender identity and ordering relative to nearby messages. Existing coverage: `group_membership_smoke_test.dart` covers newly-added-member text participation after bootstrap.
- **NGM-006: Newly-added member sends image after joining.** The sender sees a truthful outgoing image row, existing members receive the image row and metadata, the media downloads or renders according to normal product behavior, and retry state is visible if upload or download fails.
- **NGM-007: Newly-added member sends video after joining.** The sender sees a truthful outgoing video row, existing members receive the video row and metadata, the video downloads and presents a playback affordance, and the row survives app restart.
- **NGM-008: Newly-added member sends voice after joining.** The sender sees a truthful outgoing voice row, existing members receive the voice row and metadata, playback is available when download completes, and the row survives app restart.
- **NGM-009: Multiple newly-added members converge on post-join media.** When Bob and Charlie are added before the same post-join image, video, or voice message, both new members receive the same visible message content and media metadata without duplicate rows.
- **NGM-010: Add-then-immediate-media boundary is deterministic.** If an existing member sends media immediately after the add becomes active, the newly-added member either receives it exactly once or the product shows a clear, consistent boundary that matches the established no-backfill policy. Existing coverage pins the text boundary at the app layer; media needs the same observable confidence.
- **NGM-011: Announcement reader receives post-join admin media.** A newly-added announcement reader receives admin text, image, video, and voice content after joining, but does not receive pre-join content. Existing coverage: `announcement_new_reader_onboarding_test.dart` covers app-layer image, video, and voice descriptors.
- **NGM-012: Role-eligible announcement sender media still works.** An announcement admin can send image, video, and voice content to newly-added readers with the same visible media behavior expected in discussion groups. No writer-role claim is made under the current admin-only product contract.

### Edge Cases

- **NGM-013: No pre-join media backfill.** A newly-added member does not receive text, image, video, or voice messages sent before their membership was active, even if they later receive post-join media correctly.
- **NGM-014: Text success does not mask media failure.** If the new member receives post-join text but an image, video, or voice attachment cannot be downloaded or rendered, the conversation shows a truthful pending, failed, or retryable media state instead of silently omitting the media.
- **NGM-015: Offline inbox recovery includes media.** If the new member is offline when post-join text and media are sent, opening the app later drains the eligible group inbox and shows text, image, video, and voice content exactly once.
- **NGM-016: Foreground push drain includes media.** If a foreground group notification corresponds to a post-join media message for the new member, opening or refreshing the conversation shows the media row and preserves the attachment metadata. Existing coverage covers a targeted group image inbox path; video and voice remain the higher-risk media types.
- **NGM-017: Download retry is visible and recoverable.** A failed receiver-side image, video, or voice download for the newly-added member shows an observable failed or retryable state and can recover without creating a duplicate message.
- **NGM-018: Upload retry is visible and recoverable for new-member sends.** A newly-added member sending image, video, or voice content sees a truthful outgoing state during upload failure, retry, and eventual success or terminal failure.
- **NGM-019: App restart preserves pending and completed media.** After app restart, newly-added members still see received and sent text, image, video, and voice rows with accurate media status and playable completed media.
- **NGM-020: Duplicate live and inbox delivery does not duplicate media.** If a post-join media message arrives through both live delivery and inbox recovery, the newly-added member sees one message row and one attachment set.
- **NGM-021: Removed-before-send user does not receive media.** If a user is added and then removed before media is sent, they do not receive text, image, video, voice, or notification access for that later content.
- **NGM-022: Removed-after-send access stays consistent.** If a newly-added member legitimately receives media before removal, the post-removal state follows the existing group retention and access policy without leaking later media.
- **NGM-023: Announcement readers remain read-only.** A newly-added announcement reader can receive eligible post-join media but cannot send text, images, videos, or voice messages unless their role changes to one that allows posting.
- **NGM-024: Media metadata remains stable across sender and receivers.** Message rows for image, video, and voice preserve the expected attachment identity, media type, MIME type, size, duration, dimensions, and waveform metadata where applicable.

### Regressions To Preserve

- **Bug regression: new member sees text but misses video.** A newly-added member who receives a post-join text message must also visibly receive a post-join video sent by an existing member in the same active group. The case fails if the video row is absent, has no attachment, cannot progress beyond an untruthful state, disappears after reopening, or lacks the expected video playback affordance.
- **No-backfill regression.** Strengthening media coverage must not cause newly-added members to receive pre-join text, image, video, or voice messages.
- **Existing-member fan-out regression.** Existing members must continue receiving image, video, and voice media sent by other existing members. Existing coverage: `group_media_fanout_test.dart`.
- **New-reader announcement regression.** Newly-added announcement readers must keep receiving post-join admin media while preserving the existing no-backfill contract.
- **Read-only role regression.** Announcement readers must not gain compose access for text, images, videos, or voice messages as a side effect of media receive coverage.
- **Removal and dissolved-group regression.** Users removed from a group, or blocked by dissolved-group state, must not regain access through media retry, inbox drain, notification open, or conversation restart.
- **Retry UI regression.** Existing failed outgoing group media rows must remain truthful and retryable according to the current product behavior.
- **Duplicate prevention regression.** Existing duplicate suppression across live delivery, inbox drain, and repeated foreground pushes must still prevent duplicate text or media rows.

### Acceptance Evidence Layers

- **Integration evidence is required** for newly-added members receiving and sending text, image, video, and voice messages because the outcome spans membership state, message delivery, media descriptors, and persistence.
- **Smoke evidence is required** for the end-to-end user journey of add member, send media in both directions, reopen the group, and confirm stable visible rows.
- **Simulator evidence is required** for the reported video failure and the broader media matrix because the key acceptance depends on mobile conversation rendering, download state, restart behavior, and playback affordances that descriptor-only tests do not fully prove.
- **Unit evidence is useful where deterministic rules are involved,** such as no-backfill boundaries, read-only announcement sending denial, removed-member denial, and duplicate suppression.
