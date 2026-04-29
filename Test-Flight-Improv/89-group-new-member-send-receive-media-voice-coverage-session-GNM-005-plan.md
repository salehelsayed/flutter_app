# GNM-005 Plan - Simulator Acceptance Gate Classification And Final Closure

## real scope

- Verify the Report 89 host-side direct suites and named group/completeness gates.
- Classify simulator/device-backed video playback, voice playback, and restart persistence honestly.
- Update the source doc, closure references, and session breakdown so they agree on covered versus residual evidence.
- Persist one final program verdict.

## closure bar

- `GNM-001` through `GNM-004` are resolved or explicitly blocked in the breakdown ledger.
- The focused discussion, announcement, visible-media, retry, inbox, and foreground-drain suites pass with the current changes.
- The `groups` named gate is run with an explicit device when needed.
- `completeness-check` is run and any unrelated known gaps are not misrepresented as Report 89 regressions.
- The final verdict distinguishes host-side closure from simulator playback/restart residual evidence.

## source of truth

- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## session classification

`acceptance-only`

## exact tests and gates to run

- `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
- `flutter test test/features/groups/integration/group_media_fanout_test.dart`
- `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`

Earlier session runs also count for direct evidence if unchanged after this plan lands.

## accepted differences / intentionally out of scope

- No full mobile simulator playback claim is made for video or voice.
- No restart-persistence simulator claim is made for newly-added-member media rows.
- The final verdict may be `accepted_with_explicit_follow_up` if host-side coverage is closed but simulator playback/restart remains residual.
