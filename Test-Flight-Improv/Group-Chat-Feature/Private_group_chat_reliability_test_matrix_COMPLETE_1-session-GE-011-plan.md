# GE-011 Session Plan: Partial Live Topic Peers Plus Inbox Fallback

Status: accepted

## Gap-Closure Reconciliation

Preflight found GE-011 source row `Open`: Alice sends while Bob is a live topic peer and Charlie is offline; Bob must receive live, Charlie must retrieve from inbox, and duplicate live-plus-inbox delivery must dedupe.

The breakdown ledger row 170 classifies GE-011 as `needs_code_and_tests` / `implementation-ready`. GE-010 now proves the adjacent zero-live-peer fallback path, but it does not prove the mixed live plus durable replay contract or Bob's dedupe behavior when an already-live recipient later sees the same durable inbox payload. Because the missing host proof, criteria contract, runner scenario, and three-device harness path are repo-owned, this row remains implementation work.

## Scope

- Add exact host fake-network proof for GE-011 partial-live-topic-peer durable fallback and dedupe.
- Add `ge011` three-role simulator harness/runner support.
- Add `ge011` criteria validation and criteria tests.
- Update source matrix, breakdown, and test inventory only after gates pass.

Out of scope: unrelated GE rows, broad transport refactors, and final program verdict.

## Execution Contract

The row closes only if:

- Alice/Bob/Charlie start from a private group state.
- Bob remains a live topic peer and Charlie is not a live topic peer when Alice sends.
- Alice's send reports a partial live peer count, sender status `sent`, and durable inbox custody for Bob and Charlie.
- Bob receives the message live during the send window.
- Charlie receives no live delivery during the send window, then returns and drains the inbox.
- Bob drains a duplicate durable replay after live receipt and still persists the Alice message exactly once.
- Charlie persists the Alice message exactly once from durable replay.
- Alice/Bob/Charlie remain converged on final A/B/C membership and key epoch.
- The same contract passes in the three-device `ge011` relay harness.

## Required Gates

| Gate | Command |
|---|---|
| Focused fake-network proof | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-011'` |
| Criteria focused proof | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-011'` |
| Criteria full regression | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` |
| Static analysis | `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` |
| Three-device relay proof | `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge011 -d <alice,bob,charlie>` |
| Broader group smoke gate | `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` |
| Formatting | `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` |
| Hygiene | `git diff --check` |

## Execution Evidence

Implemented GE-011 as row-owned host, criteria, runner, and three-device harness coverage. `test/features/groups/integration/group_messaging_smoke_test.dart::GE-011 partial live topic peers use live plus inbox fallback and dedupe` creates joined Alice/Bob/Charlie private group state, keeps Bob live while Charlie is off the live topic, sends from Alice with `publishTopicPeersOverride: 1`, proves Alice reports `success`, `topicPeers == 1`, sender status `sent`, and durable inbox custody for Bob and Charlie, proves Bob receives live while Charlie receives no live delivery, then replays the durable payload and proves Bob and Charlie each persist exactly one Alice message after dedupe/rejoin.

Added repo-owned `ge011` criteria, runner, and harness support in `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. The criteria validator accepts only verdicts that prove partial live peers, Bob live receipt, Charlie no-live-then-inbox receipt, duplicate replay dedupe, final A/B/C membership, and shared key epoch.

Passed gates:

- `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` passed after formatting.
- `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` passed with no issues.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-011'` passed (`+3`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-011'` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+166`).
- Required three-device relay proof passed: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge011 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge011_gfMpyN`, run id `1778673583563`, verdict `ge011 proof passed: ge011 verdicts valid for alice, bob, charlie`.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`+124`).

## Current Verdict

Accepted/closed. GE-011 is `Covered` in the source matrix with exact host, criteria, broader host, scoped analyzer, formatting, diff hygiene, and required three-device relay evidence. Residual-only: none for GE-011. GE-012 is the next unresolved P0 session; no final program verdict is written because unresolved rows remain.
