# Audit Closure TDD Plan for Resilient libp2p

## Purpose

This document is the acceptance-recovery companion to
`Network-Arch/Resilient-libp2p-TDD-Plan.md`.

Use it after the audit of the current `Network-Arch` worktree based on commit
`0c4c639`.

The original plan still defines the target architecture and phase order. This
document defines the additional RED and GREEN work required before the audited
phases can be accepted.

Baseline note:

- the audited tree was dirty
- the Phase 1 send-path mismatch is therefore a current-worktree regression
  until reverified
- Phase 3 production behavior was judged sufficient, but its tagged proof is
  blocked by the current integration slice not building

## Controller Rules

- Use the same states as the phase controller reference:
  `pending`, `implementing`, `tests_green`, `review_green`, `accepted`,
  `blocked`.
- Re-open only one phase at a time.
- Do not advance past a phase marked `reject` or `blocked`.
- Cross-phase edits are allowed only when they repair a lying test, fake, or
  compile blocker that hides the real phase status.
- If an audited gap spans Flutter, Go bridge, and native bridge layers, the
  RED tests for the user-visible contract must land before production changes.

## Acceptance Snapshot

- Phase 1: `reject`
- Phase 2: `reject`
- Phase 3: `blocked`
- Phase 4: `reject`
- Phase 5: `reject`
- Phase 6: `implementing`
- Phase 7: `reject`

## Harness Repairs Required Before Re-review

These are not new architectural phases. They are truth-restoring test or fake
repairs that must be folded into the relevant phase re-open.

- Phase 1 must update
  `test/features/conversation/application/send_chat_message_use_case_test.dart`
  so the suite expects the current result taxonomy
  (`peerNotFound`, `dialFailed`) where that is the intended contract.
- Phase 5 must align `test/shared/fakes/lifecycle_bridge.dart` with the real
  bridge field name `recoveryMode`; fake-only `recoveryMethod` behavior must no
  longer hide contract drift.
- Phase 3 and Phase 7 must make `go test -tags integration ./integration`
  build again by fixing `go-mknoon/integration/watchdog_failover_test.go`
  before using that slice as proof for either phase.

---

## Phase 1 Re-open: Interactive Send Path and Startup Readiness

### Current Audit Verdict

`reject`

Remaining gaps:

- `startNode()` still waits for the full warm path because it awaits
  `warmBackground()`
- `_drainOfflineInbox()` still paginates synchronously and does not use the new
  foreground timeout split for the first page
- relay auto-register still waits for all warm goroutines instead of first
  healthy discoverable relay readiness
- stream deadline and reset hygiene is incomplete outside chat
- the current send tests no longer reflect the implementation result taxonomy

### RED Tests

#### Flutter unit

**File:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

- `returns peerNotFound when discover returns null`
- `returns dialFailed when dial returns false`
- `transport exception still maps to sendFailed`
- `durable inbox fallback still succeeds exactly once when active paths lose`

**File:** `test/core/services/p2p_service_impl_test.dart`

- `startNode returns before background warm continuation drains remaining inbox pages`
- `drainOfflineInbox uses foreground timeout for the first page`
- `drainOfflineInbox schedules remaining pages on background budget`
- `resume shows first inbox page before relay warm completion`
- `startNode does not await full warmBackground before reporting ready`

**File:** `test/features/identity/presentation/screens/startup_router_test.dart`

- `returning cold start schedules inbox-first recovery before secondary warm tasks`

#### Go bridge and node unit

**File:** `go-mknoon/bridge/bridge_test.go`

- `TestInboxRetrieve_HonorsForegroundTimeoutWhenProvided`
- `TestInboxRetrieve_ExposesContinuationMetadataWhenBacklogRemains`

**File:** `go-mknoon/node/node_test.go`

- `TestAutoRegister_DoesNotWaitForAllRelayWarmAttemptsAfterFirstHealthyRelay`
- `TestAutoRegister_RegistersAfterFirstDiscoverableRelayReadiness`

**File:** `go-mknoon/node/stream_timeout_test.go`

- `TestInboxStreams_ApplyDeadlineAndResetOnTimeout`
- `TestRendezvousStreams_ApplyDeadlineAndResetOnTimeout`
- `TestMediaStreams_ApplyDeadlineAndResetOnTimeout`
- `TestProfileStreams_ApplyDeadlineAndResetOnTimeout`

#### Integration with fakes

**File:** `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`

- `startup inbox first page arrives before relay warm settles`
- `large backlog continues in background after first page`

### GREEN Targets

- `startNode()` must not await full `warmBackground()` completion before the
  app can proceed.
- `_drainOfflineInbox()` must run a short first-page drain on the foreground
  budget and continue with additive `hasMore` or equivalent metadata in the
  background.
- personal auto-register must release after the first healthy discoverable
  relay path and must not wait for all warm goroutines to finish.
- shared stream deadline and reset helpers must cover chat, inbox, rendezvous,
  group inbox, media, and profile paths consistently.
- the send-path test suite must match the intended result taxonomy instead of
  masking regressions with stale expectations.

### Exit Criteria

- startup and resume can surface inbox progress before full relay warm
  completion
- the first inbox page uses the foreground timeout class and later pages do not
  block readiness
- dead secondary relay warm attempts do not delay personal registration
- timeout and framing failures reset non-chat streams too
- the send-path slice is green with expectations aligned to the current API

### Commands

```bash
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/features/identity/presentation/screens/startup_router_test.dart
cd go-mknoon && go test ./bridge ./node -run 'InboxRetrieve|AutoRegister|Stream'
flutter test test/features/conversation/integration/offline_inbox_roundtrip_test.dart
```

---

## Phase 2 Re-open: Shared Relay Control State

### Current Audit Verdict

`reject`

Remaining gaps:

- `go-relay-server/backend_redis.go` is still placeholder text
- server bootstrap still hard-wires in-memory backends
- current failover tests prove shared in-process objects, not real
  multi-process/shared-backend deployment

Out of scope for this phase:

- replacing infinite relay service limits with finite runtime limits remains a
  Phase 7 acceptance item, except for any small bootstrap seam required to
  inject backend configuration

### RED Tests

#### Go unit

**File:** `go-relay-server/backend_redis_test.go`

- `TestRedisRendezvous_RegisterRefreshesTTL`
- `TestRedisRendezvous_DiscoverExcludesExpiredEntries`
- `TestRedisInbox_RetrieveExactlyOnceAcrossInstanceRestart`
- `TestRedisInbox_PaginatedRetrieveKeepsFIFOAcrossInstances`
- `TestRedisGroupInbox_CursorPaginationStableAcrossInstances`
- `TestRedisPushTokens_SurviveServerRestart`

**File:** `go-relay-server/main_test.go` or `go-relay-server/server_bootstrap_test.go`

- `TestServerBootstrap_UsesRedisBackendWhenConfigured`
- `TestServerBootstrap_DefaultsToMemoryBackendWhenUnset`
- `TestServerBootstrap_WiresSharedStoresIntoRendezvousInboxGroupInboxAndPush`

#### Tagged integration

**File:** `go-relay-server/redis_failover_integration_test.go`

- `TestTwoRelayProcesses_SharedRendezvousRedisBackend`
- `TestTwoRelayProcesses_SharedInboxRedisBackend`
- `TestTwoRelayProcesses_SharedGroupInboxCursorContinuation`
- `TestTwoRelayProcesses_PushTokenRegistrationSurvivesRelayACrash`

Required harness behavior:

- boot two real relay processes with different peer IDs
- point both at the same Redis backend
- write via relay A and read via relay B
- kill relay A and prove relay B still serves the same shared state

### GREEN Targets

- implement a real Redis backend for rendezvous, inbox, group inbox, and push
  token state
- make backend selection runtime-configurable in `go-relay-server/main.go`
- preserve in-memory backends for local development and non-shared tests
- prove shared-backend behavior with real multi-process integration, not only
  shared object references in one process

### Exit Criteria

- relay state survives process restart when Redis is configured
- relay A can write state that relay B can discover or retrieve
- paginated inbox and group cursor continuation survive relay failover
- the default local-dev path still works without Redis

### Commands

```bash
cd go-relay-server && go test ./...
cd go-relay-server && go test -tags integration ./... -run 'Redis|TwoRelayProcesses'
```

---

## Phase 3 Re-open: Multi-Relay Routing Everywhere

### Current Audit Verdict

`blocked`

Production code status:

- current routing implementation was judged sufficient in production code
- acceptance is blocked because the tagged integration proof does not build

### RED Tests and Blockers

#### Tagged integration

**File:** `go-mknoon/integration/watchdog_failover_test.go`

- remove the unused import or use it intentionally so the file builds under
  `-tags integration`
- keep the phase boundary tight: this file may be edited only to restore honest
  proof, not to pull in Phase 4 or Phase 7 behavior changes

**File:** `go-mknoon/integration/multi_relay_test.go`

- `TestRendezvousFallbackWithDeadFirstRelay`
- `TestInboxFallbackWithDeadFirstRelay`
- `TestMediaFallbackWithDeadFirstRelay`
- `TestProfileFallbackWithDeadFirstRelay`

Keep these existing proof slices green:

- `cd go-mknoon && go test ./node ./bridge -run 'Relay|Rendezvous|Inbox|Media|Profile'`
- `flutter test test/core/bridge`

### GREEN Targets

- unblock the tagged integration suite
- keep the current production routing behavior unchanged unless the integration
  proof exposes a real defect
- document any remaining environment requirements for the tagged integration
  slice so the phase can be reproduced outside one workstation

### Exit Criteria

- `go test -tags integration ./integration` builds and passes for the
  multi-relay slice
- no `relayAddrs[0]` regression is reintroduced while unblocking the harness
- no later-phase recovery work is bundled into this re-open

### Commands

```bash
cd go-mknoon && go test ./node ./bridge -run 'Relay|Rendezvous|Inbox|Media|Profile'
cd go-mknoon && go test -tags integration ./integration -run 'Relay|Rendezvous|Inbox|Media|Profile'
flutter test test/core/bridge
```

---

## Phase 4 Re-open: Relay Session Manager and Reservation-Aware Health

### Current Audit Verdict

`reject`

Remaining gaps:

- `go-mknoon/node/autorelay_metrics.go` is still a placeholder
- the live event loop does not drive relay-session reservation transitions
- Flutter has no real `relay:state` push handler
- health still keys off empty `circuitAddresses` instead of `relayState`

### RED Tests

#### Go unit

**File:** `go-mknoon/node/relay_session_test.go`

- `TestAutoRelayMetrics_ReservationOpenedTransitionsReserved`
- `TestAutoRelayMetrics_ReservationEndedTransitionsDegraded`
- `TestAutoRelayMetrics_RequestFailureTransitionsDegradedWithoutRestart`
- `TestRelaySession_IgnoresCircuitAddressesWithoutReservationTruth`

**File:** `go-mknoon/node/node_test.go`

- `TestEventLoop_EmitsRelayStateOnReservationTransition`
- `TestStatus_ExposesAggregateRelayStateFields`
- `TestConnectednessLossEmitsRelayStateBeforeAddressesUpdated`
- `TestEventDispatcher_CoalescesRelayStateWithoutDroppingFinalState`

**File:** `go-mknoon/bridge/bridge_test.go`

- `TestNodeStatus_ContainsRelayStateFields`
- `TestBridgeEvent_ForwardsRelayStatePush`

#### Flutter unit

**File:** `test/core/bridge/go_bridge_client_test.dart`

- `relay state event is parsed and surfaced`

**File:** `test/core/services/p2p_service_impl_test.dart`

- `health decisions prefer relayState when present`
- `legacy circuitAddresses fallback is used only when relayState is absent`
- `relay state push updates connection status without waiting for addresses update`

### GREEN Targets

- replace the placeholder metrics landing point with a real tracer or adapter
  that drives relay-session transitions
- emit `relay:state` events from the Go side when reservation or connectedness
  changes occur
- extend `node:status` and live event handling so Flutter can reason from
  reservation-aware state
- change Flutter health evaluation to prefer `relayState` over inferred
  `circuitAddresses` truth

### Exit Criteria

- reservation lifecycle transitions reach the relay-session manager through
  real runtime hooks
- `relay:state` is emitted and consumed end to end
- a node can be marked degraded before circuit addresses disappear when the
  reservation truth is already bad
- Flutter online or degraded state is no longer driven primarily by empty or
  non-empty circuit address lists

### Commands

```bash
cd go-mknoon && go test ./node ./bridge -run 'RelaySession|Status|Event|Reservation'
flutter test test/core/bridge/go_bridge_client_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
```

---

## Phase 5 Re-open: Event-Driven Resume and Watchdog Recovery

### Current Audit Verdict

`reject`

Remaining gaps:

- the event-driven recovery path is actually keyed off `addresses:updated`
  losing circuit addresses, not a real `relay:state` event
- the real bridge returns `recoveryMode`, but Dart reads `recoveryMethod`
- the fake lifecycle bridge hides the mismatch by emitting the wrong field name

### RED Tests

#### Flutter unit

**File:** `test/core/bridge/go_bridge_client_test.dart`

- `relay reconnect parses recoveryMode from bridge response`
- `legacy recoveryMethod is not required for current behavior`

**File:** `test/core/lifecycle/connectivity_lifecycle_test.dart`

- `relay state degraded event triggers immediate recovery without waiting for timer`
- `addresses updated without relay degradation does not trigger event driven recovery`
- `resume and manual reconnect coalesce to one bridge recovery`
- `recovery branching uses recoveryMode`

**File:** `test/core/lifecycle/background_reconnect_smoke_test.dart`

- `relay state push restores online state without timer alignment`
- `watchdog restart branch is taken only when recoveryMode reports watchdog_restart`

**File:** `test/core/services/p2p_service_fault_injection_test.dart`

- `in place recovery is attempted before watchdog restart when relay state degrades`

### GREEN Targets

- drive immediate recovery from actual `relay:state` degradation or disconnect
  signals, not from indirect circuit-address loss alone
- read `recoveryMode` from the real bridge contract in Dart
- align `test/shared/fakes/lifecycle_bridge.dart` with the real payload shape
- keep the timer path as fallback only after event-driven recovery is wired

### Exit Criteria

- resume and relay degradation do not depend on timer alignment for recovery
- `recoveryMode` is the authoritative field end to end
- fake bridge behavior can no longer conceal contract drift
- immediate recovery remains coalesced across manual, lifecycle, and watchdog
  callers

### Commands

```bash
flutter test test/core/bridge/go_bridge_client_test.dart
flutter test test/core/lifecycle
flutter test test/core/services/p2p_service_fault_injection_test.dart
```

---

## Phase 6 Re-open: Group Continuity and Exactly-Once Recovery

### Current Audit Verdict

`reject`

Remaining gaps:

- cursor-based group inbox drain exists only on the Flutter side
- the real command map and native bridges do not expose
  `group:inboxRetrieveCursor`
- the Go client path is still timestamp-based
- group recovery runs on startup only, not on resume or watchdog recovery
- group discovery still redials on a fixed ticker without the planned cooldown,
  jitter, and concurrency controls

### RED Tests

#### Flutter and bridge contract

**File:** `test/core/bridge/bridge_group_helpers_test.dart`

- `group inbox retrieve cursor request encodes cursor and page metadata`

**File:** `test/core/bridge/go_bridge_client_test.dart`

- `group inbox retrieve cursor is exposed by the Go bridge client`

**File:** `go-mknoon/bridge/bridge_test.go`

- `TestGroupInboxRetrieveCursor_CommandExposed`
- `TestGroupInboxRetrieveCursor_PassesOpaqueCursor`

**File:** `integration_test/conversation_bridge_test.dart`

- `group inbox cursor command works on Android and iOS bridge hosts`

#### Flutter group recovery

**File:** `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

- `resume uses cursor continuation rather than timestamp guessing`
- `watchdog restart drains missed group messages exactly once`
- `first group inbox page returns before background continuation completes`

**File:** `test/features/groups/application/rejoin_group_topics_use_case_test.dart`

- `watchdog restart triggers group rejoin`
- `in place relay recovery skips unnecessary rejoin`

**File:** `test/core/lifecycle/connectivity_lifecycle_test.dart`

- `resume recovery schedules group drain when relay recovery succeeds`
- `watchdog restart result schedules group rejoin and drain`

#### Go unit and integration

**File:** `go-mknoon/node/group_inbox_test.go` or nearby group inbox tests

- `TestGroupInboxRetrieveCursor_StableAcrossPages`
- `TestGroupInboxRetrieveCursor_NoDuplicateOnContinuation`

**File:** `go-mknoon/node/pubsub_test.go`

- `TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures`
- `TestGroupRecoveryLimiter_JittersResumeBurst`
- `TestGroupRecoveryLimiter_CapsConcurrentRecoveryAcrossGroups`

**File:** `test/features/groups/integration/group_resume_recovery_test.dart`

- `resume drains missed group backlog exactly once`
- `watchdog restart rejoins topics and resumes live delivery`
- `multi page backlog uses cursor continuation without duplication`

### GREEN Targets

- expose `group:inboxRetrieveCursor` end to end across Go, Dart, Android, and
  iOS bridges
- move the Go-side group inbox retrieval contract to stable opaque cursor
  continuation
- trigger group rejoin and group inbox drain on resume and watchdog recovery,
  not only startup
- add backoff, jitter, and concurrency caps to group discovery and recovery
  work

### Exit Criteria

- cursor-based group catch-up works through the real bridges, not only Flutter
  helpers
- resume and watchdog recovery restore group continuity automatically
- group backlog catch-up remains exactly once across multi-page continuation
- group recovery no longer redials peers on a fixed synchronized ticker with no
  cooldown

### Commands

```bash
flutter test test/core/bridge/bridge_group_helpers_test.dart
flutter test test/core/bridge/go_bridge_client_test.dart
flutter test test/features/groups/application
flutter test test/features/groups/integration/group_resume_recovery_test.dart
cd go-mknoon && go test ./bridge ./node -run 'GroupInbox|GroupDiscovery|GroupRecovery'
flutter test integration_test/conversation_bridge_test.dart -d <device>
```

---

## Phase 7 Re-open: Watchdog, Chaos, and Deployment Validation

### Current Audit Verdict

`reject`

Remaining gaps:

- relay server still runs with `relay.WithInfiniteLimits()`
- finite `ServerLimits` scaffolding is not consumed at runtime
- rollout flags exist but are not proven to affect runtime behavior outside
  tests
- the tagged failover or watchdog gate still does not build

### RED Tests

#### Go relay server

**File:** `go-relay-server/limits_test.go`

- `TestRelayService_UsesFiniteLimitsFromServerConfig`
- `TestRelayService_RejectsExcessReservationsPredictably`
- `TestRelayService_EnforcesPerPeerConnectionCap`

**File:** `go-relay-server/main_test.go` or `go-relay-server/server_bootstrap_test.go`

- `TestServerBootstrap_UsesServerLimitsInsteadOfInfiniteRelayLimits`

#### Go node runtime flags

**File:** `go-mknoon/node/config_test.go`

- `TestFeatureFlags_DefaultsRemainBackwardCompatible`
- `TestStartNode_DisablesMultiRelayRoutingWhenFlagFalse`
- `TestReconnectRelays_DisablesInPlaceRecoveryWhenFlagFalse`
- `TestResumeGroupRecovery_DisabledWhenFlagFalse`

#### Tagged integration

**File:** `go-mknoon/integration/watchdog_failover_test.go`

- restore buildability first
- `TestSecondRelayAvailablePreventsWatchdogRestart`
- `TestAllRelaysUnavailableEnterDegradedStateAndRecover`
- `TestRendezvousAndInboxStillWorkAfterRelayRestart`

#### Flutter integration with fakes

**File:** `test/core/resilience/network_failover_test.dart`

- `relay A loss uses second relay before watchdog restart`
- `watchdog restart remains fallback when all relays fail`
- `runtime feature flags can disable new recovery behaviors intentionally`

#### Device and soak

**File:** `integration_test/multi_relay_failover_test.dart`

- `two relay failover keeps 1:1 delivery working`
- `two relay failover keeps group recovery working`

**File:** `integration_test/relay_chaos_soak_test.dart`

- `background resume and send remain stable for 30 to 60 minutes under relay churn`

### GREEN Targets

- replace `relay.WithInfiniteLimits()` with runtime-configured finite limits
- wire `ServerLimits` into the live relay bootstrap path
- make rollout flags affect real runtime paths, not only test constructors
- keep the tagged watchdog and failover integration slice as the acceptance
  proof for fallback behavior
- add or update rollout runbooks for enabling, disabling, and rolling back the
  major resilience features

### Exit Criteria

- relay overload behavior is finite and observable
- runtime flags can truly disable or stage the major resilience features
- second-relay success prevents unnecessary watchdog restart
- watchdog restart remains fallback only when in-place and failover recovery
  cannot keep the node healthy
- the tagged failover proof builds and passes

### Commands

```bash
cd go-relay-server && go test ./...
cd go-mknoon && go test ./node ./bridge
cd go-mknoon && go test -tags integration ./integration
flutter test test/core/resilience/network_failover_test.dart
flutter test integration_test/multi_relay_failover_test.dart -d <device>
flutter test integration_test/relay_chaos_soak_test.dart -d <device>
```

---

## Recommended Re-review Order

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
5. Phase 5
6. Phase 6
7. Phase 7

The order stays unchanged from the original plan. The only special handling is
that Phase 3 must be treated as `blocked` rather than reimplemented until the
tagged integration proof compiles and runs.

## Final Acceptance Gate

Do not mark the audited rollout complete until all of the following are true:

- each rejected phase has its new RED tests in place and green
- Phase 3 and Phase 7 tagged integrations build and pass
- fake bridges no longer hide field-name drift from real bridge payloads
- shared-backend proof uses real shared runtime state, not only two stores in
  one process
- startup, resume, relay recovery, and group recovery all have user-visible
  proof at the Flutter layer, bridge layer, and Go runtime layer
