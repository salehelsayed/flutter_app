# INTEGRATE-ML-005 Worktree-to-Main Integration Contract

Status: execution-ready

Source row: `ML-005`, "Remove an online member and converge remaining members"

Mode: standard worktree-to-main integration. This is not gap-closure and is not a new implementation plan.

## Planning Progress

- 2026-05-17 19:35:48 CEST - Evidence Collector completed. Files inspected since last update: integration breakdown ML-005 ledger/contract, source matrix row ML-005, source breakdown session ML-005, historical ML-005 plan/evidence, COMPLETE_1 GM-004 overlap rows, source/current anchors, and current `git status --short`. Decision/blocker: source ML-005 was tests/harness/docs-only with production untouched; current main has GM-004 overlap but no `ML-005`, `private_online_remove`, or `ml005OnlineRemovalProof` anchors. Next action: draft minimal import/reconcile/verify contract.
- 2026-05-17 19:35:48 CEST - Planner started. Files inspected since last update: same evidence set. Decision/blocker: no blocker; contract must import only the ML-005 subset and must not pull later source `private_online_remove` proof expansions. Next action: write scoped integration sections with duplicate checks, device proof policy, and ledger policy.
- 2026-05-17 19:36:46 CEST - Planner completed. Files inspected since last update: source ML-005 changed-file inventory, COMPLETE_1 GM-004 row, and current main anchor searches. Decision/blocker: reusable minimal integration contract drafted around compare/import/verify only. Next action: reviewer pass for missing overlap, live proof, and dirty-worktree details.
- 2026-05-17 19:36:46 CEST - Reviewer completed. Files inspected since last update: drafted contract sections. Decision/blocker: sufficient after explicitly requiring GM-004 preservation, live `private_online_remove` rerun, and production-untouched default. Next action: arbiter finalizes readiness.
- 2026-05-17 19:36:46 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final contract. Decision/blocker: no structural blockers remain; this is execution-ready as a minimal integration contract. Next action: executor may reconcile ML-005 into main without touching source worktree files.

## Execution Progress

- 2026-05-17 19:41:01 CEST - Contract extraction started. Files inspected or touched: this plan, current `git status --short`, execution QA skill. Command currently running: none. Decision/blocker: spawned execution is available through `codex exec`; preserve existing dirty worktree and inspect exact target/source files before edits. Next action: extract scope, gates, duplicate checks, and user ledger override.
- 2026-05-17 19:41:01 CEST - Contract extracted. Files inspected or touched: this plan. Command currently running: none. Decision/blocker: scope is ML-005 import/reconcile/verify only; allowed write set is six likely import files plus this plan, with production edits only if exact ML-005 proof fails. User instruction narrows the plan by forbidding integration breakdown ledger updates in this run. Next action: spawn Executor with bounded ML-005 contract.
- 2026-05-17 19:41:26 CEST - Executor spawned/running. Files inspected or touched: this plan. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh"`. Decision/blocker: Executor receives only the ML-005 plan, six import targets, source anchors, duplicate/overlap checks, focused tests, gates, live proof policy, and no-ledger user override. Next action: wait for Executor result, then spawn QA Reviewer.
- 2026-05-17 19:42:09 CEST - Executor spawn retry. Files inspected or touched: this plan. Command currently running: none. Decision/blocker: first `codex exec` invocation rejected `-a` as a subcommand option before any child work started; retrying with approval policy passed as a top-level Codex option. Next action: spawn Executor again with the same bounded ML-005 contract.
- 2026-05-17 19:43:11 CEST - Executor duplicate checks starting. Files inspected or touched: this plan, current `git status --short`. Command currently running: duplicate/overlap `rg` checks from this plan. Decision/blocker: target files are already dirty in main; inspect and preserve their current contents before applying any ML-005 import. Next action: run exact duplicate/overlap checks and classify ML-005/GM-004 presence.
- 2026-05-17 19:43:43 CEST - Executor duplicate checks completed. Files inspected or touched: this plan, six ML-005 targets, COMPLETE_1 overlap ledger. Command currently running: none. Decision/blocker: `rg "ML-005|private_online_remove|ml005OnlineRemovalProof"` returned no matches in the six targets, so this is not `skipped_already_present`; GM-004 anchors remain present in smoke, criteria, runner, harness, and criteria tests. Next action: inspect historical ML-005 anchors and current target regions before importing only missing ML-005 deltas.
- 2026-05-17 19:45:56 CEST - Executor file inspection completed; import starting. Files inspected or touched: six main targets and historical source anchors for the two direct tests, fake-network ML-005 smoke, `private_online_remove` mapping, and `ml005OnlineRemovalProof` validation/tests. Command currently running: none. Decision/blocker: candidate classification is import missing ML-005 subset for all six targets; GM-004 overlap is already covered and must be preserved; no conflict-blocked candidates found; later source private-online-remove extensions for PL/ST/KE/media/stale-key rows are out of scope. Next action: patch only the missing ML-005 tests, criteria, runner, and harness fields.
- 2026-05-17 19:50:23 CEST - Executor import completed. Files inspected or touched: `remove_group_member_use_case_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_real_harness.dart`, `group_multi_party_device_criteria_test.dart`, this plan. Command currently running: none. Decision/blocker: imported the two ML-005 direct selectors, one ML-005 fake-network selector, `private_online_remove` scenario registration/routing, `ml005OnlineRemovalProof` harness emission, ML-005-only criteria validation, and accept/reject criteria tests; already-covered GM-004 code was preserved; no conflict-blocked candidates; production untouched. Next action: run format and focused ML-005/GM-004 selectors.
- 2026-05-17 19:50:53 CEST - Executor focused tests starting. Files inspected or touched: six import targets and this plan. Command currently running: focused `flutter test --no-pub` ML-005 selectors, then affected GM-004 selectors. Decision/blocker: `dart format` formatted only the criteria test file and completed successfully. Next action: run the plan's focused ML-005 selectors and GM-004 preservation selectors.
- 2026-05-17 19:52:09 CEST - Executor focused tests completed. Files inspected or touched: six import targets and this plan. Command currently running: none. Decision/blocker: focused ML-005 selectors passed (`remove_group_member_use_case_test.dart --plain-name ML-005`, `group_membership_smoke_test.dart --plain-name ML-005`, `group_multi_party_device_criteria_test.dart --plain-name private_online_remove`); affected GM-004 preservation passed (`member_removal_integration_test.dart`, `group_membership_smoke_test.dart --plain-name GM-004 removes C while online, rotates key, A/B continue, and C loses access`, `group_multi_party_device_criteria_test.dart --plain-name GM-004`). Next action: run device/plist availability checks before required live proof.
- 2026-05-17 19:52:27 CEST - Executor device availability checks starting. Files inspected or touched: this plan. Command currently running: `flutter devices --machine`, `xcrun simctl list devices available`, `test -f ios/Runner/GoogleService-Info.plist`. Decision/blocker: host proof is green; live proof still requires three Flutter-visible iOS 26.2 CoreSimulator devices plus plist. Next action: classify availability and either run live proof or record `blocked_external_fixture`.
- 2026-05-17 19:53:12 CEST - Executor device availability checks completed; live proof starting. Files inspected or touched: this plan. Command currently running: `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_online_remove -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Decision/blocker: plist exists; historical iOS 26.2 IDs are unavailable, but three Flutter-visible booted iOS 26.2 simulators are available and mapped as Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Next action: run required relay-backed `private_online_remove` proof and record run id or external blocker.
- 2026-05-17 19:58:01 CEST - Executor live proof completed; preservation gates starting. Files inspected or touched: this plan. Command currently running: format/analyze/list-scenarios/groups/completeness/diff checks. Decision/blocker: required relay-backed live proof passed with run id `1779040418067`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_online_remove_c41kfK`, verdict `private_online_remove proof passed: private_online_remove verdicts valid for alice, bob, charlie`; production remains untouched. Next action: run remaining preservation gates and diff hygiene.
- 2026-05-17 20:01:54 CEST - Executor completed. Files inspected or touched: six allowed import targets and this plan only. Command currently running: none. Decision/blocker: imported missing ML-005 tests/harness/criteria support; GM-004 overlap remained already covered and preserved; no conflict-blocked candidates; skipped duplicate/later-row `private_online_remove` source extensions for PL-006, ST-006, KE-006, KE-007, media, stale-key, and unrelated rows. Focused ML-005 selectors passed, GM-004 preservation selectors passed, `dart format --set-exit-if-changed` passed, targeted `flutter analyze --no-pub` passed, `--list-scenarios` includes `private_online_remove`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed, and `git diff --check` passed. `./scripts/run_test_gates.sh completeness-check` failed on unrelated tracked file `test/shared/fakes/fake_group_pubsub_network_test.dart` being unclassified (`732/733 test files classified`); the file was not touched by this Executor. Production remains untouched; integration breakdown ledger intentionally not updated per user instruction. Next action: QA Reviewer/controller can review the Executor changes and evidence.
- 2026-05-17 20:02:44 CEST - QA review starting. Files inspected or touched: this plan, Executor result, current `git diff --name-only`. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh"` QA Reviewer. Decision/blocker: QA must confirm row scope, no source docs/ledger import, no production changes from this session, no later-row proof imports, live proof run id `1779040418067`, and whether the unrelated completeness classification gap affects acceptance. Next action: wait for QA Reviewer result before final verdict.
- 2026-05-17 20:07:15 CEST - QA review completed; final verdict writing. Files inspected or touched: this plan, QA result, row-owned six target files. Command currently running: none. Decision/blocker: QA verdict `pass`; no blocking findings; `git diff --check` rerun passed; completeness-check failure is unrelated to ML-005 (`test/shared/fakes/fake_group_pubsub_network_test.dart`, `732/733`). Recommended final status is `accepted`. Next action: write final execution verdict in this plan; do not update integration breakdown ledger per user instruction.

## real scope

Import or reconcile exactly `INTEGRATE-ML-005` from the source worktree into main. The only row behavior owned here is: A, B, and online C are active; A removes C; A and B converge without C and can exchange post-removal messages; C loses post-removal send/read access and receives no A/B post-removal plaintext.

Production changes are expected to be none unless exact source-to-main diff/proof shows a current main behavior gap that cannot be closed by importing the accepted ML-005 tests/harness proof. Historical ML-005 source evidence explicitly says production stayed untouched and row-owned changes were tests, harness/criteria/runner support, and docs.

Do not recreate, rewrite, or rerun the original worktree implementation plan. Use the historical plan and closure evidence only as source-of-truth input for this integration contract.

## closure bar

ML-005 integration is good enough when main either already has, or receives, row-owned proof that:

- direct remove-member behavior excludes Charlie from local members and bridge config while preserving Alice/Bob;
- config-sync failure restores Charlie and does not commit the removal watermark;
- fake-network online removal converges A/B delivery, rejects Charlie post-removal send, and leaks no post-removal plaintext to Charlie;
- `private_online_remove` device criteria require `ml005OnlineRemovalProof` and reject missing proof, Charlie plaintext leak, missing A/B delivery, and successful Charlie post-removal publish;
- current COMPLETE_1/main `GM-004` remove-online proof remains intact.

## source of truth

Authoritative inputs, in precedence order:

1. Main code and tests after preserving existing dirty changes.
2. Integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
3. Source worktree row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-005`.
4. Source worktree session: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `ML-005`.
5. Historical source plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-005-plan.md`.
6. Main overlap artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`, especially `GM-004`.

If docs conflict, executable tests and current main behavior win over stale prose, but the ML-005 source row title and accepted historical evidence define the row-owned integration boundary.

## session classification

`implementation-ready` for integration execution only. This authorizes compare/import/verify of the accepted source-row delta; it does not authorize a new feature implementation plan.

## exact problem statement

The source worktree accepted ML-005 on 2026-05-11 with tests/harness/docs-only evidence and exact iOS 26.2 live proof. Current main has COMPLETE_1 `GM-004` remove-online proof and `gm004RemovalProof`, but planning-time anchor checks found no `ML-005`, `private_online_remove`, or `ml005OnlineRemovalProof` in the six ML-005 candidate files.

The integration risk is either leaving main without ML-005 row-owned proof, or importing too much from the current source worktree. The source worktree has later `private_online_remove` proof additions for other rows; those are not ML-005 scope and must not be imported here.

## changed-file inventory from source evidence

Historical ML-005 source evidence says the accepted worktree session changed these row-owned test/harness files:

- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/application/remove_group_member_use_case_test.dart`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/integration/group_membership_smoke_test.dart`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/integration_test/scripts/group_multi_party_device_criteria.dart`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/integration_test/scripts/run_group_multi_party_device_real.dart`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/integration_test/group_multi_party_device_real_harness.dart`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/integration/group_multi_party_device_criteria_test.dart`

Historical source docs updated during closure, but they are evidence only and must not be copied into main:

- source matrix row `ML-005`
- source session breakdown `ML-005`
- source `test-inventory.md`
- source historical ML-005 plan

Production changed-file inventory for ML-005: none.

## duplicate/overlap checks to perform

Before editing, run these checks in main:

```bash
git status --short
rg -n "ML-005|private_online_remove|ml005OnlineRemovalProof" test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart
rg -n "GM-004|gm004|gm004RemovalProof" test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart
rg -n "GM-004|Remove C while C is online|private_online_remove|member_removal_integration_test|group_membership_smoke_test|group_multi_party_device_criteria" Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md
```

Planning-time result: current main had no ML-005/private-online-remove anchors in candidate files; current main did have GM-004 remove-online anchors in group membership smoke, criteria, runner, and device harness.

Source ML-005 anchors to compare, not wholesale-copy:

- `remove_group_member_use_case_test.dart`: `ML-005 online remove excludes target from repo and bridge config while preserving remaining members`
- `remove_group_member_use_case_test.dart`: `ML-005 config sync failure restores removed online member`
- `group_membership_smoke_test.dart`: `ML-005 online removed member converges removed while remaining members keep delivery`
- `group_multi_party_device_criteria_test.dart`: `accepts private_online_remove ML-005 proof verdicts`
- `group_multi_party_device_criteria_test.dart`: the four ML-005 rejection selectors for missing proof, Charlie plaintext leak, missing A/B delivery, and successful Charlie send
- criteria/harness/runner support for `private_online_remove` plus `ml005OnlineRemovalProof`

Known COMPLETE_1/main overlaps to preserve:

- `GM-004 removes C while online, rotates key, A/B continue, and C loses access`
- `gm004RemovalProof` validation and GM-004 criteria rejection tests
- `--scenario gm004` runner and device harness support
- `test/features/groups/application/member_removal_integration_test.dart`

## likely files to import

Likely import/reconcile targets in main:

- `test/features/groups/application/remove_group_member_use_case_test.dart`: import the two ML-005 direct selectors if still absent.
- `test/features/groups/integration/group_membership_smoke_test.dart`: import the ML-005 fake-network selector if still absent, while preserving existing GM-004 and ML-004/GM-036 tests.
- `integration_test/scripts/group_multi_party_device_criteria.dart`: add only the ML-005 `private_online_remove` requirement, scenario mapping, and `ml005OnlineRemovalProof` validator needed for ML-005.
- `test/integration/group_multi_party_device_criteria_test.dart`: add only the ML-005 `private_online_remove` accept/reject tests.
- `integration_test/scripts/run_group_multi_party_device_real.dart`: add `private_online_remove` scenario listing/routing only.
- `integration_test/group_multi_party_device_real_harness.dart`: add `private_online_remove` as a three-role scenario that reuses the GM-004 flow but emits ML-005-specific proof fields.

Do not import later source-worktree `private_online_remove` additions for `PL-006`, `ST-006`, `KE-006`, `KE-007`, media, stale-key, or other rows. Those belong to their own integration sessions.

No production files are likely import targets.

## files and repos to inspect next

Inspect only these main files unless a direct conflict forces narrower supporting context:

- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- this integration contract

Supporting production files may be read for conflict understanding only, not edited by default:

- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`

## existing tests covering this area

Main currently has overlapping COMPLETE_1 coverage:

- `GM-004` proves A/B/C remove-online behavior with rotated-key exclusion, A/B post-removal delivery, Charlie send rejection, and no Charlie post-removal plaintext under `gm004RemovalProof`.
- `test/features/groups/application/member_removal_integration_test.dart` covers member removal/key rotation behavior for GM-004.
- `group_membership_smoke_test.dart` has a focused GM-004 online-removal smoke selector.
- Criteria, runner, and harness support already know `gm004`.

Main did not have ML-005 row-owned selectors or `private_online_remove` support at planning time.

## regression/tests to add first

Do not design new regressions from scratch. Reuse the accepted historical ML-005 test blocks and proof fields if duplicate checks show they are missing.

If current source files contain extra `private_online_remove` checks for later rows, skip them. The ML-005 import requires only:

- row id `ML-005` proof field checks;
- removed peer is Charlie;
- A/B member lists exclude Charlie and include each other;
- A/B receive each other's post-removal messages;
- Charlie has no group/key state, no post-removal plaintext, and rejected post-removal send;
- rotated epoch agreement between A/B if the proof records epoch.

## step-by-step implementation plan

1. Reconfirm `git status --short`; preserve unrelated dirty files and do not revert anything.
2. Run the duplicate/overlap checks above.
3. Open the historical ML-005 plan evidence and the six source/main candidate files.
4. For each candidate delta, classify it as `already covered by main`, `import missing ML-005 subset`, or `blocked by conflict`.
5. Import only missing meaningful ML-005 test/harness/criteria/runner deltas into matching main files.
6. If a source test conflicts with changed main helper APIs, adapt only fixture glue while preserving the original ML-005 assertion.
7. Edit production only if an exact ML-005 selector fails because current main product behavior is wrong and the fix is limited to the row-owned seam.
8. Run focused ML-005 tests, affected GM-004 preservation tests, host gates, and live proof.
9. Update this plan with execution evidence and update the integration breakdown ledger for `INTEGRATE-ML-005` only.

## Device/Relay Proof Profile

Classification: `live-rerun-required`.

Historical source proof is preserved as source-of-truth input, not as a substitute for main integration acceptance if ML-005 harness/criteria/runner deltas are imported. The source proof was exact-relay iOS 26.2 run `1778528310303`, shared path `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_online_remove_3x5VAP`, with Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`, and verdict `private_online_remove proof passed: private_online_remove verdicts valid for alice, bob, charlie`.

For this integration session, rerun live proof after main imports unless duplicate checks prove `private_online_remove` and `ml005OnlineRemovalProof` are already present and no code/test/harness files changed. Even then, record the reason if preserving historical proof only.

Required availability checks before live proof:

```bash
flutter devices --machine
xcrun simctl list devices available
test -f ios/Runner/GoogleService-Info.plist
```

Default IDs policy:

- Prefer the historical ML-005 iOS 26.2 simulator role IDs if available: Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.
- If those exact IDs are unavailable, use only three Flutter-visible iOS 26.2 CoreSimulator devices that also appear under `xcrun simctl list devices available`, and record the role mapping.
- Do not substitute iOS 26.1, iOS 26.4, Android, physical iOS, macOS, Chrome, or any non-iOS-26.2 target.

Live command shape:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_online_remove -d <alice_ios_26_2>,<bob_ios_26_2>,<charlie_ios_26_2>
```

If availability or relay health blocks the run after host/criteria proof is green, mark the session `blocked_external_fixture` with the exact missing runtime, UDIDs, plist, relay, or discovery failure. Do not accept ML-005 by substituting GM-004 live proof alone.

## risks and edge cases

- The source worktree is fully advanced beyond ML-005. Current source files include later `private_online_remove` proof fields; importing them would leak future row scope.
- Current main has many dirty files from prior integration work. Work with them and do not overwrite them with source-worktree versions.
- GM-004 is behaviorally similar but uses a generic scenario/proof field. It is overlap to preserve, not a replacement for ML-005 row-owned proof.
- Device proof can fail because of fixture availability or relay/discovery health. Classify that separately from product behavior failure.

## exact tests and gates to run

Focused ML-005 selectors after import/reconcile:

```bash
flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name 'ML-005'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-005'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_online_remove'
```

Affected COMPLETE_1/main overlap tests:

```bash
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-004 removes C while online, rotates key, A/B continue, and C loses access'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-004'
```

Preservation/gates:

```bash
dart format --set-exit-if-changed test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart
flutter analyze --no-pub test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Device/relay proof:

```bash
flutter devices --machine
xcrun simctl list devices available
test -f ios/Runner/GoogleService-Info.plist
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_online_remove -d <alice_ios_26_2>,<bob_ios_26_2>,<charlie_ios_26_2>
```

## known-failure interpretation

Any imported ML-005 selector failure is a blocker unless proven to be fixture drift from main evolution. Any GM-004 regression caused by the import is a blocker. If `groups` or `completeness-check` fails in unrelated pre-existing areas, record the exact failure and rerun all focused ML-005 plus affected GM-004 selectors before accepting.

Live proof failure with valid iOS 26.2 devices and healthy relay is an ML-005 blocker until classified. Missing devices, missing plist, simulator boot failure, or relay/discovery outage is `blocked_external_fixture`.

## done criteria

- Main has ML-005 row-owned direct, fake-network, criteria, runner, and harness proof, or concrete evidence that it was already present.
- Production files remain untouched unless exact failing ML-005 proof required a narrow fix and that exception is documented.
- Focused ML-005 selectors pass.
- Affected GM-004 COMPLETE_1/main preservation tests pass.
- `groups`, `completeness-check`, and `git diff --check` pass, or non-row failures are precisely classified with focused proof green.
- Required iOS 26.2 `private_online_remove` live proof passes, or the session is truthfully marked `blocked_external_fixture`.
- Integration breakdown ledger is updated for `INTEGRATE-ML-005` only.

## scope guard

Do not edit source worktree files. Do not copy source docs into main. Do not import adjacent source rows, later `private_online_remove` extensions, or broad full-rules scenario lists. Do not stage, commit, revert, or reset unrelated dirty changes.

Allowed integration write set during execution is limited to the six likely import files, this plan, and the integration breakdown ledger. Production changes are outside the expected scope and require exact failing ML-005 proof.

## accepted differences / intentionally out of scope

- `GM-004` remains generic COMPLETE_1 support and must stay green, but ML-005 closure requires `private_online_remove` / `ml005OnlineRemovalProof`.
- Later rows remain separate: `ML-006`, `ML-007`, `ML-008`, `ML-009`, `ML-011`, offline removal, re-add, rapid ordering, duplicate/stale removal, churn, media/privacy/key-boundary additions, and stress rows.
- Historical ML-005 source docs are evidence only; main integration docs get their own ledger entry.

## dependency impact

Accepted ML-005 integration unblocks the next integration session, `INTEGRATE-ML-006`, only after the ledger records `accepted` or a truthful terminal blocker. If ML-005 is `blocked_conflict` or `blocked_external_fixture`, do not continue to ML-006 without controller approval because offline removal depends on a truthful online removal baseline.

## final ledger update policy

After execution, update `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md` for `INTEGRATE-ML-005` only:

- `accepted` if ML-005 import/reconcile completed, focused/overlap/gate proof passed, and live proof passed;
- `skipped_already_present` only if duplicate checks prove main already had exact ML-005 selectors, `private_online_remove`, `ml005OnlineRemovalProof`, and passing proof without edits;
- `blocked_conflict` if GM-004/main behavior conflicts with ML-005 and cannot be resolved in the row scope;
- `blocked_external_fixture` if only device/relay availability prevents the required live proof after host proof is green.

The ledger entry must name changed files, tests/gates, live proof run id or blocker, production untouched status, skipped adjacent source rows, and next session `INTEGRATE-ML-006` when appropriate.

## Final Execution Verdict

status: `accepted`

Files touched by this session:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-ML-005-plan.md`
- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Candidate delta classification:

- Imported: two ML-005 direct removal tests, one ML-005 fake-network smoke test, `private_online_remove` scenario requirement/routing/listing, `ml005OnlineRemovalProof` harness emission, ML-005 criteria validation, and criteria accept/reject tests.
- Already covered: GM-004 overlap/proof paths in current main were already present and preserved.
- Conflict-blocked: none.
- Skipped duplicate/later source-worktree work: no pre-existing exact ML-005 proof was present, so this was not `skipped_already_present`; later `private_online_remove` source extensions for PL-006, ST-006, KE-006, KE-007, media, stale-key, and unrelated rows were intentionally not imported.

Tests and gates run:

- `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name 'ML-005'` passed.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-005'` passed.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_online_remove'` passed.
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart` passed.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-004 removes C while online, rotates key, A/B continue, and C loses access'` passed.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-004'` passed.
- `dart format --set-exit-if-changed` on the six target files passed.
- `flutter analyze --no-pub` on the six target files passed.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios` passed and includes `private_online_remove`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed.
- `git diff --check` passed; QA reran it and it passed again.
- `./scripts/run_test_gates.sh completeness-check` failed only on unrelated tracked file `test/shared/fakes/fake_group_pubsub_network_test.dart` being unclassified (`732/733 test files classified`); the file is not ML-005-owned and was not touched by this session.

Live proof:

- Required relay-backed `private_online_remove` proof passed.
- Run id: `1779040418067`.
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_online_remove_c41kfK`.
- Verdict: `private_online_remove proof passed: private_online_remove verdicts valid for alice, bob, charlie`.
- Device/plist availability: plist existed; historical device IDs were unavailable, so the run used three Flutter-visible booted iOS 26.2 simulators mapped as Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.

QA:

- QA Reviewer verdict: `pass`.
- Blocking findings: none.
- Non-blocking unrelated gate failure: completeness classification gap for `test/shared/fakes/fake_group_pubsub_network_test.dart`.

Production changes from this ML-005 session: none. The broader worktree contains pre-existing unrelated dirty production files; they were preserved and not reverted.

Integration breakdown ledger: not updated in this execution turn because the user explicitly instructed not to update it; closure/controller verification will handle that later.
