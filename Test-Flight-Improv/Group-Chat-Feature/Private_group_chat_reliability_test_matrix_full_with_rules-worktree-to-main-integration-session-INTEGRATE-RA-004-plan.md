# INTEGRATE-RA-004 - Stale Old Invite Before Current Re-Add Integration Contract

Status: accepted

Started: 2026-05-19 12:18 CEST
Completed: 2026-05-19 12:25 CEST

## Source Row Contract

Source row: `RA-004 | Peer accepts old invite after being removed and before receiving new invite | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-004-plan.md`

RA-004 owns the stale old-invite-before-current-readd path: Charlie holds an old epoch-N invite, Alice removes Charlie and rotates before Charlie accepts, Charlie's old invite accept cannot create stale group/key/member/native join/message state, then Alice re-adds Charlie with a current invite and delivery resumes at the current epoch.

## Reconciliation Decision

Classification before import: `partial`.

Current main already has the shared stale-invite behavior through accepted `INTEGRATE-ML-019` and `INTEGRATE-KE-016`: stale/delayed invite material cannot replace the latest pending re-add package, stale accept against newer local removal/key state is rejected, current invite acceptance succeeds, removed-window plaintext stays excluded, and `private_stale_invite_readd` has ML-019/KE-016 criteria/live proof. That behavior is strong overlap but not exact RA-004 closure because current main has no RA-004 row-named host selectors, no `ra004StaleInviteBeforeReaddProof`, and no RA-004 criteria validation or negative tests.

Source RA-004 has no production changes. This integration imports only missing RA-004 row-owned proof identity on top of the existing `private_stale_invite_readd` path and preserves ML-019/KE-016 behavior.

## Intended Import Scope

Import only:

- one RA-004 application selector in `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- one RA-004 fake-P2P invite round-trip selector in `test/features/groups/integration/invite_round_trip_test.dart`
- `ra004StaleInviteBeforeReaddProof` validation in `integration_test/scripts/group_multi_party_device_criteria.dart`
- RA-004 criteria fixtures plus positive, missing-proof, and old-accept-success rejection tests in `test/integration/group_multi_party_device_criteria_test.dart`
- RA-004 proof fields and old-accept-before-current coordination inside the existing `private_stale_invite_readd` live harness path
- this integration plan plus test-inventory/breakdown closure docs

Do not import production changes, source matrix rewrites, COMPLETE_1 rewrites, unrelated source docs, source iOS project metadata, RA-005+ rows, ML-019/KE-016 rewrites beyond preservation-compatible RA-004 overlays, BB-007/BB-012/GM-029 repairs, or unrelated invite/key/replay/UI work.

## Verification Contract

Focused RA-004 checks:

- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'RA-004'`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'RA-004'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-004'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_stale_invite_readd'`
- scoped analyzer over the RA-004 touched Dart files

Affected preservation checks:

- ML-019/KE-016 application and invite round-trip selectors
- ML-019/KE-016/`private_stale_invite_readd` criteria preservation
- GM-021 member-removal preservation where practical

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

Live proof requirement: exact iOS 26.2 `private_stale_invite_readd` proof is required before final acceptance unless a real external fixture blocker is recorded. Source historical proof run `1778635732118` is source evidence only.

## Imported Row-Owned Delta

RA-004 imported no production code. The accepted delta is limited to the missing row-owned stale-old-invite proof overlay:

- `accept_pending_group_invite_use_case_test.dart` adds `RA-004 revoked old invite cannot create stale membership before current re-add invite succeeds`.
- `invite_round_trip_test.dart` adds `RA-004 IJ003 revoked old invite stays rejected before current re-add succeeds`.
- `group_multi_party_device_criteria.dart` validates `ra004StaleInviteBeforeReaddProof` for `private_stale_invite_readd`.
- `group_multi_party_device_criteria_test.dart` adds the RA-004 positive fixture check plus missing-proof and old-accept-success rejection checks.
- `group_multi_party_device_real_harness.dart` adds RA-004 old-invite-before-current coordination and Alice/Bob/Charlie proof fields on the existing `private_stale_invite_readd` scenario.

## Verification Evidence

Focused and preservation checks passed:

- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'RA-004'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'RA-004'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-004'` PASS (`+3`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_stale_invite_readd'` PASS (`+7`).
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --name 'ML-019|KE-016'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --name 'ML-019|KE-016'` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'ML-019|KE-016|private_stale_invite_readd'` PASS (`+7`).
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --name 'GM-021'` PASS (`+1`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_stale_invite_readd --list-scenarios` PASS.
- Scoped analyzer over all RA-004 touched Dart files PASS (`No issues found!`).
- `git diff --check` PASS.

iOS 26.2 live proof passed:

- Scenario: `private_stale_invite_readd`.
- Run id: `1779185770100`.
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_stale_invite_readd_RTqRQd`.
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Final result: `private_stale_invite_readd proof passed: private_stale_invite_readd verdicts valid for alice, bob, charlie`.
- RA-004 proof highlights: Alice recorded old invite sent, Charlie removed before old accept, rotation and revocation before current invite, current invite sent after old accept was blocked, post-current traffic, final epoch `2`; Bob recorded old-invite member state, removal before current invite, removed-window message, current epoch, post-current traffic, final epoch `2`; Charlie recorded old invite epoch `1`, old accept before current invite rejected as `notFound`, no group/key after old accept, current invite epoch/accepted epoch `2`, stale accept rejected as `revoked`, no key downgrade, removed-window plaintext count `0`, all final members, and final epoch `2`.

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+223 -4` only on preserved non-RA-004 residuals: `BB-007` (`Expected: not null / Actual: <null>` at `invite_round_trip_test.dart:679`), `BB-012` (`Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `group_startup_rejoin_smoke_test.dart:859`), accepted-row `IR-018` now also failing the same aged fixed-date replay fixture class (`Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `group_startup_rejoin_smoke_test.dart:1027`, fixed May 12 replay is past the seven-day retention window on May 19), and `GM-029` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `group_membership_smoke_test.dart:8725`).
- `./scripts/run_test_gates.sh completeness-check` remains red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).

## Final Verdict

`INTEGRATE-RA-004` is accepted. Current main now carries the missing RA-004 row identity and proof validation for stale old-invite acceptance before current re-add, without importing production changes or unrelated source worktree deltas. Existing ML-019/KE-016 behavior remains preserved, and row acceptance does not claim fixes for `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, `GM-029`, completeness classification, KE-007/KE-009 conflicts, or later RA rows.
