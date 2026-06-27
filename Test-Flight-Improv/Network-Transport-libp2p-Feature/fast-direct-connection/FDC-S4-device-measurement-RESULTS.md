# FDC-S4 — iOS pause-flush DEVICE MEASUREMENT: RESULTS

Status: **EXECUTED on a physical iPhone 13 (iOS 26.5) + iPhone 17 Pro sim (2026-06-26).**
All four FDC-06-consumed values are answered with real device numbers. Soft spots vs.
the spike Exit Gate: only **one** real iOS version for the grant, and the **N**
distribution is from test scenarios (not a broad normal-usage sample).

This is the measurements-only companion to
`FDC-S4-ios-pause-flush-feasibility-RESULTS.md` (decision, prototype, harness
hardening, host locks). Raw logs: `fdc-s4-measurement/logs/iphone13_ios26_5/`.
Build under test: `flutter run --profile --dart-define=FDC_PAUSE_FLUSH=1
--dart-define=FDC_FLOW_LOG=1`.

---

## The four values FDC-06 consumes (`<from FDC-S4>`)

| # | Value | Measured | Status |
|---|---|---|---|
| 1 | **Feasible?** | **YES** — reuse `beginBackgroundTask` (`callBgBegin`/`callBgEnd`); zero new native code. Deposit-success on device in ~52 ms; no termination in any trial. | ✅ device-corroborated |
| 2 | **Granted `backgroundTimeRemaining`** | **≈ 28.7 s** (iPhone 13 / iOS 26.5; 8/8 finite, min=median=p90=28.7 s) **≥ 25 s** | ✅ (1 iOS version) |
| 3a | **Per-message inbox budget** | **3 s** — a hung `storeInInbox` was cut at exactly `ms:3006` (NLC 100 % loss). Keep. | ✅ device-proven |
| 3b | **Overall ceiling** | **≤ 8 s** — all deposits ≪ 8 s; 28.7 s grant ≫ 8 s (~20 s slack). Keep. | ✅ (trip N≥3 host-locked) |
| 4 | **Cap N (newest-first)** | observed **N = 1** every trial (p95 = 1) → default **cap = 5 is conservative**. Keep 5. | ⚠ small sample |

**Headline:** `YES / 28.7 s / 3 s / ≤ 8 s / cap 5` — enough to resolve FDC-06's
`⚠ DRAFT — finalize after FDC-S4` banner.

---

## Device matrix

| Class | Device | OS | Role |
|---|---|---|---|
| iOS (real) | **iPhone 13** (`00008110-00184D622289801E`, USB) | **iOS 26.5** | grant + flush measurement |
| iOS (sim) | iPhone 17 Pro | iOS 26.1 | plumbing validation (can't suspend → `DBL_MAX` only) |

Capture: `idevicesyslog` (device) / `simctl log` (sim). **Crucial:** the app must run
**detached** (relaunch via `xcrun devicectl device process launch --terminate-existing`)
and be backgrounded by a **real home-swipe** — a `flutter run`-attached app, a
`devicectl`-backgrounded app, and the sim all report `DBL_MAX` (never truly suspend).

---

## 1. Feasible — YES (device-corroborated)
The pause→probe→flush path fires end-to-end on real iOS, and the actual deposit path
works:
```
PAUSE_FLUSH_BEGIN    {taskGranted:true, sendingCount:1, cap:5, flushing:1}
PAUSE_FLUSH_DEPOSIT  {id:9b11ea65, ok:true, ms:52}      ← deposited to the durable relay inbox
PAUSE_FLUSH_COMPLETE {deposited:1, skipped:0, totalMs:52, expired:false}
   (next background → NO_SENDING; row left in CUSTODY, never marked failed)
```
The mechanism is the shipped `beginBackgroundTask` bridge — no new native code for the
flush. ⇒ FDC-06's "Stop-if infeasible on iOS" branch does **not** trigger.

## 2. Grant — ≈ 28.7 s (iPhone 13 / iOS 26.5)

| read | when | value | n |
|---|---|---|---|
| immediate | at `didEnterBackground` (the flush's read point) | `DBL_MAX` (`1.797…e+308`) | 12/12 |
| **delayed** | +1.5 s into the background, assertion held | **28.7 s** (min=median=p90) | **8/8 finite** (4 reopened early → `DBL_MAX`) |

`backgroundTimeRemaining` is the "indeterminate-large" sentinel until the app is
executing on borrowed background time; the finite ~28.7 s only arms a beat into the
background. Captured via a delayed in-background read (`probePauseBackgroundGrant`:
immediate read → hold assertion → `Future.delayed(1.5 s)` → `bg:timeRemaining` →
release). The value rides the Flutter `[FLOW]` channel because native `os_log` buffers
while the process is suspended.

- **Decision Criterion 1 — met:** 28.7 s ≥ 25 s; the 8 s ceiling sits ~20 s under it.
- **Replaces** the "~30 s folklore" in `migration_transfer_keep_alive.dart:16-18` with
  a measured number.
- **FDC-06 must NOT** read `backgroundTimeRemaining` at the pause instant to gate the
  flush (it's `DBL_MAX` there). Use the fixed ceiling + the expiration handler.
- **Gap vs. Exit Gate:** only iOS 26.5 measured. A 2nd current iOS version is the one
  remaining grant item.

Raw: `logs/iphone13_ios26_5/grant_delayed_homeswipe.log` (+ `grant_probe_homeswipe.log`).

## 3. Flush metrics — driven with real `sending` rows
Raw: `logs/iphone13_ios26_5/flush_all_trials.log`.

| metric | measured | evidence |
|---|---|---|
| **deposit-SUCCESS** (net on) | `ok:true, ms:52` → `deposited:1`, custody | §1 above |
| **mark-on-REJECT** (airplane) | `ok:false, ms:9` → `PAUSE_TRANSITION` → `failed` | `id:73759414` |
| **HUNG network** (NLC 100 % loss) | `ok:false, ms:3006` → cut at the **3 s per-message budget** → `failed`, no termination | `id:b94b195d` |
| **per-deposit `storeInInbox`** | ~50 ms reachable / ~10 ms fast-reject / **~3006 ms hung-then-cut** | all bounded by the 3 s budget |
| **total flush** | median 30 ms, p90 52 ms, **0/4 over the 8 s ceiling** | — |
| **N at pause** | **1** every trial (median = p95 = 1) | a 6–8 burst left only 1 still `sending` |
| **termination safety** | 0 `BG_TASK_EXPIRED`, 0 `BG_TASK_REFUSED`, `expired:false` | process survived every trial |

**Deposit-first / mark-failed-only-on-reject is device-verified on both branches:** a
successful deposit is left in custody (no `PAUSE_TRANSITION`); a rejected/timed-out
deposit is marked `failed`.

### Per-message budget (3 s) — device-PROVEN
The NLC 100 % loss trial is the key safety result. Unlike airplane mode (instant fail,
~10 ms), a 100 %-loss network leaves the route up so `storeInInbox` **hangs** — and the
flush **cut it at exactly the 3 s `timeoutMs`** (`ms:3006`), then marked `failed`. This
answers the spike's central worry — *"confirm the ceiling protects against a hung
`storeInInbox`"* — at the per-message level. `storeInInbox` honors its budget; a hung
relay cannot hang the flush.

```
PAUSE_FLUSH_BEGIN    {sendingCount:1, cap:5}
PAUSE_FLUSH_DEPOSIT  {id:b94b195d, ok:false, ms:3006}   ← hung relay cut at the 3 s budget
PAUSE_FLUSH_COMPLETE {deposited:0, skipped:1, totalMs:3021, expired:false}
PAUSE_TRANSITION     {id:b94b195d}                       ← timed-out → failed
```

### Overall ceiling (≤ 8 s) — confirmed safe (trip not device-reached)
The 8 s *overall*-ceiling trip needs N ≥ 3 simultaneous hangs (3 × 3 s > 8 s). Only
N = 1 was in flight, so it wasn't reached on device — but the ceiling logic is
host-locked (`handle_app_paused_pause_flush_test.dart`, virtual-clock ceiling test) and
is a direct extension of the proven per-message cut. 28.7 s grant ≫ 8 s leaves ~20 s
slack, so the OS expiration handler (`BG_TASK_EXPIRED`) is a never-hit safety net here.

### N distribution (cap = 5)
Every pause showed `sendingCount = 1` — the realistic "open → send one → close" case;
cap = 5 is well above. **Caveat:** this is a small sample from test scenarios, not the
broad normal-usage `getSendingOutgoingMessages().length` distribution the spike's Exit
Gate 2 asks for (a richer N sample was blocked by the UX issue below). cap = 5 is a
safe conservative default; a wider sample is the one remaining N item.

---

## Observed during testing — a real UX bug (NOT FDC-S4; flag for the FDC epic)
Under degraded/no network in the 1:1 composer, rapid re-send is blocked: a send-failure
**snackbar covers the Send button**, and after dismissing it the **Send button is
briefly unresponsive, then re-sends** (and re-fails offline). This is why N ≥ 3 couldn't
be staged. It is a genuine send-reliability-under-poor-connectivity finding — worth a
separate ticket. (Root-cause investigation is tracked separately.)

---

## Exit-Gate status

| Exit Gate item | Status |
|---|---|
| Grant ≥ ~25 s | ✅ 28.7 s — but **1 iOS version only** (need a 2nd) |
| Flush < ceiling, no termination | ✅ ≤ 52 ms, 0/4 over 8 s, 0 termination |
| Hung-`storeInInbox` bounded | ✅ cut at 3 s per-message budget (NLC) |
| N distribution → cap | ⚠ N = 1 in tests (cap = 5 safe); broad normal-usage sample not collected |
| Deposit-first / mark-on-reject | ✅ device-verified both branches |
| Recipient dedup (exactly once) | ⬜ not run (needs the recipient device drained) |

## Reproduce
```bash
# 1. profile build with the flush + flow-log on (native bgGrantProbe/bgTimeRemaining
#    are Runner Swift — no gomobile rebuild needed)
flutter run --profile -d <iphone-udid> \
  --dart-define=FDC_PAUSE_FLUSH=1 --dart-define=FDC_FLOW_LOG=1
# 2. detach, relaunch NON-debugged (else backgroundTimeRemaining is always DBL_MAX)
xcrun devicectl device process launch --device <udid> --terminate-existing com.mknoon.app
# 3. capture + gesture, then parse
idevicesyslog -u <udid> | grep -E "PAUSE_FLUSH|grantSec|BG_TASK_" > trial.log   # grant: home-swipe + wait 3-4s
python3 fdc-s4-measurement/scripts/fdc_s4_parse.py --label iphone/trial trial.log
#   grant: real home-swipe, wait ~4s (delayed read needs +1.5s in background)
#   flush: send to offline peer / airplane / NLC 100% loss, background mid-`sending`
```
