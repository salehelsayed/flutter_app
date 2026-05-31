# Device-Run Schedule — NET-REL-01 I3 + NET-REL-05 E2

Prepared 2026-05-31. Monitor-authored handoff for the device-equipped executor session.

## Confirmations (locked)
- **Devices:** Pixel (E2); iPhone + Pixel on the **same WiFi** (I3) — connected.
- **Executor:** device-equipped session runs these.
- **I3 mode:** AUTOMATED — resolve the iPhone "Preparing" CoreDevice state first (§2 gate).
- **Build:** both runs from `121-improvements` (contains NET-REL-01 code + the E2 per-id
  tag `e7f9d1b5`). Verify the build under test includes both before running.

## ⚠️ Reality correction (2026-05-31 — supersedes the Run statuses below)
A headless executor verified the harness against this schedule and found the runbook
scenarios were a **spec, not implemented code**:
- **E2 is NOT runnable as-is.** `transport_e2e_test.dart` implements only A1–A6/B1–B6/D3/E1–E6/G2
  (encryption / inbox / dedup / liveness). The E2-A/E2-B/NC-1/NC-2 scenarios — and the
  low-confidence concurrent-fallback path the `e7f9d1b5` id-tag instruments — **do not exist
  in the harness** (grep for `median|p95|CONCURRENT_INBOX_BEGIN|lowConfidence|custody` = 0).
  → **Headless prerequisite:** BUILD E2-A/E2-B/NC-1/NC-2 into the harness first, THEN a human
  runs it on Pixel + testpeer (autoConfirmDirectAck on). E2 below is BLOCKED until that lands.
- **I3 is human-only.** There is no automated discovery-ON 1:1 two-device harness; the proof
  needs a person at both phones (contact pairing via QR, granting the iOS Local Network prompt,
  reading the kDebugMode Transport Diagnostics card, physically blocking LAN for the negative
  control) + manual iPhone CoreDevice "Preparing" resolution. The "automated" framing below is
  wrong; even the documented fallback still needs a human at the iPhone.

## Order & rationale
1. **Run 1 — E2** (ready now; reuses the proven Pixel + host test-peer config from the census).
2. **Gate — resolve iPhone "Preparing"** (precondition for automated I3).
3. **Run 2 — I3** (automated, iPhone ↔ Pixel, same WiFi).

E2 first because it has zero new setup; I3 waits on the iPhone-prep gate.

---

## Run 1 — E2 (NET-REL-05 concurrent fallback + offline sizing) — READY
Runbook (authoritative steps/commands): `Test-Flight-Improv/NET-REL-05-E2-concurrent-fallback-device-runbook.md`
- **Resources:** Pixel + host Go CLI test-peer (`go-mknoon/bin/testpeer`) + real relay (`MKNOON_RELAY_ADDRESSES`).
- **Prereqs (do not skip):** build the testpeer; **enable `autoConfirmDirectAck` on the peer**
  (without it the direct-confirm times out → false 100%-inbox); drive via `run_transport_e2e.dart`.
- **Scenarios (corrected pairs):**
  - E2-A live-wins = `CONCURRENT_INBOX_BEGIN(id)` + `SUCCESS(id, via≠inbox)`
  - E2-A inbox-saves = `CONCURRENT_INBOX_BEGIN(id)` + `CONCURRENT_INBOX_CUSTODY(id)`
  - E2-B offline = send→custody **median/p95** (this sizes the NET-REL-05 offline tail)
  - NC-1 high-confidence → 0 inbox; NC-2 two ids → two messages
- **N:** ≥30 (per-id correlation).
- **PASS:** per-id correlation holds (the `e7f9d1b5` tag makes this decisive); offline-tail sized; both negative controls hold.
- **Capture:** fill the runbook's results template.

## 2. GATE — resolve iPhone "Preparing iPhone" (CoreDevice) for automation
This is the chosen precondition for automated I3. "Preparing iPhone for development / debugger
support" means CoreDevice is downloading the developer disk image; automated repeated
`flutter test` launches fail until it's fully ready. Resolution checklist:
1. **Let it finish.** Keep the iPhone **unlocked**, connected by **cable** (not WiFi-only), stable
   USB. First-time prep can take 10-30+ min — don't launch mid-prep.
2. **Developer Mode ON** (Settings → Privacy & Security → Developer Mode) and device **trusted**.
3. **Watch progress in Xcode → Window → Devices and Simulators** — wait until it shows
   **Connected / ready** (no "Preparing…" banner).
4. **Version match + space:** Xcode up to date for the iPhone's iOS version; enough Mac disk.
5. **Check state from CLI:** `xcrun devicectl list devices` then
   `xcrun devicectl device info details --device <UDID>` — should report ready.
6. **If stuck:** unplug/replug → restart iPhone → restart Mac; if still stuck, re-pair the device
   and clear DerivedData.
7. **Readiness proof (REQUIRED before automating):** one clean `flutter run -d <iphone-id> --debug`
   that installs + launches without the "Preparing" stall. Only after that succeeds is automated
   `flutter test`/`flutter drive` reliable.

**Fast fallback if prep can't be cleared:** run I3 as **Pixel-automated-sender + iPhone-manual-launch-receiver**
— I3's assertion is on the *receiver's* stored transport, so a hand-launched iPhone receiver avoids
iPhone automation entirely. (Not your chosen path, but it unblocks I3 without the CoreDevice fix.)

## Run 2 — I3 (NET-REL-01 LAN pinning) — after the gate
Runbook (authoritative steps/commands): `Test-Flight-Improv/NET-REL-01-I3-lan-pinning-device-runbook.md`
- **Resources:** iPhone + Pixel on the **same WiFi** (LAN path is cross-platform: Bonjour iOS / NSD Android).
- **Build flags:** debug, **discovery ON** (`DISABLE_LOCAL_DISCOVERY` NOT set), iOS **Local Network permission ALLOWED**.
- **Happy:** receiver stored `transport == 'local'` (**path-pinned — never the {direct,relay,inbox} set**) + census `wifi` count moved.
- **Negative control:** block the LAN path (one device on cellular, or firewall the WS port) with relay reachable → `transport != 'local'`.
- **N:** ≥20.
- **PASS:** `local` on happy; `!= local` on the negative control.

---

## Doctrine (both runs)
Per `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`: **path-pin the transport,
run the negative control, never accept the {direct,relay,inbox} set** for a path-specific claim.

## Post-run
- Update `00-INDEX.md` rows: NET-REL-01 and NET-REL-05 → **validated** (from "code-complete, host-green / device-pending").
- E2-B's offline median/p95 is the number that finally **sizes** the NET-REL-05 offline-tail win (don't claim it until this lands).
