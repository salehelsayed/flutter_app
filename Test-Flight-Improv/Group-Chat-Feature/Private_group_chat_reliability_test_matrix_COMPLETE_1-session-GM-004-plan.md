# GM-004 Remove Current Member While Online Plan

Status: closed

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`

Pipeline artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`

Session: `GM-004`

Scenario: Remove C while C is online.

Preconditions: C is a current member and topic peer.

Steps: A removes C and rotates key; A/B send; C attempts send/decrypt.

Expected: A/B continue receiving; C is rejected for send and cannot decrypt post-removal messages.

Source row status: Covered.

Breakdown classification: `needs_repo_evidence`, `covered/accepted`; missing GM-004 proof support was implemented and exact row proof passed.

Closure verdict: `closed` for GM-004 only; GM-005 and later rows remain unresolved.

## Planning Progress

- 2026-05-10 13:34:59 CEST - Arbiter completed. Files inspected since last update: reviewer findings, closure bar, regression-first order, scope guard, accepted differences, and exact test/gate contract. Decision/blocker: no structural blockers; incremental details are intentionally deferred; plan is execution-ready. Next action: hand off to execution without marking GM-004 covered.
- 2026-05-10 13:34:50 CEST - Arbiter started. Files inspected since last update: reviewer findings and completed plan sections. Decision/blocker: no provisional structural blocker. Next action: classify reviewer findings and finalize status.
- 2026-05-10 13:34:31 CEST - Reviewer completed. Files inspected since last update: GM-004 draft plan sections and scoped grep checks for status, mandatory headings, GM-004 references, closure wording, and exact gates. Decision/blocker: sufficient as-is with no structural blocker; timestamp drift in draft progress entries corrected. Next action: arbiter classification.
- 2026-05-10 13:34:10 CEST - Reviewer started. Files inspected since last update: GM-004 draft plan sections. Decision/blocker: no initial blocker; checking closure bar, scope guard, regression-first rule, source of truth, and test/gate contract. Next action: complete sufficiency review.
- 2026-05-10 13:34:00 CEST - Planner completed. Files inspected since last update: row docs, accepted GM harness files, group remove/send flows, group membership/member-removal tests, Go validator/key tests, `test-inventory.md`, and `test-gate-definitions.md`. Decision/blocker: draft plan is implementation-ready because GM-004 lacks exact row-owned host/device proof and `--scenario gm004` harness support. Next action: reviewer sufficiency pass.
- 2026-05-10 13:29:41 CEST - Evidence Collector started. Files inspected since last update: none yet beyond the requested source row/session metadata. Decision/blocker: intake artifact created so planning can proceed file-backed. Next action: inspect the current breakdown row, source matrix row, accepted harness capabilities, adjacent tests, and test gate docs only as needed.

## Execution Progress

- 2026-05-10 13:38:14 CEST - Contract extracted. Files inspected since last update: this GM-004 plan, current git status, and local `codex exec` availability. Decision/blocker: plan is concrete; worktree is intentionally dirty; child-agent spawning appears available through `codex exec`. Next action: spawn isolated Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-10 13:39:00 CEST - Executor spawn requested. Files inspected since last update: plan execution contract and Codex CLI help. Command currently running: isolated Executor via `codex exec -m gpt-5.5` with xhigh reasoning request. Decision/blocker: no blocker yet. Next action: wait for bounded Executor result and inspect assigned-file progress before QA.
- 2026-05-10 13:39:12 CEST - Executor spawn retried. Files inspected since last update: failed `codex exec` invocation output. Decision/blocker: first spawn failed before work because this CLI build does not accept `-a`; no repo files were touched by the child. Next action: rerun Executor spawn with approval policy supplied through config.
- 2026-05-10 13:40:09 CEST - Executor local pass started. Files inspected since last update: plan execution contract, dirty worktree status, GM-004 grep over host smoke test, criteria, harness, and runner. Decision/blocker: GM-004 host/criteria/runner/harness support is absent; existing dirty files are preserved. Next action: inspect owner files and add the smallest GM-004-scoped proof.
- 2026-05-10 13:49:14 CEST - Baseline and implementation delta landed. Files inspected or touched since last update: `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`. Decision/blocker: baseline `member_removal_integration_test.dart` and pre-edit full membership smoke passed; GM-004 host regression, criteria contract/tests, runner scenario, and real-device harness support added without product changes. Next action: format and run focused GM-004 tests.
- 2026-05-10 13:51:06 CEST - Focused and direct host tests passed. Files inspected or touched since last update: formatted GM-004 host/criteria/runner/harness files. Commands completed: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-004 removes C while online, rotates key, A/B continue, and C loses access'` passed; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed; `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart` passed; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` passed. Decision/blocker: no product gap exposed by host/criteria proof. Next action: refresh device discovery and run exact GM-004 relay/device proof.
- 2026-05-10 13:58:53 CEST - First GM-004 device proof failed in harness setup. Files inspected or touched since last update: `integration_test/group_multi_party_device_real_harness.dart`, shared artifact directory `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm004_ekGiyI`, and per-role logs under that directory. Commands completed: exact GM-004 relay/device proof started with three simulators and failed on Charlie after `GROUP_MESSAGE_LISTENER_SELF_REMOVED` because the imported fixture preserved Alice's local `myRole=admin`, causing `GROUP_LEAVE_USE_CASE_BLOCKED_LAST_ADMIN`. Decision/blocker: this is a GM-004 harness fixture-role bug, not a product gap; patched GM-004 Bob/Charlie fixture import to derive local `myRole` from the imported self member before removal processing. Next action: rerun the exact GM-004 relay/device proof.
- 2026-05-10 14:03:24 CEST - Executor continuation started. Files inspected since last update: local process table, latest GM-004 artifact directories, and this progress section. Decision/blocker: prior Executor process was idle with no active `flutter`, `dart`, `xcrun`, or `simctl` child process after the harness-only fixture-role patch; no accepted GM-004 device proof has been captured yet. Next action: spawn fresh Executor continuation to refresh device discovery, rerun the exact GM-004 relay/device proof with the accepted relay env and three simulator IDs, then run required groups/completeness/git-diff gates or record blocker artifacts.
- 2026-05-10 14:04:34 CEST - Device discovery refreshed. Files inspected since last update: `flutter devices --machine` output and `xcrun simctl list devices available` output. Commands completed: `flutter devices --machine`; `xcrun simctl list devices available`. Output summary: Flutter sees Pixel 6 `21071FDF600CSC`, iPhone 17 Pro `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, iPhone 16e `1B098DFF-6294-407A-A209-BBF360893485`, macOS, and Chrome; `simctl` shows the three required iOS 26.1 simulator IDs booted plus iPhone 16e booted. Decision/blocker: required three simulator IDs are available. Next action: run the exact GM-004 relay/device proof with the accepted relay env and device list.
- 2026-05-10 14:05:05 CEST - Exact GM-004 relay/device proof started. Files inspected or touched since last update: this progress section only. Command currently running: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm004 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Decision/blocker: no blocker yet. Next action: wait for proof result and inspect artifacts if it fails.
- 2026-05-10 14:08:52 CEST - Exact GM-004 relay/device proof passed. Files inspected since last update: artifact directory `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm004_xapxB3`, orchestrator verdict `gmp_1778414729800_gm004_orchestrator_verdict.json`, and Alice/Bob/Charlie role verdict JSON files. Commands completed: exact GM-004 relay/device proof command above. Artifact paths: shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm004_xapxB3`; orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm004_xapxB3/gmp_1778414729800_gm004_orchestrator_verdict.json`; role logs/verdicts `alice.log`, `bob.log`, `charlie.log`, `gmp_1778414729800_alice_verdict.json`, `gmp_1778414729800_bob_verdict.json`, `gmp_1778414729800_charlie_verdict.json`. Decision/blocker: orchestrator verdict is `scenario: gm004`, `ok: true`, `detail: gm004 verdicts valid for alice, bob, charlie`; Alice and Bob have key epoch 2, exclude Charlie, and receive each other's post-removal messages; Charlie has no post-removal group/key, stores no post-removal plaintext, and his post-removal send is `groupNotFound` with `accepted: false`. Next action: run `./scripts/run_test_gates.sh groups`.
- 2026-05-10 14:09:51 CEST - Groups gate started. Files inspected or touched since last update: this progress section only. Command currently running: `./scripts/run_test_gates.sh groups`. Decision/blocker: no blocker yet; command is resolving dependencies and running the group messaging gate. Next action: wait for gate result.
- 2026-05-10 14:10:24 CEST - Groups gate failed and needs isolation. Files inspected since last update: `scripts/run_test_gates.sh` and the gate output tail. Commands completed: `./scripts/run_test_gates.sh groups` failed with exit code 1 after `+107 -1`; output tail shows failure while running `test/features/groups/integration/group_membership_smoke_test.dart`, but the assertion details were truncated by the verbose flow logs. Decision/blocker: not yet classified as GM-004, harness setup, product gap, or unrelated/pre-existing gate failure. Next action: rerun `group_membership_smoke_test.dart` in isolation with structured output to identify the exact failing test and assertion.
- 2026-05-10 14:13:17 CEST - GM-004 host gate failure isolated and fixed. Files inspected or touched since last update: `/tmp/gm004_group_membership_smoke_1410.jsonl` and `test/features/groups/integration/group_membership_smoke_test.dart`. Commands completed: `flutter test --no-pub --reporter json test/features/groups/integration/group_membership_smoke_test.dart > /tmp/gm004_group_membership_smoke_1410.jsonl` failed and identified testID 16, `GM-004 removes C while online, rotates key, A/B continue, and C loses access`, at line 1688; targeted rerun failed once with fixed `removedAt` `2026-05-10T12:01Z` because the membership watermark was later than that timestamp; `dart format test/features/groups/integration/group_membership_smoke_test.dart` passed with no formatting changes; targeted rerun `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-004 removes C while online, rotates key, A/B continue, and C loses access'` passed. Decision/blocker: classified as GM-004 host test setup flake, not product behavior, because the stale fixed removal timestamp caused the listener to correctly ignore the event; changed only the GM-004 host test to use a run-relative removal timestamp and give fake listeners one pump before removal. Next action: rerun full `group_membership_smoke_test.dart`, then retry `./scripts/run_test_gates.sh groups`.
- 2026-05-10 14:13:44 CEST - Full GM membership host suite passed. Files inspected or touched since last update: `test/features/groups/integration/group_membership_smoke_test.dart`. Commands completed: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` passed. Decision/blocker: isolated GM-004 host fix is stable in the full membership smoke suite. Next action: retry `./scripts/run_test_gates.sh groups`.
- 2026-05-10 14:14:25 CEST - Groups gate passed on retry. Files inspected or touched since last update: group gate output. Commands completed: `./scripts/run_test_gates.sh groups` passed with `00:07 +108: All tests passed!`. Decision/blocker: no remaining groups-gate blocker after the scoped GM-004 host test timestamp fix. Next action: run `./scripts/run_test_gates.sh completeness-check`.
- 2026-05-10 14:14:48 CEST - Completeness gate passed. Files inspected or touched since last update: completeness-check output. Commands completed: `./scripts/run_test_gates.sh completeness-check` passed with `731/731 test files classified`. Decision/blocker: no completeness blocker. Next action: run `git diff --check`.
- 2026-05-10 14:15:12 CEST - Executor continuation complete and result written. Files inspected or touched since last update: final git status/diff, this plan, `test/features/groups/integration/group_membership_smoke_test.dart`, and `/tmp/gm004-executor-cont-result.md`. Commands completed: `git diff --check` passed. Decision/blocker: no remaining Executor blocker; exact GM-004 three-device proof, `groups`, `completeness-check`, and whitespace gates are green. Result file: `/tmp/gm004-executor-cont-result.md`. Next action: hand off to QA Reviewer; do not mark GM-004 Covered in the source matrix or breakdown during this Executor step.
- 2026-05-10 14:21:52 CEST - QA Reviewer accepted. Files inspected since last update: `/tmp/gm004-qa-result.md`, GM-004 plan/source/breakdown status, GM-004 harness/criteria/runner/test deltas, and accepted proof artifacts. Commands rerun by QA: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`, focused GM-004 host regression, `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`. Decision/blocker: no blocking or non-blocking fix-pass findings; source matrix GM-004 remains `Open` and breakdown remains `Open` / `needs_repo_evidence` for later closure. Next action: report execution verdict and artifact paths.

## Closure Audit Progress

- 2026-05-10 14:24:58 CEST - Completion Auditor completed. Files inspected since last update: accepted execution and QA notes in this plan, source matrix GM-004 row, breakdown GM-004 inventory/session/ordered rows, orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm004_xapxB3/gmp_1778414729800_gm004_orchestrator_verdict.json`, role verdict facts, and dirty worktree status. Decision/blocker: `closed`; missing proof support was implemented, exact row proof passed, and no product behavior gap remains for GM-004. Next action: update the source matrix row and breakdown ledger/progress only.
- 2026-05-10 14:25:38 CEST - Closure Writer completed. Files inspected or touched since last update: source matrix GM-004 row; breakdown GM-004 closure progress, row inventory, row-disposition rationale, session closure ledger, session ledger row, ordered session row, and prerequisite/current-status notes; this plan metadata/progress. Decision/blocker: GM-004 is documented as `Covered`/`covered/accepted` with the accepted device proof and direct gates; GM-005 and later rows remain unresolved. Next action: closure review for overclaiming, stale GM-004 current-state wording, and whitespace hygiene.
- 2026-05-10 14:27:23 CEST - Closure Reviewer completed. Files inspected since last update: final GM-004 source row, breakdown GM-004 ledger/progress rows, this plan closure metadata, accepted proof artifacts, stale current GM-004-open search, final-program-verdict search, and scoped whitespace checks. Decision/blocker: no overclaiming found; no final program verdict was written; GM-004 should reopen only on a real regression against online removal, rotated-key exclusion, A/B post-removal delivery, or removed-member send/decrypt denial. Next action: report closure verdict.

## real scope

Own exactly source row `GM-004`: an online current member C is removed, the group key is rotated for remaining members, A and B continue exchanging post-removal messages, and C cannot send an accepted post-removal message or persist/decrypt post-removal plaintext.

In scope:
- Add row-owned host regression proof for the exact remove-online plus rotate plus A/B post-removal send path.
- Extend the accepted multi-party device harness/criteria/test support with explicit `--scenario gm004` proof.
- Fix the smallest production or harness bug only if the new GM-004 proof shows C can send accepted post-removal messages, C receives/decrypts post-removal content, A/B delivery breaks, or key rotation reaches C.

Out of scope:
- Re-add, offline removal, duplicate removal, stale event ordering, media, announcement groups, large groups, and `--scenario all` operator expansion.
- Weakening GM-001/GM-002/GM-003 criteria or changing their accepted row artifacts.
- Treating a single `FLUTTER_DEVICE_ID` gate as GM-004 closure evidence.

## closure bar

GM-004 is good enough only after execution produces row-specific evidence:
- Host/app proof passes for a GM-004-named remove-online scenario.
- `test/integration/group_multi_party_device_criteria_test.dart` rejects missing/false GM-004 removal-proof fields and accepts only the exact expected A/B post-removal delivery plus C non-access tuple.
- Exact relay/device proof passes with `--scenario gm004` and the accepted relay env, producing an orchestrator verdict JSON with `scenario: gm004`, `ok: true`, and per-role verdicts for Alice, Bob, and Charlie.
- The verdict proves Bob receives Alice's post-removal message, Alice receives Bob's post-removal message, Charlie does not receive/decrypt either post-removal message, Charlie's post-removal send attempt is rejected or group-not-found before publish, and Alice/Bob hold the rotated epoch while Charlie does not.
- `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` pass, with any additional direct Go/Dart tests green for touched code.

Planning must not mark GM-004 covered. GM-004 may be marked `Covered` only in the later closure step after row-specific evidence updates both the source matrix and this breakdown.

## source of truth

Authoritative inputs:
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GM-004`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row `GM-004` and the accepted GM prerequisite/GM-001/GM-002/GM-003 closure notes.
- Current code and tests in the Flutter app and Go node modules.
- `Test-Flight-Improv/test-gate-definitions.md` for named gate definitions.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` for direct suite classification and manual device proof classification.

Conflict rule:
- Current code/tests beat stale prose.
- `test-gate-definitions.md` defines named gates.
- The matrix row text defines the row closure contract unless current code proves the row is stale; current evidence does not prove GM-004 stale.

## session classification

`implementation-ready`

Reason: the source row is evidence-gated, but exact planning found missing row-owned harness/criteria support and missing exact GM-004 host proof. This is repo-owned implementation work. Product code changes are conditional and should happen only if the new GM-004 regression/harness reveals a real behavior gap.

## exact problem statement

GM-004 is still open. Existing coverage proves adjacent pieces:
- Flutter fake-network membership tests show removed members stop receiving regular post-removal messages and remaining peers continue sending.
- Application tests show key rotation can exclude a removed/leaving member and first post-removal send can use the rotated epoch.
- Go tests show updated configs reject removed senders and missing/removed keys fail closed.

Missing: no exact row-owned proof currently combines online C, removal, key rotation, A/B post-removal send continuity, C send rejection, and C post-removal decrypt denial in the accepted multi-party Flutter-app relay harness. The accepted harness currently supports `gm001`, `gm002`, `gm003`, and `all` only; `all` still expands to GM-001/GM-002 only.

User-visible behavior that must improve or be proven: after an online member is removed, the remaining current members keep receiving valid messages, while the removed online member cannot send, cannot receive/decrypt new content, and does not hold the rotated key.

Behavior that must stay unchanged: GM-001/GM-002/GM-003 criteria and accepted validation, existing group create/add/offline-add behavior, current signed membership/key-transition verification, and existing app/Go fail-closed validation.

## files and repos to inspect next

Primary Flutter production files:
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/core/bridge/bridge_group_helpers.dart`

Primary harness and tests:
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

Go fallback only if the failure points below Flutter:
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_inbox.go`
- `go-relay-server/group_inbox_test.go`

Docs to update during execution only if files are added or gate classification changes:
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

Already covered, but not enough to close GM-004:
- `test/features/groups/application/member_removal_integration_test.dart` includes removal command flow, `rotated key is NOT distributed to removed member`, `first post-removal send uses the rotated epoch`, and voluntary-leave rotation/exclusion tests.
- `test/features/groups/integration/group_membership_smoke_test.dart` includes `admin removes member - removed member stops receiving messages`, `removed member cannot send after self-removal cleanup`, `post-removal messaging - admin can still send to remaining members`, and re-add/no removed-period visibility coverage.
- `test/features/groups/application/group_message_listener_test.dart` includes `member_removed` handling, unauthorized/stale event rejection, self-removal cleanup, and no resurrection by older role/member events.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` covers replayed `member_removed`, removed-peer cleanup, removed-sender cutoff behavior, and future/missing-key undecryptable placeholder behavior.
- `go-mknoon/node/pubsub_delivery_test.go::TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription` proves validator rejection of C after config removal on an active subscription.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_RejectsRemovedMemberAfterConfigUpdate` and related validator tests prove `non_member` rejection after removal.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGroupTopicValidator_RejectsRemovedSenderPreviousEpochDuringGrace` proves removed senders are rejected even with previous-epoch grace.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator` and `pubsub_decryption_failure_test.go` cover missing key fail-closed behavior.

Missing:
- A GM-004-named direct host regression that combines online removal, key rotation, A/B post-removal sends, C send rejection, and C no post-removal decrypt/persistence.
- A GM-004 criteria contract.
- A GM-004 multi-party Flutter-app relay/device artifact.

## regression/tests to add first

Add proof before product fixes:
- Add a focused GM-004 host regression in `test/features/groups/integration/group_membership_smoke_test.dart`, named exactly enough for direct execution, such as `GM-004 removes C while online, rotates key, A/B continue, and C loses access`.
- The host test should keep Alice, Bob, and Charlie online, remove Charlie, rotate the key for remaining members, have Alice and Bob send post-removal messages, and assert:
  - Alice/Bob both keep the group and current member list excludes Charlie.
  - Alice/Bob receive each other's post-removal messages.
  - Charlie's send returns `groupNotFound` or `unauthorized` and produces no accepted local or remote message.
  - Charlie has no plaintext/persisted post-removal messages from Alice/Bob.
  - The rotated epoch is present for Alice/Bob and not distributed to Charlie.
- Add GM-004 criteria tests in `test/integration/group_multi_party_device_criteria_test.dart` before or alongside harness code:
  - accepts complete GM-004 role verdicts,
  - rejects missing Charlie removal proof,
  - rejects Charlie receiving Alice/Bob post-removal messages,
  - rejects Alice/Bob missing post-removal messages,
  - rejects Charlie successful post-removal send,
  - rejects rotated epoch evidence on Charlie.

Only after a proof fails for product behavior should execution edit production code.

## step-by-step implementation plan

1. Confirm the exact current baseline by running the direct adjacent host tests that already exist:
   - `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
   - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`

2. Add the GM-004 host regression in `group_membership_smoke_test.dart`.
   - Reuse `GroupTestUser`/fake-network patterns.
   - Prefer existing helper behavior over adding new infrastructure.
   - Model the production flow as remove member, publish/observe membership removal, rotate key for remaining peers, then post-removal sends.
   - If `GroupTestUser.removeMember` lacks key rotation, call or mirror `rotateAndDistributeGroupKey` behavior with the existing test helpers; do not change production semantics just to make the fake helper convenient.

3. Run the new host regression.
   - If it passes, treat production behavior as likely present and continue to device harness proof.
   - If it fails because C sends accepted content, C receives/decrypts post-removal content, A/B delivery breaks, or rotated key reaches C, fix the smallest owner seam shown by the failure:
     - sender authorization/local group cleanup in `send_group_message_use_case.dart` or repository state,
     - removal broadcast/config convergence in `group_message_listener.dart` or `remove_group_member_use_case.dart`,
     - rotation distribution/key promotion in `rotate_and_distribute_group_key_use_case.dart`,
     - Go validator/key behavior in `go-mknoon/node/pubsub.go`,
     - durable recipient filtering in `send_group_message_use_case.dart`/`group_offline_replay_envelope.dart`/`go-mknoon/node/group_inbox.go`.

4. Extend `integration_test/scripts/group_multi_party_device_criteria.dart`.
   - Add `gm004` requirement with roles `alice`, `bob`, `charlie`.
   - Add expected post-removal messages:
     - `aliceAfterCharlieRemove` from Alice to Bob only.
     - `bobAfterCharlieRemove` from Bob to Alice only.
   - Add GM-004-specific proof validation. Required fields should prove Charlie was online/current before removal, Alice removed Charlie, Alice/Bob rotated to a post-removal epoch, Alice/Bob member lists exclude Charlie, Charlie lacks the rotated epoch, Charlie's send was rejected before accepted publish, and Charlie has no post-removal plaintext/persisted received rows.
   - Keep existing GM-001/GM-002/GM-003 expected messages and proof fields unchanged.

5. Extend `test/integration/group_multi_party_device_criteria_test.dart`.
   - Add positive and negative GM-004 criteria tests before relying on the real simulator run.
   - Include negative tests for any acceptance hole that would otherwise let a false GM-004 device proof pass.

6. Extend `integration_test/scripts/run_group_multi_party_device_real.dart`.
   - Accept `--scenario gm004`.
   - Map `gm004` to only `gm004`.
   - Update usage/help text.
   - Do not make `--scenario all` expansion a GM-004 closure requirement; adding GM-004 to `all` is optional operator convenience only.

7. Extend `integration_test/group_multi_party_device_real_harness.dart`.
   - Add `gm004` roles `alice`, `bob`, `charlie`.
   - Add scenario dispatch for Alice/Bob/Charlie.
   - Alice creates the A/B/C private group, waits for Bob and Charlie to import/join, and records pre-removal online/topic proof.
   - Alice removes Charlie and performs the row's key rotation for remaining members using the production remove/rotate flows or their existing app-layer helper equivalents.
   - Bob observes membership/key convergence, sends `bobAfterCharlieRemove`, and receives `aliceAfterCharlieRemove`.
   - Alice sends `aliceAfterCharlieRemove` and receives `bobAfterCharlieRemove`.
   - Charlie remains online long enough to process removal, attempts a post-removal send, records the rejected result, verifies no post-removal plaintext rows for Alice/Bob messages, and records lack of post-removal key access.
   - Write verdict fields that criteria can validate without relying on logs alone.

8. Run the GM-004 direct host and criteria tests.
   - Fix harness/criteria bugs until these pass without weakening assertions.
   - If failures expose product behavior gaps, return to step 3 and fix the narrow product seam first.

9. Run fresh device discovery and the exact GM-004 relay/device proof.
   - Record the provided proof profile in the execution notes:
     - `flutter devices --machine` shows Pixel 6 `21071FDF600CSC`, iPhone 17 Pro `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, iPhone 16e `1B098DFF-6294-407A-A209-BBF360893485`, plus macOS/chrome.
     - `xcrun simctl list devices available` shows the four iOS 26.1 simulator ids booted.
   - Use the accepted relay env:
     - `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
   - Run with Alice/Bob/Charlie on three distinct Flutter app targets:
     - `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm004 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`

10. Run the supporting gates, update only necessary docs, and stop.
    - Update `test-inventory.md` and `test-gate-definitions.md` only if adding new files or changing classification text is necessary.
    - Do not update the source matrix or breakdown row to `Covered` during implementation execution; that belongs to the later closure step after final evidence is available.

## risks and edge cases

- C may process the member-removal system message and delete local group state before the post-removal send attempt; accepted result is `groupNotFound` or `unauthorized`, not success.
- C may remain subscribed at the transport layer briefly; validators and app persistence must still prevent accepted/decrypted post-removal content.
- Key rotation is not part of `remove_group_member_use_case.dart` by design; production UI orchestrates remove, broadcast, then rotate. Tests and harness must model the full row flow without moving rotation into the low-level remove use case unless evidence proves the architecture is wrong.
- Recipient filtering must exclude C from durable inbox storage for post-removal messages.
- Stale local state on C must not allow a send that A/B accept.
- A/B delivery must not depend on C staying connected or on expected peer counts that include C.
- Device proof can be flaky because it uses real relay/simulators; reruns are acceptable only for environment failures, not assertion failures.

## exact tests and gates to run

Direct Flutter tests:
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-004 removes C while online, rotates key, A/B continue, and C loses access'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`

Conditional adjacent Flutter tests if the touched seam requires them:
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'member_removed'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'member_removed'`
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'rotated key is NOT distributed to removed member'`
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'first post-removal send uses the rotated epoch'`

Conditional Go tests if the failure points below Flutter:
- `cd go-mknoon && go test ./node -run 'TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription|TestGroupTopicValidator_RejectsRemovedMemberAfterConfigUpdate|TestGroupTopicValidator_RejectsRemovedSenderPreviousEpochDuringGrace|TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator' -count=1`
- `cd go-mknoon && go test -race ./node -run 'TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription|TestGroupTopicValidator_RejectsRemovedSenderPreviousEpochDuringGrace' -count=1`
- `cd go-mknoon && go test ./node -run 'GroupInbox|HistoryRepair' -count=1` only if durable recipient filtering changes.
- `cd go-relay-server && go test ./... -run 'GroupInbox|InboxDedup' -count=1` only if relay inbox behavior changes.

Device discovery and exact relay proof:
- `flutter devices --machine`
- `xcrun simctl list devices available`
- `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm004 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`

Named gates and hygiene:
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## known-failure interpretation

Do not classify these as GM-004 regressions unless execution touched their owner files or the failure output directly names GM-004 behavior:
- Existing broad-suite application failures already documented around unrelated media replay cases.
- Existing Go LP-006 zero-peer/sender-transport mismatch failures in broad `Group|PubSub|Rendezvous` selections.
- `--scenario all` omitting GM-003/GM-004 remains operator convenience unless this session deliberately changes it.
- Simulator startup, relay availability, or device boot issues may justify one clean rerun with the same command and evidence capture.

These are GM-004 failures, not known failures:
- C sends a post-removal message that A/B accept or persist.
- C receives, persists, or decrypts Alice/Bob post-removal plaintext.
- C receives or stores the rotated post-removal key.
- Alice/Bob fail to receive each other's post-removal messages.
- Criteria accepts a verdict missing one of those proof points.

## done criteria

- GM-004 host regression exists and passes.
- GM-004 criteria support exists and positive/negative criteria tests pass.
- `--scenario gm004` harness support exists and exact relay/device proof passes with a row-specific verdict JSON.
- Any product bug found by the new proof has the smallest focused fix and direct regression.
- Required direct tests, named gates, and diff hygiene pass.
- Execution notes identify the exact artifact path for GM-004 proof.
- No GM-001/GM-002/GM-003 criteria, proof expectations, or accepted closure records are weakened.
- GM-004 source matrix and breakdown are updated only by the closure pass that records the row-specific evidence.

## scope guard

Do not:
- Implement re-add, offline removal, duplicate removal, stale event ordering, media, large group, or announcement semantics in this session.
- Rewrite group membership architecture.
- Move key rotation into `remove_group_member_use_case.dart` unless the exact regression proves the current orchestration is unsound and reviewer/arbiter explicitly accepts that product-scope change.
- Treat host-only proof as enough for closure when the row requires 3-party E2E.
- Adjust tests to accept buggy behavior.
- Add broad logging-only proof instead of explicit verdict fields.
- Change accepted GM-001/GM-002/GM-003 proof contracts.

## accepted differences / intentionally out of scope

- `remove_group_member_use_case.dart` only removes and updates config; `group_info_wired.dart` orchestrates member removal broadcast and later `rotateAndDistributeGroupKey`. The plan accepts this layered architecture and models the full row flow at the orchestrating level.
- GM-004 uses Alice/Bob/Charlie only. A fourth simulator is available but not required for this row.
- Expanding `--scenario all` to include GM-004 is optional and not required for row closure.
- Durable offline replay boundary rows (`GM-005`, `GI-018`, `GK-022`, `GK-023`) remain separate even if GM-004 checks that C has no post-removal plaintext while online.
- Go/relay changes are conditional only; if Flutter/app-layer proof passes and device proof passes, do not broaden into Go or relay work.

## dependency impact

GM-004 will provide the first exact remove-online multi-party harness shape for later removal rows. Later rows likely to reuse the helpers and criteria patterns:
- `GM-005` remove C while offline.
- `GM-006` remove then immediately re-add with new epoch.
- `GM-007` removed-window history boundary.
- `GM-016` removed member remains unsubscribed.
- `GM-017` stale subscription cannot publish accepted messages.
- `GM-018` remaining members keep delivery after C removal.
- `GM-020` removed member excluded from immediate durable recipient list.
- `GE-002` and `GE-003` end-to-end remaining-member delivery after removal.
- `GK-022` and `GK-023` post-removal decrypt/backlog privacy rows.

If GM-004 exposes product bugs, later rows should wait for this row's fix and evidence before building on the removal harness. If GM-004 closes as tests/harness only, later rows can reuse the scenario helpers but must still produce their own row-specific evidence.

## reviewer findings

Reviewer verdict: sufficient as-is.

Missing files, tests, regressions, or gates: none structurally missing. The plan names the source matrix, breakdown, accepted harness files, owner app files, adjacent Flutter tests, conditional Go tests, device discovery, exact relay command, `groups`, `completeness-check`, and `git diff --check`.

Stale or incorrect assumptions: none found. The plan explicitly handles that the current harness supports only GM-001/GM-002/GM-003, that low-level removal does not itself rotate keys, and that GM-004 cannot close from host-only evidence.

Overengineering: none found. Go/relay work is conditional only if the GM-004 proof fails below Flutter.

Decomposition: sufficient. The plan adds host proof first, then criteria, then harness support, then exact relay proof, with stop points before product code.

Minimum needed to make the plan sufficient: no additional structural change.

## arbiter decisions

Structural blockers: none.

Incremental details intentionally deferred:
- Exact helper names for GM-004 harness internals can be chosen during execution after reading the surrounding helper style.
- Adding GM-004 to `--scenario all` remains optional operator convenience and is not part of row closure.

Accepted differences:
- The row remains evidence-gated for closure even though this plan is implementation-ready because missing GM-004 harness/criteria/host proof is repo-owned implementation work.
- Low-level removal and key rotation stay separate operations; the row proof should model the orchestrated production flow rather than forcing rotation into `remove_group_member_use_case.dart`.

Final arbiter verdict: no new structural blocker; stop after this pass. The plan is safe to implement now and must not mark GM-004 covered until a later closure pass records row-specific evidence in the source matrix and breakdown.
