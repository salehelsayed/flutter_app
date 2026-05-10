# GM-006 Execution Plan - Remove C And Immediately Re-add C With New Epoch

Status: closed

## Planning Progress

- 2026-05-10 15:39 CEST - Local planner completed. Files inspected since last update: source matrix GM-006 row, breakdown GM-006 session and detailed rows, accepted GM-004/GM-005 closure notes, current GM harness support, `group_membership_smoke_test.dart` re-add coverage, `add_group_member_use_case.dart`, `remove_group_member_use_case.dart`, `GroupTestUser`, and `FakeGroupPubSubNetwork`. Decision/blocker: GM-006 is implementation-ready because adjacent re-add tests exist but exact row-owned host, criteria, runner, and relay/device proof are missing. Next action: implement GM-006 proof without changing source matrix/breakdown closure status.

## Execution Progress

- 2026-05-10 15:57 CEST - Implemented GM-006 row-owned host regression, criteria support, criteria tests, runner mapping, and A/B/C real-device harness flow. Files changed: `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`.
- 2026-05-10 15:58 CEST - Focused GM-006 host test initially failed because the fixture used a future removal timestamp, which correctly made the re-add stale relative to the removal guard. Corrected the GM-006 fixture to chronological timing; no production behavior change was required.
- 2026-05-10 16:00 CEST - Direct host proof, criteria guard, targeted analyzer, exact relay/device proof, groups gate, completeness-check, and diff-check all passed. Source matrix row GM-006 and this breakdown were then updated in closure, not during implementation.

## Closure Evidence

- Host proof: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic'`.
- Criteria proof: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed with 35 tests, including negative removed-window plaintext, stale-epoch, missing-delivery, and incomplete-proof cases.
- Analyzer proof: `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart`.
- Fresh device discovery was run with `flutter devices --machine` and `xcrun simctl list devices available`; Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` were available.
- Exact relay/device proof passed with the accepted `MKNOON_RELAY_ADDRESSES` env and `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm006 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm006_Gjv8kM/gmp_1778421144199_gm006_orchestrator_verdict.json` records `scenario: gm006`, `ok: true`, and `gm006 verdicts valid for alice, bob, charlie`.
- Role verdict facts: Bob received the removed-window Alice message exactly once; Charlie received zero removed-window plaintext; Alice, Bob, and Charlie converged on member list A/B/C and final epoch `2`; Charlie's post-readd publish was accepted; Alice/Bob received Charlie's post-readd message exactly once; Bob/Charlie received Alice's post-readd message exactly once.
- Supporting gates passed: `./scripts/run_test_gates.sh groups` (`+110`), `./scripts/run_test_gates.sh completeness-check` (`731/731 test files classified`), and `git diff --check`.

## Checkpoint Policy

- 2026-05-10 16:00 CEST - Local checkpoint commit skipped. A clean scoped commit is unsafe because the source matrix, breakdown, and GM-006 plan are untracked aggregate rollout artifacts containing earlier session work, while the worktree also contains unrelated dirty files and overlapping prior-session edits.

## real scope

Own exactly source row `GM-006`: Charlie is removed, the key rotates, Charlie is immediately re-added under the current product rejoin rule, and A/B/C all exchange post-readd messages under the current config/device binding.

In scope:
- Add a row-owned GM-006 host/app proof for immediate remove/re-add, removed-window non-access, current rejoin epoch install, Charlie send acceptance after re-add, and A/B delivery continuity.
- Extend only the accepted GM multi-party harness files already used by GM-001 through GM-005:
  - `integration_test/scripts/run_group_multi_party_device_real.dart`
  - `integration_test/group_multi_party_device_real_harness.dart`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
- Fix the smallest production or harness seam only if GM-006 proof shows Charlie can decrypt removed-window content, uses a stale epoch after re-add, cannot send after valid re-add, or A/B reject/miss Charlie's current-epoch message.

Out of scope:
- Long removed-window history boundaries, app restart during re-add, duplicate remove/re-add loops, out-of-order stale add/remove events, notification UX, media, role-change policy, and `--scenario all` expansion.
- Changing GM-001 through GM-005 accepted criteria or closure facts.
- Committing changes.

## closure bar

GM-006 is good enough only after implementation produces row-specific evidence that all of the following are true:
- Alice starts an A/B/C group with a valid epoch-1 config/key.
- Alice removes Charlie, rotates to a post-removal epoch for Alice/Bob only, and sends at least one removed-window message.
- Charlie does not persist/decrypt the removed-window message and cannot use the removed-window or stale pre-removal epoch as current access after re-add.
- Alice immediately re-adds Charlie and installs/distributes the current rejoin epoch according to product policy.
- Alice, Bob, and Charlie converge on the same final member list and key epoch after re-add.
- Charlie sends a post-readd message accepted by Alice and Bob under the current config/device binding.
- Alice sends a post-readd message accepted by Bob and Charlie under the current config/device binding.
- Exact relay/device proof passes with `--scenario gm006` and writes an orchestrator verdict JSON where `scenario: gm006`, `ok: true`, and per-role verdicts validate Alice, Bob, and Charlie.
- Direct tests, named gates, and whitespace checks pass as listed in this plan.

Do not weaken the expected result to "Charlie can send eventually"; the row requires the immediate remove/re-add boundary and current-epoch binding to be proven.

## source of truth

Authoritative inputs:
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GM-006`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row `GM-006`.
- Accepted GM-004 and GM-005 closure evidence as precedent only.
- Current code and tests in the Flutter app and accepted GM harness files.
- `Test-Flight-Improv/test-gate-definitions.md` for named gate behavior.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` only if test classification must be updated.

Conflict rule:
- Current code/tests beat stale prose.
- The GM-006 matrix row defines the row contract unless exact repo proof shows the row is already covered; current evidence does not.
- The accepted relay env in this plan is mandatory for device proof.

## session classification

`implementation-ready`

Rationale: the breakdown classifies GM-006 as `needs_repo_evidence` / `evidence-gated`, but exact planning found missing row-owned host proof, criteria support, runner support, and real-device harness support. Those missing tests, harness scenarios, criteria, and test hooks are repo-owned implementation work. Product changes are conditional and should happen only if the new proof exposes a real GM-006 behavior gap.

## exact problem statement

GM-006 remains `Open`. Existing re-add coverage proves a removed member can later rejoin, but the row's high-risk case is an immediate remove/re-add with a new epoch and current config/device binding. The repo needs exact proof that Charlie cannot carry removed-window access forward, and that Alice/Bob accept Charlie only after the current rejoin epoch/config is installed.

What must improve or be proven:
- Charlie's old or removed-window epoch cannot decrypt or authorize removed-window content after the remove/re-add boundary.
- Charlie gets the current rejoin epoch and final member list before accepted post-readd publish.
- Alice and Bob accept Charlie's post-readd message under the latest config/device binding.
- Bob and Charlie accept Alice's post-readd message under the latest config/device binding.

What must stay unchanged:
- Accepted GM-001 through GM-005 proof semantics.
- Existing create/add/offline-add/online-remove/offline-remove behavior.
- Existing signed system-message validation, key-rotation verification, and fail-closed send validation.

## files and repos to inspect next

Production/app seams:
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/core/bridge/bridge_group_helpers.dart`

Harness/tests:
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Go fallback only if the failing proof points below Flutter/app replay or pubsub validation:
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`

## existing tests covering this area

Already useful but not enough to close GM-006:
- `test/features/groups/integration/group_membership_smoke_test.dart::removed member can be re-added with current state and resumes send/receive` covers later re-add, rejoin key epoch 2, Charlie send after rejoin, and removed-window non-delivery.
- GM-004 proves online removal and removed-member non-access.
- GM-005 proves stale offline removal, inbox catch-up, removed-member non-access, and remaining-member delivery continuity.
- `integration_test/group_real_crypto_onboarding_test.dart` covers real encrypted invite and re-add invite material at a lower scope.

Missing:
- A GM-006-named host/app regression combining immediate remove/re-add, removed-window cutoff, current rejoin epoch, Charlie post-readd send, and Alice/Bob/Charlie final convergence.
- GM-006 criteria that reject incomplete or false role verdicts.
- `--scenario gm006` runner/harness support.
- Exact relay/device proof for GM-006.

## regression/tests to add first

Add tests before product fixes:
- Add a focused host regression in `test/features/groups/integration/group_membership_smoke_test.dart`, named:
  - `GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic`
- Extend `test/integration/group_multi_party_device_criteria_test.dart` for GM-006 before relying on the device run:
  - accepts complete GM-006 Alice/Bob/Charlie verdicts;
  - rejects Charlie seeing the removed-window message;
  - rejects Charlie retaining or using stale epoch after re-add;
  - rejects Charlie post-readd publish not being accepted by Alice/Bob;
  - rejects Alice post-readd message missing from Bob or Charlie;
  - rejects incomplete final member/key convergence proof.

Product code changes should begin only after one of these tests fails for product behavior rather than missing proof support.

## step-by-step implementation plan

1. Reconfirm current dirty worktree and do not revert unrelated changes.
   - Use `git status --short`.
   - Do not stage/commit.
   - Do not edit source matrix or breakdown closure status during implementation.

2. Add the GM-006 host regression first.
   - Create Alice/Bob/Charlie with epoch 1.
   - Start all three users.
   - Alice removes Charlie and rotates Alice/Bob to epoch 2.
   - Alice sends one removed-window message; Bob receives it and Charlie does not.
   - Alice immediately re-adds Charlie, installs the current rejoin epoch for Charlie, broadcasts member-added, and confirms all three converge on A/B/C membership and epoch 2.
   - Charlie sends a post-readd message and Alice/Bob receive it exactly once.
   - Alice sends a post-readd message and Bob/Charlie receive it exactly once.
   - Assert Charlie has no removed-window plaintext and no stale epoch use after re-add.
   - If this host test passes without product changes, continue to criteria/harness. If it fails for product behavior, fix the smallest seam shown by the failure.

3. Add GM-006 criteria support in `integration_test/scripts/group_multi_party_device_criteria.dart`.
   - Add `_gm006Requirement` with roles `alice`, `bob`, `charlie`.
   - Update supported-scenario error text to include `gm006`.
   - Expected messages:
     - removed-window Alice message goes to Bob only.
     - Charlie post-readd message goes to Alice and Bob.
     - Alice post-readd message goes to Bob and Charlie.
   - Add `_validateGm006ReaddProof` requiring:
     - Alice proof: removed Charlie, readded Charlie, final member list includes Charlie, final epoch >= 2, received Charlie post-readd message, and removed-window message was sent before readd.
     - Bob proof: member list includes Charlie, final epoch matches Alice, received removed-window Alice message, received Charlie post-readd message, and received Alice post-readd message.
     - Charlie proof: removed-window plaintext count is 0, stale epoch after readd is false, final member list includes Alice/Bob/Charlie, final epoch matches Alice/Bob, post-readd send accepted, and received Alice post-readd message.

4. Extend `test/integration/group_multi_party_device_criteria_test.dart` for GM-006 positive and negative cases.

5. Extend `integration_test/scripts/run_group_multi_party_device_real.dart`.
   - Accept `--scenario gm006`.
   - Map `gm006` to only `gm006`.
   - Keep `--scenario all` unchanged unless execution chooses optional operator convenience; GM-006 closure must use direct `--scenario gm006`.

6. Extend `integration_test/group_multi_party_device_real_harness.dart`.
   - Add `gm006` roles `alice`, `bob`, `charlie`.
   - Alice flow: create A/B/C, remove Charlie, rotate to current epoch, send removed-window message, re-add Charlie, install/distribute current rejoin epoch, send post-readd message, and record proof.
   - Bob flow: verify removed-window Alice message, final A/B/C membership, current epoch, Charlie post-readd message, and Alice post-readd message.
   - Charlie flow: verify removed-window plaintext absent, current epoch/config after re-add, accepted post-readd send, and Alice post-readd receipt.

7. Run direct tests and fix only GM-006-owned failures.

8. Run fresh device discovery before exact device proof:
   - `flutter devices --machine`
   - `xcrun simctl list devices available`
   - Use three distinct Flutter app targets. The recent available IDs were Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; refresh discovery must confirm availability before reuse.

9. Run exact GM-006 relay/device proof with the accepted relay env:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm006 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

10. Run named gates and hygiene, then stop for closure.

## risks and edge cases

- If the "immediate" re-add is modeled too slowly, the test can collapse into generic re-add coverage. Keep removal, rotation, re-add, and proof messages in the same scenario timeline.
- Charlie must not be allowed to see removed-window content through stale local state, pubsub, or inbox replay.
- A/B must accept Charlie's post-readd message only after their config includes Charlie.
- Charlie must use the current rejoin epoch after re-add, not the pre-removal epoch.
- Existing dirty files may affect broad gates; isolate failures before attributing them to GM-006.

## exact tests and gates to run

Direct tests after adding GM-006 support:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
```

Fresh device discovery required before exact proof:

```bash
flutter devices --machine
xcrun simctl list devices available
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

If Go files are touched:

```bash
(cd go-mknoon && go test ./node -run 'Group|PubSub|Inbox|Key|Validator')
```

If docs remain untracked and `git diff --check` cannot see them, run a no-index whitespace check on newly created/edited untracked markdown files before final handoff.

## known-failure interpretation

Known unrelated context from planning:
- The worktree already contains many modified and untracked files across docs, Go node tests, group app code, and accepted GM harness files. Treat those as pre-existing unless GM-006 implementation edits them.
- GM-004 and GM-005 are covered; reopening them is out of scope unless a real regression appears in their accepted direct proof.
- `--scenario all` currently expands to GM-001/GM-002 only; that is an accepted operator-convenience difference and not a GM-006 blocker.

Do not hide a GM-006 regression behind "known failure" if Charlie accesses removed-window plaintext, uses stale epoch after re-add, cannot send after valid re-add, or Alice/Bob miss Charlie's post-readd message.

## done criteria

- GM-006 plan remains scoped to row GM-006 and says `Status: execution-ready` until closure.
- GM-006 host regression exists and passes.
- GM-006 criteria tests exist and pass, including negative stale/removed-window cases.
- `--scenario gm006` runner/harness support exists and reuses the accepted GM multi-party device harness surface.
- Fresh device discovery was run immediately before the exact proof.
- Exact relay/device proof passes with the accepted relay env and writes an `ok: true` GM-006 orchestrator verdict plus Alice/Bob/Charlie role verdicts.
- Direct tests and named gates listed above pass, or any failure is isolated and documented as unrelated/pre-existing with evidence.
- Source matrix and breakdown are not marked `Covered` during implementation.
- No unrelated dirty files are reverted or overwritten.

## scope guard

Do not:
- Convert GM-006 into a general re-add history rewrite.
- Change product expectations so Charlie can see removed-window content.
- Treat the existing generic re-add host test as complete closure evidence without row-owned GM-006 proof.
- Add a second orchestration system; extend the accepted GM harness files only.
- Expand `--scenario all` as a required closure condition.
- Modify closure docs to mark GM-006 covered during implementation.
- Revert or clean unrelated dirty/untracked files.

Overengineering signs:
- New generic membership simulator framework.
- New persistence abstraction just for the test.
- Broad Go pubsub rewrites before a GM-006 failing proof points there.
- Adding notifications/media/role assertions to GM-006.

## accepted differences / intentionally out of scope

- GM-006 is distinct from GM-004 and GM-005 because Charlie is removed and then re-added with current epoch access. Prior remove-only proof is precedent but not closure evidence.
- `--scenario all` not including GM-006 is acceptable for this session; direct `--scenario gm006` is the required row proof.
- Host fake-network proof and exact device proof are both required. Host proof is not a substitute for the relay/device artifact.
- If implementation evidence passes with harness/test changes only, product code should remain unchanged.

## dependency impact

Later removal/re-add and history-boundary rows depend on GM-006's proof shape:
- GM-007 and GM-008 should reuse the remove/re-add rejoin proof pattern for history and restart windows.
- GM-019 depends on recipient inclusion only after re-add.
- GK-021 depends on re-add epoch separation.

If GM-006 exposes a product gap, pause later GM removal/re-add rows until the narrow GM-006 fix and proof are accepted. If GM-006 closes with tests/harness only, later rows can proceed using the GM-006 scenario as the accepted immediate re-add precedent.

## Reviewer Findings

Verdict: sufficient as-is.

- Missing files, tests, regressions, or gates: none structural. The plan names the GM harness files, row-owned host/criteria tests, direct tests, named gates, fresh device discovery, and exact relay proof.
- Stale or incorrect assumptions: none found. The plan treats existing re-add coverage as adjacent precedent only and keeps GM-006 separate because the immediate remove/re-add plus current epoch boundary needs exact proof.
- Overengineering: none required. The plan extends the accepted harness rather than adding a separate orchestration surface.
- Decomposition: sufficient. Product changes are conditional on failing GM-006 proof and are limited to the owning seam shown by evidence.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: optional `--scenario all` expansion remains deferred.
- Accepted differences: GM-004/GM-005 prove removal boundaries only; GM-006 requires re-add/current-epoch proof. Host proof does not replace exact relay/device proof.
- Stop rule: no structural blocker was found, so no fix loop is needed. This plan is execution-ready for GM-006 only.

## QA checklist

- Verify plan and implementation touch only GM-006-owned files or explicitly justified shared harness/docs.
- Confirm `scenarioRequirement`, device selection, runner usage text, and verdict evaluation all include `gm006`.
- Confirm criteria tests reject false positives for removed-window plaintext access, stale epoch after re-add, missing Charlie post-readd delivery, and incomplete convergence.
- Confirm exact device proof used the required relay env and fresh device discovery.
- Confirm source matrix and breakdown still leave GM-006 open until a separate closure step.
- Confirm no unrelated dirty files were reverted, formatted, staged, or committed.
