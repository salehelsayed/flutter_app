# INTEGRATE-ML-016 Integration Contract

Status: accepted

## Scope

Import and verify only source row `ML-016` into current main: a newly admitted private group member with no saved Alice/Bob social-contact edges still receives Alice/Bob group messages and renders stable non-blank sender labels.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update or recreate the original worktree implementation plan.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-016-plan.md`
- Historical accepted source proof: focused ML-016 selector passed (`+7`), `private_non_friend_member_delivery` criteria selector passed (`+3`), scoped format/analyze/diff passed, and live iOS 26.2 proof run `1778866945512` passed for Alice/Bob/Dana.

## Import Contract

- Add `lib/features/groups/application/group_sender_display_name.dart` for stable wire/member/peer fallback labels.
- Reconcile `handle_incoming_group_message_use_case.dart` so blank wire sender names fall back to verified group-member identity before persistence.
- Reconcile `group_conversation_screen.dart` and wired propagation so incoming messages render stable sender labels instead of blank or `Unknown` when group member data exists.
- Reconcile `group_invite_auth.dart` and `accept_pending_group_invite_use_case.dart` only enough to allow a valid signed member-snapshot invite bootstrap without adding Alice/Bob as saved contacts. Generic non-contact invite rejection remains covered.
- Import row-owned ML-016 unit/widget/fake-network tests, criteria tests, runner scenario, and live harness proof plumbing only.

## Device Reality

Historical source iOS 26.2 device IDs are unavailable in this checkout. Current Flutter-visible iOS 26.2 devices used by the controller:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Dana: `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`

Live proof used only those IDs and the source relay profile through `MKNOON_RELAY_ADDRESSES`.

## Verification Log

- PASS: writer run `flutter test --no-pub ... --plain-name 'ML-016'` (`+7`).
- PASS: writer run `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_non_friend_member_delivery'` (`+3`).
- PASS: writer scoped `dart analyze` exited `0` with only pre-existing informational findings in `group_conversation_screen.dart`.
- PASS: writer scoped `git diff --check`.
- PASS: controller rerun `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart --plain-name 'ML-016'` (`+7`), both before and after broad red gates.
- PASS: controller rerun `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_non_friend_member_delivery'` (`+3`).
- PASS: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_non_friend_member_delivery --list-scenarios` printed `private_non_friend_member_delivery`.
- PASS: `dart format --set-exit-if-changed` on touched ML-016 files (`0 changed`).
- PASS: controller scoped `dart analyze` exited `0` with only existing informational findings in `group_conversation_screen.dart`.
- PASS: controller scoped `git diff --check`.
- PASS: preservation selector `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'returns unknownSender for invite from non-contact'` (`+1`).
- PASS: preservation selector `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'ML-003 accept preserves invite config version as membership watermark for hash convergence'` (`+1`).
- PASS: preservation selector `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'ML-002 online add D receives immediate live A and B messages after join/key handoff'` (`+1`).
- PASS: preservation selector `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'private_timeline_truth|private_rapid_readd|private_concurrent_admin_membership_edits|private_readd_cycles'` (`+26`).
- PASS: preservation selector `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --name 'loads and displays messages on init|counts own member as verified without saved contact|shows security status from key epoch and member safety'` (`+3`).
- PASS: live iOS 26.2 `private_non_friend_member_delivery` proof run `1779097299480` using Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_non_friend_member_delivery_mLWk6y`; orchestrator detail `private_non_friend_member_delivery verdicts valid for alice, bob, dana`. Dana verdict recorded no saved Alice/Bob contacts, Alice/Bob messages received and persisted exactly once, `senderLabelsNonBlank=true`, `messagesHiddenByContactGate=false`, final member/key convergence, and labels `GM Alice` / `GM Bob`.
- GATE RESIDUAL: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red outside ML-016 with the same residuals recorded after ML-015: `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:678`, and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:7798`.
- GATE RESIDUAL: `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Integration Verdict

`accepted` for `INTEGRATE-ML-016`.

The row-owned code, tests, criteria, runner, and live harness proof are present in main. Focused selectors, preservation selectors, scoped format/analyze/diff hygiene, and fresh iOS 26.2 live proof all passed. The remaining red gates are classified as non-ML-016 residuals: prior accepted `BB-007`, known `GM-029`, and the existing completeness classification gap for `fake_group_pubsub_network_test.dart`.
