# Sendable Online Badge Spec

Issue type: `feature-improvement`

Output doc path: `Test-Flight-Improv/Network-Transport-libp2p-Feature/06-sendable-online-badge-spec.md`

---

## 1. Problem Statement

Users want the green badge to reflect when the app is actually usable, not only when relay reservation is complete.

Today, the app shows `Connecting` until relay-backed readiness is present. On some WiFi networks, relay reservation can be delayed or blocked even though the app may still be able to send and retrieve inbox data through other valid paths. From the user’s perspective, that makes the app look stuck or half-broken when it is already usable.

The requested product contract is:

- `Online` means the user can send and can retrieve inbox data
- `Online.` means the user is still fully usable and relay reservation is now also ready

This change is meant to fix the user-visible readiness contract. It is not, by itself, a transport-speed fix.

---

## 2. Impact Analysis

Who is affected:

- users on networks where relay reservation is delayed, blocked, or unstable
- users resuming the app from background while relay readiness lags behind actual usability
- users on same-host or local-direct paths where the app can already function before relay truth turns green under the current model

When it appears:

- cold start on hostile or unusual WiFi
- degraded background resume
- any recovery window where relay reservation settles after other usable paths recover first

Why it matters:

- the badge currently communicates “not ready” during cases where the app may already be usable
- that creates confusion, support cost, and unnecessary waiting
- it also hides the difference between “usable now” and “fully relay-ready”

Severity:

- medium to high user-facing confusion
- especially visible in the same networks already called out during relay-recovery investigation

---

## 3. Current State

Current badge semantics are strict relay semantics.

- `lib/features/p2p/presentation/widgets/connection_status_indicator.dart` derives `ConnectionHealth.online` only when `relayState == 'online'` or `circuitAddresses.isNotEmpty`.
- If the node is started but neither of those is true, the badge shows `Connecting`.
- Existing widget tests in `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` explicitly lock that behavior in today.

Current benchmark and smoke surfaces also treat strict relay truth as the badge success condition.

- `integration_test/benchmark_time_to_online_harness.dart` measures “green badge” from `TIME_TO_ONLINE_BADGE`.
- `integration_test/benchmark_background_resume_harness.dart` measures healthy and degraded resume against the same badge event.
- `integration_test/benchmark_relay_recovery_harness.dart` measures relay recovery against the same badge event.
- `integration_test/background_reconnect_test.dart` waits for `ConnectionHealth.online`.
- many lifecycle tests under `test/core/lifecycle/` also use `healthFromState(...) == ConnectionHealth.online` as the recovered condition.

The codebase already contains evidence that “usable transport” and “relay-ready” are not always the same thing.

- `lib/core/debug/intro_e2e_runner.dart` uses `_hasUsableTransportForIntroE2E(...)`, which accepts relay-backed transport or same-host/local transport instead of waiting only for circuit relay truth.

The codebase also already treats successful inbox fallback as a valid delivered send path.

- `lib/features/conversation/application/send_chat_message_use_case.dart` races reuse/local/direct/relay, then falls back to `storeInInbox(...)`.
- if inbox store succeeds, the message is persisted with delivered status and transport `inbox`.
- regression coverage in `test/features/conversation/application/send_chat_message_use_case_test.dart` already proves several valid “usable even without relay reservation” send outcomes, including probe-error and no-reservation inbox fallback.

Current gap:

- there is no user-visible state for “sendable and inbox-capable, but relay reservation not ready yet”
- there is no benchmark that separates “sendable badge reached” from “relay-ready badge reached”
- there is no explicit, tested product contract for when the app should show `Online` versus `Online.`

---

## 4. Scope Clarification

In scope:

- redefine badge semantics so `Online` means usable now and `Online.` means usable now plus relay-ready
- make the distinction user-visible during cold start, degraded resume, and relay-delayed recovery
- add a verification contract that proves both sending and inbox retrieval actually work before plain `Online` is shown
- preserve the existing transport correctness guarantees while splitting the badge into usable vs relay-ready truth

Out of scope:

- speeding up relay reservation itself
- changing transport routing policy for direct, relay, local, or inbox paths
- changing server-side relay behavior
- redesigning the broader transport architecture from the accepted Phase 3b baseline
- redesigning the badge copy beyond the requested text states `Online` and `Online.`

Important product constraints:

- `Online.` is an upgrade on top of `Online`, not a separate unrelated state
- relay-ready alone is not enough for `Online.` if the app cannot yet satisfy the plain `Online` contract
- a defined proof-reset event or node stop must clear stale readiness proof so the badge cannot stay green incorrectly

Accepted implementation ambiguity for a later pass:

- the internal storage/event wiring used to track readiness proof may vary
- the spec fixes what counts as proof and when it must be cleared; it does not require a specific bridge field, cache shape, or state-holder type
- the spec does not require a particular internal event name as long as benchmarks can separately measure sendable and relay-ready transitions

---

## 5. User-Visible State Contract

### 5a. Operational Readiness Definitions

Phase 6 must use these exact readiness meanings.

#### `relay-ready`

`relay-ready` keeps the current strict relay truth:

- `relayState == 'online'`, or
- `circuitAddresses.isNotEmpty`

This is the same readiness concept the badge uses today.

#### `send-capable`

`send-capable` is proven only by a real successful foreground send path in the current valid proof window.

Accepted proof:

- successful direct send
- successful local send
- successful relay send
- successful inbox fallback store via `storeInInbox(...)`

Not accepted as proof by itself:

- `connections.length > 0`
- `listenAddresses.isNotEmpty`
- `relayState == 'online'`
- `circuitAddresses.isNotEmpty`
- bridge health being true
- a cached earlier send success from an invalidated proof window

Reason:

- the Phase 6 badge must reflect actual user sendability, not transport-looking hints

#### `inbox-capable`

`inbox-capable` is proven only by a successful inbox retrieval path in the current valid proof window.

Accepted proof:

- successful `retrieveInbox(...)`
- successful `drainOfflineInbox()`

Not accepted as proof by itself:

- node started state
- existing local message rows
- successful send proof
- relay-ready truth
- a cached earlier inbox success from an invalidated proof window

Reason:

- the Phase 6 badge must prove that inbox retrieval still works now, not merely that it worked sometime earlier

### 5b. Proof Window and Reset Rules

Readiness proof is not app-lifetime sticky. It is valid only inside the current proof window.

There is no standalone wall-clock TTL for `send-capable` or `inbox-capable`.

- a past successful send or inbox retrieval does not expire just because a fixed number of seconds passed
- proof remains valid until a defined proof-reset event happens
- this keeps the badge from flapping back to `Connecting` during an otherwise healthy idle session

For Phase 6, staleness is event-bounded, not time-bounded.

`proof-reset event` means any of these:

- node stop
- watchdog restart or any full host restart
- identity change
- explicit bridge/node reinitialization that starts a new transport session
- entry into a new degraded or unhealthy recovery window after prior proof was established
- a failed verification attempt for that specific capability in the current recovery window

Additional resume/recovery rule:

- if the app resumes into a degraded or unhealthy recovery path, any pre-background `send-capable` or `inbox-capable` proof must not be reused as post-resume truth
- in that case, both capabilities must be re-proven in the new recovery window before the badge may show `Online`

Relay-only downgrade rule:

- loss of relay-ready truth alone clears only `relay-ready`
- if the app stays in the same live session and no capability failure is observed, existing `send-capable` and `inbox-capable` proof may remain valid
- this is what allows the badge to downgrade from `Online.` to `Online` instead of falling all the way back to `Connecting`

### 5c. Proof Trigger Model

Phase 6 must define when readiness proof is attempted, not only what counts as proof.

Proof attempts must be proactive.

They must begin automatically on:

- cold start
- hot restart / already-started resync
- degraded background resume
- any new recovery window created by restart, reinitialize, or transport-session reset

Proof attempts must not depend only on user action.

That means:

- the badge must be able to reach `Online` without waiting for the user to send a real message
- a later successful user send may satisfy `send-capable` if the proactive send proof is still pending
- a later successful inbox retrieval/drain may satisfy `inbox-capable` if proactive inbox proof is still pending
- but user action is not allowed to be the only path out of `Connecting`

Required trigger behavior:

- `inbox-capable` proof must be attempted through the normal inbox retrieval path already used by the app on start/resume
- `send-capable` proof must also be attempted proactively in the same proof window through a dedicated safe mechanism
- if proactive proof finishes first, the badge may advance without any user send
- if real user success arrives first, that real success may satisfy the corresponding proof

Healthy-session reuse rule:

- when the app resumes and the proof window was not invalidated, existing `send-capable` and `inbox-capable` proof may be reused
- when the app resumes into a degraded or reset recovery window, proof must be re-attempted proactively in that new window

Pending-proof rule:

- if proactive proof is still pending, the badge remains `Connecting`
- if one capability is proven and the other is still pending, the badge remains `Connecting`
- the badge advances only when both capabilities are proven

### 5d. Signal Ownership and Flow

Phase 6 must use one authoritative readiness owner.

Authoritative owner:

- `P2PService` / `P2PServiceImpl` is the single source of truth for the badge-ready state exposed to the app

Signal origin rules:

- `relay-ready` originates from the existing bridge / Go transport state and continues to flow into `P2PServiceImpl` through the same relay-status and state-update paths already used today
- `send-capable` originates from Dart-side successful send outcomes
- `inbox-capable` originates from Dart-side successful inbox retrieval / drain outcomes

Ownership rules:

- Go / bridge may continue to own relay transport truth
- Go / bridge must not become a second independent owner of `send-capable` or `inbox-capable`
- widget code must not infer readiness independently from raw transport-looking hints
- benchmarks and smoke tests must observe the same readiness owner that the widget uses

Required flow shape:

- proof-producing paths update readiness through `P2PServiceImpl`
- `P2PService.stateStream` / current exposed service state remains the app-facing projection seam
- `ConnectionStatusIndicator` remains a pure renderer of that service-owned state
- benchmark events for Phase 6 must be emitted from the same service-owned readiness transitions, not from parallel widget-only or harness-only inference

Anti-patterns this spec disallows:

- widget-local readiness inference that bypasses service state
- a second separate “badge readiness service” with different truth from `P2PService`
- using bridge health, connection counts, or listen addresses directly in the widget as Phase 6 readiness truth
- benchmark-only sendable state that the production widget never consumes

### 5e. User-Visible State Mapping

Phase 6 should satisfy this exact visible contract:

- `Offline`
  - node is not started
- `Connecting`
  - node is started, but the app has not yet proven both:
    - send capability
    - inbox retrieval capability
- `Online`
  - send capability is proven
  - inbox retrieval capability is proven
  - relay-ready is not yet proven
- `Online.`
  - all `Online` conditions are true
  - relay reservation / relay-ready truth is also proven

Transition rules:

- if all three conditions become true together, the UI may go directly to `Online.`
- if relay-ready drops but send and inbox remain valid, the badge must downgrade from `Online.` to `Online`
- if either send capability or inbox capability is no longer valid, the badge must leave `Online` / `Online.` and return to `Connecting`
- `Offline` always wins when the node stops

This spec intentionally changes the meaning of the green badge:

- before Phase 6, green means relay-ready
- after Phase 6, green means usable now
- the trailing dot communicates that relay reservation has also caught up

### 5f. Rendering and Accessibility Contract

Phase 6 must define not only state meaning, but also how the badge renders and how assistive technologies describe it.

Visible copy contract:

- `Offline`
- `Connecting`
- `Online`
- `Online.`

Visual styling contract:

- `Online` and `Online.` use the same green badge family
- `Online` and `Online.` use the same base color, border treatment, and emphasis level
- the trailing `.` is the only required visible distinction between the two ready states unless product explicitly changes that later
- `Connecting` remains visually distinct from both ready states
- `Offline` remains visually distinct from both ready states

Accessibility contract:

- assistive technology must not rely on punctuation alone to express the difference
- `Online` must expose an accessibility/semantics label equivalent to:
  - online, send and inbox ready, relay reservation pending
- `Online.` must expose an accessibility/semantics label equivalent to:
  - online, send and inbox ready, relay reservation ready
- `Connecting` and `Offline` must continue to expose explicit state labels rather than color-only meaning

Test implications:

- widget tests must verify the exact visible text for all four states
- widget/semantics tests must verify the accessibility label for `Online` versus `Online.`
- regression tests must verify that `Online` and `Online.` do not silently diverge in color/emphasis unless the product contract is intentionally changed

---

## 6. Test Cases

### 6a. Happy Path

#### HP-1: Cold start reaches usable state before relay-ready on a relay-delayed network

Expected behavior:

- app starts in `Connecting`
- once send capability and inbox retrieval capability are both proven, the badge changes to `Online`
- when relay reservation becomes ready later, the badge changes to `Online.`

Existing partial coverage:

- `integration_test/benchmark_time_to_online_harness.dart`
- `test/performance/benchmark_time_to_online_test.dart`

Gap to add:

- explicit sendable-before-relay-ready cold-start coverage
- explicit second transition from `Online` to `Online.`

#### HP-2: Degraded background resume becomes usable before relay-ready

Expected behavior:

- app resumes in `Connecting`
- if immediate recovery restores send capability and inbox retrieval before relay reservation finishes, badge changes to `Online`
- when relay-ready truth arrives later, badge changes to `Online.`

Existing partial coverage:

- `integration_test/benchmark_background_resume_harness.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`

Gap to add:

- explicit split between `resume_to_sendable_ms` and `resume_to_relay_ready_ms`
- explicit resume assertion that the first green state may be plain `Online`

#### HP-3: Relay-ready available immediately

Expected behavior:

- if send capability, inbox capability, and relay-ready are all already true in the same recovery window, the badge may move straight from `Connecting` to `Online.`
- no fake intermediate `Online` frame is required

Existing partial coverage:

- none directly

Gap to add:

- widget and core-service tests that allow direct `Connecting -> Online.` when all conditions are satisfied together

### 6b. Edge Cases

#### EC-1: Send-capable only is not enough

Expected behavior:

- if send capability is proven but inbox retrieval is not yet proven, badge remains `Connecting`

Gap to add:

- unit/service coverage that send proof alone does not unlock `Online`

#### EC-2: Inbox-capable only is not enough

Expected behavior:

- if inbox retrieval is proven but send capability is not yet proven, badge remains `Connecting`

Gap to add:

- unit/service coverage that inbox proof alone does not unlock `Online`

#### EC-3: Relay-ready alone is not enough

Expected behavior:

- relay reservation or circuit-address truth by itself must not show `Online.` unless the plain `Online` contract is already satisfied

Gap to add:

- widget and service coverage that relay-only truth does not bypass usable-state requirements

#### EC-4: Relay never returns on a hostile WiFi, but app remains usable

Expected behavior:

- app reaches `Online`
- app does not reach `Online.`
- send and inbox retrieval continue to work in that state

Existing partial coverage:

- send-path fallback coverage already exists in `test/features/conversation/application/send_chat_message_use_case_test.dart`

Gap to add:

- integration and smoke coverage tying that usability to the badge state

#### EC-5: Relay drops after `Online.`, but app still remains usable

Expected behavior:

- badge downgrades from `Online.` to `Online` when relay-ready is lost but existing `send-capable` and `inbox-capable` proof remains valid under the Section 5b proof-reset rules
- badge does not fall back to `Connecting`
- no false offline/degraded UX if the usability contract still holds

Gap to add:

- widget and lifecycle coverage for `Online.` to `Online` downgrade

#### EC-6: Proof-reset event invalidates stale usability proof

Expected behavior:

- a proof-reset event clears prior readiness proof
- the badge cannot stay `Online` or `Online.` based on stale earlier success

Existing partial coverage:

- lifecycle and reconnect tests already exercise restart/degraded transitions, but only under the old relay-only contract

Gap to add:

- explicit reset tests for the Phase 6 proof-reset events, including:
  - node stop
  - degraded recovery window after prior proof
  - restart/reinitialize
  - capability-verification failure

#### EC-7: Degraded resume cannot reuse stale pre-background proof

Expected behavior:

- if the app resumes into a degraded or unhealthy recovery path, previous pre-background send/inbox proof is not enough
- the badge stays `Connecting` until the current post-resume window re-proves both capabilities

Gap to add:

- explicit lifecycle and service tests that stale pre-background proof does not unlock `Online` after degraded resume

#### EC-8: No user action still allows proactive transition to `Online`

Expected behavior:

- on a valid cold-start or degraded-resume path, the app can reach `Online` from proactive proof attempts alone
- the user does not need to send a message manually just to make the badge leave `Connecting`

Gap to add:

- integration and service tests that no-user-action runs can still reach `Online`

#### EC-9: Real success may satisfy proof while proactive proof is still pending

Expected behavior:

- if proactive `send-capable` proof has not finished yet, a real successful user send may satisfy that capability
- if proactive `inbox-capable` proof has not finished yet, a real successful inbox retrieval/drain may satisfy that capability
- the badge may advance as soon as both capabilities are proven, regardless of which completed first

Gap to add:

- explicit tests for “proactive proof pending, real success arrives first”

### 6c. Preservation / Regression

#### PR-1: Existing transport routing still works

Expected behavior:

- direct, local, relay, and inbox send routing remain unchanged
- Phase 6 changes badge semantics, not transport routing policy

Existing partial coverage:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `./scripts/run_test_gates.sh transport`

#### PR-2: Inbox drain and post-resume continuity remain correct

Expected behavior:

- inbox drain still delivers pending messages
- group and registration follow-up still preserve continuity
- badge changes must not hide real resume failures

Existing partial coverage:

- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`

#### PR-3: Phase 3b relay-ready win remains intact

Expected behavior:

- the accepted Phase 3b recovery improvement remains measurable
- relay-ready timing may stay the same even if `Online` appears earlier
- plain `Online` must not be reported by simply relabeling an unchanged broken path

Existing partial coverage:

- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`
- `test/performance/benchmark_background_resume_test.dart`
- `test/performance/benchmark_relay_recovery_test.dart`

#### PR-4: Bug regression for the original complaint

Expected behavior:

- on a WiFi or relay-delayed scenario where the app can send and retrieve inbox before reservation is ready, the badge must not remain stuck on `Connecting`

This is the explicit user-visible regression case that should fail if the old misleading behavior returns.

---

## 7. Required Verification Coverage

The later implementation pass should not be considered complete unless it adds or updates all of the following coverage layers.

### 7a. Widget / Unit Coverage

Primary target:

- `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`

Required cases:

- `Offline` when node is stopped
- `Connecting` when node is started but neither send nor inbox readiness is proven
- `Online` when send and inbox are proven but relay-ready is not
- `Online.` when send, inbox, and relay-ready are all proven
- direct `Connecting -> Online.` when all three become true together
- downgrade `Online.` -> `Online` when relay-ready disappears but usability remains
- downgrade `Online` / `Online.` -> `Connecting` when required usability proof is cleared
- `Connecting` remains while proactive proof is still pending
- widget renders only from service-owned readiness state, not independent badge inference
- exact visible text is correct for `Offline`, `Connecting`, `Online`, and `Online.`
- semantics/accessibility label distinguishes `Online` from `Online.` without relying on punctuation alone
- `Online` and `Online.` keep the same base ready-state styling unless the product contract intentionally changes later
- widget timing/event coverage for the first usable green state and the later relay-ready dot state

### 7b. Core Service / Lifecycle Coverage

Primary targets:

- `test/core/services/p2p_service_impl_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`

Required cases:

- degraded resume can become `Online` before relay-ready
- relay-ready later upgrades `Online` to `Online.`
- send proof alone does not unlock `Online`
- inbox proof alone does not unlock `Online`
- stale pre-background proof does not unlock `Online` after degraded resume
- proactive proof is attempted automatically on cold start and degraded resume
- no-user-action path can still reach `Online` when proactive proof succeeds
- real user success may satisfy pending proof without waiting for the proactive mechanism to finish
- new outage clears sendable and relay-ready truth
- relay-ready is bridge-owned, while send/inbox proof is service-owned and converges into one state projection
- deferred resume follow-up does not incorrectly advance the badge before required usability proof exists
- existing lifecycle recovery and group continuity behavior stay correct

### 7c. Conversation / Delivery Regression Coverage

Primary target:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`

Required cases:

- existing successful inbox fallback cases still count as delivered transport behavior
- a valid send path during the `Online` window remains possible before `Online.`
- relay delays do not force a regression where sends block waiting for dotted readiness

### 7d. Integration Coverage

Primary targets:

- `integration_test/benchmark_time_to_online_harness.dart`
- `integration_test/benchmark_background_resume_harness.dart`
- `integration_test/benchmark_relay_recovery_harness.dart`

Required cases:

- cold start records both:
  - first usable green state (`Online`)
  - later relay-ready dotted state (`Online.`), if different
- degraded resume records both:
  - `resume_to_sendable_ms`
  - `resume_to_relay_ready_ms`
  - `resume_to_first_send_success_ms`
  - `resume_to_first_inbox_success_ms`
- relay-recovery harness continues to measure relay-ready timing as a secondary metric instead of losing the old signal
- no-user-action benchmark runs can still produce `resume_to_sendable_ms` when proactive proof succeeds
- Phase 6 benchmark events come from the same service-owned readiness transitions the widget consumes

Preferred additional integration surface:

- a dedicated Phase 6 harness or equivalent test flow that proves:
  - usable badge first
  - actual send succeeds during the plain `Online` window
  - relay-ready transition happens later or never, depending on the scenario

### 7e. Device / Smoke Coverage

Primary targets:

- `integration_test/background_reconnect_test.dart`
- `./scripts/run_test_gates.sh transport`
- `dart run integration_test/scripts/run_routing_smoke_e2e.dart` phase 1 scope

Required cases:

- device background reconnect can show `Online` before `Online.` on a delayed-relay scenario
- send still works during the plain `Online` window
- inbox retrieval still works during the plain `Online` window
- routing smoke and transport smoke do not regress because of the badge-semantics change

### 7f. Benchmark / Reporting Coverage

Required event / hook contract:

- `READINESS_PROOF_WINDOW_START`
  - emitted by the service-owned readiness layer when a new proof window begins
  - required fields:
    - `proofWindowId`
    - `phase`
    - `trigger`
- `READINESS_PROOF_RESULT`
  - emitted when a proof attempt for one capability completes
  - required fields:
    - `proofWindowId`
    - `capability` = `send` or `inbox`
    - `success`
    - `proofSource`
    - `elapsedMs`
- `TIME_TO_SENDABLE_BADGE`
  - emitted when the service-owned readiness state first reaches plain `Online`
  - required fields:
    - `proofWindowId`
    - `phase`
    - `totalMs`
    - `source`
    - `sendProofSource`
    - `inboxProofSource`
- `TIME_TO_RELAY_READY_BADGE`
  - emitted when the service-owned readiness state first reaches `Online.`
  - required fields:
    - `proofWindowId`
    - `phase`
    - `totalMs`
    - `source`
- `FIRST_SEND_SUCCESS_IN_WINDOW`
  - emitted on the first actual successful send outcome in the current proof window
  - required fields:
    - `proofWindowId`
    - `phase`
    - `totalMs`
    - `source`
    - `sendPath`
    - `trigger` = `user_action` or `system_action`
- `FIRST_INBOX_SUCCESS_IN_WINDOW`
  - emitted on the first actual successful inbox retrieval/drain outcome in the current proof window
  - required fields:
    - `proofWindowId`
    - `phase`
    - `totalMs`
    - `source`
    - `trigger` = `user_action` or `system_action`

Optional widget/render timing companion events:

- `TIME_TO_SENDABLE_BADGE_WIDGET`
- `TIME_TO_RELAY_READY_BADGE_WIDGET`

If widget timing is collected, it must mirror the service-owned transitions above and remain keyed by the same `proofWindowId` whenever possible.

Required reporting split:

- `resume_to_sendable_ms`
- `resume_to_relay_ready_ms`
- `resume_to_first_send_success_ms`
- `resume_to_first_inbox_success_ms`
- `sendable_to_relay_ready_gap_ms`
- `badge_honesty_gap_ms`
- source/attribution for the sendable transition
- source/attribution for the relay-ready dotted transition

Metric derivation rules:

- `resume_to_sendable_ms`
  - derived from `TIME_TO_SENDABLE_BADGE.totalMs` for `phase=background_resume`
- `resume_to_relay_ready_ms`
  - derived from `TIME_TO_RELAY_READY_BADGE.totalMs` for `phase=background_resume`
- `resume_to_first_send_success_ms`
  - derived from `FIRST_SEND_SUCCESS_IN_WINDOW.totalMs` for `phase=background_resume`
- `resume_to_first_inbox_success_ms`
  - derived from `FIRST_INBOX_SUCCESS_IN_WINDOW.totalMs` for `phase=background_resume`
- `sendable_to_relay_ready_gap_ms`
  - derived by subtracting `TIME_TO_SENDABLE_BADGE.totalMs` from `TIME_TO_RELAY_READY_BADGE.totalMs` within the same `proofWindowId`
- `badge_honesty_gap_ms`
  - derived by subtracting `max(FIRST_SEND_SUCCESS_IN_WINDOW.totalMs, FIRST_INBOX_SUCCESS_IN_WINDOW.totalMs)` from `TIME_TO_SENDABLE_BADGE.totalMs` within the same `proofWindowId`
- sendable-transition attribution
  - derived from `TIME_TO_SENDABLE_BADGE.source`, plus `sendProofSource` and `inboxProofSource`
- relay-ready attribution
  - derived from `TIME_TO_RELAY_READY_BADGE.source`
- first-send attribution
  - derived from `FIRST_SEND_SUCCESS_IN_WINDOW.source`, `sendPath`, and `trigger`
- first-inbox attribution
  - derived from `FIRST_INBOX_SUCCESS_IN_WINDOW.source` and `trigger`

Hooking rule:

- harnesses must read these metrics from the service-owned Phase 6 flow events, not from harness-local polling or independent widget inference
- widget timing is supplementary only; the canonical benchmark numbers come from the service-owned events above
- if a dedicated Phase 6 harness is added, it must still consume the same events so results remain comparable to the existing benchmark suite

Required outcome interpretation:

- if `Online` appears materially earlier than `Online.` on the target WiFi / degraded-resume cases and correctness stays green, Phase 6 is delivering user-visible value
- if `Online` and `Online.` always collapse to the same instant, the experiment is functionally a relabel and should not be treated as a meaningful win

---

## 8. Ready-for-Implementation Verdict

This spec is ready for a later implementation pass.

It is narrow enough to guide Phase 6 without mixing in new relay-transport fixes, and it includes the user-visible contract plus the test and benchmark coverage needed to decide whether the badge-semantics change actually improves the experience.
