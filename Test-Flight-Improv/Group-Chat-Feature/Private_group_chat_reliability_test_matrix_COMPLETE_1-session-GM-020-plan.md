# GM-020 Immediate Removed-Member Durable Recipient Exclusion Plan

Status: execution-ready

Planning mode: simulated Evidence Collector, Planner, Reviewer, and Arbiter roles in one controller pass. No product or test code was edited during planning.

## Planning Progress

- 2026-05-11T07:23:40+0200 - Arbiter completed. Files inspected since last update: reviewer findings, mandatory plan sections, exact tests/gates, scope guard, and accepted differences. Decision/blocker: no structural blockers remain; stop rule passes; plan is execution-ready. Next action: execute GM-020 only in a separate implementation pass using the evidence-first contract.
- 2026-05-11T07:23:22+0200 - Arbiter started. Files inspected since last update: reviewer-adjusted plan content and scoped file existence/status check. Decision/blocker: no evidence of a structural blocker; only the GM-020 plan file is newly created by this task. Next action: classify findings and mark the plan execution-ready if the stop rule passes.
- 2026-05-11T07:21:18+0200 - Reviewer completed. Files inspected since last update: draft plan content. Decision/blocker: plan is sufficient with adjustments; no structural blocker remains after tightening simulator sequence, criteria proof fields, usage-list updates, and relay setup handling. Next action: run Arbiter pass and classify findings.
- 2026-05-11T07:20:51+0200 - Reviewer started. Files inspected since last update: draft plan content. Decision/blocker: reviewing for exact simulator profile, missing direct proof, conditional test clarity, and overreach into later GM rows. Next action: record sufficiency findings and required adjustments.
- 2026-05-11T07:18:51+0200 - Planner completed. Files inspected since last update: no new files beyond the Evidence Collector set. Decision/blocker: draft plan written as evidence-gated with RED/evidence-first host, criteria, and simulator proof; no structural blocker in drafting. Next action: run Reviewer pass for missing tests, stale assumptions, overreach, and stop-rule sufficiency.

## Evidence Summary

- Source row GM-020 is `Open` and P0: after C is removed, A sends immediately, and the actual `GroupInboxStore` request must omit C from `recipientPeerIds` for every post-removal message.
- Session breakdown row 37 classifies GM-020 as `needs_repo_evidence`, `evidence-gated`, and "evidence only unless exact row plan finds missing code."
- GM-019 is closed, but it proves removed-window recipient exclusion after re-add and post-readd inclusion. It does not close GM-020 because GM-020 is specifically the immediate post-removal durable-recipient request.
- `send_group_message_use_case.dart` currently selects durable recipients from `groupRepo.getMembers(groupId)`, excludes the sender, de-duplicates via `toSet()`, applies the GM-019 timestamp cutoff when an explicit in-group-lifetime send timestamp is supplied, writes the same recipients into `buildGroupOfflineReplayEnvelope`, persisted `inboxRetryPayload`, and `group:inboxStore`.
- `remove_group_member_use_case.dart` removes the member from the local repository before building the remaining-member config and calling `group:updateConfig`; on config-update failure it restores the member and deletes the removal cutoff timeline message.
- `group_message_listener.dart` handles `member_removed` by local cleanup for self-removal, removing other members from the repository, applying the authoritative config snapshot, syncing Go config, saving the timeline cutoff, and recording the membership watermark.
- `go-mknoon/node/group_inbox.go` forwards caller-provided `recipientPeerIds`; `go-mknoon/node/group_inbox_test.go` already proves the request marshals those recipients and keeps the encrypted replay envelope opaque.
- Existing GM-016/GM-018/GM-019 tests prove adjacent removed-member and durable-recipient behavior, but no current row-owned `GM-020` test or simulator scenario exists. The current runner and criteria support stop at `gm019`.

## real scope

GM-020 owns only immediate post-removal durable recipient exclusion for private group messages. The execution must prove that after Alice removes Charlie, every post-removal message Alice sends immediately uses actual durable `group:inboxStore` and persisted retry payload recipients that contain Bob only: no Charlie, no sender, no duplicates.

The expected execution shape is tests/harness/evidence first. Product code changes are conditional and allowed only if the GM-020 proof fails against current code. If the exact GM-020 proof passes because GM-019 or earlier fixes already made the behavior correct, stop as evidence-only and do not invent product changes.

## closure bar

GM-020 is closable only when row-owned proof shows the actual `GroupInboxStore` request payload, not a recomputed member list, omits Charlie for every post-removal send in the scenario. The proof must include an immediate first send after removal, at least one repeated post-removal send, persisted retry payload parity, Bob delivery continuity, and Charlie receiving zero post-removal plaintext.

The exact simulator verdict must be `scenario: gm020`, `ok: true`, on the three specified iOS simulators. A green GM-019 verdict, a generic membership test, or a proof that inspects only local repository membership is not enough.

## source of truth

Authoritative inputs, in order:

1. Current code and tests in the repository.
2. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` for named gate meaning; if they disagree, the script wins.
3. GM-020 source row in `Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
4. GM-020 row in `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
5. Prior GM-016 through GM-019 closure evidence only as adjacent context, not as automatic closure.

On disagreement, current code and direct row-owned tests win over stale prose. The source matrix and breakdown must not be edited during this planning task.

## session classification

`evidence-gated`.

Evidence only unless exact GM-020 proof finds a missing product behavior. If missing behavior is found, the session becomes a narrow implementation fix around membership removal propagation or durable recipient selection only.

## exact problem statement

There is no row-owned proof that a removed Charlie is excluded from the actual durable inbox recipient list immediately after removal. The user-visible risk is privacy and delivery correctness: a removed member could receive post-removal durable inbox messages if the sender uses stale membership while storing offline copies.

The desired behavior is: after Charlie is removed, Alice can send immediately, Bob remains an eligible recipient, Charlie is never included in `recipientPeerIds`, Charlie receives no post-removal plaintext, and existing GM-019 re-add recipient behavior remains unchanged.

## files and repos to inspect next

Production or bridge seams:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/pubsub.go`

Direct and proof tests:

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/group_real_crypto_onboarding_test.dart` only if real-crypto onboarding, bridge encryption/decryption semantics, or onboarding harness behavior is touched.
- `go-mknoon/node/group_inbox_test.go` only if Go inbox request behavior is touched or questioned.

## existing tests covering this area

- `send_group_message_use_case_test.dart` has GM-019 durable-recipient tests that inspect actual `group:inboxStore` payloads and persisted `inboxRetryPayload` before and after Charlie re-add.
- `member_removal_integration_test.dart` has GM-018 repeated post-removal durable recipient coverage and GM-019 removal/re-add coverage, but GM-018 removes a different member and does not own GM-020's immediate Charlie-removal row.
- `group_membership_smoke_test.dart` has GM-019 network-level durable-recipient proof around removal and re-add, but not immediate post-removal-only GM-020 proof.
- `group_multi_party_device_criteria.dart`, its tests, the real-device runner, and the harness support `gm019` only. They currently need a `gm020` scenario, valid/invalid criteria, and role proof fields.
- `go-mknoon/node/group_inbox_test.go` proves Go preserves supplied recipient IDs in a store request. It does not decide which members Flutter should supply.

Missing: exact GM-020 host tests, exact GM-020 criteria tests, exact simulator-only `gm020` scenario support, and row-owned proof that the first and every repeated post-removal durable request excludes Charlie.

## regression/tests to add first

Add RED/evidence-first proof before any product code change:

1. `send_group_message_use_case_test.dart`: add a `GM-020` test that seeds Alice, Bob, and Charlie, removes Charlie from the repository through the same removal seam or a narrowly controlled repository mutation, sends immediately, sends a second post-removal message, and asserts actual `group:inboxStore` `recipientPeerIds` plus persisted `inboxRetryPayload` are exactly Bob-only for each message.
2. `member_removal_integration_test.dart`: add a `GM-020` test that uses `removeGroupMember` with active Charlie, clears bridge logs after removal, sends immediately with no re-add, repeats once, and inspects actual inbox-store payloads. This catches stale local membership, sender inclusion, duplicates, and retry-payload drift.
3. `group_membership_smoke_test.dart`: add a `GM-020` host smoke where Alice, Bob, and Charlie are active; Alice removes Charlie; Alice sends immediately and repeatedly; Bob receives all messages; Charlie receives no post-removal plaintext; Alice's actual durable payload recipients are Bob-only.
4. `group_multi_party_device_criteria_test.dart`: add valid and invalid `GM-020` criteria fixtures. Invalid cases must reject missing proof, missing actual durable payload proof, Charlie in any recipient list, missing Bob, duplicate recipients, sender in recipients, wrong timestamp order, and Charlie plaintext leak.
5. Add `gm020` to `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart` so the simulator proof has its own row-owned verdict. Include scenario parsing, supported scenario lists, role maps, usage text, and criteria scenario validation. The proof must record actual durable payload recipients from the sender's `group:inboxStore` calls, not recomputed membership.

If these tests pass on current product code, keep execution evidence-only. If any fail, implement the smallest product fix needed and rerun the same tests.

## step-by-step implementation plan

1. Add GM-020-focused host regression support first:
   - Extend helper methods only where needed to retrieve actual inbox-store payloads by message ID.
   - Add the `send_group_message_use_case_test.dart` GM-020 proof for immediate and repeated post-removal sends.
   - Add the `member_removal_integration_test.dart` GM-020 proof through `removeGroupMember`.
   - Add the `group_membership_smoke_test.dart` GM-020 proof through the existing fake multi-user network.

2. Run the GM-020 host tests in isolation. If they pass without product changes, classify this part as evidence-only. If they fail, inspect only the failing seam:
   - If Charlie remains in Flutter recipients, fix the sender-side membership source or removal ordering.
   - If retry payload differs from the bridge request, fix `send_group_message_use_case.dart` recipient propagation.
   - If Go mutates or drops caller-provided recipients, fix `go-mknoon/node/group_inbox.go` and add/update the focused Go test.
   - If listener/config propagation is the failure, fix only `group_message_listener.dart`, `group_key_update_listener.dart`, or `group_config_payload.dart` as directly proven.

3. Add GM-020 criteria support:
   - Add `_gm020Requirement` for Alice, Bob, and Charlie.
   - Add `_validateGm020ImmediateRemovedRecipientExclusionProof`.
   - Require actual durable payload proof on every sent post-removal message.
   - Require Alice proof fields for `removedPeerId`, `removedAt`, `firstPostRemovalSentAt`, `offlinePostRemovalSentAt`, `postRemovalMessageCount >= 2`, exact `postRemovalMessageKeys`, and `everyPostRemovalExcludedCharlie`.
   - Require Bob proof of receipt for every Alice post-removal key.
   - Require Charlie proof of zero post-removal plaintext.
   - Add criteria tests for valid and invalid verdicts.

4. Add exact simulator-only `gm020` support:
   - Add `gm020` to scenario parsing, supported scenario lists, usage text, role maps, and criteria scenario validation.
   - In the harness, create Alice/Bob/Charlie group, wait for Bob and Charlie to join, remove Charlie while active, record the removal timestamp, and send the first Alice post-removal message immediately after Alice's removal call returns. Do not wait for a re-add path, source-matrix closure work, or broad scenario sweep before this first send.
   - Include at least two post-removal messages. The first must prove immediate post-removal recipient exclusion. The second must run after Charlie has been made offline/stopped or is otherwise demonstrably unavailable, proving the "may be offline" durable-recipient case while still keeping Bob eligible.
   - The sender proof must inspect Alice's actual durable requests. Bob must receive every post-removal message; Charlie must not receive plaintext.
   - Write role verdict fields under `gm020ImmediateRecipientExclusionProof`.

5. Run exact GM-020 direct host, criteria, and simulator proof. Do not run `--scenario all`.

6. Run adjacent gates. If production code changed, run analyzer over touched Dart files and the full listed adjacent host suites. If only tests/harness changed, still run the focused GM-020 host tests, criteria test, exact simulator proof, group gate, completeness check, and diff hygiene.

7. Stop once the closure bar is met. Do not expand into GM-021 re-add key-package behavior, GM-022 duplicate member records, GM-023 stale inactive shadow records, or any broad membership-model redesign.

## risks and edge cases

- Stale local membership immediately after removal could include Charlie in sender-side recipients.
- The bridge request and persisted retry payload could diverge, leaving retry delivery less private than the initial store attempt.
- A background or offline Charlie path could accidentally receive durable replay after being removed.
- Duplicate recipient IDs or sender inclusion could create privacy or delivery side effects.
- A simulator harness could accidentally validate recomputed membership rather than actual `group:inboxStore` payloads.
- Build-state failures can masquerade as simulator proof failures; they must be repaired and rerun rather than accepted as blockers.
- GM-019 re-add inclusion must remain unchanged if product code is touched.

## exact tests and gates to run

Focused RED/evidence-first tests:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-020'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-020'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-020'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-020'
```

Adjacent host suites:

```bash
flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test test/features/groups/integration/group_new_member_onboarding_test.dart
```

Conditional real-crypto proof:

```bash
flutter test integration_test/group_real_crypto_onboarding_test.dart
```

Run the real-crypto proof only if GM-020 touches real-crypto onboarding, bridge encryption/decryption semantics, key-package onboarding, or onboarding harness setup. If not run, record the exact skip reason.

Conditional Go proof:

```bash
cd go-mknoon
go test ./node -run '^TestBuildGroupInboxStoreRequest_' -count=1
```

Run this if `go-mknoon/node/group_inbox.go` or related Go recipient request behavior changes. If Go remains untouched, record that `GroupInboxStore` stayed the accepted caller-provided-recipient boundary.

Exact simulator-only Device/Relay Proof Profile:

```bash
MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm020 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Roles:

- Alice: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`
- Bob: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
- Charlie: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`

Use simulator-only devices and the repo/local relay configuration. Do not require physical devices or real external devices. Do not run `--scenario all`.

If `MKNOON_RELAY_ADDRESSES` is unset or stale, start or select the repo-local relay fixture used by the existing multi-party proof flow, export the local relay address, and rerun the exact `gm020` command. Missing relay configuration is setup repair, not a GM-020 product blocker.

Maintenance gates:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Run targeted `dart analyze` over touched Dart files if any Dart production or harness files change.

## known-failure interpretation

- A first red GM-020-focused test is expected if the proof is newly introduced before any required fix. It must become green before closure.
- Existing unrelated dirty worktree changes from GM-008 through GM-019 must not be reverted and must not be misclassified as GM-020 regressions.
- Existing unrelated analyzer info-level lints may be recorded only if unchanged and outside GM-020 touched files. New analyzer errors or warnings in touched files are GM-020 blockers.
- Simulator or Xcode build-state failures are repair/rerun infrastructure. Refresh devices, boot the exact simulators, uninstall the Runner app/extensions, clear Runner/Pods DerivedData and `build/ios` if needed, run `flutter pub get`, run `flutter clean` only if needed, and rerun the exact `gm020` proof. Do not leave the session blocked on stale simulator build state.
- A green GM-019 proof is supporting context only. It cannot close GM-020 without a GM-020 verdict and GM-020 direct proof.

## done criteria

- GM-020 host tests pass and inspect actual durable inbox payloads by message ID.
- GM-020 criteria tests accept valid proof and reject Charlie-recipient, missing-Bob, duplicate-recipient, sender-recipient, missing-actual-proof, timestamp-order, and Charlie-leak failures.
- Exact simulator-only `--scenario gm020` passes on the three specified simulator IDs and records `scenario: gm020`, `ok: true`, and GM-020 valid detail.
- Alice's proof shows every post-removal sent message has actual durable `recipientPeerIds` exactly Bob-only.
- Alice's first post-removal proof message is sent immediately after removal returns, and the repeated proof message covers the Charlie-offline/unavailable durable path.
- Bob receives every Alice post-removal message exactly once.
- Charlie receives zero post-removal plaintext and is absent from every actual durable recipient list.
- If no product code changes were needed, execution is explicitly classified as tests/harness/evidence-only.
- If product code changed, all direct, adjacent, named, conditional-as-needed, and hygiene gates listed above pass or have accepted unchanged external failure evidence.

## scope guard

Do not broaden GM-020 into:

- GM-021 fresh invite/key package after re-add.
- GM-022 duplicate peer IDs after re-add.
- GM-023 inactive shadow records.
- Group membership schema redesign.
- Go pubsub authorization redesign.
- Key rotation or real-crypto onboarding changes unless directly required by failing GM-020 proof.
- Notification payload, push, or UI work.
- Physical-device or external-device requirements.
- `--scenario all`.

Do not change source matrix or session breakdown as part of planning. During execution, defer closure doc updates to the closure/audit step unless the execution prompt explicitly includes them.

## accepted differences / intentionally out of scope

- Go `GroupInboxStore` remains a caller-provided-recipient boundary unless GM-020 directly proves Go mutates or drops recipients.
- GM-019's removed-window/re-add proof remains separate and intentionally does not close GM-020.
- Simulator proof is row-specific `gm020`; broad `all` scenario proof is intentionally out of scope.
- Real-crypto onboarding proof is conditional, not mandatory, unless GM-020 touches onboarding or encryption/decryption semantics.
- Product changes may be unnecessary; evidence-only closure is acceptable if row-owned proof passes.

## dependency impact

GM-021 through GM-024 depend on trustworthy member removal and recipient proof. If GM-020 fails because sender-side membership can be stale, pause later re-add and member-list rows until the durable-recipient fix lands. If GM-020 closes as evidence-only, later rows can reuse the GM-020 harness helpers but must still own their own source-row proof.

## Reviewer Findings

Result: sufficient with adjustments.

Required adjustments applied:

- Made the simulator proof sequence explicit: first immediate send after Alice removal returns, then a repeated send after Charlie is offline/unavailable.
- Required `gm020` updates in usage text and validation lists, not only role maps.
- Tightened GM-020 criteria proof fields to require at least two exact post-removal keys and an offline post-removal timestamp.
- Clarified that missing or stale relay env is local setup repair and must be rerun, not treated as a structural blocker.

Missing files, tests, or gates after adjustment: none structural. Direct host, criteria, exact simulator, named group/completeness, conditional Go, conditional real-crypto, analyzer, and diff-hygiene contracts are present.

Stale or incorrect assumptions: no stale closure assumption remains; GM-019 is supporting context only.

Overengineering: none found. The plan does not redesign membership, Go pubsub authorization, key rotation, or later GM rows.

Minimum needed for sufficiency: keep execution row-owned, add GM-020 proof first, and stop if current code passes.

## Arbiter Decision

Final classification: execution-ready.

Structural blockers: none remaining.

Incremental details intentionally deferred:

- Exact helper names for extracting `gm020` inbox-store payloads may be chosen during execution as long as they inspect actual bridge payloads by message ID.
- Exact local relay start command may follow the existing repo fixture available during execution; missing `MKNOON_RELAY_ADDRESSES` remains setup repair and rerun work, not a product blocker.

Accepted differences intentionally left unchanged:

- GM-019 remains supporting context, not closure for GM-020.
- Go `GroupInboxStore` remains the caller-provided-recipient boundary unless a GM-020 proof directly fails there.
- Real-crypto onboarding remains conditional.
- The exact simulator proof is `--scenario gm020`; `--scenario all` and physical devices are out of scope.

Why the plan is safe to implement now:

- It starts with row-owned RED/evidence-first proof before product changes.
- It has a precise closure bar against actual durable `recipientPeerIds`, persisted retry payloads, Bob delivery, and Charlie plaintext exclusion.
- It limits product edits to the failing seam if evidence exposes one.
- It contains exact direct tests, simulator-only device IDs, named gates, known-failure interpretation, and a stop rule.

## Execution Progress

- 2026-05-11T07:25:38+0200 - Controller extracted contract. Files inspected or touched: this GM-020 plan, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, git status. Decision/blocker: scope is GM-020 only, evidence-gated, simulator-only proof required, source matrix and breakdown are read-only for this session; `codex exec` is available for spawned Executor/QA agents. Next action: spawn Executor with model `gpt-5.5`, reasoning effort `xhigh`.
- 2026-05-11T07:27:48+0200 - Executor started and extracted GM-020 contract. Files inspected or touched: this GM-020 plan, GM-019-adjacent host tests, criteria, runner, simulator harness, git status. Decision/blocker: no existing GM-020 row-owned proof found; product code remains conditional only. Next action: add missing GM-020 evidence-first tests and harness support.
- 2026-05-11T07:37:57+0200 - Executor added GM-020 evidence-first proof. Files inspected or touched: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`. Decision/blocker: product code unchanged; next action is focused GM-020 direct tests.
- 2026-05-11T07:39:40+0200 - Focused GM-020 tests passed. Commands: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-020'`; `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-020'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-020'`; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-020'`. Decision/blocker: no product fix needed from direct proof. Next action: run adjacent host suites.
- 2026-05-11T07:40:38+0200 - Adjacent host suites passed. Commands: `flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart`; `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`. Decision/blocker: real-crypto skipped because GM-020 did not touch real-crypto onboarding, bridge encryption/decryption semantics, key-package onboarding, or onboarding harness setup; Go skipped because Go recipient request behavior and `go-mknoon/node/group_inbox.go` were untouched. Next action: exact simulator-only `--scenario gm020` proof.
- 2026-05-11T07:45:47+0200 - Exact simulator-only GM-020 proof passed. Command: `MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm020 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Verdict path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm020_UyQtpw/gmp_1778478097803_gm020_orchestrator_verdict.json`; role verdicts and logs are in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm020_UyQtpw`. Decision/blocker: no simulator repair or product fix needed.
- 2026-05-11T07:47:57+0200 - Maintenance gates and analyzer passed. Commands: `flutter analyze test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart`; `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check`; `git diff --check`. Decision/blocker: no analyzer findings, group gate passed, completeness check classified 731/731 test files, whitespace check clean.
- 2026-05-11T07:48:03+0200 - Executor result: GM-020 implemented and verified as tests/harness/evidence-only. Product code changed by this Executor: no. Source matrix and session breakdown changed by this Executor: no. Remaining blocker/uncertainty: none from Executor pass; ready for separate QA Reviewer role.
- 2026-05-11T07:52:14+0200 - QA Reviewer accepted GM-020. Files inspected/touched: this plan progress entry only; inspected GM-020 diff scope, executor summary, source matrix and session breakdown GM-020 rows, GM-020 host proofs, criteria, runner, harness, and persisted simulator verdict files. Commands rerun: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-020'`; `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-020'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-020'`; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-020'`; `git diff --check`. Decision/blocker: PASS / accepted, no blocking issues; exact simulator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm020_UyQtpw/gmp_1778478097803_gm020_orchestrator_verdict.json` records `scenario: gm020`, `ok: true`, and `gm020 verdicts valid for alice, bob, charlie`; source matrix and session breakdown were not updated for GM-020 closure by this QA pass.
