# GEK-004 Delayed Membership/Config Propagation Plan

Status: execution-ready

## Planning Progress

- `2026-05-09T21:14:04Z` - Role: Arbiter completed. Files inspected since last update: final reviewer-pass plan and patched incremental details. Decision/blocker: no structural blockers remain; GEK-004 plan is execution-ready with test-first stop rule, exact selectors, named gate contract, GEK-005 exclusion, and accepted differences documented. Next action: stop planning and hand off for GEK-004 execution.
- `2026-05-09T21:13:38Z` - Role: Arbiter started. Files inspected since last update: reviewer-pass plan and patched selector/invite-scope text. Decision/blocker: no blocker found so far; classifying reviewer adjustments into structural blockers, incremental details, and accepted differences. Next action: write final arbiter decision and mark the plan execution-ready if no structural blocker remains.
- `2026-05-09T21:12:39Z` - Role: Reviewer completed. Files inspected since last update: GEK-004 draft plan, exact selector searches in group key/listener/drain/create/integration tests, and gate docs. Decision/blocker: sufficient with incremental adjustments; the stale-key GEK-001 selector needed exact wording, and invite-status preservation was narrowed to existing safety selectors instead of broadening the new drain regression. No structural blockers found. Next action: run Arbiter pass.
- `2026-05-09T21:12:05Z` - Role: Reviewer started. Files inspected since last update: completed draft plan. Decision/blocker: no blocker yet; reviewing mandatory sections, selector exactness, GEK-005 boundary, invite-truth preservation, and known-failure handling. Next action: verify the draft against repo test names and gate docs.
- `2026-05-09T21:11:45Z` - Role: Planner completed. Files inspected since last update: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-004-plan.md` draft content plus evidence gathered above. Decision/blocker: mandatory draft sections are written with a focused GEK-004 regression, exact selectors, named gate contract, known-failure interpretation, and scope guard; no blocker. Next action: run Reviewer pass for sufficiency, stale assumptions, missing gates, and overreach.

## Execution Progress

- `2026-05-09T21:16:12Z` - Phase: contract extracted. Files inspected or targeted: this GEK-004 plan, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/application/group_message_listener.dart`, and `lib/features/groups/application/handle_incoming_group_message_use_case.dart`. Decision/blocker: execution is limited to the delayed membership/config propagation regression; production edits are allowed only if the focused regression fails for a repo-owned gap; GEK-005 final simulator/relay verdict remains out of scope. Next action: add the GEK-004 regression before any production edits.
- `2026-05-09T21:19:06Z` - Phase: Executor test edit completed. Files touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Decision/blocker: added the focused GEK-004 regression in the existing owner test file with no production edits. Next action: run the focused GEK-004 selector red/green before deciding whether production changes are justified.
- `2026-05-09T21:21:31Z` - Phase: Executor production edit completed after red test. Files touched: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command/result: focused GEK-004 selector failed red before production edits because `unknown_sender` replay rejection aborted the drain before the delayed `member_added` config replay. Decision/blocker: patched only the drain replay seam so signed durable group-message replays rejected as `unknown_sender` are deferred within the page and retried before cursor commit after config/system replays; unresolved unknown senders still reject and leave the cursor unadvanced, and live unknown senders are unchanged. Next action: rerun the focused GEK-004 selector.
- `2026-05-09T21:23:04Z` - Phase: Executor focused validation completed. Files touched: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command/result: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once'` passed after the drain fix and test-fixture watermark correction. Decision/blocker: no blocker in the focused regression. Next action: run the required GEK-001/002/003, membership/config, invite-truth, named-gate, and diff checks.
- `2026-05-09T21:24:39Z` - Phase: Executor safety selectors completed. Files touched: none after focused validation. Command/result: all required GEK-001, GEK-002, GEK-003, membership/config, and invite-truth focused selectors listed in this plan passed. Decision/blocker: no focused selector blocker. Next action: run `./scripts/run_test_gates.sh groups` and `git diff --check`; completeness-check remains conditional and is not expected because no `_test.dart` file was added, removed, or renamed.
- `2026-05-09T21:25:24Z` - Phase: Executor named gates completed. Files touched: none after safety selectors. Command/result: `./scripts/run_test_gates.sh groups` passed; `git diff --check` passed. Decision/blocker: Executor pass has no known blocker; `./scripts/run_test_gates.sh completeness-check` skipped because GEK-004 only updated an existing `_test.dart` file. Next action: start QA Reviewer pass against the landed diff and rerun minimum QA checks.
- `2026-05-09T21:26:56Z` - Phase: QA Reviewer started. Files inspected or targeted: landed diffs in `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and this plan. Decision/blocker: no blocking issue found in the static diff review so far; the production change stays in the signed durable drain path, does not make live unknown senders deliverable, and leaves unresolved unknown senders rejecting before cursor commit. Next action: rerun QA focused checks for GEK-004 plus the drain-seam GEK-002/GEK-003 selectors and `git diff --check`.
- `2026-05-09T21:27:47Z` - Phase: QA Reviewer completed. Files inspected or targeted: same landed GEK-004 diff. Command/result: QA reran the GEK-004 focused selector, GEK-002 drain selector, GEK-003 drain selector, and `git diff --check`; all passed. Decision/blocker: no blocking issues remain; no fix pass needed. Next action: write final execution verdict.

## Final Execution Verdict

- Verdict: `accepted`
- Timestamp: `2026-05-09T21:27:47Z`
- Scope completed: GEK-004 focused regression was added to the existing drain owner test file, failed red before production edits for the expected `unknown_sender` delayed-config gap, and now passes after a narrow drain-level deferred retry fix.
- Production behavior: signed durable group-message replays rejected only because the sender is not yet locally known are deferred within the page and retried before cursor commit after membership/config system replays; unresolved unknown senders still reject before cursor advancement, and ordinary live unknown-sender messages remain fail-closed.
- Required evidence: focused GEK-004 selector, all required GEK-001/GEK-002/GEK-003 safety selectors, all required membership/config and invite-truth selectors, `./scripts/run_test_gates.sh groups`, and `git diff --check` passed. QA reran the GEK-004, GEK-002, and GEK-003 drain selectors plus `git diff --check`; all passed.
- Completeness-check: skipped because GEK-004 updated an existing `_test.dart` file and did not add, remove, or rename a test file.
- Non-goals preserved: no final simulator/relay acceptance, no final Report 94 program verdict, no invite eligibility redesign, no per-recipient acknowledgement semantics, and no Go/native bridge change claimed.

## real scope

GEK-004 owns one host app-layer membership/config ordering proof:

- Add a focused regression proving that a newly added accepted sender's post-join group message is not permanently lost when the recipient sees that sender's signed durable replay before local membership/config catch-up.
- Prove the catch-up path by applying the delayed `member_added` or `members_added` group config and then processing the same durable message identity to exactly one delivered visible row, or to one explicit non-delivered terminal state if the replay is truly unrecoverable.
- Preserve creator-side invite delivery truth: `sent`, `queued`, `needsResend`, `cannotSend`, and `unknown` invitees must not be treated as confirmed silent-miss recipients. Only accepted/joined members become eligible for the GEK-004 delivery guarantee.
- Preserve GEK-001 key-update monotonicity, GEK-002 live/deferred repair convergence, GEK-003 partial key-update rotation/send/repair convergence, and the GEK-002 explicit follow-up for old `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date receipt fixtures.

GEK-004 does not close real relay/simulator acceptance, group-wide final confidence, per-recipient acknowledgement semantics, invite-status UI redesign, group membership policy changes, or the final Report 94 program verdict. GEK-005 owns final simulator/relay reconciliation and the final whole-program verdict.

## closure bar

GEK-004 is good enough when a deterministic regression proves this sequence:

1. A recipient has the group and current key, but its local membership/config state does not yet include a newly accepted sender.
2. A signed durable replay for that sender's post-join message arrives before the membership/config update.
3. The app does not persist a normal delivered plaintext row from an unverified or still-unknown sender.
4. After the delayed config catch-up is applied, durable recovery processes the same message identity into exactly one visible delivered row with the correct sender, message id, timestamp, epoch, group id, and no duplicate row after a second replay.
5. If the message cannot be recovered because the config never catches up or the replay is invalid, the app leaves cursor/retry state intact or records one explicit non-delivered state. It must not silently advance past the message as if delivery succeeded.
6. Invite degradation remains truthful: failed, queued, missing-secure-key, or unaccepted invitees remain visibly degraded and are not counted as confirmed eligible recipients.

Named gates and focused safety selectors must pass or have documented pre-existing failures outside GEK-004.

## source of truth

Authority order:

1. Current code and tests in this workspace win over stale prose.
2. `Test-Flight-Improv/test-gate-definitions.md` is the source of truth for named gates.
3. `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md` is the active GEK-004 session contract unless current repo evidence proves it stale.
4. `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md` defines the user-visible reliability problem and explicitly says delayed membership/config propagation remains missing.
5. GEK-001, GEK-002, and GEK-003 closure evidence is already accepted for their own slices and must be preserved, not reopened.

## session classification

`implementation-ready`

Reason: the breakdown marks GEK-004 implementation-ready, and current repo evidence shows a concrete missing proof around the unknown-sender membership/config boundary. The session may still land as test-only evidence if the focused regression passes against current code. Production edits are allowed only after the GEK-004 regression proves a repo-owned gap.

## exact problem statement

The current receive path is intentionally fail-closed for unknown senders:

- `handleIncomingGroupMessage` rejects a normal message when `groupRepo.getMember(groupId, senderId)` returns null and there is no matching removal cutoff.
- `decryptGroupOfflineReplayEnvelope` verifies the signed durable replay against the sender's local group member/device record before decrypting. If local config has not caught up, it throws `GroupOfflineReplaySignatureException('unknown_sender')`.
- `drainGroupOfflineInbox` treats that signature exception as a hard replay rejection unless it is the special deleted-local-group case, so a post-join message can be rejected before the delayed membership/config update has a chance to make the sender known.

That fail-closed posture is correct for truly unauthorized senders, but GEK-004 needs a proof that an accepted newly added sender is not permanently lost just because membership/config propagation is late. User-visible behavior must improve from "successful add/send and unknown-sender rejection are individually covered" to "late config plus durable replay converges to one delivered message or an explicit non-delivered state."

What must stay unchanged:

- Unknown, unsigned, forged, unbound-device, removed-after-cutoff, and not-yet-accepted sender traffic must not become delivered plaintext.
- GEK-001 delayed/conflicting key-update monotonicity must remain intact.
- GEK-002 durable replay supersede/finalize behavior must remain intact.
- GEK-003 signed replay account-sender/device identity mapping must remain intact.
- Invite status must still distinguish `sent`, `queued`, `needsResend`, `cannotSend`, `joined`, and `unknown`.

## files and repos to inspect next

Production files:

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/record_group_invite_delivery_attempts.dart`
- `lib/features/groups/presentation/group_invite_status_presentation.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart` only if a placeholder or existing repair-state handoff becomes necessary

Test and fake files:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/send_group_invite_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`

Docs and gates:

- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`
- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## existing tests covering this area

Existing coverage that must remain green:

- `handle_incoming_group_message_use_case_test.dart` already proves unknown senders are rejected without storing a ghost row, removed-sender cutoff rules are enforced, and duplicate pubsub/inbox delivery dedupes by `messageId`.
- `group_message_listener_test.dart` already proves `member_added` and `members_added` apply group config snapshots, retry `group:updateConfig` once, preserve stale membership watermarks, reject unauthorized membership events, mark `member_joined` invite delivery status as `joined`, and reject unknown sender messages before stream/storage/notification side effects.
- `drain_group_offline_inbox_use_case_test.dart` already proves signed durable replay validation, cursor atomicity, history-gap repair, GEK-002 live diagnostic plus durable replay convergence, and GEK-003 partial key-update rotation/send/repair convergence.
- `group_membership_smoke_test.dart` already proves successful add/member list convergence, new-member participation after bootstrap, re-add send/receive, and the bootstrap-key guard. It does not prove a newly accepted sender's message arrives before local membership/config catch-up.
- `create_group_with_members_use_case_test.dart` already proves local group/member creation can succeed while invite delivery is degraded, missing secure keys are explicit, config sync failure rolls back added members, and publish failure is surfaced.
- `send_group_invite_use_case_test.dart` and `invite_round_trip_test.dart` already cover direct invite success, inbox fallback, unknown sender invite rejection, duplicate invite guard, multiple-member config, accepted-but-degraded recovery, and pending accept convergence.

Missing coverage:

- No current test proves that a signed durable message from a newly accepted sender, observed before local membership/config catch-up, later converges after config catch-up instead of being permanently skipped, looped invisibly, or misclassified as delivered.
- No current test ties invite degradation truth to the later group-message reliability interpretation: degraded or unaccepted invitees are not confirmed silent-miss recipients.

## regression/tests to add first

Add one focused regression to `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` before any production edits:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once'
```

Regression shape:

1. Create a receiver group repo with the group, admin/existing members, and the current group key, but without the newly accepted sender in local membership/config.
2. Build a signed durable group offline replay for the newly accepted sender's post-join message using the sender's account/device identity, message id, epoch, and current key.
3. Put the durable replay ahead of the membership/config catch-up signal, either in the same cursor page before a `member_added`/`members_added` system replay or in a first failed drain followed by an explicit delayed system replay and a second drain of the unchanged cursor. Prefer same-page message-before-config because that is the strictest proof of late propagation.
4. Assert no normal delivered plaintext row is saved before the sender becomes known.
5. After config catch-up, assert exactly one delivered incoming row exists for the original message id, with the sender account identity and no duplicate after replaying the same durable message again.
6. Keep invite-status preservation out of the new drain regression unless the implementation touches invite eligibility. Use the existing invite/status safety selectors below to prove `needsResend`, `cannotSend`, `queued`, and `unknown` attempts are not marked `joined` or treated as accepted recipients unless a `member_joined` event is processed.

Expected first-run interpretation:

- If the regression fails because an `unknown_sender` durable replay aborts before catch-up and never converges, implement the smallest repo-owned change.
- If the regression passes without production edits, keep the test as GEK-004 evidence and stop implementation. Do not invent a production change.

## step-by-step implementation plan

1. Re-read the focused owner files and tests listed above, paying attention to current dirty changes from GEK-001/002/003. Do not revert or normalize unrelated worktree changes.
2. Add the GEK-004 regression in the existing `drain_group_offline_inbox_use_case_test.dart` file. Do not add a new `_test.dart` file.
3. Run the focused GEK-004 selector. Record whether it fails red or passes as existing coverage.
4. If it passes, stop production work. The implementation result is test-only GEK-004 evidence.
5. If it fails, inspect the exact failure class before editing production. The likely repo-owned seams are recoverable `unknown_sender` replay handling in `drain_group_offline_inbox_use_case.dart` and replay signature/member lookup in `group_offline_replay_envelope.dart`.
6. Prefer a narrow drain-level fix that defers a signed replay rejected only for missing local sender membership until after membership/config system events in the same drain page have been processed, then retries the deferred replay before committing the cursor. Never decrypt or persist a delivered plaintext row until the sender is known and signature/device checks pass.
7. If same-page deferral is not enough because catch-up can arrive in a later drain, ensure cursor advancement does not skip the rejected message. If an explicit user-visible state is necessary, reuse an existing non-delivered placeholder/status pattern only if it can be superseded by the later verified replay. Avoid a new schema unless the existing repositories cannot represent the required state.
8. Keep `handleIncomingGroupMessage` fail-closed for ordinary live unknown senders. GEK-004 should not make unverified live messages from unknown senders deliverable.
9. Preserve invite truth by limiting any invite-status changes to the already established `member_joined` path. Do not mark `sent`, `queued`, `needsResend`, `cannotSend`, or `unknown` attempts as joined merely because a member row exists locally.
10. Run the focused GEK-004 selector until green, then run the GEK-001/002/003 and invite/membership safety selectors listed below.
11. Run `./scripts/run_test_gates.sh groups` because GEK-004 can change group send/receive/retry/resume/invite behavior.
12. Run `./scripts/run_test_gates.sh completeness-check` only if implementation adds, removes, or renames a `_test.dart` file. The expected GEK-004 plan uses an existing test file, so completeness-check is not required.
13. Stop and escalate if the only viable fix requires broad product semantics such as per-recipient ACKs, invite eligibility redesign, relay API changes, or new cross-session acceptance claims.

## risks and edge cases

- Same-page durable ordering: a message replay can precede the membership/config catch-up that would make the sender verifiable.
- Cross-drain recovery: the first drain may see the message before catch-up, and a later drain may need to retry the same cursor or same message id.
- Security: a forged unknown sender must not become deliverable just because GEK-004 treats some `unknown_sender` cases as retryable.
- Cursor atomicity: do not advance a cursor past an unprocessed recoverable message unless one explicit non-delivered state was durably saved.
- Duplicate delivery: live plus inbox plus retry must still converge by `messageId`.
- Removed-member cutoff: GEK-004 must not weaken removed-sender denial after removal/dissolve.
- Device binding: sender account/device/transport identity must remain bound as GEK-003 fixed for durable replay.
- Invite eligibility: pending, failed, queued, or cannot-send invitees are not eligible recipients until the accepted/joined flow proves they joined.
- Existing worktree state: unrelated dirty files and prior GEK edits are present; implementation must work with them and not revert them.

## exact tests and gates to run

Required focused GEK-004 regression:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once'
```

Required GEK-001/GEK-002/GEK-003 safety selectors:

```bash
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'delayed older key update after newer generation does not promote active key'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates keep first accepted material'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival'
```

Required membership/config and invite-truth selectors:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'member_added retries once using incoming groupConfig snapshot and then succeeds'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'members_added retries once using incoming groupConfig snapshot and then succeeds'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'ER002 rejects unknown sender message before stream, storage, or notification'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'member_joined marks invite delivery status as joined'
flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name 'succeeds locally even when P2P invite fails'
flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name 'reports missing secure keys as explicit invite degradation'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'add member syncs every member list and the new member can participate'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'new member cannot send before bootstrap key exists, then succeeds after bootstrap completes'
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'invite round-trip with multiple members in config'
```

Conditional selectors:

```bash
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'rejects messages from unknown members without storing a ghost row'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'deduplicates by messageId when pubsub and group inbox deliver same message'
flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart
flutter test --no-pub test/features/contact_request/integration/contact_request_flow_test.dart
```

Run the `handle_incoming_group_message_use_case_test.dart` selectors if `handle_incoming_group_message_use_case.dart` changes. Run `send_group_invite_use_case_test.dart`, `add_group_member_use_case_test.dart`, and `contact_request_flow_test.dart` only if implementation touches invite sending, add-member permissions, contact-entry flows, or related eligibility behavior.

Named gates and final checks:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

```bash
./scripts/run_test_gates.sh completeness-check
```

Run `completeness-check` only if a `_test.dart` file is added, removed, or renamed. GEK-004 should add its regression to an existing file, so this gate should usually be skipped with that reason recorded.

## known-failure interpretation

- The new GEK-004 focused regression is expected to fail before production changes if current code cannot recover a durable replay rejected as `unknown_sender` before config catch-up. That red is useful evidence, not a blocker.
- After implementation, the GEK-004 regression and required safety selectors must pass.
- The full `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` owner-file run may still fail older `PREREQ-GROUP-SYNC-RECEIPTS` cases because fixed `2026-05-01T12:00:00Z` receipt fixtures are outside the seven-day retention cutoff on `2026-05-09`. Preserve this GEK-002 explicit follow-up and do not classify it as a GEK-004 regression unless GEK-004 changes receipt or retention semantics.
- Missing simulator devices or relay addresses are fixture gaps for GEK-005, not GEK-004 implementation failures.
- Pre-existing dirty worktree changes must not be reverted. If a test failure is caused by unrelated dirty files, record the evidence and do not claim GEK-004 caused it.

## done criteria

- The GEK-004 regression exists in an existing test file and has a recorded first-run result.
- If production changes are needed, they are limited to the proven delayed membership/config recovery seam.
- After config catch-up plus durable replay, an accepted newly added sender's message appears exactly once or one explicit non-delivered terminal state exists.
- Unknown or unauthorized senders remain fail-closed and do not produce delivered plaintext rows.
- Invite delivery attempts remain truthful; degraded or unaccepted invitees are not counted as confirmed silent-miss recipients.
- GEK-001, GEK-002, and GEK-003 focused safety selectors still pass.
- `./scripts/run_test_gates.sh groups` passes or any failure is classified with evidence as pre-existing/out of scope.
- No GEK-005 simulator/relay acceptance or final program verdict is claimed.

## scope guard

Do not implement:

- Final simulator/relay proof or final Report 94 verdict.
- Per-recipient delivery acknowledgements or receipt-based group `sent` semantics.
- A broad invite eligibility redesign or new Members UI workflow.
- Go relay, Go pubsub validator, or native bridge API changes unless the focused GEK-004 regression proves the root cause is outside Flutter app-layer handling.
- Persistence schema changes unless existing message, pending-key, history-gap, or invite-attempt repositories cannot express the required explicit state.
- Any change that makes ordinary live unknown-sender messages deliverable before membership/config verification.
- Any cleanup of unrelated dirty files or prior GEK edits.

Stop implementation if the focused regression proves current behavior already covers GEK-004. Record test-only evidence instead of widening scope.

## accepted differences / intentionally out of scope

- Host deterministic app-layer proof is sufficient for GEK-004. True multi-device relay timing remains GEK-005.
- A pending, queued, failed, cannot-send, or unknown invitee is not an eligible message recipient until acceptance/join evidence exists.
- Group `sent` status remains receipt-less. GEK-004 must not reinterpret `sent` as every member acknowledged the message.
- Existing fail-closed security behavior for forged, unsigned, unknown, unbound, and removed-after-cutoff senders is intentionally preserved.
- The GEK-002 fixed-date receipt fixture follow-up remains separate maintenance.
- If no durable replay exists, GEK-004 does not require inventing message plaintext. It requires avoiding silent success: retain retry/cursor state or expose one explicit non-delivered state.

## dependency impact

- GEK-005 depends on GEK-004 being closed, test-only covered, or truthfully blocked before it reconciles final simulator/relay evidence.
- Closure docs after implementation should update only GEK-004 evidence in `94-group-epoch-key-reliability-test-gaps.md`, `Group-Chat-Feature/test-inventory.md`, and `20-group-discussion-reliability-closure-reference.md`. They must not write a final program verdict.
- If GEK-004 changes durable replay identity, placeholder replacement, cursor commit, or group config catch-up behavior, GEK-002 and GEK-003 selectors are required because later sessions rely on those contracts.
- If GEK-004 changes invite delivery attempt semantics, the invite-status docs and tests must be updated in the same execution session. Otherwise invite-status closure remains untouched.

## reviewer findings

- Sufficiency: sufficient with adjustments. The plan has the mandatory scope, closure bar, source of truth, classification, regression-first contract, test/gate list, known-failure interpretation, done criteria, and scope guard.
- Missing files/tests/gates: no structural omissions after adding exact GEK-001/002/003, membership/config, invite-truth, groups gate, and conditional completeness-check guidance.
- Stale or incorrect assumptions: patched the GEK-001 stale-key selector to the repo's exact name, `delayed older key update after newer generation does not promote active key`.
- Overengineering: patched the new GEK-004 regression so invite-status preservation is proved by existing invite/status selectors rather than folded into the drain regression.
- Decomposition: narrow enough. One focused drain regression owns the delayed config plus durable message seam; production edits stop if that regression passes.
- Minimum needed: no additional structural work before execution.

## arbiter decision

Structural blockers:

- None.

Incremental details intentionally deferred:

- A second GEK-004 regression for a later-drain config catch-up can be added only if the primary same-page or message-before-config regression does not cover the observed failure shape.
- Full owner-file `drain_group_offline_inbox_use_case_test.dart` rerun remains optional until the GEK-002 fixed-date receipt fixture follow-up is addressed, unless GEK-004 touches receipt or retention semantics.
- Contact-request integration is conditional on touching invite/contact-entry flows.

Accepted differences:

- Host deterministic app-layer proof is accepted for GEK-004; live relay/simulator timing remains GEK-005.
- Invite status and confirmed recipient eligibility remain separate: degraded or unaccepted invitees are not confirmed silent-miss recipients.
- Group `sent` remains receipt-less; GEK-004 does not add per-recipient ACK semantics.
- Existing fail-closed behavior for forged, unsigned, unbound, removed, and truly unknown senders remains intentional.

Final arbiter verdict:

`execution-ready`
