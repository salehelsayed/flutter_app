Status: execution-ready

# INTRO-REL-015 Plan - Retry Uses Direct/Relay When Inbox Store Fails

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-22 21:59 CEST | Planner completed | Same files as planner start plus current owner-file diff baseline | Draft plan selects an inbox-first fallback design: keep successful inbox retry behavior, but when `storeInInbox` fails, reuse existing direct/relay delivery logic so an acknowledged reachable target deletes the retry row. | Run strict reviewer pass. |
| 2026-05-22 22:02 CEST | Reviewer started | Full draft plan, source row, breakdown row, gate script membership, direct test inventory | Review focus: missing files/gates, stale assumptions, overbroad scope, and whether the direct/relay fallback is precise enough for implementation. | Classify sufficiency and required adjustments. |
| 2026-05-22 22:04 CEST | Reviewer completed | Same review set | Verdict: sufficient with small adjustments. No structural blocker. Added precision that retry should avoid depending on a second inbox store after inbox failure and should preserve `storeInInboxCallCount == 1` in the direct regression. | Run arbiter classification and finalize if no structural blocker appears. |
| 2026-05-22 22:05 CEST | Arbiter started | Reviewer pass, adjusted draft, source row, breakdown row, gate contract | Classifying review findings into structural blockers, incremental details, and accepted differences. | Apply stop rule. |
| 2026-05-22 22:06 CEST | Arbiter completed | Same arbiter set | No structural blockers. Incremental helper-shape details are intentionally deferred to implementation. Accepted host-helper proof profile is documented with conditional transport/simulator upgrade. | Plan is execution-ready for `INTRO-REL-015` only. |

## Execution Progress

| Timestamp | Role | Files inspected or touched since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-22 21:59 CEST | Executor started | Plan file and owner files: `lib/features/introduction/application/introduction_outbound_delivery.dart`, `test/features/introduction/application/introduction_outbound_delivery_test.dart`, `test/core/services/fake_p2p_service.dart`, `test/shared/fakes/in_memory_introduction_repository.dart` | Contract extracted for `INTRO-REL-015` only: add RED direct retry regression, preserve inbox success, fall back to existing direct/relay helper after inbox store failure, run direct file plus `./scripts/run_test_gates.sh intro`; do not update matrix/breakdown/inventory closure docs. | Capture required dirty baseline and add RED regression. |
| 2026-05-22 21:59 CEST | Executor baseline | Required pre-edit status command: `git status --short -- lib/features/introduction/application/introduction_outbound_delivery.dart test/features/introduction/application/introduction_outbound_delivery_test.dart lib/core/lifecycle/handle_app_resumed.dart lib/core/services/pending_message_retrier.dart test/core/services/fake_p2p_service.dart test/shared/fakes/in_memory_introduction_repository.dart` | Output before edits: `M lib/features/introduction/application/introduction_outbound_delivery.dart`; `M test/shared/fakes/in_memory_introduction_repository.dart`. No row-owned test-file modification yet. | Add RED regression in the direct test file. |
| 2026-05-22 21:59 CEST | Executor RED | Touched `test/features/introduction/application/introduction_outbound_delivery_test.dart` only | Added direct retry regression and ran `flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart --plain-name 'retryPendingIntroductionDeliveries delivers a failed row through direct send when inbox storage fails'`; expected failure observed: `Expected: <1> Actual: <0>` for delivered count, confirming retry stops after failed inbox storage. | Implement scoped retry fallback in `introduction_outbound_delivery.dart`. |
| 2026-05-22 22:02 CEST | Executor implementation | Touched `lib/features/introduction/application/introduction_outbound_delivery.dart` and `test/features/introduction/application/introduction_outbound_delivery_test.dart` | Implemented inbox-first retry fallback by calling the existing direct/relay delivery helper after `storeInInbox` fails, with helper inbox fallback disabled so retry makes no second inbox store attempt. Added relay-probe retry regression and renamed stale inbox-only test wording. Direct plain-name rerun passed. | Run required direct suite, diff hygiene, and intro gate. |
| 2026-05-22 22:02 CEST | Executor verification | Same touched files | `flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart` passed with 11 tests. `git diff --check -- lib/features/introduction/application/introduction_outbound_delivery.dart test/features/introduction/application/introduction_outbound_delivery_test.dart` passed. `./scripts/run_test_gates.sh intro` passed with 204 tests. `dart format --output=none --set-exit-if-changed ...` reported 0 changed files. | Record conditional gate decision and hand off to QA. |
| 2026-05-22 22:02 CEST | Executor verdict candidate | Same touched files plus plan progress | Initial conditional-gate decision was host-helper-only; later final gate-model check superseded this by running the conditional transport and pass-fallback simulator gates. Verdict candidate: accepted pending independent QA review. | QA should review scope adherence, retry persistence states, and test evidence. |
| 2026-05-22 23:05 CEST | Post-closure conditional gate addendum | `scripts/run_test_gates.sh`, `smoke_test_friends.sh`, source matrix and breakdown closure docs | Final gate-model check added the conditional evidence anyway: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed, and `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh` passed with `Intro E2E harness passed`. | Source matrix, breakdown, inventory, and final program verdict were updated with the stronger evidence. |
| 2026-05-22 22:05 CEST | QA Reviewer started | Plan contract, scoped diff, `introduction_outbound_delivery.dart`, `introduction_outbound_delivery_test.dart`, `fake_p2p_service.dart`, `in_memory_introduction_repository.dart`, `scripts/run_test_gates.sh`, source matrix and breakdown gate rows | Review scope: no production/test edits; verify retry fallback behavior, direct/relay regressions, direct test, intro gate, and conditional transport/simulator decision. | Run independent direct/gate verification and classify findings. |
| 2026-05-22 22:05 CEST | QA Reviewer completed | Same inspected files; commands rerun: `flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart`, `git diff --check -- lib/features/introduction/application/introduction_outbound_delivery.dart test/features/introduction/application/introduction_outbound_delivery_test.dart`, `./scripts/run_test_gates.sh intro` | Verdict: accepted with explicit follow-up. No blocking code/test/gate issues. Direct file passed with 11 tests, diff check passed, intro gate passed with 204 tests. Later final gate-model check also ran the conditional transport and pass-fallback simulator gates. | Closure follow-up may update source matrix, breakdown, and test inventory with this concrete evidence. |

## real scope

Implement the single `INTRO-REL-015` reliability gap: `retryPendingIntroductionDeliveries` must not leave a retryable introduction outbox row failed solely because `storeInInbox` returns false or throws when the target is reachable through local/direct/relay delivery.

In scope:

- Add row-owned TDD coverage in `test/features/introduction/application/introduction_outbound_delivery_test.dart`.
- Update `lib/features/introduction/application/introduction_outbound_delivery.dart` so retry preserves the existing successful inbox retry path and falls back to viable direct/relay delivery after inbox storage failure.
- Touch `lib/core/lifecycle/handle_app_resumed.dart` or `lib/core/services/pending_message_retrier.dart` only if the current call wiring prevents the fixed retry function from running. Current evidence suggests call wiring already invokes the retry function and should not need product changes.
- Rename stale direct-test wording if needed, such as changing "inbox-only retry" to a scenario-specific name, without changing behavior outside this row.

Out of scope:

- Source matrix row updates, breakdown closure updates, and `test-inventory.md` closure edits during planning. Those happen only after implementation and gates.
- Product decision work for inbox-only retry. No such product decision exists in this session.
- Changes to Go relay behavior, `P2PService` contracts, database schema, introduction trust/terminal-state handling, send/accept/pass fan-out staging, group retry, or 1:1 message retry.

## closure bar

`INTRO-REL-015` is good enough when a retryable introduction outbox row with a failed inbox store and reachable target is delivered through an existing direct or relay path, persisted as delivered long enough to clear stale error/path state, and deleted from the outbox after acknowledged delivery.

The fix must preserve these existing behaviors:

- A retryable row still deletes immediately when it is already `delivered` through `inbox`.
- A retryable row still uses inbox storage and deletes when inbox storage succeeds.
- A reachable acknowledged direct/relay retry increments the delivered count and clears the row.
- An unacknowledged direct/relay send remains retryable as `sent` rather than being counted as delivered.
- A fully failed inbox plus direct/relay attempt remains retryable as `failed` with a useful last error.
- Existing resume and pending-message retrier callers keep invoking the same retry function.

## source of truth

- Primary source row: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md`, row `INTRO-REL-015`, which remains `Open` until execution and gates are complete.
- Current handoff: `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md`, which marks only `INTRO-REL-015` as `needs_code_and_tests`.
- Code source of truth: current `lib/features/introduction/application/introduction_outbound_delivery.dart` and its current dirty-worktree state.
- Direct test source: `test/features/introduction/application/introduction_outbound_delivery_test.dart`.
- Inventory source: `Test-Flight-Improv/Intro-Feature/test-inventory.md`, which currently documents inbox-only retry coverage and the missing retry direct/relay proof.
- Gate source: `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md` is descriptive. If they disagree, the script wins.
- On disagreement, current code and tests beat stale prose, but source row status cannot move from `Open` to `Covered` until execution/gates provide concrete evidence.

## session classification

`implementation-ready`

This is repo-owned code+tests. It is not acceptance-only and is not covered by existing tests. A product-owned inbox-only retry decision would change the classification, but no such decision exists.

## exact problem statement

Initial introduction delivery already has a richer delivery cascade: it can try local/direct, relay probe, and inbox fallback. Retry does not. `retryPendingIntroductionDeliveries` currently loads retryable outbox rows, tries `p2pService.storeInInbox`, and writes `inbox_retry_failed` if inbox storage fails. If the target is reachable by direct or relay send at that moment, the row can still remain failed only because inbox storage failed.

User-visible behavior that must improve: after app resume or pending retrier work, a previously failed/sent introduction delivery should heal when the target is reachable, even if relay inbox storage is unavailable.

Behavior that must stay unchanged: inbox success remains a valid retry path, already-delivered inbox rows are cleaned, stale retry rows stay retryable when all paths fail, and intro send/accept/pass trust/state semantics do not change.

## files and repos to inspect next

Production files:

- `lib/features/introduction/application/introduction_outbound_delivery.dart` - primary owner file for retry and delivery cascade.
- `lib/core/lifecycle/handle_app_resumed.dart` - inspect only if resume-triggered retry wiring or tests break.
- `lib/core/services/pending_message_retrier.dart` - inspect only if background retrier wiring or tests break.

Test/fake files:

- `test/features/introduction/application/introduction_outbound_delivery_test.dart` - row-owned direct tests.
- `test/core/services/fake_p2p_service.dart` - likely already sufficient for direct retry proof.
- `test/shared/fakes/in_memory_introduction_repository.dart` - likely already sufficient for retryable row state assertions.

Docs to update only after execution/gates:

- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15.md`
- `Test-Flight-Improv/Intro-Feature/Introduction_reliability_test_matrix_TOP_15-session-breakdown.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`

## existing tests covering this area

`test/features/introduction/application/introduction_outbound_delivery_test.dart` currently covers:

- Acked live send clears the staged outbox delivery.
- Unacked live send keeps a retryable `sent` row.
- Initial relay-probe fallback after direct failure.
- Initial inbox fallback success.
- Initial all-path failure leaving a failed row.
- Retry through inbox for one sent row.
- Retry of multiple stalled/failed rows plus cleanup of already-delivered inbox rows.
- Resume-triggered retry through inbox.

Missing:

- Retry direct send after `storeInInbox` fails.
- Retry relay-probe send after `storeInInbox` fails and direct dial is unavailable.
- Assertion that a successful retry through direct/relay deletes the row rather than leaving `inbox_retry_failed`.

The named `intro` gate in `scripts/run_test_gates.sh` does not include `introduction_outbound_delivery_test.dart`, so this direct file must be run explicitly in addition to `./scripts/run_test_gates.sh intro`.

## regression/tests to add first

Add the failing direct-path regression first:

```bash
flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart --plain-name 'retryPendingIntroductionDeliveries delivers a failed row through direct send when inbox storage fails'
```

Test shape:

- Seed a retryable `failed` or old `sent` introduction outbox row for `peer-B`.
- Configure `p2pService.storeInInboxResult = false`.
- Configure `discoverPeerResult`, `dialPeerResult = true`, and `sendMessageWithReplyResult = SendMessageResult(sent: true, acked: true, transport: IntroductionOutboxDeliveryPath.direct)`.
- Run `retryPendingIntroductionDeliveries`.
- Expect delivered count `1`, outbox empty, `storeInInboxCallCount == 1`, and `sendMessageWithReplyCallCount == 1`.

Add a second narrow relay-probe regression in the same file, either before implementation if time allows or immediately after the direct fix if the direct fix reuses the helper:

- Seed a retryable row.
- Configure inbox storage to fail, direct dial to fail, relay probe to return `RelayProbeResult.connected`, and send-with-reply to return acknowledged `relay`.
- Expect delivered count `1`, outbox empty, `probeRelayCallCount == 1`, and the send path used relay.

These tests prove the row seam without requiring a real device or relay server because the implementation should reuse the already-covered delivery cascade helper.

## step-by-step implementation plan

1. Capture dirty baseline before editing: `git status --short -- lib/features/introduction/application/introduction_outbound_delivery.dart test/features/introduction/application/introduction_outbound_delivery_test.dart lib/core/lifecycle/handle_app_resumed.dart lib/core/services/pending_message_retrier.dart test/core/services/fake_p2p_service.dart test/shared/fakes/in_memory_introduction_repository.dart`. Do not revert unrelated work.
2. Add the direct-path failing regression in `introduction_outbound_delivery_test.dart` and run its `--plain-name` command. Record that it fails on current code because retry only attempts inbox storage and leaves the row failed.
3. Implement the smallest production change in `introduction_outbound_delivery.dart`:
   - Keep existing normalization and delivered-inbox cleanup.
   - Keep the existing inbox-success retry path first so current inbox retry and resume tests remain valid.
   - When `storeInInbox` returns false or throws, call the existing local/direct/relay delivery cascade rather than writing `inbox_retry_failed` immediately.
   - If reusing `_deliverEnvelope` after an inbox failure, guard or parameterize its inbox fallback so this retry fallback does not depend on a second inbox store attempt. The direct regression should continue to prove exactly one failed inbox attempt followed by direct delivery.
   - Reuse existing helper logic where practical. A small private helper or return value refactor is acceptable if it prevents copy/paste of the delivery result persistence switch.
   - Avoid changing public `P2PService` APIs, Go transport, relay storage, or database schema.
4. Persist retry results consistently with initial delivery:
   - Acknowledged `delivered` via local/direct/relay saves clear state and deletes the row; increment delivered count.
   - Unacknowledged `sent` via local/direct/relay saves `sent`, clears `lastError`, keeps the row, and does not increment delivered count.
   - Failed direct/relay after failed inbox saves `failed` with a retryable path/error; do not delete.
5. Add the relay-probe retry regression if not already added, using `_RelayProbeFakeP2PService` or an equally small fake extension in the same test file.
6. Rerun the direct touched file. If existing test names or assertions still say "inbox-only" globally, update wording to describe the specific inbox-success scenario without weakening assertions.
7. Inspect resume/retrier wiring only if tests show the fixed retry is not invoked. Do not edit `handle_app_resumed.dart` or `pending_message_retrier.dart` for naming or style.
8. Run the required gates. Only after green evidence should the executor update the source matrix row and breakdown from `Open` to `Covered`.
9. Stop if evidence shows the row is already fixed before code changes. In that case, convert this to evidence-gated closure with direct proof, but current code does not support that outcome.

## risks and edge cases

- Duplicate sends: retrying direct/relay after an inbox failure could deliver an envelope already delivered by a previous unacknowledged attempt. The envelope `messageId` normalization must remain unchanged so receiver-side idempotency still has the same key.
- Unacknowledged direct/relay send: do not delete the row unless the send is acknowledged as delivered.
- Stale local state: failed rows and old `sent` rows must remain retryable after a complete path failure.
- Resume ordering: `handleAppResumed` already invokes the retry function after other message retries; do not move lifecycle steps unless a direct test proves the call order is broken.
- Dirty worktree: owner files already contain unrelated or prior-session changes, including current `introduction_outbound_delivery.dart` refactoring. Preserve current behavior and do not revert.
- Relay proof: host fake relay-probe proof is sufficient only if implementation reuses existing delivery helper logic and does not change real relay/transport behavior.

## exact tests and gates to run

Required TDD red command:

```bash
flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart --plain-name 'retryPendingIntroductionDeliveries delivers a failed row through direct send when inbox storage fails'
```

Required direct touched test after implementation:

```bash
flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

Recommended hygiene:

```bash
git diff --check -- lib/features/introduction/application/introduction_outbound_delivery.dart test/features/introduction/application/introduction_outbound_delivery_test.dart
```

Conditional gates only if implementation changes real direct/relay retry behavior beyond reusing existing delivery helper logic in host tests, touches `P2PService`/bridge/relay/resume ordering, or changes simulator-visible transport semantics:

```bash
./scripts/run_test_gates.sh transport
INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh
```

If implementation stays inside `introduction_outbound_delivery.dart` and only reuses the existing helper cascade, record that `transport` and targeted simulator E2E were not required because no real transport, relay server, bridge, or simulator harness behavior changed.

## known-failure interpretation

- The new direct-path regression must fail before implementation for the expected reason: current retry attempts inbox only and leaves the row failed when inbox storage fails.
- Any failure in `introduction_outbound_delivery_test.dart` after implementation is in scope unless clearly caused by a pre-existing dirty-worktree compile error unrelated to this file.
- Any `./scripts/run_test_gates.sh intro` failure in touched intro application code is a blocker for row closure.
- If `intro` fails in an unrelated dirty file or fixture, capture the failure and current `git status --short`; do not mark `INTRO-REL-015` covered unless the row-owned direct tests are green and the gate failure is proven pre-existing or unrelated by rerun/baseline evidence.
- Simulator or transport failures are not relevant unless the conditional proof profile is triggered. If triggered, they must be green or explicitly triaged before closure.

## done criteria

- Failing direct-path regression was run and recorded before production changes where feasible.
- `retryPendingIntroductionDeliveries` attempts direct/relay delivery after inbox storage failure for reachable targets.
- Existing inbox-success retry behavior and delivered-inbox cleanup still pass.
- Direct retry through acknowledged direct and relay paths deletes the outbox row and increments delivered count.
- Unacknowledged or fully failed retry paths remain retryable and do not falsely increment delivered count.
- Required direct test and `./scripts/run_test_gates.sh intro` pass.
- Conditional `transport` and targeted simulator E2E are either run because the implementation triggered them or explicitly recorded as not required under the host-helper proof profile.
- Only after execution/gates, source matrix row `INTRO-REL-015` and breakdown/test inventory are updated with concrete evidence.

## scope guard

Do not:

- Mark `INTRO-REL-015` `Covered` during planning.
- Change product semantics to inbox-only retry without an explicit product decision and matching docs.
- Modify Go relay, real inbox storage semantics, `P2PService` APIs, app bootstrap, DB schema, or unrelated introduction handler trust guards.
- Broaden into all pending message retries, group retries, 1:1 delivery retry, push notifications, or UI.
- Use destructive git commands or revert unrelated dirty-worktree changes.
- Add broad abstractions unless needed to avoid duplicating the existing delivery-result persistence logic.

If implementation evidence suggests a broader transport bug, stop after preserving the row-owned regression and open a separate follow-up rather than expanding this session.

## accepted differences / intentionally out of scope

- Host fake direct/relay proof is accepted for this plan if implementation reuses existing delivery helper logic. Real-device relay or simulator proof is intentionally out of scope unless the executor changes transport/relay behavior beyond invoking the helper from retry.
- The plan does not require a product decision for inbox-only retry because the task explicitly states no product choice exists.
- The plan does not update closure docs or source row status. Closure documentation is intentionally deferred until after execution and gates.
- The plan does not require `go-relay-server` tests because no relay server behavior should change.

## dependency impact

`INTRO-REL-015` is the only remaining open row in the TOP 15 breakdown. Its execution gates the final closure of `Introduction_reliability_test_matrix_TOP_15.md`.

Later closure work depends on:

- direct test evidence from `introduction_outbound_delivery_test.dart`
- `./scripts/run_test_gates.sh intro` evidence
- conditional proof profile decision for `transport` and targeted simulator E2E
- source row, breakdown, and inventory docs being updated only after execution

If the implementation changes from host-helper reuse to real transport behavior, downstream closure must include the conditional transport/E2E evidence before claiming the row covered.

## dirty-worktree handling

The worktree is dirty before this plan. Current dirty files include intro application/domain/repository/test files, DB helpers/migrations, relay server files, `main.dart`, `pubspec.yaml`, `info.plist`, and untracked TOP_15 docs/migration files. The executor must:

- Re-read any owner file immediately before editing.
- Preserve existing uncommitted changes and work with them.
- Use scoped diffs to identify this session's edits.
- Avoid `git reset`, `git checkout --`, or any revert of unrelated work.
- Stop and ask only if concurrent changes make the row impossible to implement safely.

## Device/Relay Proof Profile decision

Selected default profile: `host-helper direct/relay proof`.

Reason: the intended fix is a Flutter retry-orchestration change that should reuse the existing local/direct/relay delivery helper logic already covered by host tests. It should not alter Go relay behavior, bridge transport behavior, simulator harnesses, or real-device network setup.

Required proof under this profile:

- Failing direct-path retry regression first.
- Full `test/features/introduction/application/introduction_outbound_delivery_test.dart`.
- `./scripts/run_test_gates.sh intro`.

Upgrade to `transport-plus-targeted-simulator proof` only if implementation changes real transport, relay probe semantics, inbox storage, `P2PService`, resume ordering, or anything outside helper reuse. Upgrade commands:

```bash
./scripts/run_test_gates.sh transport
INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh
```

## Reviewer Pass

Sufficiency verdict: sufficient with adjustments already folded into this file.

Files/tests/gates missing: none structurally. The plan correctly names the owner production file, direct test file, optional wiring files, direct test command, required `intro` gate, and conditional transport/simulator proof. The direct test is required separately because the `intro` gate script does not include `introduction_outbound_delivery_test.dart`.

Stale or incorrect assumptions: no blocker. Current code confirms retry is inbox-only while initial delivery has local/direct/relay/inbox cascade. The dirty worktree means the executor must re-read owner files before editing.

Overengineering risk: the plan allows a helper refactor only to avoid duplicated delivery-result persistence. It correctly rejects `P2PService`, DB schema, Go relay, or broad retry abstractions for this row.

Minimum needed to make the plan sufficient: keep the inbox-success path, add failing direct retry coverage first, add relay-probe retry coverage, implement direct/relay fallback after inbox failure using existing helper logic, and run the required direct test plus `intro` gate.

## Arbiter Decision

Structural blockers: none.

Incremental details: exact helper shape is deferred to implementation. Acceptable options include a small private persistence helper, a guarded `_deliverEnvelope` inbox fallback parameter, or an ignored return value from an existing staged-delivery helper, as long as the regression proves one failed inbox attempt followed by direct/relay delivery and no public transport API changes.

Accepted differences: host fake direct/relay proof is sufficient while implementation stays inside retry orchestration and reuses existing helper logic. `transport` and targeted simulator E2E remain conditional, not default, because this plan does not require real transport, relay server, bridge, or simulator harness changes.

Stop rule result: no new structural blocker, so planning stops. This file is reusable for execution as `Status: execution-ready`.
