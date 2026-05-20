# INTEGRATE-ML-017 Integration Contract

Status: accepted

## Scope

Import and verify only source row `ML-017` into current main: a removed private-group member with existing local history keeps allowed pre-removal history in a read-only shell, cannot send or react, has no active self member/current key, and receives no Alice/Bob post-removal plaintext.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update or recreate the original worktree implementation plan.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-017-plan.md`
- Historical accepted source proof: focused ML-017 selectors passed, `private_history_retention` criteria passed, scoped hygiene passed, and source live iOS 26.2 proof run `1778548645837` passed for Alice/Bob/Charlie.

## Import Contract

- Reconcile `group_message_listener.dart` so self-removal retains local non-system history as read-only state while removing self membership, current keys, and native topic subscription.
- Reconcile `send_group_message_use_case.dart` so retained removed/self-missing state is rejected before publish and missing current keys cannot publish stale local membership rows.
- Reconcile `group_conversation_wired.dart` and `group_conversation_screen.dart` so retained removed history opens read-only with compose/record/quote/reaction controls disabled and a removed-user banner.
- Import row-owned ML-017 unit/widget/fake-network tests, criteria tests, runner scenario, and live harness proof plumbing only.
- Reconcile affected main-row tests that still expected delete-on-removal (`group_resume_recovery_test.dart`, `group_messaging_smoke_test.dart`, and the generic membership smoke assertion) to accept either no-history deletion or ML-017 retained read-only state without broadening their contracts.
- Reconcile `GroupTestUser.addMember` fake fixture pruning so retained stale member rows are pruned when a current authoritative member snapshot is applied to an invitee.

## Device Reality

Current Flutter-visible iOS 26.2 devices used by the controller:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

Live proof used only those IDs and the source relay profile through `MKNOON_RELAY_ADDRESSES`.

## Verification Log

- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-017'` (`+6`).
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_history_retention'` (`+5`).
- PASS: affected main-row selectors:
  - `group_membership_smoke_test.dart --plain-name 'admin removes member - removed member stops receiving messages'` (`+1`).
  - `group_resume_recovery_test.dart --plain-name 'removed offline member does not retry queued failed sends after replayed removal'` (`+1`).
  - `group_messaging_smoke_test.dart --name 'GE-005|GE-008'` (`+2`).
- PASS: preservation selectors `ML-007 removed member rejoins with current state and receives only post-readd messages`, `ML-008 repeated add-remove-re-add cycles stay convergent across restarts`, and `GE-019 seeded random key rotations preserve access windows`.
- PASS: `dart format` on touched ML-017 files (`0 changed`).
- PASS: scoped `git diff --check`.
- SCOPED ANALYZER RESIDUAL: `dart analyze` on touched files exits `2` only for the pre-existing ten diagnostics already recorded before ML-017 closure: unused `mime` optional parameter in `group_conversation_wired_test.dart:229`, six `withOpacity` deprecations and two `use_build_context_synchronously` infos in `group_conversation_screen.dart`, and one null-aware style info in `group_message_listener_test.dart:4793`.
- PASS: live iOS 26.2 `private_history_retention` proof run `1779100595114` using Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_history_retention_48ICGL`; orchestrator detail `private_history_retention verdicts valid for alice, bob, charlie`.
- LIVE PROOF DETAIL: Alice proof recorded `removedCharlie=true`, `sentPreRemovalHistory=true`, `sentPostRemovalMessage=true`, `receivedBobPostRemovalMessage=true`, `memberListExcludesCharlie=true`, `rotatedEpoch=2`; Bob proof recorded `receivedPreRemovalHistory=true`, `receivedAlicePostRemovalMessage=true`, `sentBobPostRemovalMessage=true`, `memberListExcludesCharlie=true`, `hasRotatedEpoch=true`, `rotatedEpoch=2`; Charlie proof recorded `retainedLocalGroup=true`, `retainedPreRemovalHistory=true`, `composeDisabled=true`, `postRemovalSendRejected=true`, `selfMemberRemoved=true`, `noCurrentKey=true`, `selfRemovalCleanupObserved=true`, `receivedAlicePostRemovalMessage=false`, `receivedBobPostRemovalMessage=false`, `postRemovalPublishAccepted=false`, `postRemovalPlaintextCount=0`, and `postRemovalSendOutcome=unauthorized`.
- GATE RESIDUAL: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red outside ML-017 only on `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:678`) and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:7951` in the fresh run).
- GATE RESIDUAL: `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Integration Verdict

`accepted` for `INTEGRATE-ML-017`.

The row-owned code, tests, criteria, runner, and live harness proof are present in main. Focused selectors, affected main-row selectors, scoped format/diff hygiene, and fresh iOS 26.2 live proof all passed. The remaining red gates are classified as non-ML-017 residuals: prior `BB-007`, known `GM-029`, and the existing completeness classification gap for `fake_group_pubsub_network_test.dart`.
