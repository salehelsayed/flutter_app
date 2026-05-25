# GCA-006 Composer Identity-Missing Silent-Send Guard

Status: execution-ready

## Execution Progress

- 2026-05-23T20:11:41+02:00 - Phase: contract extracted. Files inspected or touched: plan, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `git status --short`. Decision/blocker: scope is limited to the plan plus the two row-owned product/test files; `GroupConversationScreen` is inspect-only and already has unrelated worktree changes. Next action: spawn Executor with `gpt-5.5` and `model_reasoning_effort=xhigh`.
- 2026-05-23T20:12:20+02:00 - Phase: Executor spawned/running. Files inspected or touched: plan heartbeat. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: none. Next action: wait for Executor result and inspect assigned evidence.
- 2026-05-23T20:12:55+02:00 - Phase: Executor spawn retry. Files inspected or touched: plan heartbeat. Command result: initial spawn failed before agent materialization because this `codex exec` build rejects `--ask-for-approval`; repo config already sets approval policy to `never`. Decision/blocker: retry with supported flags. Next action: run corrected Executor spawn.
- 2026-05-23T20:15:10+02:00 - Phase: local fallback started. Files inspected or touched: plan, target-file diff, `rg GCA-006`, child process list. Decision/blocker: spawned Executor produced no trustworthy code/test/doc delta inside bounded waits; visible diff remained pre-existing GCA-005 message-load work plus plan heartbeats, so the child was terminated and local sequential fallback is being used. Next action: add the GCA-006 regression first.
- 2026-05-23T20:18:20+02:00 - Phase: RED test added. Files inspected or touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. Command currently running: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GCA-006"`. Decision/blocker: delayed-identity regression added before production edits. Next action: confirm expected enabled-composer/missing-identity failure.
- 2026-05-23T20:18:50+02:00 - Phase: RED confirmed. Files inspected or touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. Command result: `GCA-006` selector failed as expected at `screen.canWrite`, actual `true`. Decision/blocker: expected enabled-composer/missing-identity gap reproduced. Next action: implement minimal `GroupConversationWired` identity guard.
- 2026-05-23T20:21:10+02:00 - Phase: implementation applied. Files inspected or touched: `lib/features/groups/presentation/screens/group_conversation_wired.dart`. Decision/blocker: writable checks now require complete sender identity, late identity copies username/public/private key fields, and `_onSend` remains defensive before draft/media work. Next action: run required post-implementation commands.
- 2026-05-23T20:23:20+02:00 - Phase: direct verification partial. Files inspected or touched: product/test files. Command results: `dart format --set-exit-if-changed ...` pass with 0 changed; `flutter analyze --no-pub ...` pass; `flutter test --plain-name "GCA-006"` pass; `flutter test --plain-name "UP-003 composer enables only for an active member with current key"` pass. Decision/blocker: focused identity and adjacent membership/key regressions pass. Next action: triage full suite failure.
- 2026-05-23T20:24:30+02:00 - Phase: full suite triage. Files inspected or touched: `group_conversation_wired_test.dart`, `send_group_message_use_case.dart`, target-file diff. Command result: full `group_conversation_wired_test.dart` red; first failures are existing send/media/voice cases without seeded group members, failing via `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED` and no `group:publish`. Decision/blocker: failures are outside the GCA-006 identity guard and not in files changed by this session, but the required full suite is still red. Next action: run required groups gate and then QA review.
- 2026-05-23T20:27:40+02:00 - Phase: required gate finished. Files inspected or touched: gate output. Command result: `./scripts/run_test_gates.sh groups` red after `288` passed and `13` failed; residuals include the same group-conversation empty-membership send/media/voice failures and final visible integration failure `GM-028 empty PeerId add event does not persist or block valid delivery` expecting length `1`, actual `[]`. Decision/blocker: required named gate is red. Next action: run `git diff --check` and QA review.
- 2026-05-23T20:28:05+02:00 - Phase: diff check finished. Files inspected or touched: repository diff. Command result: `git diff --check` pass. Decision/blocker: no whitespace errors. Next action: spawn QA Reviewer for sufficiency verdict.
- 2026-05-23T20:28:20+02:00 - Phase: QA Reviewer spawned/running. Files inspected or touched: plan heartbeat. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: none. Next action: wait for QA result.
- 2026-05-23T20:35:03+02:00 - Phase: QA Reviewer local fallback. Files inspected or touched: QA child output, process list, plan, diffs, test evidence. Decision/blocker: QA child inspected the plan/diffs but did not return a final result inside bounded waits, so it was terminated and QA classification completed locally. Blocking issue: required full `group_conversation_wired_test.dart` and required `groups` gate are red; fixing the visible residuals would require broad non-GCA-006 membership/send/integration work outside this session. Next action: write final blocked verdict.
- 2026-05-23T20:35:30+02:00 - Phase: final verdict written. Files inspected or touched: plan. Decision/blocker: `blocked` with blocker class `test_or_gate_failure`. Next action: report verdict, changed files, exact tests, residual failures, and manual verification step.

## Recovery Input

2026-05-23T20:36:00+02:00 - Same-session recovery requested by the pipeline controller.

- Blocker class: `test_or_gate_failure`.
- Blocker signature: `GCA-006` focused identity guard passes, but the plan still marked the session blocked because full `group_conversation_wired_test.dart` and `./scripts/run_test_gates.sh groups` remain red.
- Failing tests/gates: full `group_conversation_wired_test.dart` first failure `sending a message calls bridge and refreshes`, expected `group:publish`, actual `['bg:begin']`, flow `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED`; `groups` gate `288` passed / `13` failed with the same empty-membership send/media/voice residuals plus known `GM-028`.
- Current row-owned passing evidence: pre-implementation `GCA-006` selector failed as expected at `screen.canWrite == true`; post-implementation `GCA-006` selector passed; `UP-003 composer enables only for an active member with current key` passed; `flutter analyze --no-pub lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart` passed; `git diff --check` passed.
- Owner files touched by this row: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and this plan file.
- Recovery question: tighten the plan around whether the full-suite/gate failures are row-owned. The same empty-membership send/media/voice residual was already recorded as unrelated during `GCA-005` closure before `GCA-006` execution, so a fresh planner should decide whether closure may treat those failures as residual-only while keeping the focused `GCA-006` selector and adjacent `UP-003` selector mandatory.

## Planning Progress

- 2026-05-23T20:36:20+02:00 - Role: Recovery Evidence Collector completed. Files inspected since last update: `## Recovery Input`, source matrix row `GCA-006`, breakdown session `GCA-006`, prior `GCA-005` closure residual notes, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, owner-file diffs. Decision/blocker: full-suite/groups-gate failures match pre-existing empty-membership send/media/voice residuals plus known `GM-028`, not the identity guard. Next action: planner tightens acceptance/gate contract only.
- 2026-05-23T20:36:45+02:00 - Role: Recovery Planner completed. Files inspected since last update: closure bar, exact tests/gates, known-failure interpretation, done criteria. Decision/blocker: classify recovery as acceptance-only; focused `GCA-006`, adjacent `UP-003`, scoped analyze, `git diff --check`, and truthful residual recording are the required closure contract. Next action: reviewer pass.
- 2026-05-23T20:37:05+02:00 - Role: Recovery Reviewer completed. Files inspected since last update: tightened acceptance/gate draft. Decision/blocker: sufficient with adjustments; remove the stale requirement that the full widget suite and groups gate must be green for this row when failures reproduce pre-existing residuals. Next action: arbiter classification.
- 2026-05-23T20:37:25+02:00 - Role: Recovery Arbiter completed. Files inspected since last update: reviewer finding, residual evidence, tightened sections. Decision/blocker: no structural blocker after tightening; broad failures are residual-only unless they fail the focused selector, adjacent selector, scoped analyze, or identity-guard behavior. Next action: hand off for closure using the tightened contract.
- 2026-05-23T20:37:40+02:00 - Role: Recovery plan finalized. Files inspected since last update: this plan. Decision/blocker: final verdict is residual-only; do not reopen product code, tests, source matrix, or breakdown for GCA-006 recovery planning. Next action: controller may record closure/residuals outside this plan if invoked separately.

## Recovery Planning Verdict

Recovery classification: `acceptance-only`.

Final verdict: the full `group_conversation_wired_test.dart` and `./scripts/run_test_gates.sh groups` failures are residual-only for `GCA-006` when they remain limited to the already-recorded empty-membership send/media/voice selectors around `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED` plus known `GM-028`.

They are not row-owned because `GCA-006` owns the missing or late sender-identity guard in `GroupConversationWired`, the source matrix and breakdown scope this row to focused writable-state/send-guard proof, and the same empty-membership residual was recorded as unrelated during `GCA-005` closure before `GCA-006` execution.

Closure may proceed on the current recovery evidence if the focused `GCA-006` selector, adjacent `UP-003` selector, scoped analyze, and `git diff --check` are green, and the broad-suite/groups-gate red results are recorded truthfully with exact failing residual names or signatures. Reclassify as row-owned only if a broad failure hits the focused `GCA-006` selector, the adjacent `UP-003` selector, scoped analysis, `git diff --check`, the identity-unavailable read-only reason, stale identity-missing send suppression, late identity restoration, or a behavior path changed by this row.

## real scope

Change only the group conversation composer identity guard for `GCA-006`: while the sender identity is unavailable, incomplete, or still loading, the group composer must not look writable and a send attempt must not silently drop user text from an enabled composer. Once the existing identity load path supplies a complete identity, the composer may become writable again without changing group membership, key, announcement, media, reaction, or publish semantics.

Expected non-doc implementation/test files for the eventual fix:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

Hard file cap: the executor must touch no more than 3 non-doc implementation/test files. If the fix appears to require `GroupConversationScreen`, `ComposeArea`, identity repository/storage, `send_group_message_use_case.dart`, shared fake infrastructure, database code, bridge code, or any fourth non-doc file, stop and ask before editing.

## closure bar

This session is closed only when an identity-unavailable group conversation cannot show an enabled text composer that drops sends silently, the user sees a concrete read-only reason, a late successful identity load restores the existing send path, and focused tests prove no group publish or message row is created while identity is absent.

Good enough in the current architecture means a small `GroupConversationWired` guard using existing identity state and existing read-only composer behavior. Do not redesign identity loading, add identity listeners, add retry queues, or change the group send use case.

Same-session recovery tightening: the closure bar does not require the full `group_conversation_wired_test.dart` suite or `./scripts/run_test_gates.sh groups` to be green when their failures are limited to pre-existing empty-membership send/media/voice residuals or known `GM-028`. Closure instead requires the focused `GCA-006` selector, the adjacent `UP-003` selector, scoped analyze, `git diff --check`, and an exact residual record for the broad red commands if they were run.

## source of truth

- Source row: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md` row `GCA-006`, which is Open and says the composer can be enabled while identity is missing or late, then send silently returns.
- Breakdown contract: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md` session `GCA-006`, which scopes the work to `GroupConversationWired` and focused writable-state/send-guard tests.
- Gate authority: `Test-Flight-Improv/test-gate-definitions.md`; it says `./scripts/run_test_gates.sh groups` is the named gate when group send behavior changes.
- Current code and tests win over stale prose. If another worker changes these files before execution, re-read them before editing and preserve unrelated edits.

## session classification

`implementation-ready`

## exact problem statement

`GroupConversationWired` starts with `_isCurrentUserActiveMember = true` and `_hasCurrentSendKey = true`, and `_canWriteForGroup` does not require `_ownPeerId` or complete sender keys. `_loadSecurityStatus` and `_refreshSendCapabilityAndCanWrite` also treat `ownPeerId == null` as active-member-compatible. As a result, `GroupConversationScreen` can receive `canWrite: true`; the screen then renders `ComposeArea` instead of the read-only banner. `_onSend` later exits at `if (_ownPeerId == null) return;`, which creates the user-visible silent-send gap.

The fix must preserve existing read-only behavior for dissolved groups, removed members, missing group keys, and non-admin announcement groups. It must also preserve normal sends after identity is available.

## files and repos to inspect next

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`: production seam for identity load, `_canWrite`, read-only banner text, `_refreshSendCapabilityAndCanWrite`, and `_onSend`.
- `test/features/groups/presentation/group_conversation_wired_test.dart`: focused widget test suite and local `FakeIdentityRepository`.
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`: read-only composer behavior; inspect only unless evidence proves the wired guard cannot express the state.
- `lib/features/groups/application/send_group_message_use_case.dart`: inspect only to confirm sender identity parameters stay unchanged.
- `test/shared/fakes/in_memory_group_repository.dart`: inspect only for membership/key setup patterns.
- `Test-Flight-Improv/test-gate-definitions.md`: named gate source.

## existing tests covering this area

- `test/features/groups/presentation/group_conversation_wired_test.dart` already has `UP-003 composer enables only for an active member with current key`, covering removed-member and missing-key read-only states plus stale `onSend` not publishing.
- The same suite exercises ordinary text/media/voice sends, upload failure recovery, quote restoration, reaction permissions, dissolved groups, and announcement read-only behavior.
- `GroupConversationScreen` already hides `ComposeArea` and shows a read-only banner when `canWrite` is false.
- Missing coverage: no focused test proves identity missing or identity loading keeps `canWrite` false, no test proves the banner reason is concrete for identity-unavailable state, and no test proves a stale send callback cannot silently drop user text from an enabled composer in that state.

## regression/tests to add first

Add the failing-first regression in `test/features/groups/presentation/group_conversation_wired_test.dart` before production changes. Use a `GCA-006` test name so it can be selected directly.

Preferred test intent:

1. Arrange an existing active chat group with a current group key and a member row for `testIdentity`, but make `identityRepo.loadIdentity()` unresolved or return `null` at first.
2. Pump `GroupConversationWired`.
3. Assert the composer is not writable while identity is unavailable: `GroupConversationScreen.canWrite` is false, `TextField` is absent, and the read-only banner says a concrete identity reason such as `Waiting for your identity before you can send.`
4. Invoke the stale `screen.onSend` callback with `GCA-006 missing identity send`.
5. Assert no `group:publish` command was sent and no message row with that text exists.
6. If the test uses a delayed identity future, complete it with `testIdentity`, pump, assert the composer becomes writable, send `GCA-006 late identity send`, and assert the normal group publish/message row uses `testIdentity.peerId` and `testIdentity.username`.

If the current local `FakeIdentityRepository` cannot delay `loadIdentity`, keep any test helper change inside `group_conversation_wired_test.dart`. Do not introduce a shared fake or new helper file.

Expected first result before the fix: the identity-unavailable assertions fail because the composer is currently writable.

## step-by-step implementation plan

1. Re-read the current worktree versions of the two target files and confirm the `GCA-006` test does not already exist.
2. Add the failing-first widget regression in `test/features/groups/presentation/group_conversation_wired_test.dart`. Run only the new selector and confirm it fails for the expected writable-composer reason. If it passes before production changes, stop and classify the row as stale/already-covered instead of editing production.
3. In `GroupConversationWired`, make writable state require complete sender identity before allowing `canWrite: true`. Keep this local to existing fields: `_ownPeerId`, `_senderUsername`, `_senderPublicKey`, and `_senderPrivateKey`.
4. Add or adjust read-only banner selection in `GroupConversationWired` so the identity-unavailable case has a concrete reason and does not fall through to the announcement admin text.
5. Ensure any identity loaded inside `_loadSecurityStatus` or `_refreshSendCapabilityAndCanWrite` copies the full sender identity fields, not only `_ownPeerId`, so late identity does not send with blank username/public/private key values.
6. Keep `_onSend` defensive: if identity is still incomplete, it must not publish, pre-persist an optimistic row, clear the draft, or upload media. Do not add a queue or background retry path.
7. Rerun the focused selector, the existing `UP-003` selector, scoped analysis, and `git diff --check`. Format may be recorded if files were reformatted. The full `group_conversation_wired_test.dart` suite and `./scripts/run_test_gates.sh groups` are diagnostic residual-classification commands for same-session recovery, not row-closure blockers when they fail only on the pre-existing empty-membership send/media/voice residuals or known `GM-028`.
8. If any step requires more than the two expected files or a fourth non-doc implementation/test file, stop and ask with the evidence.

## risks and edge cases

- Late identity load: the guard must not permanently freeze the composer after `_loadIdentity` or `_loadSecurityStatus` obtains a complete identity.
- Blank credentials: setting only `_ownPeerId` during refresh can allow sends with empty sender username/public/private key fields; the implementation must avoid that.
- Existing read-only reasons: dissolved, removed-member, missing-key, and non-admin announcement banners must keep their current precedence except the identity-unavailable state must not show the wrong admin text.
- Stale callback: a previously captured `onSend` callback must not publish or save rows while identity is absent.
- Attachments/voice: do not start upload, media preparation, voice send, or draft clearing before identity is complete.

## exact tests and gates to run

Failing-first:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GCA-006"
```

Required closure commands after implementation or recovery:

```bash
flutter analyze --no-pub lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GCA-006"
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "UP-003 composer enables only for an active member with current key"
git diff --check
```

Implementation hygiene command to record when code/test files are edited:

```bash
dart format --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart
```

Diagnostic residual commands, if run:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart
./scripts/run_test_gates.sh groups
```

The diagnostic commands above do not block `GCA-006` closure under same-session recovery when their failures match the pre-existing empty-membership send/media/voice residuals or known `GM-028`; record the exact failing selectors/signatures instead.

Manual verification step:

- In a debug run, open an active group while local identity is unavailable or deliberately delayed; verify the composer is read-only with the identity waiting reason, then restore identity/reopen the group and verify one text message sends normally without duplicate rows.

## known-failure interpretation

The focused `GCA-006` selector, adjacent `UP-003` selector, scoped analyze command, and `git diff --check` must pass for closure. Any failure in those commands is row-owned unless it is proven to be infrastructure-only and rerun evidence proves the row-owned behavior.

The full `group_conversation_wired_test.dart` suite and `./scripts/run_test_gates.sh groups` are residual-classification evidence, not automatic `GCA-006` blockers. If they are red only on the same empty-membership send/media/voice selectors already recorded during `GCA-005` closure, or on known `GM-028`, classify those failures as residual-only and record exact failing test names, first assertion lines, and signatures such as `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED`.

Do not claim `GCA-006` closure if a broad failure is in the focused `GCA-006` selector, adjacent `UP-003` selector, scoped analysis, `git diff --check`, the missing-identity read-only reason, stale identity-missing send suppression, late identity restoration, or a changed `GroupConversationWired` behavior path.

## done criteria

- The plan's failing-first `GCA-006` test fails before production edits for the expected enabled-composer/missing-identity reason.
- After implementation, identity-unavailable state renders read-only UI with a concrete identity reason.
- A stale send attempt while identity is unavailable creates no optimistic row, no persisted message, no media/upload work, and no `group:publish`.
- Late complete identity through the existing load path restores normal writable send behavior.
- Only the expected product/test files are changed unless the executor stopped and received approval.
- Required closure evidence is green: focused `GCA-006` selector, adjacent `UP-003` selector, scoped analyze, and `git diff --check`.
- Any full-suite or groups-gate red result is recorded as residual-only only when it matches the pre-existing empty-membership send/media/voice failures or known `GM-028`; otherwise it is row-owned and blocks closure until explained or fixed.

## scope guard

Do not edit product code outside `GroupConversationWired` unless the executor stops and asks. Do not edit `send_group_message_use_case.dart`, identity repository implementations, database migrations, bridge code, `ComposeArea`, or shared test fake files in this session. Do not add an identity observer, retry queue, new send result type, telemetry schema, persistence model, or new abstraction. Do not change media, voice, reaction, announcement authorization, membership, group key, invite, or message-retry semantics.

This planning session must not edit the source matrix or breakdown. Implementation/closure work may update closure docs after code and tests pass, but those doc edits do not relax the three-file non-doc cap.

## accepted differences / intentionally out of scope

- One-to-one conversation identity handling is not part of `GCA-006`.
- Permanent identity-loss recovery, account repair, login routing, and identity repository health checks are out of scope.
- `GCA-007` optimistic-message handling for unauthorized or missing-group send results remains a separate row.
- No UX redesign is required beyond the concrete read-only reason.

## dependency impact

Closing `GCA-006` gives later group composer/send sessions a stable precondition: visible writable group composer means a complete sender identity exists. If this plan changes to require identity repository or screen-level changes, revisit `GCA-007` and any later composer/send plan before implementation because their assumptions about stale `onSend` and optimistic rows may change.

## Evidence Collector Notes

- `group-chat-audit-gap-closure-matrix.md` row `GCA-006` is Open and scoped to `GroupConversationWired`, focused tests.
- `group-chat-audit-gap-closure-session-breakdown.md` says exact scope is to ensure missing identity disables composer or shows a concrete send error instead of allowing an enabled send that silently returns.
- `GroupConversationWired` initializes `_isCurrentUserActiveMember` and `_hasCurrentSendKey` to true, stores identity in `_ownPeerId`, `_senderUsername`, `_senderPublicKey`, and `_senderPrivateKey`, and calls `_loadIdentity()` plus `_loadSecurityStatus()` in `initState`.
- `_loadSecurityStatus` and `_refreshSendCapabilityAndCanWrite` currently compute `isCurrentUserActiveMember` as true when `ownPeerId == null`.
- `_refreshSendCapabilityAndCanWrite` currently sets `_ownPeerId` from a late identity but does not copy username/public/private key fields.
- `_onSend` currently returns silently when `_ownPeerId == null`.
- `GroupConversationScreen` already hides `ComposeArea` when `canWrite` is false, so this should be expressible from wired state without screen changes.
- Existing `UP-003` test covers active member/key guards but not missing identity.

## Reviewer Pass

Reviewer status: sufficient as-is.

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is. The draft includes explicit scope, closure bar, source of truth, failing-first regression, minimal implementation files, named gate, known-failure rules, done criteria, and hard file cap.
- What files, tests, regressions, or gates are missing? None required for execution safety. `GroupConversationScreen` and `send_group_message_use_case.dart` are correctly inspect-only unless evidence forces a stop.
- What assumptions are stale or incorrect? None found in the current worktree evidence. The executor must still re-read the target files because the worktree is active.
- What is overengineered? Nothing structural. The plan forbids production abstractions, retry queues, identity observers, and send use-case changes.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It is one widget-state behavior plus one focused widget regression.
- Minimum needed to make the plan sufficient: already present; preserve the three-file stop rule and the `GCA-006` failing-first selector.

## Arbiter Decision

Arbiter status: execution-ready.

- Structural blockers: none.
- Incremental details: none required before implementation. The executor may choose a nearby exact banner phrase if repo wording has changed, but the focused test must still assert a concrete identity-unavailable reason.
- Accepted differences: no 1:1 identity parity work, no identity repository recovery, no `send_group_message_use_case.dart` change, and no `GCA-007` optimistic-message result handling in this session.
- Stop rule result: no structural blocker found, so planning stops after this arbiter pass.
