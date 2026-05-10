# GM-005 Execution Plan - Remove C While Offline

Status: closed

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`

Pipeline artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`

Session: `GM-005`

Scenario: Remove C while C is offline.

Preconditions: C has old config/key and no live topic.

Steps: A removes C and sends N messages; C reconnects with stale state; C retrieves inbox and tries topic publish.

Expected: C converges to removed state and cannot access post-removal content; remaining members do not lose delivery.

Source row status: Covered.

Breakdown classification: `needs_repo_evidence`, `covered/accepted`; missing GM-005 proof support was implemented and exact row proof passed.

Closure verdict: `closed` for GM-005 only; GM-006 and later rows remain unresolved.

## Planning Progress

- 2026-05-10 14:58 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final mandatory plan sections. Decision/blocker: no structural blockers remain; plan is execution-ready for GM-005 only. Next action: hand off to implementation without updating source matrix/breakdown closure status.
- 2026-05-10 14:56 CEST - Arbiter started. Files inspected since last update: reviewer findings, closure bar, scope guard, tests/gates, accepted differences, and implementation stop rule. Decision/blocker: no provisional structural blocker. Next action: classify findings and finalize plan status.
- 2026-05-10 14:54 CEST - Reviewer completed. Files inspected since last update: full GM-005 draft, mandatory heading coverage, exact proof command, device discovery requirement, source/breakdown closure guard, and accepted GM-004 differences. Decision/blocker: sufficient as-is; no structural blocker. Next action: Arbiter classifies reviewer findings and finalizes execution readiness.
- 2026-05-10 14:50 CEST - Reviewer started. Files inspected since last update: GM-005 draft plan sections. Decision/blocker: no initial blocker; checking required section coverage, exact device discovery/relay command, tests-first rule, closure bar, known failure policy, and scope guard. Next action: run structural checks and record reviewer findings.
- 2026-05-10 14:49 CEST - Planner completed. Files inspected since last update: collected evidence and full draft plan sections. Decision/blocker: draft is `implementation-ready`; GM-005 needs row-owned host, criteria, runner, and harness proof before any product fix. Next action: Reviewer checks sufficiency, stale assumptions, exact tests/gates, and scope guard.

## Execution Progress

- 2026-05-10 14:41 CEST - Contract extracted. Files inspected since last update: GM-005 plan, GM-005 source matrix row, GM-005 breakdown row, dirty worktree, and Codex CLI availability. Decision/blocker: execution contract is concrete; nested Executor spawn will be attempted with `model: gpt-5.5` and `reasoning_effort: xhigh`. Next action: spawn Executor for GM-005-only implementation without changing matrix/breakdown closure status.
- 2026-05-10 14:42 CEST - Executor spawned/running. Files inspected or touched since last update: plan execution progress only. Command currently running: `codex exec -m gpt-5.5 -c reasoning_effort=\"xhigh\" ...` for GM-005 Executor. Decision/blocker: child materialized with `approval: never`, `sandbox: danger-full-access`, and `reasoning effort: xhigh`. Next action: bounded wait, then inspect assigned files and child summary.
- 2026-05-10 14:43 CEST - Executor local pass started. Files inspected since last update: execution-QA skill contract, GM-005 plan, GM-005 matrix row, GM-005 breakdown row, dirty worktree status, and accepted GM-004 host/criteria/runner/harness search hits. Decision/blocker: scope remains GM-005-only; source matrix/breakdown closure status will not be changed. Next action: inspect accepted GM-004 helper patterns before adding GM-005 host and criteria proof.
- 2026-05-10 14:45 CEST - Nested Executor fallback activated. Files inspected/touched since last update: plan execution progress and child output stream. Decision/blocker: nested Executor materialized but did not return a trustworthy implementation result inside the bounded wait and produced no code/test delta beyond this heartbeat section; it was terminated as `spawn_or_tool_failure`. Next action: continue with a local sequential Executor pass in this isolated worker without weakening GM-005 proof, then run local QA.
- 2026-05-10 14:47 CEST - Local Executor edits starting. Files inspected since last update: `GroupTestUser`, `FakeGroupPubSubNetwork`, GM-004 host test, GM-003/GM-004 harness flows, criteria evaluator/tests, runner scenario dispatch, and drain replay helper tests. Decision/blocker: no product gap proven yet; implementation will add GM-005 proof in existing host/criteria/runner/harness surfaces only. Next action: patch GM-005 host regression, criteria support/tests, and direct `--scenario gm005` harness flow.
- 2026-05-10 14:52 CEST - Status checkpoint after user interruption. Files touched since last update: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and this plan ledger. Decision/blocker: GM-005 criteria/runner/harness support is partial; required GM-005 host regression is still missing and no tests/device proof have run. Next action: finish host regression, complete harness dispatch, format, then run required direct tests and gates.
- 2026-05-10 14:59 CEST - Takeover execution contract re-extracted. Files inspected since last update: this plan, dirty worktree status, Codex CLI availability, and GM-005 search hits in criteria/runner/harness/tests. Decision/blocker: partial GM-005 criteria/runner/harness support exists but host regression is still missing; source matrix/breakdown closure status remains out of scope. Next action: spawn a fresh GM-005 Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-10 15:07 CEST - Controller local takeover completed missing direct proof. Files inspected or touched since last update: `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`. Commands completed: `dart format` on GM-005 harness/criteria/runner/test files; focused host proof `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-005 removes C while offline, C catches up removed, cannot access post-removal content, and A/B delivery continues'` passed; criteria proof `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed with 30 tests. Decision/blocker: GM-005 host/criteria proof is now present and green; no product behavior gap proven by these direct tests. Next action: run remaining direct app/host tests, then fresh device discovery and exact `--scenario gm005` relay/device proof.
- 2026-05-10 15:18 CEST - GM-005 direct tests and exact device proof passed. Files inspected or touched since last update: `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, device discovery output, and GM-005 proof artifacts. Commands completed: `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; full `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`; `dart analyze integration_test/group_multi_party_device_real_harness.dart`; fresh `flutter devices --machine`; `xcrun simctl list devices available`; exact `--scenario gm005` relay/device proof. Artifact paths: shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm005_J6Cj77`; orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm005_J6Cj77/gmp_1778419237387_gm005_orchestrator_verdict.json`; role verdicts `gmp_1778419237387_alice_verdict.json`, `gmp_1778419237387_bob_verdict.json`, and `gmp_1778419237387_charlie_verdict.json`. Decision/blocker: orchestrator verdict is `scenario: gm005`, `ok: true`, `detail: gm005 verdicts valid for alice, bob, charlie`; Bob received all three Alice post-removal messages exactly once at key epoch 2; Charlie had stale old config/key, reconnected, retrieved inbox, converged removed, held no rotated epoch, had zero post-removal plaintext, and send was `groupNotFound` with `accepted: false`. Accepted harness note: `flutter drive` relaunch resets the app container, so the Charlie proof restores stale group/key from the runner fixture before drain while the criteria still require stale-state, inbox retrieval, removal convergence, no post-removal plaintext/rotated key, and send rejection. Next action: run groups/completeness/diff gates.
- 2026-05-10 15:28 CEST - GM-005 execution gates passed. Files inspected since last update: groups gate output, completeness-check output, and diff-check result. Commands completed: `./scripts/run_test_gates.sh groups` passed with `00:08 +109: All tests passed!`; `./scripts/run_test_gates.sh completeness-check` passed with `731/731 test files classified`; `git diff --check` passed. Decision/blocker: no remaining GM-005 execution blocker; source matrix and breakdown can now be closed in the closure step. Next action: closure audit and row-only doc updates.

## Closure Audit Progress

- 2026-05-10 15:29:12 CEST - Completion Auditor completed. Files inspected since last update: accepted execution evidence in this plan, source matrix GM-005 row, breakdown GM-005 inventory/session/ordered rows, orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm005_J6Cj77/gmp_1778419237387_gm005_orchestrator_verdict.json`, Bob/Charlie role verdict facts, harness-only fixture restore note, direct tests, named gates, and dirty worktree status. Decision/blocker: `closed`; missing proof support was implemented, exact row proof passed, and no product behavior gap remains for GM-005. Next action: update the source matrix row and breakdown ledger/progress only.
- 2026-05-10 15:30:04 CEST - Closure Writer completed. Files inspected or touched since last update: source matrix GM-005 row; breakdown GM-005 closure progress, row inventory, row-disposition rationale, session closure ledger, session ledger row, ordered session row, and prerequisite/current-status notes; this plan metadata/progress. Decision/blocker: GM-005 is documented as `Covered`/`covered/accepted` with the accepted stale-offline removal device proof and direct gates; GM-006 and later rows remain unresolved. Next action: closure review for overclaiming, stale GM-005 current-state wording, and whitespace hygiene.
- 2026-05-10 15:30:41 CEST - Closure Reviewer completed. Files inspected since last update: final GM-005 source row, breakdown GM-005 ledger/progress rows, this plan closure metadata, accepted proof artifacts, final-program-verdict search, and scoped whitespace checks. Decision/blocker: no overclaiming found; no final program verdict was written; GM-005 should reopen only on a real regression against stale offline removal, removed-member non-access, removed-member send rejection, or remaining-member delivery continuity. Next action: report closure verdict and continue to GM-006.

## real scope

Own exactly source row `GM-005`: remove Charlie while Charlie is offline with stale group config/key and no live topic, send post-removal messages from Alice to Bob, relaunch Charlie from stale persisted state, drain Charlie's group inbox, and prove Charlie converges to removed state, cannot publish as a removed member, cannot decrypt or access post-removal content, while Alice/Bob delivery remains intact.

In scope:
- Add row-owned GM-005 host/app proof for stale offline removal, inbox replay, removed-member send denial, and A/B post-removal delivery.
- Extend only the accepted GM multi-party harness files already used by GM-001 through GM-004:
  - `integration_test/scripts/run_group_multi_party_device_real.dart`
  - `integration_test/group_multi_party_device_real_harness.dart`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
- Fix the smallest production or harness seam only if the new GM-005 proof shows Charlie can access post-removal plaintext, keeps a usable rotated key, publishes an accepted removed-member message, or Alice/Bob lose delivery.

Out of scope:
- Re-add flows, duplicate remove, stale add/remove ordering, large groups, media, announcements, push notification UX, and broad key-epoch redesign.
- Changing GM-001, GM-002, GM-003, or GM-004 accepted criteria or closure facts.
- Updating the source matrix or breakdown to mark GM-005 `Covered`; that belongs to a later closure step after evidence exists.
- Committing changes.

## closure bar

GM-005 is good enough only after implementation produces row-specific evidence that all of the following are true:
- Charlie had persisted old group config and key before going offline.
- Charlie had no live topic/process during Alice's remove and post-removal sends.
- Alice removed Charlie and rotated/distributed the post-removal key only to remaining members.
- Alice sends at least three post-removal messages after Charlie is offline and removed; Bob receives every one exactly once with the expected sender/message/key tuple.
- Charlie reconnects from stale persisted state, runs group inbox retrieval after those sends, processes the removal boundary, and converges to removed state.
- Charlie does not persist/display/decrypt any Alice post-removal plaintext after reconnect and does not hold the rotated epoch/key.
- Charlie's post-removal publish attempt is rejected before accepted publish, with outcome such as `groupNotFound` or `unauthorized`.
- Exact relay/device proof passes with `--scenario gm005` and writes an orchestrator verdict JSON where `scenario: gm005`, `ok: true`, and per-role verdicts validate Alice, Bob, and Charlie.
- Direct tests, named gates, and whitespace checks pass as listed in this plan.

Do not weaken the expected result to "no crash" or "best effort"; Charlie's non-access and Alice/Bob delivery continuity are required closure facts.

## source of truth

Authoritative inputs:
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GM-005`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row `GM-005`.
- Accepted GM-004 closure in the source matrix, breakdown, and `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-004-plan.md`.
- Current code and tests in the Flutter app, Go node, and accepted GM harness files.
- `Test-Flight-Improv/test-gate-definitions.md` for named gate behavior.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` only if test classification must be updated.

Conflict rule:
- Current code/tests beat stale prose.
- The GM-005 matrix row defines the row contract unless exact repo proof shows the row is already covered; current evidence does not.
- `test-gate-definitions.md` defines named gates.
- The accepted relay env in this plan is mandatory for device proof.

## session classification

`implementation-ready`

Rationale at planning time: the breakdown classified GM-005 as `needs_repo_evidence` / `evidence-gated`, but exact planning found missing row-owned host proof, criteria support, runner support, and real-device harness support. Those missing tests, harness scenarios, criteria, and test hooks were repo-owned implementation work. Product changes were conditional and would happen only if the new proof exposed a real GM-005 behavior gap.

## exact problem statement

At planning time, GM-005 remained `Open`. GM-004 closed online removal, but GM-005 was a different reliability and privacy boundary: Charlie is offline with stale state and no live topic when removed, then later reconnects and drains inbox. The repo needed exact proof that a stale offline removed member cannot regain access to post-removal content or publish after reconnect, and that remaining members do not lose delivery while the removed peer is offline/stale.

What must improve or be proven:
- Charlie's stale old config/key cannot decrypt or access messages sent after the removal boundary.
- Charlie converges to removed state during reconnect/inbox replay.
- Charlie cannot publish as a removed member after reconnect.
- Alice/Bob delivery remains intact for multiple post-removal messages.

What must stay unchanged:
- Accepted GM-001 through GM-004 proof semantics.
- Existing group create/add/offline-add/online-remove behavior.
- Existing signed system-message validation, key-rotation verification, and fail-closed send validation.

## files and repos to inspect next

Production/app seams:
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/core/bridge/bridge_group_helpers.dart`

Harness/tests:
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`

Go fallback only if the failing proof points below Flutter/app replay or pubsub validation:
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`

Docs to inspect/update only if classification changes are needed:
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

Already useful but not enough to close GM-005:
- `test/features/groups/application/member_removal_integration_test.dart` covers key rotation after removal, exclusion of removed members from rotated-key distribution, first post-removal send using rotated epoch, and inbox-store recipient/key assertions.
- `test/features/groups/integration/group_membership_smoke_test.dart` covers online removal, remaining-member delivery, removed-member send denial after self-removal cleanup, re-add boundaries, notifications while removed, and dissolved/offline replay cleanup.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` covers replayed self-removal cutting off later queued inbox traffic, replayed `member_removed` cleanup, and future media replay with old epoch remaining inaccessible.
- `integration_test/group_multi_party_device_real_harness.dart` plus criteria/runner currently support `gm001`, `gm002`, `gm003`, and `gm004`.
- Go validator/key tests cover removed-sender rejection and fail-closed missing/stale key behavior.

Missing:
- A GM-005-named host/app regression combining stale offline Charlie, removal, post-removal Alice messages, Charlie inbox replay, Charlie non-access, Charlie send rejection, and A/B delivery continuity.
- GM-005 criteria that reject incomplete or false role verdicts.
- `--scenario gm005` runner/harness support with Charlie seeded, taken offline, and relaunched.
- Exact relay/device proof for GM-005.

## regression/tests to add first

Add tests before product fixes:
- Add a focused host regression in `test/features/groups/integration/group_membership_smoke_test.dart`, named:
  - `GM-005 removes C while offline, C catches up removed, cannot access post-removal content, and A/B delivery continues`
- Add or extend a focused replay regression in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` only if the host test needs lower-level proof of a replay cutoff:
  - Charlie starts with old config/key.
  - Inbox page includes the `member_removed` replay event followed by post-removal traffic, or the replay request occurs after post-removal traffic was sent.
  - The drain applies self-removal, stops/ignores post-removal content for Charlie, and no plaintext is persisted.
- Extend `test/integration/group_multi_party_device_criteria_test.dart` for GM-005 before relying on the device run:
  - accepts complete GM-005 Alice/Bob/Charlie verdicts;
  - rejects missing Charlie stale-offline proof;
  - rejects Charlie retaining rotated epoch/key;
  - rejects Charlie receiving or persisting any Alice post-removal plaintext;
  - rejects Charlie accepted post-removal publish;
  - rejects Bob missing any Alice post-removal message;
  - rejects incomplete inbox-retrieval/reconnect proof.

Product code changes should begin only after one of these tests fails for product behavior rather than missing proof support.

## step-by-step implementation plan

1. Reconfirm current dirty worktree and do not revert unrelated changes.
   - Use `git status --short`.
   - Do not stage/commit.
   - Do not edit source matrix or breakdown closure status during implementation.

2. Inspect the exact files listed in this plan.
   - Start with the host test helpers and accepted GM-004 harness support.
   - Inspect production seams only when writing the host regression or when a failing proof points to a behavior gap.

3. Add the GM-005 host regression first.
   - Create Alice/Bob/Charlie with Charlie holding old group config/key.
   - Start Alice/Bob only for the removal/send phase; Charlie must have no live topic/listener during removal.
   - Alice removes Charlie, rotates key for remaining members, and sends at least three post-removal messages.
   - Assert Bob receives all Alice post-removal messages exactly once and Bob's member list/key converge without Charlie.
   - Relaunch/start Charlie from stale local state, drain group inbox, and assert Charlie converges to removed state, has no rotated key, persists no post-removal plaintext, and cannot send/publish.
   - If this host test passes without product changes, continue to criteria/harness. If it fails for product behavior, fix the smallest seam shown by the failure.

4. Add GM-005 criteria support in `integration_test/scripts/group_multi_party_device_criteria.dart`.
   - Add `_gm005Requirement` with roles `alice`, `bob`, `charlie`.
   - Update supported-scenario error text to include `gm005`.
   - Add expected post-removal messages, for example:
     - `aliceAfterCharlieOfflineRemove1`
     - `aliceAfterCharlieOfflineRemove2`
     - `aliceAfterCharlieOfflineRemove3`
   - All three expected messages must be sent by Alice and received by Bob only.
   - Add `_validateGm005OfflineRemovalProof` requiring:
     - Alice proof: `charlieOfflineBeforeRemoval`, `removedCharlie`, `removedPeerId`, `memberListExcludesCharlie`, `rotatedEpoch >= 2`, and `postRemovalMessageCount >= 3`.
     - Bob proof: `memberListExcludesCharlie`, `hasRotatedEpoch`, same `rotatedEpoch`, and `receivedAllAlicePostRemovalMessages`.
     - Charlie proof: `hadOldConfigBeforeOffline`, `hadOldKeyBeforeOffline`, `offlineDuringRemoval`, `reconnectedWithStaleState`, `retrievedInboxAfterReconnect`, `convergedRemoved`, `groupPresentAfterCatchUp == false`, `hasRotatedEpoch == false`, `postRemovalPlaintextCount == 0`, `postRemovalPublishAccepted == false`, and `postRemovalSendOutcome` is `groupNotFound` or `unauthorized`.

5. Add GM-005 criteria tests in `test/integration/group_multi_party_device_criteria_test.dart`.
   - Positive fixture with complete Alice/Bob/Charlie proof.
   - Negative fixtures for every privacy/delivery hole that could otherwise pass:
     - missing Charlie proof,
     - Charlie accepted send,
     - Charlie received one post-removal message,
     - Charlie has rotated epoch,
     - Bob missing one of Alice's N messages,
     - missing inbox-retrieval/reconnect proof.

6. Extend `integration_test/scripts/run_group_multi_party_device_real.dart`.
   - Accept `--scenario gm005`.
   - Map `gm005` to only `gm005`.
   - Keep `--scenario all` unchanged unless execution chooses optional operator convenience; GM-005 closure must use direct `--scenario gm005`.
   - Add a GM-005 special runner flow analogous to GM-003:
     - launch Charlie first or alongside Alice/Bob long enough to seed persisted old group config/key;
     - stop/terminate Charlie before Alice removes Charlie and sends post-removal messages;
     - relaunch Charlie with the same run id/database profile and restore mnemonic after Alice/Bob finish the post-removal send phase.

7. Extend `integration_test/group_multi_party_device_real_harness.dart`.
   - Add `gm005` roles `alice`, `bob`, `charlie`.
   - Add a Charlie seed/offline mode or scenario branch that imports the A/B/C group, persists old config/key, proves old state exists, writes `charlie_old_state_persisted`, and exits before removal.
   - Alice flow:
     - create A/B/C group and wait for Bob joined plus Charlie old-state persisted;
     - wait for runner signal that Charlie process is offline;
     - remove Charlie and rotate/distribute key to remaining members only;
     - send at least three post-removal proof messages;
     - record removal proof and rotated epoch.
   - Bob flow:
     - import/join group;
     - observe member exclusion and rotated key;
     - receive all Alice post-removal messages exactly once;
     - record remaining-member delivery proof.
   - Charlie reconnect flow:
     - launch after Alice's post-removal sends using the stale persisted state;
     - drain group inbox;
     - prove inbox retrieval ran after removal/sends;
     - prove no post-removal plaintext is present;
     - prove no rotated key is held;
     - attempt post-removal publish and record rejected outcome.

8. Run direct tests and fix only GM-005-owned failures.
   - If criteria/host failures are assertion-shape or harness sequencing bugs, fix criteria/harness/tests.
   - If they show Charlie accesses content, publishes successfully, or Alice/Bob delivery breaks, fix the narrow production seam:
     - self-removal replay cleanup in `group_message_listener.dart` or `drain_group_offline_inbox_use_case.dart`;
     - sender authorization/group state cleanup in `send_group_message_use_case.dart`;
     - removal/config propagation in `remove_group_member_use_case.dart` or `group_config_payload.dart`;
     - key rotation/distribution in `rotate_and_distribute_group_key_use_case.dart` or `group_key_update_listener.dart`;
     - Go pubsub/inbox behavior only if the failing evidence points below Flutter.

9. Run fresh device discovery before exact device proof:
   - `flutter devices --machine`
   - `xcrun simctl list devices available`
   - Use three distinct Flutter app targets for Alice/Bob/Charlie. The GM-004 accepted IDs were Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; refresh discovery must confirm availability before reuse.

10. Run exact GM-005 relay/device proof with the accepted relay env:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm005 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

11. Run named gates, update only necessary docs, and stop.
   - Do not mark GM-005 covered in the source matrix or breakdown during implementation.
   - Leave closure to a later audit/closure pass.

## risks and edge cases

- Charlie's app must truly be stopped before removal; a live Charlie listener would collapse GM-005 back into GM-004.
- Charlie must retain old config/key across relaunch without receiving the rotated key.
- Inbox replay may deliver `member_removed` before or instead of post-removal messages; either way, Charlie must not access post-removal plaintext after retrieval.
- If post-removal messages are correctly not addressed to Charlie, the proof still must show Charlie retrieved inbox after reconnect and has no plaintext/rotated key.
- Duplicate post-removal replay entries must not create duplicate Bob deliveries.
- A/B must not wait on Charlie's stale topic/relay state before sending.
- The device harness must distinguish "Charlie never launched" from "Charlie launched with stale state, retrieved inbox, and converged removed."
- Existing dirty files may affect broad gates; isolate failures before attributing them to GM-005.

## exact tests and gates to run

Direct tests after adding GM-005 support:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-005 removes C while offline, C catches up removed, cannot access post-removal content, and A/B delivery continues'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
```

Fresh device discovery required before exact proof:

```bash
flutter devices --machine
xcrun simctl list devices available
```

Exact device proof:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm005 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
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
- The worktree already contains many modified and untracked files across docs, Go node tests, group app code, and accepted GM harness files. Treat those as pre-existing unless GM-005 implementation edits them.
- GM-004 is covered; reopening GM-004 is out of scope unless a real regression appears in its accepted direct proof.
- `--scenario all` currently expands to GM-001/GM-002 only; that is an accepted operator-convenience difference and not a GM-005 blocker.
- No baseline failures were executed during this planning pass. If `groups` or another broad gate fails, isolate with focused tests and classify the failure as GM-005-caused only when the failing assertion crosses GM-005-touched code or scenario data.

Do not hide a GM-005 regression behind "known failure" if Charlie accesses post-removal plaintext, publishes successfully after removal, retains the rotated key, or Bob misses Alice's post-removal messages.

## done criteria

- GM-005 plan remains scoped to row GM-005 and says `Status: execution-ready`.
- GM-005 host regression exists and passes.
- GM-005 criteria tests exist and pass, including negative privacy/delivery cases.
- `--scenario gm005` runner/harness support exists and reuses the accepted GM multi-party device harness surface.
- Fresh device discovery was run immediately before the exact proof.
- Exact relay/device proof passes with the accepted relay env and writes an `ok: true` GM-005 orchestrator verdict plus Alice/Bob/Charlie role verdicts.
- Direct tests and named gates listed above pass, or any failure is isolated and documented as unrelated/pre-existing with evidence.
- Source matrix and breakdown are not marked `Covered` during implementation.
- No unrelated dirty files are reverted or overwritten.

## scope guard

Do not:
- Convert GM-005 into a general membership-history rewrite.
- Change product expectations so Charlie is allowed to see post-removal content.
- Treat absence of a live Charlie process as sufficient without later reconnect, inbox retrieval, and stale-state proof.
- Treat GM-004 online removal proof as GM-005 proof.
- Add a second orchestration system; extend the accepted GM harness files only.
- Expand `--scenario all` as a required closure condition.
- Modify closure docs to mark GM-005 covered during implementation.
- Revert or clean unrelated dirty/untracked files.

Overengineering signs:
- New generic membership simulator framework.
- New persistence abstraction just for the test.
- Broad Go pubsub rewrites before a GM-005 failing proof points there.
- Adding media/re-add/notification assertions to GM-005.

## accepted differences / intentionally out of scope

- GM-005 remains separate from GM-004 because Charlie is offline with stale persisted state and no live topic during removal, then reconnects and retrieves inbox. GM-004's online removal proof is strong precedent but not closure evidence for GM-005.
- `--scenario all` not including GM-005 is acceptable for this session; direct `--scenario gm005` is the required row proof.
- Host fake-network proof and exact device proof are both required. Host proof is not a substitute for the relay/device artifact.
- If implementation evidence passes with harness/test changes only, product code should remain unchanged.

## dependency impact

Later removal/re-add and history-boundary rows depend on GM-005's proof shape:
- GM-006 and GM-007 should reuse the stale-offline reconnect/inbox proof pattern for remove/re-add windows.
- GM-017 and GM-018 depend on removed-member publish denial and remaining-member delivery continuity.
- GM-020 depends on recipient exclusion for post-removal messages.

If GM-005 exposes a product gap, pause later GM removal/re-add rows until the narrow GM-005 fix and proof are accepted. If GM-005 closes with tests/harness only, later rows can proceed using the GM-005 scenario as the accepted offline-removal precedent.

## Reviewer Findings

Verdict: sufficient as-is.

- Missing files, tests, regressions, or gates: none structural. The plan names the GM harness files, row-owned host/criteria tests, direct tests, named gates, fresh device discovery, and exact relay proof.
- Stale or incorrect assumptions: none found. The plan treats GM-004 as precedent only and keeps GM-005 separate because Charlie is offline/stale and reconnects through inbox replay.
- Overengineering: none required. The plan extends the accepted harness rather than adding a separate orchestration surface.
- Decomposition: sufficient. Product changes are conditional on failing GM-005 proof and are limited to the owning seam shown by evidence.
- Minimum needed to implement safely: execute the plan in order, starting with host/criteria proof and preserving the source matrix/breakdown as open until a later closure step.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: optional `--scenario all` expansion remains deferred; optional narrower lower-level replay test naming can be adjusted during implementation if the host regression already proves the seam.
- Accepted differences: GM-004 proves online removal only; GM-005 still requires stale-offline reconnect/inbox proof. Host proof does not replace exact relay/device proof. Product code changes remain conditional.
- Stop rule: no structural blocker was found, so no fix loop is needed. This plan is execution-ready for GM-005 only.

## QA checklist

- Verify plan and implementation touch only GM-005-owned files or explicitly justified shared harness/docs.
- Confirm `scenarioRequirement`, device selection, runner usage text, and verdict evaluation all include `gm005`.
- Confirm criteria tests reject false positives for Charlie plaintext access, retained rotated key, accepted publish, and missing Bob delivery.
- Confirm Charlie is actually offline/no live topic during removal, not merely idle.
- Confirm Charlie relaunches with stale persisted group/key and runs inbox retrieval after post-removal sends.
- Confirm exact device proof used the required relay env and fresh device discovery.
- Confirm source matrix and breakdown still leave GM-005 open until a separate closure step.
- Confirm no unrelated dirty files were reverted, formatted, staged, or committed.
