# INTEGRATE-RA-013 Minimal Integration Contract

Status: accepted

## Source Row

`RA-013 | Re-add same user with multiple devices has per-device truthful state | P1 | Remove and Re-add Regression Suite`

Historical source of truth:

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-013-plan.md`

Do not recreate or rerun the historical implementation plan. This contract only governs importing and verifying the already-accepted RA-013 row delta into the main checkout.

## Controller Classification

RA-013 is partially present in main through adjacent GE-012 same-user multi-device behavior, generic sibling pending-invite coverage, and accepted RA-012 helper/harness work, but the exact row-owned RA-013 contract is missing. This row is not `skipped_already_present`.

Import only the missing meaningful RA-013 delta:

- production receive-path handling for resolving a local same-account secondary device by active device transport, applying account-member removed-window rejection, and treating same-account secondary-device self echo as local self delivery
- direct invite selector proving separate device-bound re-add invites for same-user devices
- direct accept selector proving C1 acceptance leaves C2 pending until its own onboarding
- direct receive selectors proving active same-account device delivery and account removed-window replay rejection
- fake-network RA-013 same-user phone/tablet re-add selector
- `private_same_user_multi_device_readd` runner/live-harness/criteria support
- RA-013 criteria positive and weak-proof rejection tests
- row-owned `test-inventory.md` entry

## Allowed Write Set

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/send_group_invite_use_case_test.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

The controller owns this contract, the integration breakdown ledger, row ordering, final status, and final verdict. The execution worker must not edit those files.

## Verification Contract

Focused checks:

```bash
dart analyze lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --plain-name 'RA-013'
flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'RA-013'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'RA-013'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-013'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-013'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_same_user_multi_device_readd --list-scenarios
```

Affected preservation checks:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'same-key sibling'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-012'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-012'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-013'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-013'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-021'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-021'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-021'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-012'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'
```

Required live proof uses only iOS 26.2 CoreSimulator app peers and four distinct devices:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_same_user_multi_device_readd -d <alice>,<bob>,<charlie-phone>,<dana-tablet>
```

Named gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Known residuals from RA-012 may remain unrelated unless the RA-013 import changes their owner surfaces: `BB-007`, `BB-012`, accepted-row `IR-018`, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and the unrelated completeness classification miss for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Scope Guard

Do not import RA-012 rotated material, RA-014 old-key poisoning, RA-015 `ALREADY_JOINED` refresh, RA-017/RA-018 churn breadth, UI, notifications, media, network, relay internals, Go code, Android, physical iOS, macOS app-peer proof, KE-007/KE-009 re-reconciliation, ML-012 fixture repair, or unrelated tests from later rows. If a file already contains equivalent or stronger main coverage, merge only the missing RA-013 assertion/helper instead of overwriting main.

## Execution Result

Accepted on 2026-05-19 in standard integration mode.

Imported only the missing row-owned RA-013 delta into the allowed write set: same-account secondary-device receive handling and removed-window rejection in `handle_incoming_group_message_use_case.dart`, direct invite/accept/receive selectors, the fake-network phone/tablet re-add selector, `private_same_user_multi_device_readd` runner/live-harness/criteria support, RA-013 criteria positive and weak-proof rejection tests, and one `test-inventory.md` row.

Controller focused checks passed:

```bash
dart analyze lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --plain-name 'RA-013'
flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'RA-013'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'RA-013'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-013'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-013'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_same_user_multi_device_readd --list-scenarios
```

Affected preservation checks passed for `same-key sibling`, GE-012 host/criteria, GE-013 host/criteria, GM-021 direct/fake-network/criteria, RA-012 criteria, and the accumulated `private_readd_current` criteria suite.

iOS 26.2 live proof passed:

- Scenario: `private_same_user_multi_device_readd`
- Run id: `1779203680386`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_same_user_multi_device_readd_VvxwiF`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie phone `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana/tablet `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`
- Orchestrator verdict: `private_same_user_multi_device_readd verdicts valid for alice, bob, charlie, dana`
- Verdict evidence: all four roles recorded `ra013SameUserMultiDeviceReaddProof`, distinct phone/tablet device ids, final epoch `2`; Dana/tablet stayed a Charlie-account device (`memberListIncludesDanaAccount=false`), had `preAcceptPlaintextCount=0`, was pending before its own accept, accepted after phone, received post-tablet traffic, and sent the tablet post-accept message; Alice/Bob/Charlie observed Charlie re-added with two devices and post-accept traffic.

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+226 -8` on preserved residuals: `BB-007`, `BB-012`, accepted-row `IR-018`, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`; RA-013's in-gate selector passed.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).
- `git diff --check` passed.
