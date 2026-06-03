Status: accepted

# 102 GIRD-001 - Sender In-Doubt Send Classification and Reconciliation Plan

## Planning Progress

| Time | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| `2026-05-31 17:40 CEST` | Evidence Collector started | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`; `Test-Flight-Improv/test-gate-definitions.md`; `Test-Flight-Improv/14-regression-test-strategy.md` | Confirmed GIRD-001 is implementation-ready, dependency-free, and scoped to sender in-doubt reliable-send classification plus same-id sender reconciliation. No blocker. | Inspect likely owner production files and direct tests, then draft the reusable plan. |
| `2026-05-31 17:41 CEST` | Evidence Collector completed / Planner started | `lib/core/bridge/bridge_group_helpers.dart`; `lib/features/groups/application/send_group_message_use_case.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `lib/features/groups/domain/repositories/group_message_repository.dart`; `lib/features/groups/domain/repositories/group_message_repository_impl.dart`; `lib/core/database/helpers/group_messages_db_helpers.dart`; likely direct tests | Current code marks reliable `BRIDGE_TIMEOUT` and reliable zero-peer/publish-success/inbox-fail as failed, while same-id self replay only reconciles `sending`/`pending`. No blocker. | Draft narrow RED-first implementation plan and host-only proof profile. |
| `2026-05-31 17:43 CEST` | Planner completed / Reviewer started | Draft plan artifact | Reviewer found one structural gap: RED test expectations used broad `not failed` assertions without exact result/status for in-doubt sender state. | Patch exact expected outcomes, then rerun final reviewer/arbiter pass. |
| `2026-05-31 17:43 CEST` | Reviewer completed / Arbiter completed | Patched plan artifact | Final reviewer found the plan sufficient. Arbiter accepted GIRD-001 as host-only with GIRD-007 simulator/device proof deferred by source breakdown; no structural blockers remain. | Ready for implementation execution in a later session. |

## Execution Progress

| Time | Phase | Files inspected or touched | Command/evidence | Decision/blocker | Next action |
|---|---|---|---|---|---|
| `2026-05-31 17:45 CEST` | pre-execution dirty snapshot | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md` | `git status --short`: `M scripts/check_reliability_simulation_discovery.sh`; `?? Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md`; `?? Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`; `?? Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md` | Dirty tree recorded; unrelated modified reliability discovery script and untracked 102 docs must not be reverted. | Extract execution contract, then spawn Executor. |
| `2026-05-31 17:45 CEST` | contract extracted | Plan sections: `real scope`, `closure bar`, `source of truth`, `regression/tests to add first`, `exact tests and gates to run`, `known-failure interpretation`, `done criteria`, `scope guard` | Scope: sender reliable in-doubt classification plus same-id own replay repair only. RED tests: bridge timeout guard, two send use-case GIRD-001 regressions, one incoming self-replay repair regression. Required gates: listed direct RED/green and preservation commands, `./scripts/run_test_gates.sh groups`, `git diff --check`; `transport` only if bridge behavior changes beyond timeout coverage. | Contract is executable and host-only; no replan/blocker. | Spawn isolated Executor with model `gpt-5.5` and `reasoning_effort: xhigh`. |
| `2026-05-31 17:46 CEST` | Executor spawned/running | Assigned GIRD-001 plan and scoped owner files/tests to spawned worker `019e7eb6-5a93-7a42-83cc-caa7f6830166` (`Bernoulli`) | Spawned with `model: gpt-5.5`, `reasoning_effort: xhigh`; instructed to add RED tests first, run focused failure proof, implement, run required direct/preservation/gate commands, and update this progress table. | No blocker. | Wait for Executor result, then spawn separate QA Reviewer. |
| `2026-05-31 17:46 CEST` | Executor pass started | Plan and breakdown orientation read; dirty snapshot confirmed | `git status --short`: unrelated `scripts/check_reliability_simulation_discovery.sh` modified; untracked 102 docs present | Scope held to GIRD-001. Bridge helper timeout coverage may be guard-green; application regressions must RED before production edits. | Inspect owner files/tests, add planned RED tests first. |
| `2026-05-31 17:48 CEST` | RED tests added | `test/core/bridge/bridge_group_helpers_test.dart`; `test/features/groups/application/send_group_message_use_case_test.dart`; `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` | Added the four planned GIRD-001 tests before production edits. | No blocker. | Run focused RED commands and confirm expected application failures. |
| `2026-05-31 17:49 CEST` | RED proof complete | Same three direct test files | `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupSendReliable"` passed; `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"` failed because both new send cases returned `SendGroupMessageResult.error`; `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-001"` failed because same-id failed row returned `null` duplicate handling. | Failures match planned gap; bridge helper is guard-green. | Implement narrow reliable in-doubt classifier and failed-row self replay repair. |
| `2026-05-31 17:50 CEST` | implementation complete | `lib/features/groups/application/send_group_message_use_case.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; touched tests formatted | Added reliable in-doubt pending classifier for `BRIDGE_TIMEOUT` and reliable publish-zero-peers/no-custody; widened same-id self replay repair to failed outgoing rows with retry evidence. | No blocker; no repository/helper or bridge behavior changes beyond test coverage. | Run focused green direct suites, then preservation suites and required gate. |
| `2026-05-31 17:50 CEST` | direct GREEN complete | Direct GIRD-001 test files | `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupSendReliable"` passed; `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"` passed; `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-001"` passed. | New regressions now green. | Run planned preservation suites. |
| `2026-05-31 17:51 CEST` | preservation GREEN complete | `test/features/groups/application/send_group_message_use_case_test.dart`; `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` | Preservation commands for `GSR-001`, `PGC-010` reliable partial fanout, `DE-008` publish timeout plus inbox custody, `DE-005` pending self echo, and same-message-id pubsub/inbox dedupe all passed. | Existing reliable and same-id behaviors preserved. Conditional repository/helper and transport gates not required by code scope. | Run `./scripts/run_test_gates.sh groups`, then `git diff --check`. |
| `2026-05-31 17:53 CEST` | Executor pass complete | Production/tests touched for GIRD-001; plan progress updated | `./scripts/run_test_gates.sh groups` passed; `git diff --check` passed. `git status --short` still shows unrelated modified `scripts/check_reliability_simulation_discovery.sh` and untracked 102 docs. | Executor scope complete; no remaining blocker. Transport gate skipped per plan because bridge behavior/startup/resume/transport wiring were not changed. | Hand off to QA Reviewer for independent review. |
| `2026-05-31 17:54 CEST` | QA Reviewer spawned/running | Executor summary, changed files, and this plan assigned to separate reviewer | Spawned separate QA reviewer with `model: gpt-5.5`, `reasoning_effort: xhigh`; reviewer instructed not to fix code and to classify blocking vs non-blocking findings. | No blocker. | Wait for QA verdict; if blocking issues exist, run a bounded fix pass. |
| `2026-05-31 17:57 CEST` | QA diff/scope review | `lib/features/groups/application/send_group_message_use_case.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; three touched direct test files; plan and breakdown orientation | Reviewed landed diff. Sender in-doubt classifier covers `BRIDGE_TIMEOUT` and reliable publish-success/no-custody/zero-peer state as `pending` + `SendGroupMessageResult.success`; self replay reconciliation remains same-id/self/group/sender/transport/text guarded and requires failed recovery evidence. | No blocking scope or behavior issue found. Repository/helper suites and `transport` remain conditional and not required because no repository/helper/bridge production/startup/resume/transport code changed. | Rerun required direct, preservation, gate, and whitespace commands. |
| `2026-05-31 17:57 CEST` | QA direct and preservation rerun complete | Required GIRD-001 direct suites and preservation suites | Passed: `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupSendReliable"`; `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"`; `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-001"`; `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GSR-001 reliable send uses single native command and treats full live fanout as sent"`; `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PGC-010 reliable partial live fanout marks sent while custody retry remains staged"`; `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "DE-008 publish timeout with durable inbox custody is visible sent success"`; `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "DE-005 self echo reconciles pending outbound row without creating incoming duplicate"`; `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "deduplicates by messageId when pubsub and group inbox deliver same message"`. | Required direct and preservation checks all green. | Run named gate and whitespace check. |
| `2026-05-31 17:57 CEST` | QA gate rerun complete | Group gate and diff hygiene | Passed: `./scripts/run_test_gates.sh groups` (`00:55 +313: All tests passed!`); passed: `git diff --check`; `git status --short` still shows only scoped production/test changes, unrelated modified `scripts/check_reliability_simulation_discovery.sh`, and untracked 102 docs. | Required named gate and whitespace check green; no untriaged required failure. | Write QA verdict. |
| `2026-05-31 17:57 CEST` | QA verdict | GIRD-001 plan closure bar and done criteria | Verdict: `accepted`. Blocking issues: none. Non-blocking follow-ups: none. Fix pass required: no. | Done criteria met for host-only GIRD-001; transport/device/simulator evidence correctly deferred by plan and breakdown to later sessions. | Return compact QA verdict to controller. |
| `2026-05-31 17:58 CEST` | final verdict written | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md` | Controller recorded final status as `accepted` after isolated Executor and separate QA Reviewer completed. | No blockers or follow-ups remain for GIRD-001. | Session complete. |

## real scope

GIRD-001 changes only the sender-side application contract for group message delivery states after native reliable-send ambiguity.

In scope:

- Treat a Dart-side `group:sendReliable` `BRIDGE_TIMEOUT` as an in-doubt send, not proven non-delivery, so the sender is not given a failed-card retry affordance while native work may still complete.
- Treat reliable-send `publishSucceeded: true` with zero or weak `topicPeerCount` and `inboxStored: false` as in-doubt live-delivery evidence, not as a receiver-visible non-delivery proof.
- Persist enough sender-side recovery evidence on the existing outgoing row to settle the same logical send later.
- Reconcile same-id own-message replay for a row that was previously marked `failed` by the in-doubt reliable path, where the group, sender, transport identity, and text still match.
- Keep existing reliable-send happy paths, legacy publish-timeout plus inbox-success behavior, same-id recipient dedupe, and intentional separate-send behavior unchanged.

Out of scope:

- Composer restored-draft behavior, failed-card retry ownership, upload-pending retry UX, resume overlap, already-open UI refresh, recipient logical dedupe for reminted ids, relay inbox idempotency, media placeholder copy, notification identity, and simulator/device acceptance. Those belong to later GIRD sessions.

## closure bar

This session is closed when host tests prove:

- Reliable `group:sendReliable` timeout no longer stores or returns a permanent `failed` outgoing row for the original message id.
- Reliable publish success with weak/zero local peer evidence plus failed inbox custody no longer stores or returns a permanent `failed` outgoing row.
- The in-doubt row retains the original message id and enough replay/custody evidence to be settled or retried by the appropriate existing owner without creating a new logical send.
- Same-id own-message replay can repair the affected failed/in-doubt outgoing row to `sent` and clear failed-card eligibility without inserting an incoming duplicate.
- The canonical in-doubt persisted state for this session is `status: pending` under the original message id, with `SendGroupMessageResult.success` returned to avoid restored-composer retry UX. A different status/result is a structural plan change unless the executor first proves existing `pending` cannot represent this safely and updates dependent tests in the same narrow scope.
- Existing reliable full live fanout, reliable partial live fanout with custody retry staged, legacy publish timeout plus inbox custody, and same-message-id recipient replay dedupe still pass.

Source acceptance mapping for GIRD-001:

| Source requirement owned here | Planned proof |
|---|---|
| `group:sendReliable` times out in Flutter while native delivery may later succeed | New `send_group_message_use_case_test.dart` RED regression for reliable timeout returning/persisting an in-doubt non-failed row under the original id |
| Reliable publish succeeds but local peer evidence is weak/zero and inbox custody failed | New `send_group_message_use_case_test.dart` RED regression for reliable `publishSucceeded: true`, `topicPeerCount: 0`, `inboxStored: false` preserving non-failed in-doubt state |
| Same-id own-message replay after false failure resolves truthfully | New `handle_incoming_group_message_use_case_test.dart` RED regression for same-id self replay promoting the affected failed/in-doubt row to `sent` without duplicate insert |
| Preserve existing same-id dedupe and intentional separate sends | Existing same-id replay tests stay green; recipient reminted-id/content dedupe remains GIRD-003 |

## source of truth

- Primary session contract: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`, Session `GIRD-001`.
- Source bug/acceptance doc: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`.
- Named gate authority: `Test-Flight-Improv/test-gate-definitions.md`; if it and prose disagree, `scripts/run_test_gates.sh` wins per that doc.
- Regression policy: `Test-Flight-Improv/14-regression-test-strategy.md`, requiring a permanent targeted regression for escaped production bugs and change-based named gates.
- Current code and tests win over stale prose if implementation discovers a mismatch.

## session classification

`implementation-ready`

This is implementation-committed gap closure. Current repo evidence shows code/tests are needed; do not downgrade to acceptance-only or evidence-only.

## exact problem statement

The sender can be told a group image send failed when native reliable-send work is actually ambiguous or partially successful. The failed row then becomes eligible for user or app retry paths in later sessions, which can remint or replay the same user-intended image send. GIRD-001 must prevent the sender-state contract from converting ambiguous reliable delivery evidence into a permanent failed affordance, and it must let same-id delivery evidence repair the original outgoing row.

What must improve:

- Ambiguous reliable-send results become non-failed, reconcilable sender state.
- Same-id own replay can settle affected rows after a false failure.

What must stay unchanged:

- Proven send failures still fail.
- Reliable full/partial live success remains successful.
- Durable inbox custody still marks sender-visible success where existing behavior already does.
- Recipient-side duplicate policy for distinct stable message ids is not changed here.

## files and repos to inspect next

Production entry files:

- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/groups/domain/models/group_message_receipt.dart`
- `lib/core/database/helpers/group_sync_receipts_db_helpers.dart` only if delivered/read receipt settlement is actually implemented in this session

Direct test files:

- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- `test/core/database/helpers/group_sync_receipts_db_helpers_test.dart` only if receipt settlement is used

## existing tests covering this area

- `test/core/bridge/bridge_group_helpers_test.dart` covers `callGroupSendReliable` success but not its timeout result.
- `test/features/groups/application/send_group_message_use_case_test.dart` covers reliable full live fanout as `sent`, reliable partial live fanout as `sent` with custody retry staged, legacy publish timeout plus inbox custody as `sent`, and legacy publish timeout without custody as failed.
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` covers same-id self echo reconciliation for `pending` outbound rows and same-message-id duplicate replay dedupe.
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` covers status updates, failed outgoing loading, stuck sending recovery, and durable receipt loading.
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` covers duplicate insert behavior, failed outgoing queries, inbox-stored updates, and reliability persistence helpers.

Missing coverage:

- `callGroupSendReliable` timeout behavior for `group:sendReliable`.
- `sendGroupMessage` reliable branch handling of `BRIDGE_TIMEOUT`.
- `sendGroupMessage` reliable branch handling of `publishSucceeded: true`, `topicPeerCount <= 0`, `inboxStored: false`.
- Same-id own replay repair when the existing row is `failed` because it was previously classified from an in-doubt reliable-send result.

## regression/tests to add first

Add these RED tests before implementation:

1. `test/core/bridge/bridge_group_helpers_test.dart`
   - Add guard coverage `callGroupSendReliable returns BRIDGE_TIMEOUT map on timeout`.
   - Use the existing `_SlowBridge` with a very short timeout.
   - Expect `ok: false`, `errorCode: BRIDGE_TIMEOUT`, and no thrown `TimeoutException`.
   - This guard may already pass because the helper currently returns a timeout map; it is still required coverage, not the RED proof for the application bug.

2. `test/features/groups/application/send_group_message_use_case_test.dart`
   - Add `GIRD-001 reliable send timeout persists in-doubt non-failed outgoing row`.
   - Use a bridge/fake response that makes only `group:sendReliable` time out or return `{ok: false, errorCode: BRIDGE_TIMEOUT}`.
   - Exact RED expectation: `result == SendGroupMessageResult.success`, returned and persisted row `status == 'pending'`, `isIncoming == false`, original message id retained, `wireEnvelope != null`, `inboxRetryPayload != null`, `inboxStored == false`, and `getFailedOutgoingMessages()` does not include the id.

3. `test/features/groups/application/send_group_message_use_case_test.dart`
   - Add `GIRD-001 reliable publish success with zero peers and no custody is in-doubt, not failed`.
   - Reliable response: `ok: true`, `publishSucceeded: true`, `topicPeerCount: 0`, `expectedRecipientCount` greater than zero, `inboxStored: false`, `deliveryMode: live_only`.
   - Exact RED expectation: `result == SendGroupMessageResult.success`, returned and persisted row `status == 'pending'`, `isIncoming == false`, original message id retained, `wireEnvelope == null` because native publish succeeded, `inboxRetryPayload != null`, `inboxStored == false`, and `getFailedOutgoingMessages()` does not include the id.

4. `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
   - Add `GIRD-001 same-id self replay repairs in-doubt failed outgoing row`.
   - Seed an outgoing same-id row with `status: failed`, matching group/sender/transport/text, and the recovery evidence shape produced by the new in-doubt send tests.
   - Call `handleIncomingGroupMessage` with `selfPeerId`, matching `senderId`, matching `transportPeerId`, and the same `messageId`.
   - Expect one local row, `isIncoming: false`, `status: sent`, original timestamp/createdAt preserved, `wireEnvelope` cleared if settlement proves sent, and no unread increment.

Optional only if the implementation adds a repository/helper method instead of using existing `saveMessage`/`updateMessageStatus`:

- Add the matching repository/helper test in `group_message_repository_impl_test.dart` or `group_messages_db_helpers_reliability_test.dart` before wiring application code.

## step-by-step implementation plan

1. Add the RED tests above and run only the direct test files needed to confirm they fail for the expected reasons.
2. Keep `callGroupSendReliable` timeout behavior explicit. If the helper already returns the expected map, only add the coverage test and do not change helper code.
3. In `send_group_message_use_case.dart`, introduce a narrow classifier for reliable in-doubt results:
   - `ok: false` plus `errorCode: BRIDGE_TIMEOUT`
   - `ok: true`, `publishSucceeded: true`, `inboxStored: false`, and `topicPeerCount/topicPeers <= 0`
4. For those in-doubt cases, persist the existing outgoing row under the same message id with `status: 'pending'` and return `SendGroupMessageResult.success`.
   - Reliable timeout: keep `wireEnvelope` and `inboxRetryPayload` because neither live publish nor durable custody is proven.
   - Reliable publish success with zero peers and failed custody: clear `wireEnvelope` because native publish succeeded, but keep `inboxRetryPayload` so the existing failed-inbox owner can pursue durable custody without a failed-card retry.
   - If implementation evidence proves this exact representation unsafe, stop and revise this plan rather than silently inventing a new state.
5. Ensure the in-doubt row keeps the minimal recovery evidence required by later owners: original id, sender/group/text/timestamp, media attachment ownership, and the existing `wireEnvelope` and/or `inboxRetryPayload` fields as applicable.
6. Emit timing/flow evidence that distinguishes in-doubt reliable classification from proven `reliable_failed` and from normal `success`, without claiming recipient delivery or delivered/read receipts.
7. In `handle_incoming_group_message_use_case.dart`, extend same-id own-message reconciliation to repair only the affected non-incoming failed/in-doubt row when identity checks match. Do not reconcile failed rows with mismatched group, sender, transport identity, or text.
8. If delivered/read receipt settlement is chosen, first add the repository/helper tests that prove receipt evidence can only settle matching outgoing rows and cannot mark forged/mismatched receipt data as sender success.
9. Rerun direct tests, then the named gates listed below.
10. Update only this plan/breakdown ledger with final evidence during execution closure; stable matrix/source-doc updates remain GIRD-007.

Stop if the RED tests show the repo already has equivalent behavior. In that case classify the session as stale/already-covered with exact passing evidence instead of changing code.

## risks and edge cases

- Returning `SendGroupMessageResult.error` for in-doubt states would still trigger composer restore and duplicate-prone retry UX in later sessions.
- Reusing `pending` may interact with failed-inbox retry ownership; preserve existing owner semantics and do not add new retry orchestration in this session.
- Clearing `wireEnvelope` too early can remove later recovery evidence; retaining it too broadly can make unrelated retry paths think the send is eligible. Tests must pin the chosen state.
- Same-id reconciliation of arbitrary failed rows could hide real failed sends. Restrict repair to matching self, group, sender, transport, text, and original id.
- Receipt settlement, if added, must not trust forged or mismatched member receipt data.
- Do not classify zero local peers as delivered/read evidence; it is only weak live fanout evidence.

## Device/Relay Proof Profile

GIRD-001 is host-only for execution closure. It mentions relay/durable custody and group messaging, but this session changes the Flutter sender classification and same-id reconciliation seams that are directly provable with host unit/integration-style tests.

No simulator, real-network relay, multi-relay, three-party, OS notification, or `integration_test` proof is required to close GIRD-001. The three-user incident, real app instance behavior, and `$run-flutter-reliability-sims` group proof are explicitly deferred to GIRD-007 by the breakdown. If implementation work starts requiring real relay/device behavior, that is scope drift unless the breakdown is revised.

Deferred final acceptance profile for GIRD-007:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only <GIRD-007 group image retry incident scenario>
```

GIRD-007 must add or name the exact scenario path before running that command.

## exact tests and gates to run

Direct RED/green suites:

```bash
flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupSendReliable"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-001"
```

Direct preservation suites after the fix:

```bash
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GSR-001 reliable send uses single native command and treats full live fanout as sent"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PGC-010 reliable partial live fanout marks sent while custody retry remains staged"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "DE-008 publish timeout with durable inbox custody is visible sent success"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "DE-005 self echo reconciles pending outbound row without creating incoming duplicate"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "deduplicates by messageId when pubsub and group inbox deliver same message"
```

If repository/helper code changes:

```bash
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart
flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart
```

If receipt settlement is used:

```bash
flutter test test/core/database/helpers/group_sync_receipts_db_helpers_test.dart
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "PGC-002 sender-bound replay receipt remains idempotent"
```

Named gates:

```bash
./scripts/run_test_gates.sh groups
```

Also run transport only if implementation changes bridge helper behavior beyond adding a timeout coverage test, or changes startup/resume/transport wiring:

```bash
./scripts/run_test_gates.sh transport
```

Always finish with:

```bash
git diff --check
```

## known-failure interpretation

- A failure in a newly added `GIRD-001` RED test before implementation is expected only if it matches the planned gap. Any unrelated compile/runtime failure must be fixed or recorded before continuing.
- Pre-existing `./scripts/run_test_gates.sh completeness-check` red status on unclassified files from `test-gate-definitions.md` is not part of GIRD-001 unless the implementation changes gate classification.
- Device/simulator failures are not GIRD-001 closure blockers because this session is host-only; they become GIRD-007 evidence.
- Existing unrelated dirty files must not be reverted. Current intake observed modified `scripts/check_reliability_simulation_discovery.sh` and untracked 102 source/breakdown docs before this plan was created.

## done criteria

- All required RED tests are added first and fail on current behavior for the expected reason.
- After implementation, the RED tests pass and prove the row is non-failed/in-doubt rather than permanently failed.
- Same-id own replay repairs the affected sender row to `sent` without inserting a duplicate incoming row.
- Existing reliable happy-path and same-id dedupe preservation tests pass.
- Required direct suites and `./scripts/run_test_gates.sh groups` pass, with `transport` run if touched by actual code changes.
- `git diff --check` passes.
- The implementation does not touch later-session surfaces except as required by the sender classification/reconciliation contract.

## scope guard

Do not:

- Change composer restored-draft behavior or failed-card retry ownership.
- Add broad UI copy, new notification behavior, media placeholder changes, recipient content-hash dedupe, relay inbox idempotency, or simulator scenarios.
- Collapse intentional separate successful sends of the same image.
- Treat local peer count as delivered/read receipt evidence.
- Add a schema migration or new status enum unless direct tests prove existing `pending`/existing fields cannot represent the in-doubt state safely.
- Widen named gates or update stable closure matrices; final stable docs are GIRD-007.

## accepted differences / intentionally out of scope

- Same-message-id live pubsub plus inbox replay is preservation coverage, not the primary duplicate-row mechanism.
- Distinct reminted message ids for the same image are not deduped in GIRD-001; GIRD-003 owns recipient logical dedupe and attachment row stability.
- Relay group inbox idempotency is not changed here; GIRD-004 owns durable store and push fanout boundaries.
- The exact reported count of three recipient rows is not proven or reproduced here; GIRD-007 owns incident reproduction and final simulator evidence.
- iOS/Android notification behavior and real APNs coalescing are not part of GIRD-001.

## dependency impact

GIRD-002 depends on this plan to know which sender states are eligible for failed-card retry, restored composer continuation, upload-pending retry, and resume retry ownership.

GIRD-003 and GIRD-004 depend on the final logical-send settlement contract so recipient and relay idempotency do not conflict with sender state.

GIRD-006 notification dedupe should align with the final logical-message identity after GIRD-001 through GIRD-004 land.

GIRD-007 must rerun final host/reliability acceptance and update stable docs after all implementation sessions are closed.

If GIRD-001 changes from existing `pending` to a new in-doubt status or field, all dependent sessions must refresh against landed code before planning/execution.

## reviewer findings

Final reviewer verdict: sufficient as-is after the exact expected outcomes were tightened.

- Missing files/tests/gates: none structurally missing. Repository/helper and receipt tests are conditional on the implementation path.
- Stale assumptions: none found. Current code evidence supports the sender reliable-timeout and self-replay gaps.
- Overengineering: avoided. The plan defaults to existing `pending` status and existing recovery fields instead of a new schema/status.
- Decomposition: sufficient. GIRD-001 does not include retry ownership, recipient dedupe, relay idempotency, media UI, notification behavior, or final simulator acceptance.
- Checklist/source mapping: GIRD-001-owned source requirements have direct planned proofs or accepted deferral to later sessions.

## arbiter decision

Structural blockers: none remaining.

Incremental details intentionally deferred:

- Exact flow-event names for in-doubt classification can be chosen during implementation as long as tests prove they do not claim delivered/read receipt evidence.
- Additional repository/helper tests are required only if the implementation adds a new helper or receipt-settlement path.

Accepted differences intentionally left unchanged:

- `$run-flutter-reliability-sims` is not a GIRD-001 direct closure gate because the breakdown assigns final simulator/device incident proof to GIRD-007. This plan still records the deferred proof profile and treats device/relay expansion during GIRD-001 as scope drift.
- The bridge helper timeout coverage may pass before implementation; it is a required guard, while the RED application regressions are in `send_group_message_use_case_test.dart` and `handle_incoming_group_message_use_case_test.dart`.
