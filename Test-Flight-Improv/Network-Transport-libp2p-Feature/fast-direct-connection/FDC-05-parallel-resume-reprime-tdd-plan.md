# FDC-05 — Parallel (not serial) resume re-prime  (Modification)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.4 "Lifecycle handshake
+ graceful handoff" → resume bullet; recommendation **P1-2**)

## Source Of Truth
- **Proposal §6.4**, the resume bullet (lines 269-272): *"On resume/notif-tap: run relay re-prime +
  mDNS restart + peer warm + inbox drain **in parallel** with foreground 3s budgets — **not**
  serialized behind an awaited drain as today (`handle_app_resumed.dart:136-191`). Keep the existing
  'catching up…' affordance for the unawaited drain."*
- **Proposal §4 R5 / §8 P1-2** (line 114, 356): resume re-establishment is serial + awaited on the
  single Go bridge → "resume latency couples onto send latency."
- **`scripts/run_test_gates.sh` wins over prose.** The `ONE_TO_ONE_TESTS` array (line 31) already
  curates `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`; the `TRANSPORT_TESTS`
  array (lines 164-168) curates `background_reconnect_test.dart`. Those are the literal locks.
- Epic roadmap: FDC-00 (this folder). This is the lifecycle slice; warm-peer (P0-1) and the
  concurrent-inbox send-path change (P0-2/P0-3) are sibling plans, **not** in scope here.

## Session Classification
**implementation-ready.** Every seam is host-verifiable against existing fakes
(`FakeP2PService`, `FakeBridge`) at the application tier. No relay/Go deploy, no migration. The only
device-gated claim (real over-the-wire resume reconnect) is covered by an existing transport
integration test run as a preservation gate; new behavior is fully host-provable.

## Exact Problem Statement
**What's broken.** `handleAppResumed` (`lib/core/lifecycle/handle_app_resumed.dart:130-191`) runs the
resume re-prime **strictly serially**:

1. `await bridge.checkHealth()` (+`reinitialize()` if dead) — `:136`/`:145`
2. `await p2pService.performImmediateHealthCheck()` — `:163` (re-dials relay, re-registers FCM,
   restarts mDNS advertising internally — see `p2p_service_impl.dart:3985-3999`)
3. `await retryPushRegistrationFn()` — `:176`
4. **`await p2pService.drainOfflineInbox()`** — `:189` (a relay round-trip: retrieve → decrypt →
   persist → emit). This awaited network drain is what couples recovery latency onto the resume
   future, which the first post-resume send sits behind.

**Who feels it.** A user who backgrounds, then re-opens the app (or taps a notification) and
immediately sends a message: the send is queued behind a resume future that is itself blocked on a
multi-second awaited inbox drain. The reported "open app → send one message → close feels slow."

**What must improve.** The relay/mDNS re-prime (step 2) and the inbox drain (step 4) must **overlap**
(run concurrently, each bounded by the foreground 3s budgets in `go-mknoon/node/config.go:39-41`),
and the inbox drain must be **fire-and-forget (unawaited)** so the resume future no longer blocks on
it. The first send must not wait behind the drain.

**What must stay unchanged (preserved sentinels).**
- **The Step-8 outbound recovery sweep stays strictly ordered**: `recoverStuckSendingMessages →
  retryIncompleteUploads → retryFailedMessages → retryUnackedMessages → verifyInboxCustody →
  retryPendingIntroductionDeliveries` (locked by `handle_app_resumed_upload_ordering_test.dart`).
- **`bridge.checkHealth()`/`reinitialize()` stays first** — it is a hard precondition; everything
  downstream uses the bridge.
- **141 deferral**: `drainOfflineInbox` still no-ops-and-defers when `!isStarted`
  (`p2p_service_impl.dart:4014-4017`) — making it unawaited must not change that.
- **The "catching up…" affordance** (`isSyncingNewMessages` banner) keeps showing for the in-flight
  drain.
- **Drain coalescing** (`_drainOfflineInbox` single-in-flight guard,
  `p2p_service_impl.dart:1670-1697`) and the 158/159 idle `scheduleFrame()` corollary stay correct.

## Root Cause (verify→refute confirmed)
- **Mechanism (confirmed by Read):** `handle_app_resumed.dart:189` is `await
  p2pService.drainOfflineInbox();` — a serial `await` inside the resume `try` block, executed after
  the awaited `performImmediateHealthCheck()` at `:163`. The resume future therefore = checkHealth +
  healthCheck + push + **drain** + step-8, all serialized. Verified the drain is a real network
  round-trip via `p2p_service_impl.dart:4010-4027 → _drainOfflineInbox :1670 → _drainOfflineInboxDurably
  :1763`.
- **mDNS restart already lives inside `performImmediateHealthCheck`** (`p2p_service_impl.dart:3990-3999
  _localP2P?.restartAdvertising()`), and `performImmediateHealthCheck` already coalesces concurrent
  recovery (`:3966-3981`). So "relay re-prime + mDNS restart" is one already-bounded call; the only
  thing serialized against it that we must un-serialize is the **drain**.
- **Refuted / do-NOT-re-introduce:**
  - Do **NOT** also un-serialize `bridge.checkHealth()` — refuted: the bridge must be healthy/
    reinitialized before `performImmediateHealthCheck` or `drainOfflineInbox` can use it. Keep it
    first.
  - Do **NOT** add a second, resume-level "catching up" banner — refuted: the affordance is already
    driven by the **conversation surface's own** drain
    (`conversation_wired.dart:1178/1195-1263 → conversation_screen.dart:360 _ConversationSyncingBanner`),
    not by the resume drain. Making the resume drain unawaited does not touch that path.
  - Do **NOT** cap the cold relay dial here — that is FDC's P1-3 (proposal §8 warns against blind
    3s-capping the cold `DialTimeout`); this plan only un-serializes the **foreground** resume path
    that already runs under the 3s foreground budgets.
  - Do **NOT** parallelize the Step-8 outbound sweep — it must stay strictly ordered.

## Real Scope
**In scope.**
- `lib/core/lifecycle/handle_app_resumed.dart`: kick `performImmediateHealthCheck` and
  `drainOfflineInbox` off concurrently after `bridge.checkHealth`; await only the bounded re-prime
  (+push); make the inbox drain **unawaited** with its own `catchError` (fault isolation); emit a
  distinct `APP_LIFECYCLE_RESUME_REPRIME_PARALLEL` discriminator event.
- Test-only: add a gateable `onPerformImmediateHealthCheck` Completer hook to `FakeP2PService` so a
  test can hold the re-prime open and observe the drain firing concurrently.

**Out of scope (owning FDC-xx).**
- LAN-aware `warmPeer` on resume (proposal P0-1) → **FDC-04**.
- Concurrent durable-inbox-on-send / online→inbox mis-route (P0-2/P0-3) → **send-path FDC plans**.
- iOS `beginBackgroundTask` pause-flush (the other half of §6.4 P1-2) → **FDC pause-flush plan**.
- Cold-start earlier reserve / re-timing the 15s `DialTimeout` (P1-3) → **FDC cold-start plan**.
- Any relay/Go change; any Go transport labelling (Go only labels transport; the path decision lives
  in Dart).

## Files To Inspect Next
**Production entry / use-case:**
- `lib/core/lifecycle/handle_app_resumed.dart` — `:130-191` (the serial re-prime), `:738-749` (outer
  catch), `:534-712` (Step-8 sweep), `:725-735` (RESUME_COMPLETE emit). **Primary edit.**
- `lib/main.dart:4366` — `_onResumed()` awaits `handleAppResumed`; no change, but the caller is the
  reason the first send sits behind the resume future.

**Service surface (read-only context — already correct):**
- `lib/core/services/p2p_service_impl.dart` — `performImmediateHealthCheck :3952-4007` (relay re-dial
  + FCM + mDNS restart + coalesce), `drainOfflineInbox :4010-4028` (141 defer + coalesce),
  `_drainOfflineInbox :1670-1697`.
- `lib/core/services/p2p_service.dart:170/173` — the two method signatures.

**Affordance (read-only — must not regress):**
- `lib/features/conversation/presentation/screens/conversation_wired.dart:1178,1195-1263`
- `lib/features/conversation/presentation/screens/conversation_screen.dart:357-360,1099-1104`

**Go budgets (read-only — cite, do not edit):**
- `go-mknoon/node/config.go:39-41` — `ForegroundRelayDialTimeout/ReserveTimeout/CircuitAddressWaitTimeout
  = 3s`.

**Tests (direct + integration):**
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart` (existing — Step-8 lock).
- `test/core/services/fake_p2p_service.dart` (extend with re-prime gate hook).
- `test/core/bridge/fake_bridge.dart` (dependency-only context).
- `integration_test/background_reconnect_test.dart` (transport gate — preservation).

## Existing Tests Covering This Area
| Test | Exists? | Gate array |
|---|---|---|
| `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart` | EXISTS — locks the Step-8 sweep order + per-step fault isolation | `ONE_TO_ONE_TESTS[31]` |
| `test/features/conversation/integration/offline_inbox_roundtrip_test.dart` | EXISTS — inbox drain round-trip | `BASELINE_TESTS[11]`, `ONE_TO_ONE_TESTS[19]` |
| `test/core/services/p2p_service_impl_test.dart` | EXISTS — drain coalescing / 141 defer | `ONE_TO_ONE_TESTS[48]` |
| `integration_test/background_reconnect_test.dart` | EXISTS — resume reconnect over the wire | `TRANSPORT_TESTS[165]` |
| `handle_app_resumed_parallel_reprime_test.dart` (NEW, this plan) | MISSING — to be authored | auto-globs `core-host-all`; **ADD to `ONE_TO_ONE_TESTS`** |

## RED Test Catalog
All new application-tier tests live in **`test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart`**
(new file). Setup mirrors the existing ordering test: `FakeBridge` + `FakeP2PService(initialState:
NodeState(isStarted: true, peerId: 'my-peer', circuitAddresses: ['/p2p-circuit/addr1']))`. Flow
events captured via the test flow-event sink used elsewhere in the suite.

**TC-05-01 — resume future does NOT await the inbox drain**
- file::name: `handle_app_resumed_parallel_reprime_test.dart::resume completes while inbox drain is still in flight`
- Tier: application (unit of `handleAppResumed`).
- Shape/setup: set `fakeP2PService.onDrainOfflineInbox` to a callback that awaits a `Completer<void>`
  the test never completes (a drain that "hangs"). Call `await handleAppResumed(...)` under a real
  timeout (e.g. `expectLater(handleAppResumed(...), completes)` or `.timeout(Duration(seconds: 2))`).
- RED-on-HEAD-because: `:189` is `await drainOfflineInbox()`; with a never-completing drain the resume
  future never resolves → the test times out.
- GREEN-asserts: `handleAppResumed` returns `true` (bridgeOk) promptly; `fakeP2PService.drainOfflineInboxCallCount == 1`
  (the drain WAS started); the held completer is still uncompleted (resume did not block on it).
- Mutation-that-re-reds: revert the drain call from `unawaited(drainOfflineInbox()...)` back to
  `await drainOfflineInbox()` → resume hangs → RED (timeout).
- Distinct-event discriminator: `drainOfflineInboxCallCount == 1` proves drain fired (not merely
  skipped); pairs with TC-05-03's `APP_LIFECYCLE_RESUME_REPRIME_PARALLEL`.

**TC-05-02 — re-prime and drain OVERLAP (not strictly serial)**
- file::name: `..._test.dart::inbox drain fires before performImmediateHealthCheck resolves`
- Tier: application.
- Shape/setup: add `FakeP2PService.onPerformImmediateHealthCheck` Completer hook (impl step);
  hold the re-prime open. Start `handleAppResumed(...)` **without awaiting**; pump microtasks
  (`await Future<void>.delayed(Duration.zero)`); assert.
- RED-on-HEAD-because: HEAD awaits `performImmediateHealthCheck` at `:163` BEFORE reaching the drain
  at `:189`; with the re-prime held open, `drainOfflineInboxCallCount` is still `0`.
- GREEN-asserts: `performImmediateHealthCheckCallCount == 1` AND `drainOfflineInboxCallCount == 1`
  while the re-prime completer is still pending → the two genuinely overlap.
- Mutation-that-re-reds: move the drain back to after `await performImmediateHealthCheck()` (serial
  shape) → drain count stays `0` while re-prime held → RED.
- Distinct-event discriminator: this is THE overlap discriminator the spec demands — it proves the
  steps are not strictly ordered, while TC-05-04 proves the protected sweep stays ordered.

**TC-05-03 — distinct parallel-shape flow event emitted**
- file::name: `..._test.dart::emits APP_LIFECYCLE_RESUME_REPRIME_PARALLEL`
- Tier: application.
- Shape/setup: capture flow events; run a normal (non-hanging) resume.
- RED-on-HEAD-because: the event does not exist on HEAD.
- GREEN-asserts: captured events contain `APP_LIFECYCLE_RESUME_REPRIME_PARALLEL` exactly once, and
  still contain `APP_LIFECYCLE_RESUME_COMPLETE` (both paths end the same → the new event is the
  discriminator that the parallel shape ran).
- Mutation-that-re-reds: delete the `emitFlowEvent(... 'APP_LIFECYCLE_RESUME_REPRIME_PARALLEL' ...)`
  line → RED.

**TC-05-04 — Step-8 sweep is reached and ordered DESPITE an in-flight drain (preservation under the new transition)**
- file::name: `..._test.dart::recovery sweep runs in order while drain is still pending`
- Tier: application.
- Shape/setup: hang the drain (TC-05-01 completer) AND wire the six Step-8 callbacks
  (`recoverStuckSendingMessagesFn`…`retryPendingIntroductionDeliveriesFn`) to append to a shared
  `callOrder`. Await `handleAppResumed` under a timeout.
- RED-on-HEAD-because: on HEAD the awaited drain at `:189` never completes → execution never reaches
  Step-8 → `callOrder` stays empty (test times out / asserts empty).
- GREEN-asserts: `handleAppResumed` returns; `callOrder == ['recoverStuckSendingMessages',
  'retryIncompleteUploads', 'retryFailedMessages', 'retryUnackedMessages', 'verifyInboxCustody',
  'retryPendingIntroductionDeliveries']` — reached AND ordered while drain still pending.
- Mutation-that-re-reds: (a) re-await the drain → sweep unreachable → RED; (b) reorder any two Step-8
  calls → ordering assert RED.
- Distinct-event discriminator: complements TC-05-02 — overlap is allowed for re-prime/drain, but
  the outbound sweep order is invariant.

**TC-05-05 — a throwing drain no longer aborts resume / no longer skips the sweep (fault isolation)**
- file::name: `..._test.dart::drain error is isolated, recovery sweep still runs, resume returns healthy`
- Tier: application.
- Shape/setup: `fakeP2PService.throwOnDrainInbox = true`; wire Step-8 callbacks to a `callOrder`.
- RED-on-HEAD-because: on HEAD `await drainOfflineInbox()` throws inside the resume `try` → caught by
  the outer `catch` at `:738` → returns `null` (`APP_LIFECYCLE_RESUME_ERROR`) and **skips Steps 4-8**
  → `callOrder` empty, return value `null`.
- GREEN-asserts: `handleAppResumed` returns `true` (bridgeOk); `callOrder` is the full ordered sweep;
  captured events contain a dedicated `APP_LIFECYCLE_RESUME_DRAIN_ERROR` (from the unawaited drain's
  `catchError`) and NOT `APP_LIFECYCLE_RESUME_ERROR`.
- Mutation-that-re-reds: drop the `.catchError(...)` on the unawaited drain (or re-await it) → the
  throw escapes / aborts the sweep → RED.
- Distinct-event discriminator: `APP_LIFECYCLE_RESUME_DRAIN_ERROR` (isolated) vs
  `APP_LIFECYCLE_RESUME_ERROR` (whole-resume abort) — the two failure shapes must be distinguishable.

**TC-05-06 — `bridge.checkHealth` still runs first; drain is not started before bridge is healthy**
- file::name: `..._test.dart::bridge health check precedes the parallel re-prime`
- Tier: application.
- Shape/setup: use `FakeBridge` with a `checkHealthCallOrder`/timestamp probe (or a `checkHealth`
  that records into the same `callOrder` as a sentinel) ; assert `checkHealth` recorded before
  `performImmediateHealthCheck`/`drainOfflineInbox` fire.
- RED-on-HEAD-because: N/A as a regression on HEAD (HEAD already orders checkHealth first) — this is a
  **preservation lock** authored to fail under the obvious over-parallelization mutation.
- GREEN-asserts: checkHealth sentinel precedes both re-prime and drain.
- Mutation-that-re-reds: move `bridge.checkHealth()` into the concurrent `Future.wait` block (or after
  the drain kick-off) → checkHealth no longer guaranteed first → RED.

## Test Coverage Matrix
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Drain unawaited (resume doesn't block) | resume future independent of drain | application | `handle_app_resumed_parallel_reprime_test.dart::resume completes while inbox drain is still in flight` | `await drainOfflineInbox()` hangs resume | `unawaited(...)` → `await ...` | `./scripts/run_test_gates.sh 1to1` | NEW file auto-globs `core-host-all`; **add to `ONE_TO_ONE_TESTS`** |
| Re-prime ∥ drain overlap | not strictly serial | application | `..._test.dart::inbox drain fires before performImmediateHealthCheck resolves` | serial: drain fires only after awaited health check | drain moved after `await performImmediateHealthCheck()` | `./scripts/run_test_gates.sh 1to1` | same NEW file; needs `onPerformImmediateHealthCheck` fake hook |
| Parallel-shape discriminator | distinct flow event | application | `..._test.dart::emits APP_LIFECYCLE_RESUME_REPRIME_PARALLEL` | event absent on HEAD | delete emit | `./scripts/run_test_gates.sh 1to1` | same NEW file |
| Step-8 sweep ordered under pending drain | invariant preserved under new transition | application | `..._test.dart::recovery sweep runs in order while drain is still pending` | awaited drain → sweep unreached | re-await drain / reorder sweep | `./scripts/run_test_gates.sh 1to1` | same NEW file |
| Drain error isolated | throw doesn't abort resume/sweep | application | `..._test.dart::drain error is isolated, recovery sweep still runs, resume returns healthy` | awaited throw → outer catch → null, sweep skipped | drop `.catchError` / re-await | `./scripts/run_test_gates.sh 1to1` | same NEW file |
| checkHealth precondition kept first | bridge health before network | application | `..._test.dart::bridge health check precedes the parallel re-prime` | preservation (RED under over-parallelization mutation) | move `checkHealth` into concurrent block | `./scripts/run_test_gates.sh 1to1` | same NEW file |
| Existing Step-8 order + fault isolation | unchanged | application | `handle_app_resumed_upload_ordering_test.dart::*` (4 existing tests) | preservation — stays GREEN | n/a (regression guard) | `./scripts/run_test_gates.sh 1to1` | already `ONE_TO_ONE_TESTS[31]` |
| Inbox round-trip still drains | drain still functions when fired | integration | `offline_inbox_roundtrip_test.dart` | preservation — stays GREEN | n/a | `./scripts/run_test_gates.sh 1to1` / `baseline` | already `ONE_TO_ONE_TESTS[19]`/`BASELINE_TESTS[11]` |
| Over-the-wire resume reconnect | real reconnect unbroken | integration | `background_reconnect_test.dart` | preservation — stays GREEN | n/a | `./scripts/run_test_gates.sh transport` | already `TRANSPORT_TESTS[165]` |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the unawaited drain still runs to completion in the
  background (its `Future` is retained by the runtime; `_onResumed`'s `clearResumeStarted()` in the
  resume `finally` is unaffected). 141 defer-when-`!isStarted` is untouched (drain method's own guard,
  `p2p_service_impl.dart:4014`). **Row: TC-05-01 (drain fires) + preservation `p2p_service_impl_test`.**
- **Sibling-surface consistency — the "catching up…" affordance:** verified the banner is driven by
  the **conversation surface's own** drain (`conversation_wired.dart:1195-1263`), not the resume
  drain, so an unawaited resume drain does not remove/regress the affordance. **Row: read-only
  verification + preservation `conversation_wired_test`/`conversation_screen_test` in `1to1`.**
- **158/159 idle `scheduleFrame()` corollary:** the resume drain delivers incoming messages via
  `messageStream`, consumed by the conversation listener which already `scheduleFrame()`s after its
  `addPostFrameCallback` on an idle surface. Making the resume drain unawaited changes *when* messages
  arrive, not *who* consumes them or *whether* a frame is scheduled. **Row: justified N/A for new code
  (no edit to the consumer); regression caught by the existing conversation gate.**
- **Destructive-action side-effects:** none — this plan reorders/awaits-less; it deletes no state and
  adds no migration.
- **Invariant re-verification under new transition:** the Step-8 outbound sweep now runs *while the
  drain is still in flight* (previously after a completed drain). Verified the sweep is outbound-only
  (recover-stuck/upload/failed/unacked/**outbound** custody/intro) and independent of incoming-drain
  results. **Row: TC-05-04 (ordered + reached under pending drain) + the existing ordering test.**
- **Drain coalescing:** `_drainOfflineInbox` single-in-flight guard means a concurrent resume drain +
  a conversation-surface drain coalesce rather than double-run. **Row: preservation
  `p2p_service_impl_test` (drain coalesce).**
- **Badge anti-flap (FDC-14 prerequisite):** the parallel resume re-prime must NOT regress the self
  online-dot. `NodeState.badgeReadinessState` (`node_state.dart:147-153`) drives
  `ConnectionStatusIndicator`; re-priming relay/inbox in parallel keeps `usabilityReady` true, so the
  dot must stay `online`/`onlineDotted` across resume. **Row: assert NO `online→connecting`/`offline`
  transition is emitted on `stateStream` during resume re-prime** (preservation lock; FDC-14 owns the
  new `onlineDirect` tier).

## Invariants (locked by tests)
- INV-1: The resume future never awaits the inbox drain (TC-05-01).
- INV-2: Relay/mDNS re-prime and the inbox drain overlap concurrently (TC-05-02).
- INV-3: `bridge.checkHealth`/`reinitialize` runs first, before any network re-prime/drain (TC-05-06).
- INV-4: The Step-8 outbound recovery sweep is reached and strictly ordered regardless of drain state
  (TC-05-04 + `handle_app_resumed_upload_ordering_test`).
- INV-5: A failing drain is fault-isolated — it neither aborts resume nor skips the sweep, and emits
  `APP_LIFECYCLE_RESUME_DRAIN_ERROR` (not `APP_LIFECYCLE_RESUME_ERROR`) (TC-05-05).
- INV-6: The parallel shape is observable via `APP_LIFECYCLE_RESUME_REPRIME_PARALLEL` (TC-05-03).

## Step-By-Step Implementation Plan  (RED first)
1. **RED:** author `test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart` with TC-05-01…06.
   Add `onPerformImmediateHealthCheck` (`Completer`-style) hook + a `checkHealth`-order sentinel to the
   fakes (`fake_p2p_service.dart`, `fake_bridge.dart`). Confirm TC-05-01/02/03/04/05 RED on HEAD
   (01/04 by timeout, 02 by `drainCount==0`, 03 by missing event, 05 by `null` return + empty sweep).
   **Seam:** test-only.
2. **GREEN — un-serialize:** in `handle_app_resumed.dart`, replace the serial block at `:155-191`:
   after `bridge.checkHealth()`/`reinitialize()` (kept first), start `final reprime =
   p2pService.performImmediateHealthCheck();`, then `unawaited(p2pService.drainOfflineInbox()
   .catchError((Object e){ emitFlowEvent(layer:'FL', event:'APP_LIFECYCLE_RESUME_DRAIN_ERROR',
   details:{'error': e.toString()}); }));`, emit `APP_LIFECYCLE_RESUME_REPRIME_PARALLEL`, then `await
   reprime;` and keep `retryPushRegistrationFn` after the awaited re-prime. **Seam:** the Step-2/Step-3
   region of `handleAppResumed`. **Stop-if:** if `drainOfflineInbox`'s 141 defer or coalescing behaves
   differently when fired before `performImmediateHealthCheck` completes (bridge not yet re-dialled),
   STOP and gate the drain start behind re-prime kick-off ordering — but keep it unawaited.
3. **Verify GREEN + no regression:** TC-05-01…06 GREEN; existing `handle_app_resumed_upload_ordering_test`
   GREEN; run the `1to1` + `transport` gates.
4. **Mutation pass:** apply each row's mutation revert, confirm the named test re-reds, restore.
5. **Harness registration:** add the new file path to `ONE_TO_ONE_TESTS` in `scripts/run_test_gates.sh`
   (it also auto-globs `core-host-all`).

## Risks And Edge Cases
- **Go bridge concurrency (proposal §10, resolved by FDC-S5):** FDC-S5 found the bridge is **largely
  concurrent in the warm/steady state** (concurrent native queues + Go read-lock layers; `Future.wait`
  DOES yield real Go concurrency) — the **only** serialization point is `Node.Start`'s write lock on the
  **cold path** (irrelevant post-startup). So re-prime + drain are NOT head-of-line serialized at the bridge
  in steady state. This plan's win is narrower and at the **Dart** layer: the resume future stops *awaiting*
  the drain, so the first send isn't queued behind it. Pinned by TC-05-01 (resume returns) — not by any
  Go-timing assert. (Residual concern = native thread-pool saturation if warm fans out wide — bounded by
  Option A's single-shot per-peer cooldown.)
- **Drain fired before relay re-dial completes:** mitigated by drain's own 141 defer
  (`!isStarted → schedule startup drain`) and coalescing; STOP-if in step 2 covers the ordering nuance.
- **Background completion of the unawaited drain after the screen closes:** harmless — the drain
  persists/streams independently; no UI handle is required to be live.
- **Over-parallelizing `checkHealth`:** guarded by TC-05-06.

## Device/Relay Proof Profile
- **Host-only for closure:** TC-05-01…06 (application) + `1to1` gate fully close the new behavior; no
  device needed to prove the Dart re-prime is parallel and the sweep order is preserved.
- **Requires device/sim (preservation, not new behavior):** real over-the-wire resume reconnect is
  exercised by `integration_test/background_reconnect_test.dart` (transport gate). A two-sim
  resume→send-immediately smoke is the closure scenario but is **device-proof DEFERRED** (not waived):
  `/sims 1to1 --only N` (background-reconnect scenario; N = TODO, resolve via
  `./scripts/check_reliability_simulation_discovery.sh`).

## Acceptance Gates  (literal)
```
# 1:1 host gate (owns handle_app_resumed_upload_ordering_test + offline_inbox_roundtrip + p2p_service_impl)
./scripts/run_test_gates.sh 1to1            # expected: 1226 pass-count (current 1to1 baseline + new file), 0 fail

# transport integration (background_reconnect preservation)
./scripts/run_test_gates.sh transport       # expected: device/fixture-gated (skips on lone sim) pass-count, 0 fail

# host floor (new file auto-globs here)
./scripts/run_host_test_gates.sh core-host-all   # expected: 0 fail

# group-safety floor (parallel re-prime restarts the shared mDNS host + drains the shared inbox — Scope Guard)
./scripts/run_test_gates.sh groups               # expected: 0 fail (no group regression)

# hygiene
flutter analyze                              # expected: 0 new issues
git diff --check                             # expected: no whitespace errors
```

## Known-Failure Interpretation
- Pre-existing transport-gate flakes (durable-media-upload, per project memory) are NOT introduced by
  this plan — re-run in isolation to confirm. Any `background_reconnect_test` change in pass/fail count
  is a real regression and gates the plan.
- A TC-05-01/04 timeout that does NOT clear after the step-2 edit means the drain is still awaited
  somewhere downstream — re-grep for a second `await ...drainOfflineInbox` before declaring GREEN.

## Done Criteria
- [ ] TC-05-01…06 authored, RED-on-HEAD verified (01/04 timeout, 02 count, 03 event, 05 null+empty).
- [ ] `handle_app_resumed.dart` un-serialized: drain `unawaited(...catchError)`, re-prime awaited,
      `checkHealth` still first, `APP_LIFECYCLE_RESUME_REPRIME_PARALLEL` emitted.
- [ ] All six new tests GREEN; each mutation re-reds its named test, then restored.
- [ ] Existing `handle_app_resumed_upload_ordering_test` (4 tests) still GREEN.
- [ ] New file added to `ONE_TO_ONE_TESTS`; `1to1` + `transport` + `core-host-all` gates pass.
- [ ] `flutter analyze` 0 new; `git diff --check` clean.
- [ ] Device-proof (two-sim resume→send) logged as DEFERRED.

## Scope Guard (hard Do-not)
- **Do NOT** change group reconnect/drain behavior on resume — the parallel re-prime restarts the shared mDNS host and drains the **SHARED 1:1+group inbox**; keep group-rejoin/drain ordering intact. **Group-safety floor:** `./scripts/run_test_gates.sh groups` 0-regress.
- Do NOT touch `performImmediateHealthCheck` / `drainOfflineInbox` internals (`p2p_service_impl.dart`)
  — reorder the *call sites* only.
- Do NOT un-serialize or reorder the Step-8 outbound sweep.
- Do NOT move `bridge.checkHealth()` out of first position.
- Do NOT add `warmPeer`, concurrent-send-inbox, pause-flush, or cold-start re-timing (other FDC plans).
- Do NOT change Go (`config.go` budgets are cited, not edited); the path decision stays in Dart.

## Accepted Differences
- Per FDC-S5 the bridge is concurrent in the warm/steady state, so re-prime and drain fire concurrently
  at the Go layer (only the cold-path `Node.Start` write lock serializes); the accepted, tested improvement
  is that the **Dart resume future no longer awaits the drain** (decoupling resume latency from drain latency).
- The drain may now complete after `APP_LIFECYCLE_RESUME_COMPLETE` is emitted — accepted; the
  affordance + streamed delivery cover the user-visible state.

## Dependency Impact
- gatedBy: none. Independently landable.
- Sibling collision: `handle_app_resumed.dart` (`:130-191`) is co-edited by **FDC-04** (resume
  `warmPeer` call-site) and **FDC-06** (pause-flush). These and this plan must run **sequentially**
  on `lib/core/lifecycle/handle_app_resumed.dart`. `scripts/run_test_gates.sh` is also a shared edit
  (array registration) — sequence array additions to avoid merge churn.
- Ordering vs FDC-04: FDC-04 (Phase 0) inserts its resume `warmPeer` call into the still-serial
  block; this plan (Phase 1) then rewrites that block to parallel. **Recommended: land FDC-05 first**
  so FDC-04's resume call slots into the already-parallel block. If FDC-04 lands first, its resume
  `warmPeer` call-site MUST be rebased when this plan restructures the block (see FDC-04's Step-14
  stop-if). Do **not** assume this plan lands after FDC-04.
- Advisory (FDC-S5): the bridge is concurrent in the warm/steady state (only the cold-path `Node.Start`
  write lock serializes), so the parallelized steps don't head-of-line block the first send; FDC-S5's
  prioritization contract (user-send > speculative reprime) plus Option A's bounded warm keep the user's
  send ahead of any thread-pool/resource contention.
