# GON-008 Plan: Foreground Push Drains New-Member Media

## real scope

- Extend `foreground_group_push_drain_test.dart` from text-only group inbox drain to a representative post-join media item.
- Prove exactly-once message insertion, exactly-once notification display, media descriptor preservation, and receiver media-download trigger.
- Keep simulator/OS push delivery coverage separate from this direct integration test.

## closure bar

- `TC-25` has automated evidence that a foreground group push drains a media payload for the newly-added member's group.
- Repeated foreground push handling does not duplicate the message, notification, or media attachment.
- The media descriptor is persisted and the download path is invoked.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-008`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-25.

## session classification

`implementation-ready`

## exact problem statement

The existing foreground group push drain suite proves targeted text drain and dedupe, but Report 85 requires the same foreground recovery path to prove at least one post-join media payload for a newly-added group member.

## files and repos to inspect next

- `integration_test/foreground_group_push_drain_test.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`

## existing tests covering this area

- `foreground_group_push_drain_test.dart` covers text drain, live+push dedupe, 1:1 isolation, and post isolation.
- `drain_group_offline_inbox_use_case_test.dart` covers lower-level media parsing and replay enrichment.
- `group_new_member_onboarding_test.dart` covers live app-layer new-member media delivery.

## regression/tests to add first

- Add a media foreground-push test case to `integration_test/foreground_group_push_drain_test.dart`.

## step-by-step implementation plan

1. Add media-download support to the foreground push harness bridge.
2. Give the member harness a fake media file manager.
3. Add a foreground group inbox page containing one image payload.
4. Trigger foreground group push twice for the same message id.
5. Assert one message, one notification, one media attachment, and one media download.
6. Update source docs and breakdown ledger.

## risks and edge cases

- This is a direct foreground-drain integration test; it does not prove OS-level push delivery.
- It uses a representative image media item because image/video/audio descriptor fan-out is already covered by `GON-001` and `GON-007`.

## exact tests and gates to run

- `flutter test integration_test/foreground_group_push_drain_test.dart -d macos`
- `./scripts/run_test_gates.sh completeness-check`

## known-failure interpretation

- Duplicate saved messages or notifications indicate foreground replay dedupe regression.
- Missing media attachment or missing download command indicates group inbox media recovery regression.

## done criteria

- The extended foreground push drain suite passes.
- Source doc, gate definitions, discussion closure reference, and breakdown ledger record TC-25 truthfully.

## scope guard

- Do not add paired simulator OS-push orchestration here; later simulator sessions own that.

## accepted differences / intentionally out of scope

- This test proves foreground router/inbox drain behavior, not background/terminated OS push delivery.

## dependency impact

- Later notification and simulator sessions can use this as the foreground media-drain baseline.
