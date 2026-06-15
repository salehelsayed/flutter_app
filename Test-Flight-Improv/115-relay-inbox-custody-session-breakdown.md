# 115 Relay Inbox Custody Session Breakdown

Status: reusable breakdown

Source doc: `Test-Flight-Improv/115-relay-inbox-custody.md`

Intended breakdown artifact:
`Test-Flight-Improv/115-relay-inbox-custody-session-breakdown.md`

## Recommended Plan Count

Create and execute **3 new session plans** for the remaining work:

- `115-P3` Flutter sender custody sweep and retry truthfulness
- `115-P4` relay, Go client, bridge, and binding protocol work
- `115-P5` whole-system acceptance, gate capture, deploy evidence, and closure

The ledger also keeps `115-P1` and `115-P2` as
`stale/already-covered` rows because the source doc records both phases as
host-closed on 2026-06-13 and the current tree confirms the main production
symbols. They do not need downstream execution unless later source evidence
proves the closure log stale.

## Decomposition Artifact

- Artifact path:
  `Test-Flight-Improv/115-relay-inbox-custody-session-breakdown.md`
- Proposal or source doc path:
  `Test-Flight-Improv/115-relay-inbox-custody.md`
- Downstream workflow rule:
  detailed planning happens one session at a time; later sessions must be
  refreshed against landed code before execution.
- Doc-scoped plan naming:
  every intended plan path derives from
  `Test-Flight-Improv/115-relay-inbox-custody.md` as
  `Test-Flight-Improv/115-relay-inbox-custody-session-<session-id>-plan.md`.

## Overall Closure Bar

Relay-inbox custody must never appear as receiver-visible delivery until the
receiver confirms it. After all remaining sessions close:

- sender rows accepted by the relay inbox remain non-terminal `inboxed` until
  a receipt or other durable receiver confirmation arrives;
- unconfirmed `inboxed` rows are periodically re-stored or truthfully surfaced
  as non-delivered `sent`, with retained envelopes and monotonic status
  transitions;
- the relay rejects new stores at capacity instead of silently evicting older
  accepted entries, exposes typed `INBOX_FULL` and expiry metadata, and releases
  dedup IDs on TTL prune and ack-delete;
- end-to-end cap, TTL, lost-receipt, and deployment evidence is attached to the
  source doc closure record;
- `Test-Flight-Improv/test-gate-definitions.md` and
  `scripts/run_test_gates.sh` classify every new doc-115 test and keep
  completeness-check green.

## Source Of Truth

- Graph-first evidence from `graphify-arch` exact-symbol queries:
  `relay inbox custody`, `inboxed status`, `delivery receipts`,
  `verify custody`, `relay inbox store`, `custodyCheckedAt`,
  `dbLoadInboxCustodyOutgoingMessages`, `storeInInboxDetailed`,
  `verifyInboxCustody`, and `InboxStoreOutcome`.
- Source intent and closure state:
  `Test-Flight-Improv/115-relay-inbox-custody.md`.
- Regression strategy:
  `Test-Flight-Improv/14-regression-test-strategy.md`.
- Gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md` and
  `scripts/run_test_gates.sh`.
- Current code and tests directly confirmed with `rg`:
  `lib/features/conversation/domain/models/conversation_message.dart`,
  `lib/features/conversation/application/send_chat_message_use_case.dart`,
  `lib/features/conversation/application/delete_message_use_case.dart`,
  `lib/features/conversation/application/send_delivery_receipt_use_case.dart`,
  `lib/features/conversation/application/handle_delivery_receipt_use_case.dart`,
  `lib/features/conversation/application/delivery_receipt_listener.dart`,
  `lib/core/services/incoming_message_router.dart`,
  `test/features/conversation/application/verify_inbox_custody_use_case_test.dart`,
  `test/core/database/helpers/messages_db_helpers_test.dart`,
  `lib/features/conversation/application/retry_unacked_messages_use_case.dart`,
  `go-relay-server/inbox.go`,
  `go-relay-server/limits.go`,
  `go-relay-server/backend_redis_test.go`,
  `go-relay-server/inbox_dedup_test.go`,
  `go-relay-server/metrics_test.go`,
  and `go-mknoon/integration/relay_test.go`.
- Cross-doc prerequisite:
  `Test-Flight-Improv/116-edit-retry-fidelity.md` now records Phase 1 and
  Phase 2 as host-closed; current code confirms
  `deriveRetryAction(ConversationMessage)` exists in
  `retry_failed_messages_use_case.dart`. That satisfies the hard prerequisite
  for `115-P3`.

## Run Mode Snapshot

- Refreshed: 2026-06-13T10:13:42Z.
- Active mode: `standard`.
- Degraded local continuation explicitly allowed: no.
- Source proposal / matrix / closure doc path:
  `Test-Flight-Improv/115-relay-inbox-custody.md`.
- Source row/status vocabulary:
  `CLOSED`, `accepted`, `residual_only`, and archived residual lab evidence.
  `Open`, `Partial`, and `Contract-undefined` would be unresolved if present.
- Overall closure bar:
  host implementation must preserve non-terminal relay custody, custody sweep
  repair/truthful surfacing, typed relay reject-new behavior, gate capture, and
  explicit treatment of external deploy/device/TestFlight evidence.
- Final verdict policy for this run:
  use `closed` only if no meaningful deferred work remains; use
  `accepted_with_explicit_follow_up` when host code/gates are accepted and the
  remaining work is explicit external release evidence; use `residual_only`
  only for one narrow residual; use `still_open` if any required session is
  blocked or the source doc still has unresolved implementation rows.

## Session Ledger

| Session id | Title | Classification | Intended plan file | Depends on | Initial status |
|---|---|---|---|---|---|
| `115-P1` | Sender status foundation: `inboxed`, custody columns, UI mapping | `stale/already-covered` | `Test-Flight-Improv/115-relay-inbox-custody-session-115-P1-plan.md` | none | `stale/already-covered` |
| `115-P2` | Delivery receipts: receiver emits, sender consumes, receipt listener | `stale/already-covered` | `Test-Flight-Improv/115-relay-inbox-custody-session-115-P2-plan.md` | `115-P1`, 116 P1-P2 | `stale/already-covered` |
| `115-P3` | Flutter custody sweep, retry-unacked truthfulness, detailed outcome plumbing | `implemented` | `Test-Flight-Improv/115-relay-inbox-custody-session-115-P3-plan.md` | `115-P1`, `115-P2`, 116 P1-P2 | `accepted/closed 2026-06-13` |
| `115-P4` | Relay protocol, Go client, bridge, bindings, reject-new and TTL observability | `implemented` | `Test-Flight-Improv/115-relay-inbox-custody-session-115-P4-plan.md` | `115-P3` for app-side consumer contract | `accepted 2026-06-13` |
| `115-P5` | Whole-system acceptance, gate capture, deploy and closure evidence | `implemented` | `Test-Flight-Improv/115-relay-inbox-custody-session-115-P5-plan.md` | `115-P3`, `115-P4` | `residual_only 2026-06-13`; prod relay deployed, device/TestFlight lab proof unclaimed |

## Ordered Session Breakdown

### `115-P1` Sender Status Foundation

- Session classification: `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/115-relay-inbox-custody-session-115-P1-plan.md`
- Exact scope:
  status `inboxed`, migration 077 custody columns, `ConversationMessage`
  custody fields, sender and deletion inbox branches retaining envelopes,
  letter card pending-family mapping, and delivered-status invariant updates.
- Why it is its own session:
  this was the load-bearing shared status model for docs 114, 115, and 116.
- Likely code-entry files:
  `send_chat_message_use_case.dart`, `delete_message_use_case.dart`,
  `conversation_message.dart`, `077_message_relay_custody.dart`,
  `messages_db_helpers.dart`, `letter_card.dart`, and `conversation_wired.dart`.
- Likely direct tests/regressions:
  send custody, delete custody, migration 077, message helper roundtrip,
  letter card, and delivered-status minting tests.
- Likely named gates:
  `./scripts/run_test_gates.sh 1to1`, `baseline`, and
  `completeness-check`.
- Matrix/closure docs to update when done:
  already recorded in the source doc closure log.
- Dependency:
  none.
- Current evidence:
  the source doc records Phase 1 closed; current code and tests contain
  `persistInboxAccepted`, `relayExpiresAt`, `custodyCheckedAt`,
  `077_message_relay_custody.dart`, and `inboxed` UI/test references.

### `115-P2` Delivery Receipts

- Session classification: `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/115-relay-inbox-custody-session-115-P2-plan.md`
- Exact scope:
  route `delivery_receipt` envelopes, send plaintext v1 receipts, consume
  receipts with monotonic `inboxed` or `sent` to `delivered` transitions,
  wire chat and deletion receipt hooks, and preserve origin discrimination.
- Why it is its own session:
  it changes app-layer receipt semantics and listener routing without requiring
  relay protocol changes.
- Likely code-entry files:
  `incoming_message_router.dart`, `send_delivery_receipt_use_case.dart`,
  `handle_delivery_receipt_use_case.dart`, `delivery_receipt_listener.dart`,
  `handle_incoming_chat_message_use_case.dart`,
  `handle_incoming_message_deletion_use_case.dart`, listener wiring, and
  `main.dart`.
- Likely direct tests/regressions:
  router receipt stream, send/handle delivery receipt tests, chat/deletion hook
  tests, and `inbox_round_trip_test.dart`.
- Likely named gates:
  direct receipt suites, `./scripts/run_test_gates.sh 1to1`, `baseline`, and
  `completeness-check`.
- Matrix/closure docs to update when done:
  already recorded in the source doc closure log.
- Dependency:
  `115-P1` and doc 116 P1-P2.
- Current evidence:
  the source doc records Phase 2 closed; current code and tests contain
  `deliveryReceiptStream`, `sendDeliveryReceipt`,
  `handleDeliveryReceipt`, `DeliveryReceiptListener`, receipt hook tests, and
  `inbox_round_trip_test.dart` receipt assertions.

### `115-P3` Flutter Custody Sweep And Retry Truthfulness

- Session classification: `implemented`
- Intended plan file:
  `Test-Flight-Improv/115-relay-inbox-custody-session-115-P3-plan.md`
- Exact scope:
  implement the app-side custody verification sweep, detailed inbox-store
  outcome model, database custody query helpers, retry-unacked truthfulness,
  retrier and app-resume wiring, and old-relay defensive behavior.
- Why it is its own session:
  this is one Flutter/app persistence and lifecycle seam with direct RED tests
  already staged. It is independent from relay-server behavior because it must
  work against the old relay.
- Likely code-entry files:
  `lib/features/conversation/application/retry_unacked_messages_use_case.dart`,
  `lib/core/database/helpers/messages_db_helpers.dart`,
  `lib/features/conversation/domain/repositories/message_repository_impl.dart`,
  new `lib/core/services/inbox_store_outcome.dart`,
  `lib/core/services/p2p_service_impl.dart`,
  new `lib/features/conversation/application/verify_inbox_custody_use_case.dart`,
  `lib/core/services/pending_message_retrier.dart`,
  `lib/core/lifecycle/handle_app_resumed.dart`, and `lib/main.dart`.
- Likely direct tests/regressions:
  `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`,
  `test/core/database/helpers/messages_db_helpers_test.dart`,
  `test/features/conversation/application/verify_inbox_custody_use_case_test.dart`,
  `test/core/services/p2p_service_impl_test.dart`,
  `test/core/services/pending_message_retrier_test.dart`,
  `test/core/services/pending_message_retrier_upload_ordering_test.dart`,
  and `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`.
- Likely named gates:
  `flutter test test/features/conversation/application test/core/services test/core/lifecycle test/core/database`,
  `./scripts/run_test_gates.sh 1to1`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and
  `./scripts/run_test_gates.sh completeness-check`.
- Matrix/closure docs to update when done:
  append Phase 3 closure evidence to
  `Test-Flight-Improv/115-relay-inbox-custody.md`; defer 115 gate capture
  until `115-P5` unless this session adds new classified files that must be
  captured immediately.
- Dependency:
  `115-P1`, `115-P2`, and doc 116 P1-P2. The prerequisite is satisfied by
  current doc 116 closure evidence and the existing `deriveRetryAction` helper.
- Closure evidence:
  `115-P3` is accepted. Production now includes `inbox_store_outcome.dart`,
  `verify_inbox_custody_use_case.dart`, `storeInInboxDetailed`,
  `dbLoadInboxCustodyOutgoingMessages`, `dbMarkInboxCustodyChecked`,
  repository impl custody methods, pending retrier wiring, app-resume wiring,
  and main.dart DI. Retry-unacked now re-stores `sent` rows and persists
  successful relay custody as `inboxed` with the envelope retained instead of
  minting false `delivered`. Evidence: focused analyzer clean; focused P3
  Flutter tests passed (183); `./scripts/run_test_gates.sh 1to1` passed (593);
  `./scripts/run_test_gates.sh completeness-check` passed (841/841);
  `git diff --check` passed; `./graphify-arch/refresh_arch_graph.sh` passed
  from the repo root.

### `115-P4` Relay Protocol And Go Client Plumbing

- Session classification: `implemented`
- Intended plan file:
  `Test-Flight-Improv/115-relay-inbox-custody-session-115-P4-plan.md`
- Exact scope:
  change relay store-at-cap behavior from silent evict-old to typed reject-new,
  expose store metadata and TTL observability, fix memory dedup zombie behavior,
  keep Redis parity, pass typed outcomes through go-mknoon node and bridge, and
  rebuild app bindings.
- Why it is its own session:
  this is cross-tree Go/server/client/protocol work with Go gates and binding
  rebuild requirements. Keeping it separate from Flutter `115-P3` prevents
  app-side custody repair work from depending on a relay deploy.
- Likely code-entry files:
  `go-relay-server/inbox_store.go`, `go-relay-server/backend_memory.go`,
  `go-relay-server/limits.go`, `go-relay-server/backend_redis.go`,
  `go-relay-server/inbox.go`, `go-relay-server/metrics.go`,
  `go-mknoon/node/inbox.go`, `go-mknoon/bridge/bridge.go`,
  `go-mknoon/cmd/testpeer/commands.go`, gomobile-generated bindings, and
  iOS pod artifacts if regenerated by the established build flow.
- Likely direct tests/regressions:
  `go-relay-server/limits_test.go`,
  `go-relay-server/inbox_test.go`,
  `go-relay-server/inbox_dedup_test.go`,
  `go-relay-server/backend_redis_test.go`,
  `go-relay-server/metrics_test.go`,
  new `go-mknoon/node/inbox_parse_test.go`,
  `go-mknoon/bridge/bridge_test.go`, and
  `go-mknoon/integration/relay_test.go` for the later integration proof.
- Likely named gates:
  `cd go-relay-server && go test ./...`,
  `cd go-mknoon && make test`,
  gomobile rebuild verification, and later
  `cd go-mknoon && go test -tags integration ./integration/...`.
- Matrix/closure docs to update when done:
  append Phase 4 closure evidence to
  `Test-Flight-Improv/115-relay-inbox-custody.md`; note any coordinated relay
  deploy train requirements for `115-P5`.
- Dependency:
  `115-P3` for the Dart-side typed outcome consumer contract. The relay can be
  developed independently, but downstream acceptance should treat the P3/P4
  contract as a pair.
- Closure evidence:
  `115-P4` is accepted. Production now has typed relay
  reject-new behavior (`InboxStoreResultRejectedFull` / `INBOX_FULL` /
  `rejected_full`), memory/limited/Redis cap parity, memory TTL dedup repair,
  reject/prune telemetry, response metadata (`expiresAtMs`, `occupancy`,
  `capacity`), Go client `InboxStoreDetailed` / `InboxStoreOutcome` /
  `ErrInboxFull`, enriched bridge JSON, detailed testpeer output, and a rebuilt
  `go-mknoon/bin/testpeer`. Evidence: focused relay P4 suite passed; full
  `cd go-relay-server && go test -count=1 ./...` passed; focused Flutter
  bridge/app-side contract batch passed 128 tests; focused go-mknoon
  node/bridge/testpeer P4 tests passed; all non-`node`/`bridge` go-mknoon
  packages passed; isolated broad-timeout culprit tests passed; gomobile binding
  verification passed; `git diff --check` passed; and
	  `./graphify-arch/refresh_arch_graph.sh` passed from the repo root. The P4
	  broad-go gate caveat was resolved by `115-P5` gate policy: broad
  `cd go-mknoon && go test -count=1 -timeout=180s ./...`
  timed out in existing group-history/multi-device tests in `bridge` and
  `node` when run as one full suite, while those named tests pass in isolation;
	  `115-P5` policy-closed that aggregate timeout against focused
	  package/integration evidence.

### `115-P5` Acceptance, Gate Capture, Deploy, And Closure

- Session classification: `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/115-relay-inbox-custody-session-115-P5-plan.md`
- Exact scope:
  add or finish whole-system fake-network and Go integration proof, capture
  doc-115 gate definitions, update gate arrays, perform staging/production relay
  verification, collect two-device evidence, and close the source doc.
- Why it is its own session:
  it validates multiple earlier slices and includes doc, gate, deploy, and
  device evidence that should not be mixed into implementation sessions.
- Likely code-entry files:
  `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`,
  `go-mknoon/integration/relay_test.go`,
  `integration_test/scripts/run_transport_e2e.dart`,
  `Test-Flight-Improv/test-gate-definitions.md`,
  `scripts/run_test_gates.sh`, and
  `Test-Flight-Improv/115-relay-inbox-custody.md`.
- Likely direct tests/regressions:
  cap-rejected fake-network repair,
  lost-receipt loop closure,
  typed `INBOX_FULL` against local relay harness,
  transport E2E cap scenario, and device/staging evidence capture.
- Likely named gates:
  all doc-115 direct Flutter suites,
  `./scripts/run_test_gates.sh 1to1`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`,
  `./scripts/run_test_gates.sh completeness-check`,
  `cd go-relay-server && go test ./...`,
  `cd go-mknoon && make test`,
  `cd go-mknoon && go test -tags integration ./integration/...`, plus the
  staging relay and two-device evidence commands recorded by the final plan.
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/test-gate-definitions.md`,
  `scripts/run_test_gates.sh`, and
  the Phase 5 closure/evidence sections in
  `Test-Flight-Improv/115-relay-inbox-custody.md`.
- Dependency:
  `115-P3` and `115-P4`.
- Closure evidence:
	  `115-P5` is closed for implementation and production-relay deploy with
	  residual device/TestFlight lab evidence archived. The
  detailed inbox-store seam now lets `sendChatMessage` persist accepted relay
  custody as `inboxed` and typed `INBOX_FULL` as retryable non-delivered
  `sent` with the envelope retained. Fake-network whole-system tests cover
  cap-rejected send repair and lost-receipt repair; the local Go relay
  integration harness now proves typed `ErrInboxFull` against a cap-limited
  relay. The 1:1 gate scripts/docs now classify the Doc 115 custody, receipt,
  migration, router, retrier, bridge, media, and identity suites. Evidence:
  focused P5 Flutter batch passed 19 tests; the delivered-status source audit
  passed; `./scripts/run_test_gates.sh completeness-check` passed 841/841;
  expanded `./scripts/run_test_gates.sh 1to1` passed 788 tests; full
  `cd go-relay-server && go test -count=1 ./...` passed; focused go-mknoon
  local-relay integration passed; `git diff --check` passed; and
  `./graphify-arch/refresh_arch_graph.sh` passed from the repo root. The P4
	  broad go-mknoon aggregate timeout is policy-closed for this doc because the
	  isolated culprit tests and focused package/integration gates pass. External
	  production relay deploy is complete: the linux/amd64 artifact
	  `/tmp/relay-server-doc115-linux-amd64` with hash
	  `3d732c11f4d4ce4ba72a03d2440571c66f2b183677f4e6c19850bddddffe1bf5`
	  was installed on `mknoun.xyz`, service health/version/hash were verified,
	  and SSH-local metrics exposed the new Doc 115 counters. Two-device
	  drain/receipt proof, old TestFlight interop, and lowered-cap/TTL staging
	  proof are archived as unclaimed lab evidence, not open implementation work.

## Why This Is Not Fewer Sessions

Three remaining executable sessions are the minimum safe split:

- `115-P3` is Flutter/database/lifecycle implementation that must work against
  the old relay and has direct RED tests already staged.
- `115-P4` is Go relay, Go client, bridge, and generated-binding protocol work
  with different test commands, deploy risk, and backend parity requirements.
- `115-P5` is acceptance and closure across both previous sessions, including
  gate capture, deploy proof, and device evidence.

Merging these would mix host Flutter repair with relay protocol changes and
external acceptance evidence, making it too easy for downstream execution to
skip either the old-relay app contract or the deploy/device proof.

## Why This Is Not More Sessions

The source doc contains many tests, but most belong to one of three seams:
app-side custody repair, relay/client protocol behavior, or final acceptance.
Splitting Phase 3 into one session per helper, scheduler, and retry test would
create bookkeeping without an independently shippable state. Splitting Phase 4
into memory, Redis, handler, Go client, and bridge sessions would leave a
half-upgraded protocol that cannot be verified cleanly. Splitting Phase 5 into
separate gate-doc, staging deploy, and device-evidence sessions would invite
closure drift; those are one acceptance bar.

## Regression And Gate Contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies because doc 115
touches high-blast-radius 1:1 send, retry, listener, inbox, lifecycle, and
transport recovery paths. The plan must use direct regressions for the changed
seam first, then named gates for broad regression confidence:

- For `115-P3`, run the focused Flutter application, database, services, and
  lifecycle tests that prove custody sweep and retry truthfulness. Then run the
  1:1 gate, baseline, and completeness-check.
- For `115-P4`, run the relay and go-mknoon Go test families and any binding
  verification required by the implementation plan.
- For `115-P5`, run all accepted direct suites plus named 1:1, baseline,
  completeness, Go, integration, staging relay, and device evidence gates.

`Test-Flight-Improv/test-gate-definitions.md` remains the gate source of truth;
if it and `scripts/run_test_gates.sh` disagree, the script wins.

## Matrix Update Contract

Do not create a new matrix doc. Use the source doc's built-in test matrix and
closure sections as the matrix of record.

- `115-P3` updates the source doc with Phase 3 closure evidence when accepted.
- `115-P4` updates the source doc with Phase 4 Go/relay closure evidence when
  accepted.
- `115-P5` owns final gate capture in
  `Test-Flight-Improv/test-gate-definitions.md`, any coordinated
  `scripts/run_test_gates.sh` array edits, and final source-doc closure.

## Downstream Execution Path

For `115-P1` and `115-P2`, downstream execution should skip by default because
the ledger status is `stale/already-covered`; reopen only if a later planner
proves the source closure log stale.

For each pending session, the next workflow is:

| Session id | Next workflow |
|---|---|
| `115-P3` | `$implementation-plan-orchestrator`, then `$implementation-execution-qa-orchestrator`, then `$implementation-closure-audit-orchestrator` |
| `115-P4` | `$implementation-plan-orchestrator`, then `$implementation-execution-qa-orchestrator`, then `$implementation-closure-audit-orchestrator` |
| `115-P5` | `$implementation-plan-orchestrator`, then `$implementation-execution-qa-orchestrator`, then `$implementation-closure-audit-orchestrator` |

## Reviewer Questions

- Is the recommended session count sufficient, too coarse, or too fragmented?
  Sufficient. Three executable sessions match the remaining app, relay, and
  acceptance seams; two earlier phases are already-covered context.
- Which proposed sessions should merge?
  None. `115-P3`, `115-P4`, and `115-P5` have different gates and closure bars.
- Which proposed sessions must split?
  None at decomposition time. A later plan may split `115-P4` only if current
  relay or binding evidence proves the Go protocol is already partially landed
  enough to make a smaller acceptance slice meaningful.
- What tests or named gates are missing from the decomposition?
  No missing gate category. The exact test list must be refreshed during each
  session plan against the landed tree.
- Does each session end in a meaningful verified state?
  Yes. `115-P3` leaves old-relay app custody repair working, `115-P4` leaves
  the relay/client protocol typed and observable, and `115-P5` leaves the whole
  program accepted and documented.
- Is the matrix-update responsibility assigned clearly?
  Yes. Source-doc closure is assigned to each implementation session, while
  final gate/matrix capture is owned by `115-P5`.
- What is the minimum session set that is still safe?
  Three executable sessions, plus the two stale/already-covered historical rows
  retained for orchestration clarity.

## Arbiter

- Structural blockers:
  none for decomposition.
- Mergeable sessions:
  none.
- Required splits:
  none.
- Accepted differences:
  Phase 1 and Phase 2 are preserved as stale/already-covered rows rather than
  re-planned. The source doc still has an older header saying planned, but its
  closure log plus current tree evidence is stronger for execution state.

## Structural Blockers Remaining

No structural blocker prevents downstream planning.

Execution dependencies remain:

- `115-P3` must keep the doc 116 P1-P2 prerequisite green while rebasing on
  `deriveRetryAction`.
- `115-P5` is naturally blocked from acceptance until `115-P3` and `115-P4`
  both close.
- Two-device and old-TestFlight evidence are external lab proof for `115-P5`,
  not blockers to preparing this breakdown or closing implementation.

## Accepted Differences Intentionally Left Unchanged

- Existing historical `delivered` plus `transport == inbox` rows remain
  unrecoverable; no backfill session is added.
- No per-sender relay inbox sub-quota is added; it remains deferred hardening after
  reject-new telemetry.
- Background non-lazy 1:1 TTL prune remains deferred; lazy prune plus telemetry
  is the source-doc decision.
- Delivery receipts remain plaintext v1 for version-skew safety.

## Exact Docs And Files Used As Evidence

- `Test-Flight-Improv/115-relay-inbox-custody.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/116-edit-retry-fidelity.md`
- `lib/features/conversation/domain/models/conversation_message.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/features/conversation/application/send_delivery_receipt_use_case.dart`
- `lib/features/conversation/application/handle_delivery_receipt_use_case.dart`
- `lib/features/conversation/application/delivery_receipt_listener.dart`
- `lib/core/services/incoming_message_router.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`
- `test/features/conversation/application/verify_inbox_custody_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `test/core/database/helpers/messages_db_helpers_test.dart`
- `test/core/services/incoming_message_router_test.dart`
- `go-relay-server/inbox.go`
- `go-relay-server/limits.go`
- `go-relay-server/backend_redis_test.go`
- `go-relay-server/inbox_dedup_test.go`
- `go-relay-server/metrics_test.go`
- `go-mknoon/integration/relay_test.go`

## Why The Decomposition Is Safe To Send Into Downstream Planning And Execution

The split follows the current source-doc closure state and the repo evidence:
Phase 1 and Phase 2 are already represented in code and tests, Phase 3 has RED
tests but missing production, Phase 4 has relay/client protocol work, and Phase
5 needed final 115 gate capture plus deployment evidence. P5 now closed the
gate capture and production relay deploy while archiving uncollected device /
TestFlight lab proof as residual evidence.
Every executable session has a doc-scoped intended plan path, an explicit
dependency contract, a direct regression family, and named gates. No production
code, tests, doc 114 content, or session pipeline execution was touched during
this decomposition.

## Controller Progress

- 2026-06-13T10:13:42Z - Resume sanity for doc 115 only. Verified the source
  doc records Phases 1-4 as `CLOSED` and Phase 5 as `HOST-CLOSED with external
  release evidence pending`; verified doc-115 session plans for P3, P4, and P5
  exist; verified gate capture is present in
  `Test-Flight-Improv/test-gate-definitions.md`,
  `Test-Flight-Improv/test-gates-reference.md`, `scripts/run_test_gates.sh`,
  and `scripts/run_host_test_gates.sh`; ran an arch-graph exact-symbol query
  for `InboxStoreOutcome`, `storeInInboxDetailed`, `verifyInboxCustody`,
  `dbLoadInboxCustodyOutgoingMessages`, and `custodyCheckedAt`; no source row
	  remained `Open`, `Partial`, or `Contract-undefined`.
- 2026-06-13T15:07:40Z - Final deploy re-audit completed. Production relay
  deployment to `mknoun.xyz` is verified: binary backup
  `/usr/local/bin/relay-server.backup.20260613T145030Z`, installed binary hash
  `3d732c11f4d4ce4ba72a03d2440571c66f2b183677f4e6c19850bddddffe1bf5`,
  `relay-server v1.5.1`, active service, Doc 115 strings in the installed
  binary, and SSH-local metrics for `relay_inbox_expired_pruned_total` and
  `relay_inbox_rejected_full_total`. Final verdict normalized to
  `residual_only` because physical two-device and old-TestFlight lab evidence is
  unclaimed, not implementation work.

## Pipeline Resume Ledger Sanity

- `115-P1` remains `stale/already-covered`: the source doc records Phase 1 as
  closed and current evidence includes `inboxed`, `relayExpiresAt`,
  `custodyCheckedAt`, migration 077, and delivered-status guard coverage.
- `115-P2` remains `stale/already-covered`: the source doc records Phase 2 as
  closed and current evidence includes `deliveryReceiptStream`,
  `sendDeliveryReceipt`, `handleDeliveryReceipt`, `DeliveryReceiptListener`,
  and receipt round-trip coverage.
- `115-P3` remains `accepted`: the P3 plan status is `accepted`, the source doc
  records Phase 3 closed, and the arch graph/source reads show the custody
  sweep, detailed inbox-store outcome, DB helpers, retry truthfulness, retrier,
  and resume wiring are present.
- `115-P4` remains `accepted`: the P4 source code and relay/client protocol
  contract are closed,
  and P5 policy-closed the broad go-mknoon aggregate timeout against focused
  relay/client/integration evidence.
- `115-P5` is normalized to `residual_only`: the P5 plan records host-side
  acceptance, gate capture, fake-network repair proof, local relay `INBOX_FULL`
  proof, production deploy verification, and residual unclaimed device/TestFlight
  lab evidence. No implementation-owned doc-115 session needs reopening.
- Spawned final-acceptance agent note: this Codex tool surface did not expose a
  spawn-agent API. Because all runnable sessions were already resolved, the
  controller used the bounded local final-acceptance fallback for doc-only
  verdict persistence.

## Final Program Verdict

Verdict: `residual_only`

Date: 2026-06-13T15:07:40Z

Sessions processed by this resume pass: final acceptance and release-evidence
re-audit only. No doc-115 production code, migration, or gate-script edits were
made by this pass; source/breakdown docs were updated to record the completed
production deploy and remaining unclaimed lab evidence.

Sessions accepted:

- `115-P3`
- `115-P4`

Sessions residual_only:

- `115-P5`

Sessions stale/already-covered:

- `115-P1`
- `115-P2`

Sessions blocked: none.

Sessions skipped_due_to_dependency: none.

Plan fallbacks used: none.

Execution fallbacks used: none.

Closure fallbacks used: none.

Final acceptance fallbacks used: local final acceptance fallback, doc-only,
because no spawn-agent API was available in this controller surface.

Residual evidence archive:

- Production relay deploy is complete on `mknoun.xyz`; public
  `http://mknoun.xyz:2112/metrics` remains firewall-blocked, so metric evidence
  is SSH-local.
- Lowered-cap/TTL staging proof was not collected in this shell.
- Two-device relay drain and receipt proof was not collected in this shell.
- Old TestFlight interop proof was not collected in this shell.
- Final closure evidence on 2026-06-13: local
  `cd go-relay-server && go test -count=1 ./...` passed; the deployed Linux
  amd64 artifact `/tmp/relay-server-doc115-linux-amd64` had embedded
  `INBOX_FULL`, `rejected_full`, `relay_inbox_rejected_full_total`, and
  `relay_inbox_expired_pruned_total` strings; service health, version, binary
  hash, and SSH-local metrics were verified after install.

Why this final state is acceptable: the host code, gate capture, and local
relay/fake-network acceptance evidence are recorded in the source doc, session
plans, gate definitions, and scripts. The remaining work is release evidence
that cannot be truthfully synthesized from the repo and is already named as
non-host-code follow-up rather than an unresolved implementation gap.
