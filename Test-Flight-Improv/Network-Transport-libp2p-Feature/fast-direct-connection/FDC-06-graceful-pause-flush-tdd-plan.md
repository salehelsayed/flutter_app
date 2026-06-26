# FDC-06 — Graceful pause-flush of in-flight sends to inbox  (Feature Improvement)

Status: awaiting-review (DRAFT)
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.4 "Lifecycle handshake + graceful handoff" / §7 state-machine `on PAUSE|HIDDEN` / §8 P1-2 / §12 "On pause, issue the inbox deposit *before* the direct attempts")

---

## ⚠ DRAFT — finalize after FDC-S4

**This plan is GATED BY FDC-S4 (iOS pre-suspension background-window feasibility + bound).**
The host-testable Dart flush logic (unit/application tier) is specified in full RED detail below
and can be implemented independently. The **device-proof tier** (does the deposit actually
complete inside a real iOS `beginBackgroundTask` window before the OS freezes the process?) is the
**closure gate** and cannot be authored to final RED detail until FDC-S4 resolves:

1. Is a network call on the `paused`/`hidden` transition feasible at all, and via which existing
   seam — the `bg:begin`/`bg:end` bridge command (`lib/core/bridge/bridge.dart:777-798` →
   `ios/Runner/GoBridge.swift:185-188`, `UIApplication.beginBackgroundTask(withName:"mknoon.sendMessage")`)
   or the `mknoon/migration_keepalive` channel (`migration_transfer_keep_alive.dart:16` ≈ "30 s")?
2. The **wall-clock bound** the flush must fit inside (open question §11.6: "how many in-flight
   sends must it cover"). All `<from FDC-S4>` markers below are this value.
3. Whether the flush runs **before** `runApp`-level teardown competes for the same bg assertion.

Every value tagged `<from FDC-S4>` is provisional. Device-proof rows are flagged **CLOSURE GATE**.

---

## Source Of Truth
- Proposal §6.4 / §7 / §8-P1-2 / §12 (anchored above). `scripts/run_test_gates.sh` array membership
  and literal gate commands win over any prose here.
- This epic's roadmap: **FDC-00** (sequencing) ; spike **FDC-S4** (this plan's gate).
- Verified-against-source on branch `new-orbit`, 2026-06.

## Session Classification
**evidence-gated (DRAFT).** Host/application portion is implementation-ready; device-proof portion
is blocked on FDC-S4. Do NOT begin production edits to the iOS bg-window wiring until S4 closes;
the pure-Dart flush use-case MAY be built RED-first now behind a no-op platform seam.

## Exact Problem Statement
**What's broken/missing.** The "open app → type one message → immediately close the app" case can
silently fail to deliver. On `paused`/`hidden`, `_onPaused()` (`lib/main.dart:4314-4349`) fires
`handleAppPaused()` (`lib/core/lifecycle/handle_app_paused.dart:29-157`), which is **local-DB-only**
(comment `main.dart:4316`: "handleAppPaused() is local DB only — no network calls, no p2pService"):
it transitions every in-flight `sending` row to `failed` (`handle_app_paused.dart:59-66`) so a later
resume can retry. But if the OS suspends the process before the user ever foregrounds again (phone
locked, app evicted), **no resume fires and the message is never deposited to the durable inbox** —
the only guaranteed carrier (§6.2(b)). The message sits as `failed` on the sender's device only.

**Who feels it.** Any sender who closes/locks immediately after sending while the live transport
race (`send_chat_message_use_case.dart:662-703`) is still in flight and the durable inbox copy has
NOT yet been written (the concurrent inbox at `:639-660` fires only for `lowConfidence` sends).

**Why.** No network is allowed on pause today, and there is no bounded pre-suspension window in
which to deposit custody to the relay inbox.

**What must improve.** On pause/hidden, **deposit** every in-flight `sending` message's wire
envelope to the relay inbox via `storeInInbox` **before** the process suspends, so an
open-send-close still delivers. The deposit must be **issued before** any best-effort direct flush
(proposal §12: the early deposit, not the best-effort flush, is the guarantee).

**What must stay unchanged (preserved sentinels).**
- PS-1: when there are **no** in-flight `sending` messages, pause stays a **pure no-op / DB-only**
  path with no bridge `bg:begin` and no `storeInInbox` call (`handle_app_paused_test.dart:47-65`).
- PS-2: a message whose inbox deposit **fails or times out** still ends as `failed` (today's
  behavior) so resume retry (`retry_failed_messages_use_case.dart`) still picks it up — flush must
  not strand a row in `sending`.
- PS-3: group stale-sending recovery (`handle_app_paused.dart:89-119`) is unchanged.
- PS-4: `_onPaused` stays **fire-and-forget** / never throws to the lifecycle callback
  (`main.dart:4317`, `:4339-4348`).
- PS-5: `detached` teardown (`_onDetached` `main.dart:4303-4312`) is untouched — flush is on
  `paused`/`hidden`, NOT `detached` (the node is already being torn down there).

## Root Cause (verify→refute confirmed)
- **Mechanism (confirmed):** `handle_app_paused.dart:59-66` only calls
  `messageRepo.conditionalTransitionStatus(id, fromStatus:'sending', toStatus:'failed')`. No
  `P2PService` is injected into `handleAppPaused` (signature `:29-32` takes only `messageRepo` +
  optional `groupMsgRepo`), so the durable inbox deposit (`P2PService.storeInInbox`,
  `p2p_service.dart:150`) is structurally impossible at pause time.
- **The deposit pattern already exists** and is the model to mirror:
  `retry_unacked_messages_use_case.dart:90-100` does exactly
  `p2pService.storeInInbox(msg.contactPeerId, msg.wireEnvelope!)` → on success
  `copyWith(status:'inboxed', transport:'inbox')`. The pause flush is this, run pre-suspension,
  bounded, deposit-first.
- **iOS window is the open feasibility question (NOT refuted, deferred to FDC-S4):** there is no
  guaranteed execution window on the `paused` transition; a network flush needs an explicit
  `beginBackgroundTask` assertion. Two seams already exist (cited in the DRAFT banner). FDC-S4 must
  pick one and bound it.
- **Refuted / do-NOT-re-introduce:**
  - Do NOT hold a direct/relay socket alive in background to "finish the live race" (proposal §6.4
    "Never hold a direct connection alive in background"; §12 iOS-background risk). The flush is
    **inbox-store-only**, not a transport keep-alive.
  - Do NOT add server-side idempotency — store dedup by `messageId` is already present
    (`backend_memory.go:121-142` / `backend_redis.go:272-295` / `inbox_store.go:7,14`), so a
    duplicate of a copy the live race also delivered is harmless.
  - Do NOT move the flush to `detached` — the node is being released there (`_onDetached`
    `main.dart:4303-4312`), and `detached` does not reliably fire before OS kill.

## Real Scope
**In scope.**
- New host-testable use case that, given the in-flight `sending` messages, deposits each to the
  inbox (deposit-first), bounded, and marks `inboxed`/`failed` accordingly.
- Wire it into `handleAppPaused` as a **new optional stage** that runs only when a `P2PService` +
  bg-task seam are injected (keeps PS-1 and all existing `handle_app_paused_*` tests green).
- Inject the seam from `main.dart:_onPaused` (currently passes only repos).
- The iOS `beginBackgroundTask` acquire/release wrapping (via the existing `bg:begin`/`bg:end`
  bridge seam) — **bound + feasibility per FDC-S4**.

**Out of scope (owning FDC-xx).**
- The send-path concurrent-inbox generalization (lifting the `lowConfidence` gate) → **FDC-03 / P0-2**.
- Parallel resume re-prime (the §6.4 resume half) → **FDC-05 / P1-2 resume**.
- Presence-aware emphasis → **FDC-03 / P1-1**.
- Any Go host / relay change → **FDC-07+ / P2**.
- Group-message pause flush (this plan covers 1:1; group uses `recoverStuckSendingMessages`) →
  deferred follow-up; PS-3 keeps the existing group path unchanged.

## Files To Inspect Next
**Production entry / use-case / models / repos / helpers**
- `lib/core/lifecycle/handle_app_paused.dart` (edit — add deposit stage; signature gets optional
  `P2PService` + bg-task invoker + clock/budget).
- **NEW** `lib/core/lifecycle/flush_pending_sends_on_pause_use_case.dart` (host-testable flush core).
- `lib/main.dart:4314-4349` (`_onPaused` — inject `p2pService` + bridge bg seam) and `:943`
  (`messageRepository` construction) + the `_MknoonAppState`/widget plumbing (`:3354`, `:3443`).
- `lib/core/services/p2p_service.dart:150` (`storeInInbox` seam).
- `lib/features/conversation/domain/repositories/message_repository.dart:86`
  (`getSendingOutgoingMessages`) and `conditionalTransitionStatus` / `saveMessage`.
- `lib/features/conversation/domain/models/conversation_message.dart:59,172-199`
  (`wireEnvelope`, `copyWith`).
- `lib/core/bridge/bridge.dart:777-798` (`callBgBegin`/`callBgEnd` → `bg:begin`/`bg:end`).
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart:64-108` (deposit
  pattern to mirror, incl. null/legacy-envelope guards `:68-89`).
**Direct + integration tests**
- `test/core/lifecycle/handle_app_paused_test.dart`, `handle_app_paused_edge_cases_test.dart`,
  `handle_app_paused_group_test.dart`, `pause_resume_retry_smoke_test.dart`,
  `app_lifecycle_pause_integration_test.dart`.
- `test/features/conversation/integration/send_then_lock_delivery_test.dart` (the exact
  open-send-close scenario — already in the 1to1 array, `run_test_gates.sh:24`).
- `test/shared/fakes/in_memory_message_repository.dart`, `test/shared/helpers/lifecycle_helpers.dart`.
**Dependency-only context**
- `ios/Runner/GoBridge.swift:185-188` (real `beginBackgroundTask`; device-proof only).
- `lib/features/account_migration/application/migration_transfer_keep_alive.dart:16` (≈30 s bound
  precedent — input to FDC-S4's bound decision).

## Existing Tests Covering This Area
| Test | Exists? | In which gate array |
|---|---|---|
| `test/core/lifecycle/handle_app_paused_test.dart` | EXISTS | core-host-all auto-glob (`test/core/**`) |
| `handle_app_paused_edge_cases_test.dart` | EXISTS | core-host-all auto-glob |
| `handle_app_paused_group_test.dart` | EXISTS | core-host-all auto-glob |
| `pause_resume_retry_smoke_test.dart` | EXISTS | core-host-all auto-glob |
| `app_lifecycle_pause_integration_test.dart` | EXISTS | core-host-all auto-glob |
| `send_then_lock_delivery_test.dart` | EXISTS | **1to1** array (`run_test_gates.sh:24`) |
| `flush_pending_sends_on_pause_use_case_test.dart` | **MISSING (new)** | core-host-all auto-glob (`test/core/**`) |
| device-proof pause-flush sim scenario | **MISSING (new)** | needs `classify_path()` + dart-define case (CLOSURE GATE, post-S4) |

`test/core/**` auto-globs into the host floor, so the new unit test needs **no** array edit. The
device-proof sim scenario DOES need a `classify_path()` case + dart-define in
`scripts/check_reliability_simulation_discovery.sh` — authored after FDC-S4.

## RED Test Catalog
> Host/application tier = **fully specified now**. Device-proof tier = **CLOSURE GATE, finalize
> after FDC-S4** (shape given, exact budget/assertion `<from FDC-S4>`).

### Tier: unit/application (host — `flutter_test`, no real platform) — IMPLEMENTATION-READY

**T1 — `flush_pending_sends_on_pause_use_case_test.dart::deposits each in-flight sending message to the inbox`**
- Tier: application/unit.
- Shape/setup: `InMemoryMessageRepository` seeded with 2 `sending` outgoing rows that each carry a
  non-null `wireEnvelope`; a `FakeP2PService` recording `storeInInbox(peerId, envelope)` calls
  (returns `true`). Call the flush use-case.
- RED-on-HEAD-because: the use-case file does not exist; nothing ever calls `storeInInbox` on pause.
- GREEN-asserts: `storeInInbox` was called **once per message** with the message's
  `contactPeerId` + exact `wireEnvelope`; each row is persisted as `status:'inboxed',
  transport:'inbox'` (mirrors `retry_unacked_messages_use_case.dart:96-99`).
- Mutation-that-re-reds: skip the `storeInInbox` call (deposit nothing) → rows never reach `inboxed`.
- Distinct-event discriminator: emits `PAUSE_FLUSH_INBOX_DEPOSITED` (NOT the existing
  `APP_LIFECYCLE_PAUSE_TRANSITION`) per deposited id — proves deposit path, not the failed-transition
  path.

**T2 — `...::issues the inbox deposit BEFORE any best-effort direct flush` (deposit-first ordering — the guarantee)**
- Tier: application/unit.
- Shape/setup: `FakeP2PService` appends an ordered event log: `storeInInbox` pushes `'inbox'`, the
  (best-effort, no-op-in-DRAFT) direct attempt pushes `'direct'`. One `sending` message.
- RED-on-HEAD-because: no flush exists / no ordering guarantee.
- GREEN-asserts: in the recorded order, `'inbox'` index < `'direct'` index for the same id (proposal
  §12 "issue the inbox deposit *before* the direct attempts").
- Mutation-that-re-reds: swap the two so direct is issued/awaited first → ordering assertion fails.
- Distinct-event discriminator: `PAUSE_FLUSH_INBOX_DEPOSITED` MUST precede any
  `PAUSE_FLUSH_DIRECT_ATTEMPT` event for that id.

**T3 — `...::no sending messages → no bg-task, no storeInInbox (PS-1 preserved)`**
- Tier: application/unit.
- Shape/setup: empty repo; `FakeP2PService` + `FakeBgTaskInvoker` recording `bg:begin`/`bg:end`.
- RED-on-HEAD-because: on a naive implementation that always acquires the bg task, `bg:begin` count
  would be 1. (Lock first so the new stage can't regress the DB-only no-op path.)
- GREEN-asserts: `storeInInbox` count 0 AND `bg:begin` count 0; the existing
  `APP_LIFECYCLE_PAUSE_NO_SENDING_MESSAGES` event still fires.
- Mutation-that-re-reds: acquire the bg task before checking emptiness → `bg:begin` count 1.

**T4 — `...::a failed/timed-out deposit leaves the row as 'failed' (PS-2)`**
- Tier: application/unit.
- Shape/setup: one `sending` message; `FakeP2PService.storeInInbox` returns `false` (or throws /
  exceeds the per-message budget).
- RED-on-HEAD-because: use-case missing.
- GREEN-asserts: row ends `status:'failed'` (NOT left in `sending`, NOT `inboxed`); emits
  `PAUSE_FLUSH_INBOX_DEPOSIT_FAILED`; resume retry can still pick it up.
- Mutation-that-re-reds: on deposit-false, mark `inboxed` anyway → row wrongly `inboxed`.
- Discriminator: `PAUSE_FLUSH_INBOX_DEPOSIT_FAILED` vs `PAUSE_FLUSH_INBOX_DEPOSITED`.

**T5 — `...::skips null/empty/legacy-unsafe wireEnvelope, marks failed (mirrors retry_unacked guards)`**
- Tier: application/unit.
- Shape/setup: one `sending` row with `wireEnvelope == null`; one with an
  `isUnsafeLegacyOutboundEnvelope` envelope.
- RED-on-HEAD-because: use-case missing.
- GREEN-asserts: `storeInInbox` is NEVER called for these rows; each ends `failed`; emits
  `PAUSE_FLUSH_SKIP_NULL_ENVELOPE` / `PAUSE_FLUSH_SKIP_LEGACY_ENVELOPE`
  (parallels `retry_unacked_messages_use_case.dart:68-89`).
- Mutation-that-re-reds: drop the null guard → `storeInInbox` called with `null!` → throws / records
  a call.

**T6 — `...::total flush is bounded — stops depositing once the wall-clock budget is exhausted (PS-2 for the remainder)`**
- Tier: application/unit (fake clock / injected budget).
- Shape/setup: N `sending` rows where `FakeP2PService.storeInInbox` advances a fake clock; injected
  `flushBudget = <from FDC-S4>` (provisional small value for the test).
- RED-on-HEAD-because: use-case missing / unbounded.
- GREEN-asserts: deposits stop once cumulative time ≥ budget; **already-deposited** rows are
  `inboxed`, **not-yet-reached** rows stay `failed` (never stranded in `sending`); emits
  `PAUSE_FLUSH_BUDGET_EXHAUSTED` with a remaining-count.
- Mutation-that-re-reds: remove the budget check → loops all N (no `BUDGET_EXHAUSTED` event).

**T7 — `handle_app_paused_test.dart`-adjacent: `handleAppPaused` with NO p2pService injected stays DB-only (PS-1/regression)`**
- Tier: application/unit (extends existing `handle_app_paused` suite, in `test/core/**`).
- Shape/setup: call `handleAppPaused(messageRepo: ...)` with the **flush seam absent** (default
  null), one `sending` row.
- RED-on-HEAD-because: N/A as a NEW assertion — this is the **preservation lock**: it must stay
  GREEN through the edit (row → `failed`, no `storeInInbox`). It RED-flips only if the implementation
  makes the deposit stage unconditional instead of injection-gated.
- GREEN-asserts: row → `failed`; no bridge/network seam touched; existing
  `APP_LIFECYCLE_PAUSE_TRANSITION` still fires.
- Mutation-that-re-reds: make the new stage run even when the seam is null → it would try to deposit
  / NPE.

### Tier: device-proof (real iOS bg window) — CLOSURE GATE, finalize after FDC-S4

**T8 (CLOSURE GATE) — sim/device: open → send one message → immediately lock; recipient receives it**
- Tier: integration/device (reliability-sim, two-peer).
- Shape/setup: peer A foreground-sends to **offline** peer B, then A is backgrounded/locked within
  `<from FDC-S4>` ms (before the live race could have deposited). A real
  `beginBackgroundTask` window must let the inbox deposit complete. B comes online and drains.
- RED-on-HEAD-because: today no network on pause → message stuck `failed` on A → B never receives.
- GREEN-asserts: B receives exactly one copy (dedup by `messageId`); A's row ends `inboxed`.
- Mutation-that-re-reds: skip the pause deposit → B times out.
- **`<from FDC-S4>`**: the exact lock-delay budget, the bg-window length to request, and the
  scenario id / dart-define. Authored only after S4 confirms feasibility + bound.
- Registration: new `classify_path()` case + dart-define in
  `scripts/check_reliability_simulation_discovery.sh`; run via `/sims <scope> --only N`.

## Test Coverage Matrix
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Deposit in-flight sends to inbox (§6.4) | deposit per-message; mark `inboxed` | unit | `flush_pending_sends_on_pause_use_case_test.dart::deposits each in-flight sending message` | use-case absent | skip `storeInInbox` | `./scripts/run_host_test_gates.sh core-host-all` | `test/core/**` auto-glob |
| Deposit BEFORE direct (§12) | inbox issued before best-effort direct | unit | `...::issues the inbox deposit BEFORE any best-effort direct flush` | no ordering | swap order | core-host-all | auto-glob |
| PS-1 no-op when empty | no bg-task, no deposit | unit | `...::no sending messages → no bg-task, no storeInInbox` | naive always-acquires | acquire before emptiness check | core-host-all | auto-glob |
| PS-2 failed deposit → `failed` | never stranded `sending` | unit | `...::a failed/timed-out deposit leaves the row as 'failed'` | use-case absent | mark `inboxed` on false | core-host-all | auto-glob |
| Envelope guards | skip null/legacy, mark failed | unit | `...::skips null/empty/legacy-unsafe wireEnvelope` | use-case absent | drop null guard | core-host-all | auto-glob |
| Bounded flush | stop at budget; remainder `failed` | unit | `...::total flush is bounded` | unbounded | remove budget check | core-host-all | auto-glob |
| PS-1/regression DB-only when unwired | injection-gated stage | unit | `handle_app_paused_test.dart::handleAppPaused with no p2pService stays DB-only` | preservation | unconditional stage | `./scripts/run_host_test_gates.sh core-host-all` + `./scripts/run_test_gates.sh 1to1` | `test/core/**` + 1to1 array (`send_then_lock_delivery_test.dart`) |
| Open-send-lock delivers (device) | real iOS bg window deposits | device | `pause-flush sim scenario` **`<from FDC-S4>`** | no network on pause | skip pause deposit | `/sims <scope> --only N` **`<from FDC-S4>`** | `classify_path()` + dart-define **(post-S4)** |

## Blind-Spot Sweep
- **Lifecycle/derived-state durability:** flush marks `inboxed`/`transport:'inbox'` so resume's
  `verify_inbox_custody_use_case.dart` / feed status derive consistently (not `sending`). Locked by
  T1/T4. The bg-task assertion must be **released** (`bg:end`) on every exit path (success, budget,
  throw) — locked by a `bg:end`-count assertion folded into T3/T6.
- **Sibling-surface consistency:** group pause path (`recoverStuckSendingMessages`,
  `handle_app_paused.dart:89-119`) unchanged (PS-3); group flush is out-of-scope. N/A for this plan.
- **Destructive-action side-effects:** none — flush only deposits + status-marks; it never deletes.
  A duplicate vs a live-race delivery is dedup'd server-side by `messageId` (verified
  `backend_memory.go:121-142`). Locked by reasoning + T8.
- **Invariant re-verification under new transition:** new `sending→inboxed` transition at pause must
  not collide with the existing `sending→failed`; T1 (deposit→inboxed) + T4 (fail→failed) + T7
  (unwired→failed) jointly cover the branch.
- **Bridge serialization (proposal §10):** the pause flush funnels `storeInInbox` through the single
  Go bridge alongside any teardown; on iOS the deposit competes with `_onDetached` if `detached`
  follows `paused`. **N/A-with-note:** flush is `paused`-only and bounded; FDC-S4 must confirm the
  ordering vs a fast `paused→detached`.
- **Badge anti-flap (FDC-14 prerequisite):** the pause/flush path is a background inbox write, not a
  node teardown — it must NOT flip the self online-dot (`NodeState.badgeReadinessState`,
  `node_state.dart:147-153`). **Row: assert NO `connecting`/`offline` `badgeReadinessState` transition
  is emitted on `stateStream` during the pause-flush** (`paused`-only, bounded; preservation lock;
  FDC-14 owns the new `onlineDirect` tier).

## Invariants (locked by tests)
- INV-1: pause flush issues the inbox deposit **before** any best-effort direct attempt (T2).
- INV-2: a message is **never left in `sending`** after the flush — it is `inboxed` (deposit ok) or
  `failed` (deposit absent/failed/over-budget/guarded) (T1/T4/T5/T6/T7).
- INV-3: with no in-flight `sending` messages, pause acquires **no** bg task and makes **no** network
  call (T3).
- INV-4: the bg-task assertion is released on every exit path (T3/T6 `bg:end` count).
- INV-5: a duplicate delivered by both the flush deposit and the live race is harmless — receiver
  dedups by `messageId` (no new server work; T8 + verified store dedup).

## Step-By-Step Implementation Plan
1. **RED:** add `test/core/lifecycle/flush_pending_sends_on_pause_use_case_test.dart` with T1–T6 and
   the `FakeP2PService` / `FakeBgTaskInvoker` recorders. Confirm all RED for the real reason.
2. **RED:** add T7 to `handle_app_paused_test.dart` (preservation lock — should already pass; proves
   the seam is injection-gated once implemented).
3. **Seam:** create `lib/core/lifecycle/flush_pending_sends_on_pause_use_case.dart`:
   `Future<FlushResult> flushPendingSendsOnPause({ required MessageRepository messageRepo, required
   StoreInInbox storeInInbox, required Duration perMessageBudget, required Duration flushBudget,
   required Clock now })`. Deposit-first; mirror `retry_unacked_messages_use_case.dart:64-108`
   guards; emit the new `PAUSE_FLUSH_*` events. **No platform/bg code here** — pure, host-testable.
4. **Wire (gated):** extend `handleAppPaused` (`handle_app_paused.dart:29`) with **optional**
   `P2PService? p2pService`, `BgTaskInvoker? bgTask`, budgets. When present AND there are sending
   rows: `bg:begin` → run `flushPendingSendsOnPause` → `bg:end` (always). When absent: today's
   DB-only path (PS-1/T7). Run the deposit stage **before** the existing
   `conditionalTransitionStatus` sweep so deposited rows skip the failed-transition.
5. **Wire (main):** inject `p2pService` + `callBgBegin/callBgEnd` seam at `main.dart:_onPaused`
   (`:4314`) via the widget (`_MknoonAppState`, `:3354`/`:3443`). Keep `_onPaused` fire-and-forget
   (PS-4).
6. **GREEN + mutate** each behavior-bearing edit per the catalog.
7. **Stop-if blockers:**
   - **Stop-if** FDC-S4 says a network call on `paused` is infeasible on iOS → ship the Dart
     use-case behind a flag + reduce to the resume-side custody (re-scope to FDC-04) and mark T8
     waived-not-deferred.
   - **Stop-if** the bound from S4 is < a single `storeInInbox` round-trip → cap the flush to the
     **most-recent 1** in-flight send and document the accepted partial-coverage.

## Risks And Edge Cases
- **iOS gives no window / `bg:begin` refused** → `callBgBegin` returns null; flush degrades to a
  silent no-op and rows stay `failed` (T4 path) — exactly today's behavior, no regression. Pinned by
  a "bg refused → all rows `failed`, no throw" variant of T4.
- **`paused` immediately followed by `detached`** → bridge contention with teardown; bounded flush +
  S4 ordering. Pinned by reasoning; device by T8.
- **Many in-flight sends exceed the bound** → bounded loop, remainder `failed` (T6).
- **Duplicate delivery** (flush + live race both land) → `messageId` dedup (INV-5).
- **Budget regression to NET-REL locks** → flush adds a NEW path; existing 1to1/send tests
  (`send_chat_message_use_case_test.dart`) must stay green — full 1to1 gate in acceptance.

## Device/Relay Proof Profile
- **Host-only for closure:** T1–T7 (the flush logic, ordering, bounds, guards, PS-1/PS-2) close on
  `core-host-all` + the 1to1 gate. **This is the implementable-now surface.**
- **Requires sim/device (CLOSURE GATE):** T8 — real iOS `beginBackgroundTask` window actually
  completing the deposit before suspend. Closure scenario: `/sims <scope> --only N` **`<from FDC-S4>`**
  (two-peer, A locks within `<from FDC-S4>` ms of send, B drains). Cannot be proven on host (no real
  suspend); cannot be authored to final detail until FDC-S4.

## Acceptance Gates
```
# host floor (new unit test auto-globs via test/core/**)
./scripts/run_host_test_gates.sh core-host-all          # expected: 0 failures  (249/249 core files PASS, 0 fail)

# 1:1 family — locks send_then_lock_delivery + send_chat_message + p2p_service_impl + roundtrip
./scripts/run_test_gates.sh 1to1                         # expected: 1226+<new>, 0 reg

# lifecycle / pause suites (all under test/core/**, already auto-globbed)
#   handle_app_paused_test / _edge_cases / _group / pause_resume_retry_smoke / app_lifecycle_pause_integration

# transport gate (no transport edits expected — regression guard)
./scripts/run_test_gates.sh transport                    # expected: 0 reg

# group-safety floor (pause-flush touches the shared pause path — must stay 1:1-only — Scope Guard)
./scripts/run_test_gates.sh groups                       # expected: 0 fail (no group regression)

# device-proof CLOSURE GATE (post-FDC-S4)
./scripts/check_reliability_simulation_discovery.sh
/sims <scope> --only N                                   # <from FDC-S4>

# hygiene
flutter analyze                                          # 0 new
git diff --check
```

## Known-Failure Interpretation
- Pre-existing `app_lifecycle_pause_integration_test` / durable-media-upload flakes (per MEMORY) are
  NOT this plan — re-run in isolation before attributing.
- A RED T8 on host is EXPECTED (no real suspend); it is the device closure gate, not a host failure.

## Done Criteria
- [ ] T1–T7 written RED-first, GREEN, each mutation re-reds.
- [ ] `flushPendingSendsOnPause` deposits before direct; never strands `sending` (INV-1/INV-2).
- [ ] PS-1..PS-5 preserved (existing `handle_app_paused_*` suites green).
- [ ] `core-host-all` 0-fail; `1to1` 0-reg; `transport` 0-reg; `flutter analyze` 0-new;
      `git diff --check` clean.
- [ ] **FDC-S4 resolved** → T8 scenario authored, registered, and run green. **(CLOSURE GATE)**

## Scope Guard (hard Do-not)
- **Do NOT** alter the group pause path (`recoverStuckSendingMessages`, `handle_app_paused.dart:89-119` / PS-3) — the pause-flush is **1:1-only**; group flush is an out-of-scope follow-up. **Group-safety floor:** `./scripts/run_test_gates.sh groups` 0-regress.
- Do NOT hold a direct/relay socket alive in background (inbox-store-only).
- Do NOT add server-side dedup/idempotency (exists).
- Do NOT move the flush to `detached`, and do NOT touch `_onDetached`.
- Do NOT lift the send-path `lowConfidence` inbox gate here (that is FDC-03).
- Do NOT change any libp2p/relay timeout or Go host code.

## Accepted Differences
- A backgrounded send may produce a duplicate inbox copy vs the live race — accepted (receiver
  dedup, proposal §6.2 honesty note).
- Recipient does one extra retrieve+ack per deposited copy — accepted cost for reliability
  (proposal §6.2 "recipient cost rises").

## Dependency Impact
- **Depends on:** FDC-S4 (iOS bg-window feasibility + bound) — gating. Reuses existing
  `bg:begin`/`bg:end` bridge seam (`bridge.dart:777-798`) and the `storeInInbox` seam.
- **Touches shared `lib/main.dart`** (`_onPaused` wiring) — sequential collision with any sibling
  FDC plan editing `main.dart` (notably FDC-04 resume lifecycle). Run after / coordinate with those.
- **Touches `lib/core/lifecycle/handle_app_paused.dart`** — collision with any other pause-path plan.
- No DB migration. No Go/relay deploy.
```
