# EK-014 Identity Change Warning And Safety Number Verification Plan

## Session Intake

- breakdown artifact: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- source row: `EK-014 | Identity change warning and safety-number verification`
- disposition: `needs_code_and_tests`
- execution classification: `implementation-ready`
- local plan fallback: used after the spawned planning attempt no-progressed without leaving a reusable plan

## Current Gap

The group info surface already loads group members and has access to the contact repository, but it does not compare the member's current identity keys against the user's saved contact keys. There is also no deterministic, user-visible safety number helper that lets a user compare the saved contact identity with the current group member identity before trusting future messages.

Prior EK closure ledgers already record missing first-class per-device identity/key-package primitives. EK-014 is therefore scoped to the member-level identity keys that exist today: Ed25519 public key plus ML-KEM public key when present.

## Scope

Implement member-level identity safety warnings for group info:

- add a deterministic safety-number helper for a peer id plus public identity keys
- compare each group member's current `publicKey`/`mlKemPublicKey` with the saved `ContactModel` for the same peer id
- show an identity-change warning on the affected member row when saved and current keys differ
- show current and saved safety numbers so the user can compare identity keys before trusting future messages
- avoid false warnings when there is no saved contact key or no comparable current key
- preserve existing admin/remove/member-list behavior

## Files In Scope

- `lib/features/contacts/domain/models/contact_safety_number.dart`
- `lib/features/groups/domain/models/group_member_identity_safety.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `test/features/contacts/domain/models/contact_safety_number_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`

## Scope Guard

- Do not add a new first-class multi-device identity model in this session.
- Do not add trust-state persistence, key-package tombstones, MLS-style commits, or device verification workflows here.
- Do not change message acceptance/decryption policy; this row owns the warning and comparison surface.
- Do not alter unrelated group membership, role, leave, dissolve, media, or key-retention behavior.

## Acceptance Criteria

- Safety numbers are deterministic, formatted consistently, and change when the identity key material changes.
- `GroupInfoWired` derives member identity-safety state from `ContactRepository` plus `GroupMember` keys.
- `GroupMemberRow` displays `Identity changed` and both `Current safety` and `Saved safety` values for changed identities.
- Matching saved/current keys do not show the warning.
- Missing saved contacts or missing comparable current keys do not produce false identity-change warnings.
- Existing group info admin controls and member rows remain visible.
- Source matrix row EK-014 is updated from `Open` to `Covered` only if the implementation and focused tests pass.

## Direct Tests

- `flutter test --no-pub test/features/contacts/domain/models/contact_safety_number_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart --name "identity"`
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --name "identity"`

## Session Gates

- focused gates above
- `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/contacts/domain/models/contact_safety_number_test.dart`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Done Criteria

- code and direct tests land within the files in scope
- focused gates pass or any failure is documented as unrelated with exact evidence
- EK-014 source matrix row and `test-inventory.md` record concrete file/test evidence
- session breakdown ledger records EK-014 as `accepted | closure-verified` or truthfully blocked with blocker classes

## Execution Evidence

- implementation path: bounded local execution fallback after the fresh execution agent no-progressed without landing a trustworthy EK-014 result
- code changes:
  - `lib/features/contacts/domain/models/contact_safety_number.dart`
  - `lib/features/groups/domain/models/group_member_identity_safety.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/widgets/group_member_row.dart`
- test changes:
  - `test/features/contacts/domain/models/contact_safety_number_test.dart`
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
- behavior covered:
  - group info compares a member's current group identity keys against the saved contact identity keys
  - changed identities show an `Identity changed` member-row warning
  - changed identities expose current and saved safety numbers for comparison before trust
  - matching saved/current keys do not produce a false warning
  - missing contacts or missing comparable current public keys are skipped rather than warning
- focused gate: `flutter test --no-pub test/features/contacts/domain/models/contact_safety_number_test.dart` -> PASS, 3 tests
- focused gate: `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart --name identity` -> PASS, 2 tests
- focused gate: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --name identity` -> PASS, 2 tests
- combined focused gate: `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/contacts/domain/models/contact_safety_number_test.dart` -> PASS, 46 tests
- closure gate: `./scripts/run_test_gates.sh completeness-check` -> PASS, 694/694 test files classified
- closure gate: `git diff --check` -> PASS
- note: an initial parallel `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart --name identity` attempt failed while creating a macOS native-assets universal binary because concurrent Flutter commands raced on `build/native_assets/macos/libsqlite3.arm64.macos.dylib.lipo`; the same command passed when rerun serially.
