# GM-019 Implementation Plan

Status: execution-ready

## Planning Progress

- 2026-05-11 06:24:00 CEST - Planner completed. Files inspected since last update: local evidence from docs, code, test, criteria, runner, and harness scans. Decision/blocker: drafted GM-019 as implementation-ready with RED-first host, criteria, and simulator proof for actual durable `recipientPeerIds` before and after re-add. Next action: run Reviewer sufficiency pass.
- 2026-05-11 06:24:06 CEST - Reviewer started. Files inspected since last update: full planning draft. Decision/blocker: review focus is sufficiency, stale assumptions, over-broad commands in a dirty worktree, and exact durable-payload proof strength. Next action: classify required adjustments.
- 2026-05-11 06:24:06 CEST - Reviewer completed. Files inspected since last update: full planning draft and exact command section. Decision/blocker: sufficient with one adjustment applied: format/analyze guidance must be limited to GM-019-touched Dart files only, not every candidate in the dirty worktree. Next action: run Arbiter and finalize if no structural blockers remain.
- 2026-05-11 06:24:52 CEST - Arbiter started. Files inspected since last update: reviewer findings and revised plan. Decision/blocker: classify reviewer adjustment and decide whether any structural blocker remains. Next action: finalize or patch once.
- 2026-05-11 06:24:52 CEST - Arbiter completed. Files inspected since last update: final plan sections, closure bar, scope guard, regression contract, simulator proof profile, known-failure policy, and reviewer findings. Decision/blocker: no structural blockers remain; touched-file formatting adjustment is applied; stop rule reached. Next action: use this execution-ready plan for GM-019 only.

## Execution Progress

- 2026-05-11 06:26:43 CEST - Contract extracted. Files inspected since last update: GM-019 plan, skill instructions, git status, gm019/gm018 support scan. Decision/blocker: scope is GM-019 only; source matrix and breakdown are dirty pre-existing files and must not be edited; `codex exec` is available for spawned Executor/QA isolation. Next action: spawn Executor agent with GM-019 plan and exact gates.
- 2026-05-11 06:28:00 CEST - Executor spawn attempt adjusted. Files inspected since last update: `codex exec --help`. Decision/blocker: first command used unsupported `-a`; no child materialized and no repo edits occurred from that attempt. Next action: retry Executor spawn with approval policy through config.
- 2026-05-11 06:28:12 CEST - Executor local pass started. Files inspected since last update: GM-019 plan remainder, git status, `GM-019|gm019` repo scan. Decision/blocker: no GM-019/gm019 implementation support exists outside this plan; source matrix and breakdown remain protected dirty files; scope is RED host tests plus gm019 criteria/runner/harness support, production code only if RED proves a gap. Next action: inspect direct test, criteria, runner, and harness seams for minimal GM-019 additions.
- 2026-05-11 06:33:54 CEST - Direct seams inspected. Files inspected since last update: send use case, send-message tests, member-removal integration test, group membership smoke test, criteria test/script, runner, real multi-party harness, shared real harness bridge setup. Decision/blocker: current recipient selector uses current membership only; GM-019 RED will include a timestamped removed-window durable send after re-add to prove whether Charlie leaks into actual `group:inboxStore` payloads. Next action: add GM-019 RED tests plus criteria/runner/harness support without touching production recipient selection yet.
- 2026-05-11 06:34:13 CEST - Executor child stopped for no-progress. Files inspected since last update: child stdout, git status for GM-019 candidate files, current `## Execution Progress`, gm019 marker scan. Decision/blocker: spawned Executor produced exploratory reads and heartbeats but no GM-019 code/test support after bounded waits; classified as `spawn_or_tool_failure`. Next action: use local sequential fallback for the Executor pass, then perform QA only after required evidence is available.
- 2026-05-11 06:45:23 CEST - Local fallback implementation landed and formatted. Files touched since last update: `lib/features/groups/application/send_group_message_use_case.dart`, GM-019 host tests, criteria script/test, runner, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/group_multi_device_real_harness.dart`. Decision/blocker: production recipient selection now filters durable recipients by `joinedAt <= messageTimestamp`; harness records actual bridge `group:inboxStore` payload recipients. Next action: run focused GM-019 selectors.
- 2026-05-11 06:47:18 CEST - Focused GM-019 selectors completed. Files inspected/touched since last update: touched Dart files and targeted analyzer warning in `integration_test/group_multi_device_real_harness.dart`. Commands finished: four `flutter test --no-pub ... --plain-name 'GM-019'` selectors all passed; targeted `dart analyze` exited 0 with three existing `use_null_aware_elements` infos in `send_group_message_use_case.dart`. Decision/blocker: no GM-019 focused blocker remains. Next action: run direct adjacent suites.

## Evidence Collector Findings

- Source matrix row GM-019 is `Open`: Charlie is removed then re-added; messages stored during the removed interval must exclude Charlie from durable `recipientPeerIds`, and messages stored after re-add must include Charlie.
- Breakdown row GM-019 is `needs_code_and_tests` / `implementation-ready` / `code changes + tests`; it names membership/config/key/listener and Go inbox/pubsub files as likely owners.
- The direct Flutter recipient-selection seam is `lib/features/groups/application/send_group_message_use_case.dart`: `_loadGroupSendMembership` loads current `groupRepo.getMembers(groupId)`, excludes the sender, de-duplicates with `toSet()`, and passes that list into the replay envelope, retry payload, and `callGroupInboxStore`.
- `go-mknoon/node/group_inbox.go` does not compute membership eligibility. `GroupInboxStore` and `buildGroupInboxStoreRequest` only forward `recipientPeerIds` into the relay request.
- `GroupMember.toConfigJson()` omits `joinedAt`; receive paths reconstruct `joinedAt` from the membership event timestamp when there is no existing member. Re-add correctness therefore depends on event timestamps and local membership snapshots being current.
- GM-018 is closed only for remaining-member delivery after Charlie removal. It proves Bob live and durable inbox continuity while Charlie is stale, but it never re-adds Charlie and cannot close GM-019.
- GM-010, GM-012, and GM-014 are supporting context for duplicate re-add, stale remove after re-add, and delayed re-add/key behavior. They do not prove GM-019's removed-window durable recipient exclusion plus post-readd durable inclusion in one row-owned proof.
- Current criteria, runner, and harness support scenarios through `gm018`; no `gm019` scenario, proof contract, criteria test, or exact simulator command exists.

## Real Scope

GM-019 owns only durable inbox recipient eligibility across one remove/re-add boundary in private group chat:

1. Remove Charlie from an Alice/Bob/Charlie private group.
2. Store Alice/Bob messages during Charlie's removed interval and prove durable `recipientPeerIds` exclude Charlie.
3. Re-add Charlie with current membership/key state.
4. Store messages after re-add and prove durable `recipientPeerIds` include Charlie exactly once where Charlie is an eligible recipient.

Allowed implementation scope:

- Add GM-019 row-owned host tests, criteria tests, runner wiring, and exact three-simulator harness support.
- Touch production code only if the new RED tests prove a real eligibility gap.
- Include `send_group_message_use_case.dart` in the possible implementation scope because it is the actual recipient selector, even though the breakdown likely-owner list does not name it.
- If production changes are required, keep them to recipient selection or membership timestamp/state application needed for this boundary.

Out of real scope:

- Source matrix or breakdown edits during implementation.
- GM-020 or later durable-recipient rows.
- Physical devices or real external device dependency.
- `--scenario all` expansion.
- Broad relay authorization redesign.

## Closure Bar

GM-019 is good enough only when all of these are true:

- A row-owned host proof inspects actual `group:inboxStore` payloads, not recomputed local member lists.
- Removed-window durable sends have `recipientPeerIds` exactly equal to the eligible remaining peers, with Charlie absent and no duplicates.
- Post-readd durable sends include Charlie exactly once when Charlie is an eligible recipient, and still exclude the sender.
- The proof includes at least Alice during removal, Alice after re-add, and one non-Alice post-readd sender so the recipient selector is not only validated for one role.
- Criteria tests reject verdicts that include Charlie during the removed window, omit Charlie after re-add, contain duplicate recipient IDs, or report recomputed-only proof instead of actual durable payload proof.
- Exact simulator proof passes for scenario `gm019` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Build-state or simulator/Xcode failures are repaired and rerun; they are not accepted as a final GM-019 blocker.

## Source Of Truth

- Primary contract: source matrix row GM-019 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- Session decomposition: GM-019 row in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Execution gates: `Test-Flight-Improv/test-gate-definitions.md` plus `scripts/run_test_gates.sh`; if they disagree, the script wins.
- Current production code and tests beat stale prose.
- This plan is the active GM-019 execution contract until code evidence disproves one of its assumptions.

## Session Classification

`implementation-ready`

This is not docs-only or acceptance-only while GM-019 remains Open and no GM-019-specific proof exists. The implementation may end with tests/harness-only production behavior if RED proof shows current code already satisfies the contract, but the session still owns code/test artifacts and exact proof.

## Exact Problem Statement

The app must not let a removed member receive durable group inbox replay for messages from the interval when that member was not in the group. After the same member is re-added, the app must include that member in durable inbox recipient sets for new eligible messages.

The risky seam is that durable `recipientPeerIds` are decided before the relay store call. The relay/Go `GroupInboxStore` path forwards the caller-provided list and does not enforce group membership windows. If Flutter uses stale membership, duplicate re-add state, or current membership for a message from the wrong membership window, Charlie can be incorrectly included before re-add or omitted after re-add.

Must stay unchanged:

- Existing removed-member rejection behavior from GM-016/GM-017.
- Remaining-member delivery continuity from GM-018.
- Duplicate/stale re-add ordering behavior from GM-010/GM-012/GM-014.
- Empty-recipient durable store behavior for one-member groups.

## Files And Repos To Inspect Next

Production and bridge seams:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/pubsub.go`

Direct test and harness seams:

- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/group_real_crypto_onboarding_test.dart` only if real-crypto onboarding, bridge encryption/decryption semantics, or onboarding harness setup changes.

## Existing Tests Covering This Area

- `send_group_message_use_case_test.dart` already proves normal group sends load members, exclude the sender, include `recipientPeerIds`, and omit the field for empty recipient lists.
- `member_removal_integration_test.dart` has GM-018 proof that repeated post-removal sends keep durable recipients Bob-only, but it does not re-add Charlie.
- `group_membership_smoke_test.dart` has GM-010, GM-012, and GM-014 tests that prove adjacent duplicate/stale/simultaneous re-add behavior and inspect durable recipients in some post-readd cases.
- `group_membership_smoke_test.dart` GM-018 proves remaining-member live/inbox continuity while Charlie is removed, but not post-readd inclusion.
- `group_inbox_test.go::TestBuildGroupInboxStoreRequest_MarshalsRecipientPeerIds` proves Go marshals the list it is given.
- `group_multi_party_device_criteria_test.dart` and `group_multi_party_device_criteria.dart` validate scenarios through GM-018 only.

Missing:

- A GM-019-owned test that proves the same removed/re-added Charlie is excluded from removed-window durable recipient sets and included after re-add.
- A GM-019-owned criteria contract that rejects wrong `recipientPeerIds`.
- A GM-019 exact simulator scenario that records actual durable inbox store payloads.

## Regression/Tests To Add First

Add RED tests before production fixes:

1. `test/features/groups/application/send_group_message_use_case_test.dart`
   - Add `GM-019 removed-window durable recipients exclude re-added member until re-add`.
   - Build Alice/Bob/Charlie members, remove Charlie, send a removed-window message, inspect the actual `group:inboxStore` payload and persisted `inboxRetryPayload`, and assert recipients are Bob-only.
   - Re-add Charlie with `joinedAt == readdAt`, send a post-readd message, inspect actual durable payload and retry payload, and assert recipients are Bob + Charlie exactly once.

2. `test/features/groups/application/member_removal_integration_test.dart`
   - Add a GM-019 focused application/integration proof that uses the real remove/add use cases and exact inbox payload extraction.
   - Include a delayed-store edge if the RED result shows a leak: a message timestamped during the removed window must not gain Charlie as a durable recipient after Charlie is re-added.

3. `test/features/groups/integration/group_membership_smoke_test.dart`
   - Add `GM-019 durable recipients exclude Charlie during removal and include Charlie after re-add`.
   - Use the existing Alice/Bob/Charlie fake network helpers, rotate or distribute current key state as needed, remove Charlie, send removed-window messages, re-add Charlie, wait for membership convergence, and send post-readd messages from Alice and Bob.
   - Every assertion must parse actual bridge `group:inboxStore` payloads by replay envelope `messageId`; do not accept recipient lists recomputed from `groupRepo.getMembers`.

4. `test/integration/group_multi_party_device_criteria_test.dart`
   - Add valid GM-019 verdict fixtures.
   - Add invalid cases for Charlie present in removed-window recipients, Charlie missing after re-add, duplicate recipients, sender included as a recipient, missing actual-durable proof flag, wrong scenario, and wrong role set.

5. `integration_test/scripts/group_multi_party_device_criteria.dart`
   - Add `gm019DurableRecipientWindowProof`.
   - Validate timestamp order `removedAt < removedWindowSentAt < readdAt < postReaddSentAt`.
   - Validate actual sent-message `recipientPeerIds` for removed-window and post-readd keys using `_requireSentRecipientPeerIds`.

6. `integration_test/scripts/run_group_multi_party_device_real.dart` and `integration_test/group_multi_party_device_real_harness.dart`
   - Add `gm019` scenario support for Alice/Bob/Charlie.
   - Ensure harness sent-message records capture actual `group:inboxStore` payload recipient lists, not expected recipients recomputed from local membership.

Only after these RED tests identify a production gap should production code change.

## Step-By-Step Implementation Plan

1. Reconfirm no `GM-019`, `gm019`, or existing proof support was added after this plan.
2. Add a small test helper in affected tests/harness to extract the actual durable store payload by matching the replay envelope `messageId`.
3. Add focused GM-019 RED host tests and GM-019 criteria tests. Run the focused selectors and record whether failures are missing-support failures or product behavior failures.
4. Add `gm019` criteria, runner, and harness support with proof fields that include actual durable recipient lists before and after re-add.
5. If the RED tests pass production behavior after support code is added, stop product changes and proceed with proof/gates. This is still GM-019 implementation, not docs-only closure.
6. If removed-window recipients include Charlie, fix the smallest proven seam. Prefer a shared recipient-selection helper that:
   - starts from current group members,
   - excludes the sender,
   - de-duplicates peer IDs,
   - excludes members whose `joinedAt` is after the message timestamp for timestamped message sends/retries,
   - preserves current empty-recipient behavior.
7. Apply the helper only to paths proven by GM-019 RED evidence:
   - `send_group_message_use_case.dart` first,
   - `retry_incomplete_group_uploads_use_case.dart` only if delayed media/upload retry leaks Charlie,
   - avoid rewriting `retry_failed_group_inbox_stores_use_case.dart` unless its persisted retry payload is proven wrong.
8. If post-readd recipients omit Charlie, inspect and minimally fix membership application:
   - `add_group_member_use_case.dart`,
   - `group_message_listener.dart`,
   - `group_key_update_listener.dart`,
   - `group_config_payload.dart`,
   - `GroupMember.fromConfigMap` / `toConfigJson` behavior only if event timestamp evidence requires it.
9. Do not add relay-side membership enforcement unless the Flutter/Go boundary proves impossible to make correct. The current architecture expects Flutter to send the exact recipient set.
10. Run focused host tests, criteria tests, exact simulator proof, named gates, and diff hygiene.
11. Do not edit the source matrix or breakdown during execution. Leave closure updates for a later closure-audit pass.

## Risks And Edge Cases

- Actual durable payload proof can be accidentally weakened by using recomputed membership. GM-019 must inspect `group:inboxStore` payloads.
- Re-add event timestamps can drift across roles. Criteria should require a shared re-add timestamp or prove each role's `joinedAt` matches the re-add event it accepted.
- Persisted retry payloads should keep the original removed-window recipient list. Recomputing recipients during retry can leak removed-window messages to Charlie.
- Media upload retry may use current members at retry completion. Do not broaden into media unless a GM-019 RED test proves this path leaks the removed-window recipient set.
- Stale remove after re-add is already GM-012-supported; GM-019 must not weaken that behavior.
- Duplicate re-add is already GM-010-supported; GM-019 should assert no duplicate durable recipients but not redesign duplicate handling.
- Simulator build/Xcode state can fail independently of GM-019 behavior. Treat that as repair/rerun infrastructure.

## Exact Tests And Gates To Run

Focused RED/implementation selectors:

```sh
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-019'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-019'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-019'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-019'
```

Direct adjacent suites after fixes:

```sh
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'GM-014'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-014'
```

Conditional direct tests:

```sh
(cd go-mknoon && go test ./node -run '^TestBuildGroupInboxStoreRequest_MarshalsRecipientPeerIds$' -count=1)
flutter test -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD integration_test/group_real_crypto_onboarding_test.dart
```

Run the Go test if `go-mknoon/node/group_inbox.go`, `go-mknoon/node/pubsub.go`, or bridge request semantics change. Run the real-crypto onboarding simulator test only if GM-019 changes real-crypto onboarding, bridge encryption/decryption semantics, key-package delivery, or onboarding harness setup.

Targeted analyzer and formatting:

```sh
dart format <GM-019-touched Dart files only>
dart analyze <GM-019-touched Dart files only>
```

Do not format or analyze every candidate file just because it is listed in this plan. Build the touched-file list from the GM-019 diff and leave unrelated dirty GM-008 through GM-018 files alone.

Exact simulator-only proof:

```sh
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm019 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gates and hygiene:

```sh
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Do not require `--scenario all`.

## Simulator-Only Device/Relay Proof Profile

- Scenario: `gm019`.
- Alice simulator: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`.
- Bob simulator: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`.
- Charlie simulator: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Relay env must match `expectedMultiPartyRelayAddresses` in `integration_test/scripts/group_multi_party_device_criteria.dart`.
- No physical devices are required or accepted for GM-019 closure.
- The proof must emit an orchestrator verdict with `scenario: gm019`, `ok: true`, role devices mapped to the three simulator IDs above, and criteria detail confirming GM-019 verdicts valid for Alice, Bob, and Charlie.

If the exact simulator proof fails because of simulator/Xcode/build state:

1. Refresh device state with `xcrun simctl list devices`.
2. Boot the exact three simulators if needed with `xcrun simctl boot <udid>`.
3. Uninstall the app and extensions from those simulators if stale installs are suspected.
4. Clear Runner/Pods DerivedData and `build/ios` if the failure is an Xcode build-state or stale native artifact failure.
5. Run `flutter pub get` or `flutter clean` only when the failure evidence points to dependency or Flutter build cache state.
6. Rerun the exact `gm019` command above.

Do not leave GM-019 as simulator/Xcode build-state blocked without this repair/rerun attempt.

## Known-Failure Interpretation

- Initial RED failures in newly added GM-019 tests are expected until production or harness support is fixed. They are not closure evidence.
- Pre-existing dirty worktree changes from GM-008 through GM-018 must not be reverted.
- Existing source matrix and breakdown edits are out of planning/execution scope and should not be touched by the GM-019 implementation pass.
- Pre-existing analyzer warnings outside GM-019 touched files may be recorded as residual only if targeted analyzer on touched files is clean and the direct GM-019 proof passes.
- Build-state failures are infrastructure repair/rerun work, not accepted product blockers.
- A green GM-018 simulator proof is supporting context only; it does not satisfy GM-019.

## Done Criteria

- GM-019 host RED tests exist and pass after implementation.
- GM-019 criteria tests exist and pass, including negative cases for wrong recipient sets.
- `gm019` runner and harness support exists.
- Exact simulator-only `gm019` proof passes on the three required simulator IDs.
- Removed-window actual durable `recipientPeerIds` exclude Charlie.
- Post-readd actual durable `recipientPeerIds` include Charlie exactly once for eligible sends and exclude the sender.
- No duplicate durable recipients are present.
- Adjacent GM-010/GM-012/GM-014/GM-018 behavior remains intact through the listed focused tests or suites.
- Named `groups` and `completeness-check` gates pass.
- `git diff --check` passes.
- Source matrix and breakdown remain unedited by the implementation pass unless a later closure task explicitly requests them.

## Scope Guard

Do not:

- Reopen GM-018 or claim GM-018 evidence closes GM-019.
- Implement GM-020 or later rows.
- Add relay-side group membership enforcement as the first fix.
- Widen `--scenario all`.
- Require physical devices.
- Rewrite group invite, role, announcement, media, or full key-rotation architecture.
- Change source matrix or breakdown during implementation.
- Treat recomputed member lists as durable recipient proof.
- Fix unrelated dirty worktree files or revert prior GM-008 through GM-018 edits.

Overengineering for this session includes broad recipient-policy frameworks, generic membership-window history services, relay ACL redesign, randomized stress tests, or app-wide retry rewrites unless the RED proof demonstrates that exact shared seam is the failing GM-019 behavior.

## Accepted Differences / Intentionally Out Of Scope

- Go `GroupInboxStore` forwarding caller-provided `recipientPeerIds` is an accepted architecture boundary for GM-019. The row requires Flutter to send the right list.
- GM-018's Charlie stale pressure was live-only by accepted design and remains separate from GM-019's post-readd durable recipient inclusion.
- GM-010/GM-012/GM-014 are supporting context for re-add event ordering, not closure proof for GM-019.
- Real-crypto onboarding is conditional. Do not run or change it unless GM-019 touches onboarding or crypto semantics.
- Media/upload retry expansion is deferred unless the RED test proves that path leaks removed-window recipients.

## Dependency Impact

- Later durable-recipient and re-add rows can rely on GM-019 only after this plan's host, criteria, and exact simulator proof pass.
- If GM-019 requires a shared recipient-selection helper, later retry/media rows should reuse it instead of duplicating recipient policy.
- If GM-019 proves current production behavior already correct, later rows should rely on the new GM-019 proof fields and actual durable payload extraction helper, not on GM-018.
- If exact simulator proof cannot pass after build-state repair/rerun, later GM rows that depend on three-party simulator proof should pause until the infrastructure issue is resolved.

## Reviewer Findings

- Sufficiency: sufficient with the formatting/analyzer adjustment above.
- Missing files/tests/gates: none after adding the direct selector tests, membership smoke proof, criteria tests, runner/harness support, exact simulator command, named gates, and conditional Go/real-crypto gates.
- Stale assumptions: none found. The plan correctly treats GM-018 and GM-010/GM-012/GM-014 as supporting context only.
- Overengineering: no blocking overengineering. The media/upload retry path is explicitly conditional and deferred unless RED evidence proves it leaks GM-019 recipients.
- Decomposition: narrow enough for implementation. RED proof is first, production changes are conditional, and relay-side ACL redesign is guarded out.
- Minimum needed for sufficiency: preserve exact durable-payload inspection, add `gm019` criteria/runner/harness support, and keep formatting/analyzer commands scoped to GM-019-touched files.

## Arbiter Decision

- Final verdict: execution-ready for GM-019 only.
- Structural blockers remaining: none.
- Incremental details intentionally deferred: exact helper names and proof-field names may be adjusted during implementation if the criteria still enforces the same durable-recipient facts.
- Accepted differences intentionally left unchanged: Go relay/inbox forwarding remains a boundary; GM-018 and prior re-add rows remain supporting context only; real-crypto onboarding remains conditional.
- Why safe to implement now: the plan has a narrow scope, RED-first proof, exact durable-payload requirement, simulator-only proof profile, named gates, dirty-worktree guard, and a stop rule that prevents broad product rewrites.
