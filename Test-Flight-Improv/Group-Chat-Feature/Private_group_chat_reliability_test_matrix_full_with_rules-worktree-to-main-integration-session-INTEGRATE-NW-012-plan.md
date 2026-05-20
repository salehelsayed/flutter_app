# INTEGRATE-NW-012 Plan - Standard Integration Contract

Status: execution-complete-with-classified-residuals

Mode: standard worktree-to-main integration. This is import, reconcile, and verify work for the already-accepted source row. Do not recreate, rewrite, or rerun the original source worktree implementation plan as gap-closure work.

## Planning Progress

| date | role | concise evidence | decision/blocker | next action |
|---|---|---|---|---|
| 2026-05-20 CEST | Arbiter completed | Inspected the controlling integration breakdown (`INTEGRATE-NW-012` pending), accepted source NW-012 plan and source matrix row, current `drain_group_offline_inbox_use_case.dart` anchors, and current-main row-symbol search. Current main has no `NW-012`, `private_long_offline_epoch_churn`, or `nw012LongOfflineEpochConvergenceProof` anchors outside docs, but already has expected-recipient replay decrypt, durable synthetic cursor behavior, `_resolveStaleReplayEpoch`, `shouldSkipPreJoinReplay`, `enforceSelfJoinedAtLowerBound`, and revoked-device skip guards. | Execution-ready for one narrow standard integration pass. No planning blocker if the executor imports only missing row-owned NW-012 test/harness/script deltas and preserves current-main replay guards. | Execute row-scoped import/verification only, then close docs if proof passes. |

## Execution Progress

| date | phase | files inspected or touched | command/evidence | decision/blocker | next action |
|---|---|---|---|---|---|
| 2026-05-20 02:59:06 CEST | Contract extraction started | Plan file, allowed write-set status, source/current row-symbol searches | `git status --short -- <allowed write set>` showed the plan untracked and all allowed code/test/harness paths already dirty except no extra untracked owner files; full `git status --short` also showed many unrelated dirty files outside the row. Current-main `rg -n "NW-012|private_long_offline_epoch_churn|nw012LongOfflineEpochConvergenceProof" lib test integration_test <plan>` found only plan-documentation anchors. Source worktree search found accepted NW-012 anchors in the historical plan plus the expected test, criteria, harness, and runner files. | No dirty-state blocker; preserve all existing allowed-path edits and unrelated worktree changes. | Finish extracting the import/reconcile contract before any source edits. |
| 2026-05-20 03:01:00 CEST | Contract extraction completed | This plan and historical source row evidence from `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline` | Extracted scope: import only missing NW-012 selectors plus criteria/harness/runner support; default no production edit because current main already has expected-recipient decrypt, synthetic cursor, stale replay epoch resolution, pre-join skip, self-joined lower-bound enforcement, and revoked-device skip. Required gates remain the six NW-012 selectors, preservation selectors, runner discovery, scoped format/analyze, `git diff --check`, feasible `groups`/`completeness-check`, then fresh iOS 26.2 three-party live proof. | Execution can proceed in standard integration mode; no gap-closure or whole-file replacement allowed. | Inspect source/current hunks and merge only missing row-owned deltas. |
| 2026-05-20 03:08:00 CEST | Import/reconcile started | Source/current contexts for six test files, criteria script/test, runner, and live harness | Inspected source NW-012 blocks and current insertion anchors: drain after NW-010, send after NW-003, key rotation before RA-018, lifecycle after BB-012, fake-network after NW-003, criteria after NW-010 support, runner after `private_background_resume_group_delivery`, harness after NW-010 flow. Current production drain file still not proven missing a row-owned delta. | Proceed with row-owned tests plus criteria/runner/harness only; no production edit planned. | Apply surgical patches and then rerun row-symbol search. |
| 2026-05-20 03:24:00 CEST | Import/reconcile in progress | Touched only allowed NW-012 test, criteria, runner, harness, and plan files | Row anchors have been added to the six focused test files, criteria requirement/expected-message/validator/test helper surfaces, runner scenario switch/usage text, and harness role map plus NW-012 flow/proof helpers. No production file has been edited. No tests/gates have run yet. | No blocker currently recorded; harness dispatch still needs the `_runNw012*` scenario branch before import can be considered complete. | Finish harness dispatch hook, run `rg -n "NW-012|private_long_offline_epoch_churn|nw012LongOfflineEpochConvergenceProof" <allowed files>`, then run the first focused selector: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'NW-012'`. |
| 2026-05-20 03:29:00 CEST | Import/reconcile completed | Six focused test files, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`; plan file | Added harness dispatcher branch for `private_long_offline_epoch_churn`. Row-anchor sanity search over the allowed test/criteria/runner/harness files now finds NW-012 anchors in all required surfaces: six focused selectors, criteria scenario/proof validator, runner scenario discovery, and live harness role/proof flow. `git diff --stat -- <allowed write set>` is noisy because allowed files were already broadly dirty; no source-worktree files or closure docs were edited and no production edit was made in this pass. | No import blocker. | Start required focused tests with `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'NW-012'`. |
| 2026-05-20 03:30:00 CEST | Focused NW-012 selectors started | Focused selector files only | Starting required six-selector pass. First command: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'NW-012'`. | No blocker before test execution. | Run all six focused selectors, stopping only for a real row-owned compile/behavior blocker. |
| 2026-05-20 03:32:00 CEST | Focused NW-012 selector failed; row test setup fix started | `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | First selector failed because the test fixture still contained default `peer-sender`, causing final member-list assertion to see Alice/Bob/Charlie plus `peer-sender`. Replay filtering itself skipped stale/pre-join/removed-window/stale-epoch content and deduped final messages as expected in the command output. | Setup-only row-owned failure, not a production blocker. | Remove the default `peer-sender` member in the NW-012 test setup, then rerun the same selector. |
| 2026-05-20 03:33:00 CEST | Focused NW-012 selector passed | `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'NW-012'` passed after removing the default fixture member from the NW-012 setup. | No blocker. | Run `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'NW-012'`. |
| 2026-05-20 03:37:00 CEST | Focused NW-012 selectors completed | All six focused selector files | Passed: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'NW-012'`; `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'NW-012'`; `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'NW-012'`; `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-012'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-012'`; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-012'`. | No focused-selector blocker. | Start preservation selectors, beginning with `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'NW-003|NW-010'`. |
| 2026-05-20 03:38:00 CEST | Preservation selectors started | Source-adjacent and replay guard selector files | Starting required preservation pass. First command: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'NW-003|NW-010'`. | No blocker before preservation execution. | Run all preservation selectors, then runner discovery for `private_long_offline_epoch_churn`. |
| 2026-05-20 03:12:02 CEST | Bounded progress ledger refresh | Current import/test status | Import/reconcile is complete. All six focused NW-012 selectors have passed. Preservation selectors passed so far: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'NW-003|NW-010'`; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'RA-016|KE-018|NW-010|mixed epoch'`. | No blocker currently recorded. | Next exact command: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'NW-003|NW-006|NW-007|RA-018'`. |
| 2026-05-20 03:13:00 CEST | Preservation selectors completed with classified residual | Preservation selector files | Passed: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'NW-003|NW-006|NW-007|RA-018'`; `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --name 'RA-018|KE-021'`; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'KE-007|KE-009|ML-012'`. Red: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GI-022 revoked-device|GI-023 replay uses previous-epoch grace|GK-024 late-joining member skips pre-join replay|KE-021 future group inbox replay'` failed GI-022, GK-024, and GI-023 while KE-021 passed. Logs show replay decrypt succeeded, but no expected persisted message appeared; inspection shows the failing cases use fixed `2026-05-12` payload timestamps without `retentionNowUtc`, so on the current date `2026-05-20` they fall before the backlog retention cutoff and return before `handleIncomingGroupMessage`. | Classified as pre-existing date-sensitive preservation fixture residual outside NW-012 import; no production file was edited in this pass and the failure does not map to KE-007/KE-009/ML-012. | Continue non-mutating discovery with `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios`, then decide whether the red preservation residual blocks final acceptance before live proof. |
| 2026-05-20 03:14:00 CEST | Runner discovery completed | `integration_test/scripts/run_group_multi_party_device_real.dart` | `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios` passed and listed `private_long_offline_epoch_churn`. | No runner-discovery blocker. Preservation residual remains classified above. | Run scoped format/analyze on the NW-012-touched test/criteria/runner/harness files, then `git diff --check`. |
| 2026-05-20 03:15:00 CEST | Scoped format/analyze completed | NW-012-touched test, criteria, runner, and harness files | `dart format --set-exit-if-changed <NW-012 touched files>` changed `integration_test/scripts/group_multi_party_device_criteria.dart` on the first run and passed on rerun with 0 changes. `flutter analyze <NW-012 touched files>` passed with no issues. `git diff --check -- <NW-012 touched files plus this plan>` passed. Production drain file was excluded from format because it was already dirty but not edited in this pass. | No format/analyze/diff-check blocker. Preservation residual remains classified above. | Run feasible named gates starting with `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. |
| 2026-05-20 03:18:00 CEST | Named gates completed with classified residuals | `groups`, isolated membership rerun, `completeness-check` | `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` ran and finished red at `245 + / 8 -`. A serial diagnostic rerun of `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --reporter expanded --concurrency=1` isolated the reproducible visible failure to `GM-029 config version monotonicity converges across A/B/C shuffled delivery`, where expected `MemberRole.writer` but actual was `MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:9767`. `./scripts/run_test_gates.sh completeness-check` failed with `733/734 test files classified`, unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. | Classified as pre-existing broad-suite/documentation residuals outside NW-012 focused import. These block a clean accepted verdict unless closure explicitly accepts residual classification. | Run live preflight, select exactly three iOS 26.2 CoreSimulator UDIDs if available, then either run the live proof or record external/blocking status. |
| 2026-05-20 03:19:00 CEST | Live proof preflight completed | `flutter devices --machine`, `xcrun simctl list devices available`, stale-process check, `MKNOON_` env check | `flutter devices --machine` and `xcrun simctl list devices available` show at least three iOS 26.2 CoreSimulator devices. Selected exactly three: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Additional iOS 26.2 Dana device was intentionally not selected. `pgrep -fl 'run_group_multi_party_device_real|group_multi_party|flutter_tester|Runner' || true` returned no matching stale processes. `env | sort | rg '^MKNOON_' || true` returned no stale `MKNOON_` variables. | No `blocked_external_fixture`; enough simulators are available. Preservation and broad-gate residuals remain classified above. | Run `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_long_offline_epoch_churn -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. |
| 2026-05-20 03:24:00 CEST | Live proof completed | `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, relay-backed iOS 26.2 CoreSimulator run | `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_long_offline_epoch_churn -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C` passed. Run id: `1779239961594`. Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_long_offline_epoch_churn_wi1z0Y`. Orchestrator verdict: `[ORCH] private_long_offline_epoch_churn proof passed: private_long_offline_epoch_churn verdicts valid for alice, bob, charlie`. Role verdicts: Alice `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_long_offline_epoch_churn_wi1z0Y/gmp_1779239961594_alice_verdict.json`; Bob `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_long_offline_epoch_churn_wi1z0Y/gmp_1779239961594_bob_verdict.json`; Charlie `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_long_offline_epoch_churn_wi1z0Y/gmp_1779239961594_charlie_verdict.json`. | NW-012 live proof accepted; no external fixture blocker. | Record final execution verdict; do not update closure docs in this pass. |
| 2026-05-20 03:25:00 CEST | Final execution verdict | Allowed NW-012 files and this plan only | Row-owned import is complete. No production edit was made in this pass. All six focused NW-012 selectors passed; runner discovery passed; scoped format/analyze and `git diff --check` passed; live `private_long_offline_epoch_churn` proof passed with exactly three selected iOS 26.2 simulators. Residual red gates remain classified: date-sensitive non-NW replay preservation fixtures, `groups` broad gate `GM-029` membership residual, and `completeness-check` unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. | Verdict: `completed_with_classified_residuals`. NW-012 row import/proof is accepted, but this is not a clean global gate verdict because classified non-NW residual gates remain red. | Stop execution. Leave integration breakdown and test-inventory closure updates to the separate closure phase. |

## Scope

Own exactly integration row `INTEGRATE-NW-012`, sourced from historical row `NW-012`: "Long offline reconnect with multiple epoch changes converges."

The source row contract is Charlie offline while Alice and Bob run add/remove/re-add membership churn, rotate through multiple key epochs, and send several messages. On reconnect, Charlie must converge to the final active membership and latest key epoch, receive only final active-interval messages, and not render removed-window, stale first-interval, stale old-epoch, or duplicate replay content.

This is standard integration mode. Import or verify only missing row-owned deltas in current main. Do not implement adjacent reliability, chaos, dial/disconnect, media, notification, UI, privacy, Go/native, broader relay/shared-state, or stress work.

## Source Of Truth And Classification

Source of truth:

- Controlling integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-012-plan.md`.
- Historical source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`, row `NW-012`.
- Current main code/tests win over stale source prose for conflicts. The accepted source closure evidence wins for row ownership and required proof shape. The controlling integration breakdown wins for current integration status.

Already present in current main:

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` already passes `expectedRecipientPeerId: selfPeerId` into replay decrypt paths.
- The same file already has durable synthetic cursor behavior through `groupInboxSyntheticSinceCursorPrefix`.
- Current-main-only replay protections absent from the source row must be preserved: `_resolveStaleReplayEpoch`, `shouldSkipPreJoinReplay`, `enforceSelfJoinedAtLowerBound: true`, and revoked-device replay skip handling.

Missing row-owned artifacts in current main:

- Six focused NW-012 selectors in:
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
- `private_long_offline_epoch_churn` criteria, live harness, and runner support.
- Post-execution closure updates in this plan, `test-inventory.md`, and the integration breakdown.

## Allowed Execution Write Set

Production code:

- Default expectation: no production edit. Current main already has the key NW-012 production repair behavior and newer replay guards.
- If source/current hunk inspection proves a tiny row-owned production delta is still missing, the only allowed production file is `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`.
- Any production edit must merge surgically and preserve `_resolveStaleReplayEpoch`, `shouldSkipPreJoinReplay`, `enforceSelfJoinedAtLowerBound`, revoked-device skip, expected-recipient decrypt, and durable synthetic cursor behavior. Whole-file replacement is forbidden.

Tests:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Harness/scripts:

- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`

Closure docs after successful execution:

- This plan file.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.

Explicit exclusions:

- Do not edit source worktree files, source matrix, source session breakdown, COMPLETE_1 docs, Go/native files, unrelated production files, unrelated scripts, broader harness scenarios, adjacent row plans, or any non-NW-012 docs.
- Do not revert, reset, overwrite, or wholesale copy files over current-main edits.

## Device/Relay Proof Profile

NW-012 requires a fresh three-party iOS 26.2 CoreSimulator live proof. The historical source run `1778694869611` is source evidence only; do not assume its old UDIDs are currently available.

Fresh availability and hygiene checks before live proof:

```bash
flutter devices --machine
xcrun simctl list devices available
pgrep -fl "run_group_multi_party_device_real|group_multi_party|flutter_tester|Runner" || true
env | sort | rg '^MKNOON_' || true
```

The executor must choose exactly three currently available iOS 26.2 CoreSimulator device IDs from the fresh checks and record Alice, Bob, and Charlie IDs in the closure evidence.

Relay env:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
```

Live proof command shape:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario private_long_offline_epoch_churn \
  -d <ALICE_IOS_26_2_UDID>,<BOB_IOS_26_2_UDID>,<CHARLIE_IOS_26_2_UDID>
```

Closure evidence must record the exact device IDs, run id, shared dir, orchestrator verdict text, orchestrator verdict path, and all role verdict paths. Proof is invalid if any app peer is not iOS 26.2 CoreSimulator.

## Execution Sequence

1. Run a dirty-state check for the allowed write set and preserve all unrelated edits.
2. Inspect source NW-012 hunks and current insertion contexts. Do not copy whole files.
3. Re-run current-main symbol searches for `NW-012`, `private_long_offline_epoch_churn`, and `nw012LongOfflineEpochConvergenceProof`.
4. Merge only missing NW-012 test, criteria, runner, and live-harness deltas.
5. Treat production behavior as already present unless hunk inspection proves a precise missing NW-012 delta. If production is touched, preserve all current-main guards listed above.
6. Run the six focused NW-012 selectors.
7. Run current-main preservation selectors for source-adjacent behavior and replay guards.
8. Run runner/criteria discovery for `private_long_offline_epoch_churn`.
9. Run scoped format/analyze and `git diff --check`.
10. Run `groups` and `completeness-check` if feasible; classify pre-existing residuals separately.
11. Run the fresh iOS 26.2 live proof with the relay env.
12. Only after green focused, preservation, hygiene, and live evidence, update this plan, `test-inventory.md`, and the integration breakdown with closure evidence.

## Tests And Gates

Focused NW-012 selectors:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'NW-012'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'NW-012'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'NW-012'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-012'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-012'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'NW-012'
```

Source-adjacent preservation selectors:

```bash
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'NW-003|NW-010'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'RA-016|KE-018|NW-010|mixed epoch'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'NW-003|NW-006|NW-007|RA-018'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --name 'RA-018|KE-021'
```

Current-main replay guard preservation selectors:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GI-022 revoked-device|GI-023 replay uses previous-epoch grace|GK-024 late-joining member skips pre-join replay|KE-021 future group inbox replay'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'KE-007|KE-009|ML-012'
```

Runner/criteria discovery:

```bash
dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios
```

Scoped maintenance:

```bash
dart format --set-exit-if-changed lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart
flutter analyze lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart
git diff --check
```

Named gates if feasible:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

## Conflict And Blocker Rules

- Block as `blocked_conflict` if the production hunk cannot preserve both the accepted NW-012 source contract and current-main replay guards.
- Block if fewer than three iOS 26.2 CoreSimulator devices are available after fresh checks.
- Block if live proof uses old source UDIDs without fresh availability evidence.
- Block or defer to the owning row if a failure maps to KE-007, KE-009, or ML-012 instead of NW-012.
- Block if a focused NW-012 selector fails for real behavior after import and fixing it would require broader production, native, relay, or harness architecture outside the allowed write set.
- Record but do not fix unrelated broad-suite residuals unless directly caused by the NW-012 import.

## Done Criteria And Scope Guard

Done criteria:

- All six focused NW-012 selectors are present in current main and pass.
- `private_long_offline_epoch_churn` is discoverable in the runner and has strict `nw012LongOfflineEpochConvergenceProof` criteria that accept complete Alice/Bob/Charlie iOS 26.2 proof and reject wrong row, non-iOS-26.2, leakage, duplicates, unordered drain, and weak convergence.
- Preservation selectors pass or have exact non-NW-012 residual classification.
- Scoped format/analyze and `git diff --check` pass, or unchanged pre-existing analyzer issues are classified outside touched lines.
- Fresh iOS 26.2 three-party live proof passes and closure records exact device IDs, run id, shared dir, orchestrator verdict, and role verdict paths.
- This plan, `test-inventory.md`, and the integration breakdown are updated only after proof passes.

Scope guard:

- Do not edit source docs or source worktree artifacts.
- Do not close NW-013, NW-014, NW-015, KE-007, KE-009, ML-012, UI, notification, media, privacy, stress, or broader network rows by implication.
- Do not use Go/native proof as a substitute; source NW-012 required no Go/native proof.
- Do not accept non-iOS-26.2, Android, physical iOS, macOS app-peer, web, or desktop proof for this row.
- Do not replace `drain_group_offline_inbox_use_case.dart` wholesale or remove current-main replay protections.

## Reviewer Pass

Sufficiency: sufficient for standard integration.

Missing files/tests/gates: none structurally. The plan names the exact focused selectors, current-main preservation guards, allowed files, runner discovery, scoped maintenance, named gates, and iOS 26.2 live proof profile.

Stale assumptions: device IDs are deliberately not fixed from source evidence. The executor must rerun availability checks.

Overengineering: avoided. Production edits are expected to be unnecessary and are allowed only as a narrow reconciled exception in `drain_group_offline_inbox_use_case.dart`.

## Arbiter Decision

Final verdict: execution-ready for `INTEGRATE-NW-012` only.

Structural blockers remaining: none in the plan.

Incremental details intentionally deferred: exact hunk placement and current-main fixture adaptation are deferred to the executor after dirty-state and hunk inspection.

Accepted differences intentionally left unchanged: no Go/native proof, no old source UDID assumption, no adjacent-row closure, and no wholesale production replacement.

## Closure Audit Result

Closure verdict: `accepted`.

The execution status remains `execution-complete-with-classified-residuals`: row-owned NW-012 import/proof passed, and the remaining red commands are classified as non-NW-012 residuals rather than blockers. No production edit was made in this pass; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` was intentionally left untouched because current main already had expected-recipient decrypt, durable synthetic cursor behavior, and the replay guards required for this row.

Closed for INTEGRATE-NW-012: six focused NW-012 selectors, source-adjacent preservation selectors, runner discovery for `private_long_offline_epoch_churn`, scoped format/analyze/diff hygiene, and the fresh iOS 26.2 three-party live proof. Live proof used Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; run id `1779239961594`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_long_offline_epoch_churn_wi1z0Y`; orchestrator verdict `[ORCH] private_long_offline_epoch_churn proof passed: private_long_offline_epoch_churn verdicts valid for alice, bob, charlie`; role verdicts were written to `gmp_1779239961594_alice_verdict.json`, `gmp_1779239961594_bob_verdict.json`, and `gmp_1779239961594_charlie_verdict.json` in that shared dir.

Residual-only items preserved outside NW-012: fixed-date replay preservation fixtures `GI-022`, `GK-024`, and `GI-023` now age before the retention cutoff on 2026-05-20 while `KE-021` still passes; the broad `groups` gate remains red on pre-existing `GM-029` membership-role convergence; and `completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification. NW-013, NW-014, NW-015, KE-007, KE-009, ML-012, UI, notification, media, privacy, stress, and broader network rows are not closed by this result.
