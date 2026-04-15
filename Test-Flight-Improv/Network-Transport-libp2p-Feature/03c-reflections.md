# Benchmark Reflections — What the Numbers Tell Us

> Updated 2026-04-15 after the fact-check reruns.
> Numbers come from `03b-benchmark-test-inventory.md`.
> Test-strategy direction comes from `../03-smoke-test-strategy.md`.

---

## What's Fast (No Action Needed)

**Bridge crossing: p99=0ms for 1000 calls.** The MethodChannel is not the problem.

**Crypto is cheap.** ML-KEM keygen is `p95=3ms`. Encrypt and decrypt stay at `<=3ms` even at `100KB`. Group AES is `<1ms`.

**Warm 1:1 send is excellent.** Warm send is `p50=1ms p95=2ms`. Connection reuse hit rate is `90%`. This means most normal chat traffic is already on the fast path.

**Direct ACK is healthy.** ACK wait is `p50=1ms p95=41ms`. This is far below the `2s` timeout budget.

**Startup is already good.** Time-to-Online Badge is `p50=171ms p95=178ms`. Cold-start harness is `p50=169ms p95=170ms`.

**Notification open is now measured and looks good.** Warm notification tap is `85ms`. Cold notification tap is `313ms`.

**Background resume is good when relay stays healthy.** Healthy resume is `100-103ms`. This is not zero, but it is still fast.

**Low-level group publish is fast.** In `GP-Sim`, sender publish is `p50=5ms p95=8ms`, and receiver e2e is `p50=44ms p95=48ms`.

**Low-level media upload is now measured and looks acceptable.**
- `1MB` upload: `351ms`, `2987396 bytes/sec`, `6` progress events
- `5MB` upload: `2677ms`, `1958490 bytes/sec`, `22` progress events
- Profile upload: `221ms`, `3` profile progress events

**Health check is cheap.** X3 health check is `53ms`.

**Delete-for-everyone is fast enough.** S10 is `192ms`.

---

## What's Slow or Concerning

### 1. Relay Recovery: about 9.1 seconds (Highest Priority)

This is still the biggest user-facing problem.

- `C-Sim` relay recovery: `p50=9136ms p95=9320ms`
- Degraded background resume (`BR-Sim-2`): `9166ms`
- Detection is fast: `504ms`

**What users feel:** the app comes back to foreground, but the green badge is late. During that time, sends may queue or wait.

**Other tests show the same pattern:**
- S4 reconnect: `send=105ms`, but `e2e=3561ms`
- X1 both-sides restart: `send=142ms`, `e2e=3310ms`

The app is fast after recovery. The problem is the recovery itself.

### 2. Inbox Fallback Is Delayed by Discover Budget Starvation

The inbox store itself is not slow. The path before inbox is slow.

- Warm inbox store (`D-Sim`): `106ms`
- Real S3 offline-to-inbox path: `2058ms`

This means most of the time is lost before inbox store starts. The main suspect is still the `2s` interactive discover budget.

This is a real transition-path problem, not an inbox-write problem.

### 3. Group Discovery Still Spends 5 Seconds Waiting

- G6 total: `5255ms`
- Actual discovery work after settle: about `255ms`

This still looks like an easy win. Most of the time is the hardcoded settle wait, not the real discovery work.

### 4. Group Multi-Member Publish Is Still Slow

- G8 multi-member publish: `1239ms`
- G7 key rotation: `1209ms`

These are not emergency problems, but they are much slower than the single-peer publish numbers. They still deserve profiling.

### 5. Cold First Message Is Noticeable, but Acceptable

- S1 cold send: `227ms`
- S1 cold e2e: `806ms`

This is slower than the warm path, but still reasonable for a first message in a P2P app. It is not the main problem.

### 6. Relay Probe Needs Better Evidence Before We Call It Broken

The old reflection said relay probe was clearly failing and falling to inbox. The current rerun does not support that strong statement.

- S15 current rerun: `send=572ms`, `probe=false`, `e2e=254ms`

So the latest run did not actually exercise the relay-probe branch. The correct conclusion now is:

**we still need a clean benchmark that really hits the relay-probe path.**

This is now a measurement-quality gap, not a confirmed product bug.

---

## What Is No Longer "Pending"

Several items were unclear before. They are not unclear now.

**Notification tap is no longer pending.** It is measured:
- warm: `85ms`
- cold: `313ms`

**Background resume badge timing is no longer future work.** It is measured:
- healthy: `100ms`
- degraded: `9166ms`
- extended background: `103ms`

**Timeout accuracy is no longer a weak point in the data.** It is now validated:
- relay timeout: `5007ms`
- wrapper timeout: `2003ms`
- Go timeout events: `2`
- Go ACK-timeout events: `2`
- max deviation: `0.1%`

**E-Sim media is no longer partial.** It now emits real low-level upload and profile rows.

---

## What Doesn't Matter Right Now

**Bridge crossing** does not matter. `p99=0ms`.

**Crypto overhead** does not matter. It is already very low.

**Warm send latency** does not matter. `1ms` is already excellent.

**Event queue pressure** is not a real issue right now. Loaded is a bit slower than idle (`p95=125ms` vs `58ms`), but both are still healthy.

**Local WiFi on simulators** still does not tell us much. Simulators are not good for that path.

---

## Revised Priority Order

| Priority | Target | Current | Goal | Why It Matters |
|----------|--------|---------|------|----------------|
| **1** | Relay recovery / degraded resume | `9136-9166ms` | `<4s` | Users feel this on every bad foreground return |
| **2** | Discover budget starvation before inbox fallback | `2058ms` path vs `106ms` inbox write | `<1s` total path | Offline peer sends feel slow for avoidable reasons |
| **3** | Group discovery settle wait | `5255ms` total, `~255ms` real work | `2-3s` | First usable group delivery after join is late |
| **4** | Group multi-member publish | `1239ms` | `<500-700ms` | Group sends to more than one member still feel heavy |
| **5** | Group key rotation under traffic | `1209ms` | Keep under control | Important as groups get larger |
| **6** | Relay probe benchmark quality | current rerun did not hit probe path | clean reproduced measurement | Need truth before we optimize or claim a bug |
| **7** | Cold first-message e2e | `806ms` | Acceptable already | Lower urgency than recovery paths |

---

## Main Product Insight

The app is already fast when it is healthy and connected.

- Warm 1:1 send is excellent
- Connection reuse is excellent
- Startup is good
- Low-level group publish is fast
- Low-level media upload is acceptable

The app is slow mainly when it is **recovering** or **switching state**.

- Background resume with degraded relay is slow
- Reconnect after restart is slow
- Offline-peer send burns time before inbox fallback
- Group join/discovery spends too long waiting before real work starts

So the main performance story is simple:

**steady-state is good, transition paths are the problem.**

That should stay the main optimization focus.

---

## What This Means for Testing

The smoke strategy is still correct.

**Do not solve this by adding a huge new smoke suite.**

The numbers support the same test policy:

- Keep smoke small and stable for basic app health
- Use named regression gates for shared 1:1 send/upload/retry/recovery work
- Keep real transport and recovery tests in nightly or pre-release gates

This matters because a simple smoke can stay green while shared send-pipeline work breaks:

- media
- voice
- inbox recovery
- background resume
- relay recovery

That is exactly why the change-based regression gate in `03-smoke-test-strategy.md` is the right model.

---

## Reflection Summary

The current benchmark picture is clearer now than before.

- The app is not generally slow
- The app is slow in recovery paths
- Notification, background resume, timeout accuracy, and media are now measured, not guessed
- The highest-value work is still relay recovery and wasted timeout budget before fallback
- Group discovery remains an easy constant-level win
- Relay probe now needs a clean reproduced benchmark before stronger claims

That is the practical reading of the current data.
