# GE-012 Session Plan: Multi-Device Same User In Group

Status: accepted

## Gap-Closure Reconciliation

Preflight found GE-012 source row `Open`: Bob has two devices, Alice sends, Bob device 1 sends, Bob device 2 sends, and all devices must show the expected delivery/sync behavior without sibling-device rejection or self-skip.

The breakdown ledger row 171 classifies GE-012 as `needs_code_and_tests` / `implementation-ready`. Existing lower-level GA multi-device Go tests and MD-004 same-user harness evidence are supporting proof, but they do not close this source row because they do not prove the exact private-group A/B1/B2 exchange from the GE matrix. The missing fake-network row proof, criteria contract, runner scenario, and three-device harness path are repo-owned.

## Scope

- Add exact host fake-network proof for Alice plus Bob primary/sibling devices in one private group.
- Add `ge012` three-role simulator harness/runner support where `charlie` acts as Bob's restored sibling device.
- Add `ge012` criteria validation and criteria tests that allow Bob/Charlie to share one logical peer id while requiring distinct transport devices.
- Update source matrix, breakdown, and test inventory only after gates pass.

Out of scope: account-wide cloud sync, UI unread sync, device revocation, and unrelated multi-device GA rows.

## Execution Contract

The row closes only if:

- Alice, Bob primary, and Bob sibling start from one private group where Bob is one logical member with two active devices.
- Alice's message reaches both Bob devices exactly once as incoming.
- Bob primary's message reaches Alice as incoming and Bob sibling exactly once as a same-user mirrored `sent` row.
- Bob sibling's message reaches Alice as incoming and Bob primary exactly once as a same-user mirrored `sent` row.
- Bob primary and Bob sibling are not rejected as unbound devices and do not create duplicate logical Bob membership rows.
- The same contract passes in the three-device `ge012` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-012'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-012'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_multi_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/application/send_group_message_use_case_test.dart lib/features/groups/presentation/screens/group_conversation_wired.dart lib/features/feed/presentation/screens/feed_wired.dart lib/features/share/application/share_batch_delivery_coordinator.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge012 -d <alice,bob-primary,bob-sibling>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed integration_test/group_multi_party_device_real_harness.dart lib/features/groups/presentation/screens/group_conversation_wired.dart lib/features/feed/presentation/screens/feed_wired.dart lib/features/share/application/share_batch_delivery_coordinator.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart` |
| Hygiene | `git diff --check` |

## Recovery Input

The first GE-012 relay execution exposed a repo-owned product/harness blocker, not an external fixture blocker. Shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge012_QTDp25`, run id `1778675444038`, failed when Charlie-as-Bob-sibling sent `bobGe012SiblingSend`: Go emitted `group:validation_rejected` with reason `peer_mismatch`.

Root cause: the restored Bob sibling shares Bob's logical signing key. Without an explicit active transport binding, `sendGroupMessage` could select Bob primary's device binding for the sibling send, causing `senderTransportPeerId` to mismatch the live transport. The implementation now passes the current P2P peer id as `senderDeviceId` and `senderTransportPeerId` from product group send call sites and GE-012 harness sends, and the restored Bob sibling starts with a fresh transport identity while preserving logical account identity.

## Execution Evidence

| Gate | Result |
|---|---|
| Focused same-key send-use-case proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'same-key sibling'` passed (`+1`). |
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-012'` passed (`+1`). |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-012'` passed (`+3`). |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+169`). |
| Static analysis | Scoped `dart analyze` over GE-012 product, harness, criteria, runner, and test files passed with `No issues found!`. |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+125`). |
| Required three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge012 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` passed. Shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge012_j0W7hh`, run id `1778676353899`, verdict `ge012 proof passed: ge012 verdicts valid for alice, bob, charlie`. |
| Formatting and hygiene | Second `dart format --set-exit-if-changed ...` pass reported `Formatted 6 files (0 changed)`; `git diff --check` passed; targeted trailing-whitespace scan found no matches. |

## Current Verdict

Accepted/closed. GE-012 is covered with product/harness fixes, exact host and criteria coverage, broader group regression evidence, and the required three-device relay proof. Residual-only: none. GE-013 is the next unresolved P0 session.
