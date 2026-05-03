# GMAR-002 Plan - Existing-Member All-Recipient Media Download Parity

Status: execution-ready

## Planning Progress

- `2026-05-02 11:20:06 CEST` - Evidence Collector started. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`. Decision/blocker: source and breakdown paths match; `GMAR-001` is accepted and `GMAR-002` is the first pending runnable session. Next action: refresh current repo evidence for existing-member group media fan-out, fake bridge/network helpers, app media send/listener/download paths, and Go media integration coverage.
- `2026-05-02 11:23:35 CEST` - Evidence Collector completed / Planner started. Files inspected since last update: `test/features/groups/integration/group_media_fanout_test.dart`, `test/core/bridge/fake_bridge.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `test/shared/fakes/group_test_user.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/conversation/application/download_media_use_case.dart`, `lib/features/conversation/application/upload_media_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `go-mknoon/integration/media_test.go`, `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Decision/blocker: current evidence confirms the GMAR-002 gap is not closed; Flutter fan-out proves descriptors for Bob/Charlie but completed downloads for Bob only, while Go media integration proves only one authorized non-sender. Next action: draft the GMAR-002-only execution plan with regression-first tests, closure bar, scope guard, and verification contract.
- `2026-05-02 11:25:14 CEST` - Planner completed / Reviewer started. Files inspected since last update: no new files; this update writes the doc-scoped draft from the collected evidence. Decision/blocker: draft is limited to existing-member image/video/voice download parity, two authorized non-sender blob downloads, outsider rejection, and one-recipient-failure detection. Next action: review for missing gates, stale assumptions, and scope drift into GMAR-003 or GMAR-004.
- `2026-05-02 11:27:05 CEST` - Reviewer completed / Arbiter started. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-002-plan.md`. Decision/blocker: reviewer found the plan sufficient with adjustments; one-recipient-failure proof is now mandatory and the focused Flutter command is tied to a required stable test name. Next action: classify reviewer findings and either stop or identify any remaining structural blocker.
- `2026-05-02 11:27:52 CEST` - Arbiter completed. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-002-plan.md`. Decision/blocker: no structural blockers remain after the reviewer adjustments; incremental details are documented below and accepted differences stay out of scope. Next action: execute GMAR-002 through the execution/QA workflow when requested.

## real scope

GMAR-002 covers existing active group members only. One active sender sends image, video, and voice media to a discussion group with at least two eligible non-sender recipients. Every eligible non-sender must receive exactly one incoming row per sent media message with the sender's message id, matching attachment id, mime/media type, dimensions, duration/waveform metadata where applicable, `downloadStatus == 'done'`, and a non-null local path after the app-layer download path runs.

This session also covers relay/blob authorization proof for group media: at least two authorized non-sender peers independently download the same group blob, and an outsider that is not in `allowedPeers` remains rejected.

This session does not cover newly-added-member fan-out, non-creator/new-member send scope, UI render/playback affordances, conversation reopen preservation, retry UX, offline recovery, duplicate live/inbox replay, or simulator/device-lab proof. Those remain GMAR-003 and GMAR-004 boundaries.

## closure bar

GMAR-002 is good enough when all of these are true in the current architecture:

- `group_media_fanout_test.dart` fails if Bob downloads image/video/voice but Charlie remains descriptor-only, missing a row, missing metadata, failed, pending, or without a local path while both are eligible.
- The same Flutter proof is symmetric: either non-sender recipient failing to download one of the three media types fails the focused suite.
- A one-recipient download failure is observable at the app-layer test boundary and cannot be hidden by another recipient's success.
- `go-mknoon/integration/media_test.go` proves two authorized non-sender members can independently download the same group blob and the outsider rejection still holds.
- No GMAR-002 closure wording claims UI preview/playback, reopen, retry, new-member, non-creator, or final full-suite acceptance.

## source of truth

Current code and tests are the primary source if prose disagrees. The active contract for this session is:

- `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `go-mknoon/integration/media_test.go`

`test-gate-definitions.md` controls named gate classification. The source doc and breakdown control GMAR scope. The current code/test behavior controls whether implementation is needed after tests are strengthened.

## session classification

`implementation-ready`

The required change may end as test/evidence tightening only if the current implementation already satisfies the stronger all-recipient download assertions. It remains implementation-ready because the current accepted evidence is insufficient: Charlie is explicitly allowed to be descriptor-only in the existing Alice-send test, and the Go relay proof has only one non-sender downloader.

## exact problem statement

The repo currently allows a green-looking group media fan-out path where Bob downloads Alice's image/video/voice, while Charlie is only required to have descriptors. That leaves the reported failure shape open: one eligible member can miss completed media that another member receives. The Go media integration similarly proves one authorized non-sender plus sender persistence and outsider rejection, but not two independent authorized non-sender downloads.

User-visible behavior that must improve: existing eligible group recipients should not silently diverge at the media download layer. What must stay unchanged: sender-side success semantics, group membership authorization, removed-member exclusion, unsupported media rejection, integrity rejection, no-backfill policy, and optional/manual gate classification unless a test file is added or reclassified.

## files and repos to inspect next

Production and helper files:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`

Direct tests and docs:

- `test/features/groups/integration/group_media_fanout_test.dart`
- `go-mknoon/integration/media_test.go`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## existing tests covering this area

`group_media_fanout_test.dart` currently has:

- Existing-member Alice-send image/video/voice fan-out. Bob and Charlie both receive incoming rows with sender message ids and attachment metadata, but only Bob is required to download. Charlie can remain descriptor-only.
- Oversized fake-network media rejection before store/download.
- Removed-member exclusion for future media descriptors/downloads.
- Tampered fake-network media integrity failure before `done`.
- Newly-added-member media send fan-out, which belongs to GMAR-003 scope and currently also downloads only one of two receivers.

`group_conversation_wired.dart` gathers current group members as `allowedPeers` for ordinary media and voice uploads. `send_group_message_use_case.dart` sends media descriptors in live publish and durable inbox replay payloads, and `group_message_listener.dart` auto-downloads pending incoming attachments through `downloadMedia`.

`go-mknoon/integration/media_test.go` currently proves one group media downloader that is not the sender, then sender download persistence, then outsider rejection. `TestRelayGroupMediaVoiceNote` proves one authorized non-sender voice download.

## regression/tests to add first

Add or strengthen regression coverage before production edits:

1. In `group_media_fanout_test.dart`, strengthen the existing Alice-send image/video/voice case so both Bob and Charlie must complete all three downloads. The test should wait for both users, require each bridge to record exactly three `media:download` calls, and call `expectSingleAttachment(... expectDownloaded: true)` for every media type and every eligible non-sender.
2. Rename the strengthened test to `discussion members independently download image, video, and voice for every eligible recipient` so the focused verification command is stable.
3. Add a focused app-layer one-recipient-failure proof: Bob's download bridge succeeds, Charlie's download bridge fails one media download, and the test asserts Charlie's attachment is failed/non-done while Bob remains done. This is not UI retry scope; it only proves the test boundary can detect per-recipient divergence. If this cannot be done without crossing into UI/retry behavior, record a GMAR-002 planning/implementation blocker instead of silently dropping the proof.
4. In `go-mknoon/integration/media_test.go`, extend `TestRelayGroupMediaUploadDownload` so two authorized non-sender nodes independently download the same group blob and an outsider still fails. Keep `TestRelayGroupMediaVoiceNote` as the voice-specific smoke unless the executor finds the same two-non-sender gap should be mirrored there with minimal duplication.

If these tests pass on current production code, stop and do not make production changes.

## step-by-step implementation plan

1. Re-read the current diff for the files to be touched. Preserve unrelated dirty work and do not normalize broad formatting.
2. Update `group_media_fanout_test.dart` first. Prefer local helper changes in the test file over shared fake changes. Make the existing Bob/Charlie assertions symmetric for row identity, attachment metadata, completed download status, local path, and exact download-call counts.
3. Add a local failing-download bridge/helper for the one-recipient-failure detection test. Keep it in `group_media_fanout_test.dart` unless another existing fake already supports this cleanly.
4. Run the focused Flutter test. If it passes, treat GMAR-002 Flutter app behavior as already covered after evidence tightening and skip production edits.
5. If the focused Flutter test fails for real behavior, fix the smallest responsible seam only. Candidate seams are incoming media persistence in `handle_incoming_group_message_use_case.dart`, listener auto-download scheduling in `group_message_listener.dart`, download status/local-path persistence in `download_media_use_case.dart`, group media upload descriptor creation in `upload_media_use_case.dart`, and allowed peer propagation from `group_conversation_wired.dart` / `send_group_message_use_case.dart`. Stop if the failure is only a test race; tighten waits/helpers instead of changing production behavior.
6. Extend `go-mknoon/integration/media_test.go` with a second authorized non-sender node in `TestRelayGroupMediaUploadDownload`. Verify both downloaded byte-for-byte contents match the upload and the outsider still receives an error.
7. Run required verification. If Go integration is skipped because relay prerequisites are unavailable, record the exact skip/blocker; do not count it as passing two-non-sender proof.
8. Update GMAR-002 evidence docs after implementation/verification: source doc session evidence, this breakdown ledger, group discussion closure reference, and Group Chat test inventory. Update `test-gate-definitions.md` only if a new test file is added or classification changes.

## risks and edge cases

- Listener auto-download is fire-and-forget; tests need deterministic waits for both recipients to avoid false descriptor-only passes or timing flakes.
- A shared blob id can make a single recipient's successful download look like global success if assertions only inspect sender-side state or one recipient. Assertions must inspect each recipient's own repository and bridge log.
- Group media integrity checks use encrypted relay bytes and decrypt into plaintext. The fake download bridge must write bytes matching the attachment content hash, or the test will intentionally fail with integrity status.
- A relay integration skip from `SKIP_RELAY_TESTS` or unreachable relay is an infrastructure blocker for Go proof, not acceptance evidence.
- Existing optional/manual media tests are outside the frozen `groups` gate; the named gate can be green while GMAR-002 remains unproven unless the direct suite passes.

## exact tests and gates to run

Required focused Flutter proof:

```bash
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'
```

Required full direct Flutter suite:

```bash
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
```

Required named group gate if any shared group send/listener/download behavior changes, and recommended even for test-only closure:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Required Go proof when `go-mknoon/integration/media_test.go` is changed:

```bash
cd go-mknoon && go test -tags integration ./integration -run 'TestRelayGroupMediaUploadDownload|TestRelayGroupMediaVoiceNote' -count=1 -v
```

Required cleanliness check:

```bash
git diff --check
```

Conditional gate if a new test file is added, an optional/manual suite is reclassified, or `Test-Flight-Improv/test-gate-definitions.md` is changed:

```bash
./scripts/run_test_gates.sh completeness-check
```

GMAR-005, not GMAR-002, owns `./scripts/run_test_gates.sh all` and simulator media suites.

## known-failure interpretation

There are no accepted failures for the focused GMAR-002 Flutter direct suite. Any failure in `group_media_fanout_test.dart` after the GMAR-002 test changes is a GMAR-002 blocker unless it is clearly an unrelated pre-existing test in the same file, in which case record the exact failing test and reason.

If the Go integration command skips because `SKIP_RELAY_TESTS` is set or the configured relay is unreachable, record the exact skip line and leave Go proof blocked; do not classify the two-non-sender download proof as accepted. Existing simulator failures around `VideoThumbnailOverlay` belong to GMAR-004 and must not block GMAR-002 unless this session touches simulator/UI code.

The shared worktree is dirty. Unrelated failures from files outside the touched GMAR-002 scope must be recorded with exact commands and not treated as caused by GMAR-002 without evidence.

## done criteria

- The GMAR-002 plan remains limited to existing-member media download parity and Go blob authorization proof.
- The strengthened Flutter direct suite proves two eligible non-sender recipients complete image/video/voice downloads and fails on either recipient's divergence.
- The Go media integration proves two authorized non-sender downloads of the same group blob and outsider rejection, or records an exact relay blocker.
- Required verification commands are run or truthfully blocked with exact output.
- Source doc, breakdown ledger, closure reference, and inventory are updated with GMAR-002 evidence without closing GMAR-003, GMAR-004, or GMAR-005.

## scope guard

Do not implement GMAR-003 new-member, newly-added sender, non-creator parity, no-backfill, removed-member expansion, or pre-join history behavior here.

Do not implement GMAR-004 UI render/playback/reopen/retry/offline/duplicate/simulator behavior here.

Do not change group cryptography, media storage architecture, relay authorization model, gate membership, or product policy unless a GMAR-002 regression test proves the current seam cannot satisfy existing-member all-recipient download parity. Overengineering includes adding a new delivery abstraction, broad retry system, new simulator harness, or full-suite closure machinery in this session.

## accepted differences / intentionally out of scope

- Completed host/app-layer download is accepted for GMAR-002; visible image preview, video playback affordance, voice playback affordance, and reopen preservation remain GMAR-004.
- Existing-member Alice-send parity is accepted for GMAR-002; newly-added multiple recipients and non-creator/new-member send parity remain GMAR-003.
- The optional/manual classification of `group_media_fanout_test.dart` is accepted for this session unless a later acceptance session changes gate policy.
- Sender-side outgoing attachments are not equivalent to non-sender recipient downloads and must not be counted as closure.

## dependency impact

GMAR-003 may reuse stricter helpers or fixtures from `group_media_fanout_test.dart`, but it must not inherit GMAR-002 closure for new-member/non-creator scope. GMAR-004 may rely on GMAR-002's stable downloaded attachment state before proving UI render/reopen/retry behavior. GMAR-005 must not run final acceptance until GMAR-002, GMAR-003, and GMAR-004 are accepted, stale/already-covered with evidence, or truthfully blocked.

If GMAR-002 finds production changes are needed in shared media send/listener/download code, GMAR-003 and GMAR-004 plans should refresh evidence before execution because shared behavior may have changed.

## reviewer pass

Sufficiency: sufficient with adjustments; the adjustments have been applied in this revision.

Missing files/tests/gates: the draft had the right files and gates, but the focused Flutter command assumed a renamed test while the rename was only optional. The rename is now required. The draft also made one-recipient-failure proof conditional; that proof is now required unless implementation records an explicit blocker.

Stale or incorrect assumptions: no stale source-of-truth issue found. The plan correctly treats current code/tests as stronger than stale prose and keeps the optional/manual suite classification separate from closure evidence.

Overengineering: none found. The plan prefers local test helpers and production edits only if strengthened regressions fail.

Decomposition: sufficient. GMAR-003 new-member/non-creator scope and GMAR-004 UI/simulator/reopen/retry scope are explicit non-goals.

Minimum needed: keep the regression-first order, run the direct Flutter and Go proofs, and update only GMAR-002 evidence docs after verification.

## arbiter decision

Structural blockers: none remaining.

Incremental details: the executor may add small local helper names or assertion wording as needed, but must preserve the required all-recipient download assertions, mandatory one-recipient-failure proof, and Go two-non-sender proof.

Accepted differences: UI render/playback/reopen/retry/simulator work remains GMAR-004; newly-added-member and non-creator media parity remains GMAR-003; final full-suite closure remains GMAR-005; optional/manual direct-suite classification remains unchanged unless a later acceptance session changes gate policy.

Stop rule: no new structural blocker remains, so planning stops here and the artifact is execution-ready.

## arbiter stop rule

If reviewer finds no structural blocker, arbiter stops after classification and the plan moves to `execution-ready`. If reviewer finds a structural blocker, patch this plan once, then run one final reviewer pass and one final arbiter pass. Do not loop on incremental details, and do not reopen GMAR-003 or GMAR-004 work as part of GMAR-002.

## Execution Progress

- `2026-05-02 11:29:42 CEST` - Phase: controller contract extraction. Files inspected: `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-002-plan.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and current scoped diffs/status. Decision/blocker: contract is execution-ready and limited to GMAR-002 existing-member all-recipient media download parity, mandatory one-recipient-failure detection, Go two-authorized-non-sender blob download proof plus outsider rejection, and GMAR-002 evidence docs; GMAR-003, GMAR-004, GMAR-005, final full suite, and unrelated dirty-tree edits are out of scope. Required verification: focused Flutter proof, full direct Flutter suite, Go integration command if `go-mknoon/integration/media_test.go` changes or exact blocker, `groups` gate recommended and required if shared behavior changes, `git diff --check`, and `completeness-check` only if classification docs or new test files change. Next action: spawn fresh Executor agent with the scoped plan and required model settings.
- `2026-05-02 11:30:34 CEST` - Phase: Executor spawned/running. Files touched: this plan progress section only. Command currently running: spawned Executor agent `019de806-6a9e-78b0-8eae-84501b46b4da` (`Hubble`) with `model=gpt-5.5`, `reasoning_effort=xhigh`. Decision/blocker: Executor owns the first implementation pass and required verification/doc evidence for GMAR-002 only. Next action: wait bounded interval for Executor result, then inspect assigned file evidence before spawning QA.
- `2026-05-02 11:31:07 CEST` - Phase: Executor running. Files inspected: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-002-plan.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, and repository status. Files touched: this plan progress section only. Decision/blocker: contract extracted for GMAR-002 only; worktree is heavily dirty, so each scoped file diff will be inspected before edits. Next action: inspect scoped Flutter/Go test files and docs before strengthening regressions.
- `2026-05-02 11:32:46 CEST` - Phase: scoped file inspection. Files inspected: `test/features/groups/integration/group_media_fanout_test.dart`, `go-mknoon/integration/media_test.go`, `test/core/bridge/fake_bridge.dart`, `lib/features/conversation/application/download_media_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, and current diffs for the touched test files/docs. Decision/blocker: Flutter and Go target test files have no current diff; closure reference and inventory already have unrelated dirty edits, so later doc updates must append/narrow without rewriting those sections. Next action: edit Flutter regression first, then run focused proof.
- `2026-05-02 11:34:36 CEST` - Phase: Flutter regression edit completed / focused proof starting. Files touched: `test/features/groups/integration/group_media_fanout_test.dart` and this plan progress section. Command currently running: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'`. Decision/blocker: strengthened the existing focused test name and all-recipient assertions, and added a local one-recipient failure bridge/test in the same suite. Next action: run focused Flutter proof and decide whether production code is needed.
- `2026-05-02 11:35:21 CEST` - Phase: focused Flutter proof failed / production seam inspection. Files inspected: `lib/features/conversation/application/download_media_use_case.dart` diff before edit (clean). Command finished: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'` failed because Charlie recorded no independent `media:download` calls after Bob's in-flight download satisfied the shared `groupId|blobId|mime` key. Decision/blocker: this is a GMAR-002 download boundary bug in the in-flight dedupe key; next action is the smallest production change to scope in-flight downloads by local bridge/repository/file-manager owner before rerunning the focused proof.
- `2026-05-02 11:35:43 CEST` - Phase: production seam patched / focused proof restarting. Files touched: `lib/features/conversation/application/download_media_use_case.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, and this plan progress section. Command currently running: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'`. Decision/blocker: in-flight media downloads are now scoped by bridge, media attachment repository, and media file manager identity before `groupId|blobId|mime`, preserving same-owner dedupe while preventing cross-recipient local persistence bleed. Next action: rerun focused proof.
- `2026-05-02 11:36:53 CEST` - Phase: second focused Flutter proof failed / test fixture seam patching. Files inspected/touched: `test/features/groups/integration/group_media_fanout_test.dart`, `lib/features/conversation/application/download_media_use_case.dart`, and this plan progress section. Command finished: focused Flutter proof failed again after independent downloads began because Bob and Charlie's fake media managers wrote the same blob paths under one shared temp root and raced during decrypt/rename. Decision/blocker: production in-flight fix is still needed; next action is test-only scoping of fake media roots per simulated recipient before rerunning the focused proof.
- `2026-05-02 11:38:17 CEST` - Phase: first Executor no-final recovery decision. Files inspected: `test/features/groups/integration/group_media_fanout_test.dart`, `lib/features/conversation/application/download_media_use_case.dart`, scoped status/diffs, and this progress section. Command finished: spawned Executor `019de806-6a9e-78b0-8eae-84501b46b4da` was closed after the allowed bounded waits with previous status `running` and no final result. Decision/blocker: visible partial landing exists for Flutter tests and the in-flight download owner key, but Go proof, final required verification, and GMAR-002 evidence docs are not complete. Next action: spawn a fresh Executor recovery pass with the new repo evidence; if that pass fails to produce trustworthy completion evidence, stop blocked instead of relaunching again.
- `2026-05-02 11:37:28 CEST` - Phase: test fixture seam patched / focused proof restarting. Files touched: `test/features/groups/integration/group_media_fanout_test.dart` and this plan progress section. Command currently running: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'`. Decision/blocker: added a local scoped fake media manager for multi-recipient same-blob tests so simulated recipients use separate temp roots like separate app installs. Next action: rerun focused proof.
- `2026-05-02 11:39:01 CEST` - Phase: fresh Executor recovery pass spawned/running. Files touched: this plan progress section only. Command currently running: spawned Executor recovery agent `019de80e-2ed8-75c3-87e6-ea3876155f2d` (`Epicurus`) with `model=gpt-5.5`, `reasoning_effort=xhigh`. Decision/blocker: recovery pass has explicit visible partial-state evidence and owns finishing Flutter verification, Go two-non-sender proof, required group gate because production download behavior changed, `git diff --check`, and GMAR-002 evidence docs. Next action: wait bounded interval for recovery result; do not relaunch another Executor if this pass does not return trustworthy evidence.
- `2026-05-02 11:39:25 CEST` - Phase: Executor recovery pass local start / contract refresh. Files inspected: `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, this plan, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, scoped `git status --short`, and current diffs for `test/features/groups/integration/group_media_fanout_test.dart` and `lib/features/conversation/application/download_media_use_case.dart`. Files touched: this plan progress section only. Decision/blocker: visible partial landing is limited to GMAR-002 Flutter strengthening plus production in-flight download owner scoping; Go integration proof and evidence docs remain incomplete. Next action: inspect the landed Flutter test/helper code and Go media integration before running the required focused proof.
- `2026-05-02 11:39:52 CEST` - Phase: focused Flutter proof starting. Files inspected: `test/features/groups/integration/group_media_fanout_test.dart`, `lib/features/conversation/application/download_media_use_case.dart`, and `go-mknoon/integration/media_test.go`. Command currently running: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'`. Decision/blocker: Flutter partial landing appears coherent enough to verify before further edits; Go integration still needs two authorized non-sender recipients. Next action: capture focused proof result.
- `2026-05-02 11:40:19 CEST` - Phase: focused Flutter proof finished / Go regression edit starting. Files touched: this plan progress section only since last entry. Command finished: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'` passed with `00:00 +1: All tests passed!`. Decision/blocker: focused existing-member all-recipient image/video/voice download proof is green with the partial production/test landing. Next action: extend `go-mknoon/integration/media_test.go` so two authorized non-sender members independently download the same group blob and outsider rejection still holds.
- `2026-05-02 11:41:06 CEST` - Phase: Go regression edit finished / full direct Flutter suite starting. Files touched: `go-mknoon/integration/media_test.go` and this plan progress section. Command currently running: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart`. Decision/blocker: `TestRelayGroupMediaUploadDownload` now includes sender A, authorized non-senders B and D, and outsider C; B and D both assert relay mime/size and byte-for-byte blob content, while outsider rejection remains. Next action: capture full direct Flutter suite result.
- `2026-05-02 11:41:29 CEST` - Phase: full direct Flutter suite finished / Go integration proof starting. Files touched: this plan progress section only since last entry. Command finished: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed with `00:00 +6: All tests passed!`. Command currently running from `go-mknoon`: `go test -tags integration ./integration -run 'TestRelayGroupMediaUploadDownload|TestRelayGroupMediaVoiceNote' -count=1 -v`. Decision/blocker: direct Flutter GMAR-002 suite is green including the one-recipient-failure proof. Next action: capture Go relay proof result or exact fixture blocker.
- `2026-05-02 11:42:04 CEST` - Phase: Go integration proof finished / required group gate starting. Files touched: this plan progress section only since last entry. Command finished from `go-mknoon`: `go test -tags integration ./integration -run 'TestRelayGroupMediaUploadDownload|TestRelayGroupMediaVoiceNote' -count=1 -v` passed with `PASS` / `ok github.com/mknoon/go-mknoon/integration 1.815s`; key proof lines include `member B download: mime=image/jpeg size=4096`, `member D download: mime=image/jpeg size=4096`, `member D download verified — second authorized non-sender data matches`, and `outsider correctly rejected: download failed: not authorized`. Command currently running: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. Decision/blocker: relay fixture was available and GMAR-002 Go proof is green. Next action: capture required group gate result.
- `2026-05-02 11:42:49 CEST` - Phase: required group gate finished / diff check starting. Files touched: this plan progress section only since last entry. Command finished: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:12 +103: All tests passed!`. Command currently running: `git diff --check`. Decision/blocker: production download change has required group-gate coverage. Next action: capture whitespace check result before GMAR-002 evidence doc updates.
- `2026-05-02 11:43:07 CEST` - Phase: first diff check finished / evidence docs inspection starting. Files touched: this plan progress section only since last entry. Command finished: `git diff --check` passed with no output. Files being inspected next: `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Decision/blocker: verification is known and green so evidence docs can now be updated; `completeness-check` remains not required because no new test file, suite reclassification, or `test-gate-definitions.md` change occurred. Next action: update GMAR-002 evidence docs without closing GMAR-003, GMAR-004, or GMAR-005.
- `2026-05-02 11:46:13 CEST` - Phase: evidence docs updated / final diff check starting. Files touched: `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and this plan progress section. Command currently running: `git diff --check`. Decision/blocker: docs now record GMAR-002 as accepted for existing-member app-layer image/video/voice download parity, one-recipient failure detection, and Go two-authorized-non-sender blob proof only; GMAR-003, GMAR-004, and GMAR-005 remain pending. Next action: capture final whitespace check and then do local QA sufficiency review.
- `2026-05-02 11:46:53 CEST` - Phase: local QA fix pass starting. Files inspected/touched: `lib/features/conversation/application/download_media_use_case.dart` and this plan progress section. Command finished before this entry: `git diff --check` passed with no output. Decision/blocker: local QA found the in-flight owner key should use object-identity equality instead of relying only on stringified `identityHashCode` values. Next action: replace the string key with a private object key that compares bridge/repository/file-manager by identity and then rerun required Flutter proofs and group gate.
- `2026-05-02 11:47:23 CEST` - Phase: local QA fix patched / focused Flutter proof restarting. Files touched: `lib/features/conversation/application/download_media_use_case.dart`, `test/features/groups/integration/group_media_fanout_test.dart` (format command reported 0 changed), and this plan progress section. Command currently running: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'`. Decision/blocker: production in-flight key now compares bridge, repository, and file manager by object identity while keeping contact/blob/mime value equality. Next action: rerun Flutter focused proof, full direct suite, group gate, and final diff check against the final code/doc state.
- `2026-05-02 11:47:44 CEST` - Phase: focused Flutter proof finished after local QA fix / full direct suite restarting. Files touched: this plan progress section only since last entry. Command finished: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'discussion members independently download image, video, and voice for every eligible recipient'` passed with `00:00 +1: All tests passed!`. Command currently running: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart`. Decision/blocker: focused proof remains green after replacing the in-flight key implementation. Next action: capture full direct suite result.
- `2026-05-02 11:48:08 CEST` - Phase: full direct Flutter suite finished after local QA fix / group gate restarting. Files touched: this plan progress section only since last entry. Command finished: `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed with `00:00 +6: All tests passed!`. Command currently running: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. Decision/blocker: direct GMAR-002 suite remains green after the final production key change. Next action: capture group gate result.
- `2026-05-02 11:48:38 CEST` - Phase: group gate finished after local QA fix / final diff check starting. Files touched: this plan progress section only since last entry. Command finished: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:08 +103: All tests passed!`. Command currently running: `git diff --check`. Decision/blocker: required named gate remains green against final production code and docs. Next action: capture final diff check and complete local QA sufficiency review.
- `2026-05-02 11:49:08 CEST` - Phase: final diff check and local QA completed. Files inspected: scoped diffs for `lib/features/conversation/application/download_media_use_case.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `go-mknoon/integration/media_test.go`, this plan, source doc, breakdown, closure reference, and Group Chat inventory; full `git status --short` was also inspected and remains heavily dirty with many unrelated files. Command finished: `git diff --check` passed with no output. Decision/blocker: no GMAR-002 blocking issues remain; required focused Flutter proof, full direct Flutter suite, Go integration proof, group gate, and whitespace check all passed. `./scripts/run_test_gates.sh completeness-check` was not run because the condition was not met: no new test file, no suite reclassification, and no `Test-Flight-Improv/test-gate-definitions.md` change. Final Executor recovery verdict: accepted for GMAR-002 existing-member app-layer image/video/voice download parity, one-recipient failure detection, and Go two-authorized-non-sender blob proof only; GMAR-003, GMAR-004, and GMAR-005 remain pending. Next action: return final Executor recovery summary.
- `2026-05-02 11:50:29 CEST` - Phase: QA Reviewer spawned/running. Files touched: this plan progress section only. Command currently running: spawned QA Reviewer agent `019de819-2539-7d22-9065-bd5522722564` (`Hegel`) with `model=gpt-5.5`, `reasoning_effort=xhigh`. Decision/blocker: QA owns strict sufficiency review of scope adherence, changed diffs, required test/gate evidence, and GMAR-002 evidence docs; QA must not edit code. Next action: wait bounded interval for QA result and run one fix pass only if QA reports blocking issues.
- `2026-05-02 11:53:25 CEST` - Phase: fresh QA Reviewer started. Files inspected: `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, this plan, scoped status/diffs, `lib/features/conversation/application/download_media_use_case.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `go-mknoon/integration/media_test.go`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Commands run: `git status --short`, scoped `git diff`, `sed`, and `rg` inspections only; no direct test, named gate, final full suite, or `run_test_gates.sh all` rerun. Decision/blocker: review is limited to GMAR-002 sufficiency and evidence verification. Next action: classify blocking issues or non-blocking follow-ups.
- `2026-05-02 11:55:00 CEST` - Phase: fresh QA Reviewer completed. Files inspected: same scoped GMAR-002 code/test/doc files plus `Test-Flight-Improv/test-gate-definitions.md` status. Commands run: lightweight file/diff inspections and `git diff --check` after the QA progress update, which passed with no output. Decision/blocker: no blocking GMAR-002 sufficiency issues found; focused Flutter, full direct Flutter, Go integration, groups gate, and whitespace-check evidence are recorded in this plan; `completeness-check` is correctly not required because no new test file, suite reclassification, or `test-gate-definitions.md` change occurred. Scope decision: GMAR-003, GMAR-004, and GMAR-005 remain open, and no final full-suite closure is claimed. Next action: report QA verdict `accepted`.
- `2026-05-02 11:55:05 CEST` - Phase: controller final verdict written. Files inspected: scoped status and final QA verdict. Files touched: this plan progress section only. Decision/blocker: final session verdict is `accepted`; spawned-agent isolation was used, the first Executor was closed as no-final after bounded waits, a fresh Executor recovery pass completed the implementation/evidence, and a separate fresh QA Reviewer accepted with no blocking issues or non-blocking follow-ups. Next action: return compact final execution summary.
