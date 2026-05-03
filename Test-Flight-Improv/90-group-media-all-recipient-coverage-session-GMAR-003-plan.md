Status: execution-ready

# GMAR-003 Plan - Newly-Added and Non-Creator Media Parity

## Planning Progress

- `2026-05-02 12:24:02 CEST` - Arbiter completed. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md`. Decision/blocker: no structural blockers remain; mandatory pre-join media no-backfill, newly-added sender parity, existing non-creator sender parity, full direct suites, required `groups` gate, and GMAR-004/GMAR-005 boundaries are explicit. Next action: hand off to execution when requested.
- `2026-05-02 12:21:36 CEST` - Reviewer completed / Arbiter started. Files inspected since last update: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md`. Decision/blocker: reviewer found the plan sufficient with adjustments; pre-join media no-backfill and existing non-creator sender media parity are now mandatory proofs rather than optional executor judgment. Next action: classify findings and confirm whether any structural blocker remains.
- `2026-05-02 12:17:10 CEST` - Planner completed / Reviewer started. Files inspected since last update: no new files; this update writes the GMAR-003-only draft from the collected evidence. Decision/blocker: draft stays limited to host/app-layer newly-added multi-recipient media parity, newly-added/existing non-creator sender media parity, no-backfill, sender/key/attachment metadata, and removed-member preservation. Next action: strict reviewer pass for missing regressions, stale assumptions, overreach into GMAR-004/005, and gate sufficiency.
- `2026-05-02 12:08:44 CEST` - Evidence Collector completed / Planner started. Files inspected since last update: `test/features/groups/integration/group_new_member_onboarding_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`, `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, scoped `git diff`. Decision/blocker: GMAR-003 gap remains real; current multi-add onboarding covers same text/epoch only, and the newly-added sender media test still downloads only Alice while Charlie may remain descriptor-only. Next action: draft the execution-safe plan with direct regressions, strict scope guard, and verification contract.
- `2026-05-02 12:01:38 CEST` - Evidence Collector started. Files inspected since last update: `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-001-plan.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-002-plan.md`, `git status --short`. Decision/blocker: source and breakdown paths match; `GMAR-001` and `GMAR-002` are accepted, while `GMAR-003` remains pending and scoped to newly-added/non-creator media parity. Next action: inspect current GMAR-003-relevant tests, app seams, Report 89 evidence, gate definitions, closure references, and inventory before drafting.

## real scope

GMAR-003 covers host/app-layer discussion-group media parity at the membership boundary.

In scope:

- Multiple newly-added members, represented by Bob and Charlie, receive the same eligible post-join image, video, and voice rows after their memberships are active.
- Those newly-added members independently complete the app-layer media download path for the same post-join blobs, with matching message ids, sender identity, key epoch, attachment metadata, `downloadStatus == done`, non-null local paths, and exact per-recipient download calls.
- Newly-added members do not receive pre-join text, image, video, or voice history.
- A newly-added sender and a separate already-active non-creator sender can send image, video, and voice media after membership/bootstrap is active; the creator and every other eligible non-sender receive each row exactly once with correct sender identity, sender message id, key epoch, attachment metadata, completed download state, and no duplicates.
- Removed-member exclusion remains protected by the existing MD-011 media exclusion proof while GMAR-003 assertions tighten.

Out of scope:

- No simulator/device render, playback, conversation reopen, retry, offline recovery, duplicate live+inbox replay, or failed-media UI work. Those belong to GMAR-004.
- No final full-suite/gate reconciliation, `all` gate closure, or final program verdict. Those belong to GMAR-005.
- No announcement reader/writer policy changes.
- No media storage, codec, crypto, relay authorization, or transport architecture redesign.

## closure bar

GMAR-003 is good enough when:

- `group_new_member_onboarding_test.dart` fails if either newly-added Bob or newly-added Charlie misses any post-join image/video/voice row, remains descriptor-only where completion is expected, gets the wrong message id, key epoch, sender identity, or attachment metadata, duplicates a row, or receives pre-join text/media history.
- `group_media_fanout_test.dart` fails if media from a newly-added sender or an existing non-creator active sender reaches the creator but not another eligible member, reaches only one eligible recipient as a completed download, carries the wrong sender identity/message id/key epoch/metadata, or appears more than once for any eligible recipient.
- Existing removed-member exclusion remains covered by the direct MD-011 case in the full `group_media_fanout_test.dart` suite.
- Verification records green focused direct proofs, green full direct suites, a green `groups` gate, and `git diff --check`.
- Docs record only GMAR-003 host/app-layer parity and do not claim GMAR-004 visible simulator/reopen/retry/offline/duplicate behavior or GMAR-005 final acceptance.

## source of truth

Priority order on disagreement:

1. Current code and tests in this working tree.
2. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` for named gate membership.
3. `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md` for GMAR session scope and ordering.
4. `Test-Flight-Improv/90-group-media-all-recipient-coverage.md` for source cases and user-facing bug shape.
5. `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`, `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` for adjacent evidence boundaries.

Evidence facts collected:

- The Report 90 breakdown points to `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, lists GMAR-003 with source cases `GMAR-005`, `GMAR-006`, `GMAR-011`, `GMAR-012`, `GMAR-015`, and bug regression non-creator parity, and marks GMAR-001/GMAR-002 accepted.
- `group_new_member_onboarding_test.dart` currently proves one newly-added Bob receives post-join text/image/video/voice with completed downloads and no pre-join text, while its multi-add case proves Bob and Charlie receive the same post-add text/key epoch only.
- `group_media_fanout_test.dart` currently has GMAR-002 coverage for existing Bob/Charlie receiving Alice's image/video/voice with completed downloads, plus MD-011 removed-member future-media exclusion.
- The Report 89 new-member sender case in `group_media_fanout_test.dart` has Bob send image/video/voice after bootstrap and proves Alice downloads all three, but Charlie is still allowed to be descriptor-only through `expectDownloaded = receiver == alice`.
- `send_group_message_use_case.dart` builds recipient peer ids from current group members excluding the sender, pre-persists the sender row, carries media descriptors into live publish and inbox replay payloads, and stores the key epoch from the latest group key.
- `group_message_listener.dart` passes incoming media descriptors to `handleIncomingGroupMessage`, then auto-downloads pending incoming attachments through `downloadMedia`; `handleIncomingGroupMessage` rejects unknown/removed senders and persists incoming media attachments by message id.
- `GroupTestUser` and `FakeGroupPubSubNetwork` can simulate active membership, add/member broadcasts, removal, live publish fan-out, per-peer bridges, and per-peer media stores. Existing GMAR-002 `_ScopedMediaFileManager` evidence shows multi-recipient same-blob tests should use separate fake media roots to avoid shared temp-path races.
- `group_media_fanout_test.dart` and `group_new_member_onboarding_test.dart` are optional/manual direct suites, not frozen `groups` gate members. The `groups` gate covers membership/invite smoke through `group_membership_smoke_test.dart` and `invite_round_trip_test.dart`.

## session classification

`implementation-ready`

The session may end as tests/docs only if current production behavior already satisfies the stronger regressions. It remains implementation-ready because current evidence is insufficient and the stronger tests can expose real defects in recipient selection, listener auto-download, membership bootstrap, sender authorization, key epoch propagation, or fake fixture isolation.

## exact problem statement

The remaining GMAR-003 risk is that membership-boundary media parity can still be overclaimed:

- Multiple newly-added members may converge on group membership/key state and receive post-add text, while only one newly-added member has proven completed post-join media.
- A newly-added or non-creator sender may produce media rows for the creator while another eligible member remains descriptor-only, missing, duplicated, or carrying stale metadata.
- Tightening media parity must not backfill pre-join history or re-open removed-member delivery.

The user-visible behavior to protect is that every active eligible group participant sees the same eligible post-join media participation, regardless of whether the sender is the creator, a newly-added member, or another non-creator active member.

What must stay unchanged:

- No pre-join backfill.
- No removed-member future delivery.
- No sender identity or sender message id rewriting.
- No key epoch weakening.
- No announcement send-policy change.
- No UI/simulator closure claim from host descriptor/download tests.

## files and repos to inspect next

Direct tests to edit first:

- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/integration/group_media_fanout_test.dart`

Production/application files to inspect if strengthened tests fail:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`

Test helpers to inspect or touch only if needed:

- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/fake_media_file_manager.dart`

Docs to update after verification:

- `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md` only if reused Report 89 evidence is corrected or narrowed
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` if inventory rows are updated with GMAR-003 evidence
- `Test-Flight-Improv/test-gate-definitions.md` only if a new test file is added or suite classification changes

The worktree is heavily dirty. Executors must inspect scoped diffs before editing every file above and must preserve unrelated user/pipeline changes.

## existing tests covering this area

- `group_new_member_onboarding_test.dart`
  - Covers one newly-added Bob receiving only post-join text/image/video/voice with completed app-layer downloads.
  - Covers Bob and Charlie multi-add convergence for same post-add text, key epoch, latest key, and membership list.
  - Covers add/send boundary for text: staged unsubscribed Bob misses the racing message and receives the first post-subscription message exactly once.
  - Missing for GMAR-003: multiple newly-added members receiving the same post-join image/video/voice with completed downloads; no-backfill for pre-join media rows.
- `group_media_fanout_test.dart`
  - GMAR-002 now covers existing Bob and Charlie independently downloading creator Alice's image/video/voice, one-recipient failure visibility, and MD-011 removed-member future media exclusion.
  - Report 89 new-member sender case covers Bob sending image/video/voice after bootstrap, Alice and Charlie receiving exactly one row with Bob's sender message ids and metadata, Bob's outgoing attachments, and Alice completing three downloads.
  - Missing for GMAR-003: Charlie completing downloads in that new-member sender path; a separate existing non-creator active sender media path proving GMAR-011.
- `group_membership_smoke_test.dart` and `invite_round_trip_test.dart`
  - Covered by the `groups` gate and preserve membership/re-add/current-state behavior around joins and removals.
- Report 89 simulator/device evidence
  - Useful background for visible new-member media, but not closure for GMAR-003 host all-recipient app-layer parity and not a substitute for GMAR-004 visible simulator work.

## regression/tests to add first

Add or strengthen tests before production edits:

1. In `group_new_member_onboarding_test.dart`, add or rename a focused test to:

   `multiple newly-added members independently download the same post-join image, video, and voice without pre-join history`

   This test should:

   - create Alice, Bob, and Charlie with Bob/Charlie using download-writing bridges and separate scoped fake media roots;
   - send pre-join text plus pre-join image, video, and voice before Bob and Charlie are active; if the existing helper path cannot send pre-join media deterministically, record that exact blocker and do not claim GMAR-012 media no-backfill closure;
   - add Bob and Charlie, persist the latest key for both, start/subscribe/broadcast as required by the existing harness;
   - send post-join image, video, and voice from Alice;
   - assert Bob and Charlie each receive exactly one incoming row per post-join media message, with the sender message id, `senderPeerId`, `senderUsername`, `keyGeneration`, attachment id, MIME/media type, dimensions/duration/waveform, `downloadStatus == done`, non-null local path, and exactly three independent `media:download` calls each;
   - assert neither Bob nor Charlie has pre-join text/media rows, media attachments for pre-join message ids, pending downloads, or download calls for pre-join media.

2. In `group_media_fanout_test.dart`, strengthen the existing:

   `newly-added discussion member sends image, video, and voice to existing members`

   Rename it to a stable command name:

   `newly-added discussion member media reaches every eligible recipient`

   The strengthened test should require both Alice and Charlie to complete all three downloads from Bob, not only Alice. It should assert exact-once rows, Bob's sender peer id/username, Bob's sender message ids, key epoch, attachment metadata, completed download state/local paths, and exactly three download calls for each eligible non-sender recipient.

3. Add a focused existing non-creator sender parity proof in `group_media_fanout_test.dart`. Preferred stable name:

   `existing non-creator discussion member media reaches creator and every eligible recipient`

   Use an already-active non-creator sender such as Charlie after Bob is active. The creator Alice and the other eligible member Bob must receive image, video, and voice exactly once with correct sender identity, sender message ids, key epoch, metadata, completed downloads, and exact per-recipient download calls. This is a required GMAR-011 proof, not an optional helper refactor.

If the strengthened tests pass on current production code, stop and do not make production changes. If they fail, fix the smallest responsible seam only.

## step-by-step implementation plan

1. Reconfirm the dirty tree and inspect scoped diffs:

   ```bash
   git status --short
   git diff -- test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_media_fanout_test.dart
   ```

2. Implement regression-first test changes in `group_new_member_onboarding_test.dart`.
   - Prefer local test helpers over shared helper changes.
   - If a scoped media-root helper is needed, keep it local unless the same helper is clearly reused by both target test files without broad refactor churn.

3. Implement regression-first test changes in `group_media_fanout_test.dart`.
   - Reuse the GMAR-002 `_ScopedMediaFileManager`, `_DownloadWritingBridge`, `waitForDownloads`, `waitForDownloadedAttachments`, `expectSingleAttachment`, and outgoing attachment helpers where possible.
   - Keep test names stable so focused commands can target them.

4. Run the focused new-member multi-recipient media proof. If it fails, inspect whether the failure is fixture timing/path isolation or real membership/listener/download behavior.

5. Run the focused newly-added sender / non-creator sender media proof. If it fails, inspect whether recipient selection, current group membership, listener auto-download, `senderDeviceId`/transport binding, key epoch, or attachment persistence is wrong.

6. Only if focused tests fail for production reasons, patch the smallest application seam:
   - `send_group_message_use_case.dart` for recipient list, key epoch, message id, media descriptor, sender identity, or inbox payload issues;
   - `group_message_listener.dart` / `handle_incoming_group_message_use_case.dart` for incoming sender authorization, dedupe, media persistence, or auto-download scheduling issues;
   - `add_group_member_use_case.dart`, `accept_pending_group_invite_use_case.dart`, or `GroupTestUser` only if membership bootstrap state is genuinely wrong in the shipped path or test harness;
   - `download_media_use_case.dart` only if the GMAR-002 owner-key fix still fails for newly-added/non-creator per-recipient downloads.

7. Run full direct suites for both edited test files. This preserves adjacent no-backfill, add/send boundary, reaction/quote, existing-member parity, one-recipient failure, removed-member exclusion, oversized rejection, and tampered-media integrity cases.

8. Run the `groups` gate. It is required for GMAR-003 because the direct media suites are optional/manual and the named gate preserves the membership/invite smoke paths that this session depends on.

9. Update docs after verification:
   - Report 90 source doc: add GMAR-003 evidence and keep GMAR-004/GMAR-005 open.
   - Breakdown ledger: mark GMAR-003 accepted, blocked, or accepted with explicit follow-up based on exact evidence.
   - Group discussion closure reference and Group Chat inventory: update only if wording needs to reflect multi-new-member and non-creator all-recipient media parity.
   - Report 89 source doc only if the reused evidence wording is stale or overclaims descriptor-only completion.

10. Run `git diff --check`.

Stop early if:

- the focused GMAR-003 tests reveal current docs already cover this with exact multi-recipient completed-download evidence;
- pre-join media cannot be sent or asserted through the current host harness; record the exact blocker and leave GMAR-012 media no-backfill unaccepted rather than weakening the closure bar;
- a failure belongs to GMAR-004 visible simulator/reopen/retry/offline/duplicate behavior rather than host app-layer parity.

## risks and edge cases

- Shared fake media roots can create same-blob file path races between simulated recipients; use per-recipient scoped fake media roots.
- Fire-and-forget listener downloads need deterministic waits on each recipient's bridge log and repository state, not sender-side success.
- A test can pass row/descriptor assertions while leaving one recipient descriptor-only; completed-download assertions must be per recipient.
- A newly-added member can have a group row before subscription is effective; the add/send boundary must preserve the current no-backfill contract.
- Non-creator sender tests must assert creator receipt and other-member receipt, not just one eligible receiver.
- Removed-member protection can regress through recipient-list construction or group config sync; full `group_media_fanout_test.dart` keeps MD-011 in the required verification path.
- The existing dirty tree includes broad group send/listener/invite/drain edits; failures must be tied to scoped diffs before attributing them to GMAR-003.

## exact tests and gates to run

Required focused new-member receive proof:

```bash
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart --plain-name 'multiple newly-added members independently download the same post-join image, video, and voice without pre-join history'
```

Required focused newly-added sender proof after stable rename:

```bash
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'newly-added discussion member media reaches every eligible recipient'
```

Required focused existing non-creator sender proof:

```bash
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'existing non-creator discussion member media reaches creator and every eligible recipient'
```

Required full direct suites:

```bash
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart
```

Required named gate:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Required cleanliness check:

```bash
git diff --check
```

Conditional gate if a new test file is added, optional/manual suite classification changes, or `Test-Flight-Improv/test-gate-definitions.md` changes:

```bash
./scripts/run_test_gates.sh completeness-check
```

Do not run or require GMAR-004 simulator media suites or GMAR-005 `./scripts/run_test_gates.sh all` in this session.

## known-failure interpretation

There are no accepted failures for the focused GMAR-003 direct tests. Any failure in the new focused test names is a GMAR-003 blocker unless the executor proves it is a pre-existing unrelated test in the same file.

`group_media_fanout_test.dart` full-suite failures in existing GMAR-002 or MD-011 cases are blockers if this session touches shared media fan-out helpers, recipient selection, listener download behavior, or group media fixtures. A simulator `VideoThumbnailOverlay` failure is already documented as GMAR-004/MD-014 and must not block GMAR-003 unless this session changes presentation or simulator code, which it should not.

If `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` fails in a pre-existing unrelated case, record the exact failing test, current scoped diff, and why it is unrelated. Do not count a red `groups` gate as accepted without that evidence.

## done criteria

- The plan and execution remain limited to GMAR-003.
- Focused tests prove multiple newly-added recipients independently receive/download the same post-join image/video/voice without pre-join backfill.
- Focused tests prove newly-added and non-creator active sender media reaches the creator and every other eligible non-sender exactly once with correct sender identity, sender message id, key epoch, attachment metadata, and completed download state.
- Full direct suites preserve no-backfill, add/send boundary, one-recipient failure visibility, removed-member exclusion, oversized rejection, and tampered-media integrity.
- Required commands are run or truthfully blocked with exact command/failure evidence.
- Docs record GMAR-003 evidence without closing GMAR-004 visible behavior or GMAR-005 final acceptance.

## scope guard

Do not implement GMAR-004 visible preview/playback/reopen/retry/offline/duplicate/simulator work.

Do not implement GMAR-005 gate confidence, `all` sweep, or final program verdict work.

Do not broaden into announcement policy, process-kill persistence, real-device/TestFlight proof, relay redesign, background downloads, chunked media resume, media codec support, or cryptographic architecture.

Overengineering for this session includes adding a new delivery abstraction, rewriting fake network delivery, changing gate membership without a new file/classification need, or turning focused host parity tests into simulator acceptance tests.

Executors must preserve unrelated dirty-tree edits and inspect scoped diffs before editing files that already have user/pipeline changes.

## accepted differences / intentionally out of scope

- Host/app-layer completed download evidence is accepted for GMAR-003; visible image preview, video playback affordance, voice playback affordance, reopen preservation, retry UX, offline recovery, and duplicate live+inbox replay remain GMAR-004.
- Report 89 simulator proof is supporting background only; current Report 90 still treats configured simulator media proof as GMAR-004 work because inventory records an MD-014 failure.
- Existing MD-011 removed-member proof is reused as the preservation boundary unless GMAR-003 changes recipient-list or membership code in a way that requires additional removal assertions.
- The optional/manual classification of `group_new_member_onboarding_test.dart` and `group_media_fanout_test.dart` stays unchanged unless a new test file is introduced.

## dependency impact

GMAR-004 may reuse any local helper improvements from GMAR-003 but must refresh evidence before relying on them for visible simulator/reopen/retry/offline/duplicate behavior. GMAR-005 must not run final acceptance until GMAR-003 is accepted, marked stale/already-covered with evidence, or truthfully blocked alongside GMAR-004.

If GMAR-003 requires production changes in shared send/listener/download/member bootstrap code, GMAR-004 must re-check its assumptions because visible media behavior may have changed. If GMAR-003 is blocked because current membership bootstrap cannot safely distinguish pre-join media boundaries, later sessions should not close Report 90 on visible or final gates alone.

## reviewer pass

Sufficiency: sufficient with adjustments; the adjustments are included in this revision.

Missing files/tests/gates: the draft listed the right files and gates but made pre-join media no-backfill conditional and existing non-creator sender parity discretionary. Both are now mandatory proofs. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` is now required, not only production-change dependent.

Stale or incorrect assumptions: none found after the adjustments. The plan correctly treats current code/tests as stronger than stale prose and keeps Report 89 simulator evidence out of GMAR-003 closure.

Overengineering: none required. The plan stays in two existing integration test files unless focused failures identify a smaller production seam.

Decomposition sufficiency: sufficient. GMAR-003 is decomposed away from GMAR-004 visible media behavior and GMAR-005 final acceptance, with explicit stop rules.

Minimum needed: keep the mandatory focused regressions, full direct suites, `groups` gate, doc updates, and dirty-tree scoped-diff warning.

## arbiter pass

Structural blockers: none remaining.

Incremental details intentionally deferred: exact helper extraction shape and final focused test names may be adjusted during execution only if the resulting names are written back into the plan progress/evidence and the required commands use the final exact names.

Accepted differences intentionally left unchanged:

- GMAR-003 accepts host/app-layer completed-download proof and leaves visual playback/reopen/retry/offline/duplicate simulator proof to GMAR-004.
- GMAR-003 leaves final `all`/completeness/full-suite program closure to GMAR-005.
- Optional/manual suite classification remains unchanged unless a new test file or gate definition change requires `completeness-check`.

Stop rule: no structural blocker remains, so planning stops here and the artifact is `execution-ready`.

## Execution Progress

- `2026-05-02 12:24:13 CEST` - Executor verification and docs completed. Files inspected or touched: `test/features/groups/integration/group_new_member_onboarding_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Commands finished: focused GMAR-003 proofs all passed with `00:00 +1: All tests passed!`; full `group_new_member_onboarding_test.dart` passed with `00:01 +7: All tests passed!`; full `group_media_fanout_test.dart` passed with `00:01 +7: All tests passed!`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:08 +103: All tests passed!`; `git diff --check` passed after final doc updates. Decision/blocker: no production/app/helper files were touched; current production behavior satisfied the strengthened regressions once test assertions were aligned to the relative-path storage contract. Next action: QA reviewer should inspect the scoped test/doc diffs and rerun the required commands if desired; GMAR-004 and GMAR-005 remain pending.
- `2026-05-02 12:19:07 CEST` - Executor completed focused GMAR-003 regressions. Files inspected or touched: `test/features/groups/integration/group_new_member_onboarding_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`. Commands finished: `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart --plain-name 'multiple newly-added members independently download the same post-join image, video, and voice without pre-join history'` initially failed twice on over-strict helper assertions (`File(relativePath).existsSync()` and relative-path inequality), then passed with `00:00 +1: All tests passed!`; `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'newly-added discussion member media reaches every eligible recipient'` passed with `00:00 +1: All tests passed!`; `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'existing non-creator discussion member media reaches creator and every eligible recipient'` passed with `00:00 +1: All tests passed!`. Decision/blocker: no production/helper seam required; failures were test assertion shape only. Next action: run full direct suites.
- `2026-05-02 12:15:34 CEST` - Executor inspected scoped dirty files before edits. Files inspected or touched: `git diff -- test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_media_fanout_test.dart`, `test/features/groups/integration/group_new_member_onboarding_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_media_file_manager.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `test/shared/fakes/in_memory_media_attachment_repository.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/conversation/domain/models/media_attachment.dart`. Command currently running: none. Decision/blocker: scoped diffs show existing unrelated GMAR/media changes in the two target tests; edits will be additive/tightening only. Next action: patch the GMAR-003 regression tests in the two target files.
- `2026-05-02 12:10:53 CEST` - Executor spawned/running. Files inspected or touched: `/Users/I560101/.codex/skills/flutter-test-orchestrator/SKILL.md`, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md`, `git status --short`. Command currently running: none. Decision/blocker: starting GMAR-003 executor pass; dirty tree is broad, so scoped diffs will be inspected before editing target files and unrelated edits will be preserved. Next action: inspect current scoped diffs for the two integration test files.
- `2026-05-02 12:09:48 CEST` - Execution controller extracted contract. Files inspected or touched: `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/test-gate-definitions.md`, scoped `git status --short`, scoped diff for `group_new_member_onboarding_test.dart` and `group_media_fanout_test.dart`. Command currently running: none. Decision/blocker: GMAR-003 contract is execution-ready; work is limited to the two target integration tests unless focused failures prove a production/helper seam needs a scoped fix; GMAR-004 and GMAR-005 remain out of scope. Next action: spawn fresh Executor with `gpt-5.5` / `xhigh`.
- `2026-05-02 12:27:10 CEST` - QA Reviewer spawned/running. Files inspected or touched: `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md`. Command currently running: none. Decision/blocker: starting review-only GMAR-003 sufficiency pass; no code/test/doc logic edits permitted. Next action: inspect `git status --short`, scoped diffs and file contents for executor-reported files, confirm GMAR-003 proof coverage and GMAR-004/GMAR-005 pending status, then rerun required trust checks.
- `2026-05-02 12:30:38 CEST` - QA Reviewer completed. Files inspected or touched: `git status --short --untracked-files=all`, scoped diffs/content for `test/features/groups/integration/group_new_member_onboarding_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Commands finished: all QA reruns listed in the QA Reviewer Verdict below passed. Decision/blocker: no blocking issues; GMAR-003 is accepted as host/app-layer completed-download parity only. Next action: keep GMAR-004 and GMAR-005 pending.

## Executor Handoff Summary

- Files changed by GMAR-003 executor: `test/features/groups/integration/group_new_member_onboarding_test.dart`, `test/features/groups/integration/group_media_fanout_test.dart`, `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`, `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-GMAR-003-plan.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Production/helper files changed: none.
- Test coverage added/tightened: multi-new-member same post-join image/video/voice completed downloads with no pre-join text/media backfill; newly-added sender media to every eligible non-sender recipient; existing non-creator sender media to creator and every other eligible recipient; attachment metadata, sender identity, sender message id, key epoch, completed download status, local path, and exact per-recipient `media:download` calls.
- Commands run: all required focused proofs, both full direct suites, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, and `git diff --check`.
- Results: focused proofs `00:00 +1: All tests passed!` each; full onboarding `00:01 +7: All tests passed!`; full media fan-out `00:01 +7: All tests passed!`; `groups` gate `00:08 +103: All tests passed!`; `git diff --check` passed.
- Blockers: none. The first focused onboarding proof had two executor-authored over-assertions against relative media paths; both were corrected before green verification.
- QA next action: review scoped test/doc diffs, confirm GMAR-004 visible simulator/reopen/retry/offline/duplicate work and GMAR-005 final acceptance remain pending, then run any desired reruns of the commands above.

## QA Reviewer Verdict

- Verdict: `accepted`.
- Blocking issues: none.
- Non-blocking follow-ups: none for GMAR-003. GMAR-004 visible simulator/reopen/retry/offline/duplicate behavior and GMAR-005 final full-suite/gate reconciliation remain pending by design.
- Scope review: scoped changes are tests and docs only; no production/helper file was changed by GMAR-003. The broader worktree is dirty with unrelated tracked and untracked files, so QA reviewed only the executor-reported files plus the untracked GMAR-90 plan/source/breakdown docs.
- Proof review: `group_new_member_onboarding_test.dart` now proves newly-added Bob and Charlie independently download the same post-join image/video/voice, excludes pre-join text/media rows and attachment rows, leaves pending downloads empty, and limits media download calls to the post-join blob ids. `group_media_fanout_test.dart` now proves newly-added Bob media reaches Alice/Charlie and existing non-creator Charlie media reaches Alice/Bob with exact sender identity, sender message ids, key epoch, attachment metadata, completed downloads, local paths, and three `media:download` calls per eligible non-sender. The full media fan-out suite still covers MD-011 removed-member media exclusion.
- Docs review: source, breakdown, closure reference, Report 89, and inventory wording record GMAR-003 as host/app-layer parity only and keep GMAR-004 and GMAR-005 pending. No simulator, reopen, retry, offline, duplicate, `all` sweep, or final program verdict closure is claimed.
- Commands rerun by QA:
  - `git diff --check` passed before and after QA test reruns.
  - `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart --plain-name 'multiple newly-added members independently download the same post-join image, video, and voice without pre-join history'` passed with `00:00 +1: All tests passed!`.
  - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'newly-added discussion member media reaches every eligible recipient'` passed with `00:00 +1: All tests passed!`.
  - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'existing non-creator discussion member media reaches creator and every eligible recipient'` passed with `00:00 +1: All tests passed!`.
  - `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed with `00:01 +7: All tests passed!`.
  - `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart` passed with `00:00 +7: All tests passed!`.
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed with `00:08 +103: All tests passed!`.
- `completeness-check` was not rerun because no new test file was added, `Test-Flight-Improv/test-gate-definitions.md` was not changed, and optional/manual suite classification was unchanged.
