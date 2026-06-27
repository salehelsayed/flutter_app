# FDC-06 — Graceful pause-flush of in-flight sends to inbox  (Feature Improvement)

Status: awaiting-review — **FDC-S4 RESOLVED 2026-06-26**; **re-verified against `new-orbit` HEAD 2026-06-27** (5-agent verify→refute). DRAFT banner lifted; `<from FDC-S4>` values filled below; results in `FDC-S4-ios-pause-flush-feasibility-RESULTS.md`. **⚠ This plan was reframed from "greenfield" to "EDIT-IN-PLACE": FDC-S4 already shipped the full flush inline — see the callout below.**
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.4 "Lifecycle handshake + graceful handoff" / §7 state-machine `on PAUSE|HIDDEN` / §8 P1-2 / §12 "On pause, issue the inbox deposit *before* the direct attempts")

---

## ✅ FDC-S4 RESOLVED — values locked (2026-06-26)

**FDC-S4 measured the iOS pre-suspension window on a real device (iPhone 13 / iOS 26.5). Verdict:
FEASIBLE via Option A.** Full numbers/method: **`FDC-S4-ios-pause-flush-feasibility-RESULTS.md`**. The
`<from FDC-S4>` markers below are now resolved:

1. **Feasible? YES (device-corroborated).** Use the **`bg:begin`/`bg:end` bridge** seam
   (`lib/core/bridge/bridge.dart:777`/`:816` → `ios/Runner/GoBridge.swift:213-241`/`:243-256`,
   `UIApplication.beginBackgroundTask(withName:"mknoon.sendMessage")`) — **not** the migration-keepalive
   channel. A real in-flight message deposited to the relay inbox in **~52 ms**, row left in custody, **no
   app termination** in any trial.
2. **The bound:** per-message **3 s** (device-PROVEN — NLC 100 % loss cut `storeInInbox` at `ms:3006`),
   **overall ceiling 8 s** (fixed), cap **N = 5** newest-first (observed p95 `sendingCount` = 1), inside a
   granted `backgroundTimeRemaining` of **≈28.7 s** (8/8 finite reads, ≥25 s ✅). These replace every
   `<from FDC-S4>` budget marker below.
3. ⚠ **CRITICAL design constraint — do NOT read `backgroundTimeRemaining` at pause.** At the pause instant
   (the flush's own read point) it returns `DBL_MAX`; the finite ≈28.7 s only arms ~1.5 s into background.
   **The flush must gate/size itself on the FIXED 8 s ceiling, never on a live `backgroundTimeRemaining` read.**

**Residual device-proof (deferred-not-waived — the T8 CLOSURE GATE):** S4 measured only **one** iOS major
(26.5) — the "≥2 versions" exit-gate is not fully met — and a Send-button UX bug blocked the N∈{1,3,8} burst
matrix + the wider `getSendingOutgoingMessages().length` distribution. So the **8 s ceiling trip** and
**cap-N sizing** are host-locked but not device-exercised; confirm on a 2nd iOS major + run the burst matrix
when the UX bug is fixed (that Send-button UX bug is now its own plan, **170** — `170-1to1-send-button-frozen-snackbar-overlap-tdd-plan.md`; landing it unblocks the N∈{3,8} burst). Device-proof rows below remain **CLOSURE GATE**.

---

## ⚠ FDC-S4 already SHIPPED the flush inline — FDC-06 is EDIT-IN-PLACE, not greenfield

5-agent verify→refute against `new-orbit` HEAD (2026-06-27): **the entire bounded flush already exists and is
host-locked.** FDC-06 *productionizes a flag-gated prototype*; it does not build from scratch. Every "create a
new use-case file / inject the seam / P2PService injection is structurally impossible" framing that this plan
once carried is now **false**. What S4 shipped:

| Already on HEAD | Where | Consequence for FDC-06 |
|---|---|---|
| `_pauseFlushInFlightSends(...)` — the full Option-A flush (`callBgBegin` → newest-first `..sort(createdAt desc)` → `take(cap)` → per-msg + overall-ceiling-bounded `storeInInbox` → `callBgEnd` in `finally`; returns the accepted ids) | `handle_app_paused.dart:345-455` | **Do NOT create `flush_pending_sends_on_pause_use_case.dart`.** Edit this method in place. Extraction buys zero behavior and orphans the locks. |
| 4 bounds consts (`kPauseFlushCap=5` / `kPauseFlushPerMessageBudget=3s` / `kPauseFlushOverallCeiling=8s` / `kPauseFlushRequiredGrantMs=25000`) + flag `kFdcPauseFlushEnabled` | `handle_app_paused.dart:42/45/51/56` + `:31-36` | **Import, don't re-derive.** |
| `_onPaused` already passes `p2pService` + `bridge` + `enablePauseFlush:kFdcPauseFlushEnabled`, stays `unawaited` | `main.dart:4360-4370` | **No wiring/plumbing work remains.** (`_MknoonAppState` never existed — the state is `_MyAppState`, `main.dart:3536`.) |
| **13 host locks** across 5 groups (DISABLED 2 / ENABLED 6 / BOUNDS 3 / ASSERTION-REFUSED 1 / FLOW-EVENTS 1) | `test/core/lifecycle/handle_app_paused_pause_flush_test.dart` (~485 lines) | **Extend this file.** A new file orphans all 13 AND the S4 device `[FLOW]` harness. |
| Event taxonomy `APP_LIFECYCLE_PAUSE_FLUSH_BEGIN/_DEPOSIT(ok,ms)/_COMPLETE(expired,deposited,skipped)/_IN_CUSTODY` + fake hooks (`storeInInboxLog`, `lastStoreInInboxTimeoutMs`, `onStoreInInbox`) | code `:206/381/427/443`; `fake_p2p_service.dart:74/79/88` | **Keep these names.** Renaming to the old plan's `PAUSE_FLUSH_INBOX_*` orphans the 13 locks AND breaks the device RESULTS parser (it greps these exact strings off the reliable Flutter `[FLOW]` channel). |

**The ONE behavior-bearing edit FDC-06 owns — the custody flip.** An ACCEPTED deposit today is left in
`status:'sending'` (custody) and skipped in the mark-failed loop (`:200-209`, `continue` at `:209` — **no
status write**); lock #3 asserts exactly that (`status=='sending'`, `flushDepositedCount==1`,
`transitionedCount==0`, `:154-156`). **FDC-06 flips it to `status:'inboxed', transport:'inbox'`** (mirror
`retry_unacked_messages_use_case.dart:91-100`). Edit lock #3 → RED; add the `saveMessage(copyWith(...))` in the
deposited branch → GREEN; reverting to `'sending'` (today's behavior) re-reds. This is the headline
RED→GREEN→re-RED and is **mutation-clean**.

**Everything else is either already-green preservation OR a secondary decision** — see the reframed RED catalog:
- **Genuinely new (besides the custody flip):** legacy-unsafe-envelope guard (absent today — the flush filters
  only null/empty at `:362`, never `isUnsafeLegacyOutboundEnvelope`); the **flag-default decision**
  (`kFdcPauseFlushEnabled` defaults `false` → *nothing ships in a normal build*; FDC-06 must decide
  flip-default-ON / remove-the-gate, else FDC-06 ships no production behavior); a **double-`_onPaused`
  idempotence** lock; a **resume-survival** lock (custody row must survive `recoverStuckSendingMessages`).
- **Already green (preservation, NOT RED-on-HEAD):** deposit-each / no-op-when-empty / reject→failed /
  throw→failed+assertion-released / null-envelope-skip / cap+per-msg+ceiling bounds / unwired→DB-only.
- **Vacuous as written:** the old T2 "deposit BEFORE direct" — the prototype is **inbox-store-only with no
  direct attempt at all**, so there is no ordering to test. Reframe to "no dial/direct attempt is made".
- **Do NOT drop yet:** the grant-probe scaffolding (`probePauseBackgroundGrant` / `PAUSE_GRANT_PROBE`) — T8 is
  still owed on a 2nd iOS major and the device harness reads it; remove it only in a post-T8 cleanup.

---

## Source Of Truth
- Proposal §6.4 / §7 / §8-P1-2 / §12 (anchored above). `scripts/run_test_gates.sh` array membership
  and literal gate commands win over any prose here.
- This epic's roadmap: **FDC-00** (sequencing) ; spike **FDC-S4** (this plan's gate).
- Verified-against-source on branch `new-orbit`, 2026-06.

## Session Classification
**Implementation-ready, EDIT-IN-PLACE (FDC-S4 resolved + prototype shipped).** The host/application flush logic
AND the iOS bg-window wiring already exist on HEAD (flag-gated, OFF by default — see the callout above). FDC-06
is a small, well-bounded productionization: (1) flip accepted-deposit custody `sending`→`inboxed`/`inbox`,
(2) make a flag-default decision (ship it on), (3) optionally add the legacy-envelope guard, (4) add the two
missing idempotence/resume-survival locks — all on the existing `bg:begin`/`bg:end` seam, the **fixed 8 s
ceiling**, 3 s per-message, cap N=5, and **never reading `backgroundTimeRemaining` at pause** (S4: `DBL_MAX`).
The **device-proof tier (T8)** remains a CLOSURE GATE — S4 covered only iOS 26.5 / N=1, so a 2nd iOS major +
the N∈{3,8} burst (unblocked by plan **170**) are still owed, and the T8 sim scenario is **not yet registered**
in `check_reliability_simulation_discovery.sh`.

## Exact Problem Statement
**What's broken/missing.** The "open app → type one message → immediately close the app" case can
silently fail to deliver. On `paused`/`hidden`, `_onPaused()` (`lib/main.dart:4339-4399`) fires
`handleAppPaused()` (`lib/core/lifecycle/handle_app_paused.dart:139-309`). **By default (`FDC_PAUSE_FLUSH`
flag OFF) it is byte-for-byte local-DB-only** (doc-comment `:122-135`: "no network calls, no P2PService"):
it transitions every in-flight `sending` row to `failed` (`:200-237`, `conditionalTransitionStatus` `:212-216`)
so a later resume can retry. But if the OS suspends the process before the user ever foregrounds again (phone
locked, app evicted), **no resume fires and the message is never deposited to the durable inbox** — the only
guaranteed carrier (§6.2(b)). The message sits as `failed` on the sender's device only. *(The FDC-S4 prototype
already deposits — but only when the flag is built ON, and it leaves the row in `sending` custody, not the
durable `inboxed` state resume relies on. Flipping that and shipping it on is FDC-06's job.)*

**Who feels it (post-FDC-03).** FDC-03 landed: the send-path concurrent durable inbox now fires for **all
unknown-presence sends** (`send_chat_message_use_case.dart:697-700`, `unknownPresence = !isAlreadyConnected
&& !isLocalPeer && !isConnectedToPeer`; `kLowConfidenceWindow` is **RETIRED**, `:75-78`). So the residual
cohort that still has **no** concurrent inbox copy when the app is closed mid-flight is: **reuse-connected,
LAN-local, and otherwise-connected peers** (a live-only send — LAN-live / direct-live / relay-live at
`:751-764` / `:773-789` / `:846-861`). For these, if the live race (eval `:1000-1035`) hasn't acked when the
user locks, the durable copy was never written → FDC-06's pause-flush is the carrier. (Even for the
unknown-presence cohort, FDC-03's inbox copy is fire-and-forget and may not have completed before suspend; a
pause-flush re-deposit is harmless — relay dedups by `messageId`.)

**Why.** Unbounded network is forbidden on pause; before FDC-S4 there was no bounded pre-suspension window in
which to deposit custody to the relay inbox. FDC-S4 narrowed the invariant and built that window
(`beginBackgroundTask`); FDC-06 makes the resulting custody durable and turns it on.

**What must improve.** On pause/hidden, the bounded flush must **deposit** each eligible in-flight `sending`
message's wire envelope to the relay inbox via `storeInInbox` and then **persist the accepted row as
`status:'inboxed', transport:'inbox'`** (not leave it `sending`), so an open-send-close still delivers AND a
later resume does not re-send it as a fresh `sending`. The flush is **inbox-store-only** (no dial, no held
connection); there is no best-effort direct attempt to order against (the proposal §12 "deposit before direct"
ordering is satisfied vacuously — the prototype never dials).

**What must stay unchanged (preserved sentinels).**
- PS-1: when there are **no** in-flight `sending` messages, pause stays a **pure no-op / DB-only**
  path with no bridge `bg:begin` and no `storeInInbox` call (`handle_app_paused_test.dart:47-65`).
- PS-2: a message whose inbox deposit **fails or times out** still ends as `failed` (today's
  behavior) so resume retry (`retry_failed_messages_use_case.dart`) still picks it up — flush must
  not strand a row in `sending`.
- PS-3: group stale-sending recovery (`handle_app_paused.dart:241-270`, `recoverStuckSendingMessages` `:243`)
  is unchanged.
- PS-4: `_onPaused` stays **fire-and-forget** / never throws to the lifecycle callback
  (`main.dart:4339-4399`) — see Step 7 (hardening resolved as "keep `unawaited`").
- PS-5: `detached` teardown (`_onDetached`, `main.dart` ~`:4319-4337`) is untouched — flush is on
  `paused`/`hidden`, NOT `detached` (the node is already being torn down there).

## Root Cause (verify→refute confirmed — REFRAMED 2026-06-27)
- **Mechanism (CORRECTED — the deposit is NOT "structurally impossible"; it already exists, flag-gated):**
  `handleAppPaused` (`handle_app_paused.dart:139-155`) already takes `P2PService? p2pService`, `Bridge? bridge`,
  `bool enablePauseFlush`, `flushCap`, `perMessageBudget`, `overallCeiling`, and a test-seam `nowMs`. When the
  flag is ON it runs `_pauseFlushInFlightSends` (`:345-455`), which deposits via `storeInInbox`
  (`:415-419` → `p2p_service.dart:156`). The **two real gaps** are: **(a)** an accepted deposit is left in
  `status:'sending'` and merely *skipped* from the mark-failed loop (`:200-209`, `continue` at `:209` — **no
  durable status write**), so resume's `recoverStuckSendingMessages` re-fails it and retry re-deposits it; and
  **(b)** the whole path ships **OFF by default** (`kFdcPauseFlushEnabled` defaults `false`, `:31-36`), so a
  normal build still does pure mark-failed. FDC-06 closes both.
- **The deposit pattern to mirror for the custody flip:**
  `retry_unacked_messages_use_case.dart:91-100` does
  `p2pService.storeInInbox(msg.contactPeerId, msg.wireEnvelope!)` → on success
  `copyWith(status:'inboxed', transport:'inbox')` (`:98`). FDC-06 applies that same `copyWith` to the deposited
  ids in the `_IN_CUSTODY` branch. *(Note: that use-case also guards `isUnsafeLegacyOutboundEnvelope` at `:77`;
  the pause-flush does NOT today — see the legacy-guard decision in the RED catalog.)*
- **iOS window — RESOLVED by FDC-S4 (feasible):** the `paused` transition grants ≈28.7 s via an explicit
  `beginBackgroundTask` assertion (the `bg:begin`/`bg:end` seam); a real deposit completed in ~52 ms with no
  termination. ⚠ But `backgroundTimeRemaining` reads `DBL_MAX` *at* the pause instant (the finite grant arms
  ~1.5 s later) → the flush must gate on the **fixed 8 s ceiling**, never a live read.
- **Refuted / do-NOT-re-introduce:**
  - Do NOT hold a direct/relay socket alive in background to "finish the live race" (proposal §6.4
    "Never hold a direct connection alive in background"; §12 iOS-background risk). The flush is
    **inbox-store-only**, not a transport keep-alive.
  - Do NOT add server-side idempotency — store dedup by `messageId` is already present
    (`go-relay-server/backend_memory.go:121-128` / `backend_redis.go:287-298` via `extractMessageId` →
    `InboxStoreResultDuplicate`; `inbox_store.go`), so a duplicate of a copy the live race also delivered is
    harmless. *(Note the durability contingency: dedup is correct, but custody itself is only durable when the
    relay runs FDC-10's Redis backend — see Risks.)*
  - Do NOT move the flush to `detached` — the node is being released there (`_onDetached`, `main.dart` ~`:4319`),
    and `detached` does not reliably fire before OS kill.
  - Do NOT extract a new use-case file or a `BgTaskInvoker` abstraction — the flush is already inline and the
    locks fake the concrete `Bridge` (`_FlushFakeBridge` in the test); an abstraction orphans them.

## Real Scope
**In scope (EDIT-IN-PLACE on the shipped prototype).**
- **Custody flip (the one behavior-bearing edit):** in `_pauseFlushInFlightSends`'s deposited branch /
  `handleAppPaused`'s `_IN_CUSTODY` branch (`handle_app_paused.dart:200-209`), persist each accepted id as
  `status:'inboxed', transport:'inbox'` (mirror `retry_unacked_messages_use_case.dart:98`) instead of leaving
  it `sending`.
- **Flag-default decision (required):** flip `kFdcPauseFlushEnabled` to ship the flush in a normal build
  (default ON, or remove the `enablePauseFlush` gate and make the narrowed invariant unconditional per S4 §5).
  Keep the dart-define escape hatch only if there's a reason to disable.
- **Legacy-envelope guard (decision):** add the `isUnsafeLegacyOutboundEnvelope` skip the flush lacks today
  (`:362` filters only null/empty) to mirror `retry_unacked:77` — OR record a justified N/A.
- **Two missing locks:** double-`_onPaused` idempotence (paused+hidden both fire; the custody flip is the
  self-heal) and resume-survival (an `inboxed` custody row must survive `recoverStuckSendingMessages` + retry).
- The bg-window acquire/release (`bg:begin`/`bg:end`) and all bounds are **already implemented + locked** —
  preserve, don't re-build.

**Out of scope (owning FDC-xx).**
- The send-path concurrent-inbox generalization (lifting the `lowConfidence` gate) → **FDC-03 — DONE** (landed
  on `new-orbit`; `kLowConfidenceWindow` retired). Nothing to do here.
- Parallel resume re-prime (the §6.4 resume half) → **FDC-05 / P1-2 resume**.
- Presence-aware emphasis → **FDC-03 / P1-1**.
- Any Go host / relay change → **FDC-07+ / P2**.
- Group-message pause flush (this plan covers 1:1; group uses `recoverStuckSendingMessages`) →
  deferred follow-up; PS-3 keeps the existing group path unchanged.

## Files To Inspect Next  (anchors re-verified against `new-orbit` HEAD 2026-06-27)
**Production — the ONE file FDC-06 edits**
- `lib/core/lifecycle/handle_app_paused.dart` — `handleAppPaused` `:139-309`; the **deposited/`_IN_CUSTODY`
  branch to edit** `:200-209` (add the `inboxed`/`inbox` `saveMessage`); the flush core
  `_pauseFlushInFlightSends` `:345-455` (candidate filter `:360-365` — where the legacy guard would go); the
  flag `:31-36`; the 4 consts `:42/45/51/56`; the grant-probe scaffolding `:66-102` (KEEP until T8).
  **No new file.**
- `lib/main.dart` — `_onPaused` `:4339-4399` (ALREADY wires `p2pService`/`bridge`/`enablePauseFlush`
  `:4360-4370`; only the flag default / optional begin→await→end hardening may change); `messageRepository`
  construction `:965`; state class is `_MyAppState` `:3536` (there is **no** `_MknoonAppState`).
**Production — read-only references (model / seam to mirror)**
- `lib/core/services/p2p_service.dart:156` (`storeInInbox(toPeerId, message, {int? timeoutMs})`).
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart` — deposit-then-mark pattern
  `:91-100` (`copyWith(status:'inboxed', transport:'inbox')` `:98`); null/empty guard `:68-74`; legacy guard
  `:77` (`isUnsafeLegacyOutboundEnvelope`).
- `lib/features/conversation/application/retry_failed_messages_use_case.dart:224` (`status!='failed'` skip),
  `:246-261` (`transport=='inbox'` keeps it inboxed) — proves the custody flip is re-send-safe.
- `lib/core/lifecycle/handle_app_resumed.dart:609-623` (Step 8a `recoverStuckSendingMessagesFn` blanket
  `sending`→`failed` — the FIRST thing resume does; `inboxed` survives it).
- `lib/features/conversation/domain/repositories/message_repository.dart:86`
  (`getSendingOutgoingMessages` — DB orderBy is `timestamp ASC` in `messages_db_helpers.dart:839`; the flush
  re-sorts newest-first itself at `:364`, so repo order doesn't matter) + `conditionalTransitionStatus` /
  `saveMessage`.
- `lib/features/conversation/domain/models/conversation_message.dart:59` (`wireEnvelope`), `:170-209`
  (`copyWith`, null-sentinel pattern).
- `lib/core/bridge/bridge.dart:777` (`callBgBegin` → `String?`), `:816` (`callBgEnd(bridge, String? taskId)`).
**Direct + integration tests**
- **`test/core/lifecycle/handle_app_paused_pause_flush_test.dart` (EXISTS, 13 locks — the file to EXTEND).**
- `test/core/services/fake_p2p_service.dart:74/79/88` (`lastStoreInInboxTimeoutMs` / `storeInInboxLog` /
  `onStoreInInbox`) and its `_FlushFakeBridge`.
- `handle_app_paused_test.dart`, `handle_app_paused_edge_cases_test.dart`, `handle_app_paused_group_test.dart`,
  `pause_resume_retry_smoke_test.dart`, `app_lifecycle_pause_integration_test.dart` (all auto-glob `test/core/**`).
- `test/features/conversation/integration/send_then_lock_delivery_test.dart` (the open-send-lock scenario;
  already in the 1to1 array, `run_test_gates.sh:27`).
**Dependency-only context (device-proof only)**
- `ios/Runner/GoBridge.swift:213-241` (`bgBegin`), `:243-256` (`bgEnd`), `:266` (grantProbe) — real
  `beginBackgroundTask`.
- `go-relay-server/backend_memory.go:121-128` / `backend_redis.go:287-298` (`messageId` dedup).
- `lib/features/account_migration/application/migration_transfer_keep_alive.dart:16` (≈30 s bound precedent;
  superseded by S4's measured ≈28.7 s).

## Existing Tests Covering This Area
| Test | Exists? | In which gate array |
|---|---|---|
| **`handle_app_paused_pause_flush_test.dart`** (the 13 FDC-S4 locks — **EXTEND this**) | **EXISTS** | core-host-all auto-glob (`test/core/**`) |
| `test/core/lifecycle/handle_app_paused_test.dart` | EXISTS | core-host-all auto-glob (`test/core/**`) |
| `handle_app_paused_edge_cases_test.dart` | EXISTS | core-host-all auto-glob |
| `handle_app_paused_group_test.dart` | EXISTS | core-host-all auto-glob |
| `pause_resume_retry_smoke_test.dart` | EXISTS | core-host-all auto-glob |
| `app_lifecycle_pause_integration_test.dart` | EXISTS | core-host-all auto-glob |
| `test/core/services/fake_p2p_service.dart` (`storeInInboxLog`/`onStoreInInbox`/`lastStoreInInboxTimeoutMs`, `_FlushFakeBridge`) | EXISTS | (fake; used by the above) |
| `send_then_lock_delivery_test.dart` | EXISTS | **1to1** array (`run_test_gates.sh:27`) |
| device-proof pause-flush sim scenario | **MISSING (new)** | needs `classify_path()` + dart-define case in `check_reliability_simulation_discovery.sh` (CLOSURE GATE) |

**The 13 existing locks (the reconciliation map for the RED catalog below):**
*DISABLED:* (1) omitting flush params = legacy mark-failed · (2) `enablePauseFlush:false` does no network even
with deps. *ENABLED:* (3) **accepted deposit leaves the row in CUSTODY — asserts `status=='sending'` (`:154-156`)
← THIS is the lock FDC-06 INVERTS to `inboxed`** · (4) reject→failed · (5) throw→failed + assertion released ·
(6) null/empty-envelope rows fall through · (7) mixed accept/reject routed per-deposit · (8) no depositable rows
→ never touches the bridge. *BOUNDS:* (9) newest-first cap · (10) per-message budget = `timeoutMs` · (11) overall
ceiling stops loop (`expired:true`). *ASSERTION-REFUSED:* (12) flush runs without an assertion when `bgBegin`
refused. *FLOW-EVENTS:* (13) emits `BEGIN`/`DEPOSIT`/`COMPLETE` with expected fields.

`test/core/**` auto-globs into the host floor, so extending the existing file needs **no** array edit. The
device-proof sim scenario DOES need a `classify_path()` case + dart-define in
`scripts/check_reliability_simulation_discovery.sh` (`classify_path` `:71` has no pause/flush case today —
genuinely owed).

## RED Test Catalog  (REFRAMED 2026-06-27 — most host behavior is ALREADY LOCKED by FDC-S4)
> The S4 prototype + its 13 locks already cover deposit-each / no-op-when-empty / reject→failed /
> throw→failed+assertion-released / null-skip / cap+per-msg+ceiling bounds / unwired→DB-only / event shapes.
> Those are **preservation (P-x)**, not RED-on-HEAD. The genuinely-new RED FDC-06 owns is small — **all events
> use the SHIPPED `APP_LIFECYCLE_PAUSE_FLUSH_*` names** (renaming orphans the 13 locks + the device harness).
> Add the NR-x tests by **extending `handle_app_paused_pause_flush_test.dart`** (no new file).

### Tier: unit/application (host — `flutter_test`) — GENUINELY-NEW RED (FDC-06's actual work)

**NR-1 (HEADLINE — the custody flip) — `handle_app_paused_pause_flush_test.dart` (EDIT existing lock #3): `accepted deposit persists the row as 'inboxed'/transport:'inbox' (custody)`**
- Tier: application/unit.
- Shape/setup: enable the flush with `FakeP2PService` (`storeInInbox`→true) + `_FlushFakeBridge`; one `sending`
  row with a non-null `wireEnvelope`. Call `handleAppPaused(... enablePauseFlush:true, p2pService, bridge)`.
- RED-on-HEAD-because: lock #3 today asserts the accepted row stays `status=='sending'` (`:154-156`); the code
  only emits `APP_LIFECYCLE_PAUSE_FLUSH_IN_CUSTODY` then `continue` (`:200-209`) — **no status write**. Change
  the assertion to `status=='inboxed' && transport=='inbox'` and it goes RED.
- GREEN-asserts: the deposited row is persisted `status:'inboxed', transport:'inbox'` (via `saveMessage(
  copyWith(...))` mirroring `retry_unacked_messages_use_case.dart:98`); `flushDepositedCount==1`,
  `transitionedCount==0`; `APP_LIFECYCLE_PAUSE_FLUSH_IN_CUSTODY` still fires for the id.
- Mutation-that-re-reds: revert the `saveMessage` (leave the `continue` only) → row stays `sending` (today's
  behavior) → the edited assertion re-reds. **Mutation-clean.**
- Discriminator: assert the persisted `status=='inboxed'` (DB state) AND the `_IN_CUSTODY` event — distinguishes
  the custody path from the `APP_LIFECYCLE_PAUSE_TRANSITION` (→failed) path.

**NR-2 (DECISION — legacy-unsafe guard) — `...::a legacy-unsafe wireEnvelope is NOT deposited and is marked failed`**
- Tier: application/unit.
- Shape/setup: enable the flush; one `sending` row whose `wireEnvelope` satisfies
  `isUnsafeLegacyOutboundEnvelope` (and one normal row as a control).
- RED-on-HEAD-because: the flush's candidate filter (`:362`) checks only `wireEnvelope?.isNotEmpty` — it does
  **not** call `isUnsafeLegacyOutboundEnvelope` (unlike `retry_unacked:77`), so today the legacy row **is**
  deposited.
- GREEN-asserts: `storeInInbox` is NOT called for the legacy row; it ends `failed`; (optional new event
  `APP_LIFECYCLE_PAUSE_FLUSH_SKIP_LEGACY` if a skip event is added). The control row still deposits.
- Mutation-that-re-reds: drop the new guard → the legacy row is deposited again (`storeInInbox` records it).
- **Decision:** adopt this (cheap defense-in-depth mirroring `retry_unacked`) OR record a justified N/A — see
  the Blind-Spot Sweep. Default recommendation: **adopt** (a `sending` row CAN carry a stale envelope after an
  app-update format change; the relay would reject/mis-handle it).

**NR-3 (DECISION — ship it: flag default ON / gate removed) — `...::with deps present and NO explicit flag, the flush runs (default-on contract)`**
- Tier: application/unit.
- Shape/setup: call `handleAppPaused(messageRepo, p2pService, bridge)` **without** passing `enablePauseFlush`
  (i.e. the production default after FDC-06 removes the gate / flips the default), one depositable `sending` row.
- RED-on-HEAD-because: `enablePauseFlush` defaults `false` (`:146`) and `kFdcPauseFlushEnabled` is `false`
  (`:31-36`) → today this deposits nothing → row → failed. This **inverts existing lock #2**
  ("`enablePauseFlush:false` with deps → no network"), which FDC-06 must update.
- GREEN-asserts: the row is deposited + `inboxed` (NR-1 behavior) with no explicit flag.
- Mutation-that-re-reds: re-introduce the `enablePauseFlush==false` early-return / restore the `false` default →
  no deposit.
- **Decision (required, the single biggest one):** pick the mechanism — recommend **drop the `enablePauseFlush`
  gate and run whenever `p2pService`+`bridge` are present** (S4 §5: make the narrowed invariant unconditional).
  Update `main.dart:4360-4370` to stop threading `kFdcPauseFlushEnabled`. **If the team chooses to keep it OFF,
  FDC-06 ships no production behavior and T8 cannot be a prod closure gate — say so explicitly.**

**NR-4 (idempotence — the custody flip is the self-heal) — `...::two consecutive pauses deposit each row at most once`**
- Tier: application/unit (repo whose `getSendingOutgoingMessages` reflects `saveMessage` status writes).
- Shape/setup: enable the flush; one depositable `sending` row; call `handleAppPaused(...)` **twice** in a row
  (models `_onPaused` firing for BOTH `hidden` and `paused` — `main.dart:4313-4316`, no debounce, contrast the
  `_isResuming` guard at `:4402`).
- RED-on-HEAD-because: today the accepted row stays `sending`, so the 2nd call's `getSendingOutgoingMessages`
  returns it again → `storeInInbox` is called **twice** (relay dedups, but a 2nd bg assertion is taken).
- GREEN-asserts: after NR-1, the 1st call marks it `inboxed` → the 2nd call's `getSendingOutgoingMessages`
  (`WHERE status='sending'`) returns nothing for it → `storeInInbox` called exactly **once** total.
- Mutation-that-re-reds: revert the custody flip (NR-1) → 2 deposits again.

**NR-5 (resume survival — invariant re-verification under the new transition) — `...::an 'inboxed'/transport:'inbox' custody row survives resume recoverStuckSendingMessages + retry_failed without re-send`**
- Tier: application/unit (focused on the resume seam).
- Shape/setup: seed a row in the post-flush state (`status:'inboxed', transport:'inbox'`); run the resume Step-8a
  path (`recoverStuckSendingMessagesFn`, `handle_app_resumed.dart:609-623`) and a `retry_failed` pass.
- RED-on-HEAD-because (as a mutation): if the custody state were `'sending'` (today's prototype),
  `recoverStuckSendingMessages` (`UPDATE … WHERE status='sending'`, `messages_db_helpers.dart:937-938`) would
  flip it to `failed` and `retry_failed` would re-send it — proving the custody status choice matters.
- GREEN-asserts: the `inboxed` row is untouched by `recoverStuckSendingMessages` (skips non-`sending`) and by
  `retry_failed` (`status!='failed'` skip `:224`; `transport=='inbox'` keeps it inboxed `:246-261`); no re-send.
- Mutation-that-re-reds: use `'sending'` custody → the row is re-failed then re-sent.

### Tier: preservation (the 13 FDC-S4 locks — must STAY GREEN; reverting any FDC-06 edit must not red them)

- **P-1 / P-2 (PS-1):** empty repo → no `bg:begin`, no `storeInInbox` (locks #1, #2, #8). *NR-3 changes the
  meaning of lock #2 — update lock #2, keep the no-op-when-empty intent.*
- **P-3 (PS-2):** reject→failed (lock #4); throw→failed + `bg:end` still called (lock #5).
- **P-4:** null/empty envelope falls through (lock #6); mixed accept/reject routed per-deposit (lock #7).
- **P-5:** newest-first cap (lock #9); per-message budget == `timeoutMs` (lock #10); overall ceiling stops the
  loop with `expired:true` (lock #11) — gate on the injected fixed clock, **never** `backgroundTimeRemaining`.
- **P-6:** assertion-refused (`bgBegin` returns `''`) → flush still deposits, `callBgEnd(null)` no-ops (lock #12).
- **P-7 (store-only, replaces the old vacuous "deposit before direct"):** the flush makes **no dial / no direct
  attempt** — assert the fake's direct/dial methods are never called during the flush (there is no direct path
  to order against; §12 ordering is satisfied vacuously). Fold into the FLOW-EVENTS lock (#13).

### Tier: device-proof (real iOS bg window) — CLOSURE GATE, finalize after FDC-S4

**T8 (CLOSURE GATE) — sim/device: open → send one message → immediately lock; recipient receives it**
- Tier: integration/device (reliability-sim, two-peer).
- Shape/setup: peer A foreground-sends to **offline** peer B, then A is backgrounded/locked within
  **~200 ms** of send (FDC-S4's campaign profile — before the live race could have deposited). The real
  `beginBackgroundTask` window (≈28.7 s granted) must let the inbox deposit complete (S4 saw ~52 ms). B comes
  online and drains.
- RED-on-HEAD-because: with the flag OFF (today's default) no network on pause → message stuck `failed` on A →
  B never receives. (After NR-3 ships the flush on, this is the prod closure gate.)
- GREEN-asserts: B receives exactly one copy (dedup by `messageId`); A's row ends `inboxed`.
- Mutation-that-re-reds: skip the pause deposit → B times out.
- **FDC-S4-resolved values:** lock-delay ~200 ms; request the bg window via `bg:begin`; flush gated by the
  **fixed 8 s ceiling** (NOT a `backgroundTimeRemaining` read — `DBL_MAX` at pause), per-message 3 s, cap N=5.
  **Still CLOSURE GATE:** S4 covered only iOS 26.5 and could not stage N≥3 (Send-button UX bug → now plan
  **170**), so this scenario must also exercise a **2nd iOS major + an N∈{3,8} burst** (land 170 first).
- Registration: **genuinely owed** — there is no pause/flush case in `check_reliability_simulation_discovery.sh`
  `classify_path()` (`:71`) today; add a `classify_path()` case + dart-define, then `/sims <scope> --only N`.
  Until NR-3 ships the flush on by default, the sim build must pass `--dart-define=FDC_PAUSE_FLUSH=1`.

## Test Coverage Matrix  (all new rows EXTEND `handle_app_paused_pause_flush_test.dart`)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| **NR-1 Custody flip (§6.4)** | accepted deposit → `inboxed`/`inbox`, not `sending` | unit | `handle_app_paused_pause_flush_test.dart::accepted deposit persists 'inboxed'/'inbox'` (EDIT lock #3) | code leaves row `sending` (`:200-209`); lock #3 asserts `sending` (`:156`) | revert the `saveMessage` → row `sending` | `./scripts/run_host_test_gates.sh core-host-all` | `test/core/**` auto-glob |
| **NR-2 Legacy guard (decision)** | skip `isUnsafeLegacyOutboundEnvelope`, mark failed | unit | `...::legacy-unsafe envelope not deposited, marked failed` | filter checks only `isNotEmpty` (`:362`), deposits legacy | drop the guard → legacy deposited | core-host-all | auto-glob |
| **NR-3 Ship-it: default ON (decision)** | flush runs with deps + no explicit flag | unit | `...::deps present + no flag → flush runs (default-on)` | `enablePauseFlush` defaults `false` (`:146`); inverts lock #2 | restore `false` default / gate | core-host-all | auto-glob |
| **NR-4 Double-pause idempotence** | 2 pauses deposit each row ≤ once | unit | `...::two consecutive pauses deposit each row at most once` | `sending` custody → 2nd pause re-deposits | revert custody flip → 2 deposits | core-host-all | auto-glob |
| **NR-5 Resume survival (new transition)** | `inboxed` survives recoverStuck + retry | unit | `...::inboxed custody survives resume recoverStuck + retry_failed` | with `sending` custody, Step-8a re-fails+re-sends | use `sending` custody → re-failed/re-sent | core-host-all | auto-glob |
| **P-1..P-7 Preservation** | the 13 S4 locks (deposit/empty/reject/throw/null/bounds/refused/store-only) | unit | `handle_app_paused_pause_flush_test.dart` (existing 13 locks) | already GREEN — must stay green | (revert the corresponding FDC-06 edit) | core-host-all + `./scripts/run_test_gates.sh 1to1` | `test/core/**` + 1to1 (`send_then_lock_delivery_test.dart`, `run_test_gates.sh:27`) |
| **T8 Open-send-lock delivers (device)** | real iOS bg window deposits (≈28.7 s grant; ~52 ms deposit) | device | pause-flush sim scenario (lock ~200 ms post-send; fixed 8 s ceiling) | flag OFF today → no network on pause | skip pause deposit | `/sims <scope> --only N` | **new** `classify_path()` case + dart-define **(CLOSURE GATE: also needs 2nd iOS major + N≥3 burst via plan 170)** |

## Blind-Spot Sweep
- **Lifecycle/derived-state durability:** the custody flip marks `inboxed`/`transport:'inbox'` so resume +
  feed status derive consistently (not `sending`). Locked by **NR-1**. The bg-task assertion is released
  (`bg:end`) on every exit path (success, budget, throw) — **already** in a `finally` (`:436-439`) and locked
  by S4 lock #5; FDC-06 must not regress it.
- **Invariant re-verification under the new transition (NR-1's `sending→inboxed`):** the row's new resting state
  must survive every later transition that the old `sending`/`failed` states implied. **NEWLY ADDED:**
  - **Resume Step-8a survival (NR-5):** the FIRST thing resume does is `recoverStuckSendingMessagesFn`
    (`handle_app_resumed.dart:609-623`, blanket `sending`→`failed`). An `inboxed` row survives it
    (`UPDATE … WHERE status='sending'`, `messages_db_helpers.dart:937-938`) and `retry_failed` skips it
    (`:224`, `:246-261`). The prototype's `sending` custody does **not** survive — it gets re-failed + re-sent
    every resume. NR-5 locks the chosen status.
  - **Double-`_onPaused` idempotence (NR-4):** `paused` AND `hidden` both route to `_onPaused` with **no
    debounce** (`main.dart:4313-4316`; contrast `_isResuming` at `:4402`). The custody flip makes the 2nd fire
    a no-op for already-`inboxed` rows (they leave the `sending` query). NR-4 locks deposit-at-most-once.
- **Destructive-action side-effects:** none — flush only deposits + status-marks; it never deletes. A duplicate
  vs a live-race delivery is dedup'd server-side by `messageId` (`backend_memory.go:121-128` /
  `backend_redis.go:287-298`). Locked by reasoning + T8.
- **Sibling-surface consistency:** group pause path (`recoverStuckSendingMessages`,
  `handle_app_paused.dart:241-270`) unchanged (PS-3); group flush is out-of-scope. **N/A** for this plan.
- **Durability contingency (FDC-10) — NEWLY ADDED:** the custody guarantee is only as durable as the relay
  backend. FDC-10's relay **code default is in-memory** (durability is a deploy-env choice); a deposit into an
  in-memory relay is wiped on relay restart even though the sender row shows `inboxed`. **N/A-for-a-host-test,
  but a real product caveat** — the open-send-close guarantee holds only when the live relay runs FDC-10's
  Redis backend. Recorded in Risks + Dependency Impact (do NOT silently treat `inboxed` as durable).
- **Bridge serialization (proposal §10):** the flush funnels `storeInInbox` through the single Go bridge; on
  iOS it competes with `_onDetached` if `detached` follows `paused`. **N/A-with-note:** flush is `paused`-only,
  bounded (cap 5 / 8 s); S4 device runs saw no contention at N=1 — re-confirm under a concurrent send at N≥3.
- **Badge anti-flap (FDC-14) — DOWNGRADED to N/A-with-note:** `handleAppPaused`/`_pauseFlushInFlightSends`
  never reference `NodeState`/`stateStream` (verified `:139-455`), so there is **no code path** by which the
  pause-flush could emit a `badgeReadinessState` transition. The assertion would lock nothing → **N/A** (keep
  as a one-line preservation note, not a test). *(The old anchor `node_state.dart:147-153` was stale —
  `badgeReadinessState` is `lib/features/p2p/domain/models/node_state.dart:161-171`.)*

## Invariants (locked by tests)
- INV-1 (custody flip — NEW): an accepted deposit is persisted `status:'inboxed', transport:'inbox'` — **never
  left `sending`** (NR-1). This is the one behavior FDC-06 adds.
- INV-2: a message is **never left in `sending`** after the flush — it is `inboxed` (deposit ok) or `failed`
  (deposit absent/failed/over-budget/guarded) (NR-1 + P-3/P-4/P-5).
- INV-3 (store-only): the flush makes **no dial / no direct attempt** — inbox-store-only; the §12 "deposit
  before direct" ordering is satisfied vacuously because there is no direct leg (P-7). *(Replaces the old INV-1,
  which assumed a direct attempt that does not exist.)*
- INV-4: with no in-flight `sending` messages, pause acquires **no** bg task and makes **no** network call
  (P-1/P-2).
- INV-5: the bg-task assertion is released on every exit path — already in a `finally` (`:436-439`), locked by
  S4 lock #5; FDC-06 must not regress it.
- INV-6 (idempotence — NEW): two consecutive pauses (`hidden`+`paused`) deposit each row **at most once** —
  the custody flip removes the deposited row from the `sending` query (NR-4).
- INV-7 (resume survival — NEW): an `inboxed`/`inbox` custody row survives resume's
  `recoverStuckSendingMessages` + `retry_failed` without re-send (NR-5).
- INV-8: a duplicate delivered by both the flush deposit and the live race is harmless — receiver dedups by
  `messageId` (no new server work; T8 + verified store dedup). *(Durability of the deposit itself is contingent
  on FDC-10's Redis backend — see Risks.)*

## Step-By-Step Implementation Plan  (EDIT-IN-PLACE — no new files)
0. **Dirty-tree snapshot:** `git status --short` (this is a shared `new-orbit` tree with concurrent Dart dev —
   scope all diffs to `handle_app_paused.dart`, `handle_app_paused_pause_flush_test.dart`, and `main.dart`;
   never `git checkout` sibling files).
1. **RED-1 (custody flip):** in `handle_app_paused_pause_flush_test.dart` EDIT lock #3 to assert the accepted
   row is `status=='inboxed' && transport=='inbox'` (was `'sending'`, `:154-156`). Run it → RED.
2. **GREEN-1:** in `handle_app_paused.dart`'s deposited branch (`:200-209`), before/with the `continue`, persist
   `messageRepo.saveMessage(msg.copyWith(status:'inboxed', transport:'inbox'))` for each deposited id (mirror
   `retry_unacked_messages_use_case.dart:98`). Keep the `_IN_CUSTODY` event. Re-run → GREEN; revert the
   `saveMessage` → RED (mutation-clean).
3. **NR-3 decision (ship it):** drop the `enablePauseFlush` gate (recommended) so the flush runs whenever
   `p2pService`+`bridge` are present; update the inverted lock #2; update `main.dart:4360-4370` to stop threading
   `kFdcPauseFlushEnabled` into `handleAppPaused`. Add the NR-3 RED→GREEN test. *(If the team keeps it OFF,
   document that FDC-06 ships nothing and demote T8 from a prod gate.)*
4. **NR-2 decision (legacy guard):** add `isUnsafeLegacyOutboundEnvelope` to the candidate filter (`:360-365`)
   to mirror `retry_unacked:77` (recommended), with the NR-2 RED→GREEN test; OR record the justified N/A.
5. **NR-4 + NR-5:** add the double-pause idempotence lock and the resume-survival lock (extend the test file).
   NR-4 is GREEN once NR-1 lands; NR-5's mutation (`sending` custody) re-reds.
6. **Keep the grant-probe scaffolding** (`probePauseBackgroundGrant` / `APP_LIFECYCLE_PAUSE_GRANT_PROBE` /
   `callBgGrantProbe`) — do **NOT** delete it: T8 is still owed on a 2nd iOS major and the device RESULTS parser
   greps it. Remove only in a post-T8 cleanup ticket.
7. **`_onPaused` hardening decision (resolve, don't leave open):** the in-code TODO (`main.dart:4354`) flags a
   possible begin→await→end restructure. **Recommendation: keep `_onPaused` `unawaited` (PS-4)** — S4
   device-verified the native `bg:begin` assertion is acquired in time (the same window the interactive send path
   already relies on), and the assertion (not the Dart future) holds the process alive. Record this as resolved;
   if a device flake appears, the fallback is a bounded `await` inside `_onPaused` that still never throws.
8. **GREEN + mutate** each NR-x; **run the 13 preservation locks** — all must stay green.
9. **Device T8:** add the `classify_path()` case + dart-define in `check_reliability_simulation_discovery.sh`;
   `/sims <scope> --list` then `--only N`; run on a 2nd iOS major + the N∈{3,8} burst (after plan 170 lands).
10. **Constraint (carry from S4):** size/gate the flush on the **fixed 8 s ceiling only** — never read
    `backgroundTimeRemaining` (it returns `DBL_MAX` at the pause instant; the finite ≈28.7 s grant arms ~1.5 s
    into background). Already implemented (`:392-409`); preserve.

**Stop-if blockers (FDC-S4 outcome: both CLEARED):**
- ~~**Stop-if** FDC-S4 says a network call on `paused` is infeasible on iOS~~ → **CLEARED:** S4 = FEASIBLE
  (a real deposit landed in ~52 ms inside a ≈28.7 s window, no app termination).
- ~~**Stop-if** the bound from S4 is < a single `storeInInbox` round-trip~~ → **CLEARED:** the ≈28.7 s grant
  ≫ a single deposit (~52 ms); the fixed 8 s ceiling holds ~5 deposits comfortably → flush keeps cap N=5.

## Risks And Edge Cases
- **iOS gives no window / `bg:begin` refused** → `callBgBegin` returns `null` (Android: no native handler) or
  `''` (iOS refused); the flush still runs without an assertion (P-6 / lock #12); on a true refusal the
  store-and-exit usually still completes, and any row whose deposit doesn't land stays `failed` — no regression.
- **Relay backend is in-memory (FDC-10 not deployed) — NEWLY CALLED OUT** → the deposit lands but a relay
  restart wipes it, despite the sender row reading `inboxed`. The open-send-close guarantee holds **only** with
  FDC-10's Redis backend. Cross-plan caveat (Dependency Impact); not host-testable.
- **Double `_onPaused` (hidden+paused)** → without the custody flip, the row is re-deposited on the 2nd fire
  (relay dedups, but a 2nd bg assertion is taken). The custody flip makes the 2nd fire a no-op (INV-6, NR-4).
- **`paused` immediately followed by `detached`** → bridge contention with teardown; bounded flush (cap 5/8 s).
  Pinned by reasoning; device-confirm at N≥3 (S4 saw no contention at N=1).
- **Many in-flight sends exceed the bound** → bounded loop, remainder `failed` (P-5 cap+ceiling).
- **Duplicate delivery** (flush + live race / FDC-03 fire-and-forget both land) → `messageId` dedup (INV-8).
- **Budget regression to NET-REL locks** → existing 1to1/send tests (`send_chat_message_use_case_test.dart`)
  must stay green — full 1to1 gate in acceptance.

## Device/Relay Proof Profile
- **Host-only for closure:** NR-1..NR-5 (custody flip, legacy guard, default-on, idempotence, resume survival)
  + the 13 preservation locks (P-1..P-7) close on `core-host-all` + the 1to1 gate. **This is the
  implementable-now surface.**
- **Requires sim/device (CLOSURE GATE):** T8 — real iOS `beginBackgroundTask` window actually completing the
  deposit before suspend, with the flush shipped ON (NR-3). Closure scenario: `/sims <scope> --only N` (two-peer,
  A locks ~200 ms after send, B drains; flush gated by the **fixed 8 s ceiling**). S4 device-proved the
  single-message path (~52 ms deposit, ≈28.7 s grant; deposit-first + mark-on-reject + 3 s hung-net cut) on iOS
  26.5; **still owed:** a 2nd iOS major + the N∈{3,8} burst (blocked by the Send-button UX bug → now plan 170)
  + recipient-side "exactly once" drain. Cannot be proven on host (no real suspend).
- **The T8 sim scenario is not yet registered** — `check_reliability_simulation_discovery.sh` `classify_path()`
  has no pause/flush case; that wiring (+ dart-define) is owed before `/sims` will list it.

## Acceptance Gates
```
# RED first — edit lock #3 to assert 'inboxed' (NR-1), confirm it FAILS on HEAD for the documented reason
flutter test test/core/lifecycle/handle_app_paused_pause_flush_test.dart \
  --plain-name 'accepted deposit'                        # expect: FAIL (code leaves row 'sending')

# Direct GREEN (after the saveMessage custody flip + NR-2..NR-5)
flutter test test/core/lifecycle/handle_app_paused_pause_flush_test.dart   # expect: all pass (13 + new NR-x)

# host floor (the extended test auto-globs via test/core/**)
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
/sims <scope> --only N                                   # lock ~200ms post-send; fixed 8s ceiling; also needs 2nd iOS major + N>=3 burst (CLOSURE GATE)

# hygiene
flutter analyze                                          # 0 new
git diff --check
```

## Known-Failure Interpretation
- **Pre-existing `core-host-all` fail (NOT this plan):** the cold-start `transport_metrics_privacy_test`
  `sinceProcessStartMs` privacy-allowlist failure (FDC-S0/S1) is branch-wide on `new-orbit` — prove via
  stash-revert before attributing. So "0 failures" above means "no NEW failures beyond that one."
- Pre-existing `app_lifecycle_pause_integration_test` / durable-media-upload flakes (per MEMORY) are NOT this
  plan — re-run in isolation before attributing.
- A RED T8 on host is EXPECTED (no real suspend); it is the device closure gate, not a host failure.
- **NR-1's RED is intentional and authored-first** (edit lock #3 → fail) — it is the documented RED-on-HEAD, not
  a regression.

## Done Criteria
- [ ] **NR-1 custody flip** written RED-first (edit lock #3), GREEN via the `saveMessage(copyWith(inboxed/inbox))`,
      mutation (revert to `sending`) re-reds.
- [ ] **NR-3 ship-it decision made** (flag default ON / gate removed) + test; OR explicitly documented as
      shipped-OFF (then T8 is not a prod gate).
- [ ] **NR-2 legacy-guard** adopted (test) OR justified N/A recorded.
- [ ] **NR-4 idempotence + NR-5 resume-survival** locks added and green; their mutations re-red.
- [ ] The 13 FDC-S4 preservation locks (P-1..P-7) stay green; grant-probe scaffolding retained (not dropped).
- [ ] Custody never strands `sending` (INV-1/INV-2); flush is store-only/no-dial (INV-3).
- [ ] `core-host-all` 0-NEW-fail (the FDC-S0/S1 `transport_metrics_privacy` fail is pre-existing); `1to1` 0-reg;
      `transport` 0-reg; `groups` 0-reg; `flutter analyze` 0-new; `git diff --check` clean.
- [x] **FDC-S4 resolved** (feasible; ≈28.7 s grant; 3 s / 8 s / N=5; `DBL_MAX`-at-pause constraint locked;
      prototype + 13 host locks shipped inline).
- [ ] T8 scenario authored, **registered** (`classify_path()` + dart-define), and run green on **2 iOS majors +
      N∈{3,8} burst** (after plan 170). **(CLOSURE GATE — S4 covered iOS 26.5 / N=1 only)**

## Scope Guard (hard Do-not)
- **Do NOT** create a new use-case file or a `BgTaskInvoker`/`StoreInInbox` abstraction — edit
  `_pauseFlushInFlightSends` IN PLACE; the locks fake the concrete `Bridge`/`P2PService`.
- **Do NOT rename the event taxonomy** — keep `APP_LIFECYCLE_PAUSE_FLUSH_*`/`_IN_CUSTODY` (renaming orphans the
  13 host locks AND the FDC-S4 device `[FLOW]` parser).
- **Do NOT drop the grant-probe scaffolding** (`probePauseBackgroundGrant` / `PAUSE_GRANT_PROBE`) until T8 closes
  on a 2nd iOS major — the device harness reads it.
- **Do NOT** alter the group pause path (`recoverStuckSendingMessages`, `handle_app_paused.dart:241-270` / PS-3) —
  the pause-flush is **1:1-only**; group flush is an out-of-scope follow-up. **Group-safety floor:**
  `./scripts/run_test_gates.sh groups` 0-regress.
- Do NOT hold a direct/relay socket alive in background (inbox-store-only); do NOT add a direct/dial leg.
- Do NOT add server-side dedup/idempotency (exists, `messageId`).
- Do NOT move the flush to `detached`, and do NOT touch `_onDetached`.
- Do NOT touch the send-path inbox gate — FDC-03 already landed it (`unknownPresence`, `kLowConfidenceWindow`
  retired).
- Do NOT change any libp2p/relay timeout or Go host code.

## Accepted Differences
- A backgrounded send may produce a duplicate inbox copy vs the live race — accepted (receiver
  dedup, proposal §6.2 honesty note).
- Recipient does one extra retrieve+ack per deposited copy — accepted cost for reliability
  (proposal §6.2 "recipient cost rises").

## Dependency Impact
- **Depends on:** FDC-S4 (iOS bg-window feasibility + bound) — **RESOLVED 2026-06-26**, prototype + 13 host
  locks **shipped inline** (feasible; ≈28.7 s grant; per-message 3 s / ceiling 8 s / cap N=5; use
  `bg:begin`/`bg:end`; do NOT read `backgroundTimeRemaining` at pause). Reuses the `bg:begin`/`bg:end` seam
  (`bridge.dart:777`/`:816`) and `storeInInbox` (`p2p_service.dart:156`).
- **FDC-03 is DONE** (landed `new-orbit`) — the send-path concurrent inbox now covers all unknown-presence
  sends; FDC-06's residual cohort is reuse-connected / LAN-local / connected peers. No work owed here.
- **Durability is contingent on FDC-10** — a pause-flush deposit is only durable if the live relay runs FDC-10's
  Redis backend; FDC-10's *code default* is in-memory (durability = deploy env). State the caveat where the
  reliability claim appears; do not treat `inboxed` as a durability guarantee absent the Redis deploy.
- **Plan 170 unblocks T8** — the Send-button frozen-snackbar bug (surfaced during S4) blocked the N∈{3,8} burst;
  land 170 before the T8 burst device-proof.
- **Touches `lib/main.dart` `_onPaused`** — ALREADY wired by S4 (only the flag default / optional `await`
  changes); still a sequential collision risk with sibling FDC plans editing `main.dart` (FDC-04 resume). The
  shared-tree hazard stands: scope diffs to own files, no `git checkout`.
- **Touches `lib/core/lifecycle/handle_app_paused.dart`** — collision with any other pause-path plan.
- No DB migration. No Go/relay code change (relay durability is a deploy choice owned by FDC-10).
