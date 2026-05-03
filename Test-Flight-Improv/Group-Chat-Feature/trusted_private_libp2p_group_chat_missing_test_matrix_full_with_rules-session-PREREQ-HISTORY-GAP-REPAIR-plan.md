# Session PREREQ-HISTORY-GAP-REPAIR Plan - OS-006 Direct/Multi-Peer History Gap Repair

Status: qa_passed

## Planning Progress

| timestamp | role | files inspected since last update | decision/blocker | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T19:35:00+02:00 | Arbiter completed | This plan; Reviewer Findings; `implementation-plan-orchestrator` Arbiter contract | No structural blockers remain. Reviewer notes are incremental details or accepted differences; status moved to `execution-ready`. | Hand off to Executor; keep OS-006 `Partial` until implementation proof updates source docs. |
| 2026-05-01T19:34:30+02:00 | Arbiter started | This plan; Reviewer Findings; `implementation-plan-orchestrator` Arbiter contract | Classifying reviewer findings and deciding whether any pre-execution plan patch is required. | Complete Arbiter Decision. |
| 2026-05-01T19:34:00+02:00 | Reviewer completed | This plan; `implementation-plan-orchestrator` skill contract; OS-006 source matrix row; session breakdown row 54; test inventory/source OS-006 references; `test-gate-definitions.md`; `scripts/run_test_gates.sh`; current migration numbering and likely owner-file existence | Verdict: sufficient with only incremental implementation details. No structural blocker found; status moved to `reviewer-pass`. | Run Arbiter. |
| 2026-05-01T19:29:00+02:00 | Reviewer started | This plan; mandatory section checklist; source row and gate definitions lookup started | Reviewer validating scope, closure bar, DB/migration coverage, Go/bridge coverage, source-doc closure, live-fixture reliance, stop rule, and validation/dedupe guardrails. | Complete sufficiency review. |
| 2026-05-01T19:28:00+02:00 | Planner completed | Evidence Collector findings; OS-006 source matrix, inventory, gate definitions, and owner files | Draft plan written as implementation-ready pending Reviewer/Arbiter. Host/fake-network proof is primary; live device/relay proof is supporting only. | Run Reviewer. |

## Run Mode

- Active mode: implementation-committed gap-closure.
- Reopened prerequisite: `PREREQ-HISTORY-GAP-REPAIR`.
- Owned source row: `OS-006`.
- Source row state at planning intake: `Partial`.
- Intended closure effect: move OS-006 to `Covered` only if the source matrix can cite concrete code/test evidence for partial-history detection, direct or multi-source repair, durable gap lifecycle state, duplicate-safe repair application, and UI truth before/during/after repair.
- Device/relay defaults verified on 2026-05-01: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` is booted and visible to Flutter; `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` is available for supporting proof when a plan requires it. Host/fake-network proof remains primary unless a fixture explicitly requires live relay/device coverage.

## Evidence Collector Findings

### Existing Behavior

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` is the current Flutter recovery owner. It retrieves relay inbox pages through `callGroupInboxRetrieveWithCursor`, carries the opaque cursor forward, and stops only when the cursor is empty or `drainAllPages` is false (`_drainGroupInbox`, lines 215-224 and 413-451).
- The drain path records retention truth, not repair state. Non-system messages older than `groupBacklogRetentionCutoff` are skipped, retained messages continue through later cursor pages, and `_persistRetentionState` writes only `lastBacklogExpiredAt` / `lastBacklogRetainedAt` on `GroupModel` (lines 273-286 and 663-680).
- The same drain path has missing-key repair hooks through `GroupPendingKeyRepairRepository`, but those are future/missing group key replay repairs, not partial history gap repairs (lines 231-245 and 558-623).
- `lib/features/groups/application/rejoin_group_topics_use_case.dart` rejoins existing group PubSub topics with stored group config/key material and emits flow events. It does not request history heads, ranges, hashes, or peer-supplied repair content (lines 52-136).
- `lib/features/groups/presentation/group_backlog_retention_notice.dart` and `lib/features/groups/presentation/screens/group_conversation_screen.dart` render expired or mixed-window backlog notices from `lastBacklogExpiredAt` / `lastBacklogRetainedAt`. They do not model `gap detected`, `repairing`, `repaired`, or repair-failed UI states (notice lines 22-48; conversation screen lines 163-167 and 352-398).
- `lib/core/bridge/bridge_group_helpers.dart` exposes `callGroupInboxStore`, legacy timestamp retrieval, and `callGroupInboxRetrieveWithCursor`; the cursor helper sends only `{groupId, cursor, limit}` and returns `{messages, cursor}` (lines 663-880).
- `lib/core/bridge/go_bridge_client.dart` maps group bridge commands through `group:inboxStore`, `group:inboxRetrieve`, and `group:inboxRetrieveCursor`; no group history repair command is registered in the command map (lines 100-116).
- `go-mknoon/node/group_inbox.go` has a relay group inbox request with `action`, `groupId`, `from`, `message`, `recipientPeerIds`, `sinceTimestamp`, `cursor`, and `limit`. `GroupInboxRetrieveWithCursor` is relay cursor pagination only and has no request/response fields for ranges, known heads, hash chains, peer source identity, or repair clearance (lines 13-34 and 144-162).
- `go-mknoon/bridge/bridge.go` exposes `GroupInboxRetrieveCursor` to the native bridge with input `{groupId, cursor, limit}` and output `{ok, messages, cursor}`. No direct peer history repair bridge method exists in the inspected bridge surface (lines 2114-2168).

### Existing Coverage

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` proves cursor continuation without `sinceTimestamp`, cursor timeout error telemetry, first-page-only drain behavior, retained/expired backlog boundary persistence, repeated-drain dedupe, and expired-page continuation to retained pages (notably tests around lines 1141-1195, 1573-1732, and 2741-2898).
- `test/features/groups/integration/group_resume_recovery_test.dart` proves fake-network relay inbox behavior: multi-page cursor drain, duplicate message-id suppression across cursor pages, mixed-window retention, partial delivery completed by inbox drain, and temporary partition replay in cursor order followed by live delivery after heal (tests around lines 2971-3330 and 3879-4201).
- `test/features/groups/presentation/group_conversation_screen_test.dart` and `test/features/groups/presentation/group_list_screen_test.dart` prove the user sees expired and mixed-window backlog-retention notices while retained messages stay visible (conversation tests around lines 833-893; list tests around lines 176-217).
- `go-mknoon/node/group_inbox_test.go` proves relay cursor defaults, opaque cursor acceptance through the node layer, structurally distinct first/continuation requests, started-node guard, and relay-visible encrypted replay envelope preservation (lines 90-149 and 151-321).
- `go-mknoon/bridge/bridge_test.go` proves bridge-level `GroupInboxRetrieveCursor` validation/exposure and opaque cursor acceptance without `INVALID_INPUT` rejection (lines 1493-1498, 1838-1849, and 2510-2574).
- Supporting Go recovery tests prove adjacent relay/topic behavior, not gap repair: `TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh`, `TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery`, `TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace`, and `TestGroupInboxRetrieveWithCursor_TriesSecondRelayWhenFirstFails`.

### Missing Seams

- No inspected Flutter, bridge, or Go owner exposes a direct peer history repair protocol, history range request, known-head exchange, hash-chain comparison, missing-range claim, anti-entropy loop, or peer-supplied history response.
- No durable group history gap lifecycle state exists in the inspected persistence/model surfaces. The only durable adjacent states found are backlog-retention timestamps on `GroupModel` and key-repair rows under `group_pending_key_repairs`; neither represents a partial-history gap lifecycle.
- No multi-source or multi-peer repair selection exists. Current multi-relay code chooses relay endpoints for inbox retrieval failover; it is not authorized peer source selection for repairing history gaps.
- No repair-clearance proof exists. Existing tests prove duplicate-safe application of cursor replay and retention honesty, but not that a detected gap remains visible until a verified repair from authorized sources fills or clears it.
- No UI state distinguishes retention-window expiry from active repair. The current presentation truth is "expired" or "mixed-window retained" only.

### Likely Owner Files

- Flutter application entry: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`.
- Topic/recovery coordination adjacency: `lib/features/groups/application/rejoin_group_topics_use_case.dart`.
- Flutter bridge surface: `lib/core/bridge/bridge_group_helpers.dart` and `lib/core/bridge/go_bridge_client.dart`.
- Go node/bridge surface: `go-mknoon/node/group_inbox.go` and `go-mknoon/bridge/bridge.go`.
- UI truth surfaces: `lib/features/groups/presentation/screens/group_conversation_screen.dart` and likely `lib/features/groups/presentation/group_backlog_retention_notice.dart` or a sibling notice model if repair state must stay separate from retention expiry.
- New durable gap lifecycle work would likely need a model/repository/migration owner; no such owner exists in the inspected OS-006 surfaces today.

### Likely Blast Radius

- Application replay ordering, duplicate suppression, and removed-member cutoff paths already run through the drain/listener path, so gap repair must not bypass `GroupMessageListener` / `handleIncomingGroupMessage` validation or existing message-id dedupe.
- Bridge/API changes would affect the Dart command map, Go bridge exports, Go node protocol surface, and focused fake-network tests.
- Any durable gap lifecycle state would add database migration/helper/repository tests and UI tests, beyond the existing retention timestamp fields.
- Device/relay proof is supporting only for this prerequisite unless the later plan explicitly requires it. Host/fake-network proof is sufficient as the primary implementation proof surface because the missing seams are repo-owned primitives, not live-fixture availability.

### Stale vs Authoritative Docs

- Intake-time status before implementation: the trusted-private source matrix row `OS-006`, this prerequisite plan shell, and the session breakdown kept OS-006 `Partial` / prerequisite-blocked until direct or multi-peer history repair primitives and durable lifecycle proof existed.
- Current status after executor, fix-pass verification recovery, and final QA: the source matrix and `test-inventory.md` OS-006 rows are updated to `Covered` with concrete code/test evidence, and breakdown row 54 is `accepted` / `qa_passed`.
- Older adjacent evidence such as fake-network partition recovery and relay cursor continuation is supporting only; OS-006 closure now rests on the new durable gap lifecycle, relay/Go/Dart repair range seam, multi-source validation/fallback, listener/dedupe replay application, UI repair-state proof, direct tests, named gates, and diff hygiene recorded in this plan's Execution Progress.
- Earlier notes that `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset are stale for fixture availability. The verified defaults were available on 2026-05-01, but live device/relay proof remains supporting only because the OS-006 gap was repo-owned and closed by host/fake-network-testable production seams.

## Real Scope

Implement the smallest first-class history-gap repair slice needed for OS-006:

- detect a history gap from the group inbox/recovery boundary using explicit range/head/hash metadata rather than timestamp guessing
- persist a durable per-group gap lifecycle (`detected`, `repairing`, `repaired`, `failed`) separately from backlog-retention timestamps
- request repair data from authorized group-member sources through a typed bridge/app seam, with deterministic range-hash validation and multi-source fallback
- apply repaired encrypted replay envelopes through the existing group message replay/listener path so signature/device/member validation, removed-member cutoff handling, message-id dedupe, media handling, and ordering stay unchanged
- show UI truth for active, repaired, or failed history gaps without confusing repair state with retention expiry
- update OS-006 source docs only after direct tests and gates prove the row can move to `Covered`

The session may add new model/repository/helper/migration files and bridge command surfaces if needed. It must not redesign group messaging, introduce a server-side archive product, or replace the existing relay cursor drain.

## Closure Bar

OS-006 can move from `Partial` to `Covered` only when all of these are true:

- a real code seam records detected history gaps with range/head/hash metadata and candidate repair sources
- durable storage survives repository/DB reopen and preserves the lifecycle until a verified repair succeeds or a terminal failure is recorded
- at least one regression proves multi-source behavior: an unauthorized, incomplete, or hash-mismatched source is rejected and a later authorized matching source repairs the gap
- repaired messages flow through the existing replay/listener path and do not create duplicate or out-of-order timeline rows
- the UI distinguishes retention expiry from active/failed/repaired history repair state
- Go/bridge command tests prove the typed repair request/response surface is exposed and validates required fields, even if full live relay proof remains supporting
- `groups`, `completeness-check`, targeted direct suites, and diff hygiene pass
- source matrix, test inventory, this plan, and the session breakdown cite concrete file/test evidence before claiming `Covered`

## Source Of Truth

- Primary status source: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, row `OS-006`.
- Current prerequisite scope: row 54 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.
- Existing accepted adjacent evidence: `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-OS-006-plan.md` and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Test-gate source of truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.
- Code wins over stale prose if an older doc claims cursor recovery alone is enough. Cursor recovery, partition replay, and backlog retention honesty remain supporting evidence only.

## Session Classification

`implementation-ready`.

This is a repo-owned code-and-test prerequisite. The missing pieces are production seams and host/fake-network-testable behavior, not an external fixture. Live iOS/relay defaults are verified and may be used as supporting proof, but they are not required to start or close the host/fake-network implementation slice.

## Exact Problem Statement

OS-006 requires partial history detection and multi-peer gap repair. The repo currently handles relay inbox pagination, duplicate-safe replay, fake-network partition recovery, and backlog retention honesty, but it does not know when a timeline range is missing, cannot ask authorized peers or sources for a bounded range, cannot verify range/head/hash integrity, cannot persist repair lifecycle state, and cannot tell the user that a detected gap is being repaired or failed.

The user-visible failure is that a client can honestly show retained/expired relay backlog state, yet still has no first-class way to detect and clear a missing history range from another source without duplicate or out-of-order timeline rows.

## Files And Repos To Inspect Next

Executor should inspect before editing:

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/group_backlog_retention_notice.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/main.dart` for database migration/version and repository wiring only
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/bridge/bridge.go`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_list_screen_test.dart`
- `go-mknoon/node/group_inbox_test.go`
- `go-mknoon/bridge/bridge_test.go`

Likely new files:

- `lib/features/groups/domain/models/group_history_gap_repair.dart`
- `lib/features/groups/domain/repositories/group_history_gap_repair_repository.dart`
- `lib/features/groups/domain/repositories/group_history_gap_repair_repository_impl.dart`
- `lib/core/database/migrations/065_group_history_gap_repairs.dart`
- `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`
- focused tests for the new model/helper/repository/migration

If an existing local naming convention suggests a better filename during implementation, use that convention and record it in the plan execution progress.

## Existing Tests Covering This Area

- Drain/replay coverage:
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` covers cursor continuation, cursor timeout telemetry, first-page-only drains, retained/expired backlog boundaries, repeated-drain dedupe, and expired-page continuation.
  - `test/features/groups/integration/group_resume_recovery_test.dart` covers multi-page cursor drain, duplicate replay suppression, mixed-window retention, inbox recovery after partial delivery, and temporary partition replay followed by live delivery.
- UI coverage:
  - `test/features/groups/presentation/group_conversation_screen_test.dart` and `test/features/groups/presentation/group_list_screen_test.dart` cover expired and mixed-window backlog-retention notices.
- Go/bridge coverage:
  - `go-mknoon/node/group_inbox_test.go` covers relay cursor defaults, opaque cursor handling, distinct continuation requests, node-start guard, and encrypted relay envelope privacy.
  - `go-mknoon/bridge/bridge_test.go` covers `GroupInboxRetrieveCursor` exposure and input validation.

Coverage missing before this session:

- no direct test for a `historyGap` metadata contract on inbox/recovery
- no durable `group_history_gap_repairs` lifecycle test
- no multi-source repair-source selection/rejection test
- no range/head/hash validation test
- no proof that repaired envelopes re-enter the existing replay handler without duplicate/out-of-order rows
- no UI test for active/failed/repaired history repair state

## Regression/Tests To Add First

Add failing tests before or alongside implementation in this order:

1. Database/model:
   - `test/core/database/migrations/065_group_history_gap_repairs_test.dart`: migration creates the gap lifecycle table and indexes with required fields.
   - `test/core/database/helpers/group_history_gap_repairs_db_helpers_test.dart`: detected -> repairing -> repaired/failed lifecycle is durable and idempotent by `groupId + gapId`.
   - repository/model tests if the repo pattern requires a separate file.
2. Application repair:
   - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` add `PREREQ-HISTORY-GAP-REPAIR detects a history gap and repairs it from the first authorized matching source`.
   - Add `PREREQ-HISTORY-GAP-REPAIR rejects unauthorized or hash-mismatched sources and keeps the gap visible until another source repairs it`.
   - Add `PREREQ-HISTORY-GAP-REPAIR applies repaired envelopes through replay handling without duplicate or out-of-order rows`.
3. Integration:
   - `test/features/groups/integration/group_resume_recovery_test.dart` add a fake-network partition test where a cursor page reports a missing range, one candidate source is bad/incomplete, a second authorized source supplies a matching range, the repaired range appears in deterministic order, and post-heal live delivery still works.
4. UI:
   - `test/features/groups/presentation/group_conversation_screen_test.dart` add a test that renders active/failed/repaired gap state separately from backlog-retention notices.
   - Add `group_list_screen_test.dart` coverage only if the implemented UX exposes gap state in the list summary.
5. Bridge/Go:
   - `go-mknoon/node/group_inbox_test.go` add tests for the repair request/response structs or node helper validating group id, anchors/range, source peers, and hash fields.
   - `go-mknoon/bridge/bridge_test.go` add `GroupHistoryRepairRange` command exposure/input-validation tests.
   - `test/core/bridge/go_bridge_client_test.dart` or fake bridge tests if the Dart command map changes.

## Step-By-Step Implementation Plan

1. Add durable lifecycle primitives:
   - Add `GroupHistoryGapRepair` model with stable statuses such as `detected`, `repairing`, `repaired`, `failed`.
   - Include fields for `gapId`, `groupId`, range anchors or timestamp bounds, expected/observed head id, expected/observed range hash, candidate source peer ids, attempted source peer ids, repaired message ids, failure reason, and created/updated/repaired timestamps.
   - Add migration `065_group_history_gap_repairs.dart`, helper functions, repository interface/impl, fakes, and full migration-chain wiring.
2. Add bridge/app repair contract:
   - Extend `GroupInboxPage` or add a sibling typed result to carry optional `historyGap` metadata from inbox/recovery responses.
   - Add a Dart helper for `group:historyRepairRange` (or a repo-consistent command name) with typed request/response parsing.
   - Register the command in `go_bridge_client.dart`.
   - Add Go bridge/node request/response structs and input validation for group id, range anchors, candidate/source peer, limit, and range/head hash fields.
3. Add repair orchestration in the group recovery path:
   - When a drain page reports a gap, persist `detected`, then `repairing`.
   - Resolve authorized sources from current group members; reject non-members, removed members, empty source lists, and the local member when inappropriate.
   - Request candidate range repair from sources in deterministic order.
   - Validate response group/range/head, deterministic range hash over returned encrypted replay envelopes, source authorization, and completeness before applying.
   - If a source fails validation, record the attempt and keep trying the next authorized source.
   - If all sources fail, mark `failed` with a privacy-safe reason and keep the UI state visible.
4. Apply repaired messages through existing replay seams:
   - Extract or reuse the existing drain replay application logic so repaired envelopes call the same decode/listener/`handleIncomingGroupMessage` path as relay inbox replay.
   - Preserve existing message-id dedupe, ordering, removed-member cutoff, device/transport validation, event-log behavior, missing-key repair behavior, and media handling.
   - Mark the gap `repaired` only after all accepted repair messages are applied without bypassing normal validation.
5. Add UI truth:
   - Add a small view-state/notice model or screen input for current history repair state.
   - Render active repair and failed repair distinctly from backlog retention expiry.
   - Show repaired state only if existing UI patterns already keep resolved notices visible; otherwise record repaired state in tests/repository and omit persistent visual copy after repair.
6. Update docs only after verification:
   - If direct/gate proof passes, update OS-006 in the source matrix to `Covered`.
   - Update `test-inventory.md`, this plan execution results, breakdown current-session/ledger/ordered rows, and final program counts.
   - If any source row remains blocked, record exact blocker and do not claim `Covered`.

## Risks And Edge Cases

- Repair must not create a second replay path that skips signature, device, member, key epoch, removed-member cutoff, or event-log validation.
- Hash validation must be deterministic and independent of map key ordering.
- Duplicate candidate messages must not create duplicate rows or reorder quoted-message timelines.
- A bad first source must not clear the gap; a later good source may repair it.
- Unauthorized peers, removed members, stale group membership, dissolved groups, archived groups, and missing group keys must fail closed.
- Retention expiry and repair gaps are different states; a repair gap must not erase previously recorded expired-backlog truth.
- Repair of old messages outside the retention window must follow the existing retention policy unless the repair contract explicitly marks the range as retained and still within policy.
- Broad `lib/main.dart` analyzer state has known unrelated issues; targeted compile/analyze checks should isolate files touched by this session unless the session changes the affected constructor seam.

## Exact Tests And Gates To Run

Minimum direct commands after implementation:

- `flutter test --no-pub test/core/database/migrations/065_group_history_gap_repairs_test.dart test/core/database/helpers/group_history_gap_repairs_db_helpers_test.dart`
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name '1a. Fresh install path creates all tables with correct schema'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR'`
- Add `test/features/groups/presentation/group_list_screen_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR'` only if list summary UI changes.
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'history repair'` if Dart bridge command parsing changes.
- `cd go-mknoon && go test ./node ./bridge -run 'TestGroupHistoryRepair|TestGroupInbox.*HistoryGap|TestBridgeGroupHistoryRepair' -v`
- Targeted `dart analyze` over touched Dart production/test files, excluding known unrelated broad-main diagnostics unless this session changes those seams.
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

Optional supporting proof after host/fake-network proof is green:

- `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly`

Do not require the optional live gate for closure unless implementation adds behavior that cannot be honestly proven in host/fake-network tests.

## Known-Failure Interpretation

- Existing unrelated broad `dart analyze lib/main.dart` failures around pending-key-repair constructor wiring and broad-main unused/style diagnostics are not OS-006 regressions unless this session edits those exact seams.
- Existing historical docs that say `FLUTTER_DEVICE_ID` / `MKNOON_RELAY_ADDRESSES` were unset are stale for fixture availability only; the verified simulator/relay defaults do not close OS-006 by themselves.
- Any direct test failure in new history gap lifecycle, repair-source selection, range/hash validation, replay application, UI truth, or Go/bridge command exposure is blocking for this session.
- `groups`, `completeness-check`, and `git diff --check` failures are blocking unless independently proven unrelated and documented with exact evidence.

## Done Criteria

- Plan status moves to `qa_passed` only after Execution+QA accept the code/test/doc changes.
- OS-006 source matrix row is updated to `Covered` with file paths, direct tests, named gate outcomes, and caveats.
- `test-inventory.md` OS-006 entry records the new durable gap lifecycle, multi-source repair, hash validation, UI state, and test evidence.
- Breakdown current-session, ledger, ordered-session row 54, and final program counts are updated without moving unrelated rows.
- All required direct tests and named gates pass or any residual blocker is recorded as `blocked` without overclaiming.

## Scope Guard

Do not:

- claim OS-006 from relay cursor recovery, fake-network partition replay, or backlog retention notices alone
- implement a full MLS history service, server archive, remote storage product, or raw packet-capture proof
- bypass existing group replay/listener/message validation to insert repaired messages directly
- add a broad transport rewrite or new libp2p service beyond the minimal typed repair request/response seam needed for host/fake-network proof
- change invite, key-package, signed commit, receipt, secret-storage, or freshness behavior unless a compile seam requires a narrow adjustment
- erase or reinterpret existing backlog-retention timestamps as repair state

## Accepted Differences / Intentionally Out Of Scope

- Full MLS welcome/history semantics remain out of scope; this is a shipped architecture repair primitive for encrypted group replay envelopes.
- A permanent server-side historical archive remains out of scope. The closure target is authorized direct or multi-source repair of bounded gaps, plus durable local lifecycle state.
- Real relay/device proof is supporting only unless the implementation proves a host/fake-network blind spot.
- Packet capture, production push notification behavior, and Android paired-device proof are out of scope for this session.
- Existing key-repair queues remain future/missing-key repair, not history-gap repair; shared helper extraction is acceptable, merging the concepts is not.

## Dependency Impact

If this session closes successfully:

- OS-006 can move to `Covered`.
- TP-SMOKE-04 can cite actual gap repair evidence rather than relay cursor recovery only.
- Later `PREREQ-GROUP-SYNC-RECEIPTS` can rely on a concrete gap lifecycle pattern but still owns durable cursor/receipt transaction semantics separately.
- Later `PREREQ-REMOTE-EVENT-FAMILIES` remains responsible for unmodeled bans/deletes/receipts/replay families and should not inherit OS-006 closure automatically.

If this session blocks:

- Keep OS-006 `Partial`.
- Record whether the blocker is implementation-owned, external-fixture-only, or product-scope.
- Continue to later independent prerequisites only if the blocker does not prevent safe progress.

## Reviewer Findings

### Verdict

Sufficient with only incremental implementation details. The draft is safe to send to Arbiter and then Executor without replanning. Status is advanced to `reviewer-pass`.

### Mandatory Section Check

- Present and sufficient: Real Scope, Closure Bar, Source Of Truth, Session Classification, Exact Problem Statement, Files And Repos To Inspect Next, Existing Tests Covering This Area, Regression/Tests To Add First, Step-By-Step Implementation Plan, Risks And Edge Cases, Exact Tests And Gates To Run, Known-Failure Interpretation, Done Criteria, Scope Guard, Accepted Differences / Intentionally Out Of Scope, and Dependency Impact.
- The session classification `implementation-ready` is supported by the source row and breakdown: OS-006 is a repo-owned code/test gap, not an external fixture wait.
- The source-of-truth hierarchy is correct: OS-006 source matrix and row 54 in the session breakdown define scope; gate definitions/script define named gates; code/tests beat stale prose.

### Structural Blocker Review

- Wrong scope: none. The source row explicitly requires direct/multi-peer range/head/hash repair, durable gap lifecycle state, multi-source selection, and repair-clearance proof; the plan targets those items and avoids claiming relay cursor recovery as closure.
- Overengineering: none blocking. The draft names a minimal first-class repair seam and explicitly excludes MLS history service, server archive, raw packet capture, broad transport rewrite, and unrelated invite/key/receipt/freshness changes.
- Under-scoped closure bar: none. Closure requires durable DB reopen survival, multi-source rejection/fallback, replay through existing validation/dedupe, UI truth, Go/bridge exposure, named gates, and source-doc evidence before `Covered`.
- Missing durable DB/migration/test requirements: none. The plan requires a dedicated lifecycle model/repository/helper/migration, migration tests, helper/reopen durability tests, full migration-chain proof, and source-doc evidence.
- Missing bridge/Go coverage: none. The plan requires Dart bridge helper/command registration, Go node/bridge request/response validation, Go tests, and Dart bridge tests when the command map changes.
- Hidden reliance on live fixtures: none. Host/fake-network proof is primary; `group-real-network-nightly` is supporting only unless implementation creates a host/fake-network blind spot.
- Risk of bypassing existing validation/dedupe: addressed. The implementation plan requires repaired envelopes to flow through existing replay/listener handling and blocks direct insertion that skips signature/device/member/key epoch/removed-member/event-log validation.
- Missing source-doc closure steps: none. The plan requires source matrix, test inventory, this plan, breakdown ledger/current-session/ordered row, and final counts updates only after direct/gate proof.
- Missing stop rule: acceptable. The plan says to keep OS-006 `Partial`, record exact blockers, and not claim `Covered` when direct/gate/source-row proof is absent. Executor should preserve that stop behavior if evidence shows the minimal repair seam cannot close OS-006 without product-scope work.

### Incremental Details For Arbiter/Executor

- Recheck migration numbering immediately before editing. Current repo state has `064_group_welcome_key_package_tombstones` and `lib/main.dart` version `64`, so `065_group_history_gap_repairs` is plausible now, but the dirty worktree can change before execution.
- Treat the Dart bridge command test as effectively required if `go_bridge_client.dart` or bridge parsing changes; the draft already names this condition.
- Keep "repaired" UI visibility aligned with existing UX patterns as the plan says: persistent UI copy is not required after repair if the durable repository/test evidence records the repaired state.

### Minimum Needed To Make Sufficient

No blocking edit is needed. The above incremental details can be preserved by Arbiter as non-structural notes.

## Arbiter Decision

### Verdict

Execution-ready. No structural blocker remains, and no content patch is required before implementation. This arbiter update only records the decision and advances status.

### Structural Blockers

None.

The reviewed plan already has the required scope, closure bar, regression-first test contract, gate contract, source-of-truth hierarchy, stop rule, and source-doc closure requirements. It also blocks OS-006 from moving to `Covered` until implementation has concrete direct/gate evidence.

### Incremental Details Deferred To Executor

- Recheck migration numbering immediately before creating migration files. `065_group_history_gap_repairs` is plausible from the inspected state, but the dirty worktree can change.
- Treat the Dart bridge command-map/parsing test as required if implementation changes `go_bridge_client.dart`, `bridge_group_helpers.dart`, or equivalent Dart bridge parsing.
- Keep repaired-state UI visibility aligned with existing UX patterns. Durable repository/test evidence may prove `repaired` without requiring persistent resolved notice copy if existing surfaces normally hide resolved notices.

### Accepted Differences

- Host/fake-network proof remains the primary closure surface; live device/relay proof is optional supporting evidence unless implementation creates a blind spot that only the live fixture can prove.
- The repair target is a bounded encrypted replay-envelope gap repair primitive, not full MLS history semantics, a permanent server archive, packet capture proof, or Android paired-device coverage.
- Existing missing-key repair queues remain separate from history-gap repair. Shared helper extraction is acceptable, but merging key-repair and history-gap concepts is intentionally out of scope.

### Safe-To-Implement Rationale

The plan is safe to hand to Executor because it constrains the session to OS-006's direct/multi-peer history repair gap, requires failing direct tests before or alongside implementation, preserves existing replay/listener validation and dedupe paths, requires durable lifecycle and bridge/Go proof, and keeps source documentation updates gated on passing evidence. Incremental details are execution-time checks, not plan sufficiency gaps.

## Execution Progress

| timestamp | phase | files inspected or touched | decision/blocker | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T20:36:07+02:00 | Final QA accepted | Final QA inspected production relay/Go/Dart gap metadata and repair-range seams, Flutter drain repair lifecycle, UI repair-state truth, and source docs; reran focused drain PREREQ (`+3`), bridge helper cursor parsing (`+4`), Go relay inbox auth/cursor-gap/repair-range tests, Go node/bridge history repair/cursor tests, and `git diff --check` | No blocking findings. Source matrix and inventory OS-006 rows are consistent as `Covered`; breakdown row 54 moved to `accepted` / `qa_passed`. Live device/relay proof remains supporting only because no host/fake-network blind spot was found. | Run closure write/review and continue to `PREREQ-GROUP-SYNC-RECEIPTS`. |
| 2026-05-01T20:30:00+02:00 | Fix-pass verification recovery completed | `go-relay-server/backend_memory.go`; `go-relay-server/backend_redis.go`; `go-relay-server/group_inbox_store.go`; `go-relay-server/inbox.go`; `go-relay-server/inbox_test.go`; `go-mknoon/node/group_inbox.go`; `go-mknoon/node/group_inbox_test.go`; `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go`; `lib/core/bridge/bridge_group_helpers.dart`; `test/core/bridge/bridge_group_helpers_test.dart`; `test/core/bridge/go_bridge_client_test.dart`; OS-006 source matrix, inventory, and breakdown docs | QA blockers are addressed and focused evidence is green. Production relay cursor retrieval now returns authorized history-gap metadata, stale-cursor repair ranges, and `group_history_repair_range`; Go node/bridge and Dart helper surfaces preserve the metadata and repair-range response. Verification passed: bridge helper cursor history-gap parsing (`+4`), migration/helper (`+4`), drain PREREQ (`+3`), fake-network resume PREREQ (`+1`), conversation UI PREREQ (`+1`), full-chain fresh install proof (`+1`), Dart bridge history repair (`+1`), retry inbox stores (`+10`), Go node/bridge history gap/repair regex, `go-relay-server go test ./...`, targeted analyzer exit 0 with only info diagnostics, `groups` (`+102`), `completeness-check` (`708/708`), and `git diff --check`. Source docs now consistently present OS-006 as `Covered` pending final QA acceptance. | Spawn isolated final QA reviewer for PREREQ-HISTORY-GAP-REPAIR. |
| 2026-05-01T20:17:20+02:00 | Fix-pass verification recovery started | Fix-pass child touched relay, Go node/bridge, Dart bridge parsing, and docs but did not return a final handoff after bounded waits | Closed no-progress fix-pass child after visible assigned-scope edits. Controller will inspect the landed diff, run focused tests, repair only concrete OS-006 blocker regressions if present, and then spawn final QA if evidence is sufficient. | Inspect fix-pass diff and run focused tests. |
| 2026-05-01T20:09:36+02:00 | QA Reviewer blocked | `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `go-mknoon/node/group_inbox.go`; `go-mknoon/bridge/bridge.go`; `go-relay-server/group_inbox_store.go`; OS-006 source matrix, inventory, and breakdown rows | Blocking issues: production gap metadata is not carried from relay/Go bridge into Dart pages; production `GroupHistoryRepairRange` validates but always returns `group history repair transport unavailable`; source docs are inconsistent because the matrix says `Covered` while inventory/breakdown still record old `Partial` blockers. | Spawn one bounded Executor fix pass for production gap metadata, production repair-range retrieval, and doc consistency; then run final QA. |
| 2026-05-01T20:04:57+02:00 | Controller verification recovery completed | `lib/core/database/migrations/065_group_history_gap_repairs.dart`; `lib/core/database/helpers/group_history_gap_repairs_db_helpers.dart`; `lib/features/groups/domain/models/group_history_gap_repair.dart`; `lib/features/groups/domain/repositories/group_history_gap_repair_repository*.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/core/bridge/bridge_group_helpers.dart`; `lib/core/bridge/go_bridge_client.dart`; `lib/features/groups/presentation/group_backlog_retention_notice.dart`; `lib/features/groups/presentation/screens/group_conversation_screen.dart`; `lib/main.dart`; `go-mknoon/node/group_inbox.go`; `go-mknoon/bridge/bridge.go`; `go-relay-server/*`; focused tests and source docs | Landed implementation is coherent after controller-side verification. Direct evidence passed: migration/helper tests (`+4`), focused drain PREREQ tests (`+3`), fake-network resume PREREQ test (`+1`), conversation UI PREREQ test (`+1`), Dart bridge history repair test (`+1`), focused full-chain migration proof (`+1`), retry inbox store suite (`+10`), Go node/bridge history repair regex, `go-relay-server go test ./...`, targeted analyzer over touched Dart files with only existing informational diagnostics, `./scripts/run_test_gates.sh groups` (`+102`), `./scripts/run_test_gates.sh completeness-check` (`708/708`), `dart format`, `gofmt`, and `git diff --check`. Source OS-006 docs are provisionally updated to `Covered`; QA must still accept before closure stands. | Spawn isolated QA reviewer for PREREQ-HISTORY-GAP-REPAIR. |
| 2026-05-01T19:59:54+02:00 | Controller verification recovery started | Executor child left code/test changes but no final handoff; plan file still had only `Executor started`; active test process ended without recorded results | Closed no-progress Executor child after substantial partial landing. Controller will inspect the diff, run required validations, repair only blocking issues inside this session scope, and then spawn QA if the landing is coherent. | Inspect landed diff and run focused required tests. |
| 2026-05-01T19:33:27+02:00 | Executor started | This plan; `git status --short`; migration/helper/repository patterns; drain, bridge, UI, Go bridge/node entry files | Contract extracted. Worktree is intentionally dirty from prior sessions. Migration recheck shows latest local migration remains `064_group_welcome_key_package_tombstones`, so `065_group_history_gap_repairs` is valid. | Add history gap lifecycle primitives, bridge seam, drain repair orchestration, UI truth, focused tests, then run required gates. |
