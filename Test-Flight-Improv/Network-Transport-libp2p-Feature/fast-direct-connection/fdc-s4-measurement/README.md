# FDC-S4 measurement harness

Device-only campaign for the iOS pause-flush bound. The **decision** (Option A,
feasible YES) and the host-locked flush logic are already in the tree; this
harness measures the *numbers* the spike Exit Gate needs — the actual OS
background grant, per-deposit / total flush ms, the `BG_TASK_EXPIRED` rate under
a degraded network, and the in-flight `sending` count (N) distribution at pause.

Results doc this feeds: `../FDC-S4-ios-pause-flush-feasibility-RESULTS.md`.

> Background suspension is **not faithfully reproduced on the simulator** — every
> number here is from a **tethered real iPhone**. Sim runs are meaningless for
> this spike (spike §Risks).

## What it captures
The prototype is OFF unless built with `--dart-define=FDC_PAUSE_FLUSH=1`. With it
on, the pause transition emits (all already in the tree):

- native `[GoBridge] BG_TASK_GRANTED … backgroundTimeRemainingSec=<X>` — the
  **real OS-granted budget** read right after `beginBackgroundTask` (Method 1);
  plus the pre-existing `BG_TASK_EXPIRED` / `BG_TASK_REFUSED`.
- `[FLOW] … APP_LIFECYCLE_PAUSE_FLUSH_BEGIN` `{taskGranted, sendingCount(N), cap, flushing}`
- `[FLOW] … APP_LIFECYCLE_PAUSE_FLUSH_DEPOSIT` `{id, ok, ms}` (per message)
- `[FLOW] … APP_LIFECYCLE_PAUSE_FLUSH_COMPLETE` `{deposited, skipped, totalMs, expired}`

## Run
```bash
# 0. native libs with the declared toolchain (picks up the BG_TASK_GRANTED line)
( cd ../../../../go-mknoon && PATH="$HOME/go/bin:$PATH" GOTOOLCHAIN=go1.25.0 make ios )

# 1. install a profile build with the flush + flow-log ON
flutter build ipa --profile --dart-define=FDC_PAUSE_FLUSH=1 --dart-define=FDC_FLOW_LOG=1
#   ...install the .ipa, OR: flutter run --profile --dart-define=FDC_PAUSE_FLUSH=1 \
#                                              --dart-define=FDC_FLOW_LOG=1 -d <iphone>

# 2. per trial: start capture, then DO the gesture (see §Procedure), then Ctrl-C
bash scripts/fdc_s4_capture.sh <iphone-udid> logs/iphone/n1

# 3. parse one trial dir (or many) into the budget/per-deposit/total/N stats
python3 scripts/fdc_s4_parse.py --label iphone/n1 logs/iphone/n1/*.log
```

`fdc_s4_capture.sh` uses `idevicesyslog` (libimobiledevice) — the same tool the
FDC-S1 harness used; it reliably carries the main-app `Runner` `[FLOW]` +
`[GoBridge]` lines (the pause-flush is in the main app, not an extension).

## Procedure (per trial)
1. Foreground the app on the tethered iPhone.
2. Start `scripts/fdc_s4_capture.sh`.
3. Compose-and-send **N** messages (N ∈ {1, 3, 8}) to an **OFFLINE** peer — this
   forces the slow path so the rows stay `sending` — and **background the app**
   (home gesture) within ~200 ms of the last tap.
4. Wait ~15 s, then Ctrl-C the capture.
5. Repeat for a same-WiFi/online peer, and repeat **under Network Link Conditioner
   "Edge"/100% loss** to exercise the per-message timeout + overall ceiling
   (confirm `expired:true` / `BG_TASK_EXPIRED` and **no app termination**).
6. On the **recipient** device, drain and confirm each deposited id arrives
   exactly once (relay `messageId` dedup — Exit Gate 3).

## Exit Gate (from the spike)
- grant ≥ ~25 s on ≥2 iOS versions; flush < 8 s ceiling in ≥95% of N∈{1,3,8};
  never terminates (only benign `BG_TASK_EXPIRED`).
- N (`sendingCount`) 95th percentile fixes the cap (default 5).
- recipient dedup verified.

When done, write the numbers into the RESULTS §0/§3 and flip FDC-06 out of DRAFT.
