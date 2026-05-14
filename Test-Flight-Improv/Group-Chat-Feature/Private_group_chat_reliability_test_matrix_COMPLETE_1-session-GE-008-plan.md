# GE-008 Session Plan: Simultaneous Send Storm During Remove/Re-add

Status: accepted

## Gap-Closure Reconciliation

Preflight found GE-008 source row `Open`: Alice, Bob, and Charlie send continuously while Charlie is removed and re-added; the row closes only when no entitled message is lost, removed-window cutoff behavior is deterministic, and duplicate timeline spam is absent. The breakdown ledger row 167 classified this as `needs_code_and_tests` / `implementation-ready`.

Initial repo inspection found adjacent GE-005, GE-006, and GE-007 coverage, but no exact `GE-008` fake-network regression, no `ge008` criteria contract, no `ge008` runner scenario, and no three-device harness path. This was repo-owned test/harness work, not an external blocker, and is now closed by the execution evidence below.

## Scope

- Add exact host fake-network proof for GE-008.
- Add `ge008` three-role simulator harness/runner support.
- Add `ge008` criteria validation and criteria tests.
- Update source matrix, breakdown, and test inventory only after gates pass.

Out of scope: unrelated GE rows, unrelated transport/protocol refactors, media/quote rows, and final program verdict.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start in one private group.
- A/B/C send a pre-removal storm and active members receive every message exactly once despite duplicate live delivery.
- Alice removes Charlie; Alice and Bob continue a removed-window storm while Charlie attempts stale sends.
- Alice/Bob receive every removed-window A/B message exactly once, Charlie receives none of the removed-window messages, and Charlie's stale removed-window sends do not publish or render.
- Alice re-adds Charlie; A/B/C send a post-readd storm and active members receive every post-readd message exactly once.
- Durable recipient sets match each entitlement window: all other active members pre/post re-add, and only the remaining member during the removed window.
- The same contract passes in the three-simulator `ge008` relay harness.

## Device/Relay Proof Profile

- Profile: three-party/device-lab required closure evidence.
- Availability check for this run: reuse the configured iOS three-device relay proof profile already proven live for GE-005 through GE-007.
- Required devices: Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Required relay env: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`.
- Required command: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge008 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-008'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-008'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `flutter analyze --no-pub integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge008 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` |
| Hygiene | `git diff --check` |

## Execution Evidence

- Added exact host proof in `test/features/groups/integration/group_messaging_smoke_test.dart::GE-008 simultaneous send storm during remove/re-add keeps entitlement windows exact`.
- Added `ge008` criteria, runner, and three-role device harness support in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-008'` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-008'` passed (`+3`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+157`).
- `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` passed with no issues.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+121`).
- Required relay proof passed: shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge008_8DkrLF`, run id `1778668448619`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, verdict `ge008 proof passed: ge008 verdicts valid for alice, bob, charlie`.

## Current Verdict

Accepted/closed. GE-008 now has exact host proof, criteria contract coverage, runner/harness support, broader host regression evidence, scoped analyzer evidence, and required three-device relay evidence. No residual GE-008 blockers remain; GE-009 is the next unresolved P0 row.
