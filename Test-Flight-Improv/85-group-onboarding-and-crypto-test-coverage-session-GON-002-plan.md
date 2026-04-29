# GON-002 Plan: Announcement New-Reader Media Onboarding

## real scope

- Add focused fake-network integration coverage for an announcement reader added after an initial admin post.
- Prove the new reader receives only post-join admin image, video, and voice/audio messages with intact media descriptors and download-trigger evidence.
- Do not alter announcement permissions, reactions, simulator coverage, real-network coverage, or real crypto in this session.

## closure bar

- `TC-5` has direct automated evidence in `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`.
- Bob is added after an initial admin announcement and does not receive that pre-join post.
- Bob receives post-join admin media for the currently supported shared group media path.
- Receiver-side media descriptors and `media:download` attempts are asserted.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-002`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-5 / A-7.
- Existing announcement behavior: `test/features/groups/integration/announcement_happy_path_test.dart`.
- Gate truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.

## session classification

`implementation-ready`

## exact problem statement

Existing fake/widget announcement tests prove admin send, read-only receive, reactions, and some announcement media/recovery pieces. They do not pin the onboarding boundary where a reader is added after a pre-existing admin post and then receives post-join admin media without receiving the pre-join post.

## files and repos to inspect next

- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/models/group_model.dart`

## existing tests covering this area

- `announcement_happy_path_test.dart` covers announcement create, admin text send, reader read-only receive, reader reaction, and failed-media controls.
- `group_resume_recovery_test.dart` covers announcement media/voice recovery pieces through fake-network/widget paths.
- `group_new_member_onboarding_test.dart` covers discussion new-member media, but not announcement reader onboarding.

## regression/tests to add first

- Add `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`.
- Use `GroupTestUser` plus `FakeGroupPubSubNetwork` and the bridge-backed group send path.
- Add the pre-join admin text, then add Bob as reader, then send image, video, and audio/voice media.

## step-by-step implementation plan

1. Add a test-local fake bridge that writes files for `media:download`.
2. Create an announcement group through the existing test helper with Alice as admin.
3. Start Alice and Bob listeners, send a pre-join admin announcement before Bob is a member, then add Bob.
4. Send post-join image, video, and audio/voice admin messages via `sendGroupMessageViaBridge`.
5. Wait for three receiver download attempts.
6. Assert Bob has no pre-join post and has all post-join media messages.
7. Assert Bob's media attachment rows preserve expected descriptor fields.
8. Classify the new direct suite without widening the frozen named gates.
9. Update source and closure docs only after the direct suite passes.

## risks and edge cases

- The test is fake-network/app-layer evidence, not real-network or real-crypto proof.
- Announcement reader write restrictions are already covered elsewhere; duplicating those assertions here would widen the session.
- Auto-download is asynchronous; wait on bridge command evidence or attachment status rather than sleeps alone.

## exact tests and gates to run

- `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
- `./scripts/run_test_gates.sh completeness-check` for classification, with unrelated pre-existing unmatched files recorded if present.

Run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` only if production group send/listener behavior changes; this session is expected to add a direct test and docs only.

## known-failure interpretation

- A failure in the new direct suite is a session blocker.
- The current completeness-check has an unrelated unmatched `integration_test/settings_background_choice_smoke_test.dart`; do not classify it as a GON-002 regression unless this session touches that file.

## done criteria

- New announcement direct suite exists and passes.
- TC-5 is updated from partial to covered for fake-network/app-layer announcement onboarding evidence.
- `21-announcement-reliability-closure-reference.md`, gate docs, and this breakdown ledger record the new evidence.

## scope guard

- Do not add simulator, real-network, real-crypto, push notification, reaction, or discussion fan-out work here.
- Do not change announcement write permissions unless the new onboarding test exposes a real bug.
- Do not widen the frozen `groups` gate.

## accepted differences / intentionally out of scope

- This closes the fake-network/app-layer part of A-7 only. Real-network simulator delivery and real-crypto proof remain owned by later sessions.
- The test uses audio/voice via the shared group media attachment path; recorder-specific UI behavior remains outside this session.

## dependency impact

- Later announcement simulator and recovery sessions may cite this as host-side onboarding evidence, but they still need receiver-visible simulator assertions.
