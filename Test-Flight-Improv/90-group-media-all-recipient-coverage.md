# Group Media Reaches Every Eligible Recipient

## 1. Title and Type

- **Title:** Group media reaches every eligible recipient
- **Issue type:** bug
- **Output doc path:** `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- **Closure status:** closed on `2026-05-03` by GMAR-005 final acceptance/recovery after all required final gates passed.

## 2. Problem Statement

People in an invited group expect every active member to receive the same eligible group messages and media. If one member can read only the creator's messages, or another member cannot see group media that others can see, the group appears partially broken even when the conversation still looks active.

The reported failures are:

- A group invitee can see messages from the creator but cannot read messages sent by other members.
- One group member cannot see media posted in the group while other members can.

From the user's perspective, this creates a silent split-brain group: different members believe they are participating in the same conversation, but their visible timelines diverge.

## 3. Impact Analysis

- **Affected users:** group creators, invited members, and any active member sending text or media to a group with more than two participants.
- **When it appears:** after group creation and invites, especially when non-creator members send messages or when media is sent to multiple recipients.
- **Severity:** high for group trust. Users cannot tell whether the sender failed, the receiver is excluded, media is still downloading, or the group state is inconsistent.
- **Frequency:** not measurable from repo evidence alone. Existing host tests now cover text, existing-member app-layer media download parity, newly-added/non-creator app-layer media parity, and GMAR-004 user-visible media render/playback/reopen/retry/offline/duplicate proof. GMAR-005 completed the final direct-suite, simulator, two-simulator smoke, named-gate, broad Flutter, Go, completeness, and diff-check sweep.
- **Visible cost:** missed messages, absent video/image/voice rows, confusing retry expectations, and mismatched conversations between friends testing the same group.

## 4. Current State

- `test/features/groups/integration/group_messaging_smoke_test.dart` has a 4-user round-robin case where admin, Bob, Charlie, and Diana each send one text message and every participant must receive all three incoming messages from the others. GMAR-001 tightened this case on `2026-05-02` to assert each recipient's exact incoming text set, sender peer IDs, sender usernames, and exact-once appearance. This is accepted app-layer coverage for the text complaint shape.
- `test/features/groups/integration/group_media_fanout_test.dart` covers Alice sending image, video, and voice to Bob and Charlie. GMAR-002 tightened this on `2026-05-02` so both eligible non-sender recipients must independently complete downloads for all three media types with matching row/message identity and attachment metadata. The same suite now proves one recipient's forced image download failure remains visible as failed/non-done while the other recipient stays downloaded.
- GMAR-003 tightened `test/features/groups/integration/group_media_fanout_test.dart` further on `2026-05-02`: media sent by a newly-added Bob now reaches Alice and Charlie with completed downloads, and media sent by an existing non-creator Charlie now reaches Alice and Bob with completed downloads. Both paths assert exact sender identity, sender message ids, key epoch, attachment metadata, and exactly three `media:download` calls per eligible non-sender recipient.
- GMAR-003 also added a multi-new-member media proof to `test/features/groups/integration/group_new_member_onboarding_test.dart`: Bob and Charlie independently download the same post-join image, video, and voice from Alice while pre-join text, image, video, and voice remain absent with no pre-join attachment rows, pending downloads, or pre-join media download calls.
- GMAR-004 accepted the visible media/recovery layer on `2026-05-02`: the configured simulator proof now passes on `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` after fixing stale fixture metadata, host presentation tests pin visible video/voice/failed media rows and reopen hydration, and the offline inbox suite pins signed replay duplicate enrichment without duplicate rows or attachment sets.
- `go-mknoon/integration/media_test.go` now covers group media upload/download with the sender, two authorized non-sender members, and one outsider. GMAR-002 tightened `TestRelayGroupMediaUploadDownload` on `2026-05-02` so both authorized non-senders independently download the same group blob byte-for-byte while the outsider remains rejected.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` gathers current group member peer IDs as allowed media recipients for ordinary media and voice sends. The user-visible concern is whether every eligible recipient actually receives, downloads, and renders the resulting media.
- `integration_test/group_new_member_media_simulator_proof_test.dart` proves visible video and voice rows on the configured simulator conversation surface. The earlier failure where the proof expected two `VideoThumbnailOverlay` widgets and found zero is now treated as stale fixture metadata fixed by GMAR-004, not an open render failure.
- `scripts/run_test_gates.sh` keeps `group_media_fanout_test.dart`, `group_new_member_onboarding_test.dart`, `group_new_member_media_simulator_proof_test.dart`, and `media_message_journey_e2e_test.dart` outside the frozen `groups` gate as optional/manual tests. A normal group gate can therefore pass without proving the media failure class reported here.
- GMAR-005 keeps those optional/manual suites outside the frozen named gates, but ran them directly for final Report 90 acceptance. The same final pass also ran the GMAR-relevant two-simulator routing/group smoke and foreground group push smoke with relay addresses, the device-pinned `all` gate, completeness check, broad `flutter test`, Go module tests, and `git diff --check`.
- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md` documents broad new-member media participation and is now refined by GMAR-003 all-recipient completed-download assertions plus GMAR-004 configured visible-media proof. GMAR-005 closes the remaining Report 90 gate-confidence risk; broader device-lab or announcement matrices remain separate confidence layers, not open Report 90 blockers.

## 5. Scope Clarification

In scope:

- Existing and newly-added group members receive eligible post-join text messages from every other active member, not only from the creator.
- Existing and newly-added group members receive, download, and visibly render eligible post-join image, video, and voice messages sent by any active sender.
- Multiple eligible non-sender recipients receive the same media message with consistent row identity, attachment metadata, download state, and playback or preview affordance.
- The group test gate or an explicitly named acceptance path gives reliable signal for the reported text/media split-brain failures.
- The conversation surface shows truthful pending, failed, retryable, downloaded, and playable states when media cannot immediately render.

Non-goals:

- No new product decision about pre-join history backfill.
- No expansion of supported media types, codecs, file sizes, compression, or transcoding.
- No change to announcement read/write policy.
- No change to group cryptographic design, transport architecture, or media storage architecture.
- No manual-only acceptance path as the sole proof for this regression class.

Accepted ambiguities for later work:

- The exact delivery order around add/send boundaries should follow the existing product contract and no-backfill policy.
- Simulator evidence can use representative supported image, video, and voice media rather than every possible media encoding.
- Broader real device or TestFlight proof can remain a separate confidence layer unless a future release process explicitly requires it.

## 6. Test Cases

### Happy Path

- **GMAR-001: Four active members all receive text from all others.** In a group with a creator and at least three invitees, each member sends a text message and every other member sees that message exactly once with the correct sender identity. Accepted on `2026-05-02` through the tightened `group_messaging_smoke_test.dart` round-robin case and the green `groups` gate.
- **GMAR-002: Existing-member image reaches every recipient.** When one active member sends an image to a group with at least two other active members, every eligible non-sender sees the image row, matching attachment identity and metadata, completed download state, and visible image preview.
- **GMAR-003: Existing-member video reaches every recipient.** When one active member sends a video to a group with at least two other active members, every eligible non-sender sees the video row, matching attachment identity and metadata, completed download state, and a video playback affordance.
- **GMAR-004: Existing-member voice reaches every recipient.** When one active member sends a voice message to a group with at least two other active members, every eligible non-sender sees the voice row, matching duration and waveform metadata when available, completed download state, and a voice playback affordance.
- **GMAR-005: Newly-added multiple members receive the same post-join media.** When Bob and Charlie are added before Alice sends image, video, and voice messages, both Bob and Charlie see the same eligible post-join media rows without receiving pre-join history.
- **GMAR-006: Newly-added member media sends reach all existing members.** When a newly-added member sends image, video, and voice after membership is active, every existing eligible member sees the media rows and can render or play them.
- **GMAR-007: All authorized media recipients can download the same group blob.** When group media is authorized for the sender and at least two non-sender recipients, each authorized recipient can independently download the same media content while an outsider cannot.
- **GMAR-008: Conversation reopen preserves all-recipient media parity.** After media appears for multiple recipients, reopening the group conversation preserves the same visible rows, attachment metadata, and completed media state for each recipient.

### Edge Cases

- **GMAR-009: Text success does not mask media failure.** If a member receives post-join text but an eligible media attachment cannot download or render, the conversation shows an observable pending, failed, or retryable media state instead of silently omitting the media row.
- **GMAR-010: One recipient failure is not hidden by another recipient success.** A test fails if Bob can download/render media but Charlie cannot, or if Charlie can download/render media but Bob cannot, when both are eligible group recipients.
- **GMAR-011: Non-creator sender parity.** Messages and media sent by Bob or Charlie are visible to the creator and every other eligible member, not only messages sent by the creator.
- **GMAR-012: No pre-join media backfill.** Strengthening all-recipient media proof must not cause newly-added members to receive text, image, video, or voice messages sent before their membership became active.
- **GMAR-013: Offline recipient recovery includes media.** If one eligible recipient is offline when group media is sent, later recovery shows the same media row and truthful media state without duplicating the message for recipients who already saw it live.
- **GMAR-014: Duplicate live and inbox paths do not duplicate media rows.** If a media message is observed through both live delivery and recovery, each eligible recipient sees one row and one attachment set.
- **GMAR-015: Removed member exclusion stays intact.** A member removed before media is sent does not receive later text or media through live delivery, inbox recovery, notification open, retry, or conversation reopen.
- **GMAR-016: Failed media state is recoverable.** A temporary download failure for one eligible recipient remains visible and recoverable without requiring the sender to repost the media.

### Regressions To Preserve

- **Bug regression: member sees only creator messages.** In a group with at least three active members, an invitee must see messages from the creator and from every other active non-creator sender. The case fails if the invitee sees only creator-authored messages.
- **Bug regression: one member misses media that others can see.** In a group with at least three active members, every eligible non-sender must visibly receive and render the same image, video, and voice messages. The case fails if one recipient has no media row, descriptor-only state where completed media is expected, missing preview/playback affordance, or media that disappears after reopening while another recipient succeeds.
- **Existing text fan-out regression.** The existing 4-user text round-robin behavior must continue to pass while media coverage is strengthened.
- **No-backfill regression.** Newly-added members must continue to be excluded from pre-join text and media unless the product policy changes.
- **Outsider rejection regression.** Users who are not eligible group members must remain unable to download group media.
- **Gate confidence regression.** The named group acceptance path must not report green while the all-recipient media parity proof is absent, skipped, optional-only, or failing.
- **Full-suite confidence regression.** This work must not close on focused media tests alone. After the targeted all-recipient media proof passes, the final verification step must run the repo's full available test sweep so unrelated group, feed, transport, persistence, and presentation regressions are not missed.

### Acceptance Evidence Layers

- **Integration evidence is required** because the user-visible outcome spans group membership, group message delivery, media descriptors, persistence, download state, and conversation rendering.
- **Smoke evidence is required** for the creator-invites-members journey because the reported failures appear during normal friend-testing use rather than isolated helper behavior.
- **Simulator evidence is required** for video, voice, conversation reopen, and media playback affordances because descriptor-only host tests do not prove the user-visible mobile surface.
- **Unit evidence is useful** for deterministic boundaries such as no-backfill, removed-member exclusion, outsider media rejection, and duplicate suppression.

### Final Full-Suite Gate

The last step before closing this spec must be a full regression sweep, not only the focused GMAR tests.

Required final evidence:

- Run `./scripts/run_test_gates.sh all`.
- Run `./scripts/run_test_gates.sh completeness-check`.
- Run every direct optional/manual media or simulator suite used as GMAR evidence, including at minimum `test/features/groups/integration/group_media_fanout_test.dart`, `test/features/groups/integration/group_new_member_onboarding_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, and `integration_test/media_message_journey_e2e_test.dart`.
- Run any broader repo-level full-suite command that exists at implementation time if it covers tests outside `./scripts/run_test_gates.sh all`.

The spec is not closed if the final full-suite sweep is skipped, partially run without explanation, or fails with an untriaged regression. Any infrastructure-only or fixture-blocked failure must be recorded with the exact command, failing test, device or host context, and why it is not caused by the GMAR changes.

## 7. Session Evidence Ledger

### GMAR-001 - Text Fan-out Evidence (`2026-05-02`)

- **Status:** accepted for text fan-out only.
- **Test update:** `test/features/groups/integration/group_messaging_smoke_test.dart` now asserts Admin, Bob, Charlie, and Diana each receive the three expected incoming text messages exactly once with matching `senderPeerId` and `senderUsername`.
- **Focused proof:** `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name '4 users: round-robin messaging'` passed with `00:00 +1: All tests passed!`.
- **Named gate:** `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:08 +103: All tests passed!`.
- **Boundary:** GMAR-001 does not close all-recipient media parity by itself. GMAR-002, GMAR-003, and GMAR-004 now carry the accepted app-layer and visible-media evidence for their scoped media sessions, and GMAR-005 closed final acceptance. Descriptor-only, one-recipient, sender-side-only, optional-only, or stale failing-simulator evidence must not be used to replace this final closure bar.

### GMAR-002 - Existing-Member Media Download Parity (`2026-05-02`)

- **Status:** accepted for existing-member app-layer download parity and Go blob authorization proof only.
- **Flutter production change:** `download_media_use_case.dart` scopes in-flight media download dedupe by bridge, media attachment repository, and media file manager identity before `groupId|blobId|mime`, preserving same-owner dedupe while preventing one recipient's local download future from satisfying another recipient's repository/path.
- **Test update:** `group_media_fanout_test.dart` now requires Bob and Charlie to each complete image, video, and voice downloads from Alice with matching incoming sender message IDs, attachment IDs, MIME/media metadata, download status `done`, non-null local paths, and exactly three independent `media:download` calls per recipient. The suite also adds a one-recipient failure proof where Charlie's forced image download failure remains `failed`/non-done without hiding Bob's successful downloads.
- **Go proof:** `go-mknoon/integration/media_test.go` now proves two authorized non-sender members independently download the same group blob byte-for-byte and an outsider remains rejected.
- **Verification:** focused Flutter proof passed with `00:00 +1: All tests passed!`; full direct Flutter suite passed with `00:00 +6: All tests passed!`; tagged Go integration passed with `PASS` / `ok github.com/mknoon/go-mknoon/integration 1.815s`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:12 +103: All tests passed!`; `git diff --check` passed.
- **Boundary:** GMAR-002 does not close newly-added/non-creator media parity, visible preview/playback/reopen/retry/offline/duplicate simulator coverage, or final full-suite/gate reconciliation by itself. GMAR-003 and GMAR-004 later accepted those media layers, and GMAR-005 closed final full-sweep evidence.

### GMAR-003 - Newly-Added and Non-Creator Media Parity (`2026-05-02`)

- **Status:** accepted for host/app-layer completed-download parity at the membership boundary.
- **Test update:** `group_new_member_onboarding_test.dart` now proves Bob and Charlie, both newly added before Alice's post-join sends, independently download the same post-join image, video, and voice rows with matching sender message ids, Alice sender identity, epoch, attachment metadata, `done` download status, non-null local paths, and exactly three `media:download` calls per recipient. The same proof sends pre-join text, image, video, and voice before Bob/Charlie are active and asserts neither new member receives those rows, attachment records, pending downloads, or pre-join media download calls.
- **Sender parity update:** `group_media_fanout_test.dart` now requires media sent by newly-added Bob to reach Alice and Charlie with completed downloads, and media sent by existing non-creator Charlie to reach Alice and Bob with completed downloads. Both tests assert exact-once rows, sender identity, sender message ids, key epoch, attachment metadata, and exact per-recipient download calls.
- **Removed-member preservation:** the full `group_media_fanout_test.dart` suite remained green, preserving the MD-011 proof that a removed member receives no future media descriptor, message, media row, pending download, download/decrypt call, subscription, or future key while the remaining member receives/downloads future media.
- **Verification:** focused multi-new-member proof passed with `00:00 +1: All tests passed!`; focused newly-added sender proof passed with `00:00 +1: All tests passed!`; focused existing non-creator sender proof passed with `00:00 +1: All tests passed!`; full `group_new_member_onboarding_test.dart` passed with `00:01 +7: All tests passed!`; full `group_media_fanout_test.dart` passed with `00:01 +7: All tests passed!`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:08 +103: All tests passed!`; `git diff --check` passed.
- **Boundary:** GMAR-003 does not close visible preview/playback/reopen/retry/offline/duplicate simulator behavior or final full-suite/gate reconciliation by itself. GMAR-004 later accepted the visible/recovery layer, and GMAR-005 closed final full-suite/gate reconciliation.

### GMAR-004 - Visible Media Recovery, Retry, Inbox, Duplicate, and Reopen Behavior (`2026-05-02`)

- **Status:** accepted for configured visible media/recovery proof.
- **Fixture/test update:** `integration_test/group_new_member_media_simulator_proof_test.dart` now supplies valid content hashes and encryption metadata for representative video and voice fixtures, preserving group media integrity policy while restoring the expected `VideoThumbnailOverlay` and `AudioPlayerWidget` affordances.
- **Host visible-state proof:** `group_conversation_screen_test.dart` keeps text plus video, voice, and failed media rows visible across rebuild/reopen-style rendering, while `group_conversation_wired_test.dart` proves reopen hydration preserves completed, pending, and failed media metadata without duplicate rows and keeps unavailable-media retry wiring scoped to the attachment repair path.
- **Offline/duplicate proof:** `drain_group_offline_inbox_use_case_test.dart` proves duplicate live plus signed inbox replay enriches sparse video/voice media once. The fix pass signed legacy fake replay fixtures at the test fake bridge boundary so the full drain suite stays green without weakening production signed replay or media integrity policy.
- **Verification:** configured simulator proof passed on `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`; `group_conversation_screen_test.dart`, `group_conversation_wired_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, retry preservation suites, `group_media_fanout_test.dart`, `group_new_member_onboarding_test.dart`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check` (`712/712`), and `git diff --check` passed.
- **Boundary:** GMAR-004 does not run or close `./scripts/run_test_gates.sh all`, `media_message_journey_e2e_test.dart`, broader discussion/announcement media matrix reconciliation, or the final Report 90 program verdict. GMAR-005 now owns and closes the Report 90 final gate/full-suite scope; broader announcement/device-lab matrices remain separate work if required by a future release process.

### GMAR-005 - Final Gate Confidence and Full-Suite Recovery (`2026-05-03`)

- **Status:** accepted; final Report 90 program verdict is closed.
- **Recovery update:** GMAR-005 was upgraded from acceptance-only to fix-authorized final acceptance/recovery. Repo-owned production code, tests, fixtures, scripts, and docs were fixed only where required by failing final gates, including the prior command 5 `missing_media_encryption_metadata`, command 6 stable-ID/all-gate failure, command 8 broad host-suite compile/load failures, and later two-simulator smoke orchestration gaps.
- **Final proof:** all required commands passed in the final rerun: `flutter devices --machine`; the two direct host GMAR suites; the configured-simulator `group_new_member_media_simulator_proof_test.dart`, `media_message_journey_e2e_test.dart`, and `media_stable_id_smoke_test.dart`; the GMAR-relevant routing/group and foreground group push two-simulator smoke commands with relay addresses; `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh all`; `./scripts/run_test_gates.sh completeness-check`; broad `flutter test`; `cd go-mknoon && go test ./...`; and `git diff --check`.
- **Maintenance boundary:** optional/manual GMAR suites remain direct evidence rather than frozen named-gate members. Reopen Report 90 only if a real regression breaks all-recipient text/media parity, configured visible media/recovery proof, or the final gate confidence contract.
