# INTEGRATE-ML-018 Integration Contract

Status: accepted

## Scope

Import and verify only source row `ML-018` into current main: invite decline, invite expiry, and invite cancellation/revocation must never create active private-group membership or usable key state for the invitee.

This is standard integration mode. The historical source worktree remains the source of truth; this plan is only the minimal import/reconcile/verify contract for current main. Do not update or recreate the original worktree implementation plan.

## Source Evidence

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Source plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-018-plan.md`
- Historical accepted source proof: focused ML-018 selectors passed, `private_invite_terminal_states` criteria passed, scoped hygiene passed, and source live iOS 26.2 proof run `1778550228340` passed for Alice/Bob/Charlie.

## Import Contract

- Reconcile `decline_pending_group_invite_use_case.dart` so a local decline records a consumed-invite tombstone before deleting the pending invite, preventing delayed direct/mailbox copies from becoming usable.
- Import row-owned ML-018 assertions for decline tombstone behavior, delayed-copy rejection after decline, expiry rejection, cancellation/revocation rejection, and no receiver group/key/join/message state after terminal invite outcomes.
- Import row-owned `private_invite_terminal_states` criteria, runner selection, and live harness proof plumbing only.
- Preserve existing main expiry/revocation behavior and existing COMPLETE_1 overlap coverage as preservation evidence; do not convert local decline into global revocation.
- Do not import unrelated source row changes, source docs, COMPLETE_1 docs, broader membership lifecycle work, BB-007 repair, GM-029 repair, or ML-012 external-fixture repair.

## Device Reality

Current Flutter-visible iOS 26.2 devices used by the controller:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

Live proof used only those IDs and the source relay profile through `MKNOON_RELAY_ADDRESSES`.

## Verification Log

- PASS: `flutter test --no-pub test/features/groups/application/decline_pending_group_invite_use_case_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/invite_round_trip_test.dart --plain-name 'ML-018'` (`+4`).
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_invite_terminal_states'` (`+4`).
- PASS: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios --scenario private_invite_terminal_states`.
- PASS: `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart lib/features/groups/application/decline_pending_group_invite_use_case.dart`.
- PASS: `dart format` on all nine touched ML-018 Dart files (`0 changed`).
- PASS: scoped `git diff --check` on touched ML-018 code/test/harness files.
- PASS: preservation selectors for `group_invite_listener_test.dart --plain-name 'IJ003'` (`+2`), `store_pending_group_invite_use_case_test.dart --plain-name 'IJ003'` (`+1`), `group_membership_smoke_test.dart --plain-name 'ML-001'` (`+1`), and `group_messaging_smoke_test.dart --name 'GM-003|GE-014|GE-015'` (`+3`).
- PASS: full `test/integration/group_multi_party_device_criteria_test.dart` (`+264`).
- PASS: live iOS 26.2 `private_invite_terminal_states` proof run `1779101942400` using Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_invite_terminal_states_W7zbT1`; orchestrator detail `private_invite_terminal_states verdicts valid for alice, bob, charlie`.
- LIVE PROOF DETAIL: Alice proof recorded sent decline/expiry/cancellation/revocation/post-terminal message, received Bob post-terminal message, Charlie excluded, and rotated epoch `2`; Bob proof recorded received Alice post-terminal message, sent Bob post-terminal message, Charlie excluded, and rotated epoch `2`; Charlie proof recorded received decline/expiry/cancellation invites, declined invite, cleared pending state, tombstone recorded, delayed decline rejected, expired/cancelled invites rejected, no local group, no usable key, post-terminal send rejected, no Alice/Bob post-terminal plaintext, no publish acceptance, plaintext count `0`, and send outcome `groupNotFound`.
- GATE RESIDUAL: selected invite preservation command remains red only on pre-existing `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`); the other selected invite preservation tests passed.
- GATE RESIDUAL: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red outside ML-018 only on `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`) and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:7960` in the fresh run).
- GATE RESIDUAL: `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Integration Verdict

`accepted` for `INTEGRATE-ML-018`.

The row-owned production decline tombstone, focused tests, criteria, runner, and live harness proof are present in main. Focused selectors, affected preservation selectors, full criteria regression, scoped analyzer/format/diff hygiene, and fresh iOS 26.2 live proof all passed. The remaining red gates are classified as non-ML-018 residuals: prior `BB-007`, known `GM-029`, and the existing completeness classification gap for `fake_group_pubsub_network_test.dart`.
