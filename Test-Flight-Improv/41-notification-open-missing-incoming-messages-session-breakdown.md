# 41 - Notification Tap Opens App Without Showing Incoming Messages Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/41-notification-open-missing-incoming-messages.md`
- Decomposition date:
  `2026-04-01`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `3`

## Overall closure bar

Report `41` is closed only when all of the following are true at the same time:

- the 1:1 inbox path no longer deletes relay-backed messages before the client
  has a durable local recovery record for them
- a fetched inbound envelope that later fails local processing leaves an exact
  reject reason with enough identifiers to correlate relay receipt and client
  rejection
- cold start, resume, and later recovery can surface previously fetched but not
  yet committed inbox messages exactly once instead of losing them silently
- warm remote push opens, terminated remote push opens, warm local
  notification taps, and terminated local notification launches all use the
  same truthful prepare-before-route contract for conversation and group
  targets
- the current report closes as a bounded inbox-recovery and notification-open
  trust fix, not as a broader read-receipt, unread-count, or relay-architecture
  redesign

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/41-notification-open-missing-incoming-messages.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`

Current repo facts that govern the split:

- `go-relay-server/backend_memory.go` and `go-relay-server/backend_redis.go`
  currently implement destructive inbox retrieval by returning the requested
  page and removing it from the stored inbox immediately.
- `go-relay-server/backend_redis_test.go` currently encodes that contract in
  `TestRedisInboxBackend_RetrieveOnceAcrossClients`, which expects the inbox to
  be empty after retrieval.
- `go-relay-server/inbox.go` currently exposes only `retrieve` for 1:1 inbox
  reads; there is no separate ack/confirm phase.
- `go-mknoon/node/inbox.go` and `go-mknoon/bridge/bridge.go` expose that same
  destructive retrieve contract to Flutter.
- `lib/core/bridge/p2p_bridge_client.dart` currently sends only
  `cmd: 'inbox:retrieve'`.
- `lib/core/services/p2p_service_impl.dart` currently drains the inbox by
  retrieving relay messages and immediately injecting them into the live message
  stream, and it logs the success case as `messages consumed and deleted from
  relay memory`.
- `lib/features/conversation/application/chat_message_listener.dart` and
  `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  only persist a message after downstream validation succeeds. A fetched v2
  chat envelope can still be dropped locally because of missing ML-KEM secret,
  decrypt failure, unknown sender, or duplicate/edit handling.
- `lib/features/identity/domain/repositories/identity_repository_impl.dart`
  reads the ML-KEM secret from secure storage or legacy DB columns, while
  `lib/features/identity/presentation/startup_router.dart` only repairs the
  missing-public-key case, not a public-key-present/secret-missing case.
- `lib/main.dart` currently leaves the warm remote open path and both local
  notification tap paths without `prepareNotificationOpen(...)`, while
  `lib/features/identity/presentation/startup_router.dart` already uses
  `_prepareNotificationRouteTarget` for the terminated remote path.
- `lib/features/push/application/prepare_notification_open_use_case.dart`
  already defines the intended prepare-before-route contract for conversation
  and group targets.
- `test/core/services/p2p_service_impl_test.dart`,
  `test/core/inbox/inbox_round_trip_test.dart`, and
  `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  already prove normal inbox drain behavior, but not a durable post-fetch
  recovery path.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  and `test/features/conversation/application/chat_message_listener_test.dart`
  already prove reject paths such as decrypt failure, but not a durable raw
  envelope audit/recovery contract.
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`,
  `test/features/push/application/prepare_notification_open_use_case_test.dart`,
  and `test/integration/notification_deeplink_integration_test.dart` already
  prove helper-level notification preparation sequencing, but the report still
  lacks direct proof for the real warm/local `lib/main.dart` handlers.
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  already treats offline inbox fallback and receive-side operability as part of
  the stable 1:1 closure bar. Report `41` therefore reopens a specific 1:1
  trust seam rather than inventing a new product area.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | `Two-phase 1:1 inbox retrieve/ack contract across relay and bridge` | `implementation-ready` | `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-1-plan.md` | none | `accepted` | Accepted on `2026-04-01` after bounded local planning, execution, and closure fallback landed additive `retrieve_pending` + `ack` plumbing across relay memory/Redis backends, stream handling, Go node/bridge exports, native method-channel routing, and Flutter bridge helpers. Direct proofs passed in `go-relay-server`, `go-mknoon/bridge`, tagged `go-mknoon/integration`, and Dart bridge suites. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` still fails in existing macOS integration noise inside `integration_test/loading_states_smoke_test.dart` (`HardwareKeyboard` key-up assertion), and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` still fails on pre-existing app-harness/build issues including debug-connection startup failure plus stale `integration_test/transport_e2e_test.dart` constructor drift requiring `dbDeleteMessage`; neither failure points at the landed Session `1` inbox contract seam. |
| `2` | `Client durable inbox staging, replay, and reject observability` | `implementation-ready` | `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-2-plan.md` | `1` | `accepted` | Accepted on `2026-04-01` after bounded local planning, execution, and closure fallback landed migration `045`, the durable inbox staging helpers/repository, replay-aware chat dispositions, and the additive `P2PServiceImpl` staged replay + `retrieve_pending`/`ack` production path in `lib/main.dart`. Direct proofs passed in the new migration/helper suites, `p2p_service_impl`, listener/use-case regressions, the full migration chain, inbox round-trip, offline inbox integration, and `c4_partial_drain`. `./scripts/run_test_gates.sh 1to1` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` still fails for the same pre-existing unrelated reasons already recorded after Session `1`: stale `integration_test/wifi_relay_fallback_smoke_test.dart` and `integration_test/transport_e2e_test.dart` constructors still omit the required `dbDeleteMessage` dependency, and `integration_test/media_stable_id_smoke_test.dart` still hits the existing macOS debug-connection startup failure; none of those failures point at the landed Session `2` inbox staging seam. |
| `3` | `Notification-open parity, acceptance proof, and Report 41 closure` | `implementation-ready` | `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-3-plan.md` | `1`, `2` | `accepted` | Accepted on `2026-04-01` after bounded local planning, execution, and closure fallback landed shared app-root notification preparation wiring for warm remote opens, terminated local launches, and warm local taps, plus a direct regression for the real app-root notification-open seam. Direct proofs passed in the new `app_root_notification_open` suite, the existing notification-open helper/integration suites, the adjacent post-notification flow suite, `./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. No `transport` rerun was required because the final change threaded the existing prepare-before-route contract through app-root handlers without widening into broader startup/resume/inbox-drain ordering changes. Report `41` is now closed through this breakdown plus the refreshed maintenance docs. |

## Ordered session breakdown

### Session 1

- Title:
  `Two-phase 1:1 inbox retrieve/ack contract across relay and bridge`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-1-plan.md`
- Exact scope:
  - replace the current destructive 1:1 inbox retrieve-only contract with a
    staged fetch plus explicit ack/delete contract, or an equivalent two-phase
    protocol that satisfies the report requirement
    `stage retrieved raw inbox messages durably first, then only ACK/delete
    after local persistence succeeds`
  - keep relay shared-backend behavior, pagination, and `hasMore` semantics
    truthful under the new contract
  - thread the new contract through `go-relay-server`, `go-mknoon/node`,
    `go-mknoon/bridge`, and the Flutter bridge client surface without claiming
    the final user-visible fix before the durable client consumer exists
  - add or update the direct Go/bridge regressions that currently encode
    destructive retrieval as the expected behavior
- Why it is its own session:
  - this is the relay/backend/bridge protocol seam, which is different from
    the later Flutter database/recovery seam and the later app-root
    notification-routing seam
  - the current relay tests explicitly encode destructive retrieval, so this
    prerequisite needs its own direct proof family before client-side durable
    recovery can be planned safely
  - it can land as a backward-compatible prerequisite state without pretending
    the user-visible bug is already closed
- Likely code-entry files:
  - `go-relay-server/backend_memory.go`
  - `go-relay-server/backend_redis.go`
  - `go-relay-server/inbox.go`
  - `go-mknoon/node/inbox.go`
  - `go-mknoon/bridge/bridge.go`
  - `lib/core/bridge/p2p_bridge_client.dart`
- Likely direct tests/regressions:
  - `go-relay-server/backend_redis_test.go`
  - `go-relay-server/failover_test.go`
  - `go-relay-server/redis_failover_integration_test.go`
  - `go-mknoon/bridge/bridge_test.go`
  - `go-mknoon/integration/relay_test.go`
  - `go-mknoon/integration/multi_relay_test.go` if the final protocol changes
    multi-relay inbox fallback behavior
  - `test/core/bridge/p2p_bridge_client_test.dart`
- Likely named gates:
  - no frozen named gate directly owns relay-server Go protocol changes
  - required proof is the direct Go/bridge suite above
  - run `./scripts/run_test_gates.sh baseline` only if the final session edits
    Flutter production files under `lib/`
  - run `./scripts/run_test_gates.sh transport` only if the Flutter-facing
    bridge surface or transport-backed receive semantics are materially changed
    during this prerequisite session
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
  - do not update `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    yet; the user-visible closure bar still depends on Sessions `2` and `3`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 2

- Title:
  `Client durable inbox staging, replay, and reject observability`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-2-plan.md`
- Exact scope:
  - add a durable local recovery record for fetched 1:1 inbox envelopes before
    they are handed to the live chat processing pipeline
  - move the 1:1 inbox drain path in Flutter onto the Session `1` staged
    retrieve/ack contract so relay deletion happens only after local
    persistence succeeds
  - ensure later cold start, resume, or retry can replay staged inbox envelopes
    exactly once when an earlier attempt fetched them but did not yet commit
    visible conversation rows
  - emit one exact reject reason per dropped inbound envelope with enough
    identifiers to correlate relay receipt, staged fetch, and client-side
    rejection
  - harden any receive-path prerequisites that make staged v2 envelopes fail
    locally for avoidable reasons, including the current ML-KEM secret-availability
    gap if fresh planning confirms it is part of the same seam
- Why it is its own session:
  - this is the Flutter persistence/recovery seam, not the relay protocol seam
    and not the app-root notification-routing seam
  - it has a different direct regression family: migrations/helpers,
    `p2p_service_impl`, inbox round-trip, and inbound listener/use-case tests
  - the report is not meaningfully safer until this session exists, even if the
    new protocol from Session `1` already does
- Likely code-entry files:
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/core/services/incoming_message_router.dart` only if staged replay
    changes message dispatch ownership
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/identity/domain/repositories/identity_repository_impl.dart`
  - `lib/features/identity/presentation/startup_router.dart` only if the
    receive path needs a narrow ML-KEM secret-availability fix
  - `lib/core/database/helpers/messages_db_helpers.dart`
  - `lib/core/database/migrations/` with one new doc-scoped migration if a new
    staging table or recovery columns are required
  - `lib/features/conversation/domain/repositories/message_repository_impl.dart`
    or a new adjacent repository if staged-envelope persistence does not fit
    the current message repository cleanly
- Likely direct tests/regressions:
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/inbox/inbox_round_trip_test.dart`
  - `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - `test/features/conversation/application/chat_message_listener_test.dart`
  - `test/core/resilience/c4_partial_drain_test.dart`
  - one new migration/helper/repository regression for staged-envelope
    durability if the final implementation adds persistence schema
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport`
  - direct lifecycle suites as needed if final planning touches
    `handle_app_resumed` ordering or later recovery orchestration
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
  - keep the broad stable closure refresh deferred to Session `3` unless the
    later closure-audit pass proves Session `2` alone already changes the
    stable 1:1 closure wording safely
- Dependency on earlier sessions:
  - Session `1`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 3

- Title:
  `Notification-open parity, acceptance proof, and Report 41 closure`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-3-plan.md`
- Exact scope:
  - make the real app-root notification handlers use the same truthful
    prepare-before-route contract that already exists on the terminated remote
    path
  - unify warm remote push open, terminated local notification launch, and warm
    local notification tap behavior around the now-trustworthy staged inbox
    recovery from Sessions `1` and `2`
  - preserve existing group notification route preparation parity while keeping
    the report scoped to message visibility rather than broader notification UI
    redesign
  - add the missing direct regressions for the real `lib/main.dart`
    notification-open entry points, then refresh the closure ledger and
    maintenance docs once the end-to-end user-visible bar is actually met
- Why it is its own session:
  - this is the app-root notification-routing seam, which has different code
    ownership and different direct regression families from the protocol and
    persistence sessions
  - the report only closes when the user-visible entry paths are fixed, so the
    final closure work belongs with this last open implementation seam rather
    than as a separate bookkeeping-only session
  - splitting this further into “routing,” “acceptance,” and “closure” would
    add bookkeeping without independent verification value
- Likely code-entry files:
  - `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
  - `lib/core/notifications/notification_route_dispatch.dart` only if a narrow
    helper change is still required
  - `lib/features/push/application/background_message_handler.dart` only if the
    current fallback-notification assumption must be tightened to stay truthful
- Likely direct tests/regressions:
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_deeplink_integration_test.dart`
  - `test/core/notifications/notification_push_tap_navigate_test.dart`
  - `test/features/identity/presentation/screens/startup_router_test.dart`
    and/or one new app-root regression proving the real warm/local handlers in
    `lib/main.dart`
  - `test/features/posts/phase1/post_notification_open_flow_test.dart` as an
    adjacent guard so post-notification behavior stays truthful when shared
    app-root wiring changes
- Likely named gates:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh transport` if final planning confirms the
    `main.dart` / `StartupRouter` changes materially alter app bootstrap or
    inbox-drain ordering rather than only threading the existing preparation
    callback through
  - direct group notification suites should run when the final change touches
    group preparation paths, but no frozen named gate currently owns this
    notification-open boundary directly
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
    - `Test-Flight-Improv/00-INDEX.md`
  - conditional:
    - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
      if the final accepted state changes the stable wording around offline
      inbox recovery, receive-side operability, or reject diagnostics
    - `Test-Flight-Improv/17-roadmap-closure-audit.md` only if the current
      folder-level closure process expects the report closure to be recorded
      there as well
- Dependency on earlier sessions:
  - Sessions `1` and `2`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented:
  - sufficient; `3` is the minimum safe split across protocol, durable client
    recovery, and app-root notification parity
- Which proposed sessions should merge:
  - none
- Which proposed sessions must split:
  - none
- What tests or named gates are missing from the decomposition:
  - Session `1` needs explicit relay/backend tests that stop encoding
    destructive retrieval as the correct end state
  - Session `2` needs a new durable post-fetch recovery regression
  - Session `3` needs a direct regression for the real warm/local
    `lib/main.dart` handlers, not only helper-level dispatch coverage
- Does each session end in a meaningful verified state:
  - yes; Session `1` ends in a safe protocol prerequisite, Session `2` ends in
    a durable client recovery contract, and Session `3` ends in the final
    user-visible fix plus closure refresh
- Is the matrix-update responsibility assigned clearly:
  - yes; this breakdown artifact is the live closure ledger, with stable 1:1
    closure docs updated only at the final accepted state if warranted
- What is the minimum session set that is still safe:
  - `3`

## Arbiter outcome

- Structural blockers:
  - none
- Mergeable sessions:
  - none
- Required splits:
  - none
- Accepted differences:
  - current evidence proves the destructive-loss seam only for 1:1 inbox
    retrieval; the split does not assume a matching group-inbox protocol change
    unless later planning proves that same seam is shared
  - the dominant real-world reject reason among decrypt failure, missing ML-KEM
    secret, unknown sender, and duplicate handling stays open for execution to
    confirm; the decomposition only requires exact post-fetch diagnostics
  - no broader unread-count redesign, read-receipt model, or notification-card
    UX redesign is bundled into this rollout

## Why this is not fewer sessions

- One giant session would span three different core seams:
  - relay/backend/bridge protocol
  - Flutter persistence/recovery and database shape
  - app-root notification-open routing
- Those seams have different direct regression families, different closure
  bars, and different blast radii. Bundling them together would make later
  planning and QA noisy and unsafe.
- Session `1` is a real prerequisite because the requested
  `stage first, ACK/delete later` contract does not exist in the relay/bridge
  layer today.
- Session `3` cannot honestly close the user-visible bug until Session `2`
  makes inbox recovery durable after fetch.

## Why this is not more sessions

- No separate evidence-only session is justified. The current report, relay
  evidence, destructive retrieve tests, and repo code already give enough
  evidence to plan implementation safely.
- No separate accept-only or closure-only session is justified. Session `3`
  already owns the final remaining implementation seam and can carry the
  closure refresh without extra bookkeeping.
- Exact reject logging should stay with durable inbox staging in Session `2`
  because both belong to the same post-fetch failure family and the same test
  ownership.
- Warm remote, warm local, and terminated local notification parity should stay
  together in Session `3` because they share the same app-root notification
  boundary and helper/test family.

## Regression and gate contract

- Use `Test-Flight-Improv/14-regression-test-strategy.md` as the policy source
  and `Test-Flight-Improv/test-gate-definitions.md` as the execution source of
  truth for named gates.
- For every session, add the direct regression first for the exact seam before
  broad reruns.
- Session `1` is governed primarily by direct Go/relay/bridge proof. Named
  Flutter gates apply only if the final protocol work crosses into Flutter
  production files.
- Session `2` must run the direct inbox/service/use-case suites plus:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport`
- Session `3` must run the direct notification-open suites plus:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh transport` if the final plan materially
    changes startup/bootstrap ordering rather than only threading the existing
    preparation callback through
- Keep `test/integration/notification_deeplink_integration_test.dart` in the
  existing optional/manual direct-suite bucket unless a later planning pass
  intentionally changes named gate membership.
- Do not invent a new named gate for this report by default.

## Matrix update contract

- No separate stable notification-open closure reference currently owns this
  seam.
- Reuse the existing stable 1:1 closure reference
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` rather
  than inventing a new matrix doc if the final accepted state materially
  changes the durable receive/offline-inbox closure wording.
- This breakdown artifact is the live doc-scoped closure ledger for Report
  `41`.
- Session `3` owns the maintenance-time closure refresh for:
  - this breakdown artifact
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    only if warranted by the landed final state
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  stays untouched unless later planning proves the same destructive
  fetch-before-durable-stage seam exists and is intentionally fixed in the
  group path too.

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- The report stays scoped to 1:1 inbox durability plus notification-open truth.
  It does not force a broader group-inbox architecture change up front.
- The current notification-card UI, unread-badge model, and read-receipt model
  remain unchanged unless a later execution pass proves a narrow touch is
  required for the report closure bar.
- Session `1` may keep backward-compatible destructive-retrieve support
  temporarily during rollout if the final plan needs a safe additive migration;
  immediate removal is not required by the decomposition itself.

## Exact docs/files used as evidence

- `Test-Flight-Improv/41-notification-open-missing-incoming-messages.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `go-relay-server/backend_memory.go`
- `go-relay-server/backend_redis.go`
- `go-relay-server/backend_redis_test.go`
- `go-relay-server/inbox.go`
- `go-mknoon/node/inbox.go`
- `go-mknoon/bridge/bridge.go`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/identity/domain/repositories/identity_repository_impl.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/main.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/inbox/inbox_round_trip_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/core/notifications/notification_push_tap_navigate_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The session order matches the real dependency chain exposed by the repo:
  destructive relay protocol first, then durable client receive semantics, then
  final notification-open parity.
- Each session has a coherent blast radius and an independent direct regression
  family.
- The decomposition reuses existing stable docs and frozen named gates instead
  of inventing a new matrix.
- The final closure responsibility is explicit: Session `3` owns the last
  production seam and the maintenance-time closure refresh.
