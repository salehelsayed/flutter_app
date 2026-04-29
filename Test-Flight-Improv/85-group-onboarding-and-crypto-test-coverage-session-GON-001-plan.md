# GON-001 Plan: Discussion New-Member Media Onboarding

## real scope

- Add focused fake-network integration coverage for a newly-added discussion-group member receiving post-join text, image, video, and voice messages.
- Preserve the existing no-backfill contract by proving the newly-added member does not receive pre-join messages.
- Assert received media descriptors and that the listener starts media-download work for incoming media.
- Do not change real crypto, simulator, announcement, reaction, quote, race, or gate wiring in this session.

## closure bar

- `TC-1`, `TC-2`, `TC-3`, `TC-4`, and `TC-6` have direct automated evidence in a doc-scoped discussion onboarding suite.
- The suite uses the existing group fake-network harness and bridge-backed group send path, not an invented transport.
- Bob receives only post-join messages and has one attachment row per post-join media message with the expected media type, MIME, size, and metadata.
- The receiver bridge observes `media:download` attempts for each incoming media attachment.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-001`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-1 through TC-4 and TC-6.
- Gate truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.
- Current code and tests beat stale prose if behavior differs.

## session classification

`implementation-ready`

## exact problem statement

Current discussion-group tests prove late-joiner future-only text delivery and send-side media payload behavior separately. They do not prove that a newly-added member receives post-join image, video, or voice messages through the group listener with media descriptors persisted and download behavior started.

## files and repos to inspect next

- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/fake_media_file_manager.dart`
- `test/core/bridge/fake_bridge.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

## existing tests covering this area

- `group_messaging_smoke_test.dart` already proves a late joiner receives only post-join text.
- `group_resume_recovery_test.dart` already proves several group/announcement media and inbox recovery paths, but not newly-added discussion-member media.
- `invite_round_trip_test.dart` preserves invite bootstrap no-backfill behavior.

## regression/tests to add first

- Add `test/features/groups/integration/group_new_member_onboarding_test.dart`.
- Add one compact scenario where Alice sends pre-join text, adds Bob, then sends post-join text, image, video, and voice via `sendGroupMessageViaBridge`.
- Assert Bob receives only the post-join messages and persists expected attachment descriptors.

## step-by-step implementation plan

1. Add a test-local fake bridge that writes bytes for `media:download` so listener auto-download can complete deterministically.
2. Add media fixture helpers for image, video, and audio `MediaAttachment` rows with stable IDs and metadata.
3. Build Alice and Bob with existing `GroupTestUser` and `FakeGroupPubSubNetwork`; give Bob the downloading fake bridge and a `FakeMediaFileManager`.
4. Start listeners, send a pre-join message before Bob is added, then add Bob.
5. Send post-join text and three media messages via `sendGroupMessageViaBridge`.
6. Assert Bob's repo has no pre-join message, has all four post-join messages, and attachment rows match image/video/audio descriptors.
7. Assert Bob's bridge command log contains one `media:download` call per post-join media item.
8. Run the direct test file, then the group gate if direct test passes.
9. Update the breakdown ledger and relevant docs only after the test lands.

## risks and edge cases

- Auto-download is fire-and-forget, so the test must wait on repository state or bridge command count rather than fixed long sleeps.
- The bridge-backed send path persists outgoing attachments under the resolved message id; receiver assertions should key off received message ids.
- Download completion requires a file to exist at the expected path; the fake download bridge should write content to avoid false failed-download noise.
- This session does not prove real crypto. It remains fake-network media onboarding coverage only.

## exact tests and gates to run

- `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

If the broader gate is blocked by unrelated pre-existing failures, record the failing suites and keep the direct test result as the session evidence.

## known-failure interpretation

- Existing unrelated dirty build/index artifacts are ignored.
- A failure in the new direct suite is a session blocker.
- A failure in an existing group-gate suite is a blocker only if it is caused by this session's changes; otherwise record it as pre-existing/unrelated with exact output.

## done criteria

- New direct suite exists and passes.
- The test covers post-join text/image/video/voice and pre-join exclusion for the newly-added member.
- Media descriptor and download-trigger assertions are present.
- Session ledger in the breakdown is updated from `not_started` to `accepted` with evidence.

## scope guard

- Do not alter product media behavior unless the new regression exposes a real bug needed for the test to pass.
- Do not add simulator, real-crypto, announcement, notification, reaction, quote, race, or CI-gate work in this session.
- Do not broaden the frozen `groups` gate unless required by a later closure/gate session.

## accepted differences / intentionally out of scope

- Fake-network/passthrough media coverage is acceptable for GON-001 but does not close TC-13, TC-17, TC-20, or any simulator sufficiency row.
- At least one media type is enough for the download-trigger mechanism if all media types share the same listener path, but this session still asserts image, video, and audio descriptors separately.

## dependency impact

- `GON-003`, `GON-004`, and `GON-008` may reuse the onboarding helper shape if needed, but they should refresh against the landed test before planning.
- If this plan changes away from `GroupTestUser.sendGroupMessageViaBridge`, later sessions should not assume media onboarding helpers exist.
