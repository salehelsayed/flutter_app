# Transport Census — Operator Runbook

> **STATUS (2026-05-30): REWORKED for two physical devices; device-validation pending.** Compiles
> (`flutter analyze` clean on the harness). The architecture now solves the 3 walls that blocked the prior
> scaffold:
> 1. **Fresh identity per run on BOTH devices** — generated in-harness and saved to a FRESH per-role test DB
>    (`E2E_DB_NAME`). The `flutter test` post-run uninstall therefore wipes nothing we depend on (the prior
>    design reused the device's onboarded `identity.db`; uninstall killed it).
> 2. **One-direction stdout→dart-define exchange** — the RECEIVER prints its fresh identity to stdout; the
>    orchestrator (on the host) captures that line and passes it to the SENDER via
>    `--dart-define=CENSUS_PEER_JSON`. No `/tmp` files on-device, no `adb`/`devicectl` push, no
>    `PathAccessException`.
> 3. **No contacts/onboarding precondition** — transport-level delivery/ack is a Go-node concern, so the
>    RECEIVER does NOT need the SENDER as a contact for the sender's census to be correct. Only the SENDER adds
>    the receiver (the freshly-announced identity) as a contact at runtime, with the freshly-generated ML-KEM
>    pubkey, so the regenerate-on-restart problem is moot.
>
> Both devices run the SAME harness, selected by `CENSUS_ROLE` (sender|receiver). The output is gate-quality
> only after the device smoke run validates it; NET-REL-02/03 stay gated until then.

A real-device, **SENDER-vantage** transport census over N≥50 real 1:1 sends,
per condition, with optional cold-send. It measures, from the sender's own
metrics, **which transport leg actually carried each send** (direct vs relay vs
wifi/LAN vs inbox), plus the fallback-rung distribution, per-leg
attempt/failure counts, and per-transport latency.

## Architecture (two devices run the harness; fresh identity per run)

- **Both** devices run the SAME harness, selected by `CENSUS_ROLE`
  (`sender` | `receiver`). The orchestrator launches the RECEIVER in the
  background on one device and the SENDER in the foreground on the other.
- Each role generates a **FRESH identity in-harness** and saves it to a **fresh
  per-role test DB** (`E2E_DB_NAME` = `census_receiver.db` / `census_sender.db`).
  Nothing depends on persisted onboarding, so the `flutter test` post-run
  uninstall can wipe the app freely.
- The **RECEIVER auto-announces its identity** on stdout:
  `CENSUS_PEER_IDENTITY={"peerId":...,"publicKey":...,"mlKemPublicKey":...,"rendezvous":...}`.
  The orchestrator captures that line and injects it into the SENDER via
  `--dart-define=CENSUS_PEER_JSON`. The SENDER adds the receiver as a **contact**
  at runtime (with the freshly-announced ML-KEM pubkey) and sends N real 1:1
  messages, dumping the SENDER-vantage census to STDOUT.
- There is **no cross-device filesystem coordination** — the only channel is
  the receiver's single stdout line, read on the host. This is what makes it
  work on sandboxed physical devices (the previous host-`/tmp` design failed
  with `PathAccessException ... Permission denied`).

### Precondition (none for identity/contacts)

There is **no onboarding or contacts precondition**. The harness generates a
fresh identity on each device per run and the sender adds the receiver as a
contact at runtime. You only need both devices visible in `flutter devices`,
on the network condition you intend to test, and (iOS) with Local Network
permission allowed.

---

## Files

- Harness: `integration_test/transport_census_harness.dart`
- Launcher: `scripts/run_transport_census.sh`
- This runbook: `Test-Flight-Improv/transport-census-RUNBOOK.md`

The harness opens a **fresh per-role test DB** at **version 44** with the full
migration list, mirrored from `integration_test/transport_e2e_test.dart`. If
that e2e file's migration list changes, mirror it in the harness's
`_openTestDatabase` (and bump `_kTestDbVersion`).

---

## Device IDs

| Role label | Device  | Device ID |
|------------|---------|-----------|
| iPhone13   | iOS     | `00008110-00184D622289801E` |
| Pixel6     | Android | `21071FDF600CSC` |

The launcher auto-detects platform **per device** from each device ID: a
CoreDevice UUID (`8hex-16hex`) or classic UDID → **iOS**
(`flutter drive --publish-port`); anything else → **Android**
(`flutter test`). The sender and receiver devices are dispatched
independently, so a mixed iOS-sender / Android-receiver run works.

You may supply a relay address set via `--relay <csv>` or
`export MKNOON_RELAY_ADDRESSES=...` before running. If omitted, the app's bridge
uses its built-in default relay.

---

## Condition A_cold — both devices on the SAME Wi-Fi, cold sends

Purpose: with both phones on the same LAN, see how often a **cold** send (warm
connection torn down first) lands on direct vs relay vs wifi/LAN.

1. Put **both** phones on the **same Wi-Fi** network.
2. On iOS, when first launched, **allow the Local Network permission** prompt
   (required for LAN/Bonjour discovery). If you tapped "Don't Allow" earlier,
   fix it in Settings → the app → Local Network → ON, then relaunch.
3. Run (iPhone13 sends; Pixel6 receives — both run the harness):

```bash
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app
export MKNOON_RELAY_ADDRESSES='<your-relay-csv>'   # optional
scripts/run_transport_census.sh \
  --condition A_cold --n 50 --cold true \
  --sender-device 00008110-00184D622289801E \
  --receiver-device 21071FDF600CSC
```

The orchestrator launches the receiver first (background), waits for its
`CENSUS_PEER_IDENTITY=` line, then launches the sender (foreground). When the
sender finishes it prints the `===CENSUS_BEGIN===...===CENSUS_END===` block
(also in `/tmp/transport_census_<run-id>/sender.log`; receiver output is in
`receiver.log`).

To reverse direction, swap `--sender-device` and `--receiver-device`.

---

## Condition B_cross — devices on DIFFERENT networks (one on cellular)

Purpose: with the two phones genuinely **off the same LAN**, the LAN/direct path
should be unavailable, so the census should shift toward relay (and inbox when a
peer is briefly offline). This is the cross-network reachability census.

The operator MUST physically separate the networks:
1. On **one** phone: **toggle Wi-Fi OFF** and **confirm Cellular Data is ON**
   (and that it actually has signal / a working data plan). Open a browser and
   load a page over cellular to confirm before starting.
2. Leave the **other** phone on Wi-Fi (or a different Wi-Fi).
3. **Verify they are genuinely on different networks** — they must NOT share the
   same LAN subnet. If both are on the same router (even "guest" vs "main" on
   the same AP can sometimes bridge), the test is invalid.

```bash
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app
export MKNOON_RELAY_ADDRESSES='<your-relay-csv>'   # optional
scripts/run_transport_census.sh \
  --condition B_cross --n 50 --cold true \
  --sender-device 00008110-00184D622289801E \
  --receiver-device 21071FDF600CSC
```

(Cold vs warm is independent of the network condition; keep `--cold true` for an
apples-to-apples comparison with A_cold, or run `--cold false` separately.)

---

## The count-at-SENDER invariant (read this before trusting any number)

**The census is read from the SENDER only.** The gate number is the sender's
own `TransportMetrics`, printed in the `SENDER-VANTAGE (authoritative)` block.
The receiver also runs the harness and prints a
`RECEIVER-VANTAGE (cross-check only)` block — **do NOT pool it into the mix**.
The receiver relabels a LAN/`wifi` delivery as `direct` on its own vantage, so
combining the two would double-count and corrupt the mix. The receiver block is
diagnostic only; read the transport census exclusively from the SENDER's
`===CENSUS_BEGIN===` block (the orchestrator already filters the sender log).

---

## Validity checklist (a run is only gate-quality if ALL hold)

- [ ] **Debug build** (the harness runs via `flutter test` / `flutter drive`,
      i.e. a debug/profile Runner — that is expected).
- [ ] **Discovery ON** — do **NOT** pass `DISABLE_LOCAL_DISCOVERY`. LAN
      discovery must be live or the `wifi`/LAN bucket is structurally zero.
- [ ] **iOS Local Network permission ALLOWED** on the iPhone (see A_cold step 2).
- [ ] **Both devices ran the harness** — confirm the receiver printed its
      `CENSUS_PEER_IDENTITY=` line (orchestrator echoes the captured JSON) and
      stayed up for the whole sender run.
- [ ] **No onboarding/contacts precondition** — fresh identity per run; the
      sender adds the receiver as a contact at runtime. (Nothing to set up.)
- [ ] **N ≥ 50** (`--n 50` or higher).
- [ ] **1:1 only** — exactly one sender, one receiver, no group traffic.
- [ ] **Single condition per run** — A_cold and B_cross are separate runs;
      never interleave.
- [ ] Sender `totalTransportSamples` ≈ N (a large shortfall means sends failed —
      inspect the log and `attemptFailureCounts`).

---

## Cold-send caveat (what `--cold true` does and does NOT measure)

`--cold true` calls `peer:disconnect` (`callP2PPeerDisconnect`) before each send,
then settles ~300ms, defeating the **connection-reuse** fast path
(`send_chat_message_use_case.dart:365`,
`isAlreadyConnected = currentState.connections.any(...)`). That forces the send
to re-establish a connection each time.

**But disconnect does NOT flush the libp2p peerstore** — the peer's addresses
stay **cached**. So cold-send measures **direct-vs-relay availability GIVEN known
addresses**, i.e. "given we already know where the peer is, how often can we get
a fresh direct connection vs falling back to relay". It does **NOT** measure
**from-scratch discovery cost** (rendezvous/DHT lookup of an unknown peer). Treat
the cold census as a *re-dial availability* census, not a *cold-discovery*
census.

---

## iOS gotchas

- **"Device is busy (Preparing iPhone…)"** on launch → the launch can hang.
  **Reboot the iPhone** to recover CoreDevice, then re-run.
- **First cold launch may stop once in LLDB on `EXC_BAD_ACCESS`** → this is a
  known first-launch flake. **Relaunch** (re-run the launcher); the second
  launch typically proceeds.
- If `flutter drive` cannot find the device, confirm it is unlocked, trusted,
  and visible in `flutter devices`.

---

## Reading the output

The sender prints (between `===CENSUS_BEGIN===` and `===CENSUS_END===`):

- `condition`, `N`, `cold`, relay addrs, sender username, target peerId
  (truncated), and sends delivered/failed (recorded context).
- `totalTransportSamples` — total recorded sends from the sender.
- `transportMix` — counts per `{direct, relay, wifi, inbox, unknown}`. **This is
  the headline census.**
- `rungDistribution` — which fallback rung delivered each send
  (`reuse, local_race, direct_race, relay_probe, inbox_fallback, failed`).
- `attemptCounts` / `attemptFailureCounts` / `attemptDelivered` — per-leg
  (`reuse, local, direct, relay_probe, inbox`) tried / failed / (tried−failed).
  These disambiguate a low `direct` share: "direct never tried" vs "direct tried
  and failed often".
- `holePunch` attempt/success/fail + `relayToDirectUpgrades`.
- `latencyByTransport` — median / p95 / n per transport.
- `baselineReport` — the human-readable one-screen summary.
