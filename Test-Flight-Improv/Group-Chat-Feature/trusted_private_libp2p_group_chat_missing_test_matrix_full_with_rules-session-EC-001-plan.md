# EC-001 Session Plan - Invalid invite accepts classify safely

Status: accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:42:00+02:00 | Local planner completed | EC-001 source matrix row; ordered-session EC-001 row; `lib/features/groups/application/accept_pending_group_invite_use_case.dart`; `lib/features/groups/presentation/screens/group_list_wired.dart`; `lib/features/orbit/presentation/screens/orbit_wired.dart`; `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`; `test/features/groups/application/store_pending_group_invite_use_case_test.dart` | Existing accept/store paths already classified expired, revoked, already-used, and malformed invites without group/key side effects, but copied wrong-identity pending accepts still returned the generic malformed result. | Reclassify as a row-owned behavior gap, add a distinct accept result and UI snackbar, then add one EC001 regression that proves all invalid accept branches. |

## Execution Progress

| timestamp | role | files inspected or updated | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:43:00+02:00 | Local executor completed | `lib/features/groups/application/accept_pending_group_invite_use_case.dart`; `lib/features/groups/presentation/screens/group_list_wired.dart`; `lib/features/orbit/presentation/screens/orbit_wired.dart`; `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Added `AcceptPendingGroupInviteResult.wrongIdentity`, returned it for copied pending invite recipient/local-identity mismatch, and wired group list plus Orbit snackbars to show a distinct wrong-identity message. Added `EC001 invalid invite accepts classify failures without group or key state` and updated the IJ013 wrong-identity regression. | Run focused EC001, full accept, supporting store-path, format/analyze, and diff hygiene gates. |
| 2026-05-01T11:44:00+02:00 | Local verifier completed | EC001 focused accept slice; full accept-pending suite; supporting store-pending edge slice; touched Dart production files | Focused EC001 proof passed after same-session recovery of a stale IJ013 assertion. Full accept-pending suite and supporting store-path edge slice passed. Analyzer exited 0 with one non-blocking existing style info in `accept_pending_group_invite_use_case.dart`. | Persist EC-001 as `Covered` with exact code/test evidence. |

## real scope

EC-001 covers invalid trusted-private pending invite acceptance for the shipped direct invite contract:

- expired pending invite
- revoked pending invite
- copied pending invite bound to a different local identity
- malformed or tampered signed invite payload
- already-used single-use invite

The supporting store-path proof covers delayed revoked, already-used, expired, and local-identity-mismatched invite copies before pending/group state.

## closure bar

EC-001 can close when direct tests prove each invalid accept returns a safe classification and no case creates group state, group key state, join side effects, or messages. Wrong-identity accepts must be distinguishable from malformed/tampered invites in both application result and user-visible snackbar mapping.

## session classification

`needs_code_and_tests`; reclassified from `needs_tests_only` because direct evidence showed wrong-identity accepts were folded into the generic malformed `invalidPayload` result.

## Device/Relay Proof Profile

- Profile for this session: host-only Flutter proof.
- Device/relay proof is not required because EC-001 is about deterministic local pending-invite classification and state side effects.

## files changed

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- EC-001 closure docs

## exact tests and gates run

- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --name 'EC001|wrong local identity'` first failed on a stale IJ013 assertion that expected `invalidPayload`; after updating the assertion to `wrongIdentity`, the rerun passed (`+2`).
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart` passed (`+20`).
- `flutter test --no-pub test/features/groups/application/store_pending_group_invite_use_case_test.dart --name 'revoked|already used|expired credential|local peer identity'` passed (`+4`).
- `dart format --output=none --set-exit-if-changed lib/features/groups/application/accept_pending_group_invite_use_case.dart lib/features/groups/presentation/screens/group_list_wired.dart lib/features/orbit/presentation/screens/orbit_wired.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart` passed.
- `dart analyze lib/features/groups/application/accept_pending_group_invite_use_case.dart lib/features/groups/presentation/screens/group_list_wired.dart lib/features/orbit/presentation/screens/orbit_wired.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart` exited 0 with one non-blocking `use_null_aware_elements` info at `accept_pending_group_invite_use_case.dart:331`.
- `git diff --check` passed.

## Recovery Input

- Blocker class: stale adjacent test assertion.
- Failing command: `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --name 'EC001|wrong local identity'`.
- Failure: existing IJ013 wrong-identity regression still expected `AcceptPendingGroupInviteResult.invalidPayload`.
- Recovery: update IJ013 to expect the new row-owned `wrongIdentity` classification, then rerun focused and full accept suites.
- Result: focused EC001/IJ013 slice and full accept suite passed.

## scope guard

Do not claim a first-class account/device registry or link-token identity model. EC-001 closes the shipped trusted-private direct invite contract where pending invites are bound to local Peer ID via `recipientPeerId` and `invitePolicy.allowedDevices`.

## Final Execution Verdict

`accepted`: EC-001 is covered. Invalid pending invite accepts now produce distinct, safe results for expired, revoked, wrong-identity, malformed/tampered, and already-used cases, and direct tests prove none of those paths creates group state, group key state, join side effects, or message rows. Group list and Orbit pending-invite surfaces show a distinct wrong-identity snackbar.
