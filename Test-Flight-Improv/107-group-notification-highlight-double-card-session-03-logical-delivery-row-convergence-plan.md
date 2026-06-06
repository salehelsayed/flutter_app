Status: accepted

# 107 Group Notification Highlight Double Card - Session 03 Plan

Session id: `03-logical-delivery-row-convergence`

## Planning Progress

- `2026-06-05 16:02 CEST` - Role `Arbiter completed`; files inspected since last update: session 02 accepted plan, breakdown ledger, receive handler, repository lookup, focused handler/listener/replay/widget reaction tests; decision/blocker: no structural blocker remains because session 02 proved the nullable `logicalDeliveryId` contract and PGC-007 preservation; next action: implement convergence only in the logical-delivery branch and run focused tests before named gates.
- `2026-06-05 16:02 CEST` - Role `Reviewer completed`; files inspected since last update: receive handler duplicate branches, media retry enrichment helper, PGC-007 and logical-delivery tests, listener/replay suites, group conversation reaction tests; decision/blocker: plan is sufficient if it keeps exact-id/media/content behavior unchanged, converts only the proven logical-delivery match into a duplicate return, and records source verification requirements rather than adding unrelated simulator work; next action: mark execution-ready.
- `2026-06-05 16:02 CEST` - Role `Planner completed`; files inspected since last update: receive handler branch order and tests around PGC-007/logical delivery; decision/blocker: smallest code change is to reuse `_enrichExistingDuplicateMessage` for the existing logical row, emit `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with `dedupeBy: logicalDeliveryId`, and return `null`; next action: reviewer pass.
- `2026-06-05 16:01 CEST` - Role `Evidence Collector completed`; files inspected since last update: `handle_incoming_group_message_use_case.dart`, `handle_incoming_group_message_use_case_test.dart`, `group_message_listener_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, `group_conversation_screen_test.dart`, `group_conversation_wired_test.dart`; decision/blocker: session 02 lookup already finds the canonical row after validation, but currently emits `GROUP_HANDLE_INCOMING_MSG_LOGICAL_DELIVERY_MATCH` and still persists the second row; next action: draft the scoped convergence plan.

## Real Scope

Implement row convergence for proven duplicate logical incoming group deliveries.

Allowed positive identities:

- exact non-empty `messageId`, already handled;
- current `logicalMediaRetry`, already handled;
- legacy id-less content duplicate, already handled;
- new shared non-empty `logicalDeliveryId`, only after group/sender validation and only through the session-02 repository lookup.

This session changes only the shared-`logicalDeliveryId` branch from diagnostic-only classification into duplicate convergence. It must not merge, hide, delete, or reorder rows based only on group/sender/text/timestamp when non-empty stable ids differ and no shared logical identity exists.

## Closure Bar

- Two incoming deliveries with divergent non-empty local/stable row ids but the same group, sender, and proven non-empty `logicalDeliveryId` persist as one row.
- The converged duplicate returns `null`, emits `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with `dedupeBy: logicalDeliveryId`, and points diagnostics at the canonical existing row.
- Duplicate logical delivery replay can enrich the canonical row with missing quote/media data, matching exact `messageId` duplicate behavior.
- PGC-007 same group/sender/text/timestamp with different non-empty stable ids and no shared `logicalDeliveryId` still persists as two legitimate rows and emits no duplicate/logical-delivery collapse event.
- Exact `messageId`, current `logicalMediaRetry`, and legacy id-less content dedupe remain green.
- Listener/replay tests prove live plus replay shared logical delivery converges to one row.
- Touched widget/wired tests for duplicate-looking rows and reaction coherence remain green.
- `./scripts/run_test_gates.sh groups` passes.

## Source Of Truth

- Rollout source: `Test-Flight-Improv/107-group-notification-highlight-double-card.md`
- Breakdown: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`
- Session 02 accepted identity contract: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md`
- Current code/tests beat stale prose.
- Source verification requirements for this rollout define required gates; final simulator or stable-document closure remains owned by session `04-acceptance-closure`.

## Session Classification

`implementation-ready`

## Exact Problem Statement

Session 02 proved that `logicalDeliveryId` safely identifies one logical delivery even when raw local/stable row ids diverge, but the receive handler still persists both rows. This leaves the user-visible duplicate-card path open across live plus replay/recovery. Session 03 must converge only that proven duplicate delivery into the canonical row while preserving PGC-007 legitimate distinct sends.

## Files And Repos To Inspect Next

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

## Existing Tests Covering This Area

- Handler tests already cover exact `messageId` duplicate, legacy id-less content duplicate, `logicalMediaRetry`, PGC-007 negative controls, and session-02 diagnostic-only `logicalDeliveryId` classification.
- Listener tests already prove live/replay payloads carry `logicalDeliveryId`.
- Drain tests already prove signed offline replay carries `logicalDeliveryId`.
- Widget/wired tests already cover duplicate-looking row shells, reaction inspection, and notification-anchor reaction coherence.

## Regression Tests To Add Or Tighten First

- Tighten the handler `logicalDeliveryId` positive test so the second divergent stable-id delivery returns `null`, only one row remains, and the duplicate event uses `dedupeBy: logicalDeliveryId`.
- Keep the PGC-007 negative test explicitly asserting two rows and no logical-delivery duplicate.
- Add listener live plus replay convergence proof with divergent `messageId` values and shared `logicalDeliveryId`.
- Add drain/offline replay convergence proof with divergent `messageId` values and shared `logicalDeliveryId`.
- Keep exact `messageId`, legacy id-less content, and `logicalMediaRetry` focused tests green.

## Step-By-Step Implementation Plan

1. Tighten the handler positive regression from diagnostic-only to convergence.
2. Add/tighten listener and drain tests for shared logical delivery convergence across live plus replay.
3. In `handleIncomingGroupMessage`, after validated group/sender checks and before media/content fallbacks, change the shared-`logicalDeliveryId` branch to:
   - enrich the canonical row with missing quote/media through `_enrichExistingDuplicateMessage`;
   - emit `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with `dedupeBy: logicalDeliveryId`;
   - return `null` without saving the divergent row.
4. Preserve the existing exact `messageId`, media retry, and legacy id-less branches.
5. Format and run focused tests before `groups`.

## Risks And Edge Cases

- PGC-007 collapse risk if content/timestamp is used; prohibited.
- Reaction coherence depends on preserving the canonical row id rather than creating a second row; no reaction migration should be needed.
- Timeline ordering depends on not adding the replay row; the canonical row keeps its original position.
- Reload and notification-anchor behavior depend on the canonical persisted row retaining `logicalDeliveryId`.
- Repair placeholders must stay excluded from convergence, matching the session-02 branch guard.

## Exact Tests And Gates To Run

Focused first:

```bash
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name "logical delivery|PGC-007|legacy id-less|logicalMediaRetry|duplicate by messageId"
flutter test test/features/groups/application/group_message_listener_test.dart --name "logical delivery|duplicate"
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name "logical delivery|duplicate"
```

Touched widget/wired reaction and duplicate-looking row checks:

```bash
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --name "single glass shell|reaction and media enrichment|reaction"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "reaction inspection|incoming reaction change stream|duplicate"
```

Required gate:

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

- Any result that collapses PGC-007 distinct stable-id sends without shared `logicalDeliveryId` is blocking.
- Any convergence that uses only content/timestamp for stable-id rows is blocking.
- Existing unrelated full-wired send-refresh issues from session 01 remain non-blocking unless this session changes that path.

## Done Criteria

- Shared non-empty `logicalDeliveryId` duplicate deliveries converge to one persisted row.
- PGC-007 remains two persisted rows.
- Exact `messageId`, `logicalMediaRetry`, and legacy id-less content dedupe remain green.
- Listener/replay and drain/recovery paths converge shared logical deliveries.
- Touched reaction/duplicate-looking row widget or wired tests pass.
- `./scripts/run_test_gates.sh groups` passes.
- This plan and the breakdown ledger record exact commands/results and final verdict.

## Scope Guard

Do not implement content-only convergence for stable-id rows. Do not add another DB migration. Do not make `logical_delivery_id` unique. Do not rewrite notification routing or app-root startup. Do not move reaction rows between message ids; preserve canonical-row identity by preventing the duplicate row from being created.

## Reviewer Pass

The plan is narrow enough for execution because the identity prerequisite is already accepted in session 02 and the code seam already performs a scoped repository lookup after validation. Required negative controls and gates are explicit.

Potential concern resolved: simulator-backed final product closure is not added to session 03 because the current rollout verification contract assigns final acceptance and stable documentation closure to session 04; session 03 is the host receive/persistence convergence implementation.

## Arbiter Pass

Structural blockers: none.

Incremental details: exact listener/drain test names may be adjusted to existing harness helper names.

Accepted differences: final stable matrices/source-doc closure and any broader notification-open acceptance proof remain in session `04-acceptance-closure`.

## Execution Progress

- `2026-06-05 16:07 CEST` - Phase `session 03 gates complete`; files inspected/touched: session-03 receive/test deltas and this plan artifact; command/result: `./scripts/run_test_gates.sh groups` -> `All tests passed!` (`+321`); command/result: `git diff --check` -> exit `0` with no output; decision/blocker: no remaining session-03 blocker. Shared non-empty `logicalDeliveryId` now converges divergent stable-id deliveries to one persisted canonical row, while PGC-007 same-content/timestamp stable-id rows without shared identity remain distinct; next action: update breakdown ledger and run session `04-acceptance-closure`.
- `2026-06-05 16:06 CEST` - Phase `focused convergence proof green`; files touched: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; command/result: `dart format lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` -> `Formatted 4 files (0 changed) in 0.59 seconds.`; command/result: `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name "logical delivery|PGC-007|legacy id-less|logicalMediaRetry|duplicate by messageId"` -> `All tests passed!` (`+5`), proving shared `logicalDeliveryId` convergence, PGC-007 preservation, legacy id-less dedupe, and exact-id duplicate behavior; command/result: `flutter test test/features/groups/application/group_message_listener_test.dart --name "logical delivery|duplicate"` -> `All tests passed!` (`+17`); command/result: `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name "logical delivery|duplicate"` -> `All tests passed!` (`+7`); command/result: `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --name "single glass shell|reaction and media enrichment|reaction"` -> `All tests passed!` (`+4`); command/result: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "reaction inspection|incoming reaction change stream|duplicate"` -> `All tests passed!` (`+4`); decision/blocker: no focused blocker, the receive branch now enriches the canonical row and emits `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with `dedupeBy: logicalDeliveryId` without saving the divergent row; next action: run required `./scripts/run_test_gates.sh groups` and `git diff --check`.
- `2026-06-05 16:02 CEST` - Phase `execution-ready plan written`; files inspected/touched: session 03 plan artifact, session 02 accepted plan, breakdown ledger, receive handler, focused handler/listener/replay/widget tests; command/result: no session-03 implementation tests run yet; decision/blocker: no blocker, proceed to regression-first edits; next action: tighten logical-delivery convergence tests and implement the receive branch.

## Final Execution Verdict

- Verdict: `accepted`
- Implemented convergence: after group/member validation and exact-id checks, a divergent stable-id incoming delivery with the same non-empty `logicalDeliveryId`, group id, and sender id as an existing row now enriches the canonical row, emits `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with `dedupeBy: logicalDeliveryId`, returns `null`, and does not persist the divergent row.
- Preservation proof: PGC-007 same group/sender/text/timestamp rows with different non-empty stable ids and no shared `logicalDeliveryId` still persist as two legitimate rows and emit no logical-delivery duplicate event.
- Regression proof: focused handler/listener/drain/widget/wired tests passed; `./scripts/run_test_gates.sh groups` passed with `+321`; `git diff --check` passed.
- Conditional gates: `baseline` was not required because route/app-root/notification startup wiring did not change. `completeness-check` was not required in session 03 because no new test files or gate classifications were added.
- Downstream effect: session `04-acceptance-closure` is runnable and owns final acceptance evidence plus source/stable documentation closure.
