# FDC-S4 — iOS pause-flush feasibility: RESULTS

Status: **Decision FIRM = Option A (feasible: YES). Flag-gated prototype + all
instruments landed and host-green (the host-testable logic is locked). Device
measurement EXECUTED on a physical iPhone 13 (iOS 26.5) + iPhone 17 Pro sim
(§2.5): the pause→probe→flush plumbing fires end-to-end on real iOS, and the key
empirical finding is that `backgroundTimeRemaining`, read at the pause-handler
instant where the flush takes its assertion, returns the `DBL_MAX`
"indeterminate-large" sentinel (12/12 real home-swipe samples) — NOT a finite
countdown — so the flush must be bounded by its own ceiling + the expiration
handler, not an at-pause read. The grant itself was **MEASURED ≈ 28.7 s** via a
delayed in-background read (8/8 finite, ≥ 25 s ✅, §2.5); the 8 s ceiling sits
~20 s under it. The flush itself was driven on device with real `sending` rows
(§2.5 Result 4): **deposit-success ~52 ms, N=1, total ≤ 52 ms (0/4 over the 8 s
ceiling), deposit-first + mark-on-reject device-verified, no termination.**
**Hung-network safety device-proven** (NLC 100 % loss → `storeInInbox` HANGS and is
cut at exactly the 3 s per-message budget, `ms:3006` → failed, no termination).
Still device-pending (lowest priority): the 8 s *overall*-ceiling trip for N≥3
(host-locked) + recipient-side dedup. Harness under `fdc-s4-measurement/`, build
with `--dart-define=FDC_PAUSE_FLUSH=1`.**

Parent spike: `FDC-S4-ios-pause-flush-feasibility-spike.md`. Consumed by **FDC-06**
(`FDC-06-graceful-pause-flush-tdd-plan.md`, currently `⚠ DRAFT — finalize after FDC-S4`).

This doc holds the decision + the bound FDC-06 consumes (every `<from FDC-S4>`
marker in FDC-06). The prototype it documents is **OFF by default** — it does not
change the production pause path until FDC-06 flips it; it exists so the bound
can be *measured on device*, not guessed.

---

## 0. TL;DR for FDC-06

| Question (spike §Question) | Answer |
|---|---|
| **1. Feasible y/n** | **YES** — a bounded, inbox-store-only deposit on iOS pause is feasible. Firm from source + production precedent (the send path *already* wraps each interactive send in this exact assertion); the only OS lever `Info.plist` permits is `beginBackgroundTask`, which already ships. |
| **2. Which mechanism** | **Reuse the existing `beginBackgroundTask` bridge** — `callBgBegin`/`callBgEnd` (`bridge.dart:777-798`) → native `bgBegin`/`bgEnd` (`GoBridge.swift:213-256`). **Zero new native code**, no APNs path for v1. |
| **3a. Per-message budget** | **≈ 3 s** (`kPauseFlushPerMessageBudget`) — reuses `storeInInbox`'s existing `timeoutMs`. |
| **3b. Overall ceiling** | **≤ 8 s** (`kPauseFlushOverallCeiling`) — loop stops here even if rows remain. |
| **3c. Cap N** | **5, newest-first** (`kPauseFlushCap`) — rows beyond the cap keep today's `sending → failed` + resume-retry. Confirm against the device 95th-percentile of `getSendingOutgoingMessages().length` (Exit Gate 2). |
| **3d. Required grant** | `kPauseFlushRequiredGrantMs = 25000`. **Device-MEASURED (§2.5): ≈ 28.7 s** (iPhone 13 / iOS 26.5, 8/8 finite delayed reads) **≥ 25 s ✅** — the 8 s ceiling sits ~20 s under it. Note: at the *pause instant* (the flush's read point) it reads `DBL_MAX`; the finite ~28.7 s only arms a beat into the background, so do NOT gate the flush on an at-pause read — the **8 s ceiling + expiration handler** are the bound. |
| **Invariant** | "no network on pause" is **NARROWED, not deleted** — see §5. |

All four constants are live in `lib/core/lifecycle/handle_app_paused.dart` so FDC-06
imports them instead of re-deriving (`kPauseFlushCap`, `kPauseFlushPerMessageBudget`,
`kPauseFlushOverallCeiling`, `kPauseFlushRequiredGrantMs`).

---

## 1. Prototype landed (flag-gated, OFF by default)

The Option-A flush is implemented as a **measurement prototype**: when the flag
is off, `handleAppPaused` is byte-for-byte the legacy local-DB-only handler (no
`callBgBegin`, no `storeInInbox`, all `sending → failed`). When on, it runs the
bounded deposit. This is the FDC-S1 pattern (`--dart-define=FDC_FLOW_LOG=1`,
"OFF and inert in a normal build"): the spike ships a *measurable* prototype
without committing the production pause-path restructure that **FDC-06 owns**.

| Piece | Where | What |
|---|---|---|
| **Flag** | `handle_app_paused.dart` `kFdcPauseFlushEnabled` | `String.fromEnvironment('FDC_PAUSE_FLUSH')`, truthy `1`/`true`/`yes`/`on` (mirrors `FDC_FLOW_LOG`'s forgiving parse; `bool.fromEnvironment` alone honours only `'true'`/`'false'`). |
| **Bounds (FDC-06 consumes)** | `handle_app_paused.dart` consts | `kPauseFlushCap=5`, `kPauseFlushPerMessageBudget=3s`, `kPauseFlushOverallCeiling=8s`, `kPauseFlushRequiredGrantMs=25000`. |
| **Flush** | `handle_app_paused.dart` `_pauseFlushInFlightSends(...)` | `callBgBegin` → newest-first (`createdAt` desc), wire-envelope-only candidates, `take(cap)` → per-message `storeInInbox(contactPeerId, wireEnvelope!, timeoutMs: clamp(perMsg, remainingCeiling))` → `callBgEnd` in `finally`. Returns the set of **accepted** ids. |
| **Deposit-first / mark-on-reject** | `handle_app_paused.dart` sending loop | Accepted ids are **skipped** in the mark-failed loop (left in custody → emit `APP_LIFECYCLE_PAUSE_FLUSH_IN_CUSTODY`). Only non-accepted rows (rejected / threw / over-ceiling / beyond-cap / no-envelope) take today's `conditionalTransitionStatus → failed`. |
| **Result surface** | `AppPausedResult.flushDepositedCount` | additive; 0 when the flush is off. |
| **Pause-path wiring** | `main.dart` `_onPaused()` | passes `enablePauseFlush: kFdcPauseFlushEnabled` + `p2pService`/`bridge`. Stays `unawaited`: the **native bg assertion** (acquired inside the handler *before* the first network await) keeps the process alive across the deposit, so the Dart future need not be awaited — see §6 (the spike's begin→await→end ordering is satisfied *inside* the handler). |

### Instruments (kDebugMode/`FDC_FLOW_LOG`-gated, additive)

| Spike Method instrument | Emitted as | Fields |
|---|---|---|
| `APP_LIFECYCLE_PAUSE_FLUSH_BEGIN` | flow-event (`emitFlowEvent`) | `{taskGranted, sendingCount, candidateCount, cap, flushing}` |
| `APP_LIFECYCLE_PAUSE_FLUSH_DEPOSIT` (per message) | flow-event | `{id(8), ok, ms, error?}` |
| `APP_LIFECYCLE_PAUSE_FLUSH_COMPLETE` | flow-event | `{taskGranted, deposited, skipped, cappedOut, totalMs, expired}` |
| **Native granted budget (Method step 1)** | `NSLog` `BG_TASK_GRANTED` | `GoBridge.swift` — `UIApplication.backgroundTimeRemaining` read on the main thread **right after** the grant, alongside the existing `BG_TASK_EXPIRED` / `BG_TASK_REFUSED`. **This is the one new native line** and the source of the real per-OS grant. |

> FDC-06 uses a finer event taxonomy (`PAUSE_FLUSH_INBOX_DEPOSITED`,
> `PAUSE_FLUSH_INBOX_DEPOSIT_FAILED`, `PAUSE_FLUSH_BUDGET_EXHAUSTED`,
> `PAUSE_FLUSH_SKIP_NULL_ENVELOPE`, …). The prototype emits the **spike Method's**
> `APP_LIFECYCLE_PAUSE_FLUSH_*` names; FDC-06's set is a productionization superset
> and is not a conflict.

---

## 2. What is host-PROVEN vs device-GATED

### Host-proven (locked, mutation-verified)
`test/core/lifecycle/handle_app_paused_pause_flush_test.dart` (+ fakes extended in
`test/core/services/fake_p2p_service.dart`: `storeInInboxLog`, `onStoreInInbox`).
All green; the existing pause tests (`handle_app_paused{,_edge_cases,_group}_test.dart`)
still pass unchanged → backward-compat confirmed (`flutter test test/core/lifecycle/
test/core/services/ test/core/bridge/` = **747 pass**).

| Lock | Asserts |
|---|---|
| flush OFF by default | omitting the params, AND `enablePauseFlush:false` with deps present, does **zero** network (`bgBeginCount==0`, `storeInInboxCallCount==0`) and marks every row failed — the invariant holds. |
| deposit-first / custody | accepted deposit → recipient = `contactPeerId`, payload = `wireEnvelope`, row left `sending` (**not** failed), `bg:begin` precedes `bg:end`. |
| mark-on-reject | rejected (`storeInInbox=false`) → `failed`; throwing deposit → `failed` **and** assertion still released (`finally`). |
| newest-first cap | 8 rows, cap 5 → exactly the 5 newest deposited **in newest-first order**; the 3 oldest → failed. |
| per-message budget | `storeInInbox` receives `timeoutMs == 3000`. |
| overall ceiling | injected virtual clock, each deposit "takes" 4 s, 8 s ceiling → exactly 2 deposit, the rest → failed; assertion released. |
| assertion-refused (Android / low-power) | `bgBegin` returns `''` → flush still deposits without an assertion; `callBgEnd(null)` is a no-op. |
| no depositable rows | all-null-envelope → never touches the bridge. |
| instrument shape | `BEGIN` / per-message `DEPOSIT` / `COMPLETE` emitted with the expected fields. |

**Mutation check run:** reverting the custody-skip (so accepted rows are *also*
marked failed) fails 5 locks → the deposit-first invariant is load-bearing.

### Device — partially EXECUTED (§2.5), partially pending
Device measurement ran on a physical iPhone 13 (iOS 26.5) + iPhone 17 Pro sim
(§2.5). Status per Exit-Gate item:

1. **Exit Gate 1 — actual grant: EXECUTED + CONFIRMED, see §2.5.** Measured
   **≈ 28.7 s** (iPhone 13 / iOS 26.5; 8/8 finite delayed reads) **≥ 25 s ✅**.
   Note: at the *pause instant* (the flush's read point) it reads `DBL_MAX`; the
   finite ~28.7 s only arms a beat into the background (captured via a delayed
   read). The 8 s ceiling sits ~20 s under the real window.
2. **Exit Gate 1 — bounded flush < ceiling: EXECUTED ✅ (§2.5 Result 4).** Drove
   the flush with real `sending` rows: **deposit-success ~52 ms / total flush
   ≤ 52 ms, 0/4 over the 8 s ceiling, no termination.** Deposit-first + custody +
   mark-on-reject all device-verified. **Hung-network safety device-proven** (NLC
   100 % loss → `storeInInbox` cut at the 3 s per-message budget, `ms:3006`); the
   8 s *overall*-ceiling trip (N≥3) is host-locked, a straightforward extension.
3. **Exit Gate 2 — N distribution: EXECUTED ✅ (§2.5 Result 4).** Observed **N=1**
   (p95=1) — the realistic "send one then close" case; **cap = 5 is conservative**.
4. **Exit Gate 3 — dedup: PENDING** (deposit succeeded; needs the recipient
   device drained to confirm "exactly once").

The **decision** (Option A) does not wait on these: it is firm from source +
production precedent (§4), and §2.5 confirms the plumbing fires on real iOS. The
grant finding *strengthens* the design: because no finite budget is exposed at
the read point, the flush MUST rely on the fixed 8 s ceiling + the expiration
handler (never a measured grant) — which is exactly the current design.

---

## 2.5 Device measurement — EXECUTED (2026-06-26)

> Standalone measurements-only companion (the four FDC-06 values + raw evidence):
> **`FDC-S4-device-measurement-RESULTS.md`**.

**Matrix:** physical **iPhone 13** (`00008110…`, iOS 26.5, USB) + **iPhone 17 Pro
sim** (iOS 26.1). Build: `flutter run --profile --dart-define=FDC_PAUSE_FLUSH=1
--dart-define=FDC_FLOW_LOG=1`. Capture: `idevicesyslog` (device) / `simctl log`
(sim). Raw log: `fdc-s4-measurement/logs/iphone13_ios26_5/grant_probe_homeswipe.log`.

### Result 1 — plumbing fires end-to-end on real iOS ✅
On both sim and device the full pause chain runs on a real build:
`inactive → hidden/paused → PAUSE_BEGIN → PAUSE_GRANT_PROBE {taskGranted:true}
→ (PAUSE_NO_SENDING_MESSAGES) → PAUSE_COMPLETE`. `beginBackgroundTask` returns a
valid id every time (`taskGranted:true`), and the native instrument logs with the
correct format (`BG_TASK_GRANTED taskId=… backgroundTimeRemainingSec=…`). The
prototype + probe + native instrument are confirmed wired on device, not just in
host tests.

### Result 2 — the grant is `DBL_MAX` at the pause instant, but a measured **≈ 28.7 s** a beat into the background ✅
Two reads per pause (both on the `[FLOW]` channel):

| read | when | iPhone 13 / iOS 26.5 |
|---|---|---|
| **immediate** | at `didEnterBackground` (the flush's own assertion point) | `DBL_MAX` (`1.7976931348623157e+308`) — **12/12** |
| **delayed** | +1.5 s into the background, under a held assertion | **28.7 s — 8/8 finite reads** (min = median = p90 = 28.7 s; 4 trials reopened before the delayed read fired → still `DBL_MAX`) |

`backgroundTimeRemaining` is the "large, indeterminate" sentinel **until the app
is actually executing on borrowed background time** — so at the
`didEnterBackground` instant the Flutter `paused` callback reaches (where the
flush takes its assertion) it reads `DBL_MAX`, and the **finite countdown only
arms a beat later** (captured here by holding an assertion and reading 1.5 s in).

**The measured grant ≈ 28.7 s** (strikingly consistent, 8/8) — matching, and now
replacing, the "~30 s folklore" in `migration_transfer_keep_alive.dart:16-18`.

**Decision Criterion 1 — CONFIRMED:** grant **28.7 s ≥ ~25 s** ✅, so the **8 s
overall ceiling sits ~20 s under the real window** with ample slack for the OS to
persist + the expiration handler to fire.

**Implication for FDC-06:** keep the fixed **8 s ceiling + `BG_TASK_EXPIRED`
handler** as the bound, and **do not read `backgroundTimeRemaining` at the pause
instant to gate the flush** (it is `DBL_MAX` there); the real ~28.7 s budget only
appears deeper into the background. 8 s is safely inside it.

### Result 3 — harness hardening: the grant must ride the Flutter `[FLOW]` channel
A real device finding worth keeping: when the app is **genuinely suspended** by a
home-swipe, its **native `os_log` buffers** and stops live-streaming (idevicesyslog
went silent on the native `BG_TASK_GRANTED` line), while the **Flutter `[FLOW]`
channel kept streaming** the `PAUSE_GRANT_PROBE` events. So a native-NSLog-only
grant capture is unreliable. Fix landed: a new flag-gated native `bgGrantProbe`
command (`GoBridge.swift`) reads `backgroundTimeRemaining` and **returns it to
Dart**, which logs it as `PAUSE_GRANT_PROBE {grantSec}` on the reliable channel
(`callBgGrantProbe` `bridge.dart`; `bg:grantProbe` map `go_bridge_client.dart`;
`probePauseBackgroundGrant` `handle_app_paused.dart`). `fdc_s4_parse.py` now reads
`grantSec` from `[FLOW]`. (`log collect --device-udid` would also retrieve the
buffered native value but needs admin — same wall FDC-S1 hit.)

### Result 4 — flush mechanics on device (deposit-success + reject + N + ceiling-safety) ✅
Drove the flush with real in-flight `sending` rows on the iPhone 13 (send + quick
home-swipe). Raw: `logs/iphone13_ios26_5/flush_airplane_and_success.log`.

| metric | measured |
|---|---|
| **N (`sendingCount` at pause)** | **1** every trial (median = p95 = 1). A 6–8-message burst left only 1 still `sending` (the rest resolved to `failed` first) → the realistic case is **N=1**, **cap = 5 is conservative** (Exit Gate 2 ✓). |
| **deposit-SUCCESS** (network on) | `PAUSE_FLUSH_DEPOSIT {ok:true, ms:52}` → `COMPLETE {deposited:1, skipped:0}`, row left in **custody** (no `PAUSE_TRANSITION`). The in-flight message was deposited to the durable relay inbox in **~52 ms** — the core "send-one-then-close still arrives" guarantee, on device. |
| **mark-on-REJECT** (airplane mode) | `PAUSE_FLUSH_DEPOSIT {ok:false, ms:9}` → `COMPLETE {deposited:0, skipped:1}` → `PAUSE_TRANSITION` → row marked **failed**. Deposit-first / mark-failed-only-on-reject **device-verified on both branches**. |
| **HUNG network** (NLC 100 % loss) | `PAUSE_FLUSH_DEPOSIT {ok:false, ms:3006}` → cut at **exactly the 3 s per-message budget** → marked `failed`, `expired:false`, no termination. **This is the spike's central safety question, device-proven: a hung `storeInInbox` is bounded by `timeoutMs` (it does NOT hang the flush).** N=1 here, so the 8 s *overall* ceiling wasn't reached (needs N≥3 simultaneous hangs; the ceiling logic is host-locked). |
| **per-deposit `storeInInbox` ms** | **~50 ms** reachable / **~10 ms** fast-reject / **~3000 ms** hung-then-timed-out — all bounded by the 3 s per-message budget. |
| **total flush ms** | median **30 ms**, p90 **52 ms**, **0/4 over the 8 s ceiling** (Exit Gate 1 ✓). |
| **termination safety** | 0 `BG_TASK_EXPIRED`, 0 `BG_TASK_REFUSED`, `expired:false` — the process survived every trial. |

Note the double `_onPaused` (hidden + paused both fire) → the flush runs twice per
background; idempotent (relay dedups; `conditionalTransitionStatus` no-ops the 2nd
mark). FDC-06 may debounce, but it is harmless.

### Precise finite countdown — DONE ✅ (delayed in-background read)
Added a delayed read (`probePauseBackgroundGrant`: immediate read, then hold an
assertion, `await Future.delayed(1.5 s)`, read `bg:timeRemaining`, release). The
held assertion keeps the Dart isolate alive in the background (the same mechanism
the interactive send path relies on), so the delayed `Future` fires and the read
lands after iOS arms the finite countdown → **28.7 s** (see Result 2). Native
`bgTimeRemaining` command + `callBgTimeRemaining` + `bg:timeRemaining` map.

### Hung-network safety — DEVICE-PROVEN at the per-message level ✅ (NLC 100 % loss)
Under Network Link Conditioner "100 % Loss", `storeInInbox` **hangs** (route up,
packets dropped) and the flush **cut it at exactly the 3 s `timeoutMs`**
(`ms:3006`) → `failed`, no termination. So the per-message budget bounds a hung
relay — the spike's core safety question is answered. The **8 s *overall* ceiling
trip** (needs N≥3 simultaneous hangs, 3×3 s > 8 s) was not reached because only
N=1 was in flight (the UX issue below blocked a burst); the overall-ceiling logic
is **host-locked** (`handle_app_paused_pause_flush_test.dart` ceiling test, virtual
clock) and is a straightforward extension of the proven per-message cut.

**Observed UX issue under degraded network (worth a separate ticket, not FDC-S4):**
rapid re-send is blocked because a send-failure **snackbar covers the Send button**,
and after dismissing it the **Send button is briefly unresponsive then re-sends**
(and re-fails offline). This is why only N=1 could be staged under NLC, and it is a
real send-reliability-under-poor-connectivity finding for the FDC epic.

### What remains (device, lowest priority)
- **8 s overall-ceiling trip on device** (N≥3 simultaneous hangs) — host-locked;
  device-confirm by sending to 3 different contacts under NLC then backgrounding.
- **Recipient-side dedup.** The deposit succeeded (id `9b11ea65` in the relay
  inbox) and the live send may also land; the relay dedups by `messageId`.
  Confirming "exactly once" needs the recipient device drained.

---

## 3. Expected-Output values (FDC-06 consumes — `<from FDC-S4>`)

1. **Feasible = YES.** Bounded inbox-store-only flush on iOS pause via the
   existing `beginBackgroundTask` bridge. No new native code, no APNs for v1.
   → FDC-06's **DRAFT banner can resolve**; the "Stop-if infeasible on iOS"
   branch (FDC-06 step) does **not** trigger.
2. **Mechanism = `callBgBegin` → bounded newest-first `storeInInbox` loop →
   `callBgEnd` in `finally`.** Deposit-first; accepted → custody, rejected/over →
   `failed`.
3. **The bound (plan against; device-confirm):**
   - per-message ≈ **3 s** → FDC-06 `flushBudget` / per-message test budget.
   - overall ceiling ≈ **8 s** → `PAUSE_FLUSH_BUDGET_EXHAUSTED` trip point.
   - cap **N = 5** newest-first → every `<from FDC-S4>` count marker.
   - required grant **≥ ~25 s** (measured) → Decision Criterion 1.
4. **Custody status (the one decision the spike defers to FDC-06):** a deposited
   row **must not be left `failed`**. The prototype leaves it untouched
   (`sending`); **FDC-06 productionizes it to `status:'inboxed', transport:'inbox'`**
   (FDC-06 §"deposit per-message; mark `inboxed`") so resume doesn't re-send it as
   a fresh `sending`. The spike's only hard requirement: deposit-first, never
   `failed`-on-accept.
5. **Scope = 1:1 for v1.** The prototype covers 1:1 sends (the proposal's P0
   "send one then close"). Group in-flight sends keep their separate 2-min
   `recoverStuckSendingMessages` path; FDC-06 decides whether to extend the flush
   to the group store path (recommend: same bounded deposit via the group store).
6. **Store-only, no live race.** Option A is store-and-exit (no dial, no held
   connection). If FDC-06 adds a best-effort direct attempt (its `PAUSE_FLUSH_
   DIRECT_ATTEMPT` / INV-1), it must stay **after** the deposit — the spike's
   ordering (deposit-first) is preserved.

---

## 4. Why the decision is firm without the device numbers

- **The mechanism already ships and is load-bearing in production on the send
  path.** Each interactive send wraps itself in this same assertion
  (`feed_wired.dart:2053` begin / `:2107` end; `group_conversation_wired.dart`
  `_beginBackgroundTaskGuarded`; `share_batch_delivery_coordinator.dart:400/481`).
  A second independent user is the account-move keep-alive
  (`AppDelegate.swift:404-432`). The pause-flush is the **same call on the same
  bridge**, just triggered from `_onPaused` over the in-flight `sending` rows.
- **The OS lever is forced.** `Info.plist` `UIBackgroundModes` = `fetch`,
  `remote-notification` only — no `voip`, no BGProcessing/BGAppRefresh identifiers.
  The *only* execution-extension available without new entitlements is
  `beginBackgroundTask` (a finite assertion) — exactly Option A. Option B (APNs/
  self-push) needs infra that does not exist and gives a *worse* P0 guarantee
  (sender's message not in the inbox until a later, throttled wake).
- **The deposit is harmless even if it races the live send.** The relay dedupes
  by `messageId` on store (`backend_memory.go:121-142`, `backend_redis.go:272-295`),
  so a pause-flush copy + a landed live send = one delivery. → additive,
  NET-REL-07-safe, no relay/Go change.
- **The downside is capped by the existing expiration handler.** `bgBegin`'s
  expiration closure (`GoBridge.swift:219-225`) ends the task before forced
  suspension, so an overrun hits the benign `BG_TASK_EXPIRED`, never termination.

---

## 5. Invariant reconciliation (FDC-06 must apply)

The "no network on pause" rule (`handle_app_paused.dart:24-25` doc-comment,
`main.dart` `_onPaused` comment) is **narrowed, not deleted**:

> "no *unbounded* network and no *connection-holding* on pause; a single bounded,
> background-assertion-protected, inbox-store-only deposit of the newest in-flight
> sends is permitted."

The prototype already updates both doc-comments behind the flag framing. When
FDC-06 flips the flag on by default, it should make that narrowing the
unconditional contract and remove the `enablePauseFlush` gate (or default it on).

---

## 6. Risks carried forward to FDC-06

- **Unawaited `_onPaused`.** The prototype keeps `_onPaused` firing the handler
  `unawaited`, which is **correct** because the *native* bg assertion (not the
  Dart future) holds the process alive across the awaited deposit loop inside the
  handler (begin→await→end is satisfied *inside* `_pauseFlushInFlightSends`).
  FDC-06 may additionally `await` in `_onPaused` for symmetry, but it is **not
  required** — verify on device that the assertion is acquired inside the
  foreground window the method-channel round-trip needs (the send path already
  relies on exactly this round-trip succeeding on a background flip).
- **Single Go bridge serialization (proposal §10).** The flush's `storeInInbox`
  calls share the one bridge with any in-flight send/teardown; on a busy pause
  they can head-of-line block. Mitigated by the cap (5) + the overall ceiling;
  device-measure under a concurrent send.
- **Recipient cost (§6.2).** Each deposited id is an extra retrieve+ack on the
  recipient wake — bounded by the cap; the `COMPLETE` event's `deposited` count
  logs it.
- **Durability ordering (§9).** Until the relay moves to the durable Redis
  backend (FDC-10), pause-flushed copies also sit in the restart-losable
  in-memory backend for that window. Not blocking; note the interaction.
- **Grant < folklore.** Measure (Method step 1) before fixing the ceiling; newer
  iOS can grant less under Low Power Mode.

---

## 7. Reproduce (device campaign — harness ready under `fdc-s4-measurement/`)

```bash
# 1. rebuild native libs with the declared toolchain (picks up the new
#    BG_TASK_GRANTED backgroundTimeRemaining NSLog)
cd go-mknoon && PATH="$HOME/go/bin:$PATH" GOTOOLCHAIN=go1.25.0 make ios

# 2. build + install the measurement profile build with the flush ENABLED
flutter build ipa --profile \
  --dart-define=FDC_PAUSE_FLUSH=1 --dart-define=FDC_FLOW_LOG=1
#   (or `flutter run --profile --dart-define=...` on a tethered device)

# 3. capture device logs, then run the procedure (spike Method §Procedure):
#    compose-and-send 1 / 3 / 8 messages to an OFFLINE peer (forces the slow
#    path so they stay `sending`), then background within ~200ms of tapping send.
cd Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/fdc-s4-measurement
bash scripts/fdc_s4_capture.sh <iphone-udid> logs/iphone/n1     # repeat N∈{1,3,8}
python3 scripts/fdc_s4_parse.py --label iphone/n1 logs/iphone/n1/*.log
#   → granted budget (median/p90), per-deposit ms, total flush ms, expired-rate,
#     deposited/skipped, and the sendingCount(N) distribution for cap sizing.
```

Then write the measured grant / per-deposit / total / N-p95 back into §0 + §3 and
flip FDC-06 from DRAFT to final, replacing every `<from FDC-S4>` with the constant
(or the device-revised value).

---

## 8. Files

| File | Change |
|---|---|
| `lib/core/lifecycle/handle_app_paused.dart` | flag + 4 bounds consts; `enablePauseFlush`/`p2pService`/`bridge`/budget/`nowMs` params; `_pauseFlushInFlightSends` (Option-A flush); deposit-first custody skip; `AppPausedResult.flushDepositedCount`. |
| `lib/main.dart` | `_onPaused` passes the flush deps + flag; narrowed-invariant doc-comment. |
| `ios/Runner/GoBridge.swift` | `BG_TASK_GRANTED` + `backgroundTimeRemaining` NSLog right after the grant (Method step 1; observation-only); **`bgGrantProbe`** command (§2.5 Result 3) that returns the grant seconds to Dart. |
| `lib/core/bridge/bridge.dart` / `go_bridge_client.dart` | `callBgGrantProbe` + `bg:grantProbe` map — the grant value rides the reliable Flutter `[FLOW]` channel. |
| `lib/main.dart` `_onPaused` + `handle_app_paused.dart` `probePauseBackgroundGrant` | flag-gated grant probe on every pause → `PAUSE_GRANT_PROBE {grantSec}` (measurement scaffolding; FDC-06 drops it). |
| `test/core/services/fake_p2p_service.dart` | additive `storeInInboxLog`, `lastStoreInInboxTimeoutMs`, `onStoreInInbox` hook. |
| `test/core/lifecycle/handle_app_paused_pause_flush_test.dart` | host locks for the bounded-flush logic. |
| `fdc-s4-measurement/` | device capture + parse harness (this dir). |

> **Not** committed: the device numbers. The decision (Option A) and the
> host-locked logic are; the grant/per-deposit/N campaign is the device-gated
> tail of the Exit Gate.
