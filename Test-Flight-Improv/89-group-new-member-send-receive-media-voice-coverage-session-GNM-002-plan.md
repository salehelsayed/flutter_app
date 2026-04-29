# GNM-002 Plan - Newly-Added Discussion Member Sends Image Video And Voice

## real scope

- Add focused host-side coverage for a newly-added discussion member sending image, video, and voice after membership/bootstrap is active.
- Assert existing eligible members receive each media row exactly once with stable sender message id and media metadata.
- Assert the new member's outgoing rows and attachments are persisted.
- Do not change product behavior unless the test exposes a real send-path defect.

## closure bar

- A direct test proves a newly-added member can send image, video, and voice through `sendGroupMessageViaBridge`.
- Existing members receive image/video/audio descriptors with identity, MIME/media type, dimensions/duration/waveform where present, and download completion for receivers using the fake download bridge.
- The sender's outgoing rows exist and have corresponding persisted attachments.
- The direct test passes.

## source of truth

- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`

Current tests and code beat stale prose.

## session classification

`implementation-ready`

## exact problem statement

Existing evidence covers newly-added-member text sends and existing-member media fan-out, but not a newly-added member sending image, video, and voice after joining. The gap can let the app prove "Bob joined" and "Alice media works" without proving Bob's media send path works for established group members.

## files and repos to inspect next

- `test/features/groups/integration/group_media_fanout_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`

## existing tests covering this area

- `group_membership_smoke_test.dart` proves new-member text send after bootstrap.
- `group_media_fanout_test.dart` proves existing-member image/video/voice fan-out.
- `group_new_member_onboarding_test.dart` proves newly-added-member receive-side image/video/voice descriptors.

## regression/tests to add first

- Add a focused `group_media_fanout_test.dart` case where Bob is added after Alice and Charlie, receives bootstrap key state, sends image/video/voice, and Alice/Charlie receive exactly one matching row for each media type.

## step-by-step implementation plan

1. Add a local key helper if needed so Bob can send as a non-admin after bootstrap.
2. Add the new fan-out test using the existing media attachment and download helpers.
3. Assert outgoing Bob rows and attachments are persisted.
4. Assert Alice and Charlie incoming rows match returned sender message ids and attachment metadata.
5. Run `flutter test test/features/groups/integration/group_media_fanout_test.dart`.
6. Update source doc, closure reference, and breakdown ledger with evidence.

## risks and edge cases

- A non-admin member without a latest group key should remain blocked; this session must not weaken that guard.
- Receiver download completion is fake-bridge evidence, not real transport evidence.
- Existing-member fan-out coverage must remain intact.

## exact tests and gates to run

- `flutter test test/features/groups/integration/group_media_fanout_test.dart`

Run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` only if production group send/listener behavior changes.

## known-failure interpretation

No known failure is allowed for the direct suite.

## done criteria

- Direct suite passes.
- Newly-added-member media send evidence covers image, video, and voice.
- Breakdown ledger marks `GNM-002` accepted with concrete evidence.

## scope guard

- Do not alter cryptographic design, media upload architecture, or announcement policy.
- Do not add simulator claims.
- Do not widen named gates.

## accepted differences / intentionally out of scope

- Visible retry/restart/playback affordance checks remain owned by `GNM-003` and `GNM-005`.
- Real-network simulator fan-out remains governed by existing device-backed rollout docs.

## dependency impact

- `GNM-003` may reuse the new test fixtures if it needs outgoing media retry evidence.
- `GNM-005` should include this direct-suite result in final closure.
