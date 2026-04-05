# 66 - Immediate Event-Driven Group Recovery on needsGroupRecovery

**Feature Improvement**

## Problem Statement

When the Go relay signals that group recovery is needed
(`needsGroupRecovery=true` via `relay:state` push), the Dart side receives the
signal in `P2PServiceImpl._handleRelayStateChanged()` (line 1656) and stores it
in `NodeState` — but has no immediate forward path to trigger group recovery.
The `PendingMessageRetrier` only acts on this signal at its next scheduled tick:
either the 30-second group continuity sweep or the 5-minute full retry, whichever
fires first.

This means the app can sit idle for up to 30 seconds after the relay explicitly
says "you need to rejoin your groups" before any recovery begins. During that
gap, GossipSub messages are silently missed because the subscriptions are stale.

The gap matters because:
- The `relay:state` push fires on relay reconnection — precisely the moment when
  topics most need rejoining.
- The existing `handleAppResumed` path already handles this correctly for
  background→foreground transitions (immediate rejoin + drain + ack), but
  foreground relay reconnections have no equivalent fast path.
- The retrier's `rejoinGroupTopicsFn` already checks `needsGroupRecovery` to
  determine the rejoin reason (`main.dart:1356–1363`), so the wiring is aware
  of the signal — it just can't act on it immediately.

The trigger contract is: when `needsGroupRecovery` transitions from `false` to
`true` while the retrier is in the online state, an immediate group continuity
sweep is initiated — not deferred to the next timer tick. Repeated `true→true`
broadcasts do not re-trigger; only the `false→true` edge fires the immediate
path.

Additionally, the current `PendingMessageRetrier` has no
`group:acknowledgeRecovery` call after a successful rejoin — regardless of
whether the rejoin was triggered by the new immediate path, the 30-second timer,
or the 5-minute full retry. Only `handleAppResumed` sends the ack
(`handle_app_resumed.dart:158–168`). This means any retrier-owned rejoin that
runs with `RejoinReason.nodeRequestedRecovery` and succeeds leaves the Go side's
`needsGroupRecovery` flag set indefinitely, causing repeated full-rejoin sweeps
on every subsequent timer tick until an app resume eventually clears it.

Only users with active groups are affected. The impact is most visible when the
relay reconnects while the app is in the foreground — a scenario that occurs
during network transitions (Wi-Fi→cellular, poor connectivity areas).

## Impact Analysis

| Scenario | Current behavior | Consequence |
|---|---|---|
| Relay reconnects while app is foregrounded | `needsGroupRecovery=true` stored in NodeState; no immediate action | Up to 30s gap where group messages are missed |
| Relay reconnects while app is backgrounded | `handleAppResumed` fires on foreground, does immediate rejoin + ack | Already handled — no gap |
| `needsGroupRecovery=true` persists across retrier ticks | Retrier passes `nodeRequestedRecovery` reason → full rejoin every tick | Unnecessary per-group bridge calls every 30s until app resume acks |
| 30s sweep runs with `inPlaceRecovery` reason (healthy state) | `rejoinGroupTopics` exits early at line 58 — no per-group work | Low cost; only the inbox drain runs per group |

**Severity:** Messages silently missed during relay reconnection gap (up to 30s).
Recovery flag never cleared by retrier causes repeated unnecessary full rejoins.

**Frequency:** Each relay reconnection while foregrounded. Frequency depends on
network stability — more common on mobile networks.

**Workaround:** Backgrounding and foregrounding the app triggers
`handleAppResumed`, which has the correct immediate recovery + ack path.

## Current State

### PendingMessageRetrier Timer Architecture

**File:** `lib/core/services/pending_message_retrier.dart`

| Constant | Value | Line | Purpose |
|---|---|---|---|
| `defaultRetryDebounce` | 5 seconds | 20 | Debounce after online transition |
| `defaultPeriodicRetryInterval` | 5 minutes | 21 | Full retry sweep (groups + 1:1) |
| `defaultGroupContinuitySweepInterval` | 30 seconds | 23 | Group-only rejoin + drain |

Three timers start when the node goes online (`_startOnlineTimers`, line 149):
- `_debounceTimer` (5s one-shot) → triggers `_retryIfNeeded` (full retry)
- `_periodicTimer` (5m periodic) → triggers `_retryIfNeeded` (full retry)
- `_groupContinuityTimer` (30s periodic) → triggers `_runGroupContinuitySweepIfNeeded` (group-only)

### Group Continuity Sweep Logic

**File:** `lib/core/services/pending_message_retrier.dart`, lines 179–224

Guards (in order):
1. `_isGroupContinuitySweeping` — skip if already sweeping
2. `_isRetrying` — skip if full retry in progress
3. `_isGroupRecoveryEnabled()` — skip if feature disabled
4. `rejoinGroupTopicsFn == null && drainGroupOfflineInboxFn == null` — skip if
   not wired
5. `_isExternalRecoveryInProgressFn` — skip if app resume recovery active

When no guard blocks, sequentially calls:
- `rejoinGroupTopicsFn()` → `rejoinGroupTopics` use case
- `drainGroupOfflineInboxFn()` → `drainGroupOfflineInbox` use case

**No `group:acknowledgeRecovery` call exists anywhere in this class.**

### rejoinGroupTopicsFn Wiring in main.dart

**File:** `lib/main.dart`, lines 1355–1369

The closure checks `p2pService.currentState.needsGroupRecovery` at call time:
- `needsGroupRecovery == true` → passes `RejoinReason.nodeRequestedRecovery`
  (full per-group rejoin)
- `lastRecoveryMethod == 'watchdog_restart'` → passes
  `RejoinReason.watchdogRestart` (full per-group rejoin)
- Otherwise → passes `RejoinReason.inPlaceRecovery` (early exit, no per-group
  work)

This means the common healthy 30s sweep is cheap (rejoin exits immediately at
`rejoin_group_topics_use_case.dart:58`). The per-group cost only applies when
`needsGroupRecovery` is true — which is precisely the case that currently lacks
an ack to clear it.

### rejoinGroupTopics Use Case

**File:** `lib/features/groups/application/rejoin_group_topics_use_case.dart`,
lines 51–80

- `RejoinReason.inPlaceRecovery` → returns immediately with
  `RejoinGroupTopicsResult(skipped: true)` (line 58–79)
- All other reasons → iterates groups, calls `callGroupJoinWithConfig` per group

### Recovery Ack Contract

**File:** `lib/core/lifecycle/handle_app_resumed.dart`, lines 158–168

After a successful rejoin where `needsGroupRecovery` was true:
```
if (needsGroupRecovery && rejoinResult.errorCount == 0) {
  await callGroupAcknowledgeRecovery(bridge);
}
```

**File:** `lib/core/bridge/bridge_group_helpers.dart`, lines 191–224

`callGroupAcknowledgeRecovery(bridge)` sends `group:acknowledgeRecovery` to Go,
which clears the pending recovery signal so subsequent state pushes no longer
set `needsGroupRecovery=true`.

**The retrier has no equivalent.** When the retrier's 30s sweep runs with
`needsGroupRecovery=true`, it does the full rejoin but never acks. The flag
stays set. Next tick, it does the full rejoin again. This repeats until the user
backgrounds and foregrounds the app (triggering `handleAppResumed`'s ack path).

### Relay State Event Path

**File:** `lib/core/services/p2p_service_impl.dart`, lines 1656–1729

- Go emits `relay:state` push with `needsGroupRecovery` flag
- `_handleRelayStateChanged` stores the flag in `NodeState` and broadcasts
- `PendingMessageRetrier` subscribes to `stateStream` but only uses it for
  online/offline transitions — not for `needsGroupRecovery` changes

### drainGroupOfflineInbox Use Case

**File:** `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`,
lines 26–98

- Iterates all groups, fetches inbox messages per group via Go bridge
- Processes each message through `groupMessageListener.handleReplayEnvelope()`
- Drains all pages by default
- Runs on every 30s sweep regardless of `needsGroupRecovery` state

### Existing Tests

**File:** `test/core/services/pending_message_retrier_test.dart` (~310 lines)

| Test | Lines | Covered |
|---|---|---|
| State subscription on start | 42 | Yes |
| Offline→online triggers debounced retry | 50–71 | Yes |
| Online→offline no additional retry | 73–102 | Yes |
| Online without circuit addresses not treated as online | 104–121 | Yes |
| Dispose cancels timers | 123–136 | Yes |
| Debounce resets on rapid state changes | 138–169 | Yes |
| `_isRetrying` guard prevents concurrent retries | 171–195 | Yes |
| External recovery skips sweep | 197–245 | Yes |
| Group continuity sweep runs at 30s cadence | 247–308 | Yes |

**Not covered:** relay-driven immediate sweep, recovery ack after retrier-driven
rejoin, `needsGroupRecovery` flag persisting across ticks.

**Related test files:**
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` — covers
  the resume path's ack behavior
- `test/core/bridge/bridge_group_helpers_test.dart:670` — covers
  `callGroupAcknowledgeRecovery` bridge call

## Scope Clarification

| Area | Status | Notes |
|---|---|---|
| `PendingMessageRetrier`: react to `needsGroupRecovery` `false→true` edge while online | In scope | New event-driven trigger |
| `PendingMessageRetrier`: ack after any successful `nodeRequestedRecovery` rejoin | In scope | Missing ack contract — applies to immediate path, 30s timer, and 5m full retry equally |
| `PendingMessageRetrier`: accept bridge dependency for ack call | In scope | Needs `Bridge` or ack callback |
| Existing 30s group continuity timer | Unchanged | Kept as fallback for silent degradation |
| Existing 5m full retry timer | Unchanged | Kept as-is |
| `rejoinGroupTopics` use case | Unchanged | Called the same way |
| `drainGroupOfflineInbox` use case | Unchanged | Called the same way |
| `handleAppResumed` lifecycle handler | Unchanged | Already has correct immediate + ack path |
| Adaptive timer interval / backoff | Out of scope | Separate follow-up if desired |
| Go `groupPeerDiscoveryLoop` interval | Out of scope | Independent Go-side concern |
| Inbox cursor persistence | Out of scope | Separate optimization |
| GossipSub heartbeat tuning | Out of scope | Internal to go-libp2p-pubsub |

## Test Cases

### Group 1: Immediate Recovery on needsGroupRecovery

**TC-66-01** — `needsGroupRecovery` transitions `false→true` while online;
immediate sweep triggers.
PendingMessageRetrier is running with online timers active.
`needsGroupRecovery` is currently `false`. P2P service broadcasts a state update
with `needsGroupRecovery=true` (relay reconnected).
Expected: `_runGroupContinuitySweepIfNeeded` is called synchronously from the
state listener callback — not deferred to the next 30s or 5m tick.
`rejoinGroupTopicsFn` runs with `nodeRequestedRecovery` reason.
`drainGroupOfflineInboxFn` runs after rejoin completes. The sweep executes within
the same microtask queue drain as the state broadcast.

**TC-66-02** — `needsGroupRecovery` stays `false`; no immediate sweep.
P2P service broadcasts a state update with `needsGroupRecovery=false` (was
already `false`). No `false→true` edge detected.
Expected: no immediate sweep triggered. The existing 30s and 5m timers continue
on their normal cadence.

**TC-66-02b** — `needsGroupRecovery` stays `true` across broadcasts; no
duplicate immediate sweep.
`needsGroupRecovery` is already `true` (previous edge already triggered a
sweep). P2P service broadcasts another state update with
`needsGroupRecovery=true` (e.g., a health metric refresh, not a new recovery
signal).
Expected: no additional immediate sweep. The edge was already consumed. The
existing 30s timer handles continued `true` state normally.

**TC-66-03** — Multiple rapid `needsGroupRecovery=true` signals coalesce.
Three state broadcasts with `needsGroupRecovery=true` arrive within 1 second.
Expected: only one sweep executes. Subsequent signals are deduplicated by the
`_isGroupContinuitySweeping` guard or a debounce.

**TC-66-04** — `needsGroupRecovery=true` arrives while app resume is in progress.
`handleAppResumed` is running (external recovery gate active). A state broadcast
with `needsGroupRecovery=true` arrives.
Expected: retrier sweep is skipped (logged as `SKIPPED_EXTERNAL_RECOVERY`). The
app resume path handles recovery and ack.

### Group 2: Recovery Acknowledgment

**TC-66-05** — Immediate sweep: successful rejoin sends ack.
`needsGroupRecovery` transitions `false→true`, triggering an immediate sweep.
`rejoinGroupTopicsFn` completes with `nodeRequestedRecovery` reason and no
errors.
Expected: `group:acknowledgeRecovery` is sent to the Go bridge after rejoin.
Subsequent state broadcasts show `needsGroupRecovery=false`.

**TC-66-06** — 30s timer sweep: successful `nodeRequestedRecovery` rejoin sends
ack.
`needsGroupRecovery` is `true` (e.g., immediate sweep was guarded out). The 30s
timer fires. `rejoinGroupTopicsFn` runs with `nodeRequestedRecovery` reason and
succeeds.
Expected: `group:acknowledgeRecovery` is sent. The ack rule is the same
regardless of which trigger (immediate, 30s, or 5m) initiated the sweep.

**TC-66-07** — 5m full retry: successful `nodeRequestedRecovery` rejoin sends
ack.
`needsGroupRecovery` is `true`. The 5m periodic timer fires `_retryIfNeeded`.
`rejoinGroupTopicsFn` runs with `nodeRequestedRecovery` reason and succeeds.
Expected: `group:acknowledgeRecovery` is sent after the rejoin step, before
proceeding to the drain and remaining retry steps.

**TC-66-08** — Failed rejoin does NOT send ack (any trigger).
`needsGroupRecovery=true`. `rejoinGroupTopicsFn` throws an exception.
Expected: `group:acknowledgeRecovery` is NOT sent regardless of which trigger
initiated the sweep. The recovery signal remains set. The next timer tick or
`false→true` edge will attempt recovery again.

**TC-66-09** — Ack is NOT sent when sweep runs with `inPlaceRecovery` reason.
The 30s timer fires during healthy state (`needsGroupRecovery=false`). Rejoin
exits early with `skipped: true`.
Expected: `group:acknowledgeRecovery` is NOT sent (no recovery was needed).

**TC-66-10** — After ack, subsequent 30s sweeps use `inPlaceRecovery` reason.
`needsGroupRecovery=true` → rejoin succeeds → ack sent → Go clears the flag →
next state broadcast has `needsGroupRecovery=false`.
Expected: the next 30s timer tick calls `rejoinGroupTopicsFn` which resolves to
`inPlaceRecovery` (early exit). No per-group bridge calls.

**TC-66-11** — Without ack, `needsGroupRecovery` stays true across ticks
(regression baseline).
Simulate the current behavior (no ack): `needsGroupRecovery=true` → 30s sweep
runs full rejoin → flag remains true → next 30s sweep runs full rejoin again.
Expected: this is the regression baseline. The fix must break this cycle by
adding the ack to all retrier-owned paths.

### Group 3: Guard Interactions

**TC-66-12** — Immediate sweep respects `_isRetrying` guard.
A full retry (`_retryIfNeeded`) is in progress. A `false→true` edge on
`needsGroupRecovery` arrives.
Expected: immediate sweep is skipped because `_isRetrying` is true. The full
retry already includes the rejoin step and will handle recovery (and ack).

**TC-66-13** — Immediate sweep respects `_isGroupContinuitySweeping` guard.
A group sweep is already running. A `false→true` edge on
`needsGroupRecovery` arrives.
Expected: the second sweep is skipped. The first sweep completes normally.

**TC-66-14** — Immediate sweep respects feature kill switch.
Group recovery is disabled via `enableResumeGroupRecovery`. A `false→true` edge
on `needsGroupRecovery` arrives.
Expected: no sweep runs. The signal is ignored.

**TC-66-15** — Immediate sweep respects offline state.
PendingMessageRetrier is in offline state (no circuit addresses). A state
broadcast with `needsGroupRecovery=true` arrives (e.g., stale push).
Expected: no sweep runs. Recovery only applies when online.

### Group 4: Fallback Timer (Regression)

**TC-66-16** — 30s timer still fires as fallback when no events arrive.
User is online with active groups. No relay state events occur for 2 minutes.
Expected: the 30s group continuity timer fires normally, calling
`rejoinGroupTopicsFn` (which resolves to `inPlaceRecovery` and exits early) and
`drainGroupOfflineInboxFn`.

**TC-66-17** — 30s timer cadence is unchanged.
Expected: `defaultGroupContinuitySweepInterval` remains 30 seconds. The timer
continues to fire at 30s intervals regardless of the new event-driven path.

**TC-66-18** — Full 5m retry still includes group recovery steps and acks.
The 5-minute periodic timer fires with `needsGroupRecovery=true`.
Expected: `_retryIfNeeded` runs the full ordering contract including group rejoin
+ drain + recover stuck + retry uploads + retry failed, followed by 1:1 steps.
After a successful `nodeRequestedRecovery` rejoin, `group:acknowledgeRecovery`
is sent.

### Group 5: Live Message Delivery (Regression)

**TC-66-19** — Live GossipSub messages arrive instantly regardless of sweep.
Two peers are connected with healthy GossipSub mesh. Peer A sends a message.
Expected: Peer B receives the message within 1 second via EventChannel. The
sweep timer and event-driven path have no involvement in live delivery.

**TC-66-20** — Live messages continue during a recovery sweep.
An event-driven recovery sweep is in progress. A live GossipSub message arrives.
Expected: the live message is delivered immediately via the message stream
listener. The sweep does not block live delivery.

**TC-66-21** — Messages sent during relay reconnection gap are recovered.
Peer A sends 3 messages while Peer B's relay connection is temporarily broken.
Relay reconnects, `needsGroupRecovery` transitions `false→true`.
Expected: the immediate sweep triggers rejoin + inbox drain, recovering the 3
messages. `group:acknowledgeRecovery` is sent after successful rejoin.

### Group 6: Error Paths

**TC-66-22** — rejoinGroupTopics fails; drain still runs; no ack sent.
`rejoinGroupTopicsFn` throws during a sweep (any trigger).
Expected: error logged as `PENDING_RETRIER_GROUP_REJOIN_ERROR`. Drain still
executes. `group:acknowledgeRecovery` is NOT sent. `_isGroupContinuitySweeping`
is reset to false.

**TC-66-23** — drainGroupOfflineInbox fails; sweep completes; ack still sent
if rejoin succeeded.
`rejoinGroupTopicsFn` succeeds with `nodeRequestedRecovery` but
`drainGroupOfflineInboxFn` throws.
Expected: error logged as `PENDING_RETRIER_GROUP_DRAIN_ERROR`. Since rejoin
succeeded, `group:acknowledgeRecovery` IS sent (the ack depends on rejoin
success, not drain success — matching `handleAppResumed` behavior).

**TC-66-24** — ack call itself fails; sweep completes without crashing.
`rejoinGroupTopicsFn` succeeds with `nodeRequestedRecovery`.
`group:acknowledgeRecovery` bridge call throws.
Expected: error logged. `_isGroupContinuitySweeping` is reset. The recovery
flag remains set on Go side; the next tick or `false→true` edge will retry.

### Group 7: Dispose and Cleanup

**TC-66-25** — Disposing retrier removes state listener for `needsGroupRecovery`.
PendingMessageRetrier is disposed while a `needsGroupRecovery`-triggered sweep
is pending.
Expected: the pending sweep does not fire. State subscription is cancelled. No
ack is sent.

**TC-66-26** — Going offline cancels timers but does not clear pending recovery.
P2P service transitions to offline. `needsGroupRecovery` was true.
Expected: `_groupContinuityTimer` is cancelled. No sweep fires while offline.
On next online transition, the debounced retry fires and handles recovery
(including ack if rejoin succeeds).
