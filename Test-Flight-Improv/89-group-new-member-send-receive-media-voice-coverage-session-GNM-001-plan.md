# GNM-001 Plan - Discussion New-Member Receive Media And No-Backfill Evidence

## real scope

- Verify the current discussion onboarding evidence for a newly-added member receiving post-join text, image, video, and voice.
- Confirm the reported "text works but video missing" shape is directly represented by post-join text plus post-join video in the same group.
- Confirm no pre-join history is delivered to the newly-added member.
- Do not change production code unless the evidence test fails for a real product reason.

## closure bar

- `test/features/groups/integration/group_new_member_onboarding_test.dart` passes.
- The test evidence proves post-join text, image, video, and voice rows, media descriptor metadata, download completion, and no pre-join history for the newly-added member.
- The source doc and breakdown ledger record this as evidence coverage, not simulator playback closure.

## source of truth

- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

Current code and passing tests beat stale prose.

## session classification

`evidence-gated`

## exact problem statement

The reported regression says a newly-added member can see group text but misses a group video. This session must prove the receive-side app-layer path already covers a newly-added member receiving post-join text and video, plus image and voice, without receiving pre-join history. It must not overclaim simulator playback or restart behavior.

## files and repos to inspect next

- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`

## existing tests covering this area

- `group_new_member_onboarding_test.dart` has `new member receives only post-join text and media with descriptors`.
- The same file also covers multiple-add convergence and add/send boundary behavior.

## regression/tests to add first

No new regression is required unless the direct suite lacks the claimed assertions or fails for a real product gap.

## step-by-step implementation plan

1. Inspect the onboarding test assertions for text, video, image, voice, no pre-join history, metadata, and downloads.
2. Run `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`.
3. If the suite passes, update the source doc and breakdown ledger with evidence.
4. If it fails because evidence is missing, add only the missing focused assertions and rerun the same direct suite.

## risks and edge cases

- Descriptor evidence is not simulator playback evidence.
- Download completion in fake bridge tests should not be documented as real transport coverage.
- No-backfill must remain explicit when media assertions are strengthened.

## exact tests and gates to run

- `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`

Run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` only if production group behavior changes.

## known-failure interpretation

No known failure is allowed for the direct suite. Unrelated gate failures outside this direct suite do not block this evidence-only session unless production code changes.

## done criteria

- Direct suite passes.
- Source doc records `NGM-001` through `NGM-004`, `NGM-009`, `NGM-010`, and `NGM-013` as app-layer evidence where supported.
- Breakdown ledger marks `GNM-001` accepted with concrete evidence.

## scope guard

- Do not change group membership policy.
- Do not add simulator claims.
- Do not modify media upload/download architecture.
- Do not widen named gates.

## accepted differences / intentionally out of scope

- Simulator-visible video playback and restart persistence remain owned by `GNM-003` and `GNM-005`.
- Real-network and real-crypto evidence remain governed by Report 85 and the existing nightly classifications.

## dependency impact

- `GNM-003` may reuse this receive-side evidence but still owns visible row/retry/restart behavior.
- `GNM-005` should include this direct-suite result in final acceptance.
