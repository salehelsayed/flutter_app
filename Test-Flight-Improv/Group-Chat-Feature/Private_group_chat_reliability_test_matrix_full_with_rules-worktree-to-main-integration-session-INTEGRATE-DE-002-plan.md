# INTEGRATE-DE-002 Rapid Per-Sender Ordering Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-002 | Rapid sequential messages preserve per-sender order`.
- Source worktree plan: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-002-plan.md` in `worktrees/full-rules-pipeline`.
- Source closure status: `accepted` / `covered`, accepted on 2026-05-12 18:04:06 CEST.
- Integration mode: standard worktree-to-main import/reconcile/verify. This contract does not recreate the source implementation plan and does not expand the row beyond DE-002.

## Integration Scope

Import only the missing DE-002 row-owned delta into main:

- Replace the older same-sender ordering smoke with a DE-002 100-message A/B/C fake-network proof that Bob and Charlie receive Alice's rapid sequence in exact order and Alice's outgoing rows remain ordered.
- Add `de002` scenario criteria requirements, expected proof messages, ordered-delivery validation, and positive/negative criteria tests.
- Add `de002` runner discovery and live-harness role/proof support.
- Update the worktree-to-main ledger and test inventory after verification.

Already-present and skipped as duplicate:

- `lib/core/bridge/bridge_group_helpers.dart` already has `callGroupInboxRetrieveWithCursor` transient retry, adaptive page-size retry, reconnect, and transient cursor error classification.
- `test/core/bridge/bridge_group_helpers_test.dart` already has cursor EOF/retry/page-size shrink coverage for `callGroupInboxRetrieveWithCursor`.

Do not import DE-003+, message-id preservation, duplicate replay dedupe, sender self-echo, publish result semantics, timeout handling, callback routing, native dispatcher panic handling, source matrix/session docs, or unrelated source-worktree changes.

## Verification Contract

- Focused DE-002 host smoke selector.
- Focused DE-002 criteria selector.
- Bridge cursor preservation selector for already-present helper behavior.
- Scoped analyzer and `git diff --check`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, preserving known non-DE-002 residual failures.
- `./scripts/run_test_gates.sh completeness-check`, preserving unrelated fake-network classification residuals.
- iOS 26.2 live `de002` proof with exact simulator device ids and run id recorded.

## Execution Evidence

Imported row-owned test/proof hooks in `test/features/groups/integration/group_messaging_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`; updated `test-inventory.md` and this integration ledger. No production code was changed for DE-002 because the source bridge cursor retry helper behavior was already present in main.

Passed verification:

- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'DE-002'` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'DE-002'` (`+3`)
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupInboxRetrieveWithCursor'` (`+6`)
- `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` (`No issues found!`)
- `dart format integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` (`0 changed`)
- Scoped `git diff --check` on the DE-002 owner files passed before doc closure.

iOS 26.2 live proof evidence: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario de002 -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C` passed with run id `1779133511785` and shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_de002_pMWlNF`. Devices were Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` (`UP004 Alice iPhone 17 Pro iOS 26.2`), Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9` (`UP004 Bob iPhone Air iOS 26.2`), and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` (`UP004 Charlie iPhone 17 iOS 26.2`). Final result: `de002 proof passed: de002 verdicts valid for alice, bob, charlie`. Alice, Bob, and Charlie verdict files were written under the shared dir as `gmp_1779133511785_alice_verdict.json`, `gmp_1779133511785_bob_verdict.json`, and `gmp_1779133511785_charlie_verdict.json`.

Named gate evidence: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+195 -3` only on preserved non-DE-002 residuals `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` (`Expected: not null / Actual: <null>` at `invite_round_trip_test.dart:679`), `BB-012 restart recovery drains replay before ack and stays live` (`Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `group_startup_rejoin_smoke_test.dart:842`), and `GM-029 config version monotonicity converges across A/B/C shuffled delivery` (`Expected: MemberRole.writer / Actual: MemberRole.reader` at `group_membership_smoke_test.dart:8144`). The DE-002 selector passed independently before this named-gate run. `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Final Verdict

Accepted. DE-002 is integrated with row-owned 100-message host ordering proof, criteria validation/tests, runner/live-harness support, iOS 26.2 live `de002` evidence, inventory update, and ledger evidence. Already-present bridge cursor retry behavior was verified and skipped as duplicate.
