# GM-002 Plan - Add D While A/B/C Are Online

Status: execution-accepted

Source row:

`GM-002 | Add D while A/B/C are online | G has A/B/C joined and connected. | 1. A updates config to include D. 2. D joins. 3. A and D send. | All current members converge on same member list and all can receive messages allowed by their membership window. | P0 | Open | Required | Required | Required | Recommended | Required | Proves config update plus topic discovery.`

## Planning Progress

| Timestamp | Role/phase | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 11:54:00 CEST | Planner completed | This GM-002 plan file | Draft plan is evidence-gated and row-owned: rerun focused host/config proof, run criteria guard, run exact GM-002 A/B/C/D device proof through accepted harness, capture verdict artifact, run hygiene/gates, and reserve source matrix/breakdown updates for closure after proof passes. | Run strict Reviewer pass for missing gates, stale assumptions, and scope creep. |
| 2026-05-10 11:56:13 CEST | Reviewer started | Draft plan file; orchestrator mandatory section checklist | Reviewer pass started. Initial scan finds the core scope and proof path present; check remains for exact start/end hygiene commands, final output sections, and any accidental closure wording. | Complete sufficiency review and patch any non-structural omissions before Arbiter. |
| 2026-05-10 11:56:35 CEST | Reviewer completed | This GM-002 plan file | Sufficient with one incremental adjustment applied: include explicit `git status --short` hygiene in the execution command list so dirty-worktree attribution is repeatable. No structural blocker found; mandatory sections, device/relay profile, non-closing warnings, and product-gap interpretation are present. | Run Arbiter pass and stop if no structural blocker remains. |
| 2026-05-10 11:56:59 CEST | Arbiter started | Reviewer pass and adjusted GM-002 plan | Arbiter classification started. Candidate structural blockers: none observed so far; verify stop rule, closure bar, regression contract, and source-row Open discipline. | Complete arbiter classification and finalize status if no structural blocker remains. |
| 2026-05-10 11:57:42 CEST | Arbiter completed | This GM-002 plan file; Reviewer Pass | No structural blockers remain. Incremental hygiene adjustment was already applied. Stop rule reached: the plan is narrow, evidence-backed, row-owned, and safe to execute with GM-002 still open until closure proof passes. | Hand off as `Status: execution-ready`; do not edit production/tests/source matrix/breakdown in planning. |

## Execution Progress

| Timestamp | Role/phase | Files inspected or touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 12:00:01 CEST | Contract extraction started | This GM-002 plan file; GM-002 breakdown entry orientation; `git status --short` snapshot | Spawned child-agent primitive is unavailable in this tool context; this fresh GM-002 invocation will use the skill's local sequential fallback with Executor then QA phases. Dirty worktree contains unrelated modified and untracked files, including this untracked owner plan. | Extract exact scope, closure bar, source of truth, commands, known-failure interpretation, and scope guard before running checks. |
| 2026-05-10 12:00:01 CEST | Contract extracted | This GM-002 plan file; GM-002 breakdown orientation | Scope is GM-002 only. Acceptance requires focused host/config proof, criteria guard, exact four-role GM-002 relay/device verdict with Alice/Bob/Charlie/Dana artifacts, required direct groups tests, `./scripts/run_test_gates.sh groups`, `git diff --check`, and final `git status --short`. Production/tests are touchable only for a real GM-002 product/code gap; source matrix, breakdown closure ledgers, GM-001, and GM-003+ remain out of scope. | Start local Executor phase with fresh status/device checks. |
| 2026-05-10 12:00:27 CEST | Executor started | This GM-002 plan file | Local Executor phase started under fallback. No code/test edits made. | Run `git status --short`, `flutter devices --machine`, and `xcrun simctl list devices available`. |
| 2026-05-10 12:00:54 CEST | Fresh status/device checks completed | This GM-002 plan file; current `git status --short`; current `flutter devices --machine`; current `xcrun simctl list devices available` | Required devices are available: Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, Dana `1B098DFF-6294-407A-A209-BBF360893485`. Dirty worktree is broad and pre-existing/unrelated; no source or test edits made by GM-002 execution so far. | Run focused GM-002 host/config tests. |
| 2026-05-10 12:01:42 CEST | Focused host/config proof completed | This GM-002 plan file; `test/features/groups/application/add_group_member_use_case_test.dart`; `test/features/groups/integration/group_messaging_smoke_test.dart` | Passed `GM-002 addGroupMember syncs updated A/B/C/D config payload` and `GM-002 adds D while A/B/C are online and converges post-add delivery`. No code/test edits made. | Run accepted criteria guard. |
| 2026-05-10 12:02:18 CEST | Criteria guard completed; GM-002 device proof started | This GM-002 plan file; `test/integration/group_multi_party_device_criteria_test.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart` | Passed `flutter test test/integration/group_multi_party_device_criteria_test.dart` with 11 tests. Starting exact GM-002 relay proof for Alice/Bob/Charlie/Dana on the planned four simulator IDs. | Run `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm002 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`. |
| 2026-05-10 12:03:40 CEST | GM-002 device proof running | This GM-002 plan file; orchestrator output | Orchestrator created shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm002_LWsi7q`, run id `1778407359493`, and mapped Alice/Bob/Charlie/Dana to the exact planned devices. Alice launch is in progress. | Continue waiting for row-specific orchestrator verdict. |
| 2026-05-10 12:05:08 CEST | GM-002 device proof running | This GM-002 plan file; orchestrator output | Alice built, started, and reached relay online; Bob launch is in progress. No product verdict yet and no code/test edits made. | Continue waiting for row-specific orchestrator verdict. |
| 2026-05-10 12:06:03 CEST | GM-002 device proof running | This GM-002 plan file; orchestrator output | Bob built, became identity-ready, and reached relay online; Charlie launch is in progress. No product verdict yet and no code/test edits made. | Continue waiting for row-specific orchestrator verdict. |
| 2026-05-10 12:06:55 CEST | GM-002 device proof running | This GM-002 plan file; orchestrator output | Charlie built, became identity-ready, and reached relay online; Dana launch is in progress. No product verdict yet and no code/test edits made. | Continue waiting for row-specific orchestrator verdict. |
| 2026-05-10 12:07:58 CEST | GM-002 device proof running | This GM-002 plan file; orchestrator output | Dana is running; mid-run logs show four-member group state and Dana drained two group messages. This is progress only, not closure proof. No code/test edits made. | Continue waiting for row-specific orchestrator verdict. |
| 2026-05-10 12:09:29 CEST | GM-002 device proof completed; verdict inspected | This GM-002 plan file; `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm002_LWsi7q/gmp_1778407359493_gm002_orchestrator_verdict.json`; Alice/Bob/Charlie/Dana role verdict JSONs | Exact four-device GM-002 proof passed. Orchestrator verdict has `scenario: gm002`, `ok: true`, detail `gm002 verdicts valid for alice, bob, charlie, dana`, all planned role devices, and all per-role verdict paths. JSON verification confirmed four-role member convergence, common key epoch `1`, exactly-one Alice post-add receipts by Bob/Charlie/Dana with matching tuple, and exactly-one Dana post-join receipts by Alice/Bob/Charlie with matching tuple. No code/test edits made. | Run required direct tests, `./scripts/run_test_gates.sh groups`, `git diff --check`, and final `git status --short`. |
| 2026-05-10 12:09:53 CEST | Required direct test completed | This GM-002 plan file; `test/features/groups/application/add_group_member_use_case_test.dart` | Passed `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart` with 14 tests. | Run full `group_messaging_smoke_test.dart`. |
| 2026-05-10 12:10:20 CEST | Required direct test completed | This GM-002 plan file; `test/features/groups/integration/group_messaging_smoke_test.dart` | Passed `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart` with 15 tests. | Run full `group_membership_smoke_test.dart`. |
| 2026-05-10 12:10:49 CEST | Required direct test completed | This GM-002 plan file; `test/features/groups/integration/group_membership_smoke_test.dart` | Passed `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` with 25 tests. | Run full `group_new_member_onboarding_test.dart`. |
| 2026-05-10 12:11:14 CEST | Required direct test completed | This GM-002 plan file; `test/features/groups/integration/group_new_member_onboarding_test.dart` | Passed `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` with 7 tests. | Run full `member_removal_integration_test.dart`. |
| 2026-05-10 12:11:43 CEST | Required direct test completed; groups gate started | This GM-002 plan file; `test/features/groups/application/member_removal_integration_test.dart`; `scripts/run_test_gates.sh` | Passed `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart` with 6 tests. Starting `./scripts/run_test_gates.sh groups`. | Wait for groups gate result. |
| 2026-05-10 12:13:30 CEST | Required groups gate completed; hygiene started | This GM-002 plan file; `scripts/run_test_gates.sh` | Passed `./scripts/run_test_gates.sh groups` with 106 tests. No code/test edits made by GM-002 execution. | Run `git diff --check` and final `git status --short`, then start QA Reviewer phase. |
| 2026-05-10 12:13:54 CEST | Hygiene completed; QA started | This GM-002 plan file; `git diff --check`; final `git status --short` | `git diff --check` passed. Final status remains broadly dirty with unrelated modified and untracked files; GM-002 execution only updated this owner plan artifact and made no source/test changes. | Run QA Reviewer pass against the GM-002 contract, exact verdict JSON, required gate list, and scope guard. |
| 2026-05-10 12:15:18 CEST | QA completed; final verdict started | This GM-002 plan file; GM-002 orchestrator verdict JSON; Alice/Bob/Charlie/Dana role verdict JSONs; plan command/gate list; current dirty-worktree snapshot | QA found no blocking issue. Fresh JSON checks reconfirmed `ok: true`, `scenario: gm002`, valid roleDevices, per-role verdict paths, shared four-member list, common key epoch `1`, and exactly-once Alice/Dana post-add/post-join delivery tuples. No bounded fix loop was needed. | Record final execution output in this owner plan artifact. |
| 2026-05-10 12:15:45 CEST | Final verdict recorded | This GM-002 plan file | Final execution verdict is `accepted` for GM-002 row proof. Source matrix and breakdown closure ledgers remain untouched for the later closure phase. No code/test edits, completeness-check, or Go tests were needed on the no-product-gap path. | Stop GM-002 execution and return compact result. |

## Final Execution Output

### Final verdict

`accepted`

### Verdict artifact

`/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm002_LWsi7q/gmp_1778407359493_gm002_orchestrator_verdict.json`

### QA result

No blocking QA issue found. The orchestrator verdict has `ok: true`, `scenario: gm002`, detail `gm002 verdicts valid for alice, bob, charlie, dana`, all four planned roleDevices, and per-role verdict paths. Role verdict validation confirmed all four roles converged on the same four-member list, common key epoch `1`, Bob/Charlie/Dana each received Alice's post-add message exactly once with matching tuple, and Alice/Bob/Charlie each received Dana's post-join message exactly once with matching tuple.

### Commands and gates

- `git status --short`: completed before and after execution; dirty tree is broad and unrelated/pre-existing except this owner plan artifact.
- `flutter devices --machine`: completed; all four planned iOS simulator IDs were available.
- `xcrun simctl list devices available`: completed; all four planned iOS simulator IDs were booted/available.
- Focused host/config proof: both GM-002 `--plain-name` tests passed.
- Criteria guard: `flutter test test/integration/group_multi_party_device_criteria_test.dart` passed with 11 tests.
- Exact row proof: `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm002 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485` passed.
- Required direct tests passed: `add_group_member_use_case_test.dart` (14), `group_messaging_smoke_test.dart` (15), `group_membership_smoke_test.dart` (25), `group_new_member_onboarding_test.dart` (7), `member_removal_integration_test.dart` (6).
- `./scripts/run_test_gates.sh groups`: passed with 106 tests.
- `git diff --check`: passed.

### Scope notes

GM-002 execution made no production or test edits and did not weaken `group_multi_party_device_criteria.dart`. Completeness-check was not run because no test/docs inventory or gate definition was added, removed, or reclassified. Go tests were not run because GM-002 execution did not touch Go and the verdict did not point to Go behavior. Source matrix and breakdown closure ledger updates remain out of scope for this execution pass.

## Evidence Collector Summary

- The source matrix row GM-002 is still `Open`; its current note records host/config non-closing proof and says required exact A/B/C/D or equivalent multi-party Flutter-app `3-Party E2E` proof has not yet closed the row.
- GM-001 is now `Covered` by its own row-specific A/B/C device proof. That closure does not close GM-002.
- `PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS` is accepted as reusable support. The reusable files are `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`.
- The harness supports `--scenario gm002`, maps roles to devices in order `alice`, `bob`, `charlie`, `dana`, and requires four distinct app targets.
- GM-002 criteria require A/B/C/D membership convergence, exact Alice post-add message receipt by Bob/Charlie/Dana, exact Dana post-join message receipt by Alice/Bob/Charlie, receiver `messageId`, text/plaintext, `senderPeerId`, `keyEpoch`, and exactly-one persistence checks.
- Existing GM-002 host/config proof is present in `test/features/groups/application/add_group_member_use_case_test.dart::GM-002 addGroupMember syncs updated A/B/C/D config payload` and `test/features/groups/integration/group_messaging_smoke_test.dart::GM-002 adds D while A/B/C are online and converges post-add delivery`.
- `integration_test/scripts/run_group_multi_party_device_real.dart` is classified as an optional/manual simulator orchestrator, not a frozen named gate. It can close GM-002 only when consumed by a row-specific GM-002 session and recorded as row proof.

## Device/Relay Proof Profile

Current live availability was checked during planning with:

```sh
flutter devices --machine
xcrun simctl list devices available
```

Recorded current availability:

- `flutter devices --machine` listed physical Pixel 6 `21071FDF600CSC`, iPhone 17 Pro simulator `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone Air simulator `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone 17 simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, iPhone 16e simulator `1B098DFF-6294-407A-A209-BBF360893485`, `macos`, and `chrome`.
- `xcrun simctl list devices available` showed the same four iOS 26.1 simulators booted: iPhone 17 Pro `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and iPhone 16e `1B098DFF-6294-407A-A209-BBF360893485`.
- The physical iPhone `00008030-001A6D2801BB802E` was noted as visible earlier by the task context, but it was not present in the current `flutter devices --machine` output. Do not rely on it for GM-002 unless a fresh execution snapshot shows it.

Use this exact relay profile:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
```

Primary row-specific GM-002 command:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm002 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

Role mapping for that command is:

- `alice` = `38FECA55-03C1-4907-BD9D-8E64BF8E3469`
- `bob` = `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
- `charlie` = `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- `dana` = `1B098DFF-6294-407A-A209-BBF360893485`

A single `FLUTTER_DEVICE_ID` gate is not sufficient for GM-002 closure. The prior prerequisite-shaped GM-002 artifact is also not sufficient; it accepted the reusable harness, not this row.

## real scope

Own exactly GM-002: A/B/C are already online in group G, A adds D, D joins, A sends after the add, D sends after joining, and A/B/C/D converge on the same current member list while receiving only messages allowed by their membership window.

This planning session changes only this plan file. The execution session this plan enables should start as evidence-gated verification of existing proof and only touch production/tests if the row-specific proof exposes a real GM-002 product/code gap.

## closure bar

GM-002 is good enough only when all of these are true:

- Existing host/config proof has been rerun or verified green for the row-owned `addGroupMember` A/B/C/D config payload and host fake-network A/B/C-online add-D convergence flow.
- `test/integration/group_multi_party_device_criteria_test.dart` passes, preserving the accepted strict harness criteria.
- The row-specific GM-002 device/relay command above passes with `ok: true`, writes a GM-002 orchestrator verdict artifact, and records per-role verdicts for Alice/Bob/Charlie/Dana.
- The verdict validates A/B/C/D membership convergence, Alice's `aliceAfterDanaAdd` receipt by Bob/Charlie/Dana, Dana's `danaAfterJoin` receipt by Alice/Bob/Charlie, exact sender/receiver tuple matching, key epoch agreement, and exactly-one persistence.
- Required hygiene and gates pass.
- Only after the row-specific proof passes may closure update the source matrix and breakdown to mark GM-002 covered/accepted. Planning must not mark it covered.

## source of truth

Authoritative inputs:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-002.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` GM-002, GM-001, and PREREQ rows plus Session Closure Ledger.
- Accepted prerequisite files: `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`.
- Existing GM-002 host/config tests named above.
- `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` for gate/test classification.
- Current live device command output captured in this plan.

On disagreement, current code/tests and current command output beat stale prose. The accepted harness/criteria and current breakdown rows beat the stale pre-PREREQ GM-002 plan. `scripts/run_test_gates.sh` and `test-gate-definitions.md` define named gate membership.

## session classification

`evidence-gated`

Reason: host/config proof already exists and the shared device harness is accepted. The row still needs its own device proof. Code/test changes are conditional on evidence revealing a real GM-002 product behavior failure.

## exact problem statement

GM-002 remains open because prior proof stopped at host/config evidence and prerequisite-shaped harness validation. That is not enough to prove user-visible four-party behavior: after A adds D while A/B/C are live, all current members must converge and all entitled post-add messages from A and D must arrive exactly once with matching sender, plaintext, message id, and key epoch.

The stale failure mode is overclaiming closure from adjacent proof. The user-visible risk is that a newly added live member or an existing live member may not receive entitled private group messages after membership mutation. Existing GM-001 closure and prerequisite harness acceptance must stay unchanged.

## files and repos to inspect next

Planning/evidence docs:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-002-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Direct proof files:

- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`

Production/bridge files only if proof fails in a way that points to product behavior:

- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

## existing tests covering this area

- `GM-002 addGroupMember syncs updated A/B/C/D config payload` proves the production add-member path emits an updated A/B/C/D bridge config payload, including D's peer id, role, public key, ML-KEM public key, device id, transport peer id, and signing public key.
- `GM-002 adds D while A/B/C are online and converges post-add delivery` proves the host fake-network flow: A/B/C baseline subscribers, D not subscribed before add, A adds D, D joins, all four converge on member/key state, A's post-add message reaches B/C/D, and D's post-join message reaches A/B/C.
- `test/integration/group_multi_party_device_criteria_test.dart` proves the criteria reject missing roles, duplicate devices, wrong relay env, sender-only evidence, duplicate receiver persistence, receiver/sender tuple mismatches, key epoch mismatch, and incomplete GM-002 convergence.
- GM-001's row-specific proof is adjacent evidence for the accepted harness path, but it does not cover GM-002's add-D topology.

Missing before closure:

- A GM-002 row-specific device/relay run that consumes the accepted harness and records its own GM-002 verdict artifact.

## regression/tests to add first

No new regression should be added before the initial evidence run because the row-owned host/config tests and accepted device criteria already exist.

Execution should run existing row-owned tests first. If the GM-002 device proof fails because product behavior is wrong, add or tighten the smallest failing regression that captures that exact behavior before changing code. Do not weaken `group_multi_party_device_criteria.dart` or its tests to make the proof pass.

## step-by-step implementation plan

1. Confirm current dirty worktree and note unrelated existing changes without reverting them:

```sh
git status --short
```

2. Rerun current device availability:

```sh
flutter devices --machine
xcrun simctl list devices available
```

3. Rerun/verify focused host/config GM-002 proof:

```sh
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-002 addGroupMember syncs updated A/B/C/D config payload'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-002 adds D while A/B/C are online and converges post-add delivery'
```

4. Run the accepted criteria guard:

```sh
flutter test test/integration/group_multi_party_device_criteria_test.dart
```

5. Run the row-specific GM-002 four-device relay proof with the exact relay env and role/device order in the Device/Relay Proof Profile.
6. Capture the orchestrator verdict path from the command output. The artifact must be a GM-002 row artifact with `scenario: gm002`, `ok: true`, role devices for Alice/Bob/Charlie/Dana, and per-role verdict paths.
7. Inspect the orchestrator verdict and per-role verdicts. Verify they match the GM-002 criteria: membership convergence, Alice post-add fanout, Dana post-join fanout, sender/receiver tuple equality, key epoch equality, and exactly-one persistence.
8. Run required host/gate hygiene:

```sh
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
./scripts/run_test_gates.sh groups
git diff --check
```

9. If no code/test files changed, do not run broad unrelated gates beyond the commands above unless a failure points to a broader seam.
10. If a code/product gap is found and fixed, run the exact failed proof again, the direct tests for touched files, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check` when test inventory/classification changes, and `git diff --check`.
11. Only after all GM-002 row proof passes, hand off to closure to update the source matrix and breakdown. Do not update them during proof execution before the verdict passes.

## risks and edge cases

- Simulator availability drift: the four booted iOS simulators are currently available, but execution must recheck before launching the four-role proof.
- Physical iPhone drift: the earlier physical iPhone is not in the current Flutter device list, so execution should not depend on it.
- Relay env drift: the criteria require the exact relay address string; any mismatch is a setup/config failure.
- Product failure vs harness failure: criteria failures for missing membership, missing messages, duplicate persistence, key epoch mismatch, or receiver tuple mismatch should be treated as GM-002 product/code gaps unless logs clearly show launch/device infrastructure failure.
- Online timing: per-role startup, identity exchange, and simulator runner lifecycle can fail independently of product behavior. Preserve shared-dir logs and verdict paths for classification.
- Dirty worktree: unrelated existing changes are present; execution must not revert or attribute unrelated diffs to GM-002.

## exact tests and gates to run

Planning-time evidence commands already run:

```sh
flutter devices --machine
xcrun simctl list devices available
```

Execution commands:

```sh
flutter devices --machine
xcrun simctl list devices available
git status --short
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-002 addGroupMember syncs updated A/B/C/D config payload'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-002 adds D while A/B/C are online and converges post-add delivery'
flutter test test/integration/group_multi_party_device_criteria_test.dart
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm002 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
./scripts/run_test_gates.sh groups
git diff --check
git status --short
```

Conditional if code/tests/docs are changed during execution:

```sh
dart format <touched Dart files>
flutter analyze <touched Dart files or nearest supported target>
./scripts/run_test_gates.sh completeness-check
```

Go tests are not required on the no-code-change proof path. If a GM-002 failure leads to Go changes, run the focused affected Go package tests plus the relevant group/pubsub command chosen from the touched seam.

## known-failure interpretation

- Source matrix GM-002 being `Open` is expected before closure and is not a failure.
- A single `FLUTTER_DEVICE_ID` gate, `group-real-network-nightly`, two-simulator fixture, two-device-plus-CLI fixture, relay-nightly fixture, four-simulator invite-status display fixture, or the accepted prerequisite-shaped GM-002 artifact is non-closing for GM-002.
- `run_group_multi_party_device_real.dart` exit 64 from missing/incorrect relay env, too few devices, or duplicate devices is setup failure, not product proof.
- A role process exiting before writing a verdict, simulator boot/Runner lifecycle failure, or online timeout may be infrastructure. Preserve logs, cleanly terminate runner apps if needed, and rerun once only after recording the first failure.
- A verdict with `ok: false` due membership convergence, missing expected received proof keys, duplicate persistence, sender/receiver tuple mismatch, or key epoch mismatch is a GM-002 product/code gap unless direct logs prove infrastructure corruption.
- Pre-existing dirty files outside GM-002 scope are not regressions introduced by this plan.

## done criteria

- This plan file reaches `Status: execution-ready`.
- Execution rechecks and records live device availability.
- Focused GM-002 host/config tests pass.
- Criteria guard passes.
- Row-specific GM-002 device proof passes with a captured GM-002 orchestrator verdict artifact and per-role verdict artifacts.
- Required direct tests, `./scripts/run_test_gates.sh groups`, and `git diff --check` pass.
- Closure updates source matrix and breakdown only after row-specific proof passes.
- If proof fails because of product behavior, execution records the code/product gap, fixes code/tests within GM-002 scope, reruns proof/gates, and does not weaken harness criteria.

## scope guard

Non-goals:

- No GM-003 offline-D proof.
- No remove/re-add, stale ordering, simultaneous mutation, admin policy, media, notification, UI, or broad reliability-soak scope.
- No production/test edits in this planning turn.
- No source matrix or breakdown closure edits during planning or before execution proof passes.
- No changes to accepted GM-001 closure.
- No broad refactor of the harness, criteria, group repository, bridge, Go pubsub, relay, or discovery code unless the row-specific proof exposes a directly attributable GM-002 product failure.

Overengineering includes inventing a second orchestration path, relaxing criteria to tolerate missing receiver evidence, or replacing the accepted four-role harness instead of using it.

## accepted differences / intentionally out of scope

- GM-001 and GM-002 share the accepted multi-party harness, but GM-001 proves only A/B/C group creation and Alice fanout. GM-002 must prove A/B/C-online add-D, Alice post-add fanout, and Dana post-join fanout.
- The prerequisite-shaped GM-002 artifact remains accepted only for harness readiness. It is intentionally not treated as source-row closure.
- Manual simulator orchestrator classification is accepted; `run_group_multi_party_device_real.dart` remains outside frozen named gates and is invoked explicitly by this row plan.
- The physical Pixel 6 can remain available but is not selected for the primary GM-002 proof because four booted iOS simulators already satisfy the accepted four-role command.

## dependency impact

GM-002 closure is a prerequisite for treating add-member live group behavior as reliable in the source matrix. Later GM/GE rows involving offline D, remove/re-add, churn, relay recovery, and broader group reliability should not claim this specific add-D-online proof unless GM-002 closes with its own row-specific device verdict. If GM-002 uncovers a product/code gap, later rows depending on add-member convergence should be skipped or marked blocked until the gap is fixed and GM-002 proof passes.

## Reviewer Pass

- Sufficiency: sufficient with adjustment.
- Missing files/tests/gates: no missing proof files or gates after adding explicit `git status --short` start/end hygiene.
- Stale assumptions: stale "no exact fixture exists" assumption has been removed; accepted PREREQ harness is now the row proof vehicle.
- Overengineering: none; the plan reuses the accepted harness and existing host/config proof.
- Decomposition: narrow enough for execution; it owns only GM-002 proof and conditional GM-002 fixes if the proof exposes product behavior.
- Minimum needed: run focused host/config proof, criteria guard, exact four-device GM-002 proof, required gates, then closure docs only after proof passes.

## Arbiter Pass

- Structural blockers: none.
- Incremental details: explicit dirty-worktree hygiene was added during review; no remaining incremental detail blocks execution.
- Accepted differences: the manual orchestrator remains outside frozen named gates; the prerequisite-shaped GM-002 artifact remains non-closing; GM-001 closure remains unchanged; the current proof uses four booted iOS simulators rather than the earlier physical iPhone.
- Stop rule: no structural blocker remains, so planning stops here.

## Final Planning Output

### Final verdict

`execution-ready`

### Final plan

Run GM-002 as an evidence-gated row proof: rerun focused host/config GM-002 proof, run the accepted criteria guard, run the exact four-device `--scenario gm002` relay proof with Alice/Bob/Charlie/Dana mapping, capture and inspect the row-specific verdict artifacts, run required host/gate hygiene, and update source matrix/breakdown only during closure after proof passes.

### Structural blockers remaining

None.

### Incremental details intentionally deferred

No broad unrelated gate is required on the no-code-change proof path. If execution changes code/tests/docs because the device proof exposes a product gap, broaden only to the touched seam and required gate/classification checks.

### Accepted differences intentionally left unchanged

The accepted prerequisite harness remains prerequisite support only. The prior GM-002-shaped prerequisite artifact remains non-closing. GM-001 stays covered by its own row-specific proof. `run_group_multi_party_device_real.dart` remains an optional/manual simulator orchestrator invoked explicitly by this row plan.

### Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- Current outputs of `flutter devices --machine` and `xcrun simctl list devices available`

### Why the plan is safe to implement now

The stale missing-fixture assumption is gone, the accepted harness supports the exact GM-002 topology, four booted simulator targets are currently available, and the closure bar prevents overclaiming from host-only, single-device, nightly, or prerequisite-shaped evidence. If row-specific proof fails because of product behavior, the plan requires treating it as a GM-002 code/product gap and fixing code/tests rather than weakening harness criteria.
