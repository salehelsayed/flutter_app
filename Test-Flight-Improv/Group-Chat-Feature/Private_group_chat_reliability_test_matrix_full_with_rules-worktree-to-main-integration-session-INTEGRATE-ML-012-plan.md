Status: accepted
Acceptance Status: accepted
Mode: standard worktree-to-main integration, not gap-closure
Source row: `ML-012 | Concurrent admin membership edits resolve deterministically`
Integration row: `INTEGRATE-ML-012`

# INTEGRATE-ML-012 Worktree-to-Main Integration Contract

## Planning Evidence

- 2026-05-18 - Started after `INTEGRATE-ML-011` reached `skipped_already_present` and the integration breakdown safe next action became `INTEGRATE-ML-012`.
- Source ML-012 is `Covered`/`accepted` in `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-012-plan.md`.
- Source final evidence records committed harness stabilization `c84021b4` and iOS 26.2 `private_concurrent_admin_membership_edits` live proof run `1778945046120` in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_concurrent_admin_membership_edits_KlF28h`, with valid Alice/Bob/Charlie/Dana verdicts.
- Source blocker history is preserved: runs `1778863088562` and `1778926443606` failed on relay reservation/discovery timeouts before the source harness stabilization.
- Source touched-file inventory from the historical row plan/evidence: `lib/features/groups/application/group_message_listener.dart`; `test/features/groups/application/group_message_listener_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart`; `integration_test/group_multi_party_device_real_harness.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`.
- COMPLETE_1/main overlap considered for preservation: concurrent admin mutation coverage around `GE-016`, stale remove/re-add ordering around `GM-012`, and duplicate add/remove preservation around `GM-009`, `GM-010`, and `GM-011`.
- Current-main classification before this row: ML-012 row literals and `private_concurrent_admin_membership_edits` support were missing or partial, while adjacent COMPLETE_1 preservation behavior was already present. The row-owned deterministic membership merge, host/fake proof, criteria, runner, and harness deltas were therefore imported narrowly.
- Source RA-018 retry helper and `_rotateRa018Key` wiring from `c84021b4` were not imported because they are not ML-012 row-owned in current main, current main has no RA-018 harness path, and the fresh ML-012 failure stayed in member-exclusion delivery at key epoch `1`, not key-update retry.

## Execution Evidence

- Row-owned production/test/harness files integrated or verified for ML-012:
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
  - `integration_test/group_multi_party_device_real_harness.dart`
  - `integration_test/scripts/run_group_multi_party_device_real.dart`
- Imported meaningful production behavior in `group_message_listener.dart`: membership add snapshots are applied without pruning unrelated omitted members; same-target stale add/re-add is gated by persisted removal tombstones; membership removal applies against a rebuilt local config snapshot so independent concurrent adds are preserved; Go config sync uses the merged local truth.
- Imported row-owned host/fake proof: listener tests cover concurrent remove-C/add-D delivery orders and same-target remove/re-add timestamp ordering; fake-network smoke proves held delivery orders converge; criteria tests accept and reject `private_concurrent_admin_membership_edits` proof fields.
- Imported harness/runner support: `private_concurrent_admin_membership_edits` is listed, role-mapped, and backed by Alice/Bob/Charlie/Dana proof flows. Current harness also includes the source member-wait stabilization relevant to ML-012: drain-backed member inclusion/exclusion waits, self-removal waits, bounded group inbox drains, and key-epoch waits with group/P2P drains plus periodic health checks.

## Verification

Passed focused ML-012 verification:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart --plain-name "ML-012"
```

Result: pass, `+4`.

Passed preservation verification:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name "GM-011|GM-012"
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name "GE-016|GM-009|GM-010|GM-011|GM-012|GM-022"
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name "GM-009|GM-011|GM-012"
```

Results: pass, `+2`, `+6`, and `+19`.

Passed scenario listing and hygiene:

```bash
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_concurrent_admin_membership_edits --list-scenarios
dart format integration_test/group_multi_party_device_real_harness.dart
dart analyze integration_test/group_multi_party_device_real_harness.dart
git diff --check
```

Results: `private_concurrent_admin_membership_edits` was listed; format completed with `0 changed`; harness analyzer reported `No issues found!`; diff hygiene passed before doc closure. No Go files were touched for this row, so `gofmt` was not applicable.

## Fresh Live Proof

Pre-stabilization main attempt failed:

- Run id: `1779090790143`
- Evidence dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_concurrent_admin_membership_edits_tj0RuA`
- Result: Dana timed out in `_waitForMemberExclusion`; Alice timed out waiting for `dana_observed_charlie_removed`; logs showed relay reservation/discovery and dial-backoff failures.

Fresh post-stabilization main attempt also failed:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_concurrent_admin_membership_edits -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76
```

- Run id: `1779091658178`
- Evidence dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_concurrent_admin_membership_edits_lYMngV`
- Exit code: `255`
- Result: Dana again timed out in `_waitForMemberExclusion` before writing a verdict, and Alice timed out waiting for `gmp_1779091658178_dana_observed_charlie_removed`.
- Failure signature: Alice published Charlie removal and Bob/Charlie progressed, but Dana repeatedly drained only a stale `members_added` replay, kept `GROUP_MEMBERS_DB_LOAD_ALL_SUCCESS count:4`, never observed Alice's removal, and logs contained direct/relay dial backoff plus missing peer/topic peer instability.
- Classification: `blocked_external_fixture/relay-discovery-group-inbox-delivery-timeout`. No remaining repo-owned ML-012 delta was identified after source member-wait stabilization was imported and focused/preservation tests passed.

Focused recovery rerun after later shared fixture repairs also failed:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_concurrent_admin_membership_edits -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76
```

- Run id: `1779394615524`
- Evidence dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_concurrent_admin_membership_edits_0s7Idi`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`; all are iOS 26.2 CoreSimulator devices.
- Exit code: `255`.
- Orchestrator result: no orchestrator verdict; `Bad state: dana exited with code 1 before writing a verdict`.
- Verdict files: Bob and Charlie wrote partial `ml012ConcurrentAdminEditsProof` verdicts; Alice and Dana did not write verdict JSON, so the row acceptance contract was not satisfied.
- Failure signature: Dana timed out in `_waitForMemberExclusion` (`group_multi_party_device_real_harness.dart:2812`, called from `_runMl012Dana`), kept loading four members and repeatedly drained one stale `members_added` replay; Alice timed out waiting for `gmp_1779394615524_dana_observed_charlie_removed` (`_runMl012Alice`). Logs also recorded discovery/backoff instability: Dana saw `missingPeers:2`, `topicPeers:1`, `backoff`, direct dial deadline failures, and relay dial backoff; Alice later saw an inbox retrieve `read length: deadline exceeded` and recovered relay health after the row was already blocked.
- Classification: still `blocked_external_fixture/relay-discovery-group-inbox-delivery-timeout`. Later shared fixture repairs `f9a31437`, `9b3bfac8`, and `9ab39042` did not recover the ML-012 `private_concurrent_admin_membership_edits` live path.

Focused fixture repair:

- Repaired only the ML-012 `private_concurrent_admin_membership_edits` live harness path in `integration_test/group_multi_party_device_real_harness.dart`.
- Root cause narrowed from the failed artifacts: Dana could miss Alice's live Charlie-removal publish during relay/discovery churn, while the helper stored removal replay only for Charlie. Bob and Charlie could complete from live delivery; Dana repeatedly drained only the stale `members_added` replay and never had a durable removal replay to apply.
- Repair: `_runMl012Alice` now waits until Alice has locally applied Bob's Dana-add event before removing Charlie, then passes Dana's peer id as an additional durable replay recipient to `_removeCharlieAndPublish`. This keeps the concurrent admin edit contract intact without timeout expansion or unrelated product rewrites.

Successful focused recovery proof:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_concurrent_admin_membership_edits -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76
```

- Run id: `1779395988799`
- Evidence dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_concurrent_admin_membership_edits_RLkRDR`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`; all are iOS 26.2 CoreSimulator devices.
- Orchestrator verdict: `private_concurrent_admin_membership_edits proof passed: private_concurrent_admin_membership_edits verdicts valid for alice, bob, charlie, dana`.
- Verdict files: `gmp_1779395988799_alice_verdict.json`, `gmp_1779395988799_bob_verdict.json`, `gmp_1779395988799_charlie_verdict.json`, and `gmp_1779395988799_dana_verdict.json`.
- Proof summary: Alice, Bob, and Dana verdicts include `ml012ConcurrentAdminEditsProof` with `rowId=ML-012`, `memberSetsConverged=true`, `independentAddPreserved=true`, `removedCharlieExcluded=true`, and `sameTargetTieRemoveWins=true`; Charlie's removed-role verdict includes `postRemovalGroupAbsent=true`, `removedCharlieExcluded=true`, and `sameTargetTieRemoveWins=true`.

Post-repair focused checks passed:

```bash
dart format --set-exit-if-changed integration_test/group_multi_party_device_real_harness.dart
flutter analyze --no-pub integration_test/group_multi_party_device_real_harness.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart --plain-name "ML-012"
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name "GM-011|GM-012"
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name "GE-016|GM-009|GM-010|GM-011|GM-012|GM-022"
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name "GM-009|GM-011|GM-012"
```

Results: format passed with `0 changed`; analyzer reported `No issues found! (ran in 51.6s)`; focused ML-012 selector passed `+4`; preservation selectors passed `+2`, `+6`, and `+19`.

## Scope

Allowed integration action was limited to importing or verifying ML-012 row-owned membership merge, host/fake proof, criteria, runner, and live harness support.

Out of scope: `ML-013+`, source worktree docs, COMPLETE_1 docs, source matrix docs, unrelated RA-018/key-rotation harness changes, notification, media, history, UI, broader lifecycle churn, and timeout increases as a main fix.

## Final Verdict

`INTEGRATE-ML-012` is `accepted`.

The row-owned meaningful main delta is imported, the narrow live-harness replay repair is in place, focused/preservation checks are green, and required fresh iOS 26.2 live proof run `1779395988799` passed with valid Alice/Bob/Charlie/Dana `ml012ConcurrentAdminEditsProof` verdicts.

Next safe action: do not reopen ML-012 in this recovery pass. The only remaining integration-program blockers are `KE-007` and `KE-009` conflict re-reconciliation.
