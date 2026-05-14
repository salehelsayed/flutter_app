Status: accepted/closed

# GM-035 Plan - Re-added Member Sends First Message Before Discovery Completes

## Planning Progress

- 2026-05-12 00:13 CEST - Evidence Collector started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-035, `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` GM-035 entries, current GM-033 external fixture update. Decision/blocker: source row GM-035 is `Open`/P0 and the intended plan path is confirmed; device proof is currently fixture-contention-sensitive, but host/harness planning is safe. Next action: inspect GM-035 owner files, adjacent GM-021..GM-034 harness patterns, and current tests before drafting an execution-safe row-owned plan.
- 2026-05-12 00:18 CEST - Evidence Collector completed; Planner started. Files inspected since last update: `send_group_message_use_case.dart`, `send_group_message_use_case_test.dart`, `group_resume_recovery_test.dart`, `handle_incoming_group_message_use_case_test.dart`, `group_test_user.dart`, `fake_group_pubsub_network.dart`, `pubsub.go`, `pubsub_test.go`, GM-033/GM-034 criteria/runner/harness sections, `test-gate-definitions.md`, `scripts/run_test_gates.sh`, live devices/processes. Decision/blocker: no `gm035` row-owned host, criteria, runner, harness, or exact device scenario exists; the current three-device proof tuple is occupied by a non-GM-035 `private_readd_cycles` run. Next action: draft implementation-ready scope with regression-first host proof plus required final 3-party proof.
- 2026-05-12 00:20 CEST - Planner completed; Reviewer started. Files inspected since last update: draft plan content and row contract. Decision/blocker: GM-035 is not evidence-only because exact row support is missing and the user explicitly requires implementation-committed gap closure. Next action: review closure bar, test contract, scope guard, and fixture-blocker handling.
- 2026-05-12 00:21 CEST - Reviewer completed; Arbiter started. Files inspected since last update: draft mandatory sections, GM-035 row contract, breakdown GM-035 row, device process evidence. Decision/blocker: sufficient with one tightening adjustment: require A and B to prove initial zero live fanout from Charlie's first send, durable recipient inclusion, drain/catch-up, and exact-once persistence separately from any later live PubSub convergence. Next action: arbitrate whether any structural blocker remains.
- 2026-05-12 00:22 CEST - Arbiter completed. Files inspected since last update: final plan artifact. Decision/blocker: no structural blockers remain; current device contention is an execution-time proof scheduler blocker only, not a planning blocker. Next action: hand off to implementation; do not edit source matrix, breakdown, code, or tests in this planning turn.

## Execution Progress

- 2026-05-12 00:22 CEST - Contract extracted. Files inspected/touched: `implementation-execution-qa-orchestrator/SKILL.md`, this GM-035 plan, `git status --short`. Scope: own only GM-035, proving re-added Charlie's first post-readd send when live discovery has not completed and initial `topicPeers == 0`. Acceptance bar: host proof plus `gm035` criteria/runner/harness support, and either trusted three-device `gm035` verdict or explicit external fixture blocker. Source of truth: source matrix row GM-035, session breakdown GM-035 owner hints, `scripts/run_test_gates.sh`, and current code. Required RED/tests: exact GM-035 host regression first; criteria selector; adjacent zero-peer/dedupe selectors as practical; touched-file format/analyze; groups/completeness gates as practical. Scope guard: no source matrix/breakdown closure edits, no unrelated cleanup, production edits only if the GM-035 RED proves a repo-owned gap. Decision/blocker: execution can proceed; dirty scoped files require diff inspection before edits. Next action: inspect scoped owner files and adjacent GM-033/GM-034 patterns.
- 2026-05-12 00:27 CEST - Executor host proof added and run. Files inspected/touched: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `send_group_message_use_case.dart`, `drain_group_offline_inbox_use_case.dart`, `handle_incoming_group_message_use_case.dart`. Command/result: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-035'` failed twice for test-harness timestamp setup, then passed after assigning Charlie's first-send timestamp after Bob's re-add event was installed. Decision/blocker: no production gap proven; product code untouched. Next action: add `gm035` criteria, runner parsing, and harness role support.
- 2026-05-12 00:38 CEST - Controller stopped contaminated device proof. Files inspected/touched: this plan, live process list, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm035_bUgCtP`. Executor handoff reports focused GM-035 host selector, criteria selector, touched-file format/analyze, zero-topic send selector, dedupe selector, and `git diff --check` passed after adding host/criteria/runner/harness support. Device command was started: `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm035 -d 560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245`, but no trusted verdict exists; shared dir contains Alice/Bob identity/log artifacts only. Live process check showed GM-035 runner PID `48579` plus Bob/Charlie children, and a separate non-GM-035 `private_readd_cycles` runner PID `50999` with `flutter drive` PID `51207` using the same simulator tuple. Action: stopped only GM-035-owned processes with `kill 48579 50499 52105` and `pkill -TERM -f 'GROUP_MULTI_PARTY_SCENARIO=gm035'`; verified no GM-035 runner/child remained. Decision/blocker: final device proof is blocked/external_fixture by same-device process contention and prior Alice driver-service disappearance; no GM-035 source row acceptance yet. Next action: finish QA review of code/support, then either run a clean focused proof pass when the tuple is free or record GM-035 as blocked/not accepted.
- 2026-05-12 00:43 CEST - QA completed, alternate proof path selected. Files inspected/touched: this plan, GM-035 code/support diffs, live process/device evidence. QA result: `qa_blocked_external_fixture`; focused QA reruns passed `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-035'`, `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-035'`, and `git diff --check`. QA found no repo-owned blocker in GM-035 host/criteria/runner/harness support. Current blocker: no trusted three-device proof; the iOS 26.2 tuple is occupied by non-GM-035 `private_readd_cycles`. Decision/blocker: try focused GM-035 proof on the alternate iOS 26.1 tuple before leaving the row blocked. Next action: preflight `38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` and run the exact `--scenario gm035` proof if uncontended.
- 2026-05-12 00:49 CEST - Focused 26.1 device proof failed at row-owned harness contract. Files inspected/touched: this plan, GM-035 shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm035_Z3Ueps`, orchestrator verdict, role verdicts, live process list, harness/criteria sections. Command: `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm035 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Result: exited `255`; all role app tests passed and wrote verdicts, but orchestrator verdict is `ok:false` because Charlie's first post-readd send reported `outcome:"success"`, `topicPeers:2`, `initialTopicPeers:2`, `sentBeforeLiveDiscoveryCompleted:false`, and `successNoPeers:false`. Evidence: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm035_Z3Ueps/gmp_1778539435216_gm035_orchestrator_verdict.json`. Decision/blocker: implementation-owned harness/scenario gap, not external; the harness currently lets live discovery complete before Charlie's first send. Recovery Input: force Alice/Bob off the live group topic or stop their P2P nodes before Charlie's first post-readd send, keep them eligible durable recipients, then restart/drain/catch up and prove exact-once after later live duplicate. Next action: same-session recovery plan/execution for `integration_test/group_multi_party_device_real_harness.dart` and any required GM-035 criteria/test adjustments.
- 2026-05-12 00:57 CEST - Fix-pass Executor patched GM-035 harness choreography. Files inspected/touched: `integration_test/group_multi_party_device_real_harness.dart`, this plan. Decision/blocker: added GM-035-only live-topic leave/rejoin helpers; Alice and Bob now leave only the Go live topic after re-add while retaining group/key/member rows, signal live-topic unavailability before Charlie's first send, rejoin from local config, drain, and prove exact-once persistence after Charlie's optional live duplicate. Charlie now waits for both unavailability signals and fails immediately unless the first post-readd send records `successNoPeers` with `initialTopicPeers == 0`. Next action: format and run required GM-035 criteria/hygiene/device proof checks.
- 2026-05-12 01:08 CEST - Fix-pass validation completed. Files inspected/touched: `integration_test/group_multi_party_device_real_harness.dart`, this plan, GM-035 proof artifacts under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm035_ISnTSP`. Commands/results: `dart format --set-exit-if-changed integration_test/group_multi_party_device_real_harness.dart` passed with `0 changed`; `flutter analyze integration_test/group_multi_party_device_real_harness.dart` passed; `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-035'` passed; `git diff --check` passed; exact iOS 26.1 proof command passed after rerun via `tmux` to avoid the tool's long-run session cutoff. Device proof result: orchestrator `ok:true`, detail `gm035 verdicts valid for alice, bob, charlie`; Charlie first send `outcome:"successNoPeers"`, `topicPeers:0`, `initialTopicPeers:0`, durable recipients Alice+Bob only, Alice/Bob live-topic-unavailable proofs retained group/key/member state, and Alice/Bob `postLiveDuplicatePersistedCount == 1`. Decision/blocker: no GM-035 fix-pass blocker remains; ready for QA/closure review. Next action: hand off to QA Reviewer.

## real scope

Own exactly source row GM-035: Charlie is removed, re-added with current key/config state, and sends his first message immediately before Alice and Bob finish live PubSub discovery/mesh formation. Alice and Bob must eventually see Charlie's message once, even when Charlie's initial live topic peer count is zero.

Allowed execution changes:

- Add an exact GM-035 host regression that forces Charlie's first post-readd send through `topicPeers == 0`, verifies durable group inbox storage includes Alice and Bob, drains Alice/Bob from durable replay, and asserts exact-once persistence even if a later live delivery of the same message arrives.
- Add `gm035` support to the existing multi-party device proof stack: criteria, criteria tests, runner scenario parsing, and Alice/Bob/Charlie harness role paths.
- Patch production only if the new regression proves a product gap. Likely seams are send-side durable fallback/replay payloads, receiver drain/dedupe, or Go publish/topic-peer reporting. Do not patch broad discovery or relay architecture without a failing GM-035 proof.

Not in scope: GM-032, GM-033, GM-034, GM-036, generic discovery retries, relay-server storage redesign, notification routing, UI copy, source matrix closure edits, breakdown closure edits, or downgrading this row to docs-only/evidence-only.

## closure bar

GM-035 is good enough only when row-owned evidence proves all of these:

- Charlie's first post-readd send is accepted with the current member/device/key-package state.
- That first send observes `topicPeers == 0` or an equivalent recorded zero live-fanout proof before Alice/Bob finish discovery.
- Charlie's durable `group:inboxStore` payload includes Alice and Bob exactly once and carries an actual replay envelope for the same message ID.
- Alice and Bob eventually install Charlie's message once via durable inbox drain/catch-up, with no duplicate after any later live PubSub delivery of the same message ID.
- The proof distinguishes "no live mesh yet" from "recipient not eligible"; Alice/Bob are current eligible recipients at send time.
- The exact three-party device proof either passes with a trusted `gm035` verdict JSON, or the row remains open with a concrete external fixture/process contention blocker.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-035.
- Session ordering and owner hints: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` GM-035 row.
- User instruction for this planning turn overrides the breakdown's provisional `evidence-gated` wording: if exact row-owned code/tests/harness are missing, this is implementation-committed gap closure.
- Gate source of truth: `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md` explains intent, but the script wins on conflict.
- Current code and tests win over stale prose.

## session classification

`implementation-ready`

Reason: the source row is `Open`/P0, `rg "gm035|GM-035"` found no row-owned test/criteria/runner/harness support, and the exact row behavior is not yet proven. Existing zero-peer send and replay/dedupe tests are useful adjacent evidence, but they do not prove re-added Charlie's first send before discovery completes across Alice/Bob.

## exact problem statement

When Charlie is re-added, he can have the latest group key/config before the direct PubSub mesh has discovered Alice and Bob. His first send can therefore publish with zero live topic peers. User-visible failure would be Alice and/or Bob never seeing Charlie's first post-readd message, seeing it twice after durable replay plus later live delivery, or treating the zero-peer state as a failed send even though durable inbox accepted custody.

Must stay unchanged: removed-window exclusion, fresh re-add key/package validation, duplicate member normalization, current-member discovery filters, send authorization, receiver message-ID dedupe, and existing success semantics for normal `topicPeers > 0` sends.

## evidence collected

Evidence Collector role notes:

- Source row GM-035 says: "Re-added member sends first message before others finish discovery"; expected: "A/B eventually see C's message once, even if live topic peer count is initially zero."
- Breakdown GM-035 row currently says `needs_repo_evidence` / `evidence-gated`, with owner hints around group membership use cases, `pubsub.go`, `group_inbox.go`, membership smoke tests, onboarding, and real crypto onboarding. Exact planning found missing GM-035 row-owned support, so the row moves to implementation-ready under the user contract.
- `lib/features/groups/application/send_group_message_use_case.dart` starts `group:publish` and `group:inboxStore` concurrently. For `topicPeers == 0`, it waits for the inbox store and returns `SendGroupMessageResult.successNoPeers` while persisting the message as `sent` if durable store succeeds.
- `test/features/groups/application/send_group_message_use_case_test.dart` already proves zero topic peers plus durable store returns `successNoPeers`; it does not prove Alice/Bob later drain and dedupe Charlie's first re-add send.
- `go-mknoon/node/pubsub.go` reports `topicPeers` from `ensureGroupTopicPeersBeforePublish` and does not fail publish solely for peer count. `go-mknoon/node/pubsub_test.go` has adjacent zero-peer diagnostic coverage, not GM-035 re-add delivery proof.
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` proves message-ID dedupe when PubSub and group inbox deliver the same message. `test/features/groups/integration/group_resume_recovery_test.dart` has reusable cursor inbox and replay-envelope injection patterns.
- `test/shared/fakes/group_test_user.dart` computes fake topic peer count from network subscribers and can force `publishTopicPeersOverride: 0`, but it only mirrors live delivery for `SendGroupMessageResult.success`; this is useful for GM-035 because `successNoPeers` leaves durable replay as the only delivery path until the test injects/drains the inbox.
- GM-033/GM-034 patterns show the current three-party proof stack requires scenario registration in `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_real_harness.dart`, and `group_multi_party_device_criteria_test.dart`.
- Live device preflight on 2026-05-12 shows usable iOS simulator tuples, but PIDs `32906`, `33023`, and `34354` are a non-GM-035 `private_readd_cycles` runner using `560D3E2D-78F8-4D28-A010-16B399581C99` and `511B36DA-7113-41A7-A718-4450C87C0E62`. Final GM-035 device proof may need to wait for three uncontended targets.

## implementation plan

Planner role notes:

1. Start with `git status --short` and inspect diffs before touching any dirty owner file. Preserve all existing user/prior-run changes.
2. Add the host regression first. Prefer `test/features/groups/integration/group_membership_smoke_test.dart` if A/B/C re-add state can be modeled cleanly; otherwise add a lower-level companion in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` for precise cursor/replay control.
3. Host regression shape:
   - Create Alice, Bob, Charlie in a private chat group; remove Charlie; re-add Charlie with current member/device/key state.
   - Keep Alice/Bob current eligible recipients but simulate unfinished discovery by unsubscribing them from the fake network or forcing Charlie's `sendGroupMessageViaBridge(..., publishTopicPeersOverride: 0)`.
   - Assert Charlie's send returns `successNoPeers`, status `sent`, and the actual `group:inboxStore` replay payload names Alice and Bob as recipients.
   - Inject the stored replay envelope into Alice and Bob cursor inbox bridges and run `drainGroupOfflineInboxForGroup` or `drainGroupOfflineInbox`.
   - Assert Alice and Bob each persist Charlie's message exactly once with the same message ID/text/sender/device/key epoch.
   - Optionally deliver the same message through live PubSub after re-subscribing/discovery convergence and assert the persisted count remains one.
4. Patch product only on RED:
   - If Charlie cannot send with current re-add state, inspect `add_group_member_use_case.dart`, `group_message_listener.dart`, `group_key_update_listener.dart`, `send_group_message_use_case.dart`, and `group_config_payload.dart`.
   - If durable recipients omit Alice/Bob or duplicate them, inspect `_loadGroupSendMembership`, `hasDeliverableGroupMemberIdentity`, replay-envelope recipient wiring, and `group_inbox.go`.
   - If Alice/Bob drain fails or duplicate, inspect `drain_group_offline_inbox_use_case.dart`, `handle_incoming_group_message_use_case.dart`, and receiver repository dedupe.
   - If Go reports/handles topic peers incorrectly, inspect `pubsub.go` and add a focused Go selector before changing it.
5. Add `gm035` criteria and harness support:
   - Register `gm035` as Alice/Bob/Charlie in `group_multi_party_device_criteria.dart` and `run_group_multi_party_device_real.dart`.
   - Add criteria tests accepting valid GM-035 verdicts and rejecting missing zero-topic proof, missing durable recipient proof, missing Alice/Bob receipt, or duplicate receiver persistence.
   - Add harness role paths where Alice creates/re-adds Charlie, Charlie sends immediately with recorded initial `topicPeers`, Alice/Bob drain/catch up if live fanout is zero, then optional live convergence confirms no duplicate.
6. Stop production edits once the GM-035 host regression, criteria tests, and required gates pass. Closure updates to the source matrix/breakdown belong to a later closure worker after accepted execution evidence exists.

## test and gate plan

Regression-first direct tests:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-035'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GM-035'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'topicPeers zero'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'deduplicates by messageId when pubsub and group inbox deliver same message'
flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-035'
```

Adjacent group regressions:

```bash
flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
```

Conditional Go proof if Go publish/topic-peer or durable recipient code changes:

```bash
(cd go-mknoon && go test ./node -run 'TestGM035|TestPublishGroupMessage_EmitsLiveFanoutDiagnosticWithoutFailingDurableSend|TestGM030|TestGM031|TestGM034' -count=1)
```

Named gates and hygiene:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Required final device proof after `gm035` support exists and the simulator tuple is uncontended:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' \
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm035 \
  -d <alice_device>,<bob_device>,<charlie_device>
```

Planning-time likely tuples if free: iOS 26.2 `560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245` or iOS 26.1 `38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Recheck `flutter devices --machine`, `xcrun simctl list devices available`, and `pgrep -af 'run_group_multi_party_device_real|flutter drive|GROUP_MULTI_PARTY_SCENARIO'` immediately before running.

## dirty worktree handling

The repo is already dirty across matrix docs, many group-chat source/test files, Go files, harness files, and untracked adjacent session plans. Treat every pre-existing edit as user/prior-run work.

Execution rules:

- Do not edit the source matrix or session breakdown during GM-035 implementation; closure workers own those later.
- Before editing a dirty GM-035 owner file, inspect `git diff -- <file>` and patch only row-owned lines.
- Do not revert, restage, reformat, or "clean up" unrelated changes.
- Run formatter only on files touched for GM-035.
- If a required owner file is syntactically broken before GM-035 edits, record the exact command/failure and stop or replan instead of hiding it under GM-035.

## scope guard

Do not:

- Reopen or modify GM-021 through GM-034 behavior except as direct adjacent test coverage.
- Treat current `private_readd_cycles` device contention as accepted GM-035 evidence.
- Claim host-only proof closes the row; final row closure requires a trusted three-party proof or explicit external fixture blocker.
- Rewrite discovery, relay storage, group membership architecture, key repair, notification routing, or UI surfaces.
- Weaken removed-member rejection, stale config watermarks, fresh re-add key/package binding, duplicate member normalization, send authorization, durable recipient filtering, or message-ID dedupe.

Overengineering would be adding a global discovery wait/retry subsystem before the exact GM-035 regression proves the current durable fallback path is insufficient.

## stop/replan rules

- If exact GM-035 host and device proof pass without product changes, stop at tests/harness/evidence and do not patch production.
- If the host regression cannot force `topicPeers == 0` while keeping Alice/Bob eligible recipients, replan the host proof before changing product code.
- If durable inbox store succeeds but Alice/Bob cannot drain because the test harness lacks relay replay plumbing, add the smallest harness helper and criteria proof; do not reinterpret the row as evidence-only.
- If product changes touch shared listener/send/dedupe paths and unrelated group gates fail, classify whether the failure is GM-035-attributable before widening scope.
- If the final three-party proof cannot run because another process owns the same simulator tuple, record the exact PID/command/device IDs and leave GM-035 open as `blocked/external_fixture`; do not mark Covered.
- If `gm035` device proof fails with a role verdict assertion, fix GM-035 code/harness only until the verdict either passes or exposes a new structural blocker.

## reviewer findings

Reviewer role notes:

- Sufficiency: sufficient as-is after tightening the proof to require separate zero-live-fanout, durable recipient, drain/catch-up, and exact-once receiver assertions.
- Missing files/tests/gates: exact `GM-035` host selector, `gm035` criteria tests, `gm035` runner/harness support, and exact three-party proof are missing and are required implementation work.
- Stale/incorrect assumptions: the breakdown's `evidence-gated` label is not safe for this turn because exact row support is absent and the user contract forbids docs-only/evidence-only downgrade when row-owned gaps are found.
- Overengineering check: no broad discovery or relay rewrite is planned; production changes are conditional on RED evidence.
- Decomposition: narrow enough for implementation because it starts with a single forced-zero-peer host proof and only then adds device proof support.
- Minimum to be sufficient: add exact GM-035 host regression, add criteria/runner/harness support, run direct tests/gates, and obtain or explicitly block final device proof.

## arbiter decision

Arbiter role notes:

- Structural blockers: none for planning. The plan has explicit scope, closure bar, regression-first rule, test/gate contract, dirty-worktree handling, scope guard, and stop/replan rules.
- Incremental details: exact GM-035 verdict field names can be chosen during implementation, but they must encode at least `initialTopicPeers`, `successNoPeers`, `actualDurablePayloadProof`, `recipientPeerIds`, Alice/Bob receipt counts, and no duplicate persistence.
- Accepted differences: host fake-network proof validates app semantics and durable replay plumbing; Go proof is conditional unless Go code changes or the host/device proof exposes a Go topic-peer bug. Final simulator/device proof remains mandatory for closure.
- Final decision: `execution-ready`. Current non-GM-035 simulator contention may delay final proof, but it does not block implementing the row-owned host, criteria, runner, and harness work.

## Recovery Plan - Device Zero Peer Harness Gap

Status: fix-pass preparation only. Do not mark GM-035 accepted or update the source matrix/breakdown from this pass.

Evidence to preserve: the clean iOS 26.1 `gm035` device proof exited `255` with orchestrator verdict `ok:false` in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm035_Z3Ueps/gmp_1778539435216_gm035_orchestrator_verdict.json`. Charlie's first post-readd send reported `outcome:"success"`, `topicPeers:2`, `initialTopicPeers:2`, `sentBeforeLiveDiscoveryCompleted:false`, and `successNoPeers:false`. This is a row-owned harness/scenario gap because Alice and Bob were still joined to the live group topic before Charlie sent.

Files for the fix pass:

- Primary patch file: `integration_test/group_multi_party_device_real_harness.dart`.
- Only touch `integration_test/scripts/group_multi_party_device_criteria.dart` and `test/integration/group_multi_party_device_criteria_test.dart` if adding a new required verdict field for the unavailability proof. The current criteria already rejects the observed `topicPeers:2` / `successNoPeers:false` failure.
- Do not edit production code, host tests, source matrix, session breakdown, or unrelated GM rows unless a named stop rule below triggers a replan.

Harness patch shape:

1. Add GM-035-only helpers near the existing GM-035 helpers:
   - `_gm035LeaveLiveTopicOnly(...)`: call `callGroupLeave(stack.bridge, groupId)` directly, not `leaveGroup(...)`, so the Go node leaves the live group topic but local group/member/key rows remain intact. Verify and record that `stack.groupRepo.getGroup(groupId)`, latest key, and `_memberPeerIds(stack, groupId)` still include Alice, Bob, and Charlie after the leave.
   - `_gm035RejoinLiveTopicOnly(...)`: rebuild the current group config from `stack.groupRepo.getGroup(groupId)`, `stack.groupRepo.getLatestKey(groupId)`, and `stack.groupRepo.getMembers(groupId)`, then call `callGroupJoinWithConfig(...)`. After rejoin, run `drainGroupOfflineInboxForGroup(...)` before checking receipt.
2. In `_runGm035Alice`, after Alice re-adds Charlie, publishes the re-add payload, waits for Bob to process it, and writes `charlie_gm035_readd_group_fixture.json`, make Alice leave the live topic with `_gm035LeaveLiveTopicOnly(...)` before Charlie is allowed to send. Write a shared proof signal such as `alice_gm035_live_topic_unavailable.json` containing retained member IDs, key epoch, and leave result. Then wait for Charlie's send signal, rejoin, drain/catch up, write the existing Alice receipt proof, and after the optional live duplicate assert `postLiveDuplicatePersistedCount == 1`.
3. In `_runGm035Bob`, after `_waitForMemberInclusion(...)` proves Bob has the re-added Charlie as a current member, make Bob leave the live topic with the same helper and write `bob_gm035_live_topic_unavailable.json`. Then wait for Charlie's send signal, rejoin, drain/catch up, write the existing Bob receipt proof, and after the optional live duplicate assert `postLiveDuplicatePersistedCount == 1`.
4. In `_runGm035Charlie`, import `charlie_gm035_readd_group_fixture.json`, write `charlie_gm035_rejoined`, then wait for both `alice_gm035_live_topic_unavailable.json` and `bob_gm035_live_topic_unavailable.json` before calling `_sendProofMessage(...)`. Immediately fail the role verdict if `initialTopicPeers != 0` or `outcome != successNoPeers`; include the observed tuple in the thrown error. Keep the existing durable proof fields and add optional proof fields such as `aliceBobLiveTopicUnavailableAtSend:true` and `liveTopicUnavailableProofRoles:["alice","bob"]`.
5. Keep Alice and Bob eligible durable recipients by validating Charlie's sent proof still has `recipientPeerIds` exactly Alice and Bob, `actualDurablePayloadProof:true`, and no duplicate recipients. The live-topic leave must not remove or rewrite local membership.
6. Publish the optional live duplicate only after Alice and Bob have rejoined and written their catch-up/receipt signals. This preserves the row order: zero-live-peer durable send first, durable catch-up exactly once second, optional live duplicate/dedupe proof last.
7. If direct topic leave does not produce `initialTopicPeers == 0`, stop the device run and switch only inside `integration_test/group_multi_party_device_real_harness.dart` to the stronger harness isolation: Alice and Bob call `stack.p2pService.stopNode()` after re-add processing, write offline-unavailable signals, Charlie sends, then Alice and Bob call `startNodeCore(stack.identity.privateKey, stack.identity.peerId)`, `_waitForOnline(...)`, `_gm035RejoinLiveTopicOnly(...)`, and drain/catch up. Do not change product send semantics to manufacture zero peers.

Stop rules:

- If `callGroupLeave(...)` removes local group/member/key state, stop and use the `stopNode` harness isolation path instead; do not call `leaveGroup(...)`.
- If Charlie's first send still records live peers after Alice and Bob are unavailable, stop after one focused rerun and inspect only the GM-035 harness choreography before widening.
- If Charlie's durable `recipientPeerIds` omit Alice or Bob, contain Charlie, or contain duplicates, stop and replan because that is no longer only a live-topic harness gap.
- If Alice or Bob cannot drain the durable replay after rejoin/restart, stop with the shared dir and role logs; do not mark external fixture unless simulator/process contention is proven.
- If either receiver persists Charlie's message more than once after the optional live duplicate, stop and replan against receiver dedupe before touching production.
- If the exact device tuple is occupied, record the owning PIDs/commands and leave this fix pass blocked; do not claim final GM-035 acceptance.

Required verification for the fix pass:

```bash
flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-035'
git diff --check
```

If `test/features/groups/integration/group_membership_smoke_test.dart` or other host GM-035 tests are touched, rerun:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-035'
```

Rerun the exact focused device proof on a clean tuple, starting with the failed iOS 26.1 devices if free:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' \
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm035 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

The device proof must produce a `gm035` orchestrator verdict where Charlie's first send has `initialTopicPeers:0`, `topicPeers:0`, `outcome:"successNoPeers"`, `successNoPeers:true`, Alice/Bob are durable recipients, Alice and Bob each drain/catch up to one persisted message, and post-live-duplicate persisted counts remain one. Record the proof result only; final source-row acceptance belongs to a later closure pass.

## QA Review - GM-035 Fix Pass

Verdict: `accepted`.

Commands run:

- `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-035'` - passed.
- `git diff --check` - passed.

Evidence reviewed:

- Inspected `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, and `integration_test/scripts/run_group_multi_party_device_real.dart` for GM-035 support.
- Inspected `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm035_ISnTSP/gmp_1778540620083_gm035_orchestrator_verdict.json`: `ok:true`, `detail:"gm035 verdicts valid for alice, bob, charlie"`, devices Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Inspected role verdict JSONs and shared proof files. Charlie's first post-readd send is `outcome:"successNoPeers"`, `topicPeers:0`, `initialTopicPeers:0`, `actualDurablePayloadProof:true`, with durable recipients Alice `12D3KooWPWERnzKwTfoUH4mkgKjCAKtQgsJqrVacAWUUMUnMRYn9` and Bob `12D3KooWCFZ53mQw4dzcbtG1DGr7HW5zx6nUcZkd6RLo4qxU5WUp` only.
- Alice and Bob live-topic-unavailable proofs show `leftLiveTopicOnly:true`, retained group/key/member state, and member sets containing Alice, Bob, and Charlie. Alice and Bob each received Charlie's message with `persistedCount:1`; both verdicts record `postLiveDuplicatePersistedCount:1` and `noDuplicatePersistence:true` after the optional live duplicate.

Residual risk: the exact three-device proof was not rerun in this QA pass per instruction; acceptance is based on fresh inspection of the passing shared-dir artifacts plus the focused criteria and diff hygiene gates above.
