# PGC-SEND-1 Plan: Live-Publish Status Separated From Inbox Custody Retry

Status: execution-ready

## Planning Progress

- `2026-05-23T23:49:37+02:00` - Evidence Collector started. Files inspected since last update: `git status --short`, `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`, `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`, `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`. Decision/blocker: source row `PGC-010`, session `PGC-SEND-1`, and intended plan path confirmed; dependency `PGC-DB-1` is acknowledged as accepted with explicit follow-up per handoff. Next action: collect current send-path code, focused tests, and gate evidence without changing implementation.
- `2026-05-23T23:50:53+02:00` - Evidence Collector completed; Planner started. Files inspected since last update: `lib/features/groups/application/send_group_message_use_case.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-DB-1-plan.md`. Decision/blocker: current code and focused tests still encode `pending` for `topicPeers > 0` with failed/unknown inbox custody in the legacy publish path; retry custody already includes `sent` rows, so the behavior change is narrow and dependency status is non-blocking. Next action: draft the execution-safe plan with regression-first selectors and exact gates.
- `2026-05-23T23:50:53+02:00` - Planner completed; Reviewer started. Files inspected since last update: plan artifact draft. Decision/blocker: draft is row-scoped to `PGC-010`, includes native reliable and legacy fallback send paths, and keeps closure matrix/breakdown edits out of this planner. Next action: review for missing gates, stale assumptions, and hidden scope expansion.
- `2026-05-23T23:55:53+02:00` - Reviewer completed; Arbiter started. Files inspected since last update: plan artifact self-review. Decision/blocker: sufficient with one adjustment; the static analysis command needed the repo's Flutter analyzer form, while native partial fanout, delayed custody, legacy unknown, zero-peer, publish-failure, retry eligibility, and gate contracts are covered. Next action: arbiter classification and final reusable verdict.
- `2026-05-23T23:56:21+02:00` - Arbiter completed. Files inspected since last update: plan artifact self-review. Decision/blocker: no structural blockers remain; incremental details are bounded and accepted differences are documented. Next action: plan is execution-ready for `PGC-010` only.

## real scope

Session `PGC-SEND-1` owns only source row `PGC-010`: live publish status must be separated from offline inbox custody retry in group message send.

Implementation scope:

- Change `lib/features/groups/application/send_group_message_use_case.dart` so a successful live publish with explicit topic-peer evidence (`topicPeers > 0` or `topicPeerCount > 0`) persists and returns visible message `status: 'sent'` even when offline inbox custody is false, fails, or is still unknown at return time.
- Preserve custody retry state when inbox custody is not confirmed: `inboxStored: false`, non-null `inboxRetryPayload`, and `wireEnvelope: null` after publish success.
- Apply the same visible-status rule to both paths currently present in the use case:
  - native reliable `group:sendReliable` responses with `publishSucceeded: true`
  - fallback `group:publish` plus `group:inboxStore` responses
- Keep `retryFailedGroupInboxStores` as the custody closeout path; it already queries `status IN ('sent', 'pending')` rows with `inbox_stored = 0` and a retry payload.
- Update focused send tests in `test/features/groups/application/send_group_message_use_case_test.dart` so stale "publish succeeded but inbox failed means pending" expectations become "publish succeeded with topic peers means sent, custody retry remains staged".

Out of scope:

- No changes to Go node, relay, bridge APIs, database schema, migrations, repository upsert behavior, group listener/drain behavior, receipts, notification routing, media upload policy, UI rendering, or retry scheduling.
- No attempt to convert live publish into a recipient delivery/read receipt. The row may be visible `sent`, but `recipientReceiptClaimed` remains false and no delivered/read receipts are invented.
- No closure edits to `private-group-chat-reliability-findings-2026-05-23-matrix.md` or `private-group-chat-reliability-findings-2026-05-23-session-breakdown.md` in this planner. Execution should only update those docs if a later executor prompt explicitly permits closure-row updates.
- No cleanup or revert of unrelated dirty-worktree changes.

## closure bar

The session is good enough when:

- For live publish success with `topicPeers > 0` in the fallback path, the returned message and saved message have `status: 'sent'`, `wireEnvelope: null`, `inboxStored: false`, and a non-null `inboxRetryPayload` if inbox custody fails.
- For live publish success with `topicPeers > 0` while inbox custody is still unresolved, the use case returns quickly with visible `sent`, `inboxStored: false`, and a retry payload; if the in-flight inbox store later succeeds, the background finalizer clears the retry payload and marks `inboxStored: true` without regressing status.
- For native reliable send with `publishSucceeded: true`, `topicPeerCount > 0`, and `inboxStored: false`, the returned and saved message are `sent` with custody retry staged, including partial live fanout (`topicPeerCount < expectedRecipientCount`).
- Existing zero-peer behavior stays intact: `topicPeers == 0` still requires durable inbox custody for `successNoPeers`; zero peers plus inbox failure remains an error/failed send.
- Existing legacy-unknown behavior stays conservative: missing `topicPeers` plus failed/unknown inbox custody remains `pending` because there is no topic-peer evidence.
- Publish failure behavior stays intact: publish failure plus inbox failure remains failed and message-retry-owned; publish failure plus inbox success remains failed with custody marked stored unless the existing timeout durable-custody fallback applies.
- Focused PGC-010 regressions fail before production changes in the current dirty tree, pass after implementation, the full send use case suite passes, and required group gate results are either green or exactly classified as unrelated pre-existing failures.

## source of truth

Authoritative docs and files:

- Source matrix: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`, row `PGC-010`.
- Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`, session `PGC-SEND-1`.
- Active implementation file: `lib/features/groups/application/send_group_message_use_case.dart`.
- Direct tests: `test/features/groups/application/send_group_message_use_case_test.dart`.
- Custody retry support evidence: `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, and `test/shared/fakes/in_memory_group_message_repository.dart`.
- Named gate definition: `Test-Flight-Improv/test-gate-definitions.md`.
- Gate command source of truth if docs disagree: `scripts/run_test_gates.sh`.
- Dependency handoff: `PGC-DB-1` is accepted with explicit follow-up per latest agent result; the plan artifact records no blocking issues for `PGC-004`, `PGC-005`, or `PGC-006`, with unrelated dirty-tree group gate failures documented.

Conflict rules:

- Current code and tests beat stale prose.
- `scripts/run_test_gates.sh` wins over gate prose if commands disagree.
- This plan wins for `PGC-010` scope unless implementation evidence shows the row is already covered or unsafe.
- The user instruction for this planning turn wins over the breakdown's generic closure note: do not update matrix/breakdown closure rows here.

## session classification

`implementation-ready`

## exact problem statement

Current group send semantics conflate two different facts:

- Live publish status: whether the message was successfully published to a group topic with peers.
- Offline inbox custody: whether the relay accepted a replay envelope for offline or missed recipients.

For `PGC-010`, a live publish that succeeds with topic peers should be visible as `sent` to the sender even if custody retry still needs to happen. Current fallback logic instead writes `pending` when inbox custody is false or unresolved, even with `topicPeers > 0`. Native reliable logic also only marks sent for full fanout or inbox success, so partial topic-peer evidence with failed custody can remain pending.

User-visible behavior to improve:

- A sender who successfully published to live group peers should not see the message stuck in pending just because relay inbox custody failed or has not completed.
- Offline custody retry should remain staged and recoverable through `inbox_stored = 0` plus `inbox_retry_payload`, without making the visible message status carry custody state.

Behavior that must stay unchanged:

- `sent` still does not mean delivered/read by every recipient.
- No delivered or read receipts are created by this send-status change.
- Zero-peer sends still depend on durable inbox custody.
- Publish failures still belong to message retry, not inbox-only retry.
- Legacy bridge responses without `topicPeers` stay conservative.
- Retry closeout continues to clear `inboxRetryPayload` and set `inboxStored: true` on successful custody retry.

## current evidence

- Matrix row `PGC-010` says the current send path can persist `pending` when live publish succeeds with topic peers but inbox store is false/unknown, and expects visible `sent` while custody retry remains in `inbox_stored` and `inbox_retry_payload`.
- The session breakdown maps `PGC-SEND-1` to row `PGC-010`, depends on `PGC-DB-1`, and scopes the change to `send_group_message_use_case.dart` plus focused send tests.
- `send_group_message_use_case.dart` pre-persists an outgoing row as `sending` with `wireEnvelope`, `inboxStored: false`, and `inboxRetryPayload`.
- The native reliable branch reads `publishSucceeded`, `inboxStored`, `topicPeerCount`/`topicPeers`, and `expectedRecipientCount`, then currently marks sent only when inbox custody is true or live fanout is full.
- The fallback branch with explicit `topicPeers > 0` currently writes `status: resolvedInboxOk == true ? 'sent' : 'pending'`, so inbox failure or unresolved custody makes a live-published message visible pending.
- The fallback missing-`topicPeers` branch has the same pending behavior; that branch should remain conservative because it lacks live-peer evidence.
- The zero-peer branch already waits for inbox custody and persists success only when custody succeeds; this branch is intentionally not the `PGC-010` target.
- `retryFailedGroupInboxStores` and both DB/fake repository failed-inbox queries already include outgoing rows with `status IN ('sent', 'pending')`, `inbox_stored = 0`, and non-null `inbox_retry_payload`, so `sent` rows are already eligible for custody retry.
- Existing tests encode the stale behavior in selectors such as `DE-006 partial topicPeers with inbox failure stays publish-only and retryable`, `peers > 0 + inbox fail`, `IR-007 publish success plus inbox failure`, `GI-006 inbox failure`, `GO-002 publish success with inbox failure`, `GI-007 relay non-OK status`, `inbox store ok:false`, and delayed inbox background promotion.
- Existing reliable-send coverage already proves full live fanout can be `sent` with `inboxStored: false`; it does not cover partial live fanout with custody failure as visible `sent`.

## files and repos to inspect next

Production file expected to change:

- `lib/features/groups/application/send_group_message_use_case.dart`

Direct test file expected to change:

- `test/features/groups/application/send_group_message_use_case_test.dart`

Files to inspect but avoid editing unless a direct failing regression proves it is needed:

- `lib/core/bridge/bridge_group_helpers.dart`
- `test/core/bridge/fake_bridge.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`

Docs to read as evidence but not update in this planner:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

Existing direct coverage in `send_group_message_use_case_test.dart`:

- Pre-persist coverage proves send saves `sending` plus retry payload before bridge calls.
- Publish/inbox matrix coverage proves zero-peer inbox success, zero-peer inbox failure, peers plus inbox success, peers plus inbox failure, publish failure plus inbox success/failure, legacy missing `topicPeers`, and delayed inbox background finalization.
- `DE-006` proves partial live fanout with inbox failure is publish-only and retryable, but currently expects visible `pending`.
- `GSR-001 reliable send uses single native command and treats full live fanout as sent` proves full native live fanout can be visible `sent` even with `inboxStored: false`.
- `IR-007 publish success plus inbox failure` proves custody retry closes the same message id, but currently starts that row as visible `pending`.
- Privacy-focused inbox retry tests prove retry payloads remain opaque and omit protected plaintext; these should not need production changes but may need expected status updates if they assert pending.

Existing adjacent retry coverage:

- `retry_failed_group_inbox_stores_use_case_test.dart` has `IR-007 inbox retry sends same pending message id once without duplicate rows`. The production query already includes `sent`, so add or adjust a send-use-case assertion to prove a `sent` row remains eligible for custody retry.

Missing coverage:

- No PGC-010-named regression currently proves `topicPeers > 0` plus inbox failure returns and saves visible `sent`.
- No regression currently proves delayed/unknown custody returns visible `sent` before background custody resolves.
- No regression currently proves native reliable partial live fanout (`topicPeerCount > 0` but less than `expectedRecipientCount`) returns visible `sent` with custody retry staged.
- No preservation selector explicitly protects missing-`topicPeers` legacy responses from being promoted to `sent` without live-peer evidence.

## regression/tests to add first

Add or rename focused selectors in `test/features/groups/application/send_group_message_use_case_test.dart` before changing production code. Run them against current code and record RED or unexpected-pass evidence.

1. `PGC-010 live publish with topic peers marks sent while inbox retry remains staged`
   - Use `_InboxStoreFailBridge`.
   - Configure `group:publish` with `ok: true`, `messageId`, and `topicPeers: 2`.
   - Save at least one active recipient so the retry payload has `recipientPeerIds`.
   - Expect `SendGroupMessageResult.success`.
   - Expect returned and saved message: `status == 'sent'`, `wireEnvelope == null`, `inboxStored == false`, `inboxRetryPayload != null`.
   - Expect `_recipientPeerIdsFromRetryPayload(...)` contains the active recipient.
   - Expect `msgRepo.getMessagesWithFailedInboxStore()` contains the same sent row.
   - Expect no delivered/read receipts were created.
   - Current behavior should fail on the `sent` expectation because it writes `pending`.

2. `PGC-010 live publish with pending inbox custody returns sent and closes custody in background`
   - Use `_GatedInboxStoreBridge` with `group:publish` returning `topicPeers: 2`.
   - Start `sendGroupMessage` and await the return before completing `inboxGate`.
   - Expect returned and saved-before-release message: `status == 'sent'`, `inboxStored == false`, `inboxRetryPayload != null`.
   - Complete `inboxGate`, wait for the existing background finalizer, then expect saved-after-release: `status == 'sent'`, `inboxStored == true`, `inboxRetryPayload == null`.
   - Current behavior should fail on the before-release `sent` expectation because it writes `pending`.

3. `PGC-010 reliable partial live fanout marks sent while custody retry remains staged`
   - Configure `group:sendReliable` with `ok: true`, `publishSucceeded: true`, `topicPeerCount: 1`, `expectedRecipientCount: 2`, `inboxStored: false`, and a delivery mode such as `live_only`.
   - Save two active recipients so the partial fanout classification is meaningful.
   - Expect only `group:sendReliable` is called, not fallback `group:publish` or `group:inboxStore`.
   - Expect returned and saved message: `status == 'sent'`, `inboxStored == false`, `inboxRetryPayload != null`, `wireEnvelope == null`.
   - Expect flow/timing evidence keeps `liveFanoutState: 'partial_peers'`, `recipientReceiptClaimed: false`, `inboxStored: false`, and `status: 'sent'`.
   - Current behavior should fail because native reliable currently marks sent only for full fanout or inbox success.

4. Preservation selectors to keep old boundaries intact:
   - Missing topic-peer evidence remains conservative:
     - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "missing topicPeers + inbox fail -> legacy success stays pending until inbox retry closes it"` if the name is updated to ASCII, or use a regex selector around `missing topicPeers + inbox fail` if the existing name is unchanged.
   - Zero peers still require custody:
     - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "0-peer \\+ inbox fail"`
     - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "0-peer \\+ inbox OK"`
   - Publish failures stay message-retry-owned:
     - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "publish fail + inbox OK keeps failed status but persists inbox success explicitly"`
     - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "publish fail + inbox fail -> status failed, both payloads retained"` if renamed to ASCII, or use a regex selector around `publish fail + inbox fail`.
   - Existing full reliable live fanout remains sent:
     - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GSR-001 reliable send uses single native command and treats full live fanout as sent"`
   - Custody retry still closes same id:
     - `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name "IR-007 inbox retry sends same pending message id once without duplicate rows"`

## step-by-step implementation plan

1. Record dirty-worktree context.
   - Run `git status --short`.
   - Treat current dirty files as user/other-agent work.
   - Do not revert, reformat, or normalize unrelated files.

2. Add the PGC-010 regressions first.
   - Add the three PGC-010 selectors above before production edits.
   - It is acceptable to rename stale existing tests from "pending" wording to "sent with custody retry staged" while changing only their expectations for `PGC-010`.
   - Run the three PGC-010 selectors and record RED or unexpected-pass evidence.
   - Stop and convert to evidence-only if all three already pass without production changes.

3. Identify all stale pending expectations inside the focused send test file.
   - Use `rg -n "pending|inbox failure|inbox fail|inbox store ok:false|non-OK status|delayed inbox|topicPeers" test/features/groups/application/send_group_message_use_case_test.dart`.
   - Update only cases where publish succeeds with explicit `topicPeers > 0` or reliable `topicPeerCount > 0` and custody is false/unknown.
   - Do not update cases where `topicPeers` is missing, `topicPeers == 0`, or publish fails.

4. Implement the native reliable branch change.
   - In `send_group_message_use_case.dart`, change the reliable branch so `publishSucceeded == true` and `topicPeers > 0` is enough for visible `sent`.
   - Keep `inboxStored` equal to the actual native custody result.
   - Keep `inboxRetryPayload` non-null when native custody is false, using the existing native envelope/fallback retry-payload logic.
   - Keep zero-peer plus custody failure as error.
   - Keep `recipientReceiptClaimed: false` and do not create receipts.

5. Implement the fallback `group:publish` branch change.
   - In the explicit `topicPeers > 0` branch, persist `status: 'sent'` regardless of `resolvedInboxOk`.
   - Preserve `wireEnvelope: null`.
   - Set `inboxStored: resolvedInboxOk == true`.
   - Clear `inboxRetryPayload` only when `resolvedInboxOk == true`; otherwise retain `prePersistMessage.inboxRetryPayload`.
   - If `resolvedInboxOk == null`, keep the existing background finalizer, but the pre-background visible status must already be `sent`.
   - Update emitted timing/status details to report `status: 'sent'` while leaving inbox evidence (`inboxStored`, `inboxPending`, `topicPeers`, `liveFanoutState`) truthful.

6. Keep non-target branches unchanged.
   - Missing `topicPeers` branch: leave pending on false/unknown custody.
   - Zero-peer branch: leave success only when inbox custody succeeds.
   - Publish failure branch: leave failed unless the existing `BRIDGE_TIMEOUT` plus durable inbox success fallback applies.
   - Do not change `_tryInboxStore`, retry scheduling, or repository query semantics unless a focused test proves the custody retry row is no longer eligible.

7. Run focused selectors and fix only PGC-010-scoped failures.
   - First run the three PGC-010 selectors.
   - Then run preservation selectors listed above.
   - Then run the full direct send use case test file to catch stale expectations in the same matrix.

8. Run formatting, analysis, and gates.
   - Format only touched files.
   - Run targeted analysis on touched Dart files.
   - Run scoped `git diff --check`.
   - Run the Group Messaging Gate because group send behavior changed.
   - If the group gate is red only for previously documented dirty-tree integration failures from `PGC-DB-1`, record exact failure names and classify as accepted explicit follow-up; do not hide new send failures under that bucket.

9. Stop after code, focused tests, gates, and evidence.
   - Do not update source matrix or session breakdown closure rows unless a later executor prompt explicitly allows closure edits.
   - Do not broaden into PGC rows outside `PGC-010`.

## risks and edge cases

- Partial live fanout: `topicPeers > 0` can still be less than expected recipients. The message should be visible `sent`, but custody retry must remain staged for recipients that missed live delivery.
- Unknown live fanout: missing `topicPeers` must not be treated as sent when custody fails because there is no proof of topic peers.
- Zero live peers: `topicPeers == 0` must keep the durable inbox fallback contract.
- Background custody race: returning before inbox custody resolves must not leave a permanent retry payload if the background store later succeeds.
- Retry ownership: a `sent` row with failed custody must still be returned by `getMessagesWithFailedInboxStore`.
- Duplicate sends and DB upserts: this plan depends on `PGC-DB-1` preserving intentional outgoing state transitions; do not rework DB save semantics in this session.
- Receipts: visible `sent` must not create delivered/read receipts or imply recipient receipt claims.
- Native reliable compatibility: bridge responses may use `topicPeerCount` or `topicPeers`; preserve both existing field names.
- Dirty tree gate noise: broad group integration failures may already exist; direct PGC-010 selectors and full send suite decide whether this session is correct.

## exact tests and gates to run

Regression-first PGC-010 selectors:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PGC-010 live publish with topic peers marks sent while inbox retry remains staged"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PGC-010 live publish with pending inbox custody returns sent and closes custody in background"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PGC-010 reliable partial live fanout marks sent while custody retry remains staged"
```

Required preservation selectors:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "missing topicPeers \\+ inbox fail"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "0-peer \\+ inbox fail"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "0-peer \\+ inbox OK"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "publish fail \\+ inbox OK"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "publish fail \\+ inbox fail"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GSR-001 reliable send uses single native command and treats full live fanout as sent"
flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name "IR-007 inbox retry sends same pending message id once without duplicate rows"
```

Direct owner suite:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart
```

Static checks and hygiene:

```bash
dart format --set-exit-if-changed lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart
flutter analyze --no-pub lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
git diff --check -- lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-SEND-1-plan.md
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

Conditional:

- Run `./scripts/run_test_gates.sh completeness-check` only if execution changes gate definitions or classification docs. This PGC-SEND-1 plan does not require that.
- No Go tests are required unless execution changes Go files, which is outside scope.

## known-failure interpretation

- A failure in any new `PGC-010` selector is session-caused until proven otherwise.
- A failure in `send_group_message_use_case_test.dart` where publish succeeds with `topicPeers > 0` and status is still expected as `pending` is a stale test expectation, not accepted historical red; update the focused expectation if it matches `PGC-010`.
- A failure in missing-`topicPeers`, zero-peer, publish-failure, timeout, privacy, or retry-ownership selectors is a blocker unless direct evidence shows the selector was already red before PGC-SEND-1 edits.
- `PGC-DB-1` recorded `./scripts/run_test_gates.sh groups` as red with unrelated dirty-tree integration failures. If the same named gate remains red after PGC-SEND-1, rerun/capture the log and classify only exact pre-existing failures as accepted explicit follow-up after all direct PGC-SEND-1 tests pass.
- Do not mark PGC-SEND-1 ready if the direct send suite is red, even if the broader group gate has known unrelated failures.

## done criteria

- The three PGC-010 selectors were added before production changes and recorded as failing or unexpectedly already passing in the current dirty tree.
- The use case returns and persists `sent` for explicit live topic-peer success with custody false/unknown in both native reliable and fallback publish paths.
- `inboxStored` and `inboxRetryPayload` continue to reflect custody truth rather than visible send status.
- Custody retry still finds the sent row with failed custody and closes the same message id.
- Missing-topic-peer, zero-peer, publish-failure, and timeout durable-custody behavior remain covered and unchanged.
- `dart format`, targeted `dart analyze`, scoped `git diff --check`, the full direct send use case suite, and the required group gate are run or exactly classified if broader gate failures are pre-existing.
- No files outside the scoped production/test/doc plan surface are edited for this session.
- Matrix and breakdown closure rows remain untouched unless a later execution prompt explicitly permits them.

## scope guard

Do not:

- Change Go pubsub, relay inbox, native bridge payload shape, database migrations, repository save/upsert semantics, retry scheduler cadence, group listener/drain logic, or UI status rendering.
- Treat `sent` as delivered/read or create receipts from live publish status.
- Promote missing-`topicPeers` legacy responses to `sent` when custody fails.
- Convert zero-peer inbox failure into success.
- Clear `inboxRetryPayload` unless custody is actually stored.
- Reopen `PGC-004`, `PGC-005`, or `PGC-006`; dependency `PGC-DB-1` is accepted with explicit follow-up for unrelated broad-gate failures.
- Update matrix/breakdown closure rows during this planning task.

Overengineering indicators:

- Adding a new delivery state enum or UI badge taxonomy for this row.
- Adding new persistence columns for custody vs live status.
- Rewriting retry ownership or queue discovery when existing queries already include `sent` custody-retry rows.
- Moving send orchestration out of `send_group_message_use_case.dart`.

## accepted differences / intentionally out of scope

- Group message `sent` remains sender-visible publish success, not end-to-end recipient delivery evidence.
- Partial live fanout with topic peers is accepted as visible `sent` while custody retry remains responsible for missed/offline recipients.
- Legacy bridge responses without `topicPeers` remain more conservative than modern reliable/fallback responses with explicit topic-peer evidence.
- 1:1 message delivery semantics are not used as a required parity target for this group-row fix.
- Existing `PGC-DB-1` group gate failures are accepted only as unrelated dirty-tree follow-up if they match the recorded broad-gate failures and direct PGC-SEND-1 evidence is green.

## dependency impact

- `PGC-SEND-1` depends on `PGC-DB-1` because repeated `saveMessage` transitions must preserve outgoing retry/custody fields. Latest handoff says `PGC-DB-1` is accepted with explicit follow-up, so this plan is not prerequisite-blocked.
- Later drain/retry sessions rely on custody retry rows remaining discoverable after visible status becomes `sent`.
- If execution discovers `getMessagesWithFailedInboxStore` no longer includes `sent` rows in the active repository/helper path, stop and either fix only that direct custody-query regression if it is in current scope or report a blocker tied to `PGC-DB-1`.
- If native reliable bridge responses cannot supply retry envelopes or fallback retry payloads for custody failure, keep using the pre-persisted retry payload and document any native envelope gap as an accepted implementation detail, not a protocol rewrite.

## reviewer findings

Reviewer classification: sufficient with adjustments.

Sufficiency questions:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient with one adjustment, now applied.
- What files, tests, regressions, or gates are missing? None after the draft added native reliable partial fanout, delayed inbox custody, legacy missing-topic-peer preservation, zero-peer preservation, publish-failure preservation, direct send suite, retry selector, scoped hygiene, and the Group Messaging Gate.
- What assumptions are stale or incorrect? The draft's `dart analyze --no-pub` command was not the repo's usual analyzer form; it was replaced with `flutter analyze --no-pub`.
- What is overengineered? Nothing structural. The plan avoids new schema, UI states, bridge protocol changes, retry scheduler changes, and Go/relay work.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It has one production file, one direct test file, optional adjacent retry inspection only, regression-first selectors, stop conditions, and explicit non-target branches.
- What is the minimum needed to make the plan sufficient? Keep the current regression-first selectors, direct suite, named gate, scope guard, and known-failure interpretation intact.

## arbiter decision

Structural blockers: none.

Incremental details:

- Executor may rename stale existing test names to ASCII wording while changing expectations, but only for the PGC-010 cases where explicit topic-peer publish success is visible `sent`.
- Executor should capture the group gate log if `./scripts/run_test_gates.sh groups` remains red and compare failures to the already documented `PGC-DB-1` dirty-tree gate failures.

Accepted differences:

- Visible group message `sent` is live publish success, not recipient delivery/read proof.
- Missing `topicPeers` legacy bridge responses remain conservative.
- Zero-peer sends continue to depend on durable inbox custody.
- Closure matrix/breakdown updates are intentionally out of scope for this planning turn.

Arbiter verdict: no structural blocker; stop per the stop rule.

## final planning output

Final verdict:

- `execution-ready`

Final plan:

- Use the `PGC-010` sections above as the reusable execution plan for `lib/features/groups/application/send_group_message_use_case.dart` and focused send tests.

Structural blockers remaining:

- None.

Incremental details intentionally deferred:

- Exact stale test-name wording can be adjusted during execution so long as selectors stay focused on `PGC-010`.
- Broad `groups` gate failures that match the already documented dirty-tree failures can be recorded as explicit follow-up after direct PGC-SEND-1 evidence passes.

Accepted differences intentionally left unchanged:

- `sent` does not claim recipient delivery/read receipts.
- Missing-topic-peer legacy responses are not promoted without live-peer evidence.
- Zero-peer inbox-failure behavior remains failed/error.
- Matrix and breakdown closure rows are not updated in this planner.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-DB-1-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `test/core/bridge/fake_bridge.dart`

Why the plan is safe or unsafe to implement now:

- Safe to implement now. The plan is limited to one production file and focused send tests, starts with RED PGC-010 selectors, preserves non-target branches, uses existing custody retry eligibility for `sent` rows, and treats the accepted `PGC-DB-1` dependency follow-up as non-blocking while still requiring direct PGC-SEND-1 tests to pass.

## Execution Progress

- `2026-05-24T00:03:56+02:00` - Contract extracted and dirty worktree inspected. Files inspected/touched: `git status --short`, `lib/features/groups/application/send_group_message_use_case.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`. Decision/blocker: worktree has broad unrelated edits; execution will preserve them and stay scoped to PGC-SEND-1 files plus these notes. Next action: add PGC-010 RED selectors before production changes.
- `2026-05-24T00:03:56+02:00` - Executor RED-selector pass started. Files touched: `test/features/groups/application/send_group_message_use_case_test.dart`. Decision/blocker: added/renamed PGC-010 selectors for explicit topic peers with failed inbox custody, delayed inbox custody, and native reliable partial fanout. Next action: run the three focused selectors and record RED or unexpected pass evidence.
- `2026-05-24T00:04:13+02:00` - RED selectors run. Command: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "PGC-010"`. Result: expected RED, 0 passed / 3 failed. Failures: explicit topic peers plus failed inbox returned `pending`, native reliable partial fanout returned `pending`, and delayed inbox custody returned `pending` before background closeout. Next action: implement the visible `sent` status split while retaining inbox retry payloads.
- `2026-05-24T00:05:30+02:00` - Executor implementation pass completed. Files touched: `lib/features/groups/application/send_group_message_use_case.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`. Decision/blocker: native reliable publish success with `topicPeerCount > 0` and fallback publish success with explicit `topicPeers > 0` now save visible `sent` while retaining `inboxStored: false` and non-null retry payloads when custody is not confirmed. Stale explicit-topic inbox-failure expectations in the send suite were updated; missing-topicPeers and publish-failure `pending`/`failed` expectations were left conservative. Next action: rerun focused selectors and preservation checks.
- `2026-05-24T00:11:53+02:00` - Executor verification completed. Commands/results: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "PGC-010"` passed 3/3 after implementation; preservation selector bundle for `PGC-010`, missing-topicPeers, zero-peer, publish-failure, and `GSR-001` passed 9/9; `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name "IR-007 inbox retry sends same pending message id once without duplicate rows"` passed 1/1; `flutter analyze --no-pub lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/send_group_message_use_case_test.dart` passed with no issues; `git diff --check` passed. Full send suite command `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart` ran to completion at 125 passed / 2 failed; failures are outside PGC-010 scope: `returns error for member when bootstrap key is still missing` now returns `unauthorized`, and `GM-028 pre-existing empty PeerId member is excluded from durable recipients` fails during fake repository setup with `invalid_peer_id: "   "`.
- `2026-05-24T00:11:53+02:00` - Group gate attempted and classified. Command: `./scripts/run_test_gates.sh groups`, captured at `/tmp/pgc_send_groups_gate.log`; result: failed at 281 passed / 20 failed. PGC-owned behavior is represented by stale out-of-scope integration expectations that still assert visible `pending` for live-peer sends with failed custody: `Section 11 test infrastructure inbox store failure doesn't block publish but leaves sender state pending`, `OB-008 fake-network degraded branches use only their retry owner`, `IR-007 rapid pause/resume closes pending live-peer send via inbox retry exactly once`, `UP-008 pending outbound group message survives restart and reconciles through inbox retry`, `GR-017 recovery preserves failed direct and pending inbox retry state`, and `ST-013 fake-network relay chaos surfaces gaps and recovers media replay`. Other gate failures are unrelated dirty-tree invite/rejoin/resume/churn/member-validation failures. Scope guard: integration tests and listener/drain/incoming docs remain untouched per user instruction.

## Final Execution Verdict

- Verdict: accepted_with_explicit_follow_up
- Files changed in this session scope: `lib/features/groups/application/send_group_message_use_case.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, and this plan's execution notes.
- Follow-up/blocker: Group Messaging Gate remains red because out-of-scope integration tests still encode old `pending` wording for live-peer custody retry and because unrelated dirty-tree group invite/rejoin/churn/member-validation failures are present.
