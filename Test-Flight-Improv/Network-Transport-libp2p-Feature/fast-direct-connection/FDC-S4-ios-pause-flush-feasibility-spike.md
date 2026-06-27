# FDC-S4 - iOS pause-flush feasibility  (Spike / Decision)

Status: **EXECUTED** — device campaign run on **iPhone 13 / iOS 26.5** (real device; the simulator can't
suspend → reports `DBL_MAX`). Full numbers + method in **`FDC-S4-ios-pause-flush-feasibility-RESULTS.md`**. **Verdict: Option A FEASIBLE** — reuse the existing `beginBackgroundTask` bridge
(`callBgBegin`/`callBgEnd` → `GoBridge.swift` `bgBegin`/`bgEnd`); **no new native code.** Measured headlines:
granted `backgroundTimeRemaining` ≈ **28.7 s** (8/8 finite reads, min = median = p90; ≥25 s ✅, the 8 s ceiling
sits ~20 s under it); a real in-flight message deposited to the relay inbox in **~52 ms**, row left in custody,
**no app termination** in any trial; per-message **3 s** budget **device-PROVEN** (NLC 100 % loss → `storeInInbox`
cut at `ms:3006`, row marked `failed` cleanly); overall ceiling **≤8 s** confirmed safe (host-locked; the 8 s
trip itself not device-reached); cap **N = 5** (observed p95 `sendingCount` = 1).
⚠ **Two carry-forward caveats for FDC-06:** (1) only **ONE** iOS version (26.5) measured — Exit-Gate-1's
"≥2 iOS versions" is **NOT fully satisfied**; (2) at the **pause instant** — the flush's own read point —
`backgroundTimeRemaining` reads `DBL_MAX` (the finite ≈28.7 s only arms ~1.5 s into background), so **FDC-06
must NOT read `backgroundTimeRemaining` at pause to size/gate the flush — use the fixed 8 s ceiling.** The
wider normal-usage `getSendingOutgoingMessages().length` distribution (Exit-Gate-2) was **not** collected (a
Send-button UX bug blocked staging a large burst) → cap = 5 is a conservative default, not a measured-p95-driven
value.

Gates: **FDC-06 (Lifecycle split + graceful handoff / pause-flush)** cannot be finalized
until this resolves. FDC-06 (proposal §6.4 / P1-2 / state machine §7 `on PAUSE | HIDDEN`)
proposes that, on app pause, every in-flight `sending` message is *flushed to the durable
inbox over the network* "before the OS suspends the process." But the current pause handler
does **zero network** (`handle_app_paused.dart:24-25`, `main.dart:4316`), and iOS gives no
guaranteed pre-suspension window. FDC-06 must NOT invent a budget, a mechanism, or a message
count out of thin air — this spike supplies all three: feasible y/n, the exact mechanism to
reuse, and the bound (N messages × per-message budget × overall ceiling). Proposal §10
explicitly flags this as "unresolved" and §11 open-question 6 asks "how many in-flight sends
must it cover."

---

## Question

On the iOS pause transition, can the app perform a **bounded network call** — depositing the
in-flight `sending` 1:1 (and group) messages into the durable relay inbox — and *complete it*
before iOS suspends the process? Specifically:

1. **Feasible y/n** for a network flush on pause without breaking the app or burning battery.
2. **Which mechanism** carries it (`UIApplication.beginBackgroundTask`, an APNs-backed path,
   or neither).
3. **The bound**: realistic pre-suspension budget (ms), per-message inbox budget, overall
   ceiling, and the **count N** of in-flight sends the flush must cover.

This must be reconciled with the existing **"no network on pause"** invariant
(`handle_app_paused.dart:24-25`: "Does LOCAL DB work only — no network calls, no P2PService
interaction").

---

## Why it blocks

If FDC-06 is finalized without this spike it would have to *guess*:

- **A budget.** Guessing "3s" or "10s" risks either truncating the flush (message lost on a
  mid-send close — the exact "send one message then close" case the proposal targets) or
  over-running the OS grant so iOS *terminates* the app for overrunning the background
  assertion (the migration code's expiration handler exists precisely to avoid this:
  `AppDelegate.swift:411-413`).
- **A mechanism.** It might propose a brand-new native channel when a **proven
  `beginBackgroundTask` bridge already ships** (`GoBridge.swift:183-217`,
  `bridge.dart:777-797`) — duplicated, additive-only risk, and a second expiration code path
  to get wrong.
- **A message count.** Without knowing N (how many rows `getSendingOutgoingMessages` returns
  on a realistic pause), FDC-06 can't size the per-message vs overall budget, and can't decide
  whether to flush all rows or cap+prioritize the newest.

It would also risk **double-covering** work the send path already protects: each interactive
send *already* wraps itself in a `beginBackgroundTask` (`feed_wired.dart:2053`,
`group_conversation_wired.dart:1994/2380/3941`, `share_batch_delivery_coordinator.dart:400`).
FDC-06 needs this spike to define the pause-flush as the **safety net for sends whose
bg-task-protected future was abandoned**, not a redundant re-send of sends already in flight.

---

## Background (grounded in real source)

**What pause does today — local DB only, no network.**
- `_onPaused()` fires `handleAppPaused(...)` **unawaited** with the comment "we have at most a
  few hundred milliseconds" and "handleAppPaused() is local DB only — no network calls, no
  p2pService" (`lib/main.dart:4314-4316`).
- `handleAppPaused` (`lib/core/lifecycle/handle_app_paused.dart:29`) finds all in-flight
  sending messages (`getSendingOutgoingMessages()` :41) and **transitions each `sending` →
  `failed`** via `conditionalTransitionStatus` (:61-65) so they can be retried on resume. It
  already reads `msg.wireEnvelope != null` per message (:73) — i.e. the **serialized wire
  payload needed for an inbox deposit is already on the row** (`ConversationMessage.wireEnvelope`
  `conversation_message.dart:59`, persisted as `wire_envelope` :120/:145). Groups use a 2-min
  staleness threshold (`recoverStuckSendingMessages` :92, `kPausedGroupSendingRecoveryThreshold`
  :8).
- Net: today a mid-send pause **drops the live attempt and marks the message `failed`** — the
  recipient gets nothing until the sender resumes and retries. That is the gap FDC-06 closes.

**The mechanism FDC-06 would reuse already exists and is in production.**
- iOS native: `GoBridge.swift:183-217` implements `bgBegin` / `bgEnd`. `bgBegin` calls
  `UIApplication.shared.beginBackgroundTask(withName: "mknoon.sendMessage")` on the main thread,
  with an **expiration handler** that ends the task before forced suspension (`:188-195`),
  returns the raw task id as a string, or `""` if the OS refused (`:196-198`). `bgEnd`
  (`:204-216`) ends the task by id.
- Dart seam: `callBgBegin(bridge)` → `null` on refusal/failure (`bridge.dart:777-785`),
  `callBgEnd(bridge, taskId)` (`:788-797`), wired as `bg:begin`/`bg:end`
  (`go_bridge_client.dart:153-154`, `bg:begin` allows a raw-string response).
- Already used to protect interactive sends across a foreground→background flip:
  `feed_wired.dart:2053` (begin) / `:2107` (end in `finally`); same shape in
  `group_conversation_wired.dart:334-358` (`_beginBackgroundTaskGuarded`) and
  `share_batch_delivery_coordinator.dart:400/481`.
- A **second** independent `beginBackgroundTask` user is the account-move keep-alive
  (`AppDelegate.swift:404-425`, re-armed in `applicationDidEnterBackground` :427-432), whose
  Dart doc records the empirically-relied-upon budget: iOS `beginBackgroundTask` "grants
  **roughly 30 seconds** of continued execution after backgrounding — enough to survive brief
  app switches, not indefinite background transfer" (`migration_transfer_keep_alive.dart:16-18`).

**The deposit call the flush would make.**
- `storeInInbox(toPeerId, message, {timeoutMs})` (`p2p_service.dart:150`,
  impl `p2p_service_impl.dart:3755`) → `storeInInboxDetailed` (:3769) → `callP2PInboxStore`
  (:3785) over the bridge. `message` is the serialized wire envelope. The relay **already
  dedupes by `messageId`** on store (proposal appendix: `backend_memory.go:121-142`,
  `backend_redis.go:272-295`), so a parallel/late inbox copy is harmless even if the original
  live send also lands.

**iOS background facts that bound the answer.**
- `Info.plist` UIBackgroundModes = `fetch`, `remote-notification` only
  (`ios/Runner/Info.plist:83-86`) — **no `voip`, no BGProcessing/BGAppRefresh task identifiers**.
  So the *only* execution-extension lever available without new entitlements/modes is
  `beginBackgroundTask` (a finite assertion), exactly what already ships.
- Prior art (proposal §10, §12 "Risks prior art confirms"): **Berty's node is killed within
  seconds of backgrounding**; only VOIP-class apps hold a background socket. So the flush must
  assume **tens of seconds at most**, and must be store-and-exit, never "keep a connection."

---

## Options

### Option A — Reuse the existing `beginBackgroundTask` bridge in the pause handler (recommended)

**Description.** In `_onPaused()` (the place that today fires the local-only handler), acquire a
background assertion via the existing `callBgBegin` *before* awaiting any network, run a
**bounded** inbox-deposit loop over the in-flight `sending` rows (each carries `wireEnvelope`
already), then `callBgEnd` in a `finally`. Keep the existing local `sending → failed` DB
transition **after** (or fold it: deposit-then-mark, see Decision Criteria). The flush is
**inbox-store-only** — no dial, no live race, no held connection.

- **Pros:** zero new native code (mechanism is shipped + production-proven on the send path);
  additive (no relay/Go change, NET-REL-07-safe — store dedup already exists); reuses
  `storeInInbox`'s existing per-call `timeoutMs`; the expiration handler already guarantees we
  never get terminated for overrunning the grant; symmetric with how interactive sends already
  protect themselves.
- **Cons:** `_onPaused` currently fires **unawaited** ("few hundred ms" assumption) — it must
  hold the assertion and `await` the bounded loop, a behavioral change to the pause path; the
  Go **bridge is a single serialization point** (proposal §10) so the flush competes with any
  in-flight send/teardown on the same channel; raises recipient cost (extra retrieve+ack per
  deposited id, proposal §6.2 honesty note).
- **Cost:** S–M. Dart-only (new bounded flush in `handle_app_paused.dart` + `_onPaused` wiring).
  No native, no Go, no relay deploy.
- **Additive-only / NET-REL-07:** yes — purely client-side; store path + dedup unchanged.
- **iOS:** the target case; `beginBackgroundTask` grants the ~30s-ish window
  (`migration_transfer_keep_alive.dart:16-18`), expiration handler caps the downside.
- **Android:** `beginBackgroundTask` is an iOS concept; on Android `callBgBegin` returns `null`
  (no native handler) and the flush simply runs without an assertion. Android does not
  hard-suspend on `onPause` the way iOS does, so a short flush typically completes; the
  account-move path uses a `dataSync` foreground service for *long* work
  (`migration_transfer_keep_alive.dart:13-15`) — **not needed** for a bounded store-and-exit.

### Option B — APNs-backed / self-push path (defer)

**Description.** Don't flush on pause at all; instead, when a message is left `sending` at
pause, rely on a later wake (silent/visible push or a `remote-notification`/`fetch` background
launch) to complete the deposit, or have the *recipient*'s push-to-wake pull it. Effectively
move custody off the pause transition entirely.

- **Pros:** no dependency on the fragile pause window; aligns with "background is the inbox's
  job" (§6.4).
- **Cons:** the sender's own message isn't in the inbox **until a later wake**, so a phone that
  stays backgrounded for hours delivers nothing in that window — defeats the "send one then
  close, feels reliable" goal; iOS throttles silent pushes to ~1–2/hr with no execution
  guarantee (§12); needs a self-push channel that doesn't exist today (`Info.plist` has no
  BGProcessing identifier). Strictly more infra than Option A for a *worse* P0 guarantee.
- **Cost:** L (new push/registration plumbing, relay involvement → NET-REL-07 review).
- **Verdict:** **not needed for v1**; revisit only if Option A's measured budget proves too
  small to cover realistic N.

### Option C — Status quo: keep "no network on pause", flush only on resume

**Description.** Leave `handleAppPaused` local-DB-only; let the `sending → failed` + resume
retry path (`handle_app_resumed.dart`) re-deliver.

- **Pros:** zero risk; honors the current invariant verbatim.
- **Cons:** the proposal's exact target case ("send one message then close the app") still
  delivers **late** (only on next foreground), which is the user-visible reliability complaint
  FDC-06 exists to fix.
- **Verdict:** the baseline FDC-06 is trying to improve; documents the cost of doing nothing.

---

## Method (how to measure / validate)

This spike is part **decision** (pick A vs B/C) and part **measurement** (set the budget and N).
Validate on a **real iOS device** (background suspension behavior is not faithfully reproduced
on the simulator).

**Instruments — add flow-events (kDebugMode-gated) around a prototype Option-A flush:**
- `APP_LIFECYCLE_PAUSE_FLUSH_BEGIN` { taskGranted: bool, sendingCount: N }
- `APP_LIFECYCLE_PAUSE_FLUSH_DEPOSIT` { id(8), ok: bool, ms } per message
- `APP_LIFECYCLE_PAUSE_FLUSH_COMPLETE` { deposited, skipped, totalMs, expired: bool }
- On the native side, the existing `NSLog` `BG_TASK_EXPIRED` / `BG_TASK_REFUSED`
  (`GoBridge.swift:190/197`) already mark grant/expiry — capture via Console.app / device log.

**Procedure (device):**
1. Instrument `UIApplication.shared.backgroundTimeRemaining` on the native side right after
   `bgBegin` and log it — this is the *actual* granted budget the OS reports for this app on
   this OS version. (Do NOT trust the folklore "30s"; measure it.)
2. Compose-and-send 1, then 3, then 8 messages to an **offline** peer (forces the slow path so
   they stay `sending`), and **immediately background the app** (home gesture) within ~200ms of
   tapping send. Repeat for a same-WiFi/online peer.
3. From device logs, read: granted budget (step 1), per-deposit ms, total flush ms, and whether
   `BG_TASK_EXPIRED` fired before `FLUSH_COMPLETE`.
4. Repeat under degraded network (Network Link Conditioner "Edge"/100% loss) to see the deposit
   timeout behavior and confirm the overall ceiling protects against a hung `storeInInbox`.
5. Confirm the recipient ultimately receives each id exactly once (relay `messageId` dedup) by
   draining on the recipient device.

**Counting N (how many in-flight sends to cover):**
- Add a one-off log of `getSendingOutgoingMessages().length` at pause across normal usage
  (1:1 + feed composer + group). The realistic "open app → send one → close" case is **N=1**;
  the worst realistic case is a feed multi-thread reply burst. Record the observed distribution;
  size the cap from the 95th percentile, not the theoretical max.

**Commands (read-only here — execution is for the FDC-06 implementation/validation phase, NOT
this authoring task):**
- Device build + run, then `xcrun simctl io <udid> screenshot` is **not** sufficient (sim
  doesn't suspend) — use a tethered device and `log stream --predicate 'process == "Runner"'`
  to capture `BG_TASK_*` + the flow-events.

## Decision Criteria

Pick **Option A** if all hold (expected to hold, given the mechanism already ships and is used
on the send path):
- **Granted budget** (measured `backgroundTimeRemaining` after `bgBegin`) ≥ **~25s** on the
  target iOS versions — comfortably above the flush ceiling below. (If the OS routinely grants
  < 10s, tighten the cap or fall to Option B.)
- A bounded flush of **N ≤ cap** messages completes within the **overall ceiling** in ≥ 95% of
  device trials on a reachable network, and **never** triggers app *termination* (only the
  benign `BG_TASK_EXPIRED` path) on a hung network.

Set the bound as:
- **Per-message inbox budget** = reuse the existing inbox budget (`storeInInbox` `timeoutMs`),
  proposal cites the interactive inbox budget; target **~3s/message**.
- **Overall ceiling** = **≤ 8s** total (well under the ~25–30s grant, leaving slack for the OS
  to actually persist + for the expiration handler). The loop stops at the ceiling even if rows
  remain.
- **Cap N** = flush the **newest-first** sending rows up to a cap (proposed **cap = 5**;
  confirm against the measured 95th-percentile of `getSendingOutgoingMessages().length`).
  Rows beyond the cap keep today's `sending → failed` + resume-retry behavior.
- **Ordering vs the local transition:** deposit **first**, and only mark a row `failed` if its
  deposit was *not* accepted — a successfully-deposited message must NOT be left `failed`
  (it is in fact in custody). (FDC-06 to lock this; today's handler blindly marks `failed`.)

Choose **Option B** only if the measured grant is too small to cover N=1 reliably; choose
**Option C** if Option A proves to *terminate* the app on any tested OS (it should not, given
the expiration handler).

## Expected Output (consumed by FDC-06)

- **Feasible: YES** (device-corroborated, not just inferred) — bounded network flush on iOS pause is
  feasible by **reusing the existing `beginBackgroundTask` bridge** (`GoBridge.swift:183-217` / `callBgBegin`/
  `callBgEnd`), no new native code and no APNs path for v1. **Device evidence:** the pause→flush path fires
  end-to-end on real iOS; a real in-flight message was deposited to the relay inbox in **~52 ms** with the row
  left in custody; **no app termination** in any trial.
- **Mechanism:** in `_onPaused`, `callBgBegin` → bounded newest-first `storeInInbox` loop over
  in-flight `sending` rows (each carries `wireEnvelope`) → `callBgEnd` in `finally`; deposit
  succeeds → leave message in custody (do not mark `failed`); deposit fails / over ceiling →
  today's `sending → failed`.
- **The bound (MEASURED — iPhone 13 / iOS 26.5 device campaign):**
  per-message **3 s** (device-PROVEN: NLC 100 % loss → `storeInInbox` cut at `ms:3006` → `failed`), overall
  ceiling **≤8 s** (host-locked; the 8 s trip needs N≥3 simultaneous hangs, not device-reached because of a
  Send-button UX bug), cap **N = 5** newest-first (observed p95 `sendingCount` = 1; the wider normal-usage
  distribution per Exit-Gate-2 was NOT collected — cap = 5 is conservative), granted `backgroundTimeRemaining`
  **≈ 28.7 s** (8/8 finite, min = median = p90; ≥25 s ✅). ⚠ **`backgroundTimeRemaining` reads `DBL_MAX` at the
  pause instant** (finite ≈28.7 s only arms ~1.5 s into background) → **FDC-06 must use the FIXED 8 s ceiling,
  never read `backgroundTimeRemaining` to gate/size the flush.** ⚠ Only ONE iOS version measured (Exit-Gate-1
  "≥2 versions" not fully met).
- **Invariant reconciliation:** the "no network on pause" rule
  (`handle_app_paused.dart:24-25`) is **narrowed, not deleted** — it becomes "no *unbounded*
  network and no *connection-holding* on pause; a single bounded inbox-store-only deposit under
  a background assertion is permitted." FDC-06 must update that doc-comment + `main.dart:4316`.

## Exit Gate

The spike is done when:
1. ⚠ **PARTIAL** — `backgroundTimeRemaining` logged at **≈28.7 s**, but on **only ONE** iOS version (26.5),
   not the required **≥2** (sim can't suspend → `DBL_MAX`); the flush completed without app termination in all
   trials, but the ≥95 % of N∈{1,3,8} matrix was **not** fully run (a Send-button UX bug blocked staging N≥3
   bursts). **Carry-forward (FDC-06 device-proof, deferred-not-waived):** confirm on a 2nd iOS major + run the
   N-burst matrix.
2. ⚠ **PARTIAL** — observed p95 `sendingCount` = **1** (every pause), so cap **N = 5** is set conservatively
   above it; the **wider normal-usage distribution was NOT collected** (test scenarios only; UX bug blocked a
   large burst). Cap = 5 stands; widen the sample post-launch.
3. ✅ **DONE** — deposit-first ordering holds; a real deposit landed in **~52 ms** with the row left in custody
   (not `failed`); `messageId` dedup verified server-side.
4. ✅ **DONE** — the per-message 3 s / ceiling ≤8 s / cap N=5 / grant ≈28.7 s numbers + the **`DBL_MAX`-at-pause**
   design constraint are written back into FDC-06.

## Risks / Unknowns

- **Unawaited→awaited pause path.** `_onPaused` fires `handleAppPaused` fire-and-forget today
  (`main.dart:4317`). The flush must hold the bg assertion across the await; if wiring keeps it
  unawaited, the assertion can be ended before the deposit resolves. FDC-06 must restructure
  `_onPaused` to begin→await→end.
- **Single Go bridge serialization** (proposal §10). The flush's `storeInInbox` calls share the
  one bridge with any in-flight send/teardown; on a busy pause they can head-of-line block.
  Prioritize the flush deposits and keep the count capped.
- **Grant can be < folklore.** The "~30s" in `migration_transfer_keep_alive.dart:16-18` is a
  doc estimate, not measured per-OS; newer iOS can grant less under low battery / Low Power
  Mode. Must measure (Method step 1) before fixing the ceiling.
- **Recipient cost rises** (§6.2 honesty note): each deposited id is an extra retrieve+ack on
  the recipient's wake. Bounded by the cap; acceptable for the reliability win but worth logging.
- **Durability ordering** (§9): if FDC-03 (generalize concurrent inbox) raises inbox volume
  before the relay moves to the durable Redis backend, pause-flushed copies also sit in the
  restart-losable in-memory backend for that window. Not blocking, but note the interaction.
- **Device-only validation.** Background suspension is not faithfully reproduced on the
  simulator, so this spike's numbers are device-gated and cannot be host/sim-proven (consistent
  with the proposal's device-only flags).
- **Group parity.** Group sends use a 2-min staleness threshold and a separate recovery path
  (`handle_app_paused.dart:8/92`); FDC-06 must decide whether the pause-flush covers group
  in-flight sends too or only 1:1 (recommend: same bounded deposit, group envelope via the
  group store path).
