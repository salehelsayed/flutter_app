# 141 - Notification-open inbox drain no-ops when node not yet started (1:1 message missing on open)  (Bug)

Status: IMPLEMENTED host-green (2026-06-22) — adversarially reviewed; TC-05 device-proof deferred. Uncommitted on `new-feed`.
Spec: free-text intent (no formal spec) — production incident 2026-06-22, branch `new-feed`, EC2-relay-corroborated. Companion: Bug 2 = `142-relay-media-push-payload-too-large-tdd-plan.md` (Go relay, separate).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-22 | Evidence Collector | relay journal+redis (msg `6b4469d6` still pending); `p2p_service_impl.dart`, `prepare_notification_open_use_case.dart`, `prepare_notification_route_target_use_case.dart`, `main.dart`, `startup_router.dart`, `handle_app_resumed.dart`, `feed_wired.dart`, `feed_store.dart` | Mechanism confirmed; **original "never retried / permanent loss" framing REFUTED** | Reframe to missed-on-open/delayed; scope to start-gating the opportunistic drain |
| 2026-06-22 | Planner | gate arrays (`run_test_gates.sh`), existing test inventory + fakes | `p2p_service_impl_test`∈ONE_TO_ONE, `feed_wired_test`∈FEED; no not-started/deferred-drain coverage anywhere | Author RED catalog + matrix |
| 2026-06-22 | Reviewer (sufficiency) | this doc | see Reviewer Findings | — |
| 2026-06-22 | Arbiter | this doc | see Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-22 | contract extraction | `git status --short > /tmp/141-dirty-baseline.txt` (148 dirty) | HEAD `0f3e9170`, branch `new-feed` | scope confirmed; line numbers stale vs churn → located by content | RED |
| 2026-06-22 | RED tests added | `p2p_service_impl_test.dart` (TC-01/02), `feed_wired_test.dart` (TC-03) | TC-01 RED (`PENDING_STARTUP_DRAIN_SCHEDULED` `[]`), TC-03 RED (count 0 vs 1); TC-02 GREEN (preservation) | RED for documented reason | implement |
| 2026-06-22 | implementation | `p2p_service_impl.dart`, `feed_wired.dart`, `run_test_gates.sh` | latch fields + `_scheduleStartupDrain` + `_emitState` fire hook (re-runs public entry → gate re-checked); FeedWired `_maybeRequestOpportunisticInboxDrain` (one-shot); `prepare_..._test` → `ONE_TO_ONE_TESTS` | scoped files only | direct GREEN |
| 2026-06-22 | direct GREEN | — | TC-01/02 `+2`, TC-03 `+1`, TC-04 `+4`; analyze 0 | reds now green | preservation |
| 2026-06-22 | mutation-verified | (temp, reverted) | TC-01/TC-03 RED on HEAD; TC-02 over-latch mut RED; TC-04 drop-conversation mut RED; **review-found** TC-02 strengthened (real stop→start cycle) → now catches arm-latch-on-started mut | each fix has a re-red revert | gates |
| 2026-06-22 | preservation GREEN | `startup_router_notification_open_test.dart` (3 asserts 1→2) | 1to1 `+1012`, feed `+214`, lifecycle/notif/app-root/offline-roundtrip green | 3 startup_router asserts updated for intended Feed belt-and-suspenders drain (routing unaffected) | gates |
| 2026-06-22 | named gates | — | `./scripts/run_test_gates.sh 1to1` +1012, `feed` +214; baseline host-portion green (integration_test/* = device-gated env blocker, 3 sims/no `-d`); transport gate device-gated (deferred) | gate green | QA |
| 2026-06-22 | QA (independent) | — | 4-agent adversarial workflow `wf_57a2d5c8` (p2p=clean, preservation=clean, feed/tests=1 confirmed MEDIUM → TC-02 strengthened) | blocking: none | ship host floor |

**Pre-existing failures (NOT 141 — proven independent):** `main_invite_sweep_wiring_test` (reads `lib/main.dart`, which I never edited; main.dart pre-dirty in baseline); `orbit_wired_test` ×2 "pending group invite from Intros" (uses `FakeP2PService`, never builds `FeedWired`; documented orbit-invite flakes). Neither can reach my 2 production files.

## Source Of Truth
- Spec / intent: inline below + memory `project_relay_notif_open_drain_race_2026_06_22`, `reference_ec2_relay_inbox_access`.
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose).
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`.
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (stale at ~87; real max `139`, `140` = Orbit3 → this is `141`).
- Prior lineage (regression of): Report `41` (notification-open-missing-incoming-messages) + Report `48` (remove destructive inbox-drain fallback).

## Session Classification
implementation-ready (host floor mandatory; device-proof is deferred closure).

## Exact Problem Statement
A user tapped a 1:1 message notification, the app opened, and the new message did **not** appear. Relay forensics (EC2 `mknoun.xyz`, redis `relay:inbox:<b64(peerId)>`) prove the message is **still queued and undelivered** (id `6b4469d6-0243-402f-9eac-9c708a46a72a`, from `12D3KooWHyiSmJVcHfQo…`, ts `2026-06-22T14:18:35.796Z`), even though the relay **successfully sent the FCM push** and the app **connected + re-registered its push token at 14:18:37Z** without ever issuing an inbox ack. The app was foregrounded ~60 s (`14:18:36 → 14:19:37 disconnect`) and the message never surfaced.

Mechanism: the notification-open path drains the relay inbox by calling the **public** `P2PService.drainOfflineInbox()`, which **hard-early-returns when `!_currentState.isStarted`** (`p2p_service_impl.dart:3849`). The notif-open path wraps that call with **no node-start / await-readiness / health-check step** (unlike the app-resume path, which does `performImmediateHealthCheck()` **before** draining). When a notification opens the app and the libp2p node has not yet reached `isStarted == true` at that instant (cold start; or warm where the node was stopped while backgrounded), the opportunistic drain silently no-ops and is **not retried on the open**. The push-token re-register, by contrast, rides a relay-becomes-healthy hook and *does* fire — exactly reproducing the journal (token re-registered, no retrieve/ack).

What must improve: opening from a 1:1 (or contactRequest/intros) notification must surface the just-arrived message **promptly on open** — not only after the next periodic health-check tick or a later resume. The fix makes the opportunistic notif-open drain **node-start-aware**: if requested while `!isStarted`, it must run once the node transitions to started, instead of being dropped.

What must stay unchanged (→ preserved-green sentinels): the started-path drain semantics (immediate drain when already started), staged-inbox `stage→ack→replay` custody ordering, the account-migration network gate, the 30 s periodic health-check drain, app-resume `HC-then-drain` ordering, report-139 already-active dedupe, and report-41/48 inbox recovery behavior.

## Root Cause (verify → refute confirmed)
Survived adversarial refute (workflow `wf_e4be9494-770`, 4 agents):
- `p2p_service_impl.dart:3848-3860` — public `drainOfflineInbox()` begins `if (!_currentState.isStarted) return;` (and `drainOfflineInboxFully()` at `3863-3877`). Hard early-return, no await-for-start, no deferral.
- `prepare_notification_open_use_case.dart:26-29` — conversation/contactRequest/intros call a bare `await drainOfflineInbox();` (an injected closure); no start/health step.
- `prepare_notification_route_target_use_case.dart:30` — passes that closure straight through.
- `main.dart:4124-4127` — wires the notif-open drain to `p2pService.drainOfflineInbox` behind only the account-migration gate (`_runAccountRuntimeNetworkVoidAction`); no `performImmediateHealthCheck`/start.
- `startup_router.dart:980` — cold-start notif-open passes `p2pService.drainOfflineInbox` with no start wrapper; Android cold-tap lands on **Feed** (`startup_router.dart:449`) with the conversation route deferred (133 machinery, `main.dart:3804-3813 / 4066-4097`).
- Contrast (the working ordering to mirror): `handle_app_resumed.dart:163` `performImmediateHealthCheck()` **then** `:189` `drainOfflineInbox()`.
- State funnel for the fix: `_emitState()` (`p2p_service_impl.dart:2625`, assigns `_currentState` at `:2636`); `stopped→started` is observable here; `markResumeStarted()` (`:2253`) is an existing readiness-latch precedent; relay-healthy token re-register at `:3014-3018`.
- Contributing gaps: Feed (`feed_wired.dart`, `feed_store.dart`) has **no** drain/health/lifecycle trigger (grep exit 1); `main.dart:3959-3962` `getContact(peerId)==null` returns before pushing `ConversationWired`.

Refuted / do-NOT-re-introduce (must NOT be planned or claimed):
- **"The drain is NEVER retried / the message is permanently lost."** REFUTED. The **private** `_drainOfflineInbox` (`:1537`, no `isStarted` guard) is called unconditionally by the 30 s periodic health check (`Timer.periodic` `:2016 → _performHealthCheck → :3044`) and by every app-resume (`:189`); `_retrievePendingInboxPage` stages durably **before** acking (`:1473→:1496`) and replays staged entries each drain (`_replayStagedInboxEntries :1633`). The relay copy is retained until a drain succeeds → the message **self-heals** on a later tick/resume. Severity is therefore **missed-on-open / delayed delivery**, not silent permanent loss. The plan's tests must assert the *missed-on-open* behavior and the *fires-on-start* fix — NOT a "message lost forever" claim.
- **Build-skew** for the specific observed message: `uncertain` (working tree is mid-`new-feed` rewrite; the field build's commit is unknown). The HEAD code weakness is real regardless; do not assert the incident is 100% this path vs. build skew.

## Real Scope
In scope:
- `p2p_service_impl.dart`: make the public `drainOfflineInbox()` (and `drainOfflineInboxFully()`) node-start-aware — when called while `!isStarted` (and account gate allows), set a one-shot `_pendingStartupDrain` latch instead of silently returning; fire it from `_emitState()` on the `stopped→started` transition. Emit a discriminator FlowEvent (`P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED` / `…_FIRED`).
- `feed_wired.dart`: belt-and-suspenders — request an opportunistic `drainOfflineInbox()` when Feed becomes the active home after a notification-handled/first-ready (covers Android cold-tap-lands-on-Feed).
- Add `prepare_notification_open_use_case_test.dart` to `ONE_TO_ONE_TESTS` so the notif-open mapping is gated.

Out of scope (owning work):
- The `getContact==null` dead-end re-fetch-after-drain (`main.dart:3959-3962`) — separate follow-up (contact materialization after drain); this plan does not change routing, only ensures the drain actually runs.
- Removing/altering the public `drainOfflineInbox` `isStarted` guard's purpose for non-notif callers, the 30 s health-check cadence, or relay custody/ack semantics.
- Bug 2 (relay media-push >4 KB) → `142-…-tdd-plan.md`.

## Files To Inspect Next
Production: `lib/core/services/p2p_service_impl.dart` (`drainOfflineInbox` 3848, `drainOfflineInboxFully` 3863, `_emitState` 2625, `markResumeStarted` 2253, `_performHealthCheck` 2867, `_drainOfflineInbox` 1537); `lib/features/feed/presentation/screens/feed_wired.dart`; `lib/features/push/application/prepare_notification_open_use_case.dart`.
Direct tests: `test/core/services/p2p_service_impl_test.dart`; `test/features/feed/presentation/screens/feed_wired_test.dart`; `test/features/push/application/prepare_notification_open_use_case_test.dart`; `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`.
Integration: `integration_test/notification_open_during_other_chat_harness.dart`.
Dependency-only context: `lib/core/lifecycle/handle_app_resumed.dart` (mirror ordering); `lib/core/services/fake_p2p_service.dart` (drain spies).

## Existing Tests Covering This Area
- `p2p_service_impl_test.dart` covers the real drain mechanics (staging replay, decryption-deferred, idempotent concurrent drains, paging, `…Fully`) — but **every node is built `isStarted:true`**; no not-started/deferred-drain case. (in `ONE_TO_ONE_TESTS`, line 48)
- `startup_router_notification_open_test.dart` is the only file asserting `drainOfflineInboxCallCount==1` on notif-open — **cold start only, fake always-started**; no not-started/deferred case. (no curated array)
- `prepare_notification_open_use_case_test.dart` covers route-kind→which-drain mapping with inline closures; no node/isStarted concept. (no curated array)
- `app_root_notification_open_test.dart` covers clear→prepare→route ordering + 139 dedupe; `prepare` is a recording no-op. (no curated array)
- `feed_wired_test.dart` constructs+injects `FakeP2PService` but has **zero** drain/notif assertions. (in `FEED_TESTS`, line 91)
- `notification_open_during_other_chat_harness.dart` real-relay 2-device tap-routing, node fully online; JSON-verdict harness (no `_test.dart` suffix → run by **no** gate).

Missing coverage gaps: **drain-when-not-started**, **isStarted gating of the opportunistic drain**, **retry-after-start (deferred drain fires on `stopped→started`)**, **Feed-open opportunistic drain** — none exist.
Already in curated family arrays?: `p2p_service_impl_test.dart`→`ONE_TO_ONE_TESTS`; `feed_wired_test.dart`→`FEED_TESTS`. The notif-open use-case/app-root/startup-router/harness are in **no** curated array.

## RED Test Catalog (add BEFORE any production code — INV-RED-FIRST)
1. `test/core/services/p2p_service_impl_test.dart`::`drainOfflineInbox defers when node not started and fires on started transition`
   - Tier: unit/application (real `P2PServiceImpl` + `FakeBridge`).
   - Shape/setup: build the service with `FakeBridge` returning `node:status` `{'isStarted': false}`. Wire a flow-event recorder. Call `await service.drainOfflineInbox()`. Assert: NO `callP2PInboxRetrievePending` issued to the bridge, NO `P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN`, and (post-fix) a `P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED` event. Then drive a `stopped→started` transition (emit a `node:status`/health-poll with `{'isStarted': true}` so `_emitState` runs). Assert: `callP2PInboxRetrievePending` is now issued **after** the transition AND a `P2P_SERVICE_PENDING_STARTUP_DRAIN_FIRED` event is emitted exactly once.
   - RED on HEAD because: `drainOfflineInbox()` returns at `:3849` when `!isStarted` and nothing re-fires on the later transition → the post-transition `retrieve_pending`/`…_FIRED` assertions fail (no deferral exists).
   - GREEN after fix asserts: the deferred drain runs on `stopped→started`, issuing exactly one retrieve_pending.
   - Mutation that re-reds: revert the `_pendingStartupDrain` latch + `_emitState` fire-hook → post-transition assertions go RED.
   - Distinct-event discriminator: assert `P2P_SERVICE_PENDING_STARTUP_DRAIN_FIRED` AND that `retrieve_pending` is issued **after** the started transition, NOT before (distinguishes "deferred-then-fired" from "ran immediately / double-fired").
2. `test/core/services/p2p_service_impl_test.dart`::`drainOfflineInbox runs immediately when already started (no deferral, single fire)`
   - Tier: unit/application (real impl + `FakeBridge` `isStarted:true`).
   - Shape/setup: node `isStarted:true`; call `drainOfflineInbox()`; assert exactly one `retrieve_pending` immediately + `P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN`; then drive a benign `_emitState` (e.g. connections change, still started) and assert NO second/deferred drain fires (latch must be empty).
   - RED on HEAD because: passes today (preservation) — authored to FAIL if the fix wrongly latches/double-fires when already started.
   - GREEN: unchanged started-path behavior; no double drain.
   - Mutation that re-reds: make the fix latch unconditionally (ignore `isStarted`) → this test sees a spurious second drain → RED.
3. `test/features/feed/presentation/screens/feed_wired_test.dart`::`FeedWired requests an opportunistic inbox drain on first-ready / notification-handled`
   - Tier: widget (`WidgetTester` + `FakeP2PService`).
   - Shape/setup: pump `FeedWired` with `FakeP2PService` (which already exposes `drainOfflineInboxCallCount`), simulating the becomes-active-home / notification-handled condition the fix adds; assert `p2pService.drainOfflineInboxCallCount >= 1`.
   - RED on HEAD because: `feed_wired.dart` never calls any drain (grep exit 1) → count stays 0.
   - GREEN after fix asserts: Feed triggers one opportunistic drain on the added condition.
   - Mutation that re-reds: revert the Feed drain trigger → count 0 → RED.
   - Distinct-event discriminator: assert the drain is the opportunistic one (gated on the becomes-active/notification-handled condition, not on every rebuild) — count is exactly 1 for a single activation, not N per frame.
4. `test/features/push/application/prepare_notification_open_use_case_test.dart`::`conversation/contactRequest/intros invoke the (start-aware) 1:1 drain` (regression-lock; add file to gate)
   - Tier: unit/application (existing closures).
   - Shape/setup: keep existing 4 cases; this file is added to `ONE_TO_ONE_TESTS` so the notif-open→drain mapping is enforced under the 1:1 gate. (The start-awareness lives in `P2PService`, so the use case still just invokes the injected closure — locked here as preservation.)
   - RED on HEAD because: passes today — guards against a future regression that drops the conversation→drain mapping.
   - GREEN: mapping preserved.
   - Mutation that re-reds: drop the `conversation` case from `prepareNotificationOpen` → its assertion RED.
5. `integration_test/notification_open_during_other_chat_harness.dart`::scenario `notif_open_node_not_started_surfaces_after_start` (device-proof closure — DEFERRED)
   - Tier: device-proof / real-relay integration (2 sims, real Go bridge, real relay).
   - Shape/setup: extend the existing harness with a variant where the recipient node is **not yet started** at tap (cold launch via notification), then assert the message surfaces in the conversation after the node starts (within a bounded wait), via the real `drainOfflineInbox` deferral.
   - RED on HEAD because: on HEAD the opportunistic drain no-ops and the message only appears on the next ~30 s tick (or not within the bounded wait) → scenario fails its timing assertion.
   - GREEN after fix asserts: message surfaces promptly after node start.
   - Mutation that re-reds: revert the latch → scenario times out.
   - Note: real "node not started at tap" is environment-sensitive; **host TC-01 carries the mechanism**, this is the closure proof. Deferred (no 2-sim relay pair available in this session).

## Test Coverage Matrix (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 deferred-drain fires on start | service state-transition logic (real impl + FakeBridge) | unit/application | `test/core/services/p2p_service_impl_test.dart::drainOfflineInbox defers when node not started and fires on started transition` | `drainOfflineInbox()` returns at :3849, no re-fire on transition | revert `_pendingStartupDrain` latch + `_emitState` hook → post-transition asserts RED | `./scripts/run_test_gates.sh 1to1` (expect prior count +N) | **AUTO** (`test/core/**` host-all) + already in `ONE_TO_ONE_TESTS` (line 48) — no array edit |
| TC-02 started-path unchanged | preservation: immediate drain, no double-fire | unit/application | `test/core/services/p2p_service_impl_test.dart::drainOfflineInbox runs immediately when already started (no deferral, single fire)` | passes today; fails if fix over-latches | make fix latch unconditionally → spurious 2nd drain RED | `./scripts/run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` (no edit) |
| TC-03 Feed opportunistic drain | widget lifecycle trigger | widget | `test/features/feed/presentation/screens/feed_wired_test.dart::FeedWired requests an opportunistic inbox drain on first-ready / notification-handled` | feed_wired never drains (grep exit 1) → count 0 | revert Feed drain trigger → count 0 RED | `./scripts/run_test_gates.sh feed` | AUTO (glob) + already in `FEED_TESTS` (line 91) — no array edit |
| TC-04 notif-open→drain mapping lock | route-kind → drain mapping | unit/application | `test/features/push/application/prepare_notification_open_use_case_test.dart::conversation/contactRequest/intros invoke the (start-aware) 1:1 drain` | passes today (regression lock) | drop `conversation` case → mapping assert RED | `./scripts/run_test_gates.sh 1to1` | **MANUAL: add path to `ONE_TO_ONE_TESTS` array in `run_test_gates.sh`** (else only host-all glob) |
| TC-05 not-started→surface-after-start | OS-boundary / real relay, 2-device | device-proof (DEFERRED) | `integration_test/notification_open_during_other_chat_harness.dart::notif_open_node_not_started_surfaces_after_start` | opportunistic drain no-ops; message late/absent within bounded wait | revert latch → scenario times out | `/sims <notif-open scope> --only N` (closure) | **MANUAL: `classify_path()` case in `check_reliability_simulation_discovery.sh` + orchestrator `--scenario` case** |

## Invariants (locked by tests)
- INV-1: A notif-open opportunistic `drainOfflineInbox()` requested while `!isStarted` is **not dropped** — it runs once on the next `stopped→started` transition. → TC-01.
- INV-2: When already started, `drainOfflineInbox()` drains immediately and exactly once (no deferral, no double-fire). → TC-02.
- INV-3: The Feed surface (cold-tap landing target) triggers one opportunistic drain on becoming active. → TC-03.
- INV-4: Conversation/contactRequest/intros notification kinds still map to the 1:1 drain. → TC-04.
- INV-5 (custody preserved): the message is never lost — staged `stage→ack→replay` ordering and relay retention are unchanged; the fix only changes *when* the open-path drain runs. → TC-01 (no ack issued while not-started) + preservation sentinels.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short` (dirty-tree baseline; the tree is mid-`new-feed`). Add the RED tests TC-01…TC-04 (and stub TC-05 scenario); run focused cmds; confirm TC-01/TC-03 fail for the documented reason, TC-02/TC-04 pass.
2. `p2p_service_impl.dart` `drainOfflineInbox()` (3848) and `drainOfflineInboxFully()` (3863): replace the bare `if (!_currentState.isStarted) return;` with — if `!isStarted` and the account gate allows, set `_pendingStartupDrain = true` (record `waitForAllPages`), emit `P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED`, and return; otherwise proceed as today.
3. `p2p_service_impl.dart` `_emitState()` (2625): after assigning `_currentState`, when the transition is `!previous.isStarted && next.isStarted` and `_pendingStartupDrain` is set, clear the latch, emit `P2P_SERVICE_PENDING_STARTUP_DRAIN_FIRED`, and `unawaited(_drainOfflineInbox(waitForAllPages: …))` (private; account gate already passed at schedule time, or re-check). Mirror the existing relay-healthy token re-register pattern (`:3017`). Stop-if: `_emitState` is hot/reentrant → guard the fire behind the one-shot latch only (no loops).
4. `feed_wired.dart`: on first-ready / notification-handled activation, `unawaited(widget.p2pService.drainOfflineInbox())` once (idempotent; not per-frame). Stop-if: risk of per-rebuild drains → gate on a `_didOpportunisticDrain` bool.
5. Add `test/features/push/application/prepare_notification_open_use_case_test.dart` to `ONE_TO_ONE_TESTS` in `run_test_gates.sh`; (deferred) add TC-05 `classify_path()` + orchestrator scenario.
6. Rerun direct → preservation → named gates (below). Stop-if: any sentinel red outside Scope Guard → replan, do not hack.

## Risks And Edge Cases
- **Open question (flag):** in the incident the app was foregrounded ~60 s yet the message never surfaced and is still pending 12+ min later — so even the 30 s periodic drain did not deliver. Likely the node never reached started+relay-connected during that window, or the 14:18:37 token re-register came from a push-triggered path (`:3380/:3484`) not a full `_performHealthCheck` (whose `:3044` drain would have pulled it). The `stopped→started`-transition latch (TC-01) is the correct trigger because it fires exactly when the node is finally ready, independent of the 30 s cadence. Pinned by TC-01.
- `_emitState` reentrancy / multiple `stopped→started` flaps → one-shot latch + `unawaited` guard (TC-02 asserts no double-fire).
- Account-migration gate: schedule-time vs fire-time gate state may differ → re-check `_allowsAccountNetworkSideEffects` at fire time (do not bypass). Pinned by preservation (migration-gate tests).
- Feed drain must be idempotent (not per-frame) → `_didOpportunisticDrain` bool (TC-03 asserts exactly 1).

## Device/Relay Proof Profile
host-only for closure of TC-01…TC-04; **requires 2-sim real-relay for TC-05** (deferred — no sim pair this session).
Closure scenario: `/sims <notif-open scope> --only N` (run after `check_reliability_simulation_discovery.sh` lists it).
Deferred device work → a follow-up device session: extend `notification_open_during_other_chat_harness.dart` + orchestrator with the not-started-at-tap variant on iPhone+Pixel.
Relay defaults if needed: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (see `run_test_gates.sh:163`).

## Acceptance Gates (literal — copy/paste, with expected counts)
```bash
# Dirty-tree snapshot first (tree is mid-new-feed)
git status --short > /tmp/141-dirty-baseline.txt

# RED (before production edits) — must FAIL for the documented reason
flutter test test/core/services/p2p_service_impl_test.dart \
  --plain-name 'drainOfflineInbox defers when node not started and fires on started transition'   # RED
flutter test test/features/feed/presentation/screens/feed_wired_test.dart \
  --plain-name 'FeedWired requests an opportunistic inbox drain on first-ready / notification-handled'  # RED

# Direct GREEN (after fix)
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
flutter test test/features/push/application/prepare_notification_open_use_case_test.dart

# Preservation sentinels (must stay green) — counts are "≥ pre-change baseline"
./scripts/run_test_gates.sh 1to1        # 1:1 Reliability Gate (incl. p2p_service_impl_test.dart, offline_inbox_roundtrip_test.dart)
./scripts/run_test_gates.sh feed        # Feed / Surface Gate (incl. feed_wired_test.dart)
./scripts/run_test_gates.sh baseline    # Baseline Gate (incl. offline_inbox_roundtrip_test.dart)
# Inbox-drain ORDERING changed → transport gate is re-required (per 00-INDEX Report 41/48 maintenance note):
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport

# Simulator/device discovery + run (TC-05, deferred)
./scripts/check_reliability_simulation_discovery.sh   # new scenario MUST list
# /sims <notif-open scope> --list  → note --only N  → /sims <notif-open scope> --only N

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-01, TC-03 before the fix.
- Pre-existing dirty: large uncommitted `new-feed` churn (feed redesign, orbit3, etc.) in `git status` — do NOT revert; compare against `/tmp/141-dirty-baseline.txt`.
- Environment blocker (NOT product): TC-05 needs a 2-sim real-relay pair; absence is an environment blocker, not a product blocker — host TC-01 carries the mechanism.
- Scope drift (BLOCKING): any failure in routing/getContact behavior, migration-gate, 30 s health-check, or report-139 dedupe = blocking (outside Scope Guard).

## Done Criteria
- [x] RED added first (TC-01, TC-03), failed for the expected reason (TC-01 `SCHEDULED` absent → `[]`; TC-03 count 0 vs 1).
- [x] Mutation-verified: each fix has a re-red revert — latch/_emitState hook (TC-01 RED on HEAD), Feed trigger (TC-03 RED on HEAD), TC-02 over-latch mut RED, TC-04 drop-conversation mut RED, **and** review-strengthened TC-02 catches arm-latch-on-started mut.
- [x] Direct GREEN + preservation: 1to1 `+1012`, feed `+214` pass. **Baseline host-portion green; baseline `integration_test/*` + transport gate are DEVICE-gated (3 sims, no `-d`) → environment blocker, deferred** (host TC-01 carries the mechanism; the inbox-custody sentinel `offline_inbox_roundtrip_test.dart` is also in `ONE_TO_ONE_TESTS` and ran green).
- [x] No migration (none needed) — N/A.
- [ ] OS-boundary path: TC-05 device-proof — **DEFERRED authoring + run to a device session** (no 2-sim relay pair; the orchestrator is single-flow/device-only and adding scenario dispatch is an unrunnable blind refactor of working infra). Recipe recorded below under *Deferred: TC-05 authoring recipe*.
- [x] `prepare_notification_open_use_case_test.dart` added to `ONE_TO_ONE_TESTS`; verified it runs in `./scripts/run_test_gates.sh 1to1` (4 cases green in the +1012 run).
- [x] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

### Deferred: TC-05 authoring recipe (device session)
Run-and-author deferred — needs a 2-sim real-relay pair. To register + implement the `notif_open_node_not_started_surfaces_after_start` scenario:
1. **Orchestrator** `integration_test/scripts/run_notification_open_during_other_chat.dart` is currently single-flow (no `--scenario`). Add an additive `--scenario` arg parse that branches ONLY for the new scenario name and leaves the existing default warm-tap flow byte-identical; implement the not-started-at-tap variant (cold-launch recipient via notification, assert the message surfaces after node start within a bounded wait).
2. **Harness** `integration_test/notification_open_during_other_chat_harness.dart` (role-dispatched alice/bob via `SMOKE_ROLE`): add a `SMOKE_SCENARIO` dart-define branch in the alice path for the not-started variant.
3. **Discovery** `scripts/check_reliability_simulation_discovery.sh`: add an `expand_notification_open_during_other_chat()` scenario-expansion + a `case` for the orchestrator in `expand_record_to_checks()` so `check_reliability_simulation_discovery.sh` lists the scenario.
4. **Run** `scripts/run_reliability_simulations.sh` already passes `--scenario` for `integration_test/scripts/*.dart` runners — no change needed.

## Scope Guard (hard "Do not")
- Do not change notification ROUTING or the `getContact==null` dead-end (`main.dart:3959-3962`) — separate follow-up; this plan only makes the drain run.
- Do not remove/relax the public `drainOfflineInbox` `isStarted` guard for non-deferral purposes, alter the 30 s health-check cadence, or change relay custody / `stage→ack→replay` ordering.
- Do not touch the Go relay (Bug 2, `142-…`).

## Accepted Differences / Intentionally Out Of Scope
- Re-fetching the contact after a successful deferred drain (so a brand-new sender's first message routes to the conversation rather than hitting the `getContact==null` dead-end) — real but separate; owned by a follow-up. This plan ensures the message is drained+staged+visible in Feed/conversation on next entry even if the immediate tap hit the dead-end.
- The "self-heal within 30 s" path is intentionally left intact as a backstop; the fix makes delivery prompt-on-start rather than removing the periodic drain.

## Dependency Impact
- None block this. Report-41/48 inbox-recovery and report-139 dedupe must remain green (sentinels).

## Reviewer Findings
Sufficiency: every TC has tier+file+name+RED-reason+mutation+gate+registration (zero empty matrix cells). INV-1..INV-5 each locked. Refuted "permanent loss" framing explicitly recorded so it is not re-introduced. PROD-CRITICAL leg = TC-05 (real-relay notif-open not-started), named + deferred with host TC-01 as the mechanism floor. Preservation sentinels named with literal gate cmds + transport re-requirement. One residual: TC-05 is environment-deferred — acceptable because the state-transition mechanism is fully host-provable (TC-01) and the device leg is a confirmation, not the only proof.

## Arbiter Decision
Structural blockers: none. Deferred details: TC-05 device run (environment-gated). Accepted differences: contact re-fetch after deferred drain (separate follow-up). Verdict: structurally sufficient — hand off to execution.

## Final Execution Verdict
Verdict: **SHIP (host floor) — IMPLEMENTED host-green, adversarially reviewed.** | Files changed (6): `lib/core/services/p2p_service_impl.dart` (one-shot `_pendingStartupDrain` latch; public `drainOfflineInbox`/`drainOfflineInboxFully` defer via `_scheduleStartupDrain` when `!isStarted`; `_emitState` fires once on `stopped→started` by re-running the public entry → account-migration gate re-checked at fire time; `_SCHEDULED`/`_FIRED` FlowEvents), `lib/features/feed/presentation/screens/feed_wired.dart` (one-shot `_maybeRequestOpportunisticInboxDrain` in `initState`, `_didOpportunisticDrain` guard), `scripts/run_test_gates.sh` (`prepare_notification_open_use_case_test.dart` → `ONE_TO_ONE_TESTS`), `test/core/services/p2p_service_impl_test.dart` (TC-01 + review-strengthened TC-02 with real stop→start cycle), `test/features/feed/presentation/screens/feed_wired_test.dart` (TC-03), `test/features/identity/presentation/screens/startup_router_notification_open_test.dart` (3 asserts 1→2 for intended Feed belt-and-suspenders drain). No migration. | Tests run (+counts): 1to1 `+1012`, feed `+214`, TC-01/02 `+2`, TC-03 `+1`, TC-04 `+4`; analyze 0-new; `git diff --check` clean. | Blocking: none. | QA verdict: 4-agent adversarial workflow `wf_57a2d5c8` — p2p-correctness CLEAN, preservation CLEAN, feed/tests found 1 confirmed MEDIUM (TC-02 not load-bearing for over-latch) → FIXED (strengthened TC-02, mutation-confirmed). | Pre-existing-only reds (proven independent of this change): `main_invite_sweep_wiring_test` (reads untouched `lib/main.dart`); `orbit_wired_test` ×2 orbit-invite flakes (FakeP2PService, never builds FeedWired). | Non-blocking follow-ups (owner): contact re-fetch-after-drain (`main.dart:getContact==null` routing follow-up, out of scope); TC-05 device-proof authoring+run (device session — recipe in Done Criteria); baseline `integration_test/*` + transport gate device run (single `-d`).
