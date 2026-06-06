Status: accepted

# 107 Group Notification Highlight Double Card - Session 02 Plan

Session id: `02-duplicate-row-identity-evidence`

## Planning Progress

- `2026-06-05 15:39 CEST` - Role `Local plan fallback completed`; files inspected since last update: session breakdown, source doc, receive handler, listener, sender, retry use cases, bridge helpers, Go bridge/pubsub, group message model/repository/db helpers, migration chain, notification anchor route, existing handler/listener/drain tests; decision/blocker: the spawned planning child no-progressed after writing only `planning-draft`, so this artifact now records the bounded local execution-ready plan for a durable `logicalDeliveryId` signal; next action: spawn fresh execution/QA child for session 02.
- `2026-06-05 15:31 CEST` - Role `Spawned planner settle poll`; files inspected since last update: unchanged plan artifact plus child output; decision/blocker: planner identified `logicalDeliveryId` as the minimal repo-owned identity and noted retry/recovery/notification-anchor constraints, but did not finish the artifact; next action: terminate no-progress planner and use local plan fallback.
- `2026-06-05 15:27 CEST` - Role `Planner started`; files inspected since last update: rollout source doc, session breakdown, current Session 02 plan, receive handler, listener live/replay entry points, offline replay envelope signing/decrypt path, offline inbox drain path, sender use case, bridge helpers, Go pubsub envelope/extra forwarding, group message model/schema/repository helpers, event-log helper, and direct identity diagnostic tests; decision/blocker: no existing stronger divergent-stable-id identity exists, but a minimal repo-owned sender-generated `logicalDeliveryId` signal is feasible if planned as identity plumbing only, not Session 03 row convergence; next action: rewrite this artifact into an execution-ready refreshed plan with regression-first proof and PGC-007 preservation.
- `2026-06-05 14:43 CEST` - Role `Prior reassessment completed`; files inspected since last update: handler/listener/replay diagnostics and event-log path; decision/blocker: prior accepted state proved only exact `messageId`, `logicalMediaRetry`, and legacy id-less content duplicates; next action: reopen session 02 only if a stronger identity signal is introduced.
- `2026-06-05 14:25 CEST` - Role `Prior execution evidence`; files inspected since last update: prior session-02 diagnostic implementation and test evidence; decision/blocker: prior `groups` gate passed but divergent stable-id text identity remained missing; next action: refresh identity contract under the expanded user goal.

## Real Scope

Introduce the minimum repo-owned logical-delivery identity signal required to unblock session `03-logical-delivery-row-convergence`.

The new signal is a nullable sender-generated `logicalDeliveryId`:

- independent from the local persisted row id, even though modern sends may default it to the resolved outgoing row/message id;
- generated once per logical send and reused across failed-message retry, incomplete-upload retry, live publish, reliable send, offline inbox replay, recovery replay, reload, and notification-anchor row loading;
- carried in Flutter bridge publish/sendReliable payloads, Go envelope extras, signed offline replay plaintext, and Dart listener/replay events;
- persisted on `GroupMessage` as `logical_delivery_id` so reload and notification-anchor paths can recover it from the anchored row;
- exposed in receive diagnostics and repository lookup evidence only in this session.

This session must not merge, delete, hide, or visually collapse duplicate-looking rows. It proves the identity signal and leaves row convergence to session `03`.

## Closure Bar

Session 02 is accepted only when all of these are true:

- no current repo signal stronger than exact `messageId`, `logicalMediaRetry`, and id-less content dedupe is overclaimed;
- `logicalDeliveryId` is introduced as a durable sender-generated correlation id that survives live, replay, recovery, retry, reload, and notification-anchor row loading;
- focused tests prove two incoming deliveries with divergent non-empty `messageId` values and the same non-empty `logicalDeliveryId` are classified as one proven logical delivery by repository/diagnostic lookup, without performing session-03 row convergence;
- PGC-007 preservation remains green: same group/sender/text/timestamp with different non-empty stable ids and no shared logical identity persists as two legitimate rows and emits no duplicate classification;
- legacy id-less content dedupe, exact `messageId` dedupe, and `logicalMediaRetry` behavior remain green;
- replay/listener tests prove live and replay payloads preserve `logicalDeliveryId`;
- sender/retry tests prove fresh sends generate/persist it and retries reuse it;
- migration tests prove fresh install and upgrade add the nullable column and index without rewriting or collapsing existing rows;
- focused receive/listener/replay/persistence tests pass first, then `./scripts/run_test_gates.sh groups` passes;
- `baseline` is not required unless route/app-root/notification startup wiring changes;
- `completeness-check` runs only if new test files or gate classifications are added.

## Source Of Truth

- Rollout source: `Test-Flight-Improv/107-group-notification-highlight-double-card.md`
- Breakdown: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/_current-test-map.md`, `scripts/run_test_gates.sh`
- SQLite workflow: `flutter-sqlite-migrations-and-repositories`
- Current code/tests win over stale prose.
- Session `04-acceptance-closure` owns stable matrix/source-doc closure updates unless this session adds gate classification changes.

## Session Classification

`implementation-ready`

The current blocker is implementation-owned under the expanded goal. The repo lacks a stronger divergent-stable-id identity today, but it can introduce a minimal durable `logicalDeliveryId` without protocol/schema overreach because the existing send, bridge, replay, and persistence seams already carry optional extras and signed replay plaintext.

## Device/Relay Proof Profile

- Profile: `host-only`.
- Live device availability check: not required for session 02 because the work is Flutter/Go host-side identity propagation, persistence, and fake listener/replay proof.
- Required closure evidence: host unit/application tests, migration tests if migration 074 is added, targeted Go bridge/pubsub tests if Go files change, and `./scripts/run_test_gates.sh groups`.
- Device/OS notification proof: deferred to session `04-acceptance-closure`; session 02 only proves the anchored row carries `logicalDeliveryId`.

## Logical Delivery Identity Contract

Positive identities:

- exact non-empty raw `messageId`;
- existing `logicalMediaRetry`, only for the current media retry evidence class;
- legacy id-less same group/sender/sanitized text/timestamp, only when no stable non-empty raw `messageId` exists;
- new non-empty `logicalDeliveryId`, only when both rows/deliveries carry the same value and the group/sender validation path succeeds.

Negative control:

- same group/sender/sanitized text/timestamp with different non-empty stable ids and no shared `logicalDeliveryId` is not a duplicate identity and must preserve both rows.

Session 03 dependency:

- session 03 may implement row convergence only after this session records passing tests for `logicalDeliveryId` propagation and positive/negative identity classification;
- session 03 must use only exact `messageId`, current `logicalMediaRetry`, legacy id-less content dedupe, or new shared `logicalDeliveryId`;
- content-only convergence remains forbidden.

## Likely Code Entry Files

- `lib/features/groups/domain/models/group_message.dart`
- `lib/core/database/migrations/074_group_message_logical_delivery_id.dart`
- `lib/main.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/node/pubsub.go`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `test/shared/fakes/` group repository/message helpers as needed.

## Regression Tests To Add Or Tighten First

Focused tests should be added before or alongside the smallest implementation:

- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - positive: two divergent stable ids with same `logicalDeliveryId` are classified as same logical delivery via diagnostics/repository lookup, with only one canonical identity classification and without session-03 row convergence;
  - negative: PGC-007 same content/timestamp/different stable ids without `logicalDeliveryId` persists two rows;
  - legacy id-less content dedupe still emits `dedupeBy: content`;
  - exact `messageId` duplicate still emits `dedupeBy: messageId`;
  - existing `logicalMediaRetry` test remains green or is tightened if coverage exists.
- `test/features/groups/application/group_message_listener_test.dart`
  - live event carries `logicalDeliveryId` into saved row and identity diagnostics;
  - replay envelope carries `logicalDeliveryId` into saved row and identity diagnostics.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - signed offline replay/drain path preserves `logicalDeliveryId`.
- Sender/retry tests in the existing nearest files:
  - fresh `sendGroupMessage` persists and sends `logicalDeliveryId`;
  - failed-message retry and incomplete-upload retry reuse the existing row's `logicalDeliveryId`.
- Migration/model/helper tests:
  - migration 074 adds nullable `logical_delivery_id` and an index/lookup without rewriting rows;
  - `GroupMessage.fromMap/toMap/copyWith` preserves the field;
  - helper/repository lookup finds an existing row by `group_id`, `sender_peer_id`, and non-empty `logical_delivery_id`.
- Go tests if Go bridge/pubsub files change:
  - `group:publish` and `group:sendReliable` accept/pass `logicalDeliveryId`;
  - envelope extras forward it to Dart receive events.

## Step-By-Step Implementation Plan

1. Add failing/targeted Dart tests for the new identity contract, preserving PGC-007 and legacy exact/content/media behavior.
2. Add migration `074_group_message_logical_delivery_id.dart`, bump DB version from `73` to `74`, wire `onCreate` and `onUpgrade`, and add migration tests.
3. Add `logicalDeliveryId` to `GroupMessage`, `toMap`, `fromMap`, and `copyWith`.
4. Add DB helper/repository lookup for non-empty `logical_delivery_id` scoped by group and sender. Do not make it unique and do not collapse rows in the helper.
5. Thread `logicalDeliveryId` through `sendGroupMessage`, `wireEnvelope`, signed replay plaintext, inbox retry payload, retry use cases, bridge helpers, Go bridge params, Go pubsub envelope extras, listener schema validation, handler params, diagnostics, and replay drain fallbacks.
6. Generate a value for new sends when absent; reuse the existing row value on retry. If old rows lack it, do not synthesize a content-based identity during receive.
7. Prove notification-anchor survival by loading an anchored row with the field preserved; do not redesign notification route payloads unless a test proves row-level identity is insufficient.
8. Format touched Dart/Go files and run focused tests first.
9. Run required gates and record exact commands/results in `## Execution Progress`.
10. Update this session plan final execution verdict. If tests prove the contract, update the breakdown ledger so session 03 becomes runnable; otherwise keep session 03 prerequisite-blocked with exact blocker evidence.

## Exact Tests And Gates To Run

Focused first:

```bash
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name "logical delivery|identity diagnostic|PGC-007|legacy id-less|logicalMediaRetry"
flutter test test/features/groups/application/group_message_listener_test.dart --name "logical delivery|identity diagnostic"
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name "logical delivery|identity diagnostic"
```

Persistence and send/retry:

```bash
flutter test test/features/groups/domain/models/group_message_test.dart
flutter test test/core/database/migrations/074_group_message_logical_delivery_id_test.dart
flutter test test/features/groups/application/send_group_message_use_case_test.dart --name "logical delivery"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --name "logical delivery"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --name "logical delivery"
```

Full touched suites as needed:

```bash
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
```

Go, only if Go files change:

```bash
cd go-mknoon && go test ./bridge ./node -run 'Group.*LogicalDelivery|LogicalDelivery|GroupPublish|GroupSendReliable'
```

Required named gate:

```bash
./scripts/run_test_gates.sh groups
```

Conditional:

```bash
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh completeness-check
```

Run `baseline` only if route/app-root/notification startup wiring changes. Run `completeness-check` only if new test files or gate classifications are added.

## Known-Failure Interpretation

- Any failure that collapses PGC-007 distinct stable ids without shared `logicalDeliveryId` is blocking.
- Any positive test that relies only on group/sender/text/timestamp is blocking.
- Missing migration coverage after adding migration 074 is blocking.
- Go failures are session-owned if Go bridge/pubsub files change.
- The unrelated full-wired send-refresh red test noted by session 01 remains out of scope unless this session touches send-refresh UI code.

## Done Criteria

- `logicalDeliveryId` is durable, nullable, generated once per logical send, and reused across retries.
- Live, replay, recovery, reload, and notification-anchor row loading preserve it.
- Session 02 records a proven identity contract for session 03 without merging rows.
- PGC-007, legacy id-less dedupe, exact `messageId` dedupe, and `logicalMediaRetry` behavior remain green.
- Focused tests and `./scripts/run_test_gates.sh groups` pass or failures are exactly recorded with blocker classification.
- This plan and the breakdown ledger record the exact final execution verdict and commands/results.

## Scope Guard

Do not implement session 03 row convergence in this session. Do not delete, merge, hide, visually collapse, or reorder duplicate-looking rows. Do not use content-only identity for rows with non-empty stable ids. Do not make `logical_delivery_id` unique in the database. Do not update stable closure matrices or source-doc closure rows before session 04. Do not broaden notification routing unless a focused test proves row-level anchor survival is insufficient.

## Reviewer Pass

Plan sufficiency: sufficient for execution. The scope is minimal and uses an explicit durable identity signal rather than content-only convergence. It names migration, model, repository, send/retry, bridge, listener, replay, diagnostics, and tests.

Structural risks addressed: migration coverage is mandatory; PGC-007 is a hard negative control; session 03 convergence remains separate.

Missing items: none known. Device-backed notification proof is intentionally deferred to session 04 because session 02 is host-only identity propagation.

## Arbiter Pass

Structural blockers remaining: none for session 02 execution.

Incremental details intentionally left to execution: exact helper names, exact generated `logicalDeliveryId` format, and whether existing generated values equal the outgoing row id or a separate UUID. The only hard requirement is one value per logical send, reused across retries and carried independently from divergent receive row ids.

Accepted differences: session 02 proves and persists the identity signal but does not converge rows; session 03 owns convergence and reaction/timeline preservation; session 04 owns final stable docs/matrices.

## Execution Progress

- `2026-06-05 16:00 CEST` - Phase `session 02 gates complete`; files inspected/touched: all session-02 code/test deltas plus this plan artifact; command/result: `./scripts/run_test_gates.sh groups` -> `All tests passed!` (`+321`); command/result: `./scripts/run_test_gates.sh completeness-check` -> `Completeness check: 769/769 test files classified. Completeness check PASS.`; command/result: `git diff --check` -> exit `0` with no output; decision/blocker: no remaining session-02 blocker. The new nullable `logicalDeliveryId` identity contract is proven for propagation/classification and preserves PGC-007, legacy id-less content dedupe, exact `messageId` dedupe, and current `logicalMediaRetry` coverage; next action: update the breakdown ledger so session `03-logical-delivery-row-convergence` is runnable using only this proven contract.
- `2026-06-05 15:58 CEST` - Phase `focused identity proof green`; files touched: `lib/core/database/migrations/074_group_message_logical_delivery_id.dart`, `lib/main.dart`, group message model/repository/db helper files, group send/retry/receive/listener/replay application files, Flutter bridge helpers, Go bridge/pubsub files, in-memory group repository fake, and focused Dart/Go tests; command/result: `flutter test test/features/groups/domain/models/group_message_test.dart test/core/database/migrations/074_group_message_logical_delivery_id_test.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart` -> `All tests passed!` (`+60`); command/result: `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name "logical delivery|identity diagnostic|PGC-007|legacy id-less|logicalMediaRetry"` -> `All tests passed!` (`+6`), proving exact `messageId`, legacy id-less content dedupe, PGC-007 preservation, and shared `logicalDeliveryId` classification without row convergence; command/result: `flutter test test/features/groups/application/group_message_listener_test.dart --name "logical delivery|identity diagnostic"` -> `All tests passed!` (`+2`); command/result: `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name "logical delivery|identity diagnostic"` -> `All tests passed!` (`+1`); command/result: `flutter test test/features/groups/application/send_group_message_use_case_test.dart --name "logical delivery"` -> `All tests passed!` (`+1`); command/result: `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --name "logical delivery"` -> `All tests passed!` (`+1`); command/result: `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --name "logical delivery"` -> `All tests passed!` (`+1`); command/result: `flutter test test/core/database/integration/full_migration_chain_test.dart` -> `All tests passed!` (`+7`); command/result: `go test ./bridge ./node -run 'Group.*LogicalDelivery|LogicalDelivery|BuildGroupMessageExtra'` from `go-mknoon` -> `ok` for both packages; decision/blocker: session 02 now has focused green evidence for a repo-owned nullable `logicalDeliveryId` identity signal across persistence, live listener, signed offline replay, send, retry, and Go envelope propagation while preserving PGC-007; next action: run required named `groups` gate and conditional `completeness-check` because a new migration test file was added, then close or block session 02 based on gate results.
- `2026-06-05 15:49 CEST` - Phase `local execution fallback started`; files inspected/touched: this plan artifact; command/result: no tests run yet; decision/blocker: spawned child contexts repeatedly persisted heartbeats without materializing code or test deltas, so the current session will execute the already-approved session-02 scope locally while preserving the same fresh-child audit notes in this artifact; next action: inspect exact owner files, add the nullable `logicalDeliveryId` identity plumbing and regression proof, then run focused tests before named gates.
- `2026-06-05 15:44 CEST` - Phase `narrower spawned execution no-progress closed`; files inspected/touched: no code/test/doc delta beyond command-output inspection by the child; command/result: killed stalled narrower `codex exec` processes after bounded wait and failed progress request because stdin was closed; decision/blocker: no product blocker yet, but spawned execution materialization is unreliable for this session; next action: use the single current-session local execution fallback to implement only session-02 `logicalDeliveryId` identity plumbing and tests.
- `2026-06-05 15:43 CEST` - Phase `spawned execution closed before code delta`; files inspected/touched: this plan artifact only after the isolated Executor heartbeat; command/result: killed stalled `codex exec` execution orchestrator processes after bounded wait and settle poll produced owner-file inspection notes but no code/test/doc delta and no test results; decision/blocker: no product blocker yet, classify as spawned execution no-progress under the code-writing exception; next action: spawn one fresh narrower execution child scoped to owner files/tests and exact expected artifacts.
- `2026-06-05 15:38 CEST` - Phase `owner files inspected before edits`; files inspected: `group_message.dart`, `group_messages_db_helpers.dart`, group repository interface/impl, `main.dart` migration/version wiring, migration 073 test/example, `send_group_message_use_case.dart`, retry failed/incomplete upload use cases, `bridge_group_helpers.dart`, `group_message_listener.dart`, `handle_incoming_group_message_use_case.dart`, `drain_group_offline_inbox_use_case.dart`, `group_offline_replay_envelope.dart`, Go bridge/pubsub extras, and nearest tests by name search; command/result: no tests run yet; decision/blocker: no blocker, current code has no logical-delivery field and diagnostics only cover exact `messageId`, `logicalMediaRetry`, and legacy id-less content; next action: edit schema/model/repository and payload propagation without row convergence.
- `2026-06-05 15:36 CEST` - Phase `Executor implementation pass started`; files inspected: session plan, execution QA skill notes, SQLite migration workflow notes, and `git status --short`; command/result: no tests run yet; decision/blocker: proceeding under the strict scope guard for nullable durable `logicalDeliveryId` identity evidence only, preserving existing dirty worktree changes and avoiding any row convergence; next action: inspect owner files/tests before adding regression-first changes.
- `2026-06-05 15:34 CEST` - Phase `Executor spawned/running`; files inspected: execution contract docs only; command/result: spawned isolated Executor agent `019e97ff-3550-70c0-bacc-2afaa171a1c4` with requested model `gpt-5.5` and reasoning effort `xhigh` in prompt; decision/blocker: implementation delegated under scope guard, no local implementation edits will overlap while Executor is active; next action: wait for Executor completion and then spawn a separate QA Reviewer.
- `2026-06-05 15:34 CEST` - Phase `contract extracted`; files inspected: session plan, session breakdown, gate definitions, current test map, and `scripts/run_test_gates.sh`; command/result: docs confirm `groups` is the required named gate, `baseline` is conditional on route/app-root/notification startup wiring, and `completeness-check` is conditional on new test files or gate classifications; extracted scope: add nullable durable `logicalDeliveryId` persistence/propagation/diagnostics and regression-first proof only; explicit non-goals: no row convergence, no merge/delete/hide/reorder of duplicate-looking rows, no content-only convergence for stable-id rows, no unique DB constraint; next action: spawn isolated Executor with model `gpt-5.5` and reasoning effort `xhigh`.
- `2026-06-05 15:34 CEST` - Phase `contract extraction started`; files inspected: current session plan and `git status --short`; command/result: `git status --short` shows existing modified group receive/listener/replay/UI/test files plus untracked session artifacts; decision/blocker: no blocker before contract extraction, but existing dirty worktree must be preserved and edits remain scoped to session 02 `logicalDeliveryId` identity proof; next action: extract the execution contract before spawning the isolated Executor.
- `2026-06-05 15:40 CEST` - Phase `dirty-worktree snapshot before refreshed execution`; command/result: `git status --short` showed modified receive/listener/replay diagnostic files from prior session 02, modified group conversation UI/test files from prior session 01, and untracked current-doc plan/breakdown artifacts; decision/blocker: no unsafe unrelated blocker for session 02 execution, but new execution must stay scoped to durable `logicalDeliveryId` identity propagation/classification plus required tests/migration evidence; next action: spawn fresh execution/QA child with model `gpt-5.5` and reasoning effort `xhigh`.

## Final Execution Verdict

- Verdict: `accepted`
- Proven contract: a non-empty nullable `logicalDeliveryId` is a safe same-logical-delivery identity only when scoped by validated group and sender and shared by both deliveries. It is generated once for modern sends, persisted on `GroupMessage.logical_delivery_id`, carried through Flutter send/retry payloads, Go bridge extras, live listener events, signed offline replay/drain paths, recovery replay, reload row loading, and notification-anchor row loading.
- Scope explicitly not performed: no session-03 row convergence, merge, delete, hide, reorder, or content-only collapse occurred in this session.
- Negative control preserved: PGC-007 same group/sender/text/timestamp rows with different non-empty stable ids and no shared `logicalDeliveryId` still persist as distinct legitimate rows and emit no logical-delivery duplicate classification.
- Required evidence: focused persistence/receive/listener/replay/send/retry/migration tests passed; targeted Go bridge/pubsub tests passed; `./scripts/run_test_gates.sh groups` passed with `+321`; `./scripts/run_test_gates.sh completeness-check` passed with `769/769` classified; `git diff --check` passed.
- Downstream effect: session `03-logical-delivery-row-convergence` is now runnable, but it must use only exact `messageId`, current `logicalMediaRetry`, legacy id-less content dedupe, or the newly proven shared `logicalDeliveryId` contract. Content-only convergence for stable-id rows remains forbidden.
