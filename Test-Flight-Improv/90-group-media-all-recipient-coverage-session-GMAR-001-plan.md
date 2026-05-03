Status: accepted

# GMAR-001 Plan - Existing text fan-out and current media evidence map

## Planning Progress

- `2026-05-02 11:01:40 CEST` - Arbiter completed. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Decision/blocker: no structural blockers remain; plan is execution-ready for GMAR-001 evidence/doc/test-assertion work. Next action: hand off to execution with production-code stop rule intact.
- `2026-05-02 11:01:40 CEST` - Arbiter started. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Decision/blocker: no blocker to arbitration. Next action: classify reviewer findings into structural blockers, incremental details, and accepted differences.
- `2026-05-02 11:01:08 CEST` - Reviewer completed. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Decision/blocker: plan is sufficient as drafted; no structural blockers found. Next action: Arbiter classifies reviewer findings and finalizes status.
- `2026-05-02 11:01:08 CEST` - Reviewer started. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Decision/blocker: no blocker to review. Next action: check mandatory sections, source of truth, regression-first rule, gate contract, stop rule, and scope guard.
- `2026-05-02 10:59:16 CEST` - Planner completed. Files inspected since last update: none. Decision/blocker: draft is evidence-gated and production-code-free, with a test-first text assertion tightening only if current coverage remains narrower than GMAR-001's "every participant / correct sender identity" contract. Next action: run strict reviewer sufficiency pass.

## Execution Progress

- `2026-05-02 11:14:11 CEST` - Final whitespace check completed. Files inspected or touched since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command run: `git diff --check`. Decision/blocker: passed with no output after final controller verdict update. Next action: return final execution output.
- `2026-05-02 11:13:46 CEST` - Final verdict written. Files inspected or touched since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command currently running: none. Decision/blocker: accepted; spawned Executor and spawned QA Reviewer both completed with trustworthy evidence, QA found no blocking issues, and no fix pass is needed. Next action: run final `git diff --check` after this controller verdict update and return final execution output.
- `2026-05-02 11:12:23 CEST` - QA Reviewer completed. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md`. Commands run: inspection only (`git status --short`, scoped `git diff`, `rg`, `sed`, `git ls-files --others --exclude-standard`) plus `git diff --check -- Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md` after the QA log update; no test or gate rerun. Decision/blocker: no blocking QA issues found; GMAR-001 is accepted based on recorded green focused proof, green `groups` gate, green `git diff --check`, exact all-participant sender/text assertions in the existing four-user text case, and docs that keep GMAR-002 through GMAR-004 media parity open. Next action: hand accepted QA result back to the controller; later sessions own media parity.
- `2026-05-02 11:12:22 CEST` - QA Reviewer started. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Command currently running: none. Decision/blocker: no blocker entering QA; review is scoped to GMAR-001 sufficiency and recorded Executor evidence in the dirty worktree. Next action: verify assertion sufficiency, required command evidence, doc boundaries, and scope guard.
- `2026-05-02 11:10:51 CEST` - QA Reviewer spawned. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command currently running: spawned QA Reviewer agent `019de7f4-6384-7e62-8fd7-b76fda671ace`. Decision/blocker: second fresh spawned-agent isolation active with model `gpt-5.5` and reasoning effort `xhigh`; no blocker yet. Next action: wait for QA sufficiency result under bounded wait rule.
- `2026-05-02 11:10:20 CEST` - Controller inspected Executor result and QA handoff prepared. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Command currently running: none. Decision/blocker: Executor returned trustworthy evidence with focused proof, `groups`, and `git diff --check` reported green; no production-code edit observed in the GMAR-001 write scope. Next action: spawn QA Reviewer agent for strict sufficiency review.
- `2026-05-02 11:09:03 CEST` - Executor completed. Files inspected or touched since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `test/features/groups/integration/group_messaging_smoke_test.dart`. Command run: `git diff --check`. Decision/blocker: passed with no output; GMAR-001 has no production-code edits, focused text proof and `groups` gate are green, and evidence docs preserve GMAR-002 through GMAR-004 media gaps. Next action: hand off to QA review.
- `2026-05-02 11:08:27 CEST` - Evidence docs completed and whitespace check started. Files inspected or touched since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command currently running: `git diff --check`. Decision/blocker: Report 90 now records GMAR-001 text fan-out accepted; breakdown ledger marks GMAR-001 accepted; group discussion closure reference distinguishes GMAR-001 text proof from open Report 90 all-recipient media parity; `test-inventory.md` was inspected but not edited because existing wording was not stale for GMAR-001. Conditional `completeness-check` not run because no gate classification or inventory doc wording changed. Next action: wait for `git diff --check`.
- `2026-05-02 11:06:57 CEST` - Groups gate completed and evidence docs refresh started. Files inspected or touched since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command run: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. Decision/blocker: passed (`00:08 +103: All tests passed!`); `Group-Chat-Feature/test-inventory.md` already records MD-014 as partial and existing media fan-out as descriptor/app-layer with only one receiver exercising download, so no inventory classification change is needed. Next action: update Report 90, breakdown ledger, and discussion closure reference with GMAR-001 text proof while preserving GMAR-002 through GMAR-004 media gaps.
- `2026-05-02 11:06:19 CEST` - Focused text proof completed. Files inspected or touched since last update: `test/features/groups/integration/group_messaging_smoke_test.dart`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command run: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name '4 users: round-robin messaging'`. Decision/blocker: passed (`00:00 +1: All tests passed!`); tightened text proof is green. Next action: run required `groups` gate with `FLUTTER_DEVICE_ID=macos`.
- `2026-05-02 11:06:19 CEST` - Groups gate started. Files inspected or touched since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command currently running: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. Decision/blocker: no blocker yet. Next action: wait for named gate result.
- `2026-05-02 11:05:49 CEST` - Focused text proof started. Files inspected or touched since last update: `test/features/groups/integration/group_messaging_smoke_test.dart`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command currently running: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name '4 users: round-robin messaging'`. Decision/blocker: test-only assertion tightening is in place; no blocker yet. Next action: wait for focused proof result.
- `2026-05-02 11:04:51 CEST` - Executor started. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `lib/features/groups/domain/models/group_message.dart`, `git status --short`. Command currently running: none. Decision/blocker: current four-user text test has count assertions and Admin/Bob text sets, but is missing all-participant exact incoming sender/text identity checks; no production-code edit needed. Next action: narrowly tighten the existing round-robin test.
- `2026-05-02 11:04:51 CEST` - Executor running. Files inspected or touched since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command currently running: none. Decision/blocker: assertion helper will verify Admin, Bob, Charlie, and Diana each receive the other three texts exactly once with matching `senderPeerId` and `senderUsername`. Next action: patch `test/features/groups/integration/group_messaging_smoke_test.dart`.
- `2026-05-02 11:03:35 CEST` - Controller started. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, `git status --short`. Command currently running: none. Decision/blocker: dirty tree confirmed with many unrelated edits, including files GMAR-001 may inspect or narrowly touch; no execution blocker yet. Next action: extract and record the GMAR-001 execution contract.
- `2026-05-02 11:03:35 CEST` - Contract extracted. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command currently running: none. Decision/blocker: scope is evidence/doc/test-assertion only; no production code edits; only allowed test edit is narrow sender/text identity tightening in `test/features/groups/integration/group_messaging_smoke_test.dart`; required commands are focused four-user text proof, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` or recorded fallback, and `git diff --check`; `completeness-check` is conditional on gate classification or inventory doc wording changes. Next action: spawn Executor agent.
- `2026-05-02 11:04:21 CEST` - Executor spawned. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`. Command currently running: spawned Executor agent `019de7ee-6970-72d0-ad5a-7e3714690100`. Decision/blocker: spawned-agent isolation active with model `gpt-5.5` and reasoning effort `xhigh`; no blocker yet. Next action: wait for Executor result under bounded wait rule.

## real scope

GMAR-001 is an evidence and closure-mapping session for the existing text complaint and current media evidence boundaries.

In scope:

- Verify the current four-user group text round-robin still proves that active members receive text from active non-creator members, not only from the creator.
- Tighten the existing text regression assertion if the current test still lacks explicit per-recipient sender/text identity checks for all four users.
- Map existing Report 89 and Group Chat inventory media evidence into the narrower Report 90 all-recipient framing without claiming completed media parity where evidence is descriptor-only, one-recipient-only, newly-added-only, sender-side-only, optional-only, or currently failing.
- Update only evidence docs during execution: the Report 90 source doc, the group discussion closure reference, the Group Chat test inventory if its wording is stale, and this breakdown ledger.

Out of scope:

- No production code changes.
- No media fan-out implementation.
- No simulator/render/playback repair.
- No gate restructuring beyond correcting evidence wording if the inventory is stale.

## closure bar

GMAR-001 is good enough when:

- The executor has run or truthfully blocked the direct four-user text proof.
- If the current text test still only proves counts plus partial sender/text sets, the executor has either tightened that test to assert each participant's three incoming messages with expected sender identity, or marked GMAR-001 as only partially covered and stopped without overclaiming.
- The Report 90 source doc clearly says text fan-out is covered or partial with exact evidence, while media all-recipient completion remains open for GMAR-002 through GMAR-004 unless current evidence proves otherwise.
- The closure/reference docs distinguish descriptor evidence from completed download/render evidence.
- The breakdown ledger records GMAR-001 as accepted, accepted with explicit follow-up, stale/already-covered, or blocked based only on concrete commands and file evidence.

## source of truth

Priority order on disagreement:

1. Current code and tests in this working tree.
2. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` for named gate membership.
3. `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md` for GMAR session scope and ordering.
4. `Test-Flight-Improv/90-group-media-all-recipient-coverage.md` for the user-facing problem and source cases.
5. `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`, and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` for existing media evidence boundaries.

Current evidence facts collected:

- `test/features/groups/integration/group_messaging_smoke_test.dart` has `4 users: round-robin messaging` and is included in the frozen `groups` gate.
- That test creates Admin, Bob, Charlie, and Diana; each sends one text message; each user must have four total non-system messages, three incoming, and one outgoing. It explicitly checks Admin's incoming text set and Bob's incoming text set; the execution pass should verify or tighten equivalent per-recipient sender/text identity checks for Charlie and Diana before claiming complete GMAR-001 closure.
- `test/features/groups/integration/group_media_fanout_test.dart` proves existing Bob and Charlie receive image/video/voice rows and metadata from Alice, but the observed helper only requires completed download/local path when `expectDownloaded` is true. In the existing-member case Bob is the download-complete receiver and Charlie may remain descriptor-only.
- Report 89 adds newly-added member send/receive and simulator proof, but Report 90 requires all eligible recipients, not only a newly-added member path or one completed receiver.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` still records MD-014 simulator media proof as partial/failing in one configured recheck, so GMAR-001 must not use simulator media rows as all-recipient closure.

## session classification

`evidence-gated`

This plan is ready to execute as an evidence/doc/test-assertion session, not as a production implementation session.

## exact problem statement

The reported text failure is that an invitee can see creator messages but cannot read messages from other active non-creator members. The reported media failure is that one eligible group member misses media that other members can see.

GMAR-001 must answer the narrow planning/execution question: does the current repo already prove the text part for a four-active-member group, and exactly where does existing Report 89/media evidence stop for the media part?

User-visible behavior that must improve after the whole rollout: active group participants should not see divergent timelines where text appears healthy but messages or media from eligible members are silently absent. In this session, the only user-visible behavior that may be claimed as covered is text fan-out if the direct proof supports it.

What must stay unchanged:

- No pre-join backfill policy changes.
- No announcement role policy changes.
- No media delivery/download/render semantics changed by GMAR-001.
- No group cryptography, transport, relay, retry, inbox, or UI production code changed by GMAR-001.

## files and repos to inspect next

Primary docs to update during execution:

- `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md` only if gate/manual-suite classification wording is corrected
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md` only if announcement evidence is explicitly mentioned or ruled residual

Direct tests to inspect or touch:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `integration_test/group_new_member_media_simulator_proof_test.dart`
- `integration_test/media_message_journey_e2e_test.dart`

Production files to inspect only if evidence contradicts docs, not to edit in GMAR-001:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `go-mknoon/integration/media_test.go`
- `go-relay-server/media_test.go`

## existing tests covering this area

- `test/features/groups/integration/group_messaging_smoke_test.dart`
  - In the `groups` gate via `scripts/run_test_gates.sh`.
  - Covers four active users sending one text each with each user seeing three incoming rows.
  - Needs execution-time confirmation or tightening for every participant's exact expected sender/text identity.
- `test/features/groups/integration/group_media_fanout_test.dart`
  - Optional/manual direct suite.
  - Covers existing-member image/video/voice descriptors for Bob and Charlie, with one receiver proving completed downloads in the existing-member path.
  - Covers newly-added Bob sending image/video/voice to Alice and Charlie, again with one receiver proving completed downloads.
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - Optional/manual direct suite.
  - Covers one newly-added Bob receiving post-join text/image/video/voice with completed downloads and no pre-join backfill.
  - Its multiple-new-member case covers text/epoch convergence, not shared media download/render for multiple new members.
- `go-mknoon/integration/media_test.go` and `go-relay-server/media_test.go`
  - Cover group blob persistence/authorization with sender plus one authorized recipient or one listed peer, and outsider rejection.
  - Do not prove two separate non-sender recipients independently download the same group blob.
- `integration_test/group_new_member_media_simulator_proof_test.dart`
  - Report 89 records pass evidence for newly-added video/voice render/play/reopen, while the current inventory also records MD-014 as partial due to a configured `VideoThumbnailOverlay` failure. Treat as media boundary evidence, not GMAR-001 text closure.

## regression/tests to add first

Before any doc closure, inspect `test/features/groups/integration/group_messaging_smoke_test.dart`.

If it still only asserts:

- count-level coverage for all four users, and
- explicit text sets for Admin and Bob only,

then add the smallest test-only assertion inside the existing `4 users: round-robin messaging` case:

- For Admin, Bob, Charlie, and Diana, assert the exact incoming text set from the other three participants.
- Assert the corresponding sender peer IDs or sender identity fields for those incoming rows.
- Assert each expected incoming sender/message appears exactly once.

Do not add a new broad smoke file. Do not touch production code. If the tightened assertion fails, stop GMAR-001, keep the docs open/blocked, and hand the failing focused test to a later production-fix session.

No new media tests belong in GMAR-001. Media assertion additions belong in GMAR-002 through GMAR-004.

## step-by-step implementation plan

1. Reconfirm the dirty tree and avoid unrelated edits:
   - `git status --short`
2. Inspect the current four-user text test:
   - `test/features/groups/integration/group_messaging_smoke_test.dart`
3. If per-recipient sender/text identity checks are missing for any participant, make only the narrow test assertion tightening described above.
4. Run the focused text proof:
   - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name '4 users: round-robin messaging'`
5. Run the group gate because `group_messaging_smoke_test.dart` is in the named `groups` gate:
   - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
   - If `macos` is unavailable, run `./scripts/run_test_gates.sh groups` and record the actual device/context.
6. Refresh the media evidence map by inspecting, and only optionally rerunning if time/device state permits:
   - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members receive image, video, and voice descriptors'`
   - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'newly-added discussion member sends image, video, and voice to existing members'`
   - `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart --plain-name 'new member receives only post-join text and media with descriptors'`
7. Update evidence docs only after the focused proof is green or truthfully blocked:
   - Report 90 source doc: mark GMAR-001 text covered/partial/blocked with exact command evidence and keep media all-recipient completion open unless proven elsewhere.
   - Group discussion closure reference: add or tighten wording that existing text fan-out is covered separately from media descriptor/download/render gaps.
   - Group Chat inventory: correct stale wording if it overclaims existing media completion for every recipient.
   - Breakdown ledger: set GMAR-001 status based on the evidence and record residual media boundaries for later sessions.
8. Run `./scripts/run_test_gates.sh completeness-check` only if execution changes gate definitions or test inventory classification wording.
9. Run `git diff --check`.
10. Stop. Do not fix production failures or expand into media parity implementation under GMAR-001.

Stop early if:

- the source docs or tests have materially changed so GMAR-001 no longer maps to the four-user text round-robin;
- the focused text proof fails after test-only assertion tightening;
- media docs cannot be reconciled without making a product or architecture decision.

## risks and edge cases

- The current text test may pass count checks while not explicitly asserting every recipient's exact sender identity; that is why the test-first tightening is part of this plan.
- Optional media tests can be green while still only proving descriptors or one completed receiver; the docs must not call that all-recipient media completion.
- Report 89 newly-added-member evidence is adjacent but not identical to existing-member all-recipient media parity.
- Simulator evidence can be stale or conflicting across docs; GMAR-001 should record the conflict instead of resolving media UI behavior.
- The dirty tree contains many unrelated modified/untracked files. The executor must not revert them and must report any failure that appears caused by unrelated in-flight work.

## exact tests and gates to run

Required:

```bash
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name '4 users: round-robin messaging'
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
git diff --check
```

Conditional:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Use the unqualified `groups` command only if `FLUTTER_DEVICE_ID=macos` is not valid in the executor environment. Run `completeness-check` only if gate classification or inventory docs change.

Optional supporting evidence, not closure for all-recipient media:

```bash
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members receive image, video, and voice descriptors'
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'newly-added discussion member sends image, video, and voice to existing members'
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart --plain-name 'new member receives only post-join text and media with descriptors'
```

Do not require simulator or Go media tests in GMAR-001. Those are evidence boundaries for later sessions unless the executor intentionally refreshes them as supporting context and records them as non-closing.

## known-failure interpretation

- A failure in the focused `4 users: round-robin messaging` command is a GMAR-001 blocker unless it is conclusively unrelated to the focused case setup. Do not mark GMAR-001 accepted if this proof is red.
- A `groups` gate failure outside `group_messaging_smoke_test.dart` must be recorded with the failing file/test and treated as either unrelated dirty-tree drift or a broader group regression. Do not hide it, but do not fix it under GMAR-001 unless it is caused by the test-only assertion change.
- The MD-014 `VideoThumbnailOverlay` simulator failure recorded in `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` is an existing media/UI residual. It blocks any claim that simulator media proof closes all-recipient media parity, but it does not block text fan-out mapping.
- Optional media direct suites may fail or remain unrun; that prevents only fresh supporting media evidence claims. It does not invalidate a green focused text proof.
- Existing Go or relay media authorization failures are not GMAR-001 blockers unless the execution plan unexpectedly uses those commands as evidence.

## done criteria

- The intended GMAR-001 execution has no production-code diff.
- The focused four-user text proof passed, or GMAR-001 is explicitly blocked/partial with the exact failing command and reason.
- Any test-only assertion tightening is limited to `group_messaging_smoke_test.dart` and proves all four participants' incoming sender/text identity.
- The Report 90 docs and ledger distinguish text fan-out evidence from media all-recipient gaps.
- No descriptor-only, one-recipient, newly-added-only, sender-side-only, optional-only, or failing simulator evidence is used to close GMAR-002 through GMAR-004 scope.
- Required commands and any known failures are recorded exactly.

## scope guard

Do not:

- edit `lib/`, `go-mknoon/`, or `go-relay-server/` production code;
- add media fan-out/download/render tests in GMAR-001;
- promote optional/manual media tests into named gates;
- rewrite Report 89;
- claim announcement sender-role parity beyond the current admin-only contract;
- repair simulator `VideoThumbnailOverlay` failures;
- reclassify full program status as closed.

Overengineering in this session would be creating new media fixtures, new fake-network harnesses, new gate categories, or new closure architecture instead of recording the current evidence boundary.

## accepted differences / intentionally out of scope

- Existing text fan-out evidence can close only the text complaint shape, not media parity.
- Existing `group_media_fanout_test.dart` descriptor evidence is valuable, but completed download/render parity for at least two eligible non-sender recipients stays GMAR-002/GMAR-004 scope.
- Report 89 newly-added-member media coverage remains supporting evidence; Report 90 still needs all-recipient and non-creator/existing-member media parity.
- Announcement reader evidence remains governed by current admin-only announcement policy and should not be generalized to writer-role announcement media.
- Real device/TestFlight, broader paired-simulator, process-kill restart, relay outage breadth, and full media recovery UI breadth remain outside GMAR-001.

## dependency impact

- GMAR-002 should use GMAR-001's media boundary map to avoid treating descriptor-only or one-recipient evidence as completed all-recipient media parity.
- GMAR-003 should use the text fan-out result and Report 89 map to separate newly-added/non-creator media parity from already-covered text participation.
- GMAR-004 depends on this map to know which simulator/UI media claims are still residual.
- GMAR-005 must not run final acceptance until GMAR-001 is accepted, stale/already-covered with concrete proof, accepted with explicit follow-up, or truthfully blocked.

If GMAR-001 becomes blocked because the text proof fails, later sessions may still implement media work, but final program closure must keep the text regression open until a production-fix session resolves it.

## Reviewer Findings

Sufficiency: sufficient as-is.

- Missing files, tests, regressions, or gates: none structurally. The plan names the source docs, current test files, optional media evidence files, `groups`, conditional `completeness-check`, and `git diff --check`.
- Stale or incorrect assumptions: none found. The plan explicitly treats current code/tests as stronger than prose and notes the current text test's narrower assertion shape.
- Overengineering: none. The only potential test change is a narrow assertion tightening inside the existing four-user text case.
- Decomposition: sufficient. GMAR-001 stops at text proof plus evidence mapping and does not absorb GMAR-002 through GMAR-004 media work.
- Minimum needed to execute safely: keep the production-code stop rule, run the focused text proof, and avoid using descriptor-only media evidence as closure.

## Arbiter Decision

Structural blockers: none.

Incremental details intentionally deferred:

- The executor may choose not to rerun optional media direct suites if inspection is enough to map the boundary; in that case, do not claim fresh media pass evidence.
- `FLUTTER_DEVICE_ID=macos` may be replaced with the actual available local target for the `groups` gate, with the exact command recorded.

Accepted differences:

- GMAR-001 can be execution-ready while still classified `evidence-gated`; readiness applies to the plan, not to media closure.
- Report 89 simulator and newly-added-member media evidence remains supporting context, not all-recipient media closure.

Final arbiter verdict: execution-ready for the scoped GMAR-001 plan. No production implementation is authorized by this plan.
