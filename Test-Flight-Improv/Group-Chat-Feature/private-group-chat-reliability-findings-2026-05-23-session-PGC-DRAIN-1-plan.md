# PGC-DRAIN-1 Execution Plan

Status: execution-ready

## Planning Progress

- 2026-05-23T23:13:20+0200 - Planner completed. Files inspected since last update: no new files. Decision/blocker: draft covers rows `PGC-001`, `PGC-002`, `PGC-014`, and `PGC-016` only, with regression-first tests and exact gates. Next action: Reviewer will check sufficiency, stale assumptions, and scope drift.
- 2026-05-23T23:14:10+0200 - Reviewer started. Files inspected since last update: this plan draft. Decision/blocker: review will check for ambiguous implementation choices, missing focused regressions, and gate mismatch. Next action: record sufficiency review.
- 2026-05-23T23:14:45+0200 - Reviewer completed. Files inspected since last update: this plan draft. Decision/blocker: sufficient with adjustments; the draft needs exact choices for invalid concurrency limits and sender-bound receipt behavior before execution. Next action: Arbiter will classify those review findings.
- 2026-05-23T23:15:05+0200 - Arbiter started. Files inspected since last update: Reviewer Pass section. Decision/blocker: classify exact-choice findings before marking execution-ready. Next action: patch incremental details if no structural blocker remains.
- 2026-05-23T23:15:40+0200 - Arbiter completed. Files inspected since last update: patched plan details. Decision/blocker: no structural blockers remain; incremental exact-choice details were applied; plan is execution-ready. Next action: hand off to implementation executor when requested.

## Execution Progress

- 2026-05-23T23:21:31+0200 - Contract extraction started. Files inspected/touched: this plan, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` diff, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` diff, `git status --short`. Command: `sed`/`git diff`/`git status`. Decision/blocker: execution limited to session `PGC-DRAIN-1` rows `PGC-001`, `PGC-002`, `PGC-014`, `PGC-016`; production file already has unrelated V3 envelope decode edits to preserve; test file has no pre-existing diff. Next action: finish extracting exact scope, tests, gates, known-failure interpretation, and done criteria.
- 2026-05-23T23:21:31+0200 - Contract extracted. Files inspected/touched: this plan only. Command: none. Decision/blocker: scope is one drain-use-case product file, one focused test file, and plan notes; required regressions are the eight named selectors; required validation is those selectors, full drain test file, `dart format` on touched files, `git diff --check`, and `./scripts/run_test_gates.sh groups`; known failures are not accepted for direct drain tests; no code blocker found. Next action: spawn isolated Executor agent.
- 2026-05-23T23:22:28+0200 - Executor spawning. Files inspected/touched: this plan only. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: isolated Executor will receive only the plan path, allowed write scope, and required tests/gates. Next action: wait for Executor completion and inspect landed evidence.
- 2026-05-23T23:23:07+0200 - Executor spawn retry. Files inspected/touched: this plan only. Command: first `codex exec` launch rejected unsupported `-a` option before any child work began. Decision/blocker: no code/test/doc child work materialized, so retrying once with supported `--dangerously-bypass-approvals-and-sandbox`. Next action: wait for Executor completion and inspect landed evidence.
- 2026-05-23T23:24:39+0200 - Executor running. Files inspected/touched: this plan, `git status --short`, diffs for allowed production/test files, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and read-only fake repository references. Command: `sed`/`rg`/`git diff`/`git status`. Decision/blocker: strict scope confirmed; production file has pre-existing V3 envelope diff to preserve, test file has no pre-existing diff, and scoped gaps remain. Next action: add regression tests before production edits where practical.
- 2026-05-23T23:28:58+0200 - Executor child stopped; local fallback started. Files inspected/touched: process table and allowed-file diffs. Command: `ps`, `kill`, `git diff --name-only`, `git diff --stat`. Decision/blocker: spawned Executor remained open without trustworthy completion evidence or code/test delta; no partial code/test work landed beyond heartbeat notes, so the orchestrator is using the skill's local sequential fallback instead of relaunching the same child step. Next action: implement the scoped Executor responsibilities locally, then run required validation and perform QA.
- 2026-05-23T23:32:00+0200 - Local Executor implementation started. Files inspected/touched: allowed production/test files and read-only listener/replay helpers. Command: `sed`/`rg`. Decision/blocker: implementation points identified for bounded group scheduling, terminal reaction replay, logical system sender replay, and sender-bound payload receipts; regression tests will be added in the allowed test file before production edits complete. Next action: patch tests and production file within scope.
- 2026-05-23T23:35:37+0200 - Local Executor implementation completed; formatting/tests starting. Files inspected/touched: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, this plan. Command: none. Decision/blocker: production changes landed for bounded group-drain concurrency, terminal reaction replay without `reactionRepo`, logical system sender replay in normal drain/history repair, and sender-bound payload receipts; focused regressions added/updated for rows `PGC-001`, `PGC-002`, `PGC-014`, `PGC-016`. Next action: run formatting and required selectors.
- 2026-05-23T23:36:02+0200 - Formatting finished; selector tests starting. Files inspected/touched: allowed production/test files. Command: `dart format lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed. Decision/blocker: formatting complete. Next action: run the eight required `flutter test --plain-name` selectors.
- 2026-05-23T23:38:59+0200 - Required selectors finished; focused suite starting. Files inspected/touched: allowed production/test files. Command: all eight required `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name ...` selectors passed after fixture corrections; earlier selector failures were test-fixture issues (`stale membership event`, repair `head_mismatch`, missing local member for delivered receipt assertion, and first-page cursor expectation). Decision/blocker: no remaining selector failure. Next action: rerun format, then full focused drain test file.
- 2026-05-23T23:43:34+0200 - Tests/gates finished. Files inspected/touched: allowed production/test files and this plan. Commands: `dart format lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed with 0 final changes; `git diff --check` passed; `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name ...` passed for all required PGC selectors plus the existing concurrency selector; `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` failed with 19 failures after 92 tests run; `./scripts/run_test_gates.sh groups` failed. Decision/blocker: focused row regressions pass, but the required direct file and named gate are red and are not exact known unrelated failures under this plan. Next action: perform QA review against the scoped diff and failed-gate evidence.
- 2026-05-23T23:43:40+0200 - QA started. Files inspected/touched: allowed production/test file diffs, this plan, `git status --short`. Commands: `git status --short -- <allowed paths>`, `git diff --stat -- <allowed paths>`, `nl`/`rg` inspection, `git diff --check`, final `dart format`. Decision/blocker: QA is checking scope containment, contract coverage for rows `PGC-001`, `PGC-002`, `PGC-014`, `PGC-016`, and whether failed required gates can be accepted. Next action: record QA decision and final verdict.
- 2026-05-23T23:43:50+0200 - QA completed. Files inspected/touched: allowed production/test files and this plan. Command: manual diff review plus clean `git diff --check` and final `dart format` verification. Decision/blocker: implementation remains within allowed code/test write scope and covers bounded group drain concurrency, terminal reaction replay, logical sender/transport separation, history repair replay, and sender-bound payload receipts; no unrelated edits were reverted. Acceptance remains blocked because the full direct drain test file and `./scripts/run_test_gates.sh groups` failed. Spawned-agent isolation used: attempted; local sequential fallback used: yes. Next action: record final verdict without updating closure docs or running other sessions.
- 2026-05-23T23:44:00+0200 - Final verdict: blocked. Files inspected/touched: this plan only. Command: none. Decision/blocker: `PGC-DRAIN-1` cannot be marked accepted because required validation is incomplete/red: the targeted selectors passed, but the full `drain_group_offline_inbox_use_case_test.dart` suite failed with 19 failures and the Group Messaging Gate failed. Recommended next retry: triage the date-sensitive/full-suite drain fixture failures first, then rerun the full direct file and `./scripts/run_test_gates.sh groups`; separately investigate remaining groups-gate integration failures such as `GE-019` and `GM-028` if they persist. No matrix, session breakdown, or closure docs were updated.

## Recovery Input

- 2026-05-23T23:49:14+0200 - Same-session recovery started. Blocker class: `test_or_gate_failure`. Failing tests/gates: full `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` previously reported 19 failures; `./scripts/run_test_gates.sh groups` also failed. Missing contract: direct drain suite and group gate evidence were not green or exactly classified. Touched owner files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Blocker signature: `PGC-DRAIN-1 / test_or_gate_failure / full drain_group_offline_inbox_use_case_test.dart 19 failures + groups gate / owner files drain use case + drain test`. Scope: fix implementation-owned full-suite failures only inside the two owner files, preserve unrelated V3 envelope decode work, and do not update matrix or breakdown closure rows.
- 2026-05-23T23:54:52+0200 - Same-session recovery stopped on out-of-scope compile blocker. Files inspected/touched: scoped drain test fixture edits and this plan; out-of-scope inspection only for `lib/features/groups/application/group_message_listener.dart`. Commands: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` reproduced 19 direct-file failures in `/tmp/pgc_drain_recovery_full_1.log`; after scoped fixture work, rerun still reported 19 direct-file failures in `/tmp/pgc_drain_recovery_full_2.log`; a later required selector rerun failed at load time because `group_message_listener.dart` imports missing `group_pending_membership_message.dart` and `group_pending_membership_message_repository.dart`, calls undefined `_flushStartupDurableMembershipDependentMessages`, and awaits void `_bufferMembershipDependentMessage`. Decision/blocker: the active blocker is now external to `PGC-DRAIN-1` owner scope, so this recovery worker cannot keep executing or classify the group gate without touching out-of-scope listener files. Local checks that do not require compilation completed: `dart format lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed with 0 final changes, and `git diff --check -- <PGC-DRAIN scoped files>` passed. Next action: unblock/finish the concurrent listener durable-membership changes, then rerun PGC-DRAIN recovery from the latest full drain suite state.

## Evidence Collected

- Source matrix keeps rows `PGC-001`, `PGC-002`, `PGC-014`, and `PGC-016` `Open`; session breakdown assigns only these rows to `PGC-DRAIN-1`.
- `drainGroupOfflineInbox` drains all groups with unbounded `Future.wait(groups.map(...))` at `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:83`.
- Reaction routing currently returns early only when `payload['type'] == 'group_reaction' && reactionRepo != null`; with no `reactionRepo`, the same payload can continue into message handling at `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:505`.
- System replay through `groupMessageListener.handleReplayEnvelope` passes `senderId` as `transportSenderId` when present, while preserving `transportPeerId` separately; the same pattern exists in history repair at `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:560` and `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:1307`.
- Payload receipts are accepted from `receipt` and `receipts` maps and can set `memberPeerId` from `memberPeerId`, `peerId`, or `from` without checking the verified replay sender at `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:1818`.
- `GroupMessageListener` authorizes system messages using logical `senderId` plus `senderDeviceId`/`transportPeerId`, so the drain should preserve those fields instead of substituting transport as logical sender. See `lib/features/groups/application/group_message_listener.dart:1120` and `lib/features/groups/application/group_message_listener.dart:1550`.
- Existing focused tests already cover device-bound message replay, reaction replay when a repository is present, mismatched reaction sender, replay receipts, listener replay metadata, and current parallel drain behavior in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.

## real scope

This session may change only the offline group drain behavior needed for rows `PGC-001`, `PGC-002`, `PGC-014`, and `PGC-016`.

In scope:

- In `drainGroupOfflineInbox`, replace unbounded group-level `Future.wait` with bounded concurrency that still allows more than one group to progress.
- In the offline drain system-message branch and history-repair replay branch, pass logical `senderId` from the verified decoded payload, and pass transport identity only through `transportPeerId`/`senderDeviceId`.
- Bind payload-derived receipts to the verified replay sender before persisting them. A payload receipt whose `memberPeerId` does not match the decoded, verified replay `senderId` must be dropped. Locally generated delivered receipts remain unchanged.
- Drop or acknowledge `group_reaction` replay payloads before message handling even when `reactionRepo` is `null`, so a missing reaction repository cannot create message timeline rows from reaction JSON.
- Add focused tests in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` for these four rows.
- Update this matrix row evidence and the session breakdown ledger only after implementation and tests actually pass.

Out of scope:

- No Go, relay, bridge, migration, repository, send path, listener lifecycle, key-retention, UI, notification, or group database helper changes.
- No new dependency for concurrency limiting.
- No broad receipt protocol redesign. If signed standalone group receipt replay is needed, split it into a later plan.

## closure bar

The session is complete when:

- System replay and history repair preserve logical sender identity while still passing transport/device identity to listener authorization.
- A replay payload cannot persist read/delivered receipts for any member other than the verified replay sender; forged local or third-party receipts are dropped.
- `group_reaction` payloads never fall through to message persistence when `reactionRepo` is absent.
- Group drain concurrency is bounded by an explicit limit and remains parallel for at least two groups by default.
- Focused regressions for all four rows fail before the implementation and pass after it.
- Required direct tests, the group named gate, formatting, and diff checks pass or have an exact pre-existing failure classification.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`.
- Session decomposition: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`.
- Gate source of truth: `scripts/run_test_gates.sh`; if gate docs disagree with the script, the script wins.
- Gate rationale and known failures: `Test-Flight-Improv/test-gate-definitions.md` and `Test-Flight-Improv/test-gates-reference.md`.
- Current code and focused tests beat stale prose if they disagree with older docs.

## session classification

`implementation-ready`

No prerequisite blocker was found. The work is narrow enough for one executor pass if it stays inside the drain use case and focused drain tests.

## exact problem statement

Private group offline drain currently has four reliability/security gaps:

- `PGC-001`: system-message replay can replace logical sender with relay transport sender, which breaks valid device-bound system replay and can make authorization depend on the wrong identity.
- `PGC-002`: decrypted replay payloads can carry read/delivered receipts naming arbitrary members, so a message sender can forge local or third-party receipt state.
- `PGC-014`: startup/resume drain starts one async drain per local group with unbounded `Future.wait`, which can overload relay, bridge, and SQLite under many groups.
- `PGC-016`: reaction replay is only intercepted when `reactionRepo` exists; without it, reaction payloads can continue into message persistence.

User-visible behavior must improve by making offline group replay safer and more predictable after cold start/resume. Existing valid group message replay, locally generated delivered receipts, cursor advancement, page transaction behavior, and listener authorization must stay unchanged except where they directly enforce the four scoped fixes.

## files and repos to inspect next

Production files:

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` - only expected production edit.
- `lib/features/groups/application/group_message_listener.dart` - read-only reference for sender/transport authorization unless direct evidence proves a drain-only fix cannot work.
- `lib/features/groups/application/group_offline_replay_envelope.dart` - read-only reference for signed replay test setup if needed.

Tests:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` - expected focused test edits only.
- Existing shared fakes used by that test file, such as `test/shared/fakes/in_memory_group_repository.dart` and `test/shared/fakes/in_memory_group_message_repository.dart`, are read-only unless a focused regression cannot be expressed without a fake observation hook.

Docs to update after verified implementation:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`

## existing tests covering this area

- `MS002 stores relay transport peer id for offline inbox messages` covers normal message replay preserving `senderPeerId` and `transportPeerId`.
- `accepts offline replay from a valid registered sender device` and `GI-022 revoked-device replay is rejected while active-device replay continues` cover signed/device-bound replay validation.
- `drains group_reaction items when reactionRepo is provided` and `ignores replayed group_reaction items with mismatched sender identity` cover reaction replay only when `reactionRepo` is available.
- `replayed system messages trust the outer sender over payload sender` currently pins the unsafe system sender substitution and must be replaced or narrowed to the correct forged-transport rejection behavior.
- `drains groups concurrently so one slow inbox does not serially stall others` covers parallel drain but not a concurrency upper bound.
- Receipt-focused tests such as `PREREQ-GROUP-SYNC-RECEIPTS duplicate receipt replay is idempotent` and `DE-004 listener-backed live plus replay dedupes while preserving replay receipts and metadata` cover current payload receipt persistence. They must be updated where they assume an unbound sender can mark `peer-local` read.

Missing coverage:

- No test proves valid system replay keeps logical `senderId` while passing a distinct `transportPeerId`.
- No test proves history-repair system replay uses the same logical sender behavior.
- No test rejects forged replay receipts for `selfPeerId` or a third-party member when signed by another sender.
- No test proves `group_reaction` replay with `reactionRepo == null` is dropped before timeline persistence.
- No test proves group drain concurrency is bounded.

## regression/tests to add first

Add or update these focused tests before implementation. They should fail on current code for the targeted reason, not because of setup errors.

- `PGC-001 system replay keeps logical sender and transport peer separate`: signed system replay from an authorized logical admin with a distinct active device/transport must be accepted by `GroupMessageListener`; assert the system effect occurs and the transport identity is still available for device binding.
- `PGC-001 history repair system replay keeps logical sender and transport peer separate`: a history repair range containing a system replay from a valid logical sender/device must route to listener cleanup/config handling with logical `senderId`, not transport as sender.
- Update the existing forged system test into `PGC-001 system replay rejects transport that is not bound to the signed logical sender`: relay `from`/transport mismatch must not authorize a payload sender.
- `PGC-002 replay receipts are dropped when memberPeerId differs from signed sender`: signed replay from `peer-sender` containing a read receipt for `peer-local` or another member must persist the message and local delivered receipt, but must not save that read receipt or mark the message read.
- `PGC-002 sender-bound replay receipt remains idempotent`: only a payload receipt whose `memberPeerId == senderId` may persist, and duplicate replay stays idempotent.
- `PGC-016 group_reaction without reactionRepo does not persist a message`: signed reaction replay with no `reactionRepo` must leave `msgRepo` unchanged and should not block cursor advancement for that page.
- `PGC-014 drainGroupOfflineInbox limits concurrent group drains`: create more groups than the configured limit, use a bridge/fake that records active retrieves, call `drainGroupOfflineInbox(maxConcurrentGroupDrains: 2)`, and assert max active group retrieves is `<= 2` while all groups drain.
- Keep or adapt `drains groups concurrently so one slow inbox does not serially stall others` so the default remains parallel for two groups.

## step-by-step implementation plan

1. Read the current diff for `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` before editing. Preserve unrelated dirty-worktree changes.
2. Add the regression tests above in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.
3. Run the new focused selectors and confirm they fail for the expected rows. Stop and revise the plan if a selector already passes without code changes.
4. In `drainGroupOfflineInbox`, add a backward-compatible optional named parameter such as `maxConcurrentGroupDrains` with a small default constant, for example 4. If the supplied value is below 1, throw `ArgumentError.value(maxConcurrentGroupDrains, 'maxConcurrentGroupDrains', 'must be >= 1')`.
5. Replace the unbounded `Future.wait(groups.map(...))` with a local bounded async scheduler. Keep result ordering irrelevant and preserve the existing per-group success/error event behavior.
6. In normal drain `processDecodedPayload`, treat `payload['type'] == 'group_reaction'` as terminal before message handling. If `reactionRepo` is present, keep current reaction handling. If it is absent, emit a narrow diagnostic if useful and return without mutating messages.
7. In the system-message branch, pass `'senderId': senderId` to `groupMessageListener.handleReplayEnvelope`; keep `transportPeerId: effectiveTransportPeerId` and `senderDeviceId` unchanged. Preserve the existing transport mismatch rejection before this branch.
8. Apply the same logical sender/transport separation to `_applyHistoryRepairMessages`.
9. Change `_receiptsFromPayload` or its call sites so payload receipts are accepted only when bound to the verified decoded replay sender. Pass `trustedSenderId` and `trustedSenderDeviceId` into `_receiptsFromPayload`, drop receipts whose `memberPeerId != trustedSenderId`, and drop receipts whose embedded `senderDeviceId` conflicts with a non-empty `trustedSenderDeviceId`. Keep `_receiptsForPersistedInboxMessage` unchanged.
10. Update existing receipt tests that intentionally asserted unbound local read persistence. The new intentional behavior is that only locally derived delivered receipts and sender-bound payload receipts can persist during message replay.
11. Run focused selectors, then the full direct drain test file, then formatting, named gate, and diff checks.
12. Update the source matrix rows and session breakdown only with concrete passing evidence after tests/gates complete. If a gate has a known unrelated failure, record it exactly instead of marking rows closed on ambiguous evidence.

Stop conditions:

- Stop if the system sender fix requires changing listener authorization rather than drain replay fields; that is outside this session unless the user explicitly expands scope.
- Stop if forged receipt prevention requires a new signed receipt payload protocol; close `PGC-002` as blocked with that exact blocker instead of inventing protocol changes here.
- Stop if bounded drain cannot be implemented without a new dependency or cross-module scheduler; keep the scheduler local or mark blocked.

## risks and edge cases

- Signed replay sender, sender device, relay `from`, and `transportPeerId` can be distinct. The fix must not make transport a logical group member.
- Revoked or unknown devices must still fail closed through existing replay decode/listener checks.
- Dropping forged receipts can change `readAt` expectations for messages whose replay payload previously claimed `peer-local` read state. That is intentional for unbound payloads.
- Cursor advancement must still occur for terminal dropped reactions so the same unprocessable reaction does not replay forever.
- Bounded concurrency must not become serial by default; otherwise startup/resume can regress for small group counts.
- Page transaction behavior must still commit receipts/cursor atomically after Phase 1.

## exact tests and gates to run

Regression-first selectors:

```bash
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-001 system replay keeps logical sender and transport peer separate'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-001 history repair system replay keeps logical sender and transport peer separate'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-001 system replay rejects transport that is not bound to the signed logical sender'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-002 replay receipts are dropped when memberPeerId differs from signed sender'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-002 sender-bound replay receipt remains idempotent'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-016 group_reaction without reactionRepo does not persist a message'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-014 drainGroupOfflineInbox limits concurrent group drains'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'drains groups concurrently so one slow inbox does not serially stall others'
```

Focused suite:

```bash
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
```

Formatting and diff checks:

```bash
dart format lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
git diff --check
```

Named gates:

```bash
./scripts/run_test_gates.sh groups
```

Conditional only if a new test file is added or gate classification docs are touched:

```bash
./scripts/run_test_gates.sh completeness-check
```

## known-failure interpretation

- The direct `drain_group_offline_inbox_use_case_test.dart` selectors and full file must be green; failures there are not considered known unrelated failures for this session.
- `./scripts/run_test_gates.sh groups` is required because gate docs classify group send/receive/retry/resume changes under the Group Messaging Gate. As of `Test-Flight-Improv/test-gates-reference.md`, the Group Messaging Gate was green; a new groups-gate failure must be treated as suspect unless isolated to an unrelated dirty-worktree change.
- Do not reclassify known Baseline, Posts, or Startup/Transport gate failures as caused by this session unless the executor changes files those gates cover. The reference doc lists existing Baseline, Posts, and Transport red conditions.
- If a required gate cannot run because of environment or device availability, record the exact command, error, and which focused host-side tests passed. Do not mark rows closed from unrun gates alone.

## done criteria

- Rows `PGC-001`, `PGC-002`, `PGC-014`, and `PGC-016` each have a focused failing-before/passing-after test or an exact blocker.
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` is the only product file changed.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` is the only test file changed unless a fake observation hook is strictly necessary and documented.
- Required tests and gates in this plan pass, or failures are recorded as exact unrelated known failures.
- Matrix rows and session ledger are updated with concrete evidence only after verification.
- No unrelated dirty-worktree edits are reverted, reformatted, or overwritten.

## scope guard

Do not:

- Change `GroupMessageListener` authorization rules, lifecycle, buffering, or stream shutdown behavior.
- Change group send behavior, inbox custody, retry payloads, message repository upsert semantics, migrations, Go pubsub, relay ACLs, key retention, or UI.
- Add a receipt protocol, receipt event type, new storage table, scheduler package, or cross-module concurrency abstraction.
- Broaden test gates beyond the exact direct tests and named Group Messaging Gate unless the implementation edits additional files.
- Convert this into general parity work between 1:1 and group messaging.
- Use broad formatting on unrelated files in the dirty worktree.

Overengineering signs:

- New dependencies for a small bounded async loop.
- Public concurrency configuration beyond a backward-compatible optional parameter and a local default.
- New cryptographic envelope version or signed receipt protocol inside this session.
- Listener rewrites to compensate for wrong drain fields.

## accepted differences / intentionally out of scope

- Payload-derived receipts are not treated as equivalent to separately signed receipt events. This session only persists receipts embedded in message replay payloads when they are bound to the verified replay sender.
- A future signed group receipt replay protocol may be desirable, but it is not part of `PGC-DRAIN-1`.
- Group drain bounded concurrency does not need to share an abstraction with 1:1 inbox drain or other startup tasks.
- Existing skipped rows `PGC-003` and `PGC-017` stay skipped and must not be reopened here.

## dependency impact

- `PGC-LISTENER-1` should rely on this session preserving logical sender/transport fields for replayed system messages; it should not need to repair drain sender substitution.
- Later receipt or read-state work must account for the new rule that replay payload receipts are persisted only when sender-bound.
- `PGC-SEND-1`, `PGC-DB-1`, `PGC-GO-NODE-1`, `PGC-KEYS-1`, and `PGC-RELAY-1` do not depend directly on this plan and should not be folded into this session.

## Reviewer Pass

Verdict: sufficient with adjustments.

Answers to sufficiency questions:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient with adjustments.
- What files, tests, regressions, or gates are missing? No required files or gates are missing. The focused selector set covers all four rows and the Group Messaging Gate is the correct named gate.
- What assumptions are stale or incorrect? No stale source-of-truth assumption found. Current code and tests confirm the matrix findings still apply.
- What is overengineered? No overengineering in the scoped plan. The bounded scheduler must stay local; adding a dependency would be overengineering.
- Is the work decomposed enough to minimize hallucination during implementation? Yes, if the executor keeps edits to the drain use case and focused drain tests.
- What is the minimum needed to make the plan sufficient? Make two choices exact: invalid `maxConcurrentGroupDrains` handling and whether payload receipts are sender-bound or dropped. The plan should choose sender-bound receipts consistently because that is the stated scoped fix.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers:

- None.

Incremental details applied before finalizing:

- Invalid `maxConcurrentGroupDrains` behavior is exact: throw `ArgumentError.value` for values below 1.
- Payload receipt behavior is exact: persist only sender-bound receipts and drop sender-device conflicts.

Accepted differences intentionally left unchanged:

- No standalone signed receipt protocol in this session.
- No listener authorization rewrite.
- No cross-module or dependency-backed concurrency abstraction.

Why safe to implement now:

- The plan is row-scoped to `PGC-001`, `PGC-002`, `PGC-014`, and `PGC-016`.
- It names the expected production/test files, regression-first selectors, named gate, known-failure interpretation, done criteria, and scope guard.
- It preserves unrelated dirty-worktree edits by requiring pre-edit diff inspection and limiting formatting to touched files.
