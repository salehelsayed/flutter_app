# GNM-004 Plan - Announcement Reader And Removal Boundary Media Parity

## real scope

- Preserve announcement new-reader media receive coverage.
- Add direct use-case proof that a newly-added announcement reader remains blocked from sending text, image, video, and voice.
- Reuse existing removal and dissolved-group suites for discussion-group access boundaries without widening product policy.
- Record that current announcement writes are admin-only unless product code changes.

## closure bar

- Newly-added announcement readers receive only post-join admin image, video, and voice descriptors and trigger the receiver download path.
- Announcement readers cannot publish text, image, video, or voice messages while their role remains read-only.
- Current product evidence remains truthful: `sendGroupMessage` authorizes announcement sends only for `GroupRole.admin`.
- Removed and dissolved discussion users remain blocked by the existing membership boundary tests.

## source of truth

- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`

## session classification

`implementation-ready`

## exact problem statement

Report 89 must not close media receive and send coverage by weakening announcement or removal access boundaries. The current product contract is admin-only announcement posting, so this session proves reader receive plus reader send denial, and reuses existing membership tests for removed/dissolved group boundaries.

## regression/tests to add first

- Extend `announcement_new_reader_onboarding_test.dart` so the newly-added reader attempts text, image, video, and voice sends after receiving post-join admin media and each attempt returns `SendGroupMessageResult.unauthorized` without publishing or persisting an outgoing row.

## step-by-step implementation plan

1. Add the reader-denial assertions to the existing announcement new-reader media test.
2. Run the announcement onboarding suite.
3. Run the announcement happy-path suite for UI read-only, admin media, reaction, and dissolve coverage.
4. Run the membership boundary suite that owns removed/dissolved access rules.
5. Update the breakdown, source doc, and announcement/discussion closure references with exact evidence and residuals.

## exact tests and gates to run

- `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
- `flutter test test/features/groups/integration/announcement_happy_path_test.dart`
- `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
- `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart`

Run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` only in final acceptance unless this session changes shared authorization or removal product code.

## accepted differences / intentionally out of scope

- No writer-role announcement media claim is made because current code permits announcement sends only for admins.
- No simulator notification-open or playback journey is claimed here; those remain `GNM-005` classification items.
