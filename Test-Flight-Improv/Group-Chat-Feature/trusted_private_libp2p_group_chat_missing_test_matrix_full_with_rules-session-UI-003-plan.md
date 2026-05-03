# UI-003 Session Plan - Key change, encryption status, and verification warnings are visible

Status: accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T10:07:00+02:00 | Local planner completed | UI-003 source matrix row; ordered-session UI-003 row; group conversation/info screens and wired adapters; member identity safety row and tests | Existing member rows expose identity-change safety numbers, but there is no explicit group security surface that summarizes encryption state, current key epoch/key change, verified-member counts, and verification warnings. | Add a presentation security status model, render it in group info and conversation surfaces, wire it from latest group key/member safety evidence, and add direct UI/wired tests. |

## real scope

UI-003 asks users to see clear encrypted-state, verified-member, identity-change, and key-change warnings after key rotation or identity changes. This session covers:

- group info security status card
- group conversation security strip
- latest group key epoch and key-change visibility
- verified-member count, unverified-member count, and identity-change warning visibility
- existing per-member identity safety warning rows remaining visible with current and saved safety numbers

## closure bar

UI-003 can be resolved only when focused tests prove:

- pure info and conversation screens render encryption state and key epoch/key-change text without key material
- wired info screen derives the security status from repository key state, saved contact safety numbers, and member identity changes
- wired conversation screen derives the same status from repository key/member/contact state
- existing identity-change warnings and safety numbers still render on member rows

## session classification

`implementation-ready`. The missing behavior is a small presentation implementation plus direct widget tests.

## Device/Relay Proof Profile

- Profile for this session: host-only Flutter presentation and wired widget tests.
- Device and real-network proof are supplemental because the row-owned gap is local visibility of already-persisted key/member safety state.

## files expected to change

- `lib/features/groups/presentation/group_security_status_view_state.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart --plain-name 'security status'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'security status'`
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'security status'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'security status'`
- `git diff --check`

## scope guard

Do not add a new cryptographic trust model or expose raw group key material. Use the existing latest-key repository state and existing contact/member safety comparison.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T10:21:00+02:00 | Local executor completed | `group_security_status_view_state.dart`; group info/conversation pure screens; group info/conversation wired adapters; focused and full presentation tests | Added safe security-status presentation state, info card, conversation strip, repository/contact-backed wired loading, and direct UI-003 tests. Full pure and wired presentation suites passed after moving the larger info card below the member section to preserve existing first-screen controls. | Persist UI-003 as `Covered` with concrete code/test evidence. |

## exact tests and gates run

- `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart --plain-name 'security status'` passed (`+1`).
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'security status'` passed (`+1`).
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'security status'` passed (`+1`).
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'security status'` passed (`+1`).
- `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart` passed (`+18`).
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart` passed (`+35`).
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart` passed (`+28`).
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart` passed (`+74`).
- `git diff --check` passed.

## Final Execution Verdict

Accepted on 2026-05-01. UI-003 is covered for the shipped group UI surfaces: users can see end-to-end encrypted state, active/key-changed epoch, verified-member counts, unverified or changed-identity review warnings, and per-member current/saved safety numbers without exposing raw key material. Device/real-network proof remains supplemental because this row's shipped closure bar is local visibility of persisted key/member safety state.
