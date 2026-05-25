# GSPR-001 - Durable replay helper for direct system publishes

Status: execution-complete

## Planning Progress

- 2026-05-23 21:13:00 CEST - Planner completed. Files inspected since last update: `lib/core/bridge/bridge_group_helpers.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, caller tests. Decision/blocker: draft is execution-safe if it keeps normal sends, Go publish, schema, and broad caller migration out of scope. Next action: reviewer pass.
- 2026-05-23 21:14:04 CEST - Reviewer started. Files inspected since last update: current plan artifact, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`. Decision/blocker: no structural blocker found; retry verification command needs exact selectors. Next action: patch selector wording and record reviewer verdict.
- 2026-05-23 21:14:04 CEST - Reviewer completed. Files inspected since last update: same. Decision/blocker: sufficient with adjustment; exact retry selectors replace broad `--plain-name 'retry'`. Next action: arbiter classification.
- 2026-05-23 21:14:35 CEST - Arbiter started. Files inspected since last update: reviewer-adjusted plan. Decision/blocker: no structural blocker identified; accepted call-site differences are documented. Next action: record final arbiter decision and mark execution-ready.
- 2026-05-23 21:14:35 CEST - Arbiter completed. Files inspected since last update: same. Decision/blocker: execution-ready; no blockers remain. Next action: hand off to execution agent.

## Execution Progress

- 2026-05-23 21:16:08 CEST - Phase: before contract extraction. Files inspected/touched: `implementation-execution-qa-orchestrator` skill, this plan, `git status --short`, owner production/test files. Command currently running: none. Decision/blocker: no child-agent spawn tool is exposed in this environment, so the isolated invocation is using the skill's local sequential fallback with explicit evidence rather than widening scope. Next action: extract exact contract before coding.
- 2026-05-23 21:16:08 CEST - Phase: after contract extraction. Files inspected/touched: this plan, `lib/features/groups/application/dissolve_group_use_case.dart`, replay/retry/model/repository/bridge helper references, existing dissolve test. Command currently running: none. Decision/blocker: contract is execution-safe; owner files to edit are limited to the new helper, dissolve use case, helper test, dissolve test, and this progress ledger. Required red selectors, focused tests, scoped format/analyze, and `git diff --check` are explicit. Next action: write red tests first.
- 2026-05-23 21:18:18 CEST - Phase: before red tests. Files inspected/touched: `test/features/groups/application/group_system_publish_use_case_test.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`, this plan. Command currently running: none. Decision/blocker: required helper and dissolve regressions have been added before implementation. Next action: run the three red-first selectors exactly.
- 2026-05-23 21:18:58 CEST - Phase: after red tests. Files inspected/touched: helper test and dissolve test. Commands finished: (1) `flutter test --no-pub test/features/groups/application/group_system_publish_use_case_test.dart --plain-name 'GSPR-001 helper records retryable timeline row when replay store fails'` failed to load because `group_system_publish_use_case.dart` is missing and `publishGroupSystemMessage` is undefined; (2) `flutter test --no-pub test/features/groups/application/group_system_publish_use_case_test.dart --plain-name 'GSPR-001 helper clears retry state when replay store succeeds'` failed for the same missing helper; (3) `flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart --plain-name 'GSPR-001 dissolve inbox store failure leaves timeline row retryable'` reached current behavior and failed at `inboxRetryPayload` expected non-null, actual null. Decision/blocker: red-first evidence is valid and scoped to the missing helper/retryable timeline state. Next action: implement minimum helper and migrate dissolve caller.
- 2026-05-23 21:20:02 CEST - Phase: before implementation. Files inspected/touched: `lib/features/groups/application/dissolve_group_use_case.dart`, replay/retry helpers, owner tests, this plan. Command currently running: none. Decision/blocker: implementation will be limited to a new Dart helper plus the dissolve caller, preserving normal `sendGroupMessage`, Go `GroupPublish`, schema, relay, and other direct callers. Next action: add helper and wire dissolve to persist the helper-returned timeline row.
- 2026-05-23 21:21:29 CEST - Phase: after implementation. Files inspected/touched: `lib/features/groups/application/group_system_publish_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, helper and dissolve tests, this plan. Command currently running: none. Decision/blocker: helper now wraps `callGroupPublish`, builds existing signed replay retry payloads, stores via retry payload, saves supplied timeline rows only as retryable on store failure, and dissolve persists the helper-returned row. Next action: rerun the three red-first selectors as green checks.
- 2026-05-23 21:22:14 CEST - Phase: before focused verification. Files inspected/touched: helper/dissolve production and tests, this plan. Commands finished before this phase: all three GSPR-001 selectors now pass after implementation. Decision/blocker: no selector-level blocker remains. Next action: run the plan's focused files, retry selectors, scoped format/analyze, and `git diff --check`.
- 2026-05-23 21:24:49 CEST - Phase: after focused verification. Files inspected/touched: owner production/tests and this plan. Commands finished: `flutter test --no-pub test/features/groups/application/group_system_publish_use_case_test.dart` passed 2 tests; `flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart` passed 8 tests; retry selector `retries eligible sent messages and clears inbox retry state` passed; retry selector `retries eligible pending messages and promotes them to sent` passed; `dart format --set-exit-if-changed lib/features/groups/application/group_system_publish_use_case.dart lib/features/groups/application/dissolve_group_use_case.dart test/features/groups/application/group_system_publish_use_case_test.dart test/features/groups/application/dissolve_group_use_case_test.dart` passed with `Formatted 4 files (0 changed)`; scoped `dart analyze ...` passed with `No issues found!`; `git diff --check` passed. Optional confidence command `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` was feasible and was run; it failed with exit code 1 after broad integration failures outside owner files, final visible summary `+288 -13` with failures in `group_startup_rejoin_smoke_test.dart`, `group_messaging_smoke_test.dart`, and `group_membership_smoke_test.dart` (example visible failures: BB-012, NW-004, IR-018, GM-028). Decision/blocker: required host-only proof is green; optional broader groups gate has unrelated existing/broader failures and is not part of this session's closure bar. Next action: run QA review.
- 2026-05-23 21:25:34 CEST - Phase: before QA. Files inspected/touched: owner diffs, test results, this plan. Command currently running: none. Decision/blocker: local sequential fallback QA will check scope, behavior, required tests/gates, optional gate classification, and dirty-worktree isolation. Next action: perform QA sufficiency review.
- 2026-05-23 21:26:11 CEST - Phase: after QA. Files inspected/touched: `lib/features/groups/application/group_system_publish_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, helper/dissolve tests, owner diffs, this plan. Command currently running: none. Decision/blocker: no blocking QA issues found. Scope stayed within owner files plus this plan, normal `sendGroupMessage` and Go `GroupPublish` were not edited, and required tests/gates passed. Non-blocking follow-up: optional broad `groups` gate remains red outside this session's closure bar. Next action: write final verdict.
- 2026-05-23 21:26:11 CEST - Phase: before final verdict. Files inspected/touched: this plan. Command currently running: none. Decision/blocker: sufficiency rule is met for required GSPR-001 proof; optional broad gate failure will be recorded as explicit non-blocking follow-up. Next action: write final execution verdict.

## Final Execution Verdict

Verdict: `accepted_with_explicit_follow_up`.

Blocking issues remaining: none.

Non-blocking follow-up: optional `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` failed with broad integration failures outside this session's owner scope (`+288 -13`, examples visible in startup rejoin, messaging smoke, and membership smoke tests). Required GSPR-001 focused proof, scoped format, scoped analyze, and whitespace checks passed.

Changed files for this session:

- `lib/features/groups/application/group_system_publish_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `test/features/groups/application/group_system_publish_use_case_test.dart`
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/group-system-publish-durable-replay-session-GSPR-001-plan.md`

- 2026-05-23 21:26:11 CEST - Phase: after final verdict. Files inspected/touched: this plan. Command currently running: none. Decision/blocker: final verdict written as `accepted_with_explicit_follow_up`; no required proof is missing. Next action: return final execution summary.

## Real Scope

Implement one small Dart application-layer helper for direct group system-message publishes, then prove it through the helper itself and one representative caller that owns a local timeline row.

In scope:

- Add `lib/features/groups/application/group_system_publish_use_case.dart`.
- Reuse existing `callGroupPublish`, `buildGroupOfflineReplayInboxRetryPayload`, and `storeGroupOfflineReplayFromRetryPayload`.
- When replay storage fails and the caller supplies both `GroupMessageRepository` and a local `GroupMessage`, persist that timeline row with `inboxStored: false`, a non-null `inboxRetryPayload`, and a retry-eligible local/outgoing status so `retryFailedGroupInboxStores` can close it later.
- Migrate one representative direct system-publish caller with a timeline row and recipient list, preferably `dissolveGroup(...)` in `lib/features/groups/application/dissolve_group_use_case.dart`, because it already publishes `group_dissolved`, stores replay, persists a timeline row, and has focused tests.
- Add focused host-only tests under `test/features/groups/application/`.

Out of scope:

- Do not change the normal `sendGroupMessage(...)` path except for an unavoidable import-only shared helper dependency.
- Do not change Go `GroupPublish`, bridge protocol, relay protocol, or native inbox behavior.
- Do not add tables, migrations, outbox rows, cursors, relay endpoints, background jobs, or broad retries.
- Do not refactor group membership, key rotation, invite, leave, metadata, or UI flows beyond the one representative caller proof.
- Do not clean, revert, or normalize unrelated dirty worktree changes.

## Closure Bar

This session is good enough when a direct system-message publish can:

- publish through the existing low-level bridge helper;
- create the same signed encrypted `group_offline_replay` retry payload shape used by normal sends;
- attempt relay inbox storage for recipient peers;
- leave a supplied local timeline row retryable when inbox storage fails; and
- pass the focused helper/caller tests, scoped format/analyze, and whitespace checks without relying on simulator or live relay state.

The closure bar does not require full migration of every direct system publish site. Remaining direct callers stay inventoried as accepted follow-up scope unless they are trivial to migrate without adding behavior, tests, or ownership conflicts.

## Source of Truth

- Active session contract: `Test-Flight-Improv/Group-Chat-Feature/group-system-publish-durable-replay-session-breakdown.md`.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Current code and tests beat stale prose.
- Existing retry contract: `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`.
- Existing replay envelope contract: `lib/features/groups/application/group_offline_replay_envelope.dart`.
- Existing normal-send behavior: `lib/features/groups/application/send_group_message_use_case.dart`; do not broaden this path.

## Session Classification

`implementation-ready`

No prerequisite code or schema work is needed. The worktree is dirty from parallel sessions, so the executor must inspect touched files before editing and must not revert unrelated local changes.

## Exact Problem Statement

Normal group sends prebuild a signed offline replay envelope and persist `inboxRetryPayload` on the local row before publishing. Direct group system publishes can call `callGroupPublish` and `storeGroupOfflineReplayEnvelope` separately, so a publish can succeed while relay replay storage fails without leaving retryable state on the local timeline row. Offline members can then miss system messages until some other recovery path repairs state.

This session must add a minimal Dart helper so direct system-message callers with local timeline rows can leave failed replay storage retryable. User-message sending, native `GroupPublish`, bridge request shape, and relay storage protocol must stay unchanged.

## Files And Repos To Inspect Next

Production:

- `lib/features/groups/application/group_system_publish_use_case.dart` - new helper owner.
- `lib/features/groups/application/dissolve_group_use_case.dart` - representative caller to migrate first.
- `lib/features/groups/application/group_offline_replay_envelope.dart` - existing signed replay envelope and retry payload builders.
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart` - retry eligibility and closure behavior.
- `lib/features/groups/domain/models/group_message.dart` - `copyWith`, `inboxStored`, `inboxRetryPayload`, and status/isIncoming fields.
- `lib/features/groups/domain/repositories/group_message_repository.dart` - update/save methods used by helper.
- `lib/core/bridge/bridge_group_helpers.dart` - `callGroupPublish` and `callGroupInboxStore` behavior.

Tests:

- `test/features/groups/application/group_system_publish_use_case_test.dart` - new helper tests.
- `test/features/groups/application/dissolve_group_use_case_test.dart` - representative caller regression.
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` - existing retry behavior reference; do not duplicate broadly.
- `test/shared/fakes/in_memory_group_message_repository.dart` and `test/core/bridge/fake_bridge.dart` - host-only fakes.

Inventory-only direct callers:

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`

## Existing Tests Covering This Area

- `test/features/groups/application/dissolve_group_use_case_test.dart` already proves a successful dissolve stores a signed `group_dissolved` replay envelope and that inbox fallback failure still marks the group dissolved.
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` already proves successful invite acceptance stores a signed `member_joined` replay envelope.
- `test/features/groups/application/send_group_message_use_case_test.dart` already has broad normal-send durability coverage, including `inboxRetryPayload` persistence. Do not move or rewrite those tests for this session.
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` already proves retry rows with `inboxRetryPayload` are retried and cleared on success.
- Missing today: a direct system-publish helper proof that failed replay storage updates a local timeline row into retryable state, and a caller-level proof that at least one real system-message flow uses that helper.

## Regression/Tests To Add First

Add these red tests before implementation:

1. `test/features/groups/application/group_system_publish_use_case_test.dart`
   - Selector: `GSPR-001 helper records retryable timeline row when replay store fails`
   - Arrange `FakeBridge` with successful `group:publish` and failed `group:inboxStore`.
   - Call the new helper with a local timeline `GroupMessage`, `InMemoryGroupMessageRepository`, recipient peer IDs, sender keys, and replay plaintext.
   - Expect `group:publish` and `group:inboxStore` were attempted, the saved row has `inboxStored == false`, `inboxRetryPayload != null`, and is eligible for `retryFailedGroupInboxStores`.
   - Then flip `group:inboxStore` to success, call `retryFailedGroupInboxStores`, and expect the row becomes `inboxStored == true`, `inboxRetryPayload == null`, and `status == 'sent'`.

2. `test/features/groups/application/group_system_publish_use_case_test.dart`
   - Selector: `GSPR-001 helper clears retry state when replay store succeeds`
   - Arrange successful publish and inbox store.
   - Expect the helper does not leave a retry payload and does not create a failed-inbox row.

3. `test/features/groups/application/dissolve_group_use_case_test.dart`
   - Selector: `GSPR-001 dissolve inbox store failure leaves timeline row retryable`
   - Extend or add beside the existing inbox-failure dissolve test.
   - Arrange `group:inboxStore` failure.
   - Expect the group is still dissolved per existing behavior, the local `sys-group_dissolved` timeline row exists, and that row has retryable `inboxRetryPayload` state. A follow-up `retryFailedGroupInboxStores` with `group:inboxStore` success should clear it.

If red tests cannot fail for the intended reason because another parallel session already implemented equivalent behavior, stop and reclassify as `stale/already-covered` with evidence instead of adding duplicate code.

## Step-By-Step Implementation Plan

1. Dirty-state intake:
   - Run `git status --short`.
   - Inspect any touched owner file before editing, especially files already modified by parallel sessions.
   - Do not revert or restyle unrelated hunks.

2. Write red tests:
   - Add `group_system_publish_use_case_test.dart` with the helper behavior tests.
   - Extend `dissolve_group_use_case_test.dart` with the caller-level retryable timeline row regression.
   - Run the selectors and confirm they fail on missing helper or missing retry state, not on unrelated fixture failures.

3. Add helper:
   - Create `group_system_publish_use_case.dart`.
   - Keep the helper synchronous/sequential at the application layer: call `callGroupPublish`, build a signed replay retry payload, then attempt `storeGroupOfflineReplayFromRetryPayload`.
   - Return a tiny result object carrying `publishResult`, `inboxStored`, `inboxRetryPayload`, and the timeline row copy the caller should persist if needed.
   - If replay payload creation fails, emit one flow event and return without inventing an unsendable retry payload.
   - If inbox store fails and `msgRepo` plus `timelineMessage` are supplied, save or return a copy with retryable state. The row must be eligible for `retryFailedGroupInboxStores` under its current query: local outgoing, `status` in `sent`/`pending`, `inboxStored == false`, `inboxRetryPayload != null`.
   - If inbox store succeeds, do not leave a retry payload. Mark supplied row `inboxStored: true` only if doing so does not disturb existing caller behavior.

4. Migrate representative caller:
   - Replace the direct `callGroupPublish` plus `storeGroupOfflineReplayEnvelope` block in `dissolveGroup(...)` with the helper.
   - Preserve publish-failure semantics: publish exceptions still produce `DissolveGroupResult.bridgeError` before local group mutation.
   - Preserve current dissolve side effects: group state updates, timeline message persists, `group:leave` still runs, and inbox-store failure still reports a bridge recovery gap.
   - Persist the helper-returned timeline row copy so replay failure is not overwritten by the original row.

5. Leave other direct callers unchanged unless the same helper can be adopted without extra behavior:
   - Do not migrate `accept_pending_group_invite_use_case.dart`, `broadcast_voluntary_leave_use_case.dart`, `create_group_with_members_use_case.dart`, or `rotate_and_distribute_group_key_use_case.dart` in this session unless the caller test already being edited proves the change and no new semantics are needed.
   - Record any unmigrated direct caller as accepted follow-up in the implementation notes.

6. Run focused green tests, then scoped full files, then format/analyze/diff checks.

## Risks And Edge Cases

- Retry eligibility: `retryFailedGroupInboxStores` currently selects only outgoing rows with `status` `sent` or `pending`; helper failure state must match that query.
- Timeline semantics: system timeline rows are often built as incoming/delivered; changing only failure-state rows should avoid broad unread or UI changes.
- Publish exception semantics: direct callers differ. Do not normalize all callers through one exception policy.
- Replay-envelope build failure: without a signed envelope there is no safe retry payload; log and preserve existing caller behavior.
- Recipient list empty: skip inbox store and do not create a retry payload.
- Dirty worktree: owner files may include unrelated parallel edits; work with them, do not revert.
- Duplicate sends: retry should only replay relay inbox storage, not re-run `group:publish`.

## Exact Tests And Gates To Run

Red-first selectors:

```bash
flutter test --no-pub test/features/groups/application/group_system_publish_use_case_test.dart --plain-name 'GSPR-001 helper records retryable timeline row when replay store fails'
flutter test --no-pub test/features/groups/application/group_system_publish_use_case_test.dart --plain-name 'GSPR-001 helper clears retry state when replay store succeeds'
flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart --plain-name 'GSPR-001 dissolve inbox store failure leaves timeline row retryable'
```

Focused green files:

```bash
flutter test --no-pub test/features/groups/application/group_system_publish_use_case_test.dart
flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'retries eligible sent messages and clears inbox retry state'
flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'retries eligible pending messages and promotes them to sent'
```

Scoped analysis and formatting:

```bash
dart format --set-exit-if-changed lib/features/groups/application/group_system_publish_use_case.dart lib/features/groups/application/dissolve_group_use_case.dart test/features/groups/application/group_system_publish_use_case_test.dart test/features/groups/application/dissolve_group_use_case_test.dart
dart analyze lib/features/groups/application/group_system_publish_use_case.dart lib/features/groups/application/dissolve_group_use_case.dart test/features/groups/application/group_system_publish_use_case_test.dart test/features/groups/application/dissolve_group_use_case_test.dart
git diff --check
```

Named gate stance:

- The active breakdown requires focused Flutter tests plus scoped format/analyze evidence.
- `Test-Flight-Improv/test-gate-definitions.md` says `./scripts/run_test_gates.sh groups` is relevant when group retry or invite behavior changes. For this host-only session, do not require a simulator or live relay gate. If reviewer asks for named-gate confidence after implementation, run:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

## Host-Only Device/Relay Proof Profile

This session's required proof profile is host-only:

- Device proof: not required. No iOS/Android simulator, physical device, or multi-device orchestration is needed.
- Relay proof: not required. `FakeBridge` verifies `group:publish` and `group:inboxStore` request shape and failure behavior.
- Durable proof: host `InMemoryGroupMessageRepository` plus `retryFailedGroupInboxStores` proves failed replay storage becomes retryable and later clears without re-publishing.
- Optional companion: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` can be used as a host desktop named-gate confidence pass, but live relay evidence is intentionally out of scope.

## Known-Failure Interpretation

- A red GSPR selector before implementation is expected only if it fails because retryable timeline state is missing.
- Existing dirty worktree failures outside `group_system_publish_use_case.dart`, `dissolve_group_use_case.dart`, and their focused tests are not blockers unless they reproduce in the focused commands above or affect the helper/caller contract.
- Do not waive new failures in the focused helper, dissolve, or retry selectors.
- If `dart analyze` reports unrelated diagnostics from parallel edits outside the scoped files, rerun the scoped command after confirming the diagnostics are outside this session and document them instead of broadening the fix.

## Done Criteria

- `group_system_publish_use_case.dart` exists and uses existing bridge/replay helpers.
- Helper tests prove failed replay storage leaves a retryable local timeline row and retry later clears it.
- A representative caller test proves `dissolveGroup(...)` uses the helper behavior with a real system timeline row.
- Normal `sendGroupMessage(...)` behavior is unchanged.
- Go `GroupPublish` and relay protocol are unchanged.
- Focused tests, scoped format, scoped analyze, and `git diff --check` pass or have documented unrelated residuals.

## Scope Guard

Stop rather than broaden if implementation pressure appears in any of these areas:

- new SQLite table, migration, outbox, relay endpoint, cursor, protocol, or Go change;
- changes to normal user-message send semantics;
- broad migration of every direct publish path;
- UI/presentation refactors;
- retrying live `group:publish` from `retryFailedGroupInboxStores`;
- handling replay-envelope build failures by storing unsigned or plaintext fallback payloads.

## Accepted Differences / Intentionally Out Of Scope

- Normal user messages already own a stronger pre-persist contract and remain unchanged.
- Reactions use `GroupReactionReplayOutboxEntry`; do not merge that outbox with system timeline rows.
- `create_group_with_members_use_case.dart` and `rotate_and_distribute_group_key_use_case.dart` publish system messages but do not clearly own a local timeline row in the inspected code; leave them unchanged.
- `accept_pending_group_invite_use_case.dart` and `broadcast_voluntary_leave_use_case.dart` have timeline-row-shaped flows, but they differ in publish exception handling and optional repository ownership. Leave them as follow-up unless they can be migrated without extra behavior and with direct tests.
- Live relay, multi-device, and simulator acceptance are intentionally not part of this host-only session.

## Dependency Impact

Later group reliability work can reuse the helper for additional direct system-publish call sites after this session proves the helper/caller contract. If this plan changes away from timeline-row retry state, later sessions must not assume `retryFailedGroupInboxStores` can recover direct system publishes from `GroupMessage` rows.

## Reviewer Closure Bar

The reviewer should reject implementation if:

- tests are not red-first for both helper behavior and a representative caller;
- the helper cannot produce a retry payload compatible with `storeGroupOfflineReplayFromRetryPayload`;
- the saved timeline row is not eligible for `retryFailedGroupInboxStores`;
- normal `sendGroupMessage` or Go `GroupPublish` changed behavior;
- unrelated dirty worktree edits were reverted or mixed into the session.

## Reviewer Pass

Verdict: sufficient with adjustment.

- Missing files/tests/gates: no required owner file is missing; the new helper test file and dissolve caller test are explicit. The retry reference command was too broad and has been replaced with exact selectors.
- Stale assumptions: none found. Current code confirms normal sends already prebuild retry payloads, direct system publishes call `callGroupPublish`, and retry eligibility is row-based.
- Overengineering: no schema, Go, relay, or broad migration work is included.
- Decomposition: narrow enough for execution. Helper behavior and one caller are separately testable.
- Minimum needed for sufficiency: keep the accepted out-of-scope caller inventory explicit and preserve the host-only proof profile.

## Arbiter Decision

Verdict: execution-ready.

- Structural blockers: none.
- Incremental details: exact naming of the helper result object can be chosen during implementation as long as it stays tiny and test-covered.
- Accepted differences: full migration of every direct system publish caller is intentionally out of scope for this session; the plan requires one representative caller proof and records the rest as follow-up inventory.
- Stop decision: stop planning now and execute. Do not add schema, Go, relay, or broad caller work during GSPR-001.

## Arbiter Stop Rule

If review finds no structural blocker, stop and execute this plan. If review finds a structural blocker, patch this plan once, then run one final reviewer pass and one final arbiter pass. Do not keep looping over incremental wording or broaden accepted follow-up callers into this session.
