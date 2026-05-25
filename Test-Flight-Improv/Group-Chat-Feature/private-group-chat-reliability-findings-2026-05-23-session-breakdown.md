# Private Group Chat Reliability Findings Session Breakdown

Decomposition artifact created: 2026-05-23

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`

Downstream execution path: use `$implementation-session-pipeline-orchestrator` for each runnable session. Planning, execution, and closure are session-scoped. The user explicitly requested multi-agent orchestration to speed up this rollout; sessions may run in parallel only when write sets are disjoint and the controller can verify the on-disk result before final acceptance.

## Run Mode Snapshot

- Refreshed: 2026-05-23T23:08:09+02:00.
- Active mode: `implementation-committed gap-closure`.
- Degraded local continuation explicitly allowed: no.
- Source proposal/matrix/closure doc: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`.
- Source status vocabulary: `Open`, `Closed`, `Skipped`, `Blocked`.
- Overall closure bar: every `Open` row in the source matrix is either `Closed` with concrete code and focused test evidence or `Blocked` with an exact blocker. Rows marked `Skipped` must retain concrete current-code evidence explaining why implementation is not meaningful in this rollout.
- Final verdict policy: persist exactly one of `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; use `closed` only when every non-skipped row is `Closed`.

## Controller Progress

- 2026-05-23T23:08:09+02:00: Controller completed critical read-only triage with local inspection and parallel explorer agents. Rows `PGC-003` and `PGC-017` are skipped with evidence; all other rows remain implementation-owned. Next action is session planning/execution for disjoint runnable groups.
- 2026-05-24T00:23:00+02:00: Controller completed multi-agent implementation for all runnable sessions. Rows `PGC-001`, `PGC-002`, `PGC-004` through `PGC-016`, and `PGC-018` now have row-focused code/test evidence. Rows `PGC-003` and `PGC-017` remain skipped with current-code evidence. Broad groups/completeness/Go gates retain explicit dirty-tree follow-up items listed below.

## Recommended Plan Count

Recommended plan count: `8`

The 16 implementation-owned rows are grouped by owner files to keep patches coherent and avoid overlapping parallel write sets:

1. `PGC-DRAIN-1`: rows `PGC-001`, `PGC-002`, `PGC-014`, `PGC-016`
2. `PGC-DB-1`: rows `PGC-004`, `PGC-005`, `PGC-006`
3. `PGC-INCOMING-1`: row `PGC-007`
4. `PGC-LISTENER-1`: rows `PGC-008`, `PGC-009`, `PGC-018`
5. `PGC-SEND-1`: row `PGC-010`
6. `PGC-GO-NODE-1`: rows `PGC-011`, `PGC-012`
7. `PGC-KEYS-1`: row `PGC-013`
8. `PGC-RELAY-1`: row `PGC-015`

## Overall Closure Bar

The rollout is complete when:

- Source matrix rows `PGC-001`, `PGC-002`, `PGC-004` through `PGC-016`, and `PGC-018` are `Closed` or truthfully `Blocked`.
- Source matrix rows `PGC-003` and `PGC-017` remain `Skipped` with concrete evidence.
- Every accepted implementation session has an adjacent execution-safe plan, focused regression evidence, and a passing focused test or exact blocker.
- `git diff --check` passes after all accepted implementation sessions.
- Existing unrelated dirty-worktree changes are not reverted or overwritten.

## Source Of Truth

Primary source matrix:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`

Regression and gate docs:

- `Test-Flight-Improv/test-gates-reference.md`
- `test/core/database/integration/full_migration_chain_test.dart`

## Session Ledger

| Session ID | Rows | Title | Classification | Plan File | Depends On | Status | Execution Verdict | Closure Docs Touched | Blocker Class | Note |
|---|---|---|---|---|---|---|---|---|---|---|
| `PGC-DRAIN-1` | `PGC-001`, `PGC-002`, `PGC-014`, `PGC-016` | Offline drain sender, receipt, reaction, and concurrency hardening | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-DRAIN-1-plan.md` | None | `accepted_with_explicit_follow_up` | Focused PGC selectors passed; full drain file red | Source matrix rows `PGC-001`, `PGC-002`, `PGC-014`, `PGC-016`; this ledger | `residual_direct_suite_failure` | Row-focused fixes landed. Full `drain_group_offline_inbox_use_case_test.dart` still has 19 broader failures, recorded in the plan and treated as residual follow-up. |
| `PGC-DB-1` | `PGC-004`, `PGC-005`, `PGC-006` | Message repository and DB helper data-integrity hardening | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-DB-1-plan.md` | None | `accepted_with_explicit_follow_up` | Accepted; owner suites passed | Source matrix rows `PGC-004`, `PGC-005`, `PGC-006`; this ledger | `residual_groups_gate_failure` | Focused selectors, preservation selectors, and three owner suites passed. Broad groups gate remains red on unrelated dirty-tree failures. |
| `PGC-INCOMING-1` | `PGC-007` | Stable-message-ID dedupe precedence | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-INCOMING-1-plan.md` | None | `accepted_with_explicit_follow_up` | Accepted; focused handler file passed | Source matrix row `PGC-007`; this ledger | `residual_groups_gate_failure` | `PGC-007` normal/event-log selectors, preservation selectors, analyzer/format, and focused handler file passed. Broad groups gate remains unrelated follow-up. |
| `PGC-LISTENER-1` | `PGC-008`, `PGC-009`, `PGC-018` | Listener shutdown, durable membership-dependent buffering, and system no-bridge guard | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-LISTENER-1-plan.md` | None | `accepted_with_explicit_follow_up` | Accepted; scoped compile/tests green | Source matrix rows `PGC-008`, `PGC-009`, `PGC-018`; this ledger | `residual_groups_and_completeness_gate_failure` | PGC-009 durable storage was coherent and implemented. Focused listener tests, full listener file, new DB tests, full migration chain, scoped analyze/format, and diff checks passed. |
| `PGC-SEND-1` | `PGC-010` | Live-publish status separated from inbox custody retry | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-SEND-1-plan.md` | `PGC-DB-1` | `accepted_with_explicit_follow_up` | Accepted; PGC-010 selectors passed | Source matrix row `PGC-010`; this ledger | `residual_send_suite_and_groups_gate_failure` | PGC-010 selectors, preservation selectors, retry selector, scoped analyze/format, and diff checks passed. Full send suite has two unrelated dirty-tree failures. |
| `PGC-GO-NODE-1` | `PGC-011`, `PGC-012` | Go outbound author/device validation and join/leave mutex narrowing | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-GO-NODE-1-plan.md` | None | `accepted_with_explicit_follow_up` | Accepted; focused Go selectors passed | Source matrix rows `PGC-011`, `PGC-012`; this ledger | `residual_go_node_gate_failure` | Direct PGC-011/012 and focused Go safety tests passed. Broad `go test ./node` remains red on unrelated `TestGroupInboxRetrieveCursor_DefaultsLimitWhenZero`. |
| `PGC-KEYS-1` | `PGC-013` | Retain group keys for offline replay backlog | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-KEYS-1-plan.md` | None | `accepted_with_explicit_follow_up` | Accepted; focused key-retention evidence passed | Source matrix row `PGC-013`; this ledger | `residual_direct_drain_suite_failure` | Shared 8-generation retention policy landed. PGC-013 repository/drain selectors, future-key repair, key update selectors, full repository file, format, and diff checks passed. Full drain file remains red from broader residuals. |
| `PGC-RELAY-1` | `PGC-015` | Make group inbox recipient ACL mandatory in relay backend contract | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-RELAY-1-plan.md` | None | `accepted` | Accepted; full relay module passed | Source matrix row `PGC-015`; this ledger | None | Backend-contract RED proof, focused ACL selectors, broader group inbox slice, `cd go-relay-server && go test ./... -count=1`, and diff checks passed. |
| `PGC-SKIP-003` | `PGC-003` | Uploaded migration bundle mismatch current repo evidence | `stale/already-covered` | None | None | `stale/already-covered` | Not run | Source matrix row `PGC-003` | None | Current repo has later migrations and full-chain coverage; no implementation needed. |
| `PGC-SKIP-017` | `PGC-017` | Envelope AAD/header binding hardening deferred as protocol migration | `stale/already-covered` | None | None | `stale/already-covered` | Not run | Source matrix row `PGC-017` | None | Valid hardening, but not a safe narrow reliability patch; split into dedicated versioned-envelope rollout if desired. |

## Final Program Verdict

Final verdict: `accepted_with_explicit_follow_up`.

What is closed:

- Matrix rows `PGC-001`, `PGC-002`, `PGC-004` through `PGC-016`, and `PGC-018` are `Closed` with row-focused code and regression evidence.
- Matrix rows `PGC-003` and `PGC-017` remain `Skipped` because current repo evidence makes them obsolete for this rollout or too broad for a safe reliability patch.

Explicit follow-up, not row blockers:

- `drain_group_offline_inbox_use_case_test.dart` still has 19 broader residual failures after the PGC drain/key selectors pass. Exact examples recorded in the PGC-DRAIN and PGC-KEYS plan notes include `GE-018`, `ML-008`, `GI-018`, `GI-021`, `GK-024`, `GI-024`, `GEK004`, and `GI-017`.
- `./scripts/run_test_gates.sh groups` remains red in the dirty tree across unrelated group integration rows, including previously recorded `BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `DE-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and `GM-028`, plus later listener/send-run residuals.
- `./scripts/run_test_gates.sh completeness-check` remains red because `test/shared/fakes/fake_group_pubsub_network_test.dart` and `test/shared/fakes/seeded_group_reproduction_log_test.dart` are unmatched in the current test map.
- `cd go-mknoon && go test ./node` and `cd go-mknoon && go test ./...` remain red on unrelated `TestGroupInboxRetrieveCursor_DefaultsLimitWhenZero`.

Maintenance rule:

- Reopen a closed PGC row only if a focused selector for that row regresses or new evidence shows the row-owned behavior is still wrong.
- Track the explicit follow-up failures as separate gate/test-map cleanup, not as reopened private-group reliability findings unless focused repro ties one back to a closed row.

## Ordered Session Breakdown

### Session `PGC-DRAIN-1`: Offline Drain Sender, Receipt, Reaction, And Concurrency Hardening

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-DRAIN-1-plan.md`

Dependency on earlier sessions: none.

Exact scope: fix offline drain system replay to pass logical `senderId` and separate `transportPeerId`; bind or drop replay payload receipts so a sender cannot forge other members' receipts; prevent `group_reaction` payloads from falling into message handling when `reactionRepo` is absent; bound `drainGroupOfflineInbox` group concurrency.

Likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`.

Likely direct tests/regressions: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` focused selectors for logical sender replay, forged receipts, missing reaction repo, and bounded concurrency.

Likely named gates: focused Flutter test selectors; `dart format`; `git diff --check`.

Matrix/closure docs to update when done: rows `PGC-001`, `PGC-002`, `PGC-014`, `PGC-016`; this breakdown ledger.

### Session `PGC-DB-1`: Message Repository And DB Helper Data-Integrity Hardening

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-DB-1-plan.md`

Dependency on earlier sessions: none.

Exact scope: make missing inbox page transaction helper fail fast; make `dbLoadGroupMessage` rethrow database errors; replace destructive `ConflictAlgorithm.replace` with scoped insert/update behavior that preserves incoming operational fields while retaining intentional outgoing state transitions.

Likely code-entry files: `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`.

Likely direct tests/regressions: focused repository tests, `test/core/database/helpers/group_messages_db_helpers_*`, and incoming/self-echo regressions if needed.

Likely named gates: focused Flutter/Dart tests; `dart format`; `git diff --check`.

Matrix/closure docs to update when done: rows `PGC-004`, `PGC-005`, `PGC-006`; this breakdown ledger.

### Session `PGC-INCOMING-1`: Stable-Message-ID Dedupe Precedence

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-INCOMING-1-plan.md`

Dependency on earlier sessions: none.

Exact scope: run content-based dedupe only when no stable wire `messageId` exists; keep existing duplicate-by-id, conflict, self-echo, and repair-placeholder behavior unchanged.

Likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`.

Likely direct tests/regressions: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` focused selectors for same content/same timestamp with unique IDs and legacy no-ID dedupe.

Likely named gates: focused Flutter/Dart tests; `dart format`; `git diff --check`.

Matrix/closure docs to update when done: row `PGC-007`; this breakdown ledger.

### Session `PGC-LISTENER-1`: Listener Shutdown, Durable Membership Buffering, And System No-Bridge Guard

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-LISTENER-1-plan.md`

Dependency on earlier sessions: none.

Exact scope: guard controller writes and make shutdown awaitable where callers can use it; never persist system JSON as visible chat when bridge is missing; implement durable pending membership-dependent message storage or record an exact scoped blocker for `PGC-009`.

Likely code-entry files: `lib/features/groups/application/group_message_listener.dart`, plus adjacent pending-membership repository/helper/migration files only if durable buffering is implemented.

Likely direct tests/regressions: `test/features/groups/application/group_message_listener_test.dart`; migration/helper tests if durable storage is added.

Likely named gates: focused Flutter/Dart tests; `dart format`; `git diff --check`.

Matrix/closure docs to update when done: rows `PGC-008`, `PGC-009`, `PGC-018`; this breakdown ledger.

### Session `PGC-SEND-1`: Live-Publish Status Separated From Inbox Custody Retry

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-SEND-1-plan.md`

Dependency on earlier sessions: `PGC-DB-1`.

Exact scope: when publish succeeds with topic peers, persist visible message status `sent`; keep `inboxStored=false` and `inboxRetryPayload` for retry when inbox store fails or is unknown. Preserve zero-peer/inbox-failure failure behavior and durable inbox success behavior.

Likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`.

Likely direct tests/regressions: `test/features/groups/application/send_group_message_use_case_test.dart` focused send matrix selectors.

Likely named gates: focused Flutter/Dart tests; `dart format`; `git diff --check`.

Matrix/closure docs to update when done: row `PGC-010`; this breakdown ledger.

### Session `PGC-GO-NODE-1`: Go Outbound Author/Device Validation And Join/Leave Mutex Narrowing

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-GO-NODE-1-plan.md`

Dependency on earlier sessions: none.

Exact scope: add outbound author/device preflight for group message, reliable send, and reaction publish before local publish or inbox store; narrow `JoinGroupTopic` and `LeaveGroupTopic` mutex hold time so pubsub network operations do not run under `n.mu`.

Likely code-entry files: `go-mknoon/node/pubsub.go`.

Likely direct tests/regressions: focused Go node pubsub tests for invalid outbound device metadata and join/leave hook deadlock safety.

Likely named gates: focused `go test ./node -run ...`; `gofmt`; `git diff --check`.

Matrix/closure docs to update when done: rows `PGC-011`, `PGC-012`; this breakdown ledger.

### Session `PGC-KEYS-1`: Retain Group Keys For Offline Replay Backlog

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-KEYS-1-plan.md`

Dependency on earlier sessions: none.

Exact scope: replace latest-plus-previous Dart key pruning/stale replay policy with a bounded retention window that covers multiple offline rotations without unbounded key growth. Do not delete keys referenced by pending repair/undecryptable replay evidence if current repositories expose that horizon.

Likely code-entry files: `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, test fakes.

Likely direct tests/regressions: group repository key retention tests and offline replay stale-epoch tests.

Likely named gates: focused Flutter/Dart tests; `dart format`; `git diff --check`.

Matrix/closure docs to update when done: row `PGC-013`; this breakdown ledger.

### Session `PGC-RELAY-1`: Make Group Inbox Recipient ACL Mandatory In Relay Backend Contract

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-PGC-RELAY-1-plan.md`

Dependency on earlier sessions: none.

Exact scope: remove optional recipient ACL fallback from relay group inbox storage; ensure custom `GroupInboxBackend` implementations must support recipient-scoped store and authorized retrieve continues deriving requester from authenticated stream peer.

Likely code-entry files: `go-relay-server/group_inbox_store.go`, `go-relay-server/inbox.go`, memory/Redis backend tests if compile requires.

Likely direct tests/regressions: focused relay tests for custom backend requiring recipient ACL and authorized retrieve; existing `go test ./... -run 'GroupInbox|Inbox'` slice as feasible.

Likely named gates: focused `go test` in `go-relay-server`; `gofmt`; `git diff --check`.

Matrix/closure docs to update when done: row `PGC-015`; this breakdown ledger.
