# Session 1 Plan - Two-phase 1:1 inbox retrieve/ack contract across relay and bridge

## Final verdict

`implementation-ready`

Current repo evidence still shows the first blocking seam for Report `41` is
the destructive 1:1 inbox retrieve contract:

- `go-relay-server/backend_memory.go` and `go-relay-server/backend_redis.go`
  still remove inbox entries as part of retrieval.
- `go-relay-server/backend_redis_test.go` currently asserts retrieve-once /
  inbox-empty-after-read behavior.
- `go-relay-server/inbox.go`, `go-mknoon/node/inbox.go`,
  `go-mknoon/bridge/bridge.go`, and
  `lib/core/bridge/p2p_bridge_client.dart` expose only retrieve semantics, not
  a second explicit ack/delete phase.
- `lib/core/services/p2p_service_impl.dart` currently treats retrieved inbox
  messages as already consumed from relay memory and immediately injects them
  into the live message stream, which is unsafe until later sessions add a
  durable client recovery record.

This session is therefore a bounded protocol prerequisite: land a truthful
two-phase 1:1 inbox retrieve/ack contract across relay, node, bridge, and
Flutter bridge surfaces without claiming the whole user-visible bug is closed.

## Final plan

### real scope

- Replace the current destructive 1:1 inbox retrieve-only contract with a
  staged fetch plus explicit ack/delete contract, or an equivalent two-phase
  protocol that preserves relay-backed inbox messages until the client later
  confirms deletion.
- Keep pagination and `hasMore` semantics truthful under the new contract.
- Thread the new contract through `go-relay-server`, `go-mknoon/node`,
  `go-mknoon/bridge`, and the Flutter bridge client surface.
- Update the direct Go/bridge regressions that currently encode destructive
  retrieval as expected behavior.
- Preserve existing behavior for callers that only need to read staged inbox
  pages during this prerequisite session; do not pretend local durable replay
  or notification-open parity is complete yet.

### closure bar

- A 1:1 inbox page can be fetched without immediately deleting those relay
  entries.
- The protocol exposes an explicit ack/delete step, or an equivalent truthful
  second phase, that removes only the entries the client confirms.
- Relay memory and Redis-backed inbox behavior remain truthful across the new
  staged-read plus ack path.
- Bridge and Flutter bridge surfaces can request staged retrieve and later ack
  without inventing unrelated transport APIs.
- The direct Go/bridge regressions proving the new contract pass.
- If Flutter production files under `lib/` materially change, companion named
  gate decisions from the breakdown are honored honestly.
- Session `1` lands as a prerequisite state only; it does not claim the full
  Report `41` user-visible closure bar before Sessions `2` and `3`.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Current code and tests beat stale prose when they disagree.
- Verified repo seams:
  - `go-relay-server/backend_memory.go`
  - `go-relay-server/backend_redis.go`
  - `go-relay-server/inbox.go`
  - `go-relay-server/backend_redis_test.go`
  - `go-relay-server/failover_test.go`
  - `go-relay-server/redis_failover_integration_test.go`
  - `go-mknoon/node/inbox.go`
  - `go-mknoon/bridge/bridge.go`
  - `go-mknoon/bridge/bridge_test.go`
  - `go-mknoon/integration/relay_test.go`
  - `go-mknoon/integration/multi_relay_test.go`
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `test/core/bridge/p2p_bridge_client_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The current 1:1 inbox path deletes queued relay-backed messages at retrieve
  time, before the Flutter client has a durable local recovery record.
- That destructive contract leaves no safe foundation for the later client-side
  staging, replay, and exact reject-diagnostic work required by Report `41`.
- Current relay and bridge tests encode destructive retrieval as correct, so
  the protocol change needs its own direct proof family before the later client
  sessions can be executed safely.

### files and repos to inspect next

- Repo scope stays inside
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app`,
  `/Users/I560101/Project-Sat/mknoon-2/go-relay-server`, and
  `/Users/I560101/Project-Sat/mknoon-2/go-mknoon` if those sibling repos are
  present and are the live sources wired into this workspace.
- Production files:
  - `go-relay-server/backend_memory.go`
  - `go-relay-server/backend_redis.go`
  - `go-relay-server/inbox.go`
  - `go-mknoon/node/inbox.go`
  - `go-mknoon/bridge/bridge.go`
  - `lib/core/bridge/p2p_bridge_client.dart`
- Direct tests:
  - `go-relay-server/backend_redis_test.go`
  - `go-relay-server/failover_test.go`
  - `go-relay-server/redis_failover_integration_test.go`
  - `go-mknoon/bridge/bridge_test.go`
  - `go-mknoon/integration/relay_test.go`
  - `go-mknoon/integration/multi_relay_test.go` only if the final contract
    changes multi-relay inbox behavior
  - `test/core/bridge/p2p_bridge_client_test.dart`
- Closure docs:
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
  - do not update `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    yet

### existing tests covering this area

- `go-relay-server/backend_redis_test.go` already proves current destructive
  retrieve semantics and therefore must change with the new contract.
- `go-relay-server/failover_test.go` and
  `go-relay-server/redis_failover_integration_test.go` already cover relay
  backend behavior that could regress if inbox storage semantics change.
- `go-mknoon/bridge/bridge_test.go` and
  `go-mknoon/integration/relay_test.go` already cover bridge-facing inbox
  behavior that will need refreshed expectations.
- `test/core/bridge/p2p_bridge_client_test.dart` covers the Flutter bridge
  client surface and should prove the new staged retrieve plus ack request
  contract once introduced.
- Missing today:
  - no direct proof that staged retrieve leaves the inbox intact until ack
  - no direct proof that ack/delete removes only the intended retrieved entries
  - no direct proof that the Flutter bridge client can issue the new two-phase
    contract cleanly

### regression/tests to add first

- Add or update relay backend tests first to pin:
  - staged retrieve does not eagerly delete
  - ack/delete removes only confirmed entries
  - pagination / `hasMore` truth remains correct
- Add or update bridge/node tests next to pin the new command contract and
  wire format.
- Add or update `test/core/bridge/p2p_bridge_client_test.dart` to pin the
  Flutter bridge client's staged retrieve and ack request behavior.

### step-by-step implementation plan

1. Re-read the targeted relay, node, bridge, and Flutter bridge files in the
   live tree before editing. Merge carefully with unrelated local changes; do
   not revert them.
2. Define the smallest truthful two-phase contract that satisfies Session `1`:
   staged retrieve first, explicit ack/delete second.
3. Implement that contract in relay memory and Redis backends while preserving
   truthful pagination and inbox ownership behavior.
4. Thread the contract through relay inbox handlers, node inbox helpers, and
   bridge plumbing.
5. Update the Flutter bridge client surface to request the new staged retrieve
   and later ack/delete primitives without widening into Session `2` client
   staging logic.
6. Land the direct Go/bridge regressions before relying on any broader gate.
7. Run the exact direct suites and conditional named gates listed below.
8. Stop and re-evaluate if execution unexpectedly requires broader Flutter
   client staging, message repository changes, notification-open routing work,
   or a relay architecture redesign. Those belong to later sessions or are out
   of scope.

### risks and edge cases

- The new protocol must not leave relay inbox pages permanently undeletable or
  break `hasMore` truth.
- Ack/delete must target only the intended retrieved entries and must stay
  safe across Redis and in-memory backends.
- Bridge and Flutter bridge changes must stay compatible with the later client
  staging session instead of hard-coding destructive assumptions in a new form.
- Multi-relay or failover behavior could regress if inbox ownership or paging
  semantics shift.
- This session must not accidentally claim the user-visible bug is fixed before
  Sessions `2` and `3` land.

### exact tests and gates to run

- Direct tests:
  - run the exact updated relay backend test that pins staged retrieve and ack
    semantics in `go-relay-server/backend_redis_test.go`
  - run `go-relay-server/failover_test.go`
  - run `go-relay-server/redis_failover_integration_test.go`
  - run `go-mknoon/bridge/bridge_test.go`
  - run `go-mknoon/integration/relay_test.go`
  - run `go-mknoon/integration/multi_relay_test.go` only if execution changes
    multi-relay inbox behavior materially
  - run `flutter test test/core/bridge/p2p_bridge_client_test.dart`
- Conditional named gates:
  - `./scripts/run_test_gates.sh baseline` only if the final session edits
    Flutter production files under `lib/`
  - `./scripts/run_test_gates.sh transport` only if the Flutter-facing bridge
    surface or transport-backed receive semantics are materially changed during
    this session

### known-failure interpretation

- There is no accepted known-failure exemption for the new staged retrieve/ack
  protocol regressions in this session.
- Missing the direct relay/bridge proof for staged retrieve and ack/delete is a
  blocking failure.
- A broader Flutter receive, replay, or notification-open failure found during
  this session should be recorded as later-session scope unless the evidence
  proves Session `1` directly caused it.

### done criteria

- 1:1 inbox retrieval is no longer destructive at fetch time.
- The system exposes an explicit ack/delete phase, or equivalent truthful
  second phase, across relay, node, bridge, and Flutter bridge surfaces.
- Relay backends retain fetched inbox entries until ack/delete.
- Direct relay, bridge, and Flutter bridge regressions proving staged retrieve
  plus ack/delete pass.
- Session `1` remains a prerequisite-only acceptance state and the breakdown
  ledger can record that later client staging and notification-open work is
  still open.

### scope guard

- Do not add the durable local staging store in this session.
- Do not rewrite `p2p_service_impl.dart` to own client replay or reject
  observability in this session.
- Do not fix warm/local notification-open routing in `lib/main.dart` here.
- Do not redesign unread counts, read receipts, or broader relay architecture.
