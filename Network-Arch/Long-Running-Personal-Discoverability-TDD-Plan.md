# TDD Plan: Long-Running Personal Discoverability and Inbox-Only Degradation

## Problem

When two simulators stay open for a long time, 1:1 messages can degrade into
online inbox delivery even though both apps still appear alive. Restarting both
simulators restores live delivery.

The current evidence points to two related gaps:

1. Personal chat rendezvous registration is auto-registered at startup, but the
   current node code does not run a periodic personal re-registration loop.
   The relay registration TTL is 7200 seconds, so a long-lived node can become
   undiscoverable without actually crashing.
2. The current interactive send path does not use `relay:probe`. If personal
   discoverability is stale, `discoverPeer()` can return null and the sender
   can fall through to inbox even while the peer is still online.

The existing ACK-loss and half-open protections are still valid and must stay:
inbox remains the last-resort safety net when the live path cannot be trusted.

## Scope Contract

Allowed scope:

- personal 1:1 rendezvous refresh and re-registration
- relay-recovery-triggered personal re-registration
- targeted interactive-send fallback when discoverability is stale
- unit, integration, and simulator validation for this exact gap

Out of scope:

- group mesh or group inbox redesign
- relay-server shared-state work
- inbox semantics changes
- broad multi-relay architecture changes
- changing the ACK-loss safety-net product rule

## Phase Map

- Phase 0: Baseline Harness and Contract Locking
- Phase 1: Personal Rendezvous Refresh Loop
- Phase 2: Recovery-Triggered Personal Re-Registration
- Phase 3: Interactive Send Recovery After Discoverability Miss
- Phase 4: Long-Running QA and Regression Gates

## Phase 0: Baseline Harness and Contract Locking

### Goal

Encode the long-running regression as fast, deterministic tests before changing
production behavior.

### Production Scope

Likely files:

- `go-mknoon/integration/local_relay_harness_test.go`
- `go-mknoon/integration/relay_test.go`
- `go-mknoon/node/node_test.go`

### RED Tests

#### Go Integration Tests

**File:** `go-mknoon/integration/relay_test.go`

- `TestPersonalNamespaceRefresh_KeepsDiscoverablePastShortTTL`
  - Start node A against the local relay harness with a short TTL such as 5 s.
  - Start node B and verify A is discoverable immediately.
  - Leave A idle past TTL plus buffer.
  - Expected: B still discovers A without restarting A.
- `TestPersonalNamespaceRefresh_StopPreventsFurtherReRegistration`
  - Start node A with short TTL and verify initial discoverability.
  - Stop A, wait past TTL, then discover from B.
  - Expected: A is no longer discoverable after stop.

#### Go Unit Tests

**File:** `go-mknoon/node/node_test.go`

- `TestPersonalRendezvousRefreshLoop_DoesNotStartWhenAutoRegisterDisabled`
- `TestPersonalRendezvousRefreshLoop_StopsOnNodeStop`
- `TestPersonalRendezvousRefreshLoop_DoesNotDuplicateConcurrentTicks`

### GREEN Implementation

- Add only the minimum test hooks needed to drive short TTL behavior in tests.
- Keep those hooks internal to Go tests or package-private where possible.
- Do not ship product behavior changes in this phase beyond what the harness
  needs for later phases to compile.

### Exit Criteria

- A fast failing test exists for the long-running personal discoverability gap.
- The short-TTL harness can prove the difference between a live idle node and a
  stopped node.
- No unrelated transport behavior changed yet.

### Commands

```bash
cd go-mknoon
go test ./node -run 'PersonalRendezvousRefreshLoop'
go test -tags integration ./integration -run 'PersonalNamespaceRefresh'
```

---

## Phase 1: Personal Rendezvous Refresh Loop

### Goal

Keep a long-lived 1:1 node personally discoverable without requiring app or
node restart.

### Production Scope

Likely files:

- `go-mknoon/node/node.go`
- `go-mknoon/node/config.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/integration/relay_test.go`

### RED Tests

#### Go Unit Tests

**File:** `go-mknoon/node/node_test.go`

- `TestPersonalRendezvousRefreshInterval_IsSafelyBelowTTL`
- `TestPersonalRendezvousRefreshLoop_StartsAfterSuccessfulPersonalRegister`
- `TestPersonalRendezvousRefreshLoop_SkipsWhenNodeNotStarted`
- `TestPersonalRendezvousRefreshLoop_UsesConfiguredNamespace`

#### Go Integration Tests

**File:** `go-mknoon/integration/relay_test.go`

- `TestPersonalNamespaceRefresh_KeepsDiscoverablePastShortTTL`
  - This becomes the primary green test from Phase 0.
- `TestPersonalNamespaceRefresh_RefreshesBeforeExpiryUnderIdleNode`
  - Verify the node remains discoverable across multiple short TTL windows.

### GREEN Implementation

- Introduce a dedicated personal rendezvous refresh loop in the Go node.
- Run it only when all of these are true:
  - node is started
  - personal namespace is known
  - `AutoRegister` is enabled
- Start the loop only after the initial personal registration succeeds.
- Reuse the saved namespace and existing rendezvous register path.
- Stop the loop cleanly on `Stop()`.
- Serialize overlapping refresh ticks so slow relay responses do not create
  duplicate register calls.
- Choose a refresh interval with a large safety margin under TTL. Keep it
  configurable for tests; keep the production default conservative.

### Exit Criteria

- A node left running past the short TTL remains discoverable without restart.
- Stopping the node cancels future personal registrations.
- The refresh loop does not run when `AutoRegister` is disabled.
- No group discovery behavior changed.

### Commands

```bash
cd go-mknoon
go test ./node -run 'PersonalRendezvousRefresh'
go test -tags integration ./integration -run 'PersonalNamespaceRefresh'
```

---

## Phase 2: Recovery-Triggered Personal Re-Registration

### Goal

Restore personal discoverability immediately after relay recovery instead of
waiting for the next periodic personal refresh tick.

### Production Scope

Likely files:

- `go-mknoon/node/node.go`
- `go-mknoon/node/relay_session.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/integration/relay_test.go`
- `go-mknoon/integration/watchdog_failover_test.go`

### RED Tests

#### Go Unit Tests

**File:** `go-mknoon/node/node_test.go`

- `TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess`
- `TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace`
- `TestRecoveryCoalescing_PerformsSinglePersonalReregister`

#### Go Integration Tests

**File:** `go-mknoon/integration/relay_test.go`

- `TestPersonalNamespaceRecovery_ReRegistersAfterInPlaceRefresh`
  - Drop personal discoverability or relay health, recover in place, then
    discover from another node.
  - Expected: discoverability returns promptly without app restart.
- `TestPersonalNamespaceRecovery_ReRegistersAfterWatchdogRestart`
  - Force the watchdog path and verify personal discoverability is restored.

### GREEN Implementation

- On successful in-place relay refresh, immediately re-register the personal
  namespace when `AutoRegister` is enabled.
- On successful watchdog restart, immediately re-register the personal
  namespace after the node becomes healthy.
- Reuse the same registration guard used by the periodic personal loop so
  timer ticks, resume recovery, and watchdog recovery cannot overlap.
- Keep the change additive: no group rejoin logic should move into this phase.

### Exit Criteria

- Relay recovery restores personal discoverability without waiting for the next
  periodic personal refresh interval.
- In-place refresh and watchdog restart both preserve personal chat presence.
- Overlapping recovery callers do not trigger duplicate personal registrations.

### Commands

```bash
cd go-mknoon
go test ./node -run 'RefreshRelaySession|WatchdogRestart|PersonalNamespaceRecovery'
go test -tags integration ./integration -run 'PersonalNamespaceRecovery|Watchdog'
```

---

## Phase 3: Interactive Send Recovery After Discoverability Miss

### Goal

Prevent stale personal discoverability from forcing inbox fallback when the
peer is still online and reachable through the relay.

### Production Scope

Likely files:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/core/resilience/c2_ack_drop_test.dart`
- `test/core/resilience/c3_half_open_test.dart`

### RED Tests

#### Flutter Unit Tests

**File:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

- `discover miss then relay probe connected sends live without inbox`
  - `discoverPeer()` returns null
  - `probeRelay()` returns `connected`
  - `sendMessageWithReply()` succeeds
  - Expected: success, no inbox store, transport is live
- `discover miss then relay probe noReservation falls to inbox`
  - `discoverPeer()` returns null
  - `probeRelay()` returns `noReservation`
  - Expected: inbox fallback once
- `discover miss then relay probe error preserves inbox fallback`
  - `discoverPeer()` returns null
  - `probeRelay()` returns `error`
  - Expected: existing fallback behavior, no hang
- `connected fast path skips relay probe`
- `local wifi fast path skips relay probe`
- `probe-connected send with lost ACK still uses inbox safety net`

#### Flutter Resilience Tests

**File:** `test/core/resilience/c2_ack_drop_test.dart`

- Extend ACK-drop coverage so a probe-assisted live send still hands off to
  inbox when ACK is lost.

**File:** `test/core/resilience/c3_half_open_test.dart`

- Extend half-open coverage so a stale discoverability miss plus
  `probeRelay == connected` does not fall straight to inbox.

### GREEN Implementation

- Keep the existing ordering for the fast paths:
  - existing connected peer
  - local WiFi
  - direct discover/dial/send
- Add relay probe only after the direct path fails because the peer could not
  be discovered or could not be dialed.
- If `probeRelay()` returns `connected`, attempt one live send on the now-live
  relay connection before using inbox.
- If `probeRelay()` returns `noReservation`, go directly to inbox.
- If `probeRelay()` returns `error`, preserve the existing failure/inbox path.
- Do not reintroduce probe-before-every-send latency on the happy path.

### Exit Criteria

- A stale or expired personal discovery record no longer forces inbox when the
  peer is still online.
- Happy-path latency for already-connected peers and local WiFi peers is
  unchanged.
- ACK-loss and half-open inbox safety-net behavior is preserved.

### Commands

```bash
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/core/resilience/c2_ack_drop_test.dart
flutter test test/core/resilience/c3_half_open_test.dart
```

---

## Phase 4: Long-Running QA and Regression Gates

### Goal

Prove the fix in the layers that match the real symptom: long-lived apps,
recovery after idle time, and no restart required to regain live delivery.

### Production Scope

Likely files:

- `test/core/services/p2p_service_fault_injection_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `integration_test/transport_e2e_test.dart` or a focused new test
- `Testing-Tracking/` runbook entry if needed

### RED Tests

#### Flutter Smoke / Fault Injection

**File:** `test/core/services/p2p_service_fault_injection_test.dart`

- `expired personal discoverability plus live relay still sends without inbox`
- `post-recovery send does not require simulator restart to regain live path`

**File:** `test/core/lifecycle/background_reconnect_smoke_test.dart`

- `long background duration plus personal refresh still returns online and discoverable`

#### Optional Device / Simulator Validation

Add or document a shortened manual scenario:

1. Run two simulators against a short-TTL test relay.
2. Leave both open past TTL without restarting.
3. Send both directions.
4. Expected: live delivery resumes without requiring restart; inbox is used only
   when live path actually fails.

### GREEN Implementation

- Add the smallest device or simulator validation that proves the repaired
  long-running behavior.
- Document the manual soak scenario if a fully automated simulator test is not
  practical in the current environment.
- Record the commands and expected transport evidence for future regressions.

### Exit Criteria

- The shortened long-running scenario no longer reproduces inbox-only behavior.
- Restart is no longer required to restore live delivery after TTL-scale idle
  time.
- The regression has automated coverage in Go plus Flutter, with optional
  device validation documented.

### Commands

```bash
flutter test test/core/services/p2p_service_fault_injection_test.dart
flutter test test/core/lifecycle/background_reconnect_smoke_test.dart
flutter test integration_test/transport_e2e_test.dart -d <device>
```

## Initial Controller State

- Active phase: `Phase 0`
- Acceptance decision: `implement`
- Next state after Phase 0:
  - `implement Phase 1` only if the short-TTL regression test exists and fails
    for the right reason
